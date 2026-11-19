import UIKit
import Security

/* Talking to the server (server/src/talk.js — /api/talk/…). E11 Talk's own sign-in for now (Haris 2026-11-06: before
   the App Store it becomes shared with E11 Console): Cloudflare's email code in a web page once, then its sign-in cookie
   is kept in the Keychain and sent with every request. Built on the test server first (talk-test.e11hq.com). */
// The server E11 Talk is on: the one E11 Console is on (Haris 2026-11-13: "Follow E11 Console") — Console's live copy →
// talk.e11hq.com, its test copy → talk-test.e11hq.com, the App Review copy → the same review address. Console tells it
// through the sign-in it shares with its widget (SignInKeys.consoleSignIn). Talk's own "App Review sign-in" puts it on the
// App Review copy until signing out. No Console on the phone (a client contact): the build's own server.
enum Server {
  private(set) static var url: String = resolve()
  static var host: String { URL(string: url)?.host ?? "" }
  static var review: Bool { host.hasPrefix("review.") }
  static var reviewURL: String { Bundle.main.object(forInfoDictionaryKey: "TalkReviewServerURL") as? String ?? "https://review.e11hq.com" }
  // (asked again before signing in and at the start: E11 Console may have moved — Talk's sign-in and copy are per server)
  static func follow() {
    let u = resolve()
    guard u != url else { return }
    url = u; Net.shared.reload()
  }
  // (the App Store screenshots' run only — Haris 2026-11-14: in a simulator test build, a local server with the App Review
  //  copy's made-up chats, signed in by its development header; never in a TestFlight or App Store build)
  #if DEBUG
  static let devEmail: String? = ProcessInfo.processInfo.environment["E11_TALK_DEV_EMAIL"].flatMap { $0.isEmpty ? nil : $0 }
  #endif
  private static func resolve() -> String {
    #if DEBUG
    if let s = ProcessInfo.processInfo.environment["E11_TALK_SERVER"], !s.isEmpty { return s }
    #endif
    if UserDefaults.standard.bool(forKey: "talk_review") { return reviewURL }
    if let h = SignInKeys.consoleSignIn.flatMap({ URL(string: $0.server)?.host }) {
      if h == "console.e11hq.com" { return "https://talk.e11hq.com" }
      if h == "test.e11hq.com" { return "https://talk-test.e11hq.com" }
      if h.hasPrefix("review.") { return "https://" + h }
    }
    // (no E11 Console signed in on this phone — a client contact, or Talk signed in first: the live server, as the App Store
    //  app should — it was the test server, left from when Talk was built there; Haris 2026-11-17 12:18)
    return Bundle.main.object(forInfoDictionaryKey: "TalkServerURL") as? String ?? "https://talk.e11hq.com"
  }
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
  // (the server kept in the Keychain too: the notification helper tells it the message reached this phone — Notify/)
  init() { cookie = Keychain.get("cookie-" + Server.host); Keychain.set(Server.url, "notify-server") }
  func reload() { stopListening(); cookie = Keychain.get("cookie-" + Server.host); Keychain.set(Server.url, "notify-server") }   // (another server: its own sign-in)
  var signedIn: Bool {
    #if DEBUG
    if Server.devEmail != nil { return true }
    #endif
    return !(cookie ?? "").isEmpty
  }

