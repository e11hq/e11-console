import UIKit

/* Every upload and download in the app, carried on by iPhone itself (Haris 2026-11-10: "every upload and download in the
   app"; plan: project doc claude/ios-background-transfers-plan.md). Apple's background URLSession: each upload's 2 MB pieces
   and each download are handed to iPhone, which keeps sending and fetching with the app in the background or the phone
   locked, and wakes the app to send the next piece (AppDelegate handleEventsForBackgroundURLSession). The bars, Cancel and
   the Save / Share sheet stay as they were. iPhone may pace them on low battery or Low Power Mode. */
final class Transfers: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate {
  static let shared = Transfers()
  static let id = "ae.e11.console.ios.transfers"
  // (iPhone woke the app for its transfers: told when they've all been dealt with)
  var wake: (() -> Void)?
  private lazy var session: URLSession = {
    // (the phone keeps only what's needed: downloads saved or shared more than a day ago let go)
    let fm = FileManager.default, old = Date().addingTimeInterval(-86400)
    for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where u.lastPathComponent.hasPrefix("dl-") {
      if ((try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) < old { try? fm.removeItem(at: u) }
    }
    let c = URLSessionConfiguration.background(withIdentifier: Transfers.id)
    c.sessionSendsLaunchEvents = true
    c.isDiscretionary = false
    c.httpMaximumConnectionsPerHost = 4
    return URLSession(configuration: c, delegate: self, delegateQueue: .main)
  }()
  // (iPhone woke the app for them: the session made again, so iPhone can hand it what finished)
  func reconnect() { _ = session }
  private final class Up { var data = Data(); let sent: (Int64) -> Void; let done: (HTTPURLResponse?, Data?) -> Void; let file: URL
    init(_ s: @escaping (Int64) -> Void, _ d: @escaping (HTTPURLResponse?, Data?) -> Void, _ f: URL) { sent = s; done = d; file = f } }
  private final class Down { let name: String; let progress: (Int64, Int64) -> Void; let done: (URL?) -> Void; var file: URL?
    init(_ n: String, _ p: @escaping (Int64, Int64) -> Void, _ d: @escaping (URL?) -> Void) { name = n; progress = p; done = d } }
  private var ups: [Int: Up] = [:], downs: [Int: Down] = [:]
  // (in the office: a file fetched from the NAS over the office network — Office — while the usual one waits, paused,
  //  in case it doesn't work: the office one → the usual one, and back)
  private var usual: [Int: URLSessionDownloadTask] = [:], office: [Int: URLSessionDownloadTask] = [:]
  private var dir: URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("transfers", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }

  // a piece of an upload: written to the phone (iPhone sends from a file), handed over; sent: how much of it went so far
  @discardableResult
  func upload(_ r: URLRequest, body: Data, sent: @escaping (Int64) -> Void, done: @escaping (HTTPURLResponse?, Data?) -> Void) -> URLSessionTask? {
    let f = dir.appendingPathComponent("up-\(UUID().uuidString)")
    guard (try? body.write(to: f)) != nil else { done(nil, nil); return nil }
    let t = session.uploadTask(with: r, fromFile: f)
    ups[t.taskIdentifier] = Up(sent, done, f)
    t.resume()
    return t
  }
  // a download: progress (fetched, of — -1 when not known), then the file on the phone (its own name), or nil
  @discardableResult
  func download(_ r: URLRequest, name: String, progress: @escaping (Int64, Int64) -> Void, done: @escaping (URL?) -> Void) -> URLSessionDownloadTask {
    let t = session.downloadTask(with: r)
    let d = Down(name, progress, done)
    downs[t.taskIdentifier] = d
    // a file of the server's, in the office: from the NAS over the office network (Haris 2026-11-17 20:13); the usual way
    // if there's no pass or it doesn't work. The task handed back stays the one to cancel.
    if let u = r.url, u.path.hasPrefix("/__file/"), u.host == URL(string: serverURL())?.host {
      let fp = String(u.path.dropFirst("/__file/".count))
      Office.pass(["kind": "file", "path": fp], cookie: r.value(forHTTPHeaderField: "Cookie") ?? "") { [weak self] p in
        guard let self = self, self.downs[t.taskIdentifier] === d, t.state == .suspended else { return }
        guard let p = p, var q = URLComponents(string: p.url + "/local/file") else { return self.viaR2(t, r, d) }
        q.queryItems = [URLQueryItem(name: "t", value: p.token)]
        guard let lu = q.url else { return self.viaR2(t, r, d) }
        var lr = URLRequest(url: lu); lr.timeoutInterval = 20
        let lt = self.session.downloadTask(with: lr)
        self.downs[lt.taskIdentifier] = d; self.usual[lt.taskIdentifier] = t; self.office[t.taskIdentifier] = lt
        lt.resume()
      }
    } else { t.resume() }
    return t
  }

  // away from the office: straight from Cloudflare R2, as the pictures (Haris 2026-11-21: downloads were slow — they all
  // came through the office). The server is asked for R2's short-lived address first (r2=1, the redirect not followed:
  // the sign-in never goes along to R2), then iPhone fetches it from R2 with nothing of ours; no R2 copy, or R2 doesn't
  // answer — the usual way, as before.
  private var fromR2 = Set<Int>()
  private lazy var asker: URLSession = URLSession(configuration: .ephemeral, delegate: NoFollow(), delegateQueue: nil)
  private final class NoFollow: NSObject, URLSessionTaskDelegate {
    func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest n: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  }
  private func viaR2(_ t: URLSessionDownloadTask, _ r: URLRequest, _ d: Down) {
    guard let u = r.url else { return t.resume() }
    var h = r; h.url = R2Files.ask(u); h.httpMethod = "HEAD"; h.timeoutInterval = 15; h.httpShouldHandleCookies = false
    asker.dataTask(with: h) { _, resp, _ in
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.downs[t.taskIdentifier] === d, t.state == .suspended else { return }
        guard let hr = resp as? HTTPURLResponse, hr.statusCode / 100 == 3, let loc = hr.value(forHTTPHeaderField: "Location"),
              let lu = URL(string: loc, relativeTo: h.url)?.absoluteURL, lu.host != URL(string: serverURL())?.host else { return t.resume() }
        var lr = URLRequest(url: lu); lr.httpShouldHandleCookies = false
        let rt = self.session.downloadTask(with: lr)
        self.downs[rt.taskIdentifier] = d; self.usual[rt.taskIdentifier] = t; self.office[t.taskIdentifier] = rt; self.fromR2.insert(rt.taskIdentifier)
        rt.resume()
      }
    }.resume()
  }

