import UIKit

/* The top buttons, shared by every screen of the app's own (Haris, 2026-11-01): three Liquid Glass buttons in one
   glass container — so when two come close they melt together like drops of liquid, and part again:
     left    ‹ (a task page)                                  — grows in / shrinks away
     middle  🔍 · Mark all read · Mark all unread · Done      — stretches between a circle and a capsule
     corner  your photo · ••• (its menu opens out of it) · ✕
   Opening a task: 🔍 melts into your photo, the photo turns into •••, ‹ grows in; back: the other way; the swipe from
   the edge in between follows the finger. Each screen only says what its buttons are and where (HomeView.corner(),
   TaskPage.cornerFrame); its own buttons stay invisible. */
final class CornerButton: UIView {
  struct Spot { var kind = "none", text = "", frame = CGRect.zero, image: UIImage? = nil }
  private let container: UIVisualEffectView = {
    let v = UIVisualEffectView(effect: nil)
    // (they join only when closer than this — at rest, 12 apart, they stay two)
    if #available(iOS 26.0, *) { let c = UIGlassContainerEffect(); c.spacing = 6; v.effect = c }
    return v
  }()
  let leftB = CornerButton.glassButton(), midB = CornerButton.glassButton(), cornerB = CornerButton.glassButton()
  private(set) var left = Spot(), mid = Spot(), corner = Spot()
  var onLeft: (() -> Void)?, onMid: ((String) -> Void)?, onCorner: ((String) -> Void)?
  // (what the self-test reads: the corner's ••• on a task page, else the middle one's kind)
  var kind: String { corner.kind == "more" ? "more" : mid.kind }
  static let duration: TimeInterval = 0.42, bounce: CGFloat = 0.22

