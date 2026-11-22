import UIKit

/* A test page for now (Haris 2026-11-22 21:33): the last thing sent — each step on the phone with its time from Send, and for
   each request iPhone's own record of it (connecting, the last byte leaving, the first byte of the answer, the answer in) —
   to find where the wait at the end of an upload goes. Cloudflare's own times come from its live log. Reached by tapping
   Version five times in About. To be taken out once it's found. */
enum Diag {
  private(set) static var steps: [(String, Double)] = []
  private static var t0: Double = 0, d0 = Date()
  private(set) static var what = ""
  // something new being sent: everything starts again
  static func start(_ kind: String) {
    let t = CACurrentMediaTime(), d = Date()
    DispatchQueue.main.async { steps = []; t0 = t; d0 = d; what = kind; steps.append(("Send tapped (\(kind))", 0)) }
  }
  static func mark(_ s: String) {
    let t = CACurrentMediaTime()
    DispatchQueue.main.async { guard t0 > 0 else { return }; steps.append((s, t - t0)) }
  }
  // a request's own record, from iPhone (URLSessionTaskMetrics)
  static func metrics(_ name: String, _ m: URLSessionTaskMetrics) {
    guard let x = m.transactionMetrics.last else { return }
    DispatchQueue.main.async {
      guard t0 > 0 else { return }
      let s = { (d: Date?) -> Double? in d.map { $0.timeIntervalSince(d0) } }
      if let a = s(x.fetchStartDate) { steps.append(("· \(name): asked", a)) }
      if let a = s(x.connectStartDate), let b = s(x.connectEndDate) { steps.append(("· \(name): connecting took \(Int((b - a) * 1000)) ms", b)) }
      if let a = s(x.requestEndDate) { steps.append(("· \(name): last byte left the phone", a)) }
      if let a = s(x.responseStartDate) { steps.append(("· \(name): answer started", a)) }
      if let a = s(x.responseEndDate) { steps.append(("· \(name): answer in (\(x.networkProtocolName ?? "?")\(x.isReusedConnection ? ", same connection" : ", new connection"))", a)) }
      steps.sort { $0.1 < $1.1 }
    }
  }
}
// (per request: its record goes to the test page)
final class DiagMetrics: NSObject, URLSessionTaskDelegate {
  let name: String
  init(_ name: String) { self.name = name }
  func urlSession(_ s: URLSession, task: URLSessionTask, didFinishCollecting m: URLSessionTaskMetrics) { Diag.metrics(name, m) }
}

final class DiagVC: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Test"; view.backgroundColor = .systemGroupedBackground
    let sv = UIScrollView(), l = UILabel()
    sv.translatesAutoresizingMaskIntoConstraints = false; l.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(sv); sv.addSubview(l)
    NSLayoutConstraint.activate([sv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                 sv.leadingAnchor.constraint(equalTo: view.leadingAnchor), sv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                 l.topAnchor.constraint(equalTo: sv.topAnchor, constant: 16), l.bottomAnchor.constraint(equalTo: sv.bottomAnchor, constant: -16),
                                 l.leadingAnchor.constraint(equalTo: sv.leadingAnchor, constant: 16), l.widthAnchor.constraint(equalTo: sv.widthAnchor, constant: -32)])
    l.numberOfLines = 0; l.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    l.text = Diag.steps.isEmpty ? "Send something, then come back here." : "The last thing sent (seconds from Send):\n\n" + Diag.steps.map { String(format: "%6.2f  ", $0.1) + $0.0 }.joined(separator: "\n")
  }
}
