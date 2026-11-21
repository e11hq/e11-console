import Foundation
import CryptoKit

/* A message's photo, video, voice note or file straight to Cloudflare R2 and back (Haris 2026-11-20 17:52: "make it
   direct" — phone → Cloudflare → phone, the office line out of it). Locked here before it leaves the phone with a key of
   its own (AES-GCM, Apple's CryptoKit); the key goes only inside the message, so R2 only ever holds it locked. The server
   says who may: where to put it (/api/talk/r2/start, /done), and sends the group's phones to R2 for it (?r2=1). A server
   without R2: the usual way, as before. */
enum FileLock {
  // (Apple's "combined" form: 12 bytes of nonce, the file, 16 bytes of tag — the server reads the same form)
  static func seal(_ d: Data) -> (data: Data, key: String)? {
    let k = SymmetricKey(size: .bits256)
    guard let box = try? AES.GCM.seal(d, using: k), let c = box.combined else { return nil }
    return (c, k.withUnsafeBytes { Data($0) }.base64EncodedString())
  }
  static func open(_ d: Data, key: String) -> Data? {
    guard let kd = Data(base64Encoded: key), kd.count == 32, let box = try? AES.GCM.SealedBox(combined: d) else { return nil }
    return try? AES.GCM.open(box, using: SymmetricKey(data: kd))
  }
  // a downloaded file unlocked where it lies (one sent locked, its key known); anything else left as it is
  static func openInPlace(_ id: String, at url: URL) {
    guard let k = FileKeys.get(id), let d = try? Data(contentsOf: url, options: .mappedIfSafe), let p = open(d, key: k) else { return }
    try? p.write(to: url, options: .atomic)
  }
}

// the keys of messages' locked files, by file id — from the messages as they come, kept on the phone (its own folder)
enum FileKeys {
  private static let url = Net.filesDir.appendingPathComponent("keys.json")
  private static var all: [String: String] = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
  private static let q = DispatchQueue(label: "talk.filekeys")
  static func get(_ id: String) -> String? { q.sync { all[id] } }
  static func set(_ id: String, _ key: String) {
    q.sync {
      guard all[id] != key else { return }
      all[id] = key
      if let d = try? JSONEncoder().encode(all) { try? d.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
  }
}

// (a file's trip to R2: the server's sign-in never goes with it — a fresh request for R2's own address)
final class CleanRedirect: NSObject, URLSessionTaskDelegate {
  static let shared = CleanRedirect()
  func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest n: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(CleanRedirect.clean(n))
  }
  static func clean(_ n: URLRequest) -> URLRequest {
    guard let u = n.url, u.host != Server.host else { return n }
    var c = URLRequest(url: u); c.httpMethod = n.httpMethod ?? "GET"; c.timeoutInterval = n.timeoutInterval
    return c
  }
}

extension Net {
  /* a message's file: locked, then to R2 — under 8 MB in one go, else in 8 MB parts three side by side; the ring fills as
     they go. done: the file's id and its key — or, if the server has no R2, the usual way (no key). */
  // (keep: a group's picture — kept in R2 while the group uses it, not under messages' 31-day rule)
  func uploadMsg(_ data: Data, name: String, keep: Bool = false, progress: @escaping (Double) -> Void, done: @escaping (String?, String?) -> Void) {
    // (over 200 MB: the usual way for now — locking and unlocking hold the whole file in memory twice)
    guard data.count <= 200 * 1024 * 1024, let sealed = FileLock.seal(data) else { return upload(data, name: name, progress: progress) { done($0, nil) } }
    post("/api/talk/r2/start", ["name": name, "size": sealed.data.count, "keep": keep]) { [weak self] j in
      guard let self = self else { return done(nil, nil) }
      guard let j = j, (j["ok"] as? Bool) == true, let id = j["id"] as? String else {
        // (no R2 on this server, or it couldn't start: the usual way)
        return self.upload(data, name: name, progress: progress) { done($0, nil) }
      }
      let body = sealed.data, total = Double(max(1, body.count))
      let finish = { (etags: [String]?) in
        guard let etags = etags else { return done(nil, nil) }
        self.post("/api/talk/r2/done", ["id": id, "etags": etags]) { d in
          guard (d?["ok"] as? Bool) == true else { return done(nil, nil) }
          progress(1); done(id, sealed.key)
        }
      }
      if let put = (j["put"] as? String).flatMap(URL.init(string:)) {
        self.putR2(put, body) { p in progress(min(0.99, Double(p) / total)) } done: { e in finish(e.map { [$0] }) }
        return
      }
      guard let urls = (j["urls"] as? [String])?.compactMap(URL.init(string:)), let part = j["part"] as? Int, part > 0, !urls.isEmpty else { return done(nil, nil) }
      var etags = [String?](repeating: nil, count: urls.count), sent = [Int](repeating: 0, count: urls.count)
      var next = 0, going = 0, over = false
      func pump() {
        guard !over else { return }
        if next >= urls.count && going == 0 { over = true; return finish(etags.contains(where: { $0 == nil }) ? nil : etags.map { $0! }) }
        while going < 3 && next < urls.count {
          let i = next; next += 1; going += 1
          let piece = body.subdata(in: (i * part)..<min(body.count, (i + 1) * part))
          self.putR2(urls[i], piece) { p in
            sent[i] = Int(p); progress(min(0.99, Double(sent.reduce(0, +)) / total))
          } done: { e in
            going -= 1
            guard let e = e else { over = true; return done(nil, nil) }
            etags[i] = e; pump()
          }
        }
      }
      pump()
    }
  }
  // one piece to R2's address (its ETag back, on the main thread; nil: it didn't go)
  private func putR2(_ url: URL, _ data: Data, sent: @escaping (Int64) -> Void, done: @escaping (String?) -> Void) {
    var r = URLRequest(url: url); r.httpMethod = "PUT"; r.timeoutInterval = 120
    var watch: NSKeyValueObservation?
    let t = Net.r2Session.uploadTask(with: r, from: data) { _, resp, _ in
      let h = resp as? HTTPURLResponse
      let e = h?.statusCode == 200 ? (h?.value(forHTTPHeaderField: "ETag") ?? "") : nil
      DispatchQueue.main.async { watch?.invalidate(); watch = nil; done(e) }
    }
    watch = t.observe(\.countOfBytesSent) { t, _ in
      let n = t.countOfBytesSent; DispatchQueue.main.async { sent(n) }
    }
    t.resume()
  }
  static let r2Session: URLSession = {
    let c = URLSessionConfiguration.default
    c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.timeoutIntervalForRequest = 120
    return URLSession(configuration: c)
  }()
}