  static func glassButton() -> UIButton {
    var c: UIButton.Configuration
    if #available(iOS 26.0, *) { c = .glass() } else { c = .gray() }
    c.cornerStyle = .capsule
    c.baseForegroundColor = .label
    c.contentInsets = .zero
    let b = UIButton(configuration: c)
    b.alpha = 0
    return b
  }
  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(container)
    [leftB, midB, cornerB].forEach { container.contentView.addSubview($0) }
    leftB.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onLeft?() }, for: .touchUpInside)
    midB.addAction(UIAction { [weak self] _ in guard let self = self else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); self.onMid?(self.mid.kind) }, for: .touchUpInside)
    cornerB.addAction(UIAction { [weak self] _ in guard let self = self, self.corner.kind != "more" else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred(); self.onCorner?(self.corner.kind) }, for: .touchUpInside)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); container.frame = bounds }
  // only the buttons take touches; the rest of the strip lets them through to the screen
  override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? {
    let q = convert(p, to: container.contentView)
    for b in [cornerB, midB, leftB] where b.alpha > 0.05 && !b.isHidden && b.frame.contains(q) { return b }
    return nil
  }

  // what a capsule with words needs; a place for the middle one (a capsule keeps the circle's right edge)
  func width(_ kind: String, _ text: String) -> CGFloat {
    if ["read", "unread", "done"].contains(kind) { return ceil((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width) + 32 }
    return 44
  }
  func place(_ kind: String, _ text: String, circle f: CGRect) -> CGRect { let w = width(kind, text); return CGRect(x: f.maxX - w, y: f.minY, width: w, height: f.height) }

  private func dress(_ b: UIButton, _ s: Spot, menu: UIMenu?) {
    var c = b.configuration ?? .plain()
    c.title = nil; c.attributedTitle = nil; c.image = nil
    switch s.kind {
    case "back": c.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium))
    case "search": c.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
    case "more": c.image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
    case "close": c.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
    case "photo": c.image = s.image?.withRenderingMode(.alwaysOriginal)
    case "read", "unread", "done": c.attributedTitle = AttributedString(s.text, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: s.kind == "done" ? UIColor.systemBlue : UIColor.label]))
    default: break
    }
    c.baseForegroundColor = .label
    b.configuration = c
    // (your photo fills its circle; the ••• opens iPhone's own menu straight out of the glass)
    b.clipsToBounds = s.kind == "photo"
    b.layer.cornerRadius = s.frame.height / 2
    b.menu = s.kind == "more" ? menu : nil
    b.showsMenuAsPrimaryAction = s.kind == "more" && menu != nil
    b.accessibilityLabel = ["back": "Back", "search": "Search", "more": "More", "close": "Close search", "photo": "Me"][s.kind] ?? s.text
  }
  // to these three spots — with the spring, or at once
  func go(left l: Spot, mid m: Spot, corner c: Spot, menu: UIMenu?, animated: Bool) {
    let oldCorner = corner
    let pairs: [(UIButton, Spot, Spot)] = [(leftB, left, l), (midB, mid, m), (cornerB, corner, c)]
    left = l; mid = m; corner = c
    var moves: [() -> Void] = []
    for (b, was, now) in pairs {
      let changed = was.kind != now.kind || was.text != now.text || was.image !== now.image
      if now.kind == "none" {
        // going: 🔍 melts into the corner (moves onto it as it fades — the glass joins them), others shrink away
        let into: CGRect? = b === midB && was.kind == "search" && c.kind != "none" ? c.frame : nil
        moves.append { if let f = into { b.frame = f } else { b.transform = CGAffineTransform(scaleX: 0.4, y: 0.4) }; b.alpha = 0 }
        continue
      }
      if was.kind == "none" || b.alpha < 0.05 {
        // coming: 🔍 comes back out of the corner, the rest grow in where they go
        let from: CGRect? = b === midB && now.kind == "search" && oldCorner.kind != "none" && animated ? oldCorner.frame : nil
        b.transform = .identity
        b.frame = from ?? now.frame
        if from == nil && animated { b.transform = CGAffineTransform(scaleX: 0.4, y: 0.4) }
        dress(b, now, menu: menu)
      } else if changed {
        if animated { UIView.transition(with: b, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.dress(b, now, menu: menu) } }
        else { dress(b, now, menu: menu) }
      } else { b.menu = now.kind == "more" ? menu : nil; b.showsMenuAsPrimaryAction = now.kind == "more" && menu != nil }
      moves.append { b.transform = .identity; b.frame = now.frame; b.alpha = 1; b.layer.cornerRadius = now.frame.height / 2 }
    }
    let run = { moves.forEach { $0() } }
    if !animated { run(); return }
    if #available(iOS 17.0, *) { UIView.animate(springDuration: CornerButton.duration, bounce: CornerButton.bounce, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: run) }
    else { UIView.animate(withDuration: CornerButton.duration, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: run) }
  }
  // part way between two sets (the swipe back): t = 0 at `a`, 1 at `b`
  func between(_ a: (Spot, Spot, Spot), _ b: (Spot, Spot, Spot), _ t: CGFloat) {
    let t = max(0, min(1, t))
    func lerp(_ x: CGRect, _ y: CGRect) -> CGRect { CGRect(x: x.minX + (y.minX - x.minX) * t, y: x.minY + (y.minY - x.minY) * t, width: x.width + (y.width - x.width) * t, height: x.height + (y.height - x.height) * t) }
    let rows: [(UIButton, Spot, Spot)] = [(leftB, a.0, b.0), (midB, a.1, b.1), (cornerB, a.2, b.2)]
    for (btn, x, y) in rows {
      btn.transform = .identity
      if x.kind == "none" && y.kind == "none" { btn.alpha = 0; continue }
      if x.kind == "none" {
        btn.frame = btn === midB && a.2.kind != "none" ? lerp(a.2.frame, y.frame) : y.frame
        btn.alpha = t
        if t > 0.5 { dress(btn, y, menu: nil) }
        continue
      }
      if y.kind == "none" {
        btn.frame = btn === midB && b.2.kind != "none" ? lerp(x.frame, b.2.frame) : x.frame
        btn.alpha = 1 - t
        continue
      }
      btn.frame = lerp(x.frame, y.frame); btn.alpha = 1
      dress(btn, t < 0.5 ? x : y, menu: nil)
      btn.layer.cornerRadius = btn.frame.height / 2
    }
  }
}

