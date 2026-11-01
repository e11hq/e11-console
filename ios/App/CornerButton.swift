import UIKit

/* The corner button (shell 30, Haris 2026-11-01): one Liquid Glass button for Home's and My Tasks' Search, the
   Inbox's Mark all read / Mark all unread and a task page's •••. It isn't swapped between screens: it changes in
   place — slides to where the next screen has it, stretches from a circle to a capsule and back, its icon or words
   cross-fading — with a spring that overshoots a little and settles, as Mail's own back button does between pages.
   With the swipe back from the edge it follows the finger, part way between the two. */
final class CornerButton: UIView {
  private let fx = UIVisualEffectView(effect: nil)
  private let icon = UIImageView(), word = UILabel()
  private let menuBtn = UIButton(type: .custom)       // (••• : iPhone's own menu, from a tap)
  private(set) var kind = "none"
  private var text = ""
  var onTap: ((String) -> Void)?
  // Mail's: the glass reaches its new shape in about 0.4 s, overshooting a touch before it settles
  static let duration: TimeInterval = 0.42, bounce: CGFloat = 0.22

  override init(frame: CGRect) {
    super.init(frame: frame)
    fx.clipsToBounds = true
    if #available(iOS 26.0, *) { let g = UIGlassEffect(style: .regular); g.isInteractive = true; fx.effect = g }
    else { fx.effect = UIBlurEffect(style: .systemUltraThinMaterial); fx.layer.borderWidth = 1; fx.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor }
    addSubview(fx)
    icon.contentMode = .center; icon.tintColor = .label
    word.font = .systemFont(ofSize: 15, weight: .semibold); word.textColor = .label; word.textAlignment = .center
    addSubview(icon); addSubview(word)
    menuBtn.showsMenuAsPrimaryAction = true
    menuBtn.isHidden = true
    addSubview(menuBtn)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    isAccessibilityElement = true; accessibilityTraits = .button
    alpha = 0
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func tapped() { if kind != "more" { onTap?(kind) } }
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { kind != "more" && kind != "none" }

  static func symbol(_ kind: String) -> String? { kind == "search" ? "magnifyingglass" : kind == "more" ? "ellipsis" : nil }
  // how wide it is for this kind (a circle, or a capsule fitting its words)
  func width(_ kind: String, _ text: String) -> CGFloat {
    if kind == "read" || kind == "unread" { return ceil((text as NSString).size(withAttributes: [.font: word.font!]).width) + 32 }
    return 44
  }
  // its place for a screen whose circle would be at `f` (a capsule keeps the circle's right edge)
  func place(_ kind: String, _ text: String, circle f: CGRect) -> CGRect {
    let w = width(kind, text)
    return CGRect(x: f.maxX - w, y: f.minY, width: w, height: f.height)
  }

  // to a kind and place — with Mail's spring, or at once
  func go(_ k: String, text t: String, frame f: CGRect, menu: UIMenu?, animated: Bool) {
    let same = k == kind && t == text && frame.equalTo(f)
    menuBtn.menu = menu; menuBtn.isHidden = k != "more" || menu == nil
    accessibilityLabel = k == "search" ? "Search" : k == "more" ? "More" : t
    if same { return }
    let was = kind
    kind = k; text = t
    if k == "none" {
      // (going: it fades where it is — Search stretching into the search bar takes over from it)
      UIView.animate(withDuration: animated ? 0.12 : 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.alpha = 0 }
      return
    }
    let fromNone = was == "none" || alpha < 0.05
    if fromNone { frame = f; alpha = 0; transform = CGAffineTransform(scaleX: 0.7, y: 0.7) }
    // the new icon / words in, the old out (cross-fading while the glass changes shape)
    let sym = CornerButton.symbol(k)
    let newIcon = sym.map { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: k == "more" ? 18 : 18, weight: .medium)) } ?? nil
    let iconChanges = icon.image != newIcon || (sym == nil) != (icon.alpha < 0.5)
    if iconChanges && animated && !fromNone {
      UIView.animate(withDuration: 0.12) { self.icon.alpha = 0; self.word.alpha = 0 } completion: { _ in
        self.icon.image = newIcon; self.word.text = t
        UIView.animate(withDuration: 0.18) { self.icon.alpha = sym == nil ? 0 : 1; self.word.alpha = sym == nil ? 1 : 0 }
      }
    } else { icon.image = newIcon; word.text = t; icon.alpha = sym == nil ? 0 : 1; word.alpha = sym == nil ? 1 : 0 }
    let apply = { self.frame = f; self.alpha = 1; self.transform = .identity; self.layoutNow() }
    if !animated { apply() }
    else if #available(iOS 17.0, *) { UIView.animate(springDuration: CornerButton.duration, bounce: CornerButton.bounce, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: apply) }
    else { UIView.animate(withDuration: CornerButton.duration, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: apply) }
  }
  // part way between two (the swipe back): t = 0 at `a`, 1 at `b`
  func between(_ a: (kind: String, text: String, frame: CGRect), _ b: (kind: String, text: String, frame: CGRect), _ t: CGFloat) {
    let t = max(0, min(1, t))
    func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
    if b.kind == "none" { frame = a.frame; alpha = 1 - t; return }
    if a.kind == "none" { frame = b.frame; alpha = t; return }
    frame = CGRect(x: lerp(a.frame.minX, b.frame.minX), y: lerp(a.frame.minY, b.frame.minY), width: lerp(a.frame.width, b.frame.width), height: lerp(a.frame.height, b.frame.height))
    alpha = 1
    // the icon / words of whichever it's nearer
    let near = t < 0.5 ? a : b
    let sym = CornerButton.symbol(near.kind)
    icon.image = sym.map { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)) } ?? nil
    word.text = near.text
    let k = abs(t - 0.5) * 2   // (faint in the middle)
    icon.alpha = sym == nil ? 0 : k; word.alpha = sym == nil ? k : 0
    layoutNow()
  }
  private func layoutNow() {
    fx.frame = bounds; fx.layer.cornerRadius = bounds.height / 2
    icon.frame = bounds; word.frame = bounds.insetBy(dx: 8, dy: 0); menuBtn.frame = bounds
  }
  override func layoutSubviews() { super.layoutSubviews(); layoutNow() }
}

// ---------- on the app's screen ----------
extension Main {
  // what the corner should be now: the top task page's •••, else the shown screen's
  func cornerTarget(skipTop: Bool = false) -> (kind: String, text: String, frame: CGRect) {
    let pages = skipTop ? Array(taskPages.dropLast()) : taskPages
    if let p = pages.last { return ("more", "", p.convert(p.cornerFrame, to: view).offsetBy(dx: -p.transform.tx, dy: 0)) }
    if let h = shownScreen {
      let c = h.corner()
      return (c.kind, c.text, corner.place(c.kind, c.text, circle: h.convert(c.frame, to: view).offsetBy(dx: -h.transform.tx, dy: 0)))
    }
    return ("none", "", corner.frame)
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
    if corner.superview == nil { view.insertSubview(corner, belowSubview: tabBar) }
    // (above the screens and task pages; under sheets and the tab bar)
    if let top = taskPages.last { view.insertSubview(corner, aboveSubview: top) } else { view.insertSubview(corner, belowSubview: tabBar) }
    if lockView != nil { corner.alpha = 0; return }
    let t = cornerTarget()
    corner.go(t.kind, text: t.text, frame: t.frame, menu: taskPages.last?.cornerMenu, animated: animated && corner.window != nil)
  }
}
