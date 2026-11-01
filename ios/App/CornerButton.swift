import UIKit

/* The top buttons, shared by every screen of the app's own (Haris, 2026-11-01): three Liquid Glass buttons in one
   glass container — so when two come close they melt together like drops of liquid, and part again:
     left    ‹ (a task page)                                  — grows in / shrinks away
     middle  🔍 · Mark all read · Mark all unread · Done      — stretches between a circle and a capsule
     corner  your photo · ••• (its menu opens out of it) · ✕
   Opening a task: 🔍 melts into your photo, the photo turns into •••, ‹ grows in; back: the other way; the swipe from
   the edge in between follows the finger. Each screen only says what its buttons are and where (HomeView.corner(),
   TaskPage.cornerFrame); its own buttons stay invisible. */
/* One of them: iPhone's own Liquid Glass shape (a glass effect view, not a ready-made button), so the glass container
   does the liquid part itself — squash and stretch as it changes shape, melting into and out of the one beside it
   (Haris, 2026-11-01: "only iOS native animations throughout the app"). An icon, words or your photo on it; ••• has
   iPhone's own menu. */
final class GlassSpot: UIVisualEffectView {
  let icon = UIImageView(), word = UILabel(), photo = UIImageView()
  let menuBtn = UIButton(type: .custom)
  var onTap: (() -> Void)?
  static var glass: UIVisualEffect {
    if #available(iOS 26.0, *) { let g = UIGlassEffect(style: .regular); g.isInteractive = true; return g }
    return UIBlurEffect(style: .systemThinMaterial)
  }
  init() {
    super.init(effect: nil)
    icon.contentMode = .center; icon.tintColor = .label
    word.font = .systemFont(ofSize: 15, weight: .semibold); word.textAlignment = .center
    photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true
    menuBtn.showsMenuAsPrimaryAction = true; menuBtn.isHidden = true
    [photo, icon, word, menuBtn].forEach { contentView.addSubview($0) }
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func tapped() { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap?() }
  var shown: Bool { effect != nil || buttonGlass }
  // ••• at rest: iPhone's own glass button takes over (looks the same), so its menu grows out of the glass and goes
  // back into it; while moving / changing, the glass shape is back so the container keeps it liquid
  private(set) var buttonGlass = false
  func useButtonGlass(_ on: Bool) {
    guard on != buttonGlass else { return }
    buttonGlass = on
    if on {
      var c: UIButton.Configuration
      if #available(iOS 26.0, *) { c = .glass() } else { c = .gray() }
      c.cornerStyle = .capsule; c.baseForegroundColor = .label; c.contentInsets = .zero
      c.image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
      menuBtn.configuration = c
      UIView.performWithoutAnimation { effect = nil; icon.isHidden = true }
    } else {
      menuBtn.configuration = nil
      UIView.performWithoutAnimation { effect = GlassSpot.glass; icon.isHidden = icon.image == nil }
    }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2; layer.cornerCurve = .continuous
    icon.frame = contentView.bounds; word.frame = contentView.bounds; menuBtn.frame = contentView.bounds
    photo.frame = contentView.bounds; photo.layer.cornerRadius = bounds.height / 2
  }
}

final class CornerButton: UIView {
  struct Spot { var kind = "none", text = "", frame = CGRect.zero, image: UIImage? = nil }
  private let container: UIVisualEffectView = {
    let v = UIVisualEffectView(effect: nil)
    // (they join only when closer than this — at rest, 12 apart, they stay two)
    if #available(iOS 26.0, *) { let c = UIGlassContainerEffect(); c.spacing = 6; v.effect = c }
    return v
  }()
  let leftB = GlassSpot(), midB = GlassSpot(), cornerB = GlassSpot()
  private(set) var left = Spot(), mid = Spot(), corner = Spot()
  var onLeft: (() -> Void)?, onMid: ((String) -> Void)?, onCorner: ((String) -> Void)?
  // (what the self-test reads: the corner's ••• on a task page, else the middle one's kind)
  var kind: String { corner.kind == "more" ? "more" : mid.kind }
  // Mail's spring: inside it iPhone's glass changes shape, joins and parts with its own liquid squash and stretch
  static let duration: TimeInterval = 0.42, bounce: CGFloat = 0.22

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(container)
    [leftB, midB, cornerB].forEach { container.contentView.addSubview($0) }
    leftB.onTap = { [weak self] in self?.onLeft?() }
    midB.onTap = { [weak self] in guard let self = self else { return }; self.onMid?(self.mid.kind) }
    cornerB.onTap = { [weak self] in guard let self = self, self.corner.kind != "more" else { return }; self.onCorner?(self.corner.kind) }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); container.frame = bounds }
  // only the buttons take touches; the rest of the strip lets them through to the screen
  override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? {
    for b in [cornerB, midB, leftB] where b.shown {
      let q = b.convert(p, from: self)
      if b.bounds.contains(q) { return b.menuBtn.isHidden ? b : b.menuBtn }
    }
    return nil
  }

  // what a capsule with words needs; a place for the middle one (a capsule keeps the circle's right edge)
  func width(_ kind: String, _ text: String) -> CGFloat {
    if ["read", "unread", "done"].contains(kind) { return ceil((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width) + 32 }
    return 44
  }
  func place(_ kind: String, _ text: String, circle f: CGRect) -> CGRect { let w = width(kind, text); return CGRect(x: f.maxX - w, y: f.minY, width: w, height: f.height) }

  private func dress(_ b: GlassSpot, _ s: Spot, menu: UIMenu?) {
    let sym: String? = ["back": "chevron.left", "search": "magnifyingglass", "more": "ellipsis", "close": "xmark"][s.kind]
    b.icon.image = sym.map { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: s.kind == "back" ? 19 : s.kind == "close" ? 17 : 18, weight: .medium)) } ?? nil
    b.icon.isHidden = sym == nil
    b.word.text = ["read", "unread", "done"].contains(s.kind) ? s.text : nil
    b.word.textColor = s.kind == "done" ? .systemBlue : .label
    b.word.isHidden = b.word.text == nil
    b.photo.image = s.kind == "photo" ? s.image : nil
    b.photo.isHidden = s.kind != "photo"
    if s.kind != "more" { b.useButtonGlass(false) }
    b.menuBtn.menu = s.kind == "more" ? menu : nil
    b.menuBtn.isHidden = !(s.kind == "more" && menu != nil)
    b.accessibilityLabel = ["back": "Back", "search": "Search", "more": "More", "close": "Close search", "photo": "Me"][s.kind] ?? s.text
  }
  private func put(_ b: UIView, _ f: CGRect) { b.frame = f; b.layoutIfNeeded() }

  // to these three spots — iPhone's glass: it materialises, dematerialises, changes shape and moves inside Mail's
  // spring, and the glass container makes it liquid (no squash or stretch of our own)
  func go(left l: Spot, mid m: Spot, corner c: Spot, menu: UIMenu?, animated: Bool) {
    let oldCorner = corner
    let settled = c.kind == "more" && oldCorner.kind == "more" && c.frame == oldCorner.frame
    if !settled { cornerB.useButtonGlass(false) }
    let pairs: [(GlassSpot, Spot, Spot)] = [(leftB, left, l), (midB, mid, m), (cornerB, corner, c)]
    left = l; mid = m; corner = c
    var moves: [() -> Void] = []
    for (b, was, now) in pairs {
      let changed = was.kind != now.kind || was.text != now.text || was.image !== now.image
      // Search opening: Home's own bar starts exactly where 🔍 is and stretches out — 🔍 hands over to it at once;
      // closing, the bar shrinks back into that circle and 🔍 takes over there, in place
      if b === midB && was.kind == "search" && now.kind == "none" && c.kind == "close" { b.layer.removeAllAnimations(); b.effect = nil; b.contentView.alpha = 0; continue }
      if b === midB && now.kind == "search" && oldCorner.kind == "close" && !b.shown {
        put(b, now.frame); dress(b, now, menu: menu); b.effect = GlassSpot.glass; b.alpha = 1; b.contentView.alpha = 1
        continue
      }
      if now.kind == "none" {
        // going: 🔍 melts into the corner (moves onto it as its glass goes — the container joins them), others dissolve
        let into: CGRect? = b === midB && was.kind == "search" && c.kind != "none" ? c.frame : nil
        b.useButtonGlass(false)
        moves.append { if let f = into { self.put(b, f) }; b.effect = nil; b.contentView.alpha = 0 }
        continue
      }
      if !b.shown {
        // coming: 🔍 comes back out of the corner; the rest materialise where they go
        let from: CGRect? = b === midB && now.kind == "search" && oldCorner.kind != "none" && animated ? oldCorner.frame : nil
        put(b, from ?? now.frame)
        dress(b, now, menu: menu); b.contentView.alpha = 0
      } else if changed {
        if animated { UIView.transition(with: b.contentView, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.dress(b, now, menu: menu) } }
        else { dress(b, now, menu: menu) }
      } else { b.menuBtn.menu = now.kind == "more" ? menu : nil; b.menuBtn.isHidden = !(now.kind == "more" && menu != nil) }
      moves.append { self.put(b, now.frame); if b.effect == nil && !b.buttonGlass { b.effect = GlassSpot.glass }; b.alpha = 1; b.contentView.alpha = 1 }
    }
    let run = { moves.forEach { $0() }; self.container.contentView.layoutIfNeeded() }
    let rest: (Bool) -> Void = { [weak self] _ in guard let self = self, self.corner.kind == "more", self.corner.frame == c.frame else { return }; self.cornerB.useButtonGlass(true) }
    if !animated { run(); rest(true); return }
    if #available(iOS 17.0, *) { UIView.animate(springDuration: CornerButton.duration, bounce: CornerButton.bounce, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: run, completion: rest) }
    else { UIView.animate(withDuration: CornerButton.duration, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: run, completion: rest) }
  }
  // part way between two sets (the swipe back): t = 0 at `a`, 1 at `b`
  func between(_ a: (Spot, Spot, Spot), _ b: (Spot, Spot, Spot), _ t: CGFloat) {
    let t = max(0, min(1, t))
    func lerp(_ x: CGRect, _ y: CGRect) -> CGRect { CGRect(x: x.minX + (y.minX - x.minX) * t, y: x.minY + (y.minY - x.minY) * t, width: x.width + (y.width - x.width) * t, height: x.height + (y.height - x.height) * t) }
    cornerB.useButtonGlass(false)
    let rows: [(GlassSpot, Spot, Spot)] = [(leftB, a.0, b.0), (midB, a.1, b.1), (cornerB, a.2, b.2)]
    for (btn, x, y) in rows {
      btn.layer.removeAllAnimations()
      if x.kind == "none" && y.kind == "none" { btn.effect = nil; btn.contentView.alpha = 0; continue }
      if btn.effect == nil { btn.effect = GlassSpot.glass }
      if x.kind == "none" {
        put(btn, btn === midB && a.2.kind != "none" ? lerp(a.2.frame, y.frame) : y.frame)
        btn.alpha = t; btn.contentView.alpha = t
        if t > 0.5 { dress(btn, y, menu: nil) }
        continue
      }
      if y.kind == "none" {
        put(btn, btn === midB && b.2.kind != "none" ? lerp(x.frame, b.2.frame) : x.frame)
        btn.alpha = 1 - t; btn.contentView.alpha = 1 - t
        continue
      }
      put(btn, lerp(x.frame, y.frame)); btn.alpha = 1; btn.contentView.alpha = 1
      dress(btn, t < 0.5 ? x : y, menu: nil)
    }
  }
}

// ---------- on the app's screen ----------
extension Main {
  // the three spots now: the top task page's, else the shown screen's
  func cornerTarget(skipTop: Bool = false) -> (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot) {
    let pages = skipTop ? Array(taskPages.dropLast()) : taskPages
    if let p = pages.last {
      if p.cornerFrame.width == 0 { p.setNeedsLayout(); p.layoutIfNeeded() }   // (never aim at a page not laid out yet)
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
