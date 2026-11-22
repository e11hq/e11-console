import UIKit
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
    guard let k = FileKeys.get(id) else { return }
    if k.hasPrefix("p:") { openPieces(at: url, key: String(k.dropFirst(2))); return }
    guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), let p = open(d, key: k) else { return }
    try? p.write(to: url, options: .atomic)
  }

  /* A big file locked in pieces (Haris 2026-11-21 11:00): every 8 MB of the locked file is one piece — 12 bytes of nonce, the
     piece, 16 bytes of tag — each locked on its own with "e11p:<n>:<1 if last else 0>" added, so pieces can't be moved,
     dropped or cut short. Locked and unlocked one piece at a time: a 1 GB video never sits whole in the phone's memory. */
  static let piece = 8 * 1024 * 1024
  static let piecePlain = piece - 28
  static func pieces(_ plain: Int) -> Int { max(1, (plain + piecePlain - 1) / piecePlain) }
  static func sealPiece(_ d: Data, key: SymmetricKey, index: Int, last: Bool) -> Data? {
    let aad = Data("e11p:\(index):\(last ? 1 : 0)".utf8)
    return (try? AES.GCM.seal(d, using: key, authenticating: aad))?.combined
  }
  // unlocked into a new file beside it, piece by piece, then put in its place (left as it is if a piece doesn't open)
  static func openPieces(at url: URL, key: String) {
    guard let kd = Data(base64Encoded: key), kd.count == 32, let h = try? FileHandle(forReadingFrom: url) else { return }
    defer { try? h.close() }
    let k = SymmetricKey(data: kd)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    let n = (size + piece - 1) / piece
    guard n > 0 else { return }
    let out = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".open")
    FileManager.default.createFile(atPath: out.path, contents: nil)
    guard let w = try? FileHandle(forWritingTo: out) else { return }
    var ok = true
    for i in 0..<n {
      let opened: Data? = autoreleasepool {
        guard let c = try? h.read(upToCount: piece), c.count > 28, let box = try? AES.GCM.SealedBox(combined: c) else { return nil }
        return try? AES.GCM.open(box, using: k, authenticating: Data("e11p:\(i):\(i == n - 1 ? 1 : 0)".utf8))
      }
      guard let p = opened else { ok = false; break }
      do { try w.write(contentsOf: p) } catch { ok = false; break }
    }
    try? w.close()
    if ok { _ = try? FileManager.default.replaceItemAt(url, withItemAt: out) } else { try? FileManager.default.removeItem(at: out) }
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
  // an upload given up on this phone (the send screen closed, a photo taken out, HD switched, ✕ on its bubble): the server
  //  lets it go at once — never one already in a message (Haris 2026-11-22 16:02)
  func dropUpload(_ id: String?) { if let id = id { post("/api/talk/r2/drop", ["id": id]) } }
  // (the server's answer to a message sent with its file's "it's all there" — taken once by the sender)
  private static var sentWith: [String: [String: Any]] = [:]
  private static let sentLock = NSLock()
  static func keepSent(_ id: String, _ j: [String: Any]) { sentLock.lock(); sentWith[id] = j; sentLock.unlock() }
  static func takeSent(_ id: String) -> [String: Any]? { sentLock.lock(); defer { sentLock.unlock() }; return sentWith.removeValue(forKey: id) }
  /* a message's file: locked, then to R2 — under 8 MB in one go, else in 8 MB parts three side by side; the ring moves as the
     bytes go out but holds at 90% until Cloudflare says they've arrived — never "full" while bytes are still on their way
     (Haris 2026-11-22 17:56; 17:32's "only on Cloudflare's word" left small files' rings still). done: the file's id and its key — or, if the server has no R2, the usual way (no key). */
  // (keep: a group's picture — kept in R2 while the group uses it, not under messages' 31-day rule)
  // (back: a file asked for by the group, sent again under its own id — Ask the group, Haris 2026-11-20 21:36; nothing else
  //  happens if it's back already or another phone is sending it)
  // (stop: the sending bubble's id — its ✕ cancels what's going up, Uploads.stop)
  // (message: the message to send with "it's all there", in the same call — the server sends it and gives its answer as
  //  "sent", kept for the sender in sentWith; one trip instead of two, Haris 2026-11-22 11:26)
  func uploadMsg(_ data: Data, name: String, keep: Bool = false, back: String? = nil, stop: String? = nil, one: Bool = false, message: ((String, String) -> [String: Any])? = nil, gate: ((@escaping () -> Void) -> Void)? = nil, onId: ((String) -> Void)? = nil, progress: @escaping (Double) -> Void, done: @escaping (String?, String?) -> Void) {
    // (gate: "it's all there" held until it's opened — a photo sent up while still on the send screen, PreUpload)
    // (over 200 MB: locked in pieces, one at a time as they go up — its key given back as "p:<key>"; Haris 2026-11-21 11:00)
    if data.count > 200 * 1024 * 1024 { return uploadPieces(data, name: name, back: back, stop: stop, progress: progress, done: done) }
    guard let sealed = FileLock.seal(data) else { return back != nil ? done(nil, nil) : upload(data, name: name, progress: progress) { done($0, nil) } }
    // (a voice note: its locked bytes and its message in one call to the hub — one trip instead of three, Haris 2026-11-22
    //  19:06; the hub puts it in R2 and gives the file its id in the message. Anything wrong: the usual way below)
    if one, back == nil, !keep, gate == nil, let mk = message, sealed.data.count <= 1024 * 1024, Relay.handles("/api/talk/r2/one") {
      post("/api/talk/r2/one", ["name": name, "data": sealed.data.base64EncodedString(), "send": mk("", sealed.key)]) { [weak self] j in
        if Uploads.isStopped(stop) { return done(nil, nil) }
        if let j = j, (j["ok"] as? Bool) == true, let id = j["id"] as? String {
          if let s = j["sent"] as? [String: Any] { Net.keepSent(id, s) }
          progress(1); return done(id, sealed.key)
        }
        guard let self = self else { return done(nil, nil) }
        self.uploadMsg(data, name: name, keep: keep, back: back, stop: stop, message: message, gate: gate, onId: onId, progress: progress, done: done)
      }
      return
    }
    let start: (String, [String: Any]) = back.map { ("/api/talk/resend/start", ["file": $0, "size": sealed.data.count] as [String: Any]) } ?? ("/api/talk/r2/start", ["name": name, "size": sealed.data.count, "keep": keep] as [String: Any])
    post(start.0, start.1) { [weak self] j in
      guard let self = self else { return done(nil, nil) }
      if back != nil, (j?["here"] as? Bool) == true || (j?["taken"] as? Bool) == true { return done(back, nil) }
      guard let j = j, (j["ok"] as? Bool) == true, let id = j["id"] as? String else {
        if back != nil { return done(nil, nil) }
        // (no R2 on this server, or it couldn't start: the usual way)
        return self.upload(data, name: name, progress: progress) { done($0, nil) }
      }
      onId?(id)   // (its id on the server — to let it go at once if it's given up)
      let body = sealed.data, total = Double(max(1, body.count))
      let finish = { (etags: [String]?) in
        guard let etags = etags else { return done(nil, nil) }
        var b: [String: Any] = ["id": id, "etags": etags]
        if back != nil { b["back"] = true; b["key"] = sealed.key }
        else if gate == nil, let mk = message { b["send"] = mk(id, sealed.key) }
        let say = {
          var b = b
          if back == nil, gate != nil, let mk = message { let m = mk(id, sealed.key); if !m.isEmpty { b["send"] = m } }   // (the message as it is at Send)
          let bg = UIApplication.shared.beginBackgroundTask(withName: "talk-r2-done") {}
          self.post("/api/talk/r2/done", b) { d in
            defer { DispatchQueue.main.asyncAfter(deadline: .now() + 20) { UIApplication.shared.endBackgroundTask(bg) } }
            guard (d?["ok"] as? Bool) == true else { return done(nil, nil) }
            if let s = d?["sent"] as? [String: Any] { Net.keepSent(id, s) }
            progress(1); done(id, sealed.key)
          }
        }
        if let g = gate { g(say) } else { say() }
      }
      if Uploads.isStopped(stop) { return done(nil, nil) }
      if let put = (j["put"] as? String).flatMap(URL.init(string:)) {
        self.putR2(put, body, stop: stop) { p in progress(0.9 * Double(p) / total) } done: { e in finish(e.map { [$0] }) }
        return
      }
      guard let urls = (j["urls"] as? [String])?.compactMap(URL.init(string:)), let part = j["part"] as? Int, part > 0, !urls.isEmpty else { return done(nil, nil) }
      var etags = [String?](repeating: nil, count: urls.count), sent = [Int](repeating: 0, count: urls.count)
      // (a part on its way counts 90% of what's gone out; a part Cloudflare has said arrived counts whole)
      func ring() -> Double { min(0.99, (0..<sent.count).reduce(0.0) { $0 + (etags[$1] != nil ? Double(sent[$1]) : 0.9 * Double(sent[$1])) } / total) }
      var next = 0, going = 0, over = false
      // (Talk left: every part still to go handed to iPhone at once, so they all go on with Talk closed — Haris 2026-11-21)
      let fill = UUID()
      func end() { over = true; BgUploads.shared.fillers[fill] = nil }
      func pump() {
        guard !over else { return }
        if Uploads.isStopped(stop) { end(); return done(nil, nil) }
        if next >= urls.count && going == 0 { end(); return finish(etags.contains(where: { $0 == nil }) ? nil : etags.map { $0! }) }
        while going < BgUploads.width && next < urls.count {
          let i = next; next += 1; going += 1
          let piece = body.subdata(in: (i * part)..<min(body.count, (i + 1) * part))
          self.putR2(urls[i], piece, stop: stop) { p in
            sent[i] = Int(p); progress(ring())
          } done: { e in
            going -= 1
            guard !over else { return }   // (already ended — another part failed, or ✕: said once)
            guard let e = e else { end(); return done(nil, nil) }
            etags[i] = e; sent[i] = piece.count; progress(ring()); pump()
          }
        }
      }
      BgUploads.shared.fillers[fill] = { pump() }
      pump()
    }
  }
  // a big file in pieces: each 8 MB part of R2's upload is one piece, locked just before it goes (three at a time)
  private func uploadPieces(_ data: Data, name: String, back: String? = nil, stop: String? = nil, progress: @escaping (Double) -> Void, done: @escaping (String?, String?) -> Void) {
    let key = SymmetricKey(size: .bits256), keyText = key.withUnsafeBytes { Data($0) }.base64EncodedString()
    let n = FileLock.pieces(data.count), sealedSize = data.count + 28 * n
    let start: (String, [String: Any]) = back.map { ("/api/talk/resend/start", ["file": $0, "size": sealedSize] as [String: Any]) } ?? ("/api/talk/r2/start", ["name": name, "size": sealedSize] as [String: Any])
    post(start.0, start.1) { [weak self] j in
      guard let self = self else { return done(nil, nil) }
      if back != nil, (j?["here"] as? Bool) == true || (j?["taken"] as? Bool) == true { return done(back, nil) }
      guard let j = j, (j["ok"] as? Bool) == true, let id = j["id"] as? String,
            let urls = (j["urls"] as? [String])?.compactMap(URL.init(string:)), (j["part"] as? Int) == FileLock.piece, urls.count == n else {
        // (no R2 on this server, or not in the pieces we lock: the usual way)
        if back != nil { return done(nil, nil) }
        return self.upload(data, name: name, progress: progress) { done($0, nil) }
      }
      let total = Double(max(1, sealedSize))
      var etags = [String?](repeating: nil, count: n), sent = [Int](repeating: 0, count: n)
      // (a part on its way counts 90% of what's gone out; a part Cloudflare has said arrived counts whole)
      func ring() -> Double { min(0.99, (0..<sent.count).reduce(0.0) { $0 + (etags[$1] != nil ? Double(sent[$1]) : 0.9 * Double(sent[$1])) } / total) }
      var next = 0, going = 0, over = false
      // (Talk left: every part still to go handed to iPhone at once, so they all go on with Talk closed — Haris 2026-11-21)
      let fill = UUID()
      func end() { over = true; BgUploads.shared.fillers[fill] = nil }
      func pump() {
        guard !over else { return }
        if Uploads.isStopped(stop) { end(); return done(nil, nil) }
        if next >= n && going == 0 {
          end()
          guard !etags.contains(where: { $0 == nil }) else { return done(nil, nil) }
          var b: [String: Any] = ["id": id, "etags": etags.map { $0! }]
          if back != nil { b["back"] = true; b["key"] = keyText; b["lock"] = "p" }
          let bg = UIApplication.shared.beginBackgroundTask(withName: "talk-r2-done") {}
          self.post("/api/talk/r2/done", b) { d in
            defer { DispatchQueue.main.asyncAfter(deadline: .now() + 20) { UIApplication.shared.endBackgroundTask(bg) } }
            guard (d?["ok"] as? Bool) == true else { return done(nil, nil) }
            progress(1); done(id, "p:" + keyText)
          }
          return
        }
        while going < BgUploads.width && next < n {
          let i = next; next += 1; going += 1
          let lo = i * FileLock.piecePlain, hi = min(data.count, lo + FileLock.piecePlain)
          guard let piece = autoreleasepool(invoking: { FileLock.sealPiece(data.subdata(in: lo..<hi), key: key, index: i, last: i == n - 1) }) else { end(); return done(nil, nil) }
          self.putR2(urls[i], piece, stop: stop) { p in
            sent[i] = Int(p); progress(ring())
          } done: { e in
            going -= 1
            guard !over else { return }   // (already ended — another part failed, or ✕: said once)
            guard let e = e else { end(); return done(nil, nil) }
            etags[i] = e; sent[i] = piece.count; progress(ring()); pump()
          }
        }
      }
      BgUploads.shared.fillers[fill] = { pump() }
      pump()
    }
  }
  // one piece to R2's address (its ETag back, on the main thread; nil: it didn't go)
  private func putR2(_ url: URL, _ data: Data, stop: String? = nil, sent: @escaping (Int64) -> Void, done: @escaping (String?) -> Void) {
    BgUploads.shared.put(url, data, stop: stop, sent: sent, done: done)
  }
  static let r2Session: URLSession = {
    let c = URLSessionConfiguration.default
    c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.timeoutIntervalForRequest = 120
    return URLSession(configuration: c)
  }()
}

