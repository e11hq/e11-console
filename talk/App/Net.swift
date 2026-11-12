import UIKit
import Security

/* Talking to the server (server/src/talk.js — /api/talk/…). E11 Talk's own sign-in for now (Haris 2026-11-06: before
   the App Store it becomes shared with E11 Console): Cloudflare's email code in a web page once, then its sign-in cookie
   is kept in the Keychain and sent with every request. Built on the test server first (talk-test.e11hq.com). */
enum Server {
  static var url: String {
    if let s = UserDefaults.standard.string(forKey: "talk_server"), !s.isEmpty { return s }
    return Bundle.main.object(forInfoDictionaryKey: "TalkServerURL") as? String ?? "https://talk-test.e11hq.com"
  }
  static var host: String { URL(string: url)?.host ?? "" }
}

enum Keychain {
  static func set(_ v: String?, _ key: String) {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ae.e11.talk", kSecAttrAccount as String: key]
    SecItemDelete(q as CFDictionary)
    guard let v = v, let d = v.data(using: .utf8) else { return }
    var add = q; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
  }
  static func get(_ key: String) -> String? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ae.e11.talk", kSecAttrAccount as String: key,
                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }
}

final class Net {
  static let shared = Net()
  // the sign-in: the cookies Cloudflare set for the server (CF_Authorization …)
  var cookie: String? { didSet { Keychain.set(cookie, "cookie-" + Server.host) } }
  var onSignedOut: (() -> Void)?
  private let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.requestCachePolicy = .reloadIgnoringLocalCacheData
    c.timeoutIntervalForRequest = 30
    return URLSession(configuration: c)
  }()
  init() { cookie = Keychain.get("cookie-" + Server.host) }
  var signedIn: Bool { !(cookie ?? "").isEmpty }

  func request(_ path: String, method: String = "GET", json: [String: Any]? = nil, body: Data? = nil, type: String? = nil) -> URLRequest {
    var r = URLRequest(url: URL(string: Server.url + path)!)
    r.httpMethod = method
    if let c = cookie { r.setValue(c, forHTTPHeaderField: "Cookie") }
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    if let j = json { r.httpBody = try? JSONSerialization.data(withJSONObject: j); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let b = body { r.httpBody = b; r.setValue(type ?? "application/octet-stream", forHTTPHeaderField: "Content-Type") }
    return r
  }
  // a JSON answer on the main thread (nil: no answer — offline, or signed out: onSignedOut is told)
  func call(_ path: String, method: String = "GET", json: [String: Any]? = nil, body: Data? = nil, done: @escaping ([String: Any]?) -> Void) {
    session.dataTask(with: request(path, method: method, json: json, body: body)) { [weak self] d, resp, _ in
      let http = resp as? HTTPURLResponse
      let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
      // (Cloudflare's sign-in page instead of the answer, or "please sign in": signed out)
      let signedOut = http.map { $0.statusCode == 401 || ($0.statusCode == 403 && j == nil) || (($0.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/html")) } ?? false
      DispatchQueue.main.async {
        if signedOut { self?.onSignedOut?(); done(nil); return }
        done(j)
      }
    }.resume()
  }
  func get(_ path: String, _ done: @escaping ([String: Any]?) -> Void) { call(path, done: done) }
  func post(_ path: String, _ json: [String: Any], _ done: @escaping ([String: Any]?) -> Void = { _ in }) { call(path, method: "POST", json: json, done: done) }
  func act(_ b: [String: Any], _ done: @escaping ([String: Any]?) -> Void = { _ in }) { post("/api/talk/act", b, done) }

  // a file to send: in pieces of 4 MB, with its progress
  func upload(_ data: Data, name: String, progress: @escaping (Double) -> Void, done: @escaping (String?) -> Void) {
    let piece = 4 * 1024 * 1024
    func next(_ id: String?, _ offset: Int) {
      let end = min(data.count, offset + piece), last = end >= data.count
      var q = "/api/talk/upload?offset=\(offset)&name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "file")"
      if let id = id { q += "&id=\(id)" }
      if last { q += "&last=1" }
      session.dataTask(with: request(q, method: "POST", body: data.subdata(in: offset..<end))) { d, _, _ in
        let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        DispatchQueue.main.async {
          guard (j?["ok"] as? Bool) == true, let fid = j?["id"] as? String else { done(nil); return }
          progress(data.isEmpty ? 1 : Double(end) / Double(data.count))
          if last { done(fid) } else { next(fid, end) }
        }
      }.resume()
    }
    next(nil, 0)
  }

  // a file the phone still has but the server has let go: sent again under its own id (for a Mac being linked)
  func resend(_ id: String, name: String, done: @escaping (Bool) -> Void) {
    guard let data = try? Data(contentsOf: Net.local(id), options: .mappedIfSafe) else { done(false); return }
    let piece = 4 * 1024 * 1024
    func next(_ offset: Int) {
      let end = min(data.count, offset + piece), last = end >= data.count
      var q = "/api/talk/link/file?id=\(id)&offset=\(offset)&name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "file")"
      if last { q += "&last=1" }
      session.dataTask(with: request(q, method: "POST", body: data.subdata(in: offset..<end))) { d, _, _ in
        let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        DispatchQueue.main.async {
          guard (j?["ok"] as? Bool) == true else { done(false); return }
          if last || (j?["done"] as? Bool) == true { done(true) } else { next(end) }
        }
      }.resume()
    }
    next(0)
  }
  // a file of a message (or a picture): kept on the phone after the first time — the server lets it go once
  // everyone has it, so the phone's copy is the one that stays
  private let fileQ = DispatchQueue(label: "talk.files", attributes: .concurrent)
  static let filesDir: URL = {
    let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("talk-files", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    var v = URLResourceValues(); v.isExcludedFromBackup = false; var dd = d; try? dd.setResourceValues(v)
    return d
  }()
  static func stableKey(_ s: String) -> String {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return String(h, radix: 16)
  }
  static func local(_ id: String) -> URL { filesDir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_")) }
  func file(_ id: String, _ done: @escaping (URL?) -> Void) {
    let to = Net.local(id)
    if FileManager.default.fileExists(atPath: to.path) { done(to); return }
    session.downloadTask(with: request("/api/talk/file/" + id)) { tmp, resp, _ in
      guard let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else { DispatchQueue.main.async { done(nil) }; return }
      try? FileManager.default.removeItem(at: to)
      try? FileManager.default.moveItem(at: tmp, to: to)
      DispatchQueue.main.async { done(FileManager.default.fileExists(atPath: to.path) ? to : nil) }
    }.resume()
  }
  // a new message's file onto the phone before saying it arrived: true once it's here — or the server has none to give
  // (gone, refused); false only when it couldn't be reached, to be tried again
  func fetch(_ id: String, _ done: @escaping (Bool) -> Void) {
    let to = Net.local(id)
    if FileManager.default.fileExists(atPath: to.path) { done(true); return }
    session.downloadTask(with: request("/api/talk/file/" + id)) { tmp, resp, _ in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      if code == 200, let tmp = tmp { try? FileManager.default.removeItem(at: to); try? FileManager.default.moveItem(at: tmp, to: to) }
      DispatchQueue.main.async { done(code == 200 || (400..<500).contains(code)) }
    }.resume()
  }
  // E11 Console's pictures (people's photos, client logos) — the same server
  private let pics = NSCache<NSString, UIImage>()
  func picture(_ path: String?, _ done: @escaping (UIImage?) -> Void) {
    guard let p = path, !p.isEmpty else { done(nil); return }
    if let i = pics.object(forKey: p as NSString) { done(i); return }
    let disk = Net.filesDir.appendingPathComponent("pic-" + Net.stableKey(p))   // (a name that stays the same from one launch to the next)
    if let d = try? Data(contentsOf: disk), let i = UIImage(data: d) { pics.setObject(i, forKey: p as NSString); done(i); return }
    let path = p.hasPrefix("http") || p.hasPrefix("data:") ? p : "/__file/" + p.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
    if path.hasPrefix("data:"), let comma = path.firstIndex(of: ","), let d = Data(base64Encoded: String(path[path.index(after: comma)...])), let i = UIImage(data: d) {
      pics.setObject(i, forKey: p as NSString); done(i); return
    }
    var r = path.hasPrefix("http") ? URLRequest(url: URL(string: path)!) : request(path)
    if path.hasPrefix("http"), let c = cookie { r.setValue(c, forHTTPHeaderField: "Cookie") }
    session.dataTask(with: r) { [weak self] d, resp, _ in
      let img = ((resp as? HTTPURLResponse)?.statusCode == 200 ? d : nil).flatMap { UIImage(data: $0) }
      if let img = img, let d = d { try? d.write(to: disk); self?.pics.setObject(img, forKey: p as NSString) }
      DispatchQueue.main.async { done(img) }
    }.resume()
  }

  // ---------- live: the server says when something new is waiting (then the app asks for it) ----------
  private var stream: URLSessionDataTask?
  private var streamSession: URLSession?
  private var streamDelegate: StreamDelegate?
  var onNews: (() -> Void)?
  func listen() {
    stopListening()
    guard signedIn else { return }
    let d = StreamDelegate { [weak self] in DispatchQueue.main.async { self?.onNews?() } } ended: { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self?.stream != nil, UIApplication.shared.applicationState == .active { self?.listen() } }
    }
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 3600; c.timeoutIntervalForResource = 24 * 3600
    c.httpCookieStorage = nil; c.httpShouldSetCookies = false
    let s = URLSession(configuration: c, delegate: d, delegateQueue: nil)
    var r = request("/api/talk/stream"); r.setValue("text/event-stream", forHTTPHeaderField: "Accept"); r.timeoutInterval = 3600
    let t = s.dataTask(with: r)
    streamDelegate = d; streamSession = s; stream = t
    t.resume()
  }
  func stopListening() { stream?.cancel(); stream = nil; streamSession?.invalidateAndCancel(); streamSession = nil; streamDelegate = nil }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate {
  let news: () -> Void, ended: () -> Void
  init(_ news: @escaping () -> Void, ended: @escaping () -> Void) { self.news = news; self.ended = ended }
  func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    if String(decoding: data, as: UTF8.self).contains("event: talk") { news() }
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { ended() }
}
