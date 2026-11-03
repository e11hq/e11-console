import UIKit
import WebKit

/* SVG pictures on the phone (Haris 2026-11-03: ".svg is not loading on iOS"). iPhone's own pictures can't read SVG, so
   it's drawn by a web view out of sight and kept as a PNG — thumbnails, client logos and the preview then show it as any
   other picture. One at a time, a few seconds at most each. */
final class SVGRaster: NSObject, WKNavigationDelegate {
  static let shared = SVGRaster()
  private var web: WKWebView?
  private var queue: [(Data, CGFloat, (UIImage?) -> Void)] = []
  private var busy = false
  private var current: ((UIImage?) -> Void)?
  private var side: CGFloat = 1024
  private var timer: Timer?

  static func looksLikeSVG(_ d: Data, path: String? = nil) -> Bool {
    if let p = path?.lowercased().components(separatedBy: "?").first, p.hasSuffix(".svg") { return true }
    guard let head = String(data: d.prefix(600), encoding: .utf8)?.lowercased() else { return false }
    return head.contains("<svg")
  }
  // the picture, at most `max` points on its longer side (drawn at the screen's scale)
  func image(_ d: Data, max: CGFloat = 640, _ done: @escaping (UIImage?) -> Void) {
    queue.append((d, max, done))
    next()
  }
  private func next() {
    guard !busy, !queue.isEmpty else { return }
    busy = true
    let (d, m, done) = queue.removeFirst()
    current = done; side = m
    let w = web ?? {
      let c = WKWebViewConfiguration()
      let v = WKWebView(frame: CGRect(x: -4000, y: 0, width: m, height: m), configuration: c)
      v.isOpaque = false; v.backgroundColor = .clear; v.scrollView.backgroundColor = .clear
      v.navigationDelegate = self; v.isUserInteractionEnabled = false
      // (in a window, out of sight: a web view has to be on screen somewhere to draw)
      (UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first)?.addSubview(v)
      web = v
      return v
    }()
    w.frame = CGRect(x: -4000, y: 0, width: m, height: m)
    let html = "<!doctype html><html><head><meta name=viewport content='width=device-width,initial-scale=1'><style>html,body{margin:0;background:transparent;width:100%;height:100%}img{display:block;width:100%;height:100%;object-fit:contain}</style></head><body><img id=i src='data:image/svg+xml;base64,\(d.base64EncodedString())'></body></html>"
    w.loadHTMLString(html, baseURL: nil)
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in self?.finish(nil) }
  }
  func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
    // its own shape: the picture's width and height, fitted into the box
    w.evaluateJavaScript("(()=>{const i=document.getElementById('i');return i&&i.complete?[i.naturalWidth||0,i.naturalHeight||0]:[0,0]})()") { [weak self] r, _ in
      guard let self = self else { return }
      let a = (r as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? [0, 0]
      var size = CGSize(width: self.side, height: self.side)
      if a.count == 2, a[0] > 0, a[1] > 0 { let k = self.side / max(a[0], a[1]); size = CGSize(width: max(1, round(a[0] * k)), height: max(1, round(a[1] * k))) }
      w.frame = CGRect(origin: CGPoint(x: -4000, y: 0), size: size)
      // (a moment to lay out at the new size)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        let cfg = WKSnapshotConfiguration(); cfg.rect = CGRect(origin: .zero, size: size); cfg.afterScreenUpdates = true
        w.takeSnapshot(with: cfg) { img, _ in self.finish(img) }
      }
    }
  }
  func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { finish(nil) }
  func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { finish(nil) }
  private func finish(_ img: UIImage?) {
    timer?.invalidate(); timer = nil
    guard let done = current else { return }
    current = nil; busy = false
    done(img)
    next()
  }
}