  // ---- what iPhone tells us ----
  func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { ups[dataTask.taskIdentifier]?.data.append(data) }
  func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData _: Int64, totalBytesSent: Int64, totalBytesExpectedToSend _: Int64) {
    ups[task.taskIdentifier]?.sent(totalBytesSent)
  }
  func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
    downs[t.taskIdentifier]?.progress(w, e)
  }
  // (the file must be moved before this returns — iPhone takes it away after)
  func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
    guard let d = downs[t.taskIdentifier], ((t.response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2 else { try? FileManager.default.removeItem(at: loc); return }
    let viaOffice = usual[t.taskIdentifier] != nil   // (the office address names no file: its own name)
    let name = ((viaOffice ? nil : t.response?.suggestedFilename).flatMap { $0.isEmpty || $0 == "Unknown" ? nil : $0 } ?? d.name).replacingOccurrences(of: "/", with: "-")
    let sub = dir.appendingPathComponent("dl-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let dest = sub.appendingPathComponent(name.isEmpty ? "file" : name)
    if (try? FileManager.default.moveItem(at: loc, to: dest)) != nil { d.file = dest }
  }
  // (the office server's own certificate — Office; everything else as iPhone checks it)
  func urlSession(_ s: URLSession, didReceive ch: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    if let r = Office.trust(ch) { completionHandler(r.0, r.1) } else { completionHandler(.performDefaultHandling, nil) }
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
    let id = task.taskIdentifier
    // (an office-network download ended: its file, or — it didn't work — the usual one goes ahead)
    if let t = usual.removeValue(forKey: id) {
      office[t.taskIdentifier] = nil
      guard let d = downs.removeValue(forKey: id) else { return }   // (cancelled with the usual one)
      let r2 = fromR2.remove(id) != nil
      if e == nil, let f = d.file { downs[t.taskIdentifier] = nil; t.cancel(); d.done(f) }
      else { if !r2 { Office.failed() }; d.progress(0, -1); t.resume() }
      return
    }
    if let lt = office.removeValue(forKey: id) { usual[lt.taskIdentifier] = nil; downs[lt.taskIdentifier] = nil; lt.cancel() }
    if let u = ups.removeValue(forKey: id) {
      try? FileManager.default.removeItem(at: u.file)
      u.done(e == nil ? task.response as? HTTPURLResponse : nil, u.data)
    }
    if let d = downs.removeValue(forKey: id) { d.done(e == nil ? d.file : nil) }
  }
  func urlSessionDidFinishEvents(forBackgroundURLSession s: URLSession) { let w = wake; wake = nil; w?() }
}

// iPhone's Save / Share sheet for a file going out — and, once it's done, where it went: "Saved to Photos" or "Saved to
// Files", only for those two (a PDF is never offered Photos by iPhone, so it never says Photos — Haris 2026-11-21)
enum ShareOut {
  static func sheet(_ items: [Any], say: @escaping (String) -> Void, after: (() -> Void)? = nil) -> UIActivityViewController {
    let a = UIActivityViewController(activityItems: items, applicationActivities: nil)
    a.completionWithItemsHandler = { type, done, _, _ in
      after?()
      guard done, let t = type else { return }
      if t == .saveToCameraRoll { say("Saved to Photos") }
      else if t.rawValue.localizedCaseInsensitiveContains("SaveToFiles") { say("Saved to Files") }
    }
    return a
  }
}