/* Uploads that go on with Talk closed (Haris 2026-11-21 13:24 "plan it", 15:18 "Start": claude/talk-background-uploads-plan.md).
   Every part going to R2 is handed to iPhone's own background transfers: written to a file, sent by iPhone itself — in
   another app, with the phone locked — and Talk woken when it's done, to send the next parts, then "done" and the message.
   While Talk is open, three parts at a time; once Talk is left, every part still to go is handed over at once. Swiping
   Talk away in the app switcher stops them (iPhone's rule): the red ! when Talk opens, Send again. */
final class BgUploads: NSObject, URLSessionDataDelegate {
  static let shared = BgUploads()
  // (three at a time while Talk is open; all the rest once it's left)
  static var width: Int { UIApplication.shared.applicationState == .background ? 1000 : 3 }
  var fillers: [UUID: () -> Void] = [:]
  // (keyed by the session and the task's number — the two sessions number their tasks each from 1)
  private var waiting: [String: (sent: (Int64) -> Void, done: (String?) -> Void, file: URL)] = [:]
  // (while Talk is open: Talk's own connection — it says "done" at once; iPhone's background transfers told Talk a few seconds
  //  late, and the message waited for it: Haris 2026-11-22 15:38. Talk left mid-way: those parts handed to iPhone's)
  private var open: [Int: (url: URL, file: URL, stop: String?, task: URLSessionTask)] = [:]
  private lazy var fg: URLSession = {
    let c = URLSessionConfiguration.default
    c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.timeoutIntervalForRequest = 120
    return URLSession(configuration: c, delegate: self, delegateQueue: .main)
  }()
  private func key(_ s: URLSession, _ t: URLSessionTask) -> String { (s === fg ? "f" : "b") + String(t.taskIdentifier) }
  private var wake: (() -> Void)?
  private lazy var session: URLSession = {
    let c = URLSessionConfiguration.background(withIdentifier: "ae.e11.talk.uploads")
    c.isDiscretionary = false; c.sessionSendsLaunchEvents = true
    c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.timeoutIntervalForRequest = 120
    return URLSession(configuration: c, delegate: self, delegateQueue: .main)
  }()
  override init() {
    super.init()
    NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self else { return }
      // (parts going on Talk's own connection: stopped and handed to iPhone's, from the start of each part)
      let moving = self.open; self.open = [:]
      for (_, o) in moving {
        guard let w = self.waiting.removeValue(forKey: self.key(self.fg, o.task)) else { continue }
        o.task.cancel()
        var r = URLRequest(url: o.url); r.httpMethod = "PUT"
        let t = self.session.uploadTask(with: r, fromFile: o.file)
        self.waiting[self.key(self.session, t)] = w
        Uploads.add(t, to: o.stop)
        w.sent(0); t.resume()
      }
      self.fillers.values.forEach { $0() }
    }
  }
  func start() { _ = session }   // (at launch: reconnects to what iPhone was sending for us)
  func put(_ url: URL, _ data: Data, stop: String?, sent: @escaping (Int64) -> Void, done: @escaping (String?) -> Void) {
    guard Thread.isMainThread else { DispatchQueue.main.async { self.put(url, data, stop: stop, sent: sent, done: done) }; return }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("bgup-" + UUID().uuidString)
    guard (try? data.write(to: file)) != nil else { DispatchQueue.main.async { done(nil) }; return }
    var r = URLRequest(url: url); r.httpMethod = "PUT"
    let here = UIApplication.shared.applicationState != .background
    let s = here ? fg : session
    let t = s.uploadTask(with: r, fromFile: file)
    waiting[key(s, t)] = (sent, done, file)
    if here { open[t.taskIdentifier] = (url, file, stop, t) }
    Uploads.add(t, to: stop)
    t.resume()
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData _: Int64, totalBytesSent: Int64, totalBytesExpectedToSend _: Int64) {
    waiting[key(s, task)]?.sent(totalBytesSent)
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didFinishCollecting m: URLSessionTaskMetrics) { Diag.metrics("upload piece", m) }   // (the test page, for now)
  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if s === fg { open[task.taskIdentifier] = nil }
    guard let w = waiting.removeValue(forKey: key(s, task)) else { return }   // (from before Talk was closed, or handed over: nothing waits for it here)
    try? FileManager.default.removeItem(at: w.file)
    let h = task.response as? HTTPURLResponse
    w.done(error == nil && h?.statusCode == 200 ? (h?.value(forHTTPHeaderField: "ETag") ?? "") : nil)
  }
  // woken by iPhone with everything handed over done: told back once the next steps have had their moment
  func woken(_ f: @escaping () -> Void) { wake = f }
  func urlSessionDidFinishEvents(forBackgroundURLSession s: URLSession) {
    let f = wake; wake = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { f?() }
  }
}