// ---------- on the app's screen ----------
extension Main {
  // the three spots now: the top task page's, else the shown screen's
  func cornerTarget(skipTop: Bool = false) -> (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot) {
    let pages = skipTop ? Array(taskPages.dropLast()) : taskPages
    if let p = pages.last {
      let f = p.convert(p.cornerFrame, to: view).offsetBy(dx: -p.transform.tx, dy: 0)
      let bf = p.convert(p.backFrame, to: view).offsetBy(dx: -p.transform.tx, dy: 0)
      let mid = p.editingDesc ? CornerButton.Spot(kind: "done", text: "Done", frame: corner.place("done", "Done", circle: f.offsetBy(dx: -56, dy: 0))) : CornerButton.Spot()
      return (CornerButton.Spot(kind: "back", frame: bf), mid, CornerButton.Spot(kind: "more", frame: f))
    }
    if let h = shownScreen {
      let dx = -h.transform.tx
      let c = h.corner()
      let mf = corner.place(c.kind, c.text, circle: h.convert(c.frame, to: view).offsetBy(dx: dx, dy: 0))
      let meF = h.convert(h.meFrame, to: view).offsetBy(dx: dx, dy: 0)
      let cornerSpot = h.searching ? CornerButton.Spot(kind: "close", frame: meF) : CornerButton.Spot(kind: "photo", frame: meF, image: h.meImage)
      return (CornerButton.Spot(), CornerButton.Spot(kind: c.kind, text: c.text, frame: mf), cornerSpot)
    }
    return (CornerButton.Spot(), CornerButton.Spot(), CornerButton.Spot())
  }
  // (a tab change hides one screen and shows the next a moment apart: settled together, so it changes in place
  //  rather than going and coming back)
  func updateCorner(animated: Bool = true) {
    if cornerPending { return }
    cornerPending = true
    DispatchQueue.main.async { self.cornerPending = false; self.updateCornerNow(animated: animated) }
  }
  func updateCornerNow(animated: Bool = true) {
    // (only once there's a screen of the app's own to show it on)
    guard homeIfMade != nil || myTasksIfMade != nil || inboxIfMade != nil || !taskPages.isEmpty else { return }
    for h in [homeIfMade, myTasksIfMade, inboxIfMade].compactMap({ $0 }) where !h.cornerShared { h.cornerShared = true; h.onCorner = { [weak self] in self?.updateCorner() } }
    for p in taskPages where !p.cornerShared { p.cornerShared = true; p.onMenu = { [weak self] in self?.updateCorner(animated: false) } }
    if corner.superview == nil {
      corner.onLeft = { [weak self] in guard let self = self, let p = self.taskPages.last else { return }; if p.editingDesc { p.finishDesc() }; self.closeTaskPage(p) }
      corner.onMid = { [weak self] k in if k == "done" { self?.taskPages.last?.finishDesc(); return }; self?.shownScreen?.cornerTap(k) }
      corner.onCorner = { [weak self] k in guard let h = self?.shownScreen else { return }; if k == "close" { h.closeSearch() } else { h.meTap() } }
    }
    // (a strip across the top, above the screens and task pages, under sheets and the tab bar)
    let strip = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.safeAreaInsets.top + 60)
    if corner.frame != strip { corner.frame = strip }
    if let top = taskPages.last { view.insertSubview(corner, aboveSubview: top) } else { view.insertSubview(corner, belowSubview: tabBar) }
    if lockView != nil { corner.alpha = 0; return }
    corner.alpha = 1
    let t = cornerTarget()
    corner.go(left: t.0, mid: t.1, corner: t.2, menu: taskPages.last?.cornerMenu, animated: animated && corner.window != nil)
  }
}
