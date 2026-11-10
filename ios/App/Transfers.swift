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
    downs[t.taskIdentifier] = Down(name, progress, done)
    t.resume()
    return t
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
    let name = ((t.response?.suggestedFilename).flatMap { $0.isEmpty || $0 == "Unknown" ? nil : $0 } ?? d.name).replacingOccurrences(of: "/", with: "-")
    let sub = dir.appendingPathComponent("dl-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let dest = sub.appendingPathComponent(name.isEmpty ? "file" : name)
    if (try? FileManager.default.moveItem(at: loc, to: dest)) != nil { d.file = dest }
  }
  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
    let id = task.taskIdentifier
    if let u = ups.removeValue(forKey: id) {
      try? FileManager.default.removeItem(at: u.file)
      u.done(e == nil ? task.response as? HTTPURLResponse : nil, u.data)
    }
    if let d = downs.removeValue(forKey: id) { d.done(e == nil ? d.file : nil) }
  }
  func urlSessionDidFinishEvents(forBackgroundURLSession s: URLSession) { let w = wake; wake = nil; w?() }
}
