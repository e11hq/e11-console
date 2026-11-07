import UIKit

/* TEMPORARY — measuring only (Haris 2026-11-07, check build): what moves on Home while a task slides in over it and
   back (the big title and Home's search box jumping). Every screen frame for ~1.2 s: where Apple's bar, its big title,
   Home's page, its list and its search box are, and which of our layout code ran. Taken out once the cause is found. */
final class SelfTrace: NSObject {
  static let shared = SelfTrace()
  private var link: CADisplayLink?
  private var t0: CFTimeInterval = 0, until: CFTimeInterval = 0
  private var rows: [[String: Any]] = []
  private var notes: [String] = []
  private var key = ""
  private var done: (([[String: Any]]) -> Void)?
  static var on: Bool { shared.link != nil }
  static func note(_ s: String) { guard on else { return }; shared.notes.append(s) }
  func start(_ k: String, seconds: CFTimeInterval = 1.2, _ then: @escaping ([[String: Any]]) -> Void) {
    key = k; rows = []; notes = []; done = then
    t0 = CACurrentMediaTime(); until = t0 + seconds
    let l = CADisplayLink(target: self, selector: #selector(tick)); l.add(to: .main, forMode: .common); link = l
  }
  // where a view truly is on screen this frame (its presentation, up to the window)
  private func shown(_ v: UIView?) -> [Int] {
    guard let v = v, let w = v.window else { return [] }
    var x: CGFloat = 0, y: CGFloat = 0
    var cur: CALayer? = v.layer
    while let l = cur, l !== w.layer {
      let p = l.presentation() ?? l
      x += p.frame.minX - (l.superlayer.map { ($0.presentation() ?? $0).bounds.minX } ?? 0)
      y += p.frame.minY - (l.superlayer.map { ($0.presentation() ?? $0).bounds.minY } ?? 0)
      cur = l.superlayer
    }
    let b = (v.layer.presentation() ?? v.layer).bounds
    return [Int(x.rounded()), Int(y.rounded()), Int(b.width.rounded()), Int(b.height.rounded())]
  }
  private func labels(_ v: UIView, _ text: String, _ out: inout [[String: Any]]) {
    if let l = v as? UILabel, l.text == text { out.append(["at": shown(l), "font": Int(l.font.pointSize), "a": Double(String(format: "%.2f", (l.layer.presentation() ?? l.layer).opacity)) ?? 0, "hidden": l.isHidden]) }
    v.subviews.forEach { labels($0, text, &out) }
  }
  @objc private func tick() {
    let now = CACurrentMediaTime()
    let hvc = HomeVC.shared, h = Main.shared.homeIfMade
    let bar = hvc?.navigationController?.navigationBar
    var titles: [[String: Any]] = []
    if let b = bar, let t = hvc?.navigationItem.title { labels(b, t, &titles) }
    let sv = h?.appleScroll
    var row: [String: Any] = ["t": Int(((now - t0) * 1000).rounded())]
    row["bar"] = shown(bar); row["title"] = titles
    row["homeVC"] = shown(hvc?.view); row["safeTop"] = Int(hvc?.view.safeAreaInsets.top ?? -1); row["safeBot"] = Int(hvc?.view.safeAreaInsets.bottom ?? -1)
    row["offY"] = Int(sv?.contentOffset.y ?? 0); row["inTop"] = Int(sv?.adjustedContentInset.top ?? 0); row["inBot"] = Int(sv?.adjustedContentInset.bottom ?? 0)
    row["search"] = shown(h?.appleSearchBox); row["tabBar"] = shown(AppleTabs.shared?.tabBar)
    row["moving"] = hvc?.navigationController?.transitionCoordinator != nil
    if !notes.isEmpty { row["ran"] = notes; notes = [] }
    rows.append(row)
    if now >= until { link?.invalidate(); link = nil; done?(rows); done = nil }
  }
}