  func request(_ path: String, method: String = "GET", json: [String: Any]? = nil, body: Data? = nil, type: String? = nil) -> URLRequest {
    var r = URLRequest(url: URL(string: Server.url + path)!)
    r.httpMethod = method
    if let c = cookie { r.setValue(c, forHTTPHeaderField: "Cookie") }
    #if DEBUG
    if let e = Server.devEmail { r.setValue(e, forHTTPHeaderField: "X-Dev-Email") }
    #endif
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
  // a file → the server, in 4 MB pieces: the first makes it; then three side by side, each written at its own place (at=),
  // and an empty last one at its whole length (Haris 2026-11-16, "uploads are super slow": one piece after another left the
  // line idle between them). The ring fills smoothly as the pieces go.
  // (in the office: over the office network first — Office, Haris 2026-11-17 20:13; if that doesn't work, again the usual way
  //  from the start)
  func upload(_ data: Data, name: String, progress: @escaping (Double) -> Void, done: @escaping (String?) -> Void) {
    Office.shared.pass(["kind": "up"]) { [weak self] p in
      guard let self = self else { return done(nil) }
      guard let p = p else { return self.upload1(data, name: name, via: nil, progress: progress, done: done) }
      self.upload1(data, name: name, via: p, progress: progress) { [weak self] fid in
        if let fid = fid { return done(fid) }
        Office.shared.failed(); progress(0)
        self?.upload1(data, name: name, via: nil, progress: progress, done: done)
      }
    }
  }
  private func upload1(_ data: Data, name: String, via: Office.Pass?, progress: @escaping (Double) -> Void, done: @escaping (String?) -> Void) {
    let piece = 4 * 1024 * 1024, together = 3
    let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "file"
    var id: String?, next = 0, going = 0, over = false, gone = 0
    var partly: [Int: Int] = [:]   // (how far each piece on its way has gone)
    var watches: [Int: NSKeyValueObservation] = [:]
    let finish = { (fid: String?) in guard !over else { return }; over = true; watches.values.forEach { $0.invalidate() }; watches = [:]; done(fid) }
    let report = { progress(data.isEmpty ? 1 : min(0.99, Double(gone + partly.values.reduce(0, +)) / Double(data.count))) }
    // one piece; at nil: the first, made in order (it makes the file)
    func send(_ offset: Int, last: Bool, at: Bool, then: @escaping (String) -> Void) {
      let end = min(data.count, offset + piece)
      var q = "/api/talk/upload?offset=\(offset)&name=\(enc)"
      if let id = id { q += "&id=\(id)" }
      if at { q += "&at=\(offset)" }
      if last { q += "&last=1" }
      going += 1
      var r = request(q, method: "POST", body: data.subdata(in: offset..<end))
      if let p = via, let u = URL(string: p.url + "/local/talk/upload?t=" + (p.token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") + "&" + q.dropFirst("/api/talk/upload?".count)) {
        var lr = URLRequest(url: u); lr.httpMethod = "POST"; lr.httpBody = r.httpBody
        lr.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type"); r = lr
      }
      let t = (via == nil ? session : Office.shared.session).dataTask(with: r) { d, _, _ in
        let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        DispatchQueue.main.async {
          going -= 1
          watches[offset]?.invalidate(); watches[offset] = nil
          guard !over else { return }
          guard (j?["ok"] as? Bool) == true, let fid = j?["id"] as? String else { finish(nil); return }
          partly[offset] = nil; gone += end - offset; report()
          then(fid)
        }
      }
      if end > offset {
        watches[offset] = t.progress.observe(\.fractionCompleted) { p, _ in
          let n = Int(p.fractionCompleted * Double(end - offset))
          DispatchQueue.main.async { guard !over else { return }; partly[offset] = n; report() }
        }
      }
      t.resume()
    }
    // (as many on their way as there's room for; all in — the empty last piece, which the server takes only if nothing is missing)
    func pump() {
      guard !over else { return }
      while going < together && next < data.count { let off = next; next += piece; send(off, last: false, at: true) { _ in pump() } }
      if going == 0 && next >= data.count { send(data.count, last: true, at: true) { fid in finish(fid) } }
    }
    // (a file of one piece goes as before, in one go)
    if data.count <= piece { send(0, last: true, at: false) { fid in finish(fid) }; return }
    next = piece
    send(0, last: false, at: false) { fid in id = fid; pump() }
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
  // a message's file from the server — in the office over the office network first (Office), else (or if that doesn't
  // work) the usual way. The answer as a download task gives it: the file, and the server's answer.
  private func download(_ id: String, _ then: @escaping (URL?, URLResponse?) -> Void) {
    let usual = { self.session.downloadTask(with: self.request("/api/talk/file/" + id)) { tmp, resp, _ in then(tmp, resp) }.resume() }
    Office.shared.pass(["kind": "file", "id": id]) { p in
      guard let p = p, let u = URL(string: p.url + "/local/talk/file?t=" + (p.token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")) else { return usual() }
      Office.shared.session.downloadTask(with: URLRequest(url: u)) { tmp, resp, _ in
        if let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode == 200 { return then(tmp, resp) }
        Office.shared.failed(); usual()
      }.resume()
    }
  }
  func file(_ id: String, _ done: @escaping (URL?) -> Void) {
    let to = Net.local(id)
    if FileManager.default.fileExists(atPath: to.path) { done(to); return }
    let uid = Talk.shared.me?.id
    download(id) { tmp, resp in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      // (no longer on the server: from the iCloud backup when it's there — Haris 2026-11-14)
      if (400..<500).contains(code) { DispatchQueue.main.async { Backup.shared.recover(id, uid: uid, done) }; return }
      guard let tmp = tmp, code == 200 else { DispatchQueue.main.async { done(nil) }; return }
      try? FileManager.default.removeItem(at: to)
      try? FileManager.default.moveItem(at: tmp, to: to)
      DispatchQueue.main.async { done(FileManager.default.fileExists(atPath: to.path) ? to : nil) }
    }
  }
  // a new message's file onto the phone before saying it arrived: true once it's here — or the server has none to give
  // (gone, refused); false only when it couldn't be reached, to be tried again
  func fetch(_ id: String, _ done: @escaping (Bool) -> Void) {
    let to = Net.local(id)
    if FileManager.default.fileExists(atPath: to.path) { done(true); return }
    let uid = Talk.shared.me?.id
    download(id) { tmp, resp in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      if (400..<500).contains(code) { DispatchQueue.main.async { Backup.shared.recover(id, uid: uid) { _ in done(true) } }; return }
      if code == 200, let tmp = tmp { try? FileManager.default.removeItem(at: to); try? FileManager.default.moveItem(at: tmp, to: to) }
      DispatchQueue.main.async { done(code == 200 || (400..<500).contains(code)) }
    }
  }
  // E11 Console's pictures (people's photos, client logos) — the same server
  private let pics = NSCache<NSString, UIImage>()
  func picture(_ path: String?, max: CGFloat = 160, _ done: @escaping (UIImage?) -> Void) {
    guard let p = path, !p.isEmpty else { done(nil); return }
    if let i = pics.object(forKey: p as NSString) { done(i); return }
    let disk = Net.filesDir.appendingPathComponent("pic-" + Net.stableKey(p))   // (a name that stays the same from one launch to the next)
    if let d = try? Data(contentsOf: disk), let i = UIImage(data: d) { pics.setObject(i, forKey: p as NSString); done(i); return }
    // (an SVG logo: drawn once into a picture and kept as one — iPhone's own pictures can't read SVG)
    let svg = { (d: Data) in
      DispatchQueue.main.async {
        SVGRaster.shared.image(d, max: max) { [weak self] i in
          if let i = i { if let png = i.pngData() { try? png.write(to: disk) }; self?.pics.setObject(i, forKey: p as NSString) }
          done(i)
        }
      }
    }
    let path = p.hasPrefix("http") || p.hasPrefix("data:") ? p : "/__file/" + p.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
    if path.hasPrefix("data:"), let comma = path.firstIndex(of: ","), let d = Data(base64Encoded: String(path[path.index(after: comma)...])), let i = UIImage(data: d) {
      pics.setObject(i, forKey: p as NSString); done(i); return
    }
    var r = path.hasPrefix("http") ? URLRequest(url: URL(string: path)!) : request(path)
    if path.hasPrefix("http"), let c = cookie { r.setValue(c, forHTTPHeaderField: "Cookie") }
    session.dataTask(with: r) { [weak self] d, resp, _ in
      if (resp as? HTTPURLResponse)?.statusCode == 200, let d = d, UIImage(data: d) == nil, SVGRaster.looksLikeSVG(d, path: p) { svg(d); return }
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
    let text = String(decoding: data, as: UTF8.self)
    if text.contains("event: talk") { news() }
    // (someone typing: passed straight on by the server, nothing kept — step 5)
    // (tasks changed in E11 Console: the chat that's open asks for its cards again)
    // (…and a link turned off or on, or Client Assets changed: its cards too — Haris 2026-11-16)
    if text.contains("event: tasks") || text.contains("event: links") { DispatchQueue.main.async { NotificationCenter.default.post(name: .talkTasks, object: nil) } }
    // (E11 Console's people or clients changed — a name, a photo, a role, a client renamed or gone: read again while Talk is
    //  open, not only when it comes back; only what changed is drawn again — Haris 2026-11-16)
    if text.contains("event: people") { DispatchQueue.main.async { Talk.shared.refresh() } }
    for block in text.components(separatedBy: "\n\n") where block.contains("event: typing") {
      guard let line = block.split(separator: "\n").first(where: { $0.hasPrefix("data: ") }),
            let j = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any],
            let g = j["group"] as? String, let by = j["by"] as? String else { continue }
      DispatchQueue.main.async { Talk.shared.typed(g, by) }
    }
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { ended() }
}
