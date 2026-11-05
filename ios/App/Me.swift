import UIKit
import LocalAuthentication
import UserNotifications
import UIKit.UIGestureRecognizerSubclass

/* The Me tab, the app's own (shell 33 — Haris 2026-11-03, from the approved mockups; "one build"):
   1. Me — Home's big title; your card (photo, name, role, email › My profile); WORK (Clients for the CD, Content
      calendar / plans, Client Assets, Team members, Trash — each for those who may, as the website's Me); THIS IPHONE
      (Shortcuts, Notifications, Face ID lock, Morning summary, Appearance); ABOUT (About); TEST SITE (owner, test site
      only: View as…, Back to me, Start fresh); Sign out; the version line.
   2. Appearance — Light and Dark as two little phone pictures with iPhone's tick, the Automatic switch under them.
   3. About — App updates (those who can update: the owner), Video hardware and Move data from the Mac app (owner),
      What's new in its own box that scrolls by itself. No Roll back (website and Mac app only).
   4. Shortcuts — the ways to do things quicker in the iPhone app.
   5. Team members — Active / Past, search, people by role, About roles (folds, as Inactive clients); Admins: + Add
      member, touch and hold someone for their sheet (the website's own menu).
   6. A member — their picture, name, role, email, where, status and open tasks; Admins: Manage, Creative Director.
   What's on them and who may do what comes from the page (phone.js NativeMe — the website's own rules); every change
   is done there, the website's way, its questions asked as iPhone's own (meAsk). Pages slide in from the right; ‹ or
   the swipe from the left edge goes back; tapping Me again goes back to Me with the back slide. Built to the standing
   rules: only what changed is drawn again, touch and hold as the comment cards, the shared top buttons, the motto. */

// ---------- pieces ----------

// a section's title above its group (iPhone Settings': small capitals, grey)
final class SetHead: UIView, HomeBlock {
  let label = UILabel()
  var first = false   // (the first thing on a page under Me: just under the bar — Haris 2026-11-03, too much room on top)
  override init(frame: CGRect) { super.init(frame: frame); label.font = .systemFont(ofSize: 13); label.textColor = .secondaryLabel; addSubview(label) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ t: String) { label.text = t.uppercased() }
  // (a link on its right — Overview's "All": Haris 2026-11-04)
  private var linkB: UIButton?
  var onLink: (() -> Void)?
  func link(_ t: String?) {
    if let t = t {
      let b = linkB ?? { let b = UIButton(type: .system); b.titleLabel?.font = .systemFont(ofSize: 15); b.addAction(UIAction { [weak self] _ in self?.onLink?() }, for: .touchUpInside); addSubview(b); linkB = b; return b }()
      b.setTitle(t, for: .normal); b.isHidden = false
    } else { linkB?.isHidden = true }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { first ? 24 : (label.text ?? "").isEmpty ? 20 : 44 }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = CGRect(x: 36, y: bounds.height - 25, width: bounds.width - 72, height: 18); linkB?.frame = CGRect(x: bounds.width - 120, y: bounds.height - 32, width: 100, height: 30); linkB?.contentHorizontalAlignment = .right }
}

// the small grey words under a group
final class SetFoot: UIView, HomeBlock {
  let label = UILabel()
  var center_ = false
  override init(frame: CGRect) { super.init(frame: frame); label.font = .systemFont(ofSize: 13); label.textColor = .secondaryLabel; label.numberOfLines = 0; addSubview(label) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ t: String, centered: Bool = false) { label.text = t; label.textAlignment = centered ? .center : .natural; center_ = centered; setNeedsLayout() }
  // (a coloured dot before it, centred — Me's sync status)
  func setDot(_ t: String, _ c: UIColor) {
    let a = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: c, .font: UIFont.systemFont(ofSize: 11)])
    a.append(NSAttributedString(string: t, attributes: [.foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: 13)]))
    if label.attributedText?.isEqual(to: a) != true { label.attributedText = a }
    label.textAlignment = .center; center_ = true; setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { (label.text ?? "").isEmpty ? 0 : ceil(label.sizeThatFits(CGSize(width: W - 72, height: 600)).height) + 14 }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = CGRect(x: 36, y: 7, width: bounds.width - 72, height: max(0, bounds.height - 14)) }
}

// the coloured square behind a row's symbol, as iPhone's Settings draws it (Haris 2026-11-03: "it has bevel / inner
// shadows"): a soft fall of the colour from a little lighter at the top to a little deeper at the bottom, a thin light
// rim along its top edge fading down, and a faint darker one along the bottom
final class SettingsIcon: UIView {
  // (as iPhone's own Settings icons, iOS 26 — measured from Haris's screenshot, 2026-11-03: the colour only a little
  //  lighter at the top than at the bottom, and a thin light glass edge inside, brightest along the top, fainter down
  //  the sides, light again along the bottom; no dark shading; corners ~27 % of the size, continuous)
  private let fill = CAGradientLayer(), rim = CAGradientLayer(), rimMask = CAShapeLayer()
  var color: UIColor = .systemGray { didSet { paint() } }
  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.masksToBounds = true; layer.cornerCurve = .continuous
    rim.colors = [UIColor.white.withAlphaComponent(0.42).cgColor, UIColor.white.withAlphaComponent(0.10).cgColor,
                  UIColor.white.withAlphaComponent(0.10).cgColor, UIColor.white.withAlphaComponent(0.30).cgColor]
    rim.locations = [0, 0.3, 0.7, 1]
    rimMask.fillColor = UIColor.clear.cgColor; rimMask.strokeColor = UIColor.black.cgColor; rimMask.lineWidth = 1
    rim.mask = rimMask
    [fill, rim].forEach { layer.addSublayer($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  private func paint() {
    var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    let c = color.resolvedColor(with: traitCollection)
    if c.getHue(&h, saturation: &sat, brightness: &b, alpha: &a) {
      let top = UIColor(hue: h, saturation: max(0, sat * 0.95), brightness: min(1, b * 1.03 + 0.01), alpha: a)
      let bottom = UIColor(hue: h, saturation: min(1, sat * 1.03), brightness: b * 0.97, alpha: a)
      fill.colors = [top.cgColor, bottom.cgColor]
    } else { fill.colors = [c.cgColor, c.cgColor] }
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) { super.traitCollectionDidChange(p); paint() }
  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    layer.cornerRadius = bounds.width * 0.27
    [fill, rim].forEach { $0.frame = bounds }
    rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: max(0, layer.cornerRadius - 0.5)).cgPath
    CATransaction.commit()
  }
}

// one row of a group, as iPhone's Settings: coloured icon (or a person's picture), name, a line under it, what's on
// at the right, ›, a switch, a small pill
struct SetItem {
  var key: String
  var title: String
  var sub = ""
  var value = ""
  var sym: String? = nil
  var col: UIColor? = nil
  var chevron = true
  var toggle: Bool? = nil
  var danger = false
  var pill: String? = nil          // (a key on the right — Shortcuts: @, #, Hold…)
  var badge: String? = nil         // (a small blue "New")
  var count = 0                    // (a red count before the ›, as iPhone's Settings — waiting for you; Haris 2026-11-04)
  var pills: [(String, UIColor)] = []
  var person: (photo: String?, ini: String, rgb: UIColor)? = nil
  var warn = false                 // (the line under it in orange — "Hasn't signed in yet")
  var dim = false
  var tap: (() -> Void)? = nil
  var hold: (() -> Void)? = nil
  var flip: ((Bool) -> Void)? = nil
  var sig: String { "\(title)|\(sub)|\(value)|\(sym ?? "")|\(col?.description ?? "")|\(chevron)|\(toggle != nil)|\(danger)|\(pill ?? "")|\(badge ?? "")|\(count)|\(pills.map { $0.0 }.joined(separator: ","))|\(person?.photo ?? "")|\(person?.ini ?? "")|\(warn)|\(dim)|\(tap != nil)|\(hold != nil)" }
}

final class SetRow: AssetTile {
  let icon = SettingsIcon(), sym = UIImageView(), pic = UIImageView(), name = UILabel(), sub = UILabel(), value = UILabel(), chev = UIImageView(), sw = UISwitch(), pill = UILabel(), badge = UILabel(), countL = UILabel()
  private var pillViews: [UILabel] = []
  var item: SetItem!
  private var photoPath: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    sym.tintColor = .white; sym.contentMode = .center; icon.addSubview(sym)
    pic.layer.cornerRadius = 18; pic.clipsToBounds = true; pic.contentMode = .scaleAspectFill
    name.font = .systemFont(ofSize: 17); sub.font = .systemFont(ofSize: 13); sub.textColor = .secondaryLabel; sub.numberOfLines = 2
    value.font = .systemFont(ofSize: 17); value.textColor = .secondaryLabel; value.textAlignment = .right
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)); chev.tintColor = .tertiaryLabel; chev.contentMode = .center
    pill.font = .monospacedSystemFont(ofSize: 13, weight: .semibold); pill.textColor = .secondaryLabel; pill.textAlignment = .center; pill.backgroundColor = .tertiarySystemFill; pill.layer.cornerRadius = 7; pill.clipsToBounds = true
    badge.font = .systemFont(ofSize: 11, weight: .bold); badge.textColor = .white; badge.textAlignment = .center; badge.backgroundColor = .systemBlue; badge.layer.cornerRadius = 9; badge.clipsToBounds = true
    sw.addAction(UIAction { [weak self] _ in guard let self = self else { return }; UISelectionFeedbackGenerator().selectionChanged(); self.item.flip?(self.sw.isOn) }, for: .valueChanged)
    countL.font = .systemFont(ofSize: 15, weight: .regular); countL.textColor = .white; countL.textAlignment = .center; countL.backgroundColor = .systemRed; countL.layer.cornerRadius = 12; countL.clipsToBounds = true
    [icon, pic, name, sub, value, chev, pill, badge, countL].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
    addSubview(sw)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ it: SetItem, look L: HomeLook) {
    item = it
    icon.isHidden = it.sym == nil; icon.color = it.col ?? .systemGray
    sym.image = it.sym.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)) }   // (as big in its square as Settings' own)
    name.text = it.title; name.textColor = it.danger ? .systemRed : L.title
    sub.text = it.sub; sub.isHidden = it.sub.isEmpty; sub.textColor = it.warn ? .systemOrange : .secondaryLabel
    value.text = it.value; value.isHidden = it.value.isEmpty
    chev.isHidden = !it.chevron || it.toggle != nil
    sw.isHidden = it.toggle == nil; if let on = it.toggle { sw.setOn(on, animated: false) }
    pill.text = it.pill.map { " \($0) " }; pill.isHidden = it.pill == nil
    badge.text = it.badge; badge.isHidden = it.badge == nil
    countL.text = it.count > 99 ? "99+" : "\(it.count)"; countL.isHidden = it.count <= 0
    pillViews.forEach { $0.removeFromSuperview() }
    pillViews = it.pills.map { p in
      let l = UILabel(); l.text = p.0; l.font = .systemFont(ofSize: 11, weight: .semibold); l.textColor = p.1; l.backgroundColor = p.1.withAlphaComponent(0.14)
      l.textAlignment = .center; l.layer.cornerRadius = 8; l.clipsToBounds = true; l.isUserInteractionEnabled = false; addSubview(l); return l
    }
    pic.isHidden = it.person == nil
    if let p = it.person {
      if p.photo != photoPath {
        photoPath = p.photo
        pic.image = roundPic(nil, initials: p.ini, color: p.rgb, size: 36)
        if let path = p.photo { FeedLoader.shared.image(path) { [weak self] img in guard let self = self, self.photoPath == path, let img = img else { return }; self.pic.image = roundPic(img, initials: nil, color: nil, size: 36) } }
      } else if p.photo == nil { pic.image = roundPic(nil, initials: p.ini, color: p.rgb, size: 36) }
    }
    alpha = it.dim ? 0.6 : 1
    pressable = it.tap != nil || it.hold != nil   // (only a row that does something shrinks under the finger)
    onTap = it.tap; onHold = it.hold
    accessibilityLabel = [it.title, it.sub, it.value].filter { !$0.isEmpty }.joined(separator: ", ")
    setNeedsLayout()
  }
  // the room it takes: one line, or two with the line under it (pills on a line of their own)
  static func height(_ it: SetItem, _ w: CGFloat) -> CGFloat {
    var h: CGFloat = it.person != nil ? 60 : 50
    if !it.sub.isEmpty { h += it.person != nil ? 0 : 12 }
    if !it.pills.isEmpty { h += 22 }
    return h
  }
  var leftInset: CGFloat { item.person != nil ? 64 : item.sym != nil ? 58 : 16 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    icon.frame = CGRect(x: 16, y: (H - 30) / 2, width: 30, height: 30); sym.frame = icon.bounds
    pic.frame = CGRect(x: 16, y: (H - 36) / 2, width: 36, height: 36)
    var right = W - 16
    if !sw.isHidden { let s = sw.intrinsicContentSize; sw.frame = CGRect(x: right - s.width, y: (H - s.height) / 2, width: s.width, height: s.height); right = sw.frame.minX - 10 }
    if !chev.isHidden { chev.frame = CGRect(x: right - 12, y: 0, width: 12, height: H); right -= 20 }
    if !countL.isHidden { let cw = max(24, ceil(countL.sizeThatFits(CGSize(width: 60, height: 24)).width) + 14); countL.frame = CGRect(x: right - cw, y: (H - 24) / 2, width: cw, height: 24); right = countL.frame.minX - 8 }
    if !pill.isHidden { let pw = ceil(pill.sizeThatFits(CGSize(width: 140, height: 24)).width) + 8; pill.frame = CGRect(x: right - pw, y: (H - 24) / 2, width: pw, height: 24); right = pill.frame.minX - 10 }
    if !value.isHidden { let vw = min(ceil(value.sizeThatFits(CGSize(width: 200, height: 24)).width), W * 0.4); value.frame = CGRect(x: right - vw, y: 0, width: vw, height: H); right = value.frame.minX - 8 }
    let x = leftInset
    let nameW = right - x
    let lines = (sub.isHidden ? 0 : 1) + (pillViews.isEmpty ? 0 : 1)
    let block: CGFloat = 21 + (sub.isHidden ? 0 : 17) + (pillViews.isEmpty ? 0 : 22)
    var y = (H - block) / 2
    let bw = badge.isHidden ? 0 : ceil(badge.sizeThatFits(CGSize(width: 60, height: 18)).width) + 12
    let tw = min(nameW - (bw > 0 ? bw + 8 : 0), ceil(name.sizeThatFits(CGSize(width: nameW, height: 22)).width))
    name.frame = CGRect(x: x, y: y, width: max(0, tw), height: 21)
    badge.frame = CGRect(x: name.frame.maxX + 8, y: y + 1.5, width: bw, height: 18)
    y += 21
    if !sub.isHidden { sub.frame = CGRect(x: x, y: y + 1, width: nameW, height: 16); y += 17 }
    if !pillViews.isEmpty {
      var px = x
      for l in pillViews { let w = ceil(l.sizeThatFits(CGSize(width: 200, height: 16)).width) + 12; l.frame = CGRect(x: px, y: y + 4, width: w, height: 16); px += w + 6 }
    }
    _ = lines
  }
}

// a rounded group of rows, each kept by its key while it shows the same (only what changed is made again)
final class SetGroup: UIView, HomeBlock {
  private let box = UIView()
  private var rows: [SetRow] = [], lines: [UIView] = [], made: [String: (SetRow, String)] = [:]
  override init(frame: CGRect) { super.init(frame: frame); box.layer.cornerRadius = 26; box.layer.cornerCurve = .continuous; box.clipsToBounds = true; addSubview(box) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ items: [SetItem], look L: HomeLook) {
    box.backgroundColor = L.card
    var keep = made; made = [:]
    var fresh: [SetRow] = []
    // (each key once — a second with the same key gets its own)
    var seen = Set<String>()
    let items = items.enumerated().map { i, x -> SetItem in var y = x; if !seen.insert(y.key).inserted { y.key += "#\(i)" }; return y }
    UIView.performWithoutAnimation {
      rows = items.map { it in
        let sig = it.sig + "|\(L.light)"
        if let k = keep.removeValue(forKey: it.key) {
          if k.1 == sig {
            made[it.key] = k
            k.0.item = it; k.0.onTap = it.tap; k.0.onHold = it.hold; k.0.pressable = it.tap != nil || it.hold != nil
            if let on = it.toggle, k.0.sw.isOn != on { k.0.sw.setOn(on, animated: true) }   // (a switch the page didn't change: back as it is)
            return k.0
          }
          k.0.removeFromSuperview()
        }
        let r = SetRow(); r.set(it, look: L); box.addSubview(r); made[it.key] = (r, sig); fresh.append(r); return r
      }
      keep.values.forEach { $0.0.removeFromSuperview() }
      while lines.count > max(0, rows.count - 1) { lines.removeLast().removeFromSuperview() }
      while lines.count < max(0, rows.count - 1) { let l = UIView(); l.backgroundColor = .separator; box.addSubview(l); lines.append(l) }
      if !fresh.isEmpty { place(); fresh.forEach { $0.layoutIfNeeded() } }
    }
    setNeedsLayout()
  }
  var isEmpty: Bool { rows.isEmpty }
  func blockHeight(_ W: CGFloat) -> CGFloat { rows.isEmpty ? 0 : rows.reduce(0) { $0 + SetRow.height($1.item, W - 32) } }
  private func place() {
    let w = max(0, bounds.width - 32), px = 1 / max(1, traitCollection.displayScale)
    var y: CGFloat = 0
    for (i, r) in rows.enumerated() {
      let h = SetRow.height(r.item, w)
      r.place(CGRect(x: 0, y: y, width: w, height: h))
      y += h
      if i < lines.count { lines[i].frame = CGRect(x: r.leftInset, y: y - px / 2, width: w - r.leftInset, height: px) }
    }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    box.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: blockHeight(bounds.width))
    place()
  }
}

// your card at the top of Me: photo, name, role, email, ›
final class MeCardBlock: AssetTile, HomeBlock {
  private let card = UIView(), pic = UIImageView(), name = UILabel(), role = UILabel(), mail = UILabel(), chev = UIImageView()
  var photo: UIImage? { pic.image }
  private var photoPath: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous
    pic.layer.cornerRadius = 31; pic.clipsToBounds = true
    name.font = .systemFont(ofSize: 21, weight: .semibold); role.font = .systemFont(ofSize: 15); role.textColor = .secondaryLabel
    mail.font = .systemFont(ofSize: 14); mail.textColor = .secondaryLabel; mail.lineBreakMode = .byTruncatingMiddle
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)); chev.tintColor = .tertiaryLabel; chev.contentMode = .center
    [card, pic, name, role, mail, chev].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
    MePhoto.shared.watch { [weak self] in self?.paintPic() }
  }
  required init?(coder: NSCoder) { fatalError() }
  private var ini = "", rgb: UIColor = .systemGray
  func set(_ c: [String: Any], look L: HomeLook) {
    card.backgroundColor = L.card
    name.text = c["name"] as? String; name.textColor = L.title
    role.text = c["role"] as? String; mail.text = c["email"] as? String
    ini = c["ini"] as? String ?? ""; rgb = NativeSheetVC.color(c["rgb"]) ?? .systemGray
    MePhoto.shared.who(ini, rgb)
    paintPic()
    accessibilityLabel = "\(name.text ?? ""), \(role.text ?? ""), My profile"
  }
  private func paintPic() { pic.image = MePhoto.shared.picture(62) ?? roundPic(nil, initials: ini, color: rgb, size: 62) }
  func blockHeight(_ W: CGFloat) -> CGFloat { 96 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    card.frame = CGRect(x: 16, y: 0, width: W - 32, height: 96)
    pic.frame = CGRect(x: 32, y: 17, width: 62, height: 62)
    let x: CGFloat = 108, w = W - 16 - 36 - x
    name.frame = CGRect(x: x, y: 18, width: w, height: 25); role.frame = CGRect(x: x, y: 44, width: w, height: 18); mail.frame = CGRect(x: x, y: 63, width: w, height: 17)
    chev.frame = CGRect(x: W - 16 - 30, y: 0, width: 14, height: 96)
  }
}

// Appearance: Light and Dark as two little phones (a tiny Home: cards, the +, the tab bar), iPhone's tick under the
// chosen one; under them the Automatic switch and today's times
final class ThemeBlock: UIView, HomeBlock {
  var onPick: ((String) -> Void)?
  private let card = UIView(), autoRow = UIView(), autoName = UILabel(), sw = UISwitch(), line = UIView(), times = UILabel(), timesSub = UILabel(), sep2 = UIView()
  private var minis: [(UIControl, UIView, UILabel, UIImageView)] = []
  private var mode = "auto", now = "light"
  override init(frame: CGRect) {
    super.init(frame: frame)
    card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
    addSubview(card)
    for (k, label) in [("light", "Light"), ("dark", "Dark")] {
      let c = UIControl(); c.accessibilityLabel = label; c.isAccessibilityElement = true; c.accessibilityTraits = .button
      let frameV = UIView(); frameV.layer.cornerRadius = 17; frameV.layer.cornerCurve = .continuous; frameV.layer.borderWidth = 2.5; frameV.isUserInteractionEnabled = false
      let scr = ThemeBlock.screen(k == "dark"); scr.tag = 9; frameV.addSubview(scr)
      let l = UILabel(); l.text = label; l.font = .systemFont(ofSize: 15, weight: .medium); l.textAlignment = .center
      let tick = UIImageView(); tick.contentMode = .scaleAspectFit
      [frameV, l, tick].forEach { $0.isUserInteractionEnabled = false; c.addSubview($0) }
      _ = PressShrink.add(to: c)
      c.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onPick?(k) }, for: .touchUpInside)
      card.addSubview(c)
      minis.append((c, frameV, l, tick))
    }
    autoName.text = "Automatic"; autoName.font = .systemFont(ofSize: 17)
    sw.addAction(UIAction { [weak self] _ in guard let self = self else { return }; UISelectionFeedbackGenerator().selectionChanged(); self.onPick?(self.sw.isOn ? "auto" : self.now) }, for: .valueChanged)
    times.font = .systemFont(ofSize: 17); times.text = "Light from sunrise, dark from sunset"
    timesSub.font = .systemFont(ofSize: 13); timesSub.textColor = .secondaryLabel; timesSub.numberOfLines = 2
    line.backgroundColor = .separator; sep2.backgroundColor = .separator
    [line, autoName, sw, sep2, times, timesSub].forEach { card.addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  // a tiny Home in light or dark
  private static func screen(_ dark: Bool) -> UIView {
    let v = UIView(); v.layer.cornerRadius = 12; v.layer.cornerCurve = .continuous; v.clipsToBounds = true
    v.backgroundColor = dark ? SplashView.hex(0x0c0d0f) : SplashView.hex(0xf2f2f7)
    let card = dark ? SplashView.hex(0x1e1f24) : .white
    let parts: [(CGRect, UIColor, CGFloat)] = [
      (CGRect(x: 7, y: 12, width: 38, height: 7), dark ? SplashView.hex(0x3a3b40) : SplashView.hex(0xc7c7cc), 3),
      (CGRect(x: 7, y: 27, width: 62, height: 16), card, 5), (CGRect(x: 7, y: 48, width: 62, height: 16), card, 5), (CGRect(x: 7, y: 69, width: 62, height: 16), card, 5),
      (CGRect(x: 47, y: 112, width: 22, height: 8), dark ? SplashView.hex(0x2b2c31) : .white, 4),
      (CGRect(x: 8, y: 125, width: 60, height: 12), dark ? SplashView.hex(0x2a2b30) : SplashView.hex(0xe4e4ea), 6),
    ]
    for (r, c, rad) in parts { let p = UIView(frame: r); p.backgroundColor = c; p.layer.cornerRadius = rad; v.addSubview(p) }
    return v
  }
  func set(mode m: String, now n: String, times t: String, look L: HomeLook) {
    mode = m; now = n
    card.backgroundColor = L.card; autoName.textColor = L.title; times.textColor = L.title
    let shown = m == "auto" ? n : m
    for (i, x) in minis.enumerated() {
      let k = i == 0 ? "light" : "dark", on = k == shown
      x.1.layer.borderColor = on ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
      x.2.textColor = L.title
      x.3.image = UIImage(systemName: on ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
      x.3.tintColor = on ? .systemBlue : .tertiaryLabel
      x.0.accessibilityTraits = on ? [.button, .selected] : .button
    }
    if sw.isOn != (m == "auto") { sw.setOn(m == "auto", animated: window != nil) }
    timesSub.text = "Today: \(t) (Dubai)"
    let showTimes = m == "auto"
    times.isHidden = !showTimes; timesSub.isHidden = !showTimes; sep2.isHidden = !showTimes
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { 236 + 52 + (mode == "auto" ? 12 + 22 + 2 + subH(W) + 12 : 0) }
  private func subH(_ W: CGFloat) -> CGFloat { ceil(timesSub.sizeThatFits(CGSize(width: W - 64, height: 200)).height) }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, px = 1 / max(1, traitCollection.displayScale)
    card.frame = CGRect(x: 16, y: 0, width: W - 32, height: blockHeight(W))
    let cw = card.bounds.width, gap: CGFloat = 56, mw: CGFloat = 82
    let x0 = (cw - (mw * 2 + gap)) / 2
    for (i, x) in minis.enumerated() {
      let cx = x0 + CGFloat(i) * (mw + gap)
      x.0.bounds = CGRect(x: 0, y: 0, width: mw, height: 214); x.0.center = CGPoint(x: cx + mw / 2, y: 22 + 107)
      x.1.frame = CGRect(x: 0, y: 0, width: mw, height: 150); x.1.viewWithTag(9)?.frame = x.1.bounds.insetBy(dx: 3, dy: 3)
      x.2.frame = CGRect(x: -10, y: 158, width: mw + 20, height: 20)
      x.3.frame = CGRect(x: (mw - 24) / 2, y: 186, width: 24, height: 24)
    }
    line.frame = CGRect(x: 16, y: 236 - px / 2, width: cw - 16, height: px)
    let s = sw.intrinsicContentSize
    autoName.frame = CGRect(x: 16, y: 236, width: cw - 32 - s.width, height: 52)
    sw.frame = CGRect(x: cw - 16 - s.width, y: 236 + (52 - s.height) / 2, width: s.width, height: s.height)
    sep2.frame = CGRect(x: 16, y: 288 - px / 2, width: cw - 16, height: px)
    // (the line and the grey one under it close together, as a Settings row's two lines — Haris 2026-11-03)
    times.frame = CGRect(x: 16, y: 288 + 12, width: cw - 32, height: 22)
    timesSub.frame = CGRect(x: 16, y: times.frame.maxY + 2, width: cw - 32, height: subH(W))
  }
}

// a card of words, lines and a button (App updates, Video hardware, Move data from the Mac app): made again only when
// what it shows changed
final class InfoCard: UIView, HomeBlock {
  enum Part { case status(String, UIColor), kicker(String), big(String), kv(String, String), button(String, Bool, Bool, () -> Void), note(String), title(String, String) }
  private let card = UIView()
  private var views: [(UIView, CGFloat)] = []
  private var sig = ""
  override init(frame: CGRect) { super.init(frame: frame); card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous; addSubview(card) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ parts: [Part], sig s: String, look L: HomeLook) {
    card.backgroundColor = L.card
    guard s + "|\(L.light)" != sig else { return }
    sig = s + "|\(L.light)"
    UIView.performWithoutAnimation {
      views.forEach { $0.0.removeFromSuperview() }
      views = parts.map { p -> (UIView, CGFloat) in
        switch p {
        case .title(let sym, let t):
          let l = UILabel(); let a = NSMutableAttributedString()
          if let img = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)) { a.append(NSAttributedString(attachment: NSTextAttachment(image: img.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)))); a.append(NSAttributedString(string: "  ")) }
          a.append(NSAttributedString(string: t, attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: L.title]))
          l.attributedText = a; return (l, 30)
        case .status(let t, let c): let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: 16, weight: .semibold); l.textColor = c; l.numberOfLines = 2; return (l, 30)
        case .kicker(let t): let l = UILabel(); l.text = t.uppercased(); l.font = .systemFont(ofSize: 12, weight: .bold); l.textColor = .systemBlue; return (l, 18)
        case .big(let t): let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: 20, weight: .bold); l.textColor = L.title; l.numberOfLines = 2; return (l, 30)
        case .kv(let k, let v):
          let r = UIView(); let a = UILabel(), b = UILabel()
          a.text = k; a.font = .systemFont(ofSize: 16); a.textColor = .secondaryLabel
          b.text = v; b.font = .systemFont(ofSize: 16, weight: .semibold); b.textColor = L.title; b.textAlignment = .right
          a.tag = 1; b.tag = 2; r.addSubview(a); r.addSubview(b)
          let sep = UIView(); sep.backgroundColor = .separator; sep.tag = 3; r.addSubview(sep)
          return (r, 40)
        case .button(let t, let primary, let enabled, let run):
          var c = UIButton.Configuration.filled()
          c.title = t; c.cornerStyle = .large
          c.baseBackgroundColor = primary ? .systemBlue : UIColor.systemBlue.withAlphaComponent(0.12); c.baseForegroundColor = primary ? .white : .systemBlue
          c.attributedTitle = AttributedString(t, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16, weight: .semibold)]))
          let b = UIButton(configuration: c); b.isEnabled = enabled
          b.addAction(UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); run() }, for: .touchUpInside)
          return (b, 58)
        case .note(let t): let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: 13); l.textColor = .secondaryLabel; l.numberOfLines = 0; return (l, -1)
        }
      }
      views.forEach { card.addSubview($0.0) }
      layoutCard()
    }
    setNeedsLayout()
  }
  private func heightOf(_ v: (UIView, CGFloat), _ w: CGFloat) -> CGFloat { v.1 >= 0 ? v.1 : ceil((v.0 as? UILabel)?.sizeThatFits(CGSize(width: w, height: 800)).height ?? 0) + 8 }
  // (the room under it, as between Settings' groups — cards one after another were stuck together, Haris 2026-11-03)
  static let gap: CGFloat = 20
  private func cardH(_ W: CGFloat) -> CGFloat { views.isEmpty ? 0 : views.reduce(28) { $0 + heightOf($1, W - 64) } }
  func blockHeight(_ W: CGFloat) -> CGFloat { views.isEmpty ? 0 : cardH(W) + InfoCard.gap }
  private func layoutCard() {
    let W = bounds.width, w = W - 64
    card.frame = CGRect(x: 16, y: 0, width: W - 32, height: cardH(W))
    var y: CGFloat = 14
    let px = 1 / max(1, traitCollection.displayScale)
    for (i, v) in views.enumerated() {
      let h = heightOf(v, w)
      if v.0 is UIButton { v.0.frame = CGRect(x: 16, y: y + 8, width: w, height: 46) }
      else { v.0.frame = CGRect(x: 16, y: y, width: w, height: h) }
      if v.1 == 40 {
        v.0.viewWithTag(1)?.frame = CGRect(x: 0, y: 0, width: w * 0.5, height: 40); v.0.viewWithTag(2)?.frame = CGRect(x: w * 0.4, y: 0, width: w * 0.6, height: 40)
        let prevKV = i > 0 && views[i - 1].1 == 40
        v.0.viewWithTag(3)?.frame = CGRect(x: 0, y: 0, width: w, height: px); v.0.viewWithTag(3)?.isHidden = !prevKV
      }
      y += h
    }
  }
  override func layoutSubviews() { super.layoutSubviews(); layoutCard() }
}

// What's new: the release notes in their own rounded box that scrolls by itself (a scroll bar, a soft fade at the end)
final class NotesBox: UIView, HomeBlock {
  let text = UITextView()
  private let card = UIView(), fade = CAGradientLayer()
  var fill: CGFloat = 0   // (the room it has, to the bottom of the page)
  private var sig = ""
  override init(frame: CGRect) {
    super.init(frame: frame)
    card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
    text.isEditable = false; text.isSelectable = true; text.backgroundColor = .clear; text.showsVerticalScrollIndicator = true
    text.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 26, right: 12)
    text.alwaysBounceVertical = false
    card.addSubview(text); card.layer.addSublayer(fade); addSubview(card)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(name: String, date: String, notes: String, look L: HomeLook) {
    card.backgroundColor = L.card
    fade.colors = [L.card.withAlphaComponent(0).cgColor, L.card.cgColor]
    let s = "\(name)|\(date)|\(notes)|\(L.light)"
    guard s != sig else { return }
    sig = s
    text.attributedText = NotesBox.render(name: name, date: date, notes: notes, color: L.title)
    setNeedsLayout()
  }
  // "## Heading", "- point", **bold**, `code` — as the website's notesHTML
  static func render(name: String, date: String, notes: String, color: UIColor) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let body = UIFont.systemFont(ofSize: 15), bold = UIFont.systemFont(ofSize: 15, weight: .semibold)
    func inline(_ t: String, _ font: UIFont) -> NSAttributedString {
      let a = NSMutableAttributedString()
      var rest = Substring(t); var b = false
      while !rest.isEmpty {
        if let r = rest.range(of: "**") { a.append(NSAttributedString(string: String(rest[..<r.lowerBound]).replacingOccurrences(of: "`", with: ""), attributes: [.font: b ? bold : font, .foregroundColor: color])); b.toggle(); rest = rest[r.upperBound...] }
        else { a.append(NSAttributedString(string: String(rest).replacingOccurrences(of: "`", with: ""), attributes: [.font: b ? bold : font, .foregroundColor: color])); break }
      }
      return a
    }
    let head = NSMutableParagraphStyle(); head.paragraphSpacing = 2
    out.append(NSAttributedString(string: name, attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .bold), .foregroundColor: color, .paragraphStyle: head]))
    if !date.isEmpty { out.append(NSAttributedString(string: "  " + date, attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.secondaryLabel])) }
    out.append(NSAttributedString(string: "\n"))
    let bullet = NSMutableParagraphStyle(); bullet.headIndent = 16; bullet.firstLineHeadIndent = 2; bullet.paragraphSpacing = 4
    bullet.tabStops = [NSTextTab(textAlignment: .left, location: 16)]
    let para = NSMutableParagraphStyle(); para.paragraphSpacing = 6
    let h4 = NSMutableParagraphStyle(); h4.paragraphSpacingBefore = 8; h4.paragraphSpacing = 2
    let lines = notes.components(separatedBy: .newlines)
    var any = false
    for l in lines {
      let t = l.trimmingCharacters(in: .whitespaces)
      if t.isEmpty { continue }
      any = true
      if t.hasPrefix("- ") || t.hasPrefix("* ") {
        let a = NSMutableAttributedString(string: "•\t", attributes: [.font: body, .foregroundColor: color]); a.append(inline(String(t.dropFirst(2)), body)); a.append(NSAttributedString(string: "\n"))
        a.addAttribute(.paragraphStyle, value: bullet, range: NSRange(location: 0, length: a.length)); out.append(a)
      } else if t.hasPrefix("#") {
        let a = NSMutableAttributedString(attributedString: inline(t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces), UIFont.systemFont(ofSize: 15, weight: .bold))); a.append(NSAttributedString(string: "\n"))
        a.addAttribute(.paragraphStyle, value: h4, range: NSRange(location: 0, length: a.length)); out.append(a)
      } else {
        let a = NSMutableAttributedString(attributedString: inline(t, body)); a.append(NSAttributedString(string: "\n"))
        a.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: a.length)); out.append(a)
      }
    }
    if !any { out.append(NSAttributedString(string: "Improvements and fixes.", attributes: [.font: body, .foregroundColor: color])) }
    return out
  }
  private var contentH: CGFloat { ceil(text.sizeThatFits(CGSize(width: max(100, bounds.width - 32), height: .greatestFiniteMagnitude)).height) }
  func blockHeight(_ W: CGFloat) -> CGFloat {
    let ch = ceil(text.sizeThatFits(CGSize(width: W - 32, height: .greatestFiniteMagnitude)).height)
    return max(min(ch, 260), fill)
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    card.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: bounds.height)
    text.frame = card.bounds
    let scrolls = contentH > card.bounds.height + 1
    text.isScrollEnabled = true; text.alwaysBounceVertical = scrolls
    fade.frame = CGRect(x: 0, y: card.bounds.height - 34, width: card.bounds.width, height: 34)
    fade.isHidden = !scrolls
    if scrolls { DispatchQueue.main.async { [weak self] in self?.text.flashScrollIndicators() } }
  }
}

// Team members: Active · N / Past · N as iPhone's segmented control
final class SegBlock: UIView, HomeBlock {
  let seg = UISegmentedControl(items: ["Active", "Past"])
  var onPick: ((Int) -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    seg.selectedSegmentIndex = 0
    seg.addAction(UIAction { [weak self] _ in guard let self = self else { return }; UISelectionFeedbackGenerator().selectionChanged(); self.onPick?(self.seg.selectedSegmentIndex) }, for: .valueChanged)
    addSubview(seg)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ a: String, _ b: String, _ i: Int) {
    if seg.titleForSegment(at: 0) != a { seg.setTitle(a, forSegmentAt: 0) }
    if seg.titleForSegment(at: 1) != b { seg.setTitle(b, forSegmentAt: 1) }
    if seg.selectedSegmentIndex != i { seg.selectedSegmentIndex = i }
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { 48 }
  override func layoutSubviews() { super.layoutSubviews(); seg.frame = CGRect(x: 16, y: 6, width: bounds.width - 32, height: 34) }
}

// About roles: the heading with the turning chevron (closed at first, as Inactive clients), the role guide under it
final class RoleGuide: UIView, HomeBlock {
  private let more = UIButton(type: .system), chev = UIImageView(), box = UIView()
  private var rows: [UIView] = []
  private var open = false
  private var sig = ""
  override init(frame: CGRect) {
    super.init(frame: frame)
    box.layer.cornerRadius = 26; box.layer.cornerCurve = .continuous; box.clipsToBounds = true; box.alpha = 0
    more.contentHorizontalAlignment = .leading
    more.setAttributedTitle(NSAttributedString(string: "About roles", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel]), for: .normal)
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)); chev.tintColor = .secondaryLabel; chev.contentMode = .center; chev.isUserInteractionEnabled = false
    more.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.open.toggle()
      let o = self.open
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.chev.transform = o ? CGAffineTransform(rotationAngle: .pi / 2) : .identity }
      (self.superview?.superview as? HomeView)?.relayout()
      UIView.animate(withDuration: 0.25, delay: o ? 0.1 : 0, options: [.curveEaseOut, .allowUserInteraction]) { self.box.alpha = o ? 1 : 0 }
    }, for: .touchUpInside)
    addSubview(box); addSubview(more); addSubview(chev)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ guide: [[Any]], look L: HomeLook) {
    box.backgroundColor = L.card
    let s = guide.map { "\($0.first ?? "")|\($0.last ?? "")" }.joined(separator: "§") + "|\(L.light)"
    guard s != sig else { return }
    sig = s
    UIView.performWithoutAnimation {
      rows.forEach { $0.removeFromSuperview() }
      rows = guide.map { g in
        let v = UIView()
        let pill = UILabel(), t = UILabel()
        let col = NativeSheetVC.color(g.count > 1 ? g[1] : nil) ?? .systemGray
        pill.text = g.first as? String; pill.font = .systemFont(ofSize: 12, weight: .semibold); pill.textColor = col; pill.backgroundColor = col.withAlphaComponent(0.14)
        pill.textAlignment = .center; pill.layer.cornerRadius = 9; pill.clipsToBounds = true; pill.tag = 1
        t.text = g.last as? String; t.font = .systemFont(ofSize: 14); t.textColor = L.title; t.numberOfLines = 0; t.tag = 2
        v.addSubview(pill); v.addSubview(t); box.addSubview(v); return v
      }
    }
    setNeedsLayout()
  }
  private func rowH(_ v: UIView, _ w: CGFloat) -> CGFloat { 22 + 6 + ceil((v.viewWithTag(2) as? UILabel)?.sizeThatFits(CGSize(width: w, height: 600)).height ?? 0) + 14 }
  private var boxH: CGFloat { let w = bounds.width - 64; return rows.reduce(12) { $0 + rowH($1, w) } }
  func blockHeight(_ W: CGFloat) -> CGFloat { let w = W - 64; return 50 + (open ? rows.reduce(12) { $0 + rowH($1, w) } + 6 : 0) }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, w = W - 64
    more.frame = CGRect(x: 36, y: 6, width: W - 72, height: 44)
    let tw = ceil(more.attributedTitle(for: .normal)?.size().width ?? 0)
    chev.bounds = CGRect(x: 0, y: 0, width: 16, height: 16); chev.center = CGPoint(x: more.frame.minX + tw + 12, y: more.frame.midY)
    box.frame = CGRect(x: 16, y: 50, width: W - 32, height: open ? boxH : 0)
    var y: CGFloat = 12
    for v in rows {
      let h = rowH(v, w)
      v.frame = CGRect(x: 16, y: y, width: w, height: h)
      if let p = v.viewWithTag(1) as? UILabel { let pw = ceil(p.sizeThatFits(CGSize(width: w, height: 22)).width) + 16; p.frame = CGRect(x: 0, y: 0, width: min(pw, w), height: 22) }
      v.viewWithTag(2)?.frame = CGRect(x: 0, y: 28, width: w, height: h - 28 - 14)
      y += h
    }
  }
}

// a member's page: their picture, name, role and the extras
final class MemberHead: UIView, HomeBlock {
  private let pic = UIImageView(), name = UILabel(), role = UILabel()
  private var pills: [UILabel] = []
  private var photoPath: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.layer.cornerRadius = 46; pic.clipsToBounds = true
    name.font = .systemFont(ofSize: 24, weight: .bold); name.textAlignment = .center
    role.font = .systemFont(ofSize: 15); role.textColor = .secondaryLabel; role.textAlignment = .center
    [pic, name, role].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ p: [String: Any], look L: HomeLook) {
    name.text = p["name"] as? String; name.textColor = L.title
    role.text = p["designation"] as? String
    let ini = p["ini"] as? String ?? "", rgb = NativeSheetVC.color(p["rgb"]) ?? .systemGray
    let ph = p["photo"] as? String
    if ph != photoPath || pic.image == nil {
      photoPath = ph
      pic.image = roundPic(nil, initials: ini, color: rgb, size: 92)
      if let path = ph { FeedLoader.shared.image(path) { [weak self] img in guard let self = self, self.photoPath == path, let img = img else { return }; self.pic.image = roundPic(img, initials: nil, color: nil, size: 92) } }
    }
    pills.forEach { $0.removeFromSuperview() }
    pills = ((p["pills"] as? [[String: Any]]) ?? []).map { x in
      let c = NativeSheetVC.color(x["c"]) ?? .systemGray
      let l = UILabel(); l.text = x["t"] as? String; l.font = .systemFont(ofSize: 12, weight: .semibold); l.textColor = c; l.backgroundColor = c.withAlphaComponent(0.14)
      l.textAlignment = .center; l.layer.cornerRadius = 10; l.clipsToBounds = true; addSubview(l); return l
    }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { 92 + 12 + 30 + 20 + (pills.isEmpty ? 0 : 30) + 10 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    pic.frame = CGRect(x: (W - 92) / 2, y: 0, width: 92, height: 92)
    name.frame = CGRect(x: 16, y: 104, width: W - 32, height: 30)
    role.frame = CGRect(x: 16, y: 134, width: W - 32, height: 20)
    let ws = pills.map { ceil($0.sizeThatFits(CGSize(width: 220, height: 20)).width) + 16 }
    var x = (W - (ws.reduce(0, +) + CGFloat(max(0, ws.count - 1)) * 6)) / 2
    for (i, l) in pills.enumerated() { l.frame = CGRect(x: x, y: 162, width: ws[i], height: 20); x += ws[i] + 6 }
  }
}

// a page's search and filters as one, stuck under the bar once they reach it (HomeView.pinHead)
final class PinStack: UIView, HomeBlock {
  private var parts: [UIView] = []
  func set(_ v: [UIView]) { if v.count != parts.count || zip(v, parts).contains(where: { $0 !== $1 }) { parts.forEach { $0.removeFromSuperview() }; parts = v; v.forEach { addSubview($0) } }; setNeedsLayout() }
  func blockHeight(_ W: CGFloat) -> CGFloat { parts.reduce(0) { $0 + (($1 as? HomeBlock)?.blockHeight(W) ?? 0) } }
  override func layoutSubviews() {
    super.layoutSubviews()
    var y: CGFloat = 0
    for v in parts { let h = (v as? HomeBlock)?.blockHeight(bounds.width) ?? 0; v.frame = CGRect(x: 0, y: y, width: bounds.width, height: h); y += h }
  }
}

// Mail's category buttons in a row that scrolls sideways when they don't all fit (the Trash has six)
final class CatsBlock: UIView, HomeBlock {
  let cats: MailCats
  private let sc = UIScrollView()
  var onPick: ((Int) -> Void)?
  init(items: [MailCats.Item]) {
    cats = MailCats(items: items)
    super.init(frame: .zero)
    sc.showsHorizontalScrollIndicator = false; sc.alwaysBounceHorizontal = false
    cats.gestureRecognizers?.forEach { if $0 is UISwipeGestureRecognizer { $0.isEnabled = false } }   // (the row scrolls instead)
    cats.onPick = { [weak self] i in UISelectionFeedbackGenerator().selectionChanged(); self?.cats.choose(i, animated: true); self?.fit(); self?.onPick?(i) }
    sc.addSubview(cats); addSubview(sc)
  }
  required init?(coder: NSCoder) { fatalError() }
  func choose(_ i: Int) { if i != cats.selected { cats.choose(i, animated: false); setNeedsLayout() } }
  func blockHeight(_ W: CGFloat) -> CGFloat { MailCats.H + 14 }
  private func fit() {
    let w = cats.widths.reduce(0, +) + CGFloat(max(0, cats.widths.count - 1)) * 9 + 32 + 120
    cats.frame = CGRect(x: 0, y: 0, width: max(bounds.width, w), height: MailCats.H)
    sc.contentSize = CGSize(width: max(bounds.width, cats.widths.reduce(0, +) + CGFloat(max(0, cats.widths.count - 1)) * 9 + 32), height: MailCats.H)
  }
  override func layoutSubviews() { super.layoutSubviews(); sc.frame = CGRect(x: 0, y: 4, width: bounds.width, height: MailCats.H); fit() }
}

// one rounded group of the Trash's rows, each kept by its id while it shows the same
final class TrashGroup: UIView, HomeBlock {
  private let box = UIView()
  private var rows: [TrashRow] = [], made: [String: (TrashRow, String)] = [:], lines: [UIView] = []
  var onEvent: (([String: Any]) -> Void)?
  override init(frame: CGRect) { super.init(frame: frame); box.layer.cornerRadius = 26; box.layer.cornerCurve = .continuous; box.clipsToBounds = true; addSubview(box) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ items: [[String: Any]], look L: HomeLook) {
    box.backgroundColor = L.card
    var keep = made; made = [:]
    var fresh: [TrashRow] = []
    UIView.performWithoutAnimation {
      rows = items.map { it in
        let id = it["id"] as? String ?? UUID().uuidString, sig = jsonString(it) + "|\(L.light)"
        if let k = keep.removeValue(forKey: id) { if k.1 == sig { made[id] = k; k.0.onEvent = { [weak self] e in self?.onEvent?(e) }; return k.0 }; k.0.removeFromSuperview() }
        let r = TrashRow(); r.set(it, look: L); r.onEvent = { [weak self] e in self?.onEvent?(e) }; box.addSubview(r); made[id] = (r, sig); fresh.append(r); return r
      }
      keep.values.forEach { $0.0.removeFromSuperview() }
      while lines.count > max(0, rows.count - 1) { lines.removeLast().removeFromSuperview() }
      while lines.count < max(0, rows.count - 1) { let l = UIView(); l.backgroundColor = .separator; box.addSubview(l); lines.append(l) }
      if !fresh.isEmpty { place(); fresh.forEach { $0.layoutIfNeeded() } }
    }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { rows.reduce(0) { $0 + $1.height(W - 32) } }
  private func place() {
    let w = max(0, bounds.width - 32), px = 1 / max(1, traitCollection.displayScale)
    var y: CGFloat = 0
    for (i, r) in rows.enumerated() {
      let h = r.height(w); r.place(CGRect(x: 0, y: y, width: w, height: h)); y += h
      if i < lines.count { box.bringSubviewToFront(lines[i]); lines[i].frame = CGRect(x: 58, y: y - px / 2, width: w - 58, height: px) }
    }
  }
  override func layoutSubviews() { super.layoutSubviews(); box.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: blockHeight(bounds.width)); place() }
}

// a row in the Trash: its kind's icon, name, kind · where · who · when, its files' pictures, days left; Mail's swipes —
// right: Restore (green), left: Delete forever (red, Super Admins); touch and hold: its sheet
final class TrashRow: AssetTile, UIGestureRecognizerDelegate {
  private let body = UIView(), icon = SettingsIcon(), sym = UIImageView(), name = UILabel(), sub = UILabel(), left = UILabel()
  private let restoreB = UIButton(type: .system), foreverB = UIButton(type: .system)
  // (each button's icon and word at their own width, never squeezed — clipped by the button while it opens, and faded in;
  //  Haris 2026-11-03: "Delete forever" wrapped letter by letter on a slow swipe)
  private let restoreC = UIView(), foreverC = UIView()
  private static let RW: CGFloat = 96, FW: CGFloat = 110
  private var chips: [UIImageView] = [], more = UILabel()
  private var it: [String: Any] = [:]
  var onEvent: (([String: Any]) -> Void)?
  private var canR = false, canF = false
  private var shift: CGFloat = 0 { didSet {
    body.transform = CGAffineTransform(translationX: shift, y: 0)
    restoreB.alpha = shift > 0.5 ? 1 : 0; foreverB.alpha = shift < -0.5 ? 1 : 0
    // (each button fills what the row has uncovered, as Mail's)
    let H = bounds.height
    restoreB.frame = CGRect(x: 0, y: 0, width: max(0, shift), height: H)
    foreverB.frame = CGRect(x: bounds.width + min(0, shift), y: 0, width: max(0, -shift), height: H)
    placeContent()
  } }
  // (the icon and word sit by the row's edge as it goes, at their own width; beyond the button's full width they stay
  //  centred in what's uncovered)
  private func placeContent() {
    let H = bounds.height, rw = restoreB.bounds.width, fw = foreverB.bounds.width
    let RW = TrashRow.RW, FW = TrashRow.FW
    restoreC.frame = CGRect(x: rw <= RW ? rw - RW : (rw - RW) / 2, y: 0, width: RW, height: H)
    foreverC.frame = CGRect(x: fw <= FW ? 0 : (fw - FW) / 2, y: 0, width: FW, height: H)
    restoreC.alpha = min(1, max(0, (rw - 24) / (RW * 0.6))); foreverC.alpha = min(1, max(0, (fw - 24) / (FW * 0.6)))
  }
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    for (b, cv, t, c, sy) in [(restoreB, restoreC, "Restore", UIColor.systemGreen, "arrow.uturn.backward"), (foreverB, foreverC, "Delete forever", UIColor.systemRed, "trash.fill")] {
      var cf = UIButton.Configuration.plain()
      // (square — only the group's own corners round it: the first row's top, the last row's bottom; Haris 2026-11-03)
      cf.background.backgroundColor = c; cf.background.cornerRadius = 0; cf.cornerStyle = .fixed
      b.configuration = cf; b.layer.cornerRadius = 0; b.alpha = 0; b.clipsToBounds = true; b.accessibilityLabel = t; addSubview(b)
      let iv = UIImageView(image: UIImage(systemName: sy, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))); iv.tintColor = .white; iv.contentMode = .center
      let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: 12, weight: .semibold); l.textColor = .white; l.textAlignment = .center; l.numberOfLines = 1
      iv.translatesAutoresizingMaskIntoConstraints = false; l.translatesAutoresizingMaskIntoConstraints = false
      cv.isUserInteractionEnabled = false; cv.addSubview(iv); cv.addSubview(l); b.addSubview(cv)
      NSLayoutConstraint.activate([iv.centerXAnchor.constraint(equalTo: cv.centerXAnchor), iv.bottomAnchor.constraint(equalTo: cv.centerYAnchor, constant: 1),
                                   l.centerXAnchor.constraint(equalTo: cv.centerXAnchor), l.topAnchor.constraint(equalTo: iv.bottomAnchor, constant: 5)])
    }
    restoreB.addAction(UIAction { [weak self] _ in self?.act("trRestore") }, for: .touchUpInside)
    foreverB.addAction(UIAction { [weak self] _ in self?.act("trForever") }, for: .touchUpInside)
    sym.tintColor = .white; sym.contentMode = .center; icon.addSubview(sym)
    name.font = .systemFont(ofSize: 17); name.numberOfLines = 2
    sub.font = .systemFont(ofSize: 13); sub.textColor = .secondaryLabel; sub.numberOfLines = 2
    left.font = .systemFont(ofSize: 13); left.textAlignment = .right
    more.font = .systemFont(ofSize: 12, weight: .semibold); more.textColor = .secondaryLabel
    [icon, name, sub, left, more].forEach { $0.isUserInteractionEnabled = false; body.addSubview($0) }
    body.isUserInteractionEnabled = false
    addSubview(body)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:))); pan.delegate = self; addGestureRecognizer(pan)
    onTap = { [weak self] in guard let self = self else { return }; if abs(self.shift) > 1 { self.close() } else { self.onEvent?(["ev": "trTap", "id": self.it["id"] ?? ""]) } }
    onHold = { [weak self] in guard let self = self else { return }; self.close(); self.onEvent?(["ev": "trHold", "id": self.it["id"] ?? ""]) }
  }
  required init?(coder: NSCoder) { fatalError() }
  private func act(_ ev: String) { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); onEvent?(["ev": ev, "id": it["id"] ?? ""]); close() }
  func set(_ x: [String: Any], look L: HomeLook) {
    it = x
    body.backgroundColor = L.card   // (the row itself covers the buttons under it until swiped)
    canR = (x["restore"] as? Bool) == true; canF = (x["forever"] as? Bool) == true
    icon.color = NativeSheetVC.color(x["col"]) ?? .systemGray
    sym.image = UIImage(systemName: x["sym"] as? String ?? "trash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    name.text = x["t"] as? String; name.textColor = L.title
    sub.text = x["s"] as? String
    left.text = x["left"] as? String
    let soon = (x["soon"] as? Bool) == true
    left.textColor = soon ? .systemRed : .secondaryLabel; left.font = .systemFont(ofSize: 13, weight: soon ? .semibold : .regular)
    chips.forEach { $0.removeFromSuperview() }
    chips = ((x["files"] as? [[String: Any]]) ?? []).map { f in
      let v = UIImageView(); v.layer.cornerRadius = 7; v.clipsToBounds = true; v.contentMode = .scaleAspectFill; v.backgroundColor = .tertiarySystemFill
      let ext = f["ext"] as? String ?? "FILE"
      let lab = UILabel(); lab.text = ext; lab.font = .systemFont(ofSize: 8.5, weight: .heavy); lab.textColor = .secondaryLabel; lab.textAlignment = .center; lab.frame = CGRect(x: 0, y: 0, width: 36, height: 36); v.addSubview(lab)
      if let pic = f["pic"] as? String { FeedLoader.shared.image(pic) { [weak v, weak lab] img in guard let img = img else { return }; v?.image = img; lab?.isHidden = true } }
      body.addSubview(v); return v
    }
    let m = x["more"] as? Int ?? 0
    more.text = m > 0 ? "+\(m) more" : nil; more.isHidden = m == 0
    accessibilityLabel = [name.text, sub.text, left.text].compactMap { $0 }.joined(separator: ", ")
    setNeedsLayout()
  }
  private func textW(_ w: CGFloat) -> CGFloat { w - 58 - 16 - 92 }
  func height(_ w: CGFloat) -> CGFloat {
    let tw = textW(w)
    let nh = min(42, ceil(name.sizeThatFits(CGSize(width: tw, height: 100)).height)), sh = min(32, ceil(sub.sizeThatFits(CGSize(width: tw + 92, height: 100)).height))
    return 11 + nh + 2 + sh + (chips.isEmpty ? 0 : 42) + 11
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    body.bounds = CGRect(origin: .zero, size: bounds.size); body.center = CGPoint(x: W / 2, y: H / 2)
    restoreB.frame = CGRect(x: 0, y: 0, width: max(0, shift), height: H); foreverB.frame = CGRect(x: W + min(0, shift), y: 0, width: max(0, -shift), height: H)
    placeContent()
    icon.frame = CGRect(x: 16, y: 13, width: 30, height: 30); sym.frame = icon.bounds
    let tw = textW(W)
    let nh = min(42, ceil(name.sizeThatFits(CGSize(width: tw, height: 100)).height))
    name.frame = CGRect(x: 58, y: 11, width: tw, height: nh)
    let lw: CGFloat = 84
    left.frame = CGRect(x: W - 16 - lw, y: 11, width: lw, height: 20)
    let sh = min(32, ceil(sub.sizeThatFits(CGSize(width: tw + 92, height: 100)).height))
    sub.frame = CGRect(x: 58, y: name.frame.maxY + 2, width: W - 58 - 16, height: sh)
    var x: CGFloat = 58
    for c in chips { c.frame = CGRect(x: x, y: sub.frame.maxY + 6, width: 36, height: 36); x += 41 }
    more.frame = CGRect(x: x + 2, y: sub.frame.maxY + 6, width: 80, height: 36)
  }
  // (sideways only: the list still scrolls)
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g.view === self, let p = g as? UIPanGestureRecognizer else { return super.gestureRecognizerShouldBegin(g) }
    let v = p.velocity(in: self)
    return abs(v.x) > abs(v.y) * 1.2 && ((v.x > 0 && (canR || shift < 0)) || (v.x < 0 && (canF || shift > 0)))
  }
  private var start: CGFloat = 0
  @objc private func pan(_ g: UIPanGestureRecognizer) {
    let W = bounds.width
    switch g.state {
    case .began: start = shift; cancelTracking(with: nil)
    case .changed:
      var x = start + g.translation(in: self).x
      if !canR { x = min(0, x) }; if !canF { x = max(0, x) }
      shift = x
    default:
      let v = g.velocity(in: self).x
      // (far enough — more than half the row — it does it, as Mail's full swipe; else it opens to its button or closes)
      if shift > W * 0.55 && canR { act("trRestore"); return }
      if shift < -W * 0.55 && canF { act("trForever"); return }
      let to: CGFloat = shift > 44 || (shift > 10 && v > 400) ? 96 : shift < -44 || (shift < -10 && v < -400) ? -110 : 0
      if to != 0 && abs(start) < 1 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      SwipeSpring.run(from: shift, to: to, velocity: v) { self.shift = to }
    }
  }
  func close() { SwipeSpring.run(from: shift, to: 0, velocity: 0) { self.shift = 0 } }
}

// My profile's top: your photo (or initials), Change photo (blue) and Remove (red), as iPhone's own
final class ProfileHead: UIView, HomeBlock {
  private let pic = UIImageView(), change = UIButton(type: .system), remove = UIButton(type: .system)
  private var photoPath: String?, ini = "", hasPhoto = false
  // (uploading: the photo dimmed with iPhone's spinner on it, until the new photo has come — Haris 2026-11-03)
  private let dim = UIView(), spin = UIActivityIndicatorView(style: .medium)
  private var busy = false, waitingNew = false
  var onChange: (() -> Void)?, onRemove: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.layer.cornerRadius = 48; pic.clipsToBounds = true
    change.titleLabel?.font = .systemFont(ofSize: 16); remove.titleLabel?.font = .systemFont(ofSize: 16)
    remove.setTitle("Remove", for: .normal); remove.tintColor = .systemRed
    change.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onChange?() }, for: .touchUpInside)
    remove.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .touchUpInside)
    [pic, change, remove].forEach { addSubview($0) }
    dim.backgroundColor = UIColor.black.withAlphaComponent(0.4); dim.layer.cornerRadius = 48; dim.alpha = 0; dim.isUserInteractionEnabled = false
    spin.color = .white; spin.hidesWhenStopped = true
    addSubview(dim); addSubview(spin)
  }
  private func setBusy(_ on: Bool) {
    if on { spin.startAnimating() } else { spin.stopAnimating() }
    UIView.animate(withDuration: 0.2) { self.dim.alpha = on ? 1 : 0 }
    change.isEnabled = !on; remove.isEnabled = !on
    UIView.performWithoutAnimation { change.setTitle(on ? "Uploading…" : hasPhoto ? "Change photo" : "Add photo", for: .normal); change.layoutIfNeeded() }
    setNeedsLayout()
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ p: [String: Any], look L: HomeLook) {
    hasPhoto = (p["hasPhoto"] as? Bool) == true
    let nowBusy = (p["photoBusy"] as? Bool) == true
    if nowBusy && !busy { busy = true; waitingNew = true; setBusy(true) }
    else if !nowBusy && busy { busy = false; if (p["photo"] as? String) == photoPath || p["photo"] == nil { waitingNew = false; setBusy(false) } }
    if !busy && !waitingNew { UIView.performWithoutAnimation { change.setTitle(hasPhoto ? "Change photo" : "Add photo", for: .normal); change.layoutIfNeeded() } }
    change.tintColor = .systemBlue
    remove.isHidden = !hasPhoto
    let i = p["ini"] as? String ?? "", rgb = NativeSheetVC.color(p["rgb"]) ?? .systemGray
    let ph = p["photo"] as? String
    if ph != photoPath || i != ini || pic.image == nil {
      photoPath = ph; ini = i
      pic.image = roundPic(nil, initials: i, color: rgb, size: 96)
      if let path = ph { FeedLoader.shared.image(path) { [weak self] img in
        guard let self = self, self.photoPath == path else { return }
        if let img = img { self.pic.image = roundPic(img, initials: nil, color: nil, size: 96) }
        if self.waitingNew && !self.busy { self.waitingNew = false; self.setBusy(false) }   // (the new one is there)
      } } else if waitingNew && !busy { waitingNew = false; setBusy(false) }
    }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { 8 + 96 + 6 + 34 + 4 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    pic.frame = CGRect(x: (W - 96) / 2, y: 8, width: 96, height: 96)
    dim.frame = pic.frame; spin.center = CGPoint(x: pic.frame.midX, y: pic.frame.midY)
    let cw = ceil(change.sizeThatFits(CGSize(width: 200, height: 34)).width), rw = remove.isHidden ? 0 : ceil(remove.sizeThatFits(CGSize(width: 200, height: 34)).width)
    let gap: CGFloat = remove.isHidden ? 0 : 24, x = (W - cw - gap - rw) / 2
    change.frame = CGRect(x: x, y: 110, width: cw, height: 34)
    remove.frame = CGRect(x: x + cw + gap, y: 110, width: rw, height: 34)
  }
}

// ---------- the screens ----------

// (a tap anywhere but in a text box puts the keyboard away)
// (Haris 2026-11-03: while the keyboard is up, a touch anywhere else on the page only puts it down — it never also
//  taps the row, switch or button under the finger. A see-through cover over the page while the keyboard is up, with a
//  hole where the box being typed in is; gone with the keyboard.)
final class KeyboardShield: UIView {
  private weak var page: UIView?
  static func attach(_ page: UIView) {
    let k = KeyboardShield(); k.page = page; k.isHidden = true; k.backgroundColor = .clear
    page.addSubview(k)
    NotificationCenter.default.addObserver(k, selector: #selector(k.up), name: UIResponder.keyboardWillShowNotification, object: nil)
    NotificationCenter.default.addObserver(k, selector: #selector(k.down), name: UIResponder.keyboardWillHideNotification, object: nil)
  }
  private func field(_ v: UIView) -> UIView? {
    if (v is UITextField || v is UITextView) && v.isFirstResponder { return v }
    for x in v.subviews where x !== self { if let f = field(x) { return f } }
    return nil
  }
  // (what's being typed in: on the page, or the app's comment box over it — Haris 2026-11-04: comments too)
  private func typing(_ p: UIView) -> UIView? {
    let f = field(p) ?? (p.window.flatMap { w in w.subviews.lazy.compactMap { self.field($0) }.first })
    // (not a task's description: it locks the page itself and ends only with Done — Haris 2026-11-04)
    var v = f?.superview; while let x = v { if x is DescBox { return nil }; v = x.superview }
    return f
  }
  @objc private func up() {
    guard let p = page, typing(p) != nil else { return }
    frame = p.bounds; p.bringSubviewToFront(self); isHidden = false
  }
  @objc private func down() { isHidden = true }
  override func hitTest(_ pt: CGPoint, with e: UIEvent?) -> UIView? {
    guard !isHidden, let p = page, !p.isHidden else { return nil }
    guard let f = typing(p) else { isHidden = true; return nil }
    // (🔍's results: a tap opens what's tapped at once, as iPhone's own search — Haris 2026-11-04)
    if let h = p as? HomeView, h.searching { return nil }
    // (the box being typed in — and its clear button — still works)
    if f.convert(f.bounds, to: self).insetBy(dx: -6, dy: -6).contains(pt) { return nil }
    return self
  }
  override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { if let w = page?.window { w.endEditing(true) } else { page?.endEditing(true) }; isHidden = true }
}

final class MeCtl {
  private unowned let main: Main
  init(_ m: Main) { main = m }
  // (where the finger last came down — a question with choices opens right above the row that asked it: Haris 2026-11-03)
  private let spot = TouchSpot()
  private func watchTouches() { if spot.view == nil { main.view.addGestureRecognizer(spot) } }
  private func askAnchor() -> CGRect {
    let v = main.view!, W = v.bounds.width
    guard let p = spot.at else { return CGRect(x: v.bounds.midX, y: v.bounds.maxY - 120, width: 1, height: 1) }
    // (the row under the finger: the first view up from it that is a whole row wide)
    var r = v.hitTest(p, with: nil)
    while let x = r, x !== v { if x.bounds.width >= W - 60 && x.bounds.height <= 120 { return x.convert(x.bounds, to: v) }; r = x.superview }
    return CGRect(x: 16, y: p.y - 22, width: W - 32, height: 44)
  }
  // (a page of Me opened from elsewhere — the birthday / city card's Go to My profile, What's new's All notes: Me's tab,
  //  then that page over it)
  private var wantOpen: String?, wantOpenId: String?
  private var plMonth: String?
  // (which tab it serves: Me — or, for Social Managers and Executives, their Content plans tab, whose first page is the
  //  plans list itself, as Client Assets' — Haris 2026-11-04)
  private(set) var tab = "me"
  private var rootKind: String { tab == "plans" ? "plans" : tab == "today" ? "overview" : tab == "team" ? "team" : tab == "fin-reimb" ? "claims" : tab == "fin-expenses" ? "expenses" : tab == "reviews" ? "reviews" : "me" }
  // (a tab's own first page — big title, 🔍 / your photo, no ‹: Content plans for Social, an Office Admin's Overview and Team)
  static let tabRoots: Set<String> = ["plansTab", "overviewTab", "teamTab", "claimsTab", "expensesTab", "reviewsTab"]
  // (Claims: Need approval · All; Expenses: Subscriptions · Office expenses — Haris 2026-11-04)
  private var clSeg = 0, exSeg = 0, rvSeg = 0, rvFocusN = 0
  // ---------- Part B step 2: the pages' contents from the app's own copy (web/appme-*.js), the page's only where the copy
  // can't say (the device's own state: notifications, Face ID, theme, the sync line…) — each group on its own server
  // switch (kv app-me-<group>); until the copy is this person's, the page's as before ----------
  private var pageModel: [String: Any] = [:]
  private var copyWatch: UUID?
  private var trQv = "", trCatv = "all"
  private func own(_ p: [String: Any]) -> [String: Any] {
    guard AppData.shared.ready, let me = me, AppData.shared.me == me else { return p }
    var m = p
    let has = { (k: String) in p[k] != nil && !(p[k] is NSNull) }
    let kinds = Set(stack.map { $0.kind })
    let env: Any = p["env"] ?? (["shell": SHELL_VERSION] as [String: Any])
    if let x = AppData.shared.meModel("me", "me", [env]) { for k in ["card", "work"] { if let v = x[k] { m[k] = v } }; if !has("digest") { m["digest"] = x["digest"] } }
    // (step 9: Me's own rows the page gave, when it hasn't — no website, or offline: About, the owner, the version, the Test
    //  site rows, the sync line — from what the server said at the start and the app's own state)
    let st = main.startInfo
    if (st["me"] as? String) == me {
      if !has("about") { m["about"] = true }
      if !has("owner") { m["owner"] = st["owner"] }
      if !has("canUpdate") { m["canUpdate"] = st["owner"] }
      if !has("version"), let v = st["version"] as? String { m["version"] = "E11 Console \(v)" }
      if !has("test") {
        let va = st["viewAs"] as? [String: Any]
        if va != nil || (st["sample"] as? Bool) == true { m["test"] = ["viewAs": va != nil, "viewing": (va?["as"] as? [String: Any])?["name"] ?? NSNull(), "sample": st["sample"] ?? false] as [String: Any] }
      }
      if (p["env"] as? [String: Any])?["host"] == nil { m["env"] = ["ownerId": st["ownerId"] ?? NSNull(), "host": URL(string: serverURL())?.host ?? "", "shell": SHELL_VERSION] as [String: Any] }
    }
    if !has("sync") { m["sync"] = AppData.shared.streamUp ? "saved" : main.netUp ? "reconnecting" : "offline" }
    // (Notifications and the Face ID lock: as this phone has them — step 8)
    if let st = pushNow { m["push"] = pushModel(st) }
    pushCheck()
    if let bio = main.biometry() { m["lock"] = bio } else { m["lock"] = nil }
    // (Appearance: as this phone keeps it — step 4)
    if let tm = UserDefaults.standard.string(forKey: "e11_theme_mode") { m["theme"] = tm }
    if let look = UserDefaults.standard.string(forKey: "e11_look") { m["themeNow"] = look }
    if has("profile") || kinds.contains("profile"), let x = AppData.shared.meModel("profile", "profile", [env]) { var v = x; if let pv = p["profile"] as? [String: Any] { for k in ["photoBusy", "owner"] { v[k] = pv[k] } }; if pfBusy { v["photoBusy"] = true }; m["profile"] = v }
    if has("team") || kinds.contains("team"), let x = AppData.shared.meModel("team", "team", [env]) { m["team"] = x }
    if has("trash") || kinds.contains("trash"), let x = AppData.shared.meModel("trash", "trash", [trQv, trCatv, env]) { m["trash"] = x }
    if tab == "fin-reimb" || has("claims"), let x = AppData.shared.meModel("claims", "claims") { m["claims"] = x }
    if tab == "fin-expenses" || has("expenses"), let x = AppData.shared.meModel("expenses", "expenses") { m["expenses"] = x }
    if tab == "today" || has("overview"), let x = AppData.shared.meModel("overview", "overview") { m["overview"] = x }
    if tab == "reviews" || has("reviews"), let x = AppData.shared.meModel("reviews", "reviews") { var v = x; v["focus"] = (p["reviews"] as? [String: Any])?["focus"]; m["reviews"] = v }
    if has("plans") || kinds.contains("plans"), let x = AppData.shared.meModel("plans", "plansList", [plMonth ?? ""]) { m["plans"] = x }
    if let s = stack.last(where: { $0.kind == "plan" }), let id = s.id {
      let pr = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
      if let x = AppData.shared.meModel("plans", "plan", [pr.first ?? "", pr.count > 1 ? pr[1] : ""]) { m["plan"] = x }
    }
    return m
  }
  // (a question to the page, its answer back — Content plans' post, approve, send back)
  // (Part B step 3: these go straight to the server — /api/app/act, done there as the website would; the changed records
  //  into the app's copy at once. The server switched off for one (kv app-act-<group>), or no answer: the page, as before)
  private static let serverActs: Set<String> = ["rvApprove", "rvAmend", "clApprove", "clPaid", "clAdd", "clPerson", "exAdd", "exEnd", "plApprove", "plBack", "plReview", "trRestore"]
  private func request(_ ev: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    if let name = ev["ev"] as? String, MeCtl.serverActs.contains(name), AppData.shared.tabsOn, JSONSerialization.isValidJSONObject(ev) {
      var b = ev; b["op"] = UUID().uuidString
      main.serverTask.request("/api/app/act", body: b) { [weak self] j in
        guard let self = self else { return }
        guard let j = j, (j["off"] as? Bool) != true else { self.requestPage(ev, done); return }
        if let ch = j["changes"] as? [[String: Any]], !ch.isEmpty { AppData.shared.applyLocal(ch) }
        done(j)
      }
      return
    }
    requestPage(ev, done)
  }
  private func requestPage(_ ev: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    // (the page doesn't answer this one — it says so with its own toast)
    if (ev["ev"] as? String) == "trRestore" { send(ev); return }
    let rid = UUID().uuidString
    var e = ev; e["rid"] = rid
    asks[rid] = done
    send(e)
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.asks.removeValue(forKey: rid)?(["ok": false, "error": "No answer — try again"]) }
  }
  // ---------- Part B step 4: Me's own edits straight to the server — My profile, Trash, Team members (/api/app/act:
  // pfSet, trForever, trEmpty, cd, member, addMember; the questions from the shared brain, web/appme-people.js, asked
  // with iPhone's own alerts / sheets / forms). The server switched off for one (kv app-act-<group>), the copy not this
  // person's yet, or no answer: the page's way, as before ----------
  private var pfBusy = false
  private var mineNow: Bool { AppData.shared.tabsOn && AppData.shared.ready && me != nil && AppData.shared.me == me }
  // (testCopy: "Work as …?" leaves out Owner view on the test site, as the website does)
  private var envNow: Any { var e = (pageModel["env"] as? [String: Any]) ?? ["shell": SHELL_VERSION]; if serverURL().contains("-test.") { e["testCopy"] = true }; return e }
  private func brain(_ g: String, _ fn: String, _ args: [Any] = []) -> [String: Any]? { mineNow ? AppData.shared.meModel(g, fn, args) : nil }
  // one edit: done → its toast (the server's message), the changed records into the copy at once; refused → its reason
  private func direct(_ b: [String: Any], or page: [String: Any]?, quiet: Bool = false, _ then: (([String: Any]) -> Void)? = nil) {
    let h = top
    guard mineNow, JSONSerialization.isValidJSONObject(b) else { if let p = page { send(p) }; return }
    var body = b; body["op"] = UUID().uuidString
    main.serverTask.request("/api/app/act", body: body) { [weak self, weak h] j in
      guard let self = self else { return }
      guard let j = j else { h?.toast(["t": "No connection — try again"]); self.redraw(); return }
      if (j["off"] as? Bool) == true { if let p = page { self.send(p) }; return }
      if let ch = j["changes"] as? [[String: Any]], !ch.isEmpty { AppData.shared.applyLocal(ch) }
      if (j["ok"] as? Bool) == true { if let m = (j["messages"] as? [String])?.first(where: { !$0.isEmpty }) { h?.toast(["t": m]) } }
      else if j["need"] == nil && !quiet { UINotificationFeedbackGenerator().notificationOccurred(.error); h?.toast(["t": j["error"] as? String ?? "That didn’t work — try again"]); self.redraw() }
      then?(j)
    }
  }
  private func redraw() { guard !pageModel.isEmpty, !stack.isEmpty else { return }; model = own(pageModel); if !hidden { stack.forEach { draw($0) } } }
  // an alert from the brain ({ title, body, okText, danger }); yes → go
  private func confirm(_ q: [String: Any], _ go: @escaping () -> Void) {
    var a = q; a["kind"] = "alert"; a["cancelText"] = "Cancel"
    ask(a) { r in if (r["ok"] as? Bool) == true { go() } }
  }
  // a sheet from the brain ({ sheet, acts }): a row tapped → its act (asked first when it says so)
  private func sheet(_ m: [String: Any], multi: Bool = false, _ run: @escaping ([String: Any]) -> Void) {
    guard let a = m["sheet"] as? [String: Any], let acts = m["acts"] as? [[String: Any]] else { return }
    let pickOne: (Int) -> Void = { i in guard i >= 0, i < acts.count else { return }; run(acts[i]) }
    let vc = NativeSheetVC(a, dark: !light, pick: multi ? pickOne : nil) { i, _ in if !multi { pickOne(i) } }
    main.topMost().present(vc, animated: true)
  }
  // My profile
  private func pfSet(_ field: String, _ extra: [String: Any], page: [String: Any]?) {
    var b: [String: Any] = ["ev": "pfSet", "field": field]; for (k, v) in extra { b[k] = v }
    direct(b, or: page)
  }
  private func pfName() {
    guard mineNow else { send(["ev": "pfName"]); return }
    let cur = (model["profile"] as? [String: Any])?["name"] as? String ?? ""
    func once(_ v: String, _ err: String) {
      ask(["kind": "form", "title": "Full name", "okText": "Save", "error": err, "fields": [["key": "name", "label": "Full name", "type": "text", "value": v, "placeholder": "Your full name"]]]) { [weak self] r in
        guard (r["ok"] as? Bool) == true else { return }
        let n = ((r["values"] as? [String: Any])?["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { once(n, "Please enter your name") }; return }
        if n != cur { self?.pfSet("name", ["value": n], page: ["ev": "pfName"]) }
      }
    }
    once(cur, "")
  }
  private func pfPlace(_ kind: String) {
    let p = (model["profile"] as? [String: Any]) ?? [:]
    guard mineNow, let list = brain("profile", "places", [kind, p["country"] as? String ?? ""])?["list"] as? [String] else { send(["ev": kind == "country" ? "pfCountry" : "pfCity"]); return }
    let cur = p[kind] as? String ?? ""
    var rows: [[String: Any]] = [], vals: [String] = []
    if !cur.isEmpty { rows.append(["i": 0, "label": "Not set", "icon": "x"]); vals.append("") }
    let top = rows
    var listRows: [[String: Any]] = []
    for x in list { listRows.append(["i": vals.count, "label": x, "checked": x == cur, "find": x]); vals.append(x) }
    var sections: [[String: Any]] = []
    if !top.isEmpty { sections.append(["rows": top]) }
    sections.append(["rows": listRows])
    var a: [String: Any] = ["sections": sections, "search": kind == "country" ? "Search countries" : list.isEmpty ? "Type your city" : "Search or type your city",
                            "empty": kind == "country" ? "No country matches “%@”" : "Type the name of your city"]
    if kind == "city" { a["custom"] = "Use “%@”" }   // (a city that isn't listed can be typed)
    let vc = NativeSheetVC(a, dark: !light) { [weak self] i, typed in
      let v: String? = i == -2 ? typed?.trimmingCharacters(in: .whitespacesAndNewlines) : (i >= 0 && i < vals.count ? vals[i] : nil)
      guard let v = v, v != cur else { return }
      self?.pfSet(kind, ["value": v], page: nil)
    }
    main.topMost().present(vc, animated: true)
  }
  private func pfBday() {
    let p = (model["profile"] as? [String: Any]) ?? [:]
    guard mineNow, let md = p["md"] as? String else { send(["ev": "pfBday"]); return }
    let year = Calendar(identifier: .gregorian).component(.year, from: Date())
    main.topMost().present(DateSheetVC(["value": md.isEmpty ? "" : "\(year)-\(md)", "min": "", "max": "", "clearable": !md.isEmpty, "md": true], dark: !light) { [weak self] r in
      if (r["ok"] as? Bool) == false || (r["cancel"] as? Bool) == true { return }
      let v: String = (r["clear"] as? Bool) == true ? "" : String((r["date"] as? String ?? "").dropFirst(5))
      if (r["clear"] as? Bool) != true && v.isEmpty { return }
      if v != md { self?.pfSet("bday", ["value": v.isEmpty ? NSNull() : v], page: nil) }
    }, animated: true)
  }
  // your photo: picked here, sent up by the app, made round and small on the server, then saved on you (the old one to
  // the trash folder)
  private func pfPhoto(_ src: String) {
    guard mineNow, let me = me else { send(["ev": "pfPhoto", "source": src]); return }
    Picker.shared.pick(from: main.topMost(), single: true, source: src) { [weak self] r in
      guard let self = self, let x = ((r["files"] as? [[String: Any]]) ?? []).first, let tok = x["token"] as? String, let url = Picker.shared.url(tok) else { return }
      self.pfBusy = true; self.redraw()
      let fail = { [weak self] in guard let self = self else { return }; self.pfBusy = false; self.redraw(); self.top?.toast(["t": "Couldn’t use that photo"]) }
      Uploader.send(url, name: x["name"] as? String ?? "photo.jpg", task: "_uploads", cookies: self.main.serverHome.cookies, progress: { _ in }) { [weak self] path in
        guard let self = self, let path = path else { fail(); return }
        self.main.serverTask.request("/api/host/processImage", body: ["path": path, "kind": "avatar", "userId": me]) { [weak self] j in
          guard let self = self, let pic = j?["path"] as? String, !pic.isEmpty else { fail(); return }
          self.direct(["ev": "pfSet", "field": "avatar", "value": pic], or: nil) { [weak self] _ in self?.pfBusy = false; self?.redraw() }
        }
      }
    }
  }
  private func pfPhotoOff() {
    guard mineNow else { send(["ev": "pfPhotoOff"]); return }
    confirm(["title": "Remove your photo?", "body": "Your initials show instead.", "okText": "Remove", "danger": true]) { [weak self] in self?.pfSet("avatar", ["value": NSNull()], page: ["ev": "pfPhotoOff"]) }
  }
  // Trash: Delete forever, Empty Trash — asked first, as the website does
  private func trForever(_ id: String) {
    guard let q = brain("trash", "trashAsk", [id]), q["title"] != nil else { send(["ev": "trForever", "id": id]); return }
    confirm(q) { [weak self] in self?.direct(["ev": "trForever", "id": id], or: ["ev": "trForever", "id": id]) }
  }
  private func trEmpty() {
    guard let q = brain("trash", "trashEmptyAsk"), q["title"] != nil else { send(["ev": "trEmpty"]); return }
    confirm(q) { [weak self] in self?.direct(["ev": "trEmpty"], or: ["ev": "trEmpty"]) }
  }
  // Team members: someone's menu (role, rights, Finance access, clients, Social Manager, restore / remove), the
  // Creative Director switch, Add member
  private func memberMenu(_ id: String) {
    guard let m = brain("team", "memberMenu", [id, envNow]), m["sheet"] != nil else { send(["ev": "member", "id": id]); return }
    sheet(m) { [weak self] act in self?.memberAct(id, act) }
  }
  private func memberAct(_ id: String, _ act: [String: Any]) {
    if (act["open"] as? String) == "clients" { clientsMenu(id); return }
    var b = act; b["ev"] = "member"; b["id"] = id; b.removeValue(forKey: "ask")
    let go: () -> Void = { [weak self] in self?.direct(b, or: ["ev": "member", "id": id]) { j in if (j["clients"] as? Bool) == true { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.clientsMenu(id) } } } }
    if let q = act["ask"] as? [String: Any] { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.confirm(q, go) } } else { go() }
  }
  // the clients a freelancer can see: each tick saved at once (the sheet stays open)
  private func clientsMenu(_ id: String) {
    guard let m = brain("team", "clientsMenu", [id]), m["sheet"] != nil else { return }
    sheet(m, multi: true) { [weak self] act in var b = act; b["ev"] = "member"; b["id"] = id; self?.direct(b, or: nil) }
  }
  private func cdFlow(_ id: String) {
    guard let q = brain("team", "cdAsk", [id]) else { send(["ev": "cd", "id": id]); return }
    let send2: ([String: Any]) -> Void = { [weak self] extra in
      var b: [String: Any] = ["ev": "cd", "id": id]; for (k, v) in extra { b[k] = v }
      self?.direct(b, or: ["ev": "cd", "id": id]) { j in
        // (someone else is CD: the server's question — take over, or Acting CD while they're away)
        guard (j["need"] as? String) == "choice", let a = j["ask"] as? [String: Any] else { return }
        let choices = (a["choices"] as? [[String: Any]]) ?? []
        var c2: [[String: Any]] = choices.map { ["label": $0["label"] as? String ?? "", "primary": ($0["primary"] as? Bool) == true] }
        c2.append(["label": "Cancel", "cancel": true])
        self?.ask(["kind": "choice", "title": a["title"] ?? "", "body": a["body"] ?? "", "choices": c2]) { r in
          guard (r["ok"] as? Bool) == true, let i = r["index"] as? Int, i < choices.count, let v = choices[i]["value"] as? String else { self?.redraw(); return }
          self?.direct(["ev": "cd", "id": id, "choice": v], or: nil)
        }
      }
    }
    if (q["choice"] as? Bool) == true { send2([:]); return }
    if q["title"] == nil { redraw(); return }
    var a = q; a["kind"] = "alert"; a["cancelText"] = "Cancel"
    ask(a) { [weak self] r in if (r["ok"] as? Bool) == true { send2([:]) } else { self?.redraw() } }
  }
  private func addMember() {
    guard let form = brain("team", "addMemberForm", [envNow]), form["fields"] != nil else { send(["ev": "addMember"]); return }
    func once(_ vals: [String: Any]?, _ err: String) {
      var a = form; a["kind"] = "form"; a["error"] = err
      if let vals = vals { a["fields"] = ((form["fields"] as? [[String: Any]]) ?? []).map { f -> [String: Any] in var g = f; if let k = f["key"] as? String, let v = vals[k] { g["value"] = v }; return g } }
      ask(a) { [weak self] r in
        guard (r["ok"] as? Bool) == true, let v = r["values"] as? [String: Any] else { return }
        var b: [String: Any] = ["ev": "addMember"]; for (k, x) in v { b[k] = x }
        self?.direct(b, or: ["ev": "addMember"], quiet: true) { j in
          if (j["ok"] as? Bool) != true, j["off"] == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { once(v, j["error"] as? String ?? "That didn’t work — try again") }; return }
          if (j["clients"] as? Bool) == true, let nid = j["id"] as? String { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.clientsMenu(nid) } }
        }
      }
    }
    once(nil, "")
  }
  // ---------- Part B step 4 (the rest): About, Appearance and View as — the app's own, straight from the server (the
  // page's way while the copy isn't this person's yet) ----------
  private func drawAbout() { stack.filter { $0.kind == "about" }.forEach { draw($0) } }
  private static func timeAgo(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let s = Date().timeIntervalSince(d)
    if s < 60 { return "just now" }
    if s < 3600 { return "\(Int(s / 60))m ago" }
    if s < 86400 { return "\(Int(s / 3600))h ago" }
    if s < 86400 * 7 { return "\(Int(s / 86400))d ago" }
    let o = DateFormatter(); o.locale = Locale(identifier: "en_US"); o.dateFormat = "MMM d, yyyy"; return o.string(from: d)
  }
  private static func isoDate(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
  }
  private static func dateTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let o = DateFormatter(); o.locale = Locale(identifier: "en_US"); o.dateFormat = "MMM d, yyyy, h:mm a"; return o.string(from: d)
  }
  // (the page's updatesOf: the updater's state as the About card shows it)
  private static func updatesOf(_ s: [String: Any]) -> [String: Any] {
    let st = (s["status"] as? [String: Any]) ?? s
    if (st["managed"] as? Bool) != true && (s["managed"] as? Bool) == false { return ["unmanaged": true, "running": s["running"] as? String ?? ""] }
    var hour: String?
    if let n = st["updateHour"] as? NSNumber { hour = String(format: "%02d:00", n.intValue) } else if let t = st["updateHour"] as? String, t != "now", let n = Int(t) { hour = String(format: "%02d:00", n) }
    var out: [String: Any] = ["running": (st["running"] as? String) ?? (st["current"] as? String) ?? "—", "test": (st["channel"] as? String) == "staging",
                              "checked": (st["lastCheck"] as? String).map(MeCtl.timeAgo) ?? "Never", "error": st["lastError"] as? String ?? "", "busy": (st["busy"] as? Bool) == true]
    if let a = st["available"] as? [String: Any] {
      var av: [String: Any] = ["name": (a["name"] as? String) ?? (a["version"] as? String) ?? "", "notes": a["notes"] as? String ?? ""]
      if let h = hour { av["hour"] = h }
      out["available"] = av
    }
    return out
  }
  private func loadAbout(_ fresh: Bool) {
    guard mineNow else { send(fresh ? ["ev": "about", "fresh": true] : ["ev": "about"]); return }
    main.serverTask.request("/api/whatsnew", body: nil) { [weak self] j in
      guard let self = self else { return }
      if let j = j {
        self.about["notes"] = ["name": (j["name"] as? String) ?? (j["version"] as? String) ?? "", "version": j["version"] as? String ?? "",
                               "at": (j["publishedAt"] as? String).map(MeCtl.dateTime) ?? "", "notes": j["notes"] as? String ?? ""]
      } else if self.about["notes"] == nil { self.about["notes"] = ["name": self.model["version"] as? String ?? "", "notes": ""] }
      self.drawAbout()
    }
    guard (model["canUpdate"] as? Bool) == true else { return }
    main.serverTask.request("/api/updates", body: fresh ? ["action": "check"] : nil, timeout: 60) { [weak self] j in
      self?.about["updates"] = j.map(MeCtl.updatesOf) ?? ["error": "Couldn’t check for updates — try again"]; self?.drawAbout()
    }
    if (model["owner"] as? Bool) == true { loadVideo(false) }
  }
  private func loadVideo(_ fresh: Bool) {
    guard mineNow else { send(["ev": "videoCheck"]); return }
    var v = (about["video"] as? [String: Any]) ?? [:]
    v["checking"] = fresh ? "Checking the NAS… (a short test conversion)" : (v["title"] != nil ? "" : "Checking the NAS…")
    about["video"] = v; drawAbout()
    main.serverTask.request("/api/system/video" + (fresh ? "?fresh=1" : ""), body: nil, timeout: 45) { [weak self] j in
      guard let self = self else { return }
      guard let v = j?["video"] as? [String: Any] else { self.about["video"] = ["error": "Couldn’t check — try again"]; self.drawAbout(); return }
      var o: [String: Any] = ["state": v["state"] as? String ?? "", "title": v["title"] as? String ?? "", "detail": v["detail"] as? String ?? "",
                              "checked": (v["checkedAt"] as? String).map(MeCtl.timeAgo) ?? ""]
      if let lc = j?["lightCopies"] as? [String: Any] {
        let made = (lc["made"] as? NSNumber)?.intValue ?? 0, waiting = (lc["waiting"] as? NSNumber)?.intValue ?? 0
        let working = lc["working"] as? String
        o["light"] = "\(made) made since the last restart" + (waiting > 0 ? " · \(waiting) waiting" + (working.map { " (now: \($0))" } ?? "") : " · none waiting")
      }
      self.about["video"] = o; self.drawAbout()
    }
  }
  private func updateNow() {
    guard mineNow else { send(["ev": "update"]); return }
    confirm(["title": "Update E11 Console now?", "body": "A copy of the database is made first, and it takes about 10 seconds. Open apps show a “Reload” button.", "okText": "Update now"]) { [weak self] in
      guard let self = self else { return }
      self.main.serverTask.request("/api/updates", body: ["action": "update"], timeout: 60) { [weak self] j in
        guard let self = self else { return }
        guard let j = j, (j["ok"] as? Bool) != false else { self.top?.toast(["t": (j?["error"] as? String) ?? "Something went wrong"]); return }
        if (j["started"] as? Bool) != true { self.about["updates"] = MeCtl.updatesOf(j); self.drawAbout(); return }
        self.about["busy"] = "Updating E11 Console… This takes about 10 seconds. The app reconnects by itself."; self.drawAbout()
        let t0 = Date()
        func poll() {
          self.main.serverTask.request("/api/updates", body: nil) { [weak self] st in
            guard let self = self else { return }
            let lr = st?["lastResult"] as? [String: Any]
            if let st = st, (st["busy"] as? Bool) != true, let lr = lr, (lr["action"] as? String) == "update",
               let at = (lr["at"] as? String).flatMap({ MeCtl.isoDate($0) }), at >= t0.addingTimeInterval(-1) {
              let ok = (lr["ok"] as? Bool) == true
              self.top?.toast(["t": ok ? ((lr["upToDate"] as? Bool) == true ? "Already up to date" : "Updated to \(lr["version"] as? String ?? "")") : (lr["error"] as? String ?? "Something went wrong")])
              self.about["busy"] = nil; self.about["updates"] = MeCtl.updatesOf(st); self.drawAbout(); return
            }
            if Date().timeIntervalSince(t0) < 120 { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { poll() } } else { self.about["busy"] = nil; self.loadAbout(false) }
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { poll() }
      }
    }
  }
  // Appearance: Automatic / Light / Dark — kept by the app on this phone (this person's settings), the look changed at
  // once; the website under the app told too while it's still there
  private func setTheme(_ m: String) {
    guard mineNow, let me = me else { send(["ev": "theme", "mode": m]); return }
    let v = m == "light" || m == "dark" ? m : "auto"
    let d = UserDefaults.standard
    d.set(v, forKey: "e11_theme_mode")
    let key = "e11_prefs_\(me)"
    var p = (d.data(forKey: key).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    p["themeMode"] = v
    if let data = try? JSONSerialization.data(withJSONObject: p) { d.set(data, forKey: key) }
    // (the switch finishes its own slide first, then the whole app crossfades into its new look and the page's new rows —
    //  at once, the switch jumped mid-slide as everything changed under it: Haris 2026-11-05)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      let apply = {
        if v == "auto" { self.main.ownAppearanceTick() } else { self.main.run("setAppearance", ["mode": v, "themeMode": v]) { _ in } }
        self.redraw()
      }
      if let w = self.main.view.window { UIView.transition(with: w, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction], animations: { UIView.performWithoutAnimation(apply) }) } else { apply() }
      self.main.pageJS("typeof Theme !== 'undefined' && Theme.setMode('\(v)')")
    }
  }
  // View as (test site only): the team in the app's own sheet; a tap switches — the server remembers it, and the app
  // starts again as them
  func viewAsPick() {
    let pageWay = { [weak self] in self?.main.pageJS("typeof ViewAs !== 'undefined' && ViewAs.pick()"); return }
    main.serverTask.request("/api/me", body: nil) { [weak self] j in
      guard let self = self, let va = j?["viewAs"] as? [String: Any], let real = (va["real"] as? [String: Any])?["id"] as? String,
            let list = self.brain("me", "viewAsPeople", [real, self.envNow])?["people"] as? [[String: Any]] else { pageWay(); return }
      let ppl: [ViewAsSheet.Person] = list.compactMap { p in
        guard let id = p["id"] as? String else { return nil }
        return .init(id: id, name: p["name"] as? String ?? "", role: p["role"] as? String ?? "", ini: p["ini"] as? String ?? "", color: UIColor(hex: p["color"] as? String ?? "") ?? .systemGray, photo: p["photo"] as? String)
      }
      let s = ViewAsSheet(dark: !self.light, people: ppl, viewing: (va["as"] as? [String: Any])?["id"] as? String)
      s.closesOnPick = true
      s.onPick = { [weak self] id in self?.viewAsSet(id) }
      s.show(from: self.main.topMost())
    }
  }
  func viewAsSet(_ id: String?) {
    let b: [String: Any] = ["userId": id.map { $0 as Any } ?? NSNull()]
    main.serverTask.request("/api/view-as", body: b) { [weak self] j in
      guard let self = self else { return }
      guard j != nil else { self.main.pageJS("typeof ViewAs !== 'undefined' && " + (id == nil ? "ViewAs.back()" : "ViewAs.pick()")); return }
      // (what's on screen now is the other person's: put away at once — task pages, Client Assets, Me's screens, the other
      //  lists — so the new person's first tab shows, never the old one's page under their tab: Back to me left an
      //  Office Admin's page showing under Home's tab, Haris 2026-11-05)
      self.main.putAwayForSwitch()
      // (what the page hasn't sent yet first, then everything starts again as the chosen person)
      self.main.pageJS("(typeof Sync !== 'undefined' ? Sync.push().catch(() => {}) : Promise.resolve()).then(() => location.reload())")
    }
  }
  // the Trash, searched for something (a deleted task's update tapped — step 9)
  func openTrash(q: String) {
    trQv = q; trCatv = "all"
    if main.selectedTabKey == "me", tab == "me", !hidden, !stack.isEmpty { openSoon("trash") } else { wantOpen = "trash"; main.selectTab("me") }
  }
  func openSoon(_ kind: String) {
    if main.selectedTabKey == tab, !hidden, !stack.isEmpty {
      if stack.count > 1 { backToRoot(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.open(kind) } } else { open(kind) }
      return
    }
    wantOpen = kind
  }
  private struct Screen { let h: HomeView; let kind: String; let id: String? }
  private var stack: [Screen] = []
  private var model: [String: Any] = [:]
  private var about: [String: Any] = [:]
  var light = true
  private var me: String?
  private(set) var leaving = false
  private var hidden = false          // (the page went elsewhere — another tab, My profile…: kept, out of sight)
  private var teamTab = 0, teamQ = ""
  private var asks: [String: ([String: Any]) -> Void] = [:]

  var top: HomeView? { hidden ? nil : stack.last.map { $0.h } }
  // (this phone's notifications: "on" / "off" / "denied", as last asked of iPhone; turning on or off — step 8)
  var pushNow: String?, pushBusy = false, pushAsked: Date?
  var shown: HomeView? {
    guard !hidden, let s = stack.last, !s.h.isHidden else { return nil }
    if leaving { return stack.count >= 2 ? stack[stack.count - 2].h : nil }
    return s.h
  }
  var isOpen: Bool { !stack.isEmpty && !hidden }
  var depth: Int { stack.count }
  var screens: [HomeView] { stack.map { $0.h } }
  var kind: String { stack.last?.kind ?? "" }

  private func send(_ ev: [String: Any]) {
    // (no website — step 9, or offline: the app does it itself)
    if !main.pageReady { nativeEv(ev); return }
    main.pageJS("window.__e11Me && window.__e11Me(\(jsonString(ev)))")
  }
  // ---------- Step 9: what the page did for Me, done by the app (phone.js NativeMe __e11Me) ----------
  private func nativeEv(_ ev: [String: Any]) {
    let say = { [weak self] (t: String) in (self?.top ?? self?.shown)?.toast(["t": t]) }
    let file = { [weak self] (path: String, name: String) in
      guard !path.isEmpty else { return }
      self?.main.openFiles([["id": path, "path": path, "name": name]], at: 0)
    }
    switch ev["ev"] as? String ?? "" {
    case "nav":
      switch ev["to"] as? String ?? "" {
      case "clients": main.assetsCtl.openAll(animated: true)
      case "calendar": say("The content calendar is on the computer")
      case "projects": say("Every client’s tasks are on the computer for now")
      default: break
      }
    case "ovFile", "plFile": file(ev["path"] as? String ?? "", ev["name"] as? String ?? "File")
    case "exInv":
      let id = ev["id"] as? String ?? ""
      let ex = (model["expenses"] as? [String: Any]) ?? [:]
      let rows = ((ex["subs"] as? [[String: Any]]) ?? []) + ((ex["office"] as? [[String: Any]]) ?? [])
      if let f = rows.first(where: { ($0["id"] as? String) == id })?["invFile"] as? [String: Any] { file(f["path"] as? String ?? "", f["name"] as? String ?? "Invoice") }
    case "rvTask": if let t = ev["tid"] as? String, !t.isEmpty { main.openTaskPage(t, tab: "details", focus: "") }
    case "rvFile":
      // (the request's files, from its task's own page model — they carry where each file is)
      guard let it = reviewItem(ev["id"] as? String ?? ""), let tid = it.0["tid"] as? String,
            let all = AppData.shared.screen("task", tid).model?["files"] as? [[String: Any]] else { return }
      let want = (((it.0["files"] as? [[String: Any]]) ?? []) + ((it.0["carriedFiles"] as? [[String: Any]]) ?? [])).compactMap { $0["id"] as? String }
      let list = want.compactMap { id in all.first { ($0["id"] as? String) == id } }
      if let i = list.firstIndex(where: { ($0["id"] as? String) == (ev["fid"] as? String) }) { main.openFiles(list, at: i) }
    case "clOpen", "ovClaim":
      // (the claim's PDF, drawn by the server — the same everywhere: Haris 2026-11-05)
      say("Preparing the PDF…")
      main.serverTask.request("/api/app/claimPdf", body: ["id": ev["id"] as? String ?? ""]) { [weak self] r in
        guard let r = r, (r["ok"] as? Bool) == true, let p = r["path"] as? String else { say(r?["error"] as? String ?? "Could not make the PDF"); return }
        self?.main.openFiles([["id": p, "path": p, "name": r["name"] as? String ?? "Expense claim.pdf", "size": r["size"] ?? 0]], at: 0)
      }
    case "pfTest":
      main.serverTask.request("/api/push/test", body: ["token": main.lastToken ?? ""]) { r in say(r.map { MeCtl.testSaid($0) } ?? "No connection — try again") }
    case "pfOwner":
      main.serverTask.request("/api/owner-view", body: ["mode": ev["mode"] as? String ?? "off"]) { [weak self] r in
        if (r?["ok"] as? Bool) == true { self?.main.restartApp() } else { say(r?["error"] as? String ?? "That didn’t work — try again") }
      }
    case "sample":
      ask(["kind": "alert", "title": "Start fresh with sample data?", "body": "This wipes everything on the TEST site — every task, client, Client Assets file, Finance record, claim, Inbox update and person except you — and adds a new sample set. A backup of the old data is kept on the server. The live site is never touched.", "okText": "Start fresh", "danger": true, "cancelText": "Cancel"]) { [weak self] r in
        guard (r["ok"] as? Bool) == true else { return }
        self?.main.serverTask.request("/api/sample/reset", body: [:]) { j in
          guard let j = j, (j["ok"] as? Bool) != false else { say(j?["error"] as? String ?? "Could not start fresh"); return }
          say("Fresh sample: \(j["clients"] as? Int ?? 0) clients, \(j["tasks"] as? Int ?? 0) tasks, \(j["people"] as? Int ?? 0) people")
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self?.main.restartApp() }
        }
      }
    case "import": say("Moving data from the Mac app is done on the Mac")
    case "update", "videoCheck": say("Not available here right now — try again in a moment")
    default: break   // (pf / team / tr / pl on and off, toasts: only the page needed to hear them)
    }
  }

  // ---------- from the page ----------
  func command(_ a: [String: Any]) {
    if let rid = a["rid"] as? String { asks.removeValue(forKey: rid)?(a); return }
    // (a Content plan opened on the page — an Inbox update, a notification: the app's own page for it)
    // (a review request opened on the page — an Inbox update: the Reviews tab's own page for it)
    if let o = a["open"] as? [String: Any], (o["kind"] as? String) == "review", let rid = o["id"] as? String {
      wantOpenId = rid; wantOpen = "review"
      if main.selectedTabKey == tab, tab == "reviews", !hidden, !stack.isEmpty, let k = wantOpen { wantOpen = nil; let id = wantOpenId; wantOpenId = nil; if stack.count > 1 { backToRoot() }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.open(k, id) } }
      return
    }
    if let o = a["open"] as? [String: Any], (o["kind"] as? String) == "plan", let pid = o["pid"] as? String {
      wantOpenId = "\(pid)|\(o["month"] as? String ?? "")"; wantOpen = "plan"
      if main.selectedTabKey == tab, !hidden, !stack.isEmpty, let k = wantOpen { wantOpen = nil; let id = wantOpenId; if stack.count > 1 { backToRoot() }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.open(k, id) } }
      return
    }
    if let t = a["toast"] as? [String: Any] { (shown ?? top)?.toast(t); return }
    if let ab = a["about"] as? [String: Any] { about = ab; stack.filter { $0.kind == "about" }.forEach { draw($0) }; return }
    guard let show = a["show"] as? Bool else { return }
    if !show { hide(); return }
    light = (a["light"] as? Bool) ?? light
    if let m = a["me"] as? String {
      // (someone else now — View as…, signed in again: Me from the start)
      if let was = me, was != m { stack.forEach { $0.h.removeFromSuperview() }; stack = [] }
      me = m
    }
    if let m = a["model"] as? [String: Any] { pageModel = m; model = own(m) }
    if copyWatch == nil { copyWatch = AppData.shared.listen { [weak self] in guard let self = self, !self.pageModel.isEmpty, !self.stack.isEmpty else { return }; self.model = self.own(self.pageModel); if !self.hidden { self.stack.forEach { self.draw($0) } } } }
    // (the other tab now — Me ↔ Content plans: its own first page)
    let want = ["plans", "today", "team", "fin-reimb", "fin-expenses", "reviews"].contains(a["tab"] as? String ?? "") ? (a["tab"] as! String) : "me"
    if want != tab {
      if stack.contains(where: { $0.kind == "plans" }) { send(["ev": "pl", "on": false]) }
      stack.forEach { $0.h.removeFromSuperview() }; stack = []; tab = want
    }
    if stack.isEmpty {
      if rootKind == "plans" { plMonth = plMonth ?? ""; send(["ev": "pl", "on": true, "month": plMonth ?? ""]) }
      if rootKind == "team" { teamTab = 0; teamQ = ""; send(["ev": "team", "on": true]) }
      push(screen(rootKind, nil), animated: false)
    }
    reveal()
    stack.forEach { draw($0) }
    main.updateCorner()
    if let k = wantOpen { wantOpen = nil; let id = wantOpenId; wantOpenId = nil; if stack.count > 1 { backToRoot() }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.open(k, id) } }
  }
  // out of sight, kept as it is (Me comes back where it was, as iPhone's own tabs)
  // (Me › Client Assets: the page says "Me off" a moment before Client Assets comes — Me stays where it is until Client
  //  Assets has slid in over it, so there's never a moment with nothing — Haris 2026-11-04)
  var coverWait: Date?
  private var reveals = 0
  func hide() {
    guard !stack.isEmpty, !hidden else { return }
    if let w = coverWait, Date().timeIntervalSince(w) < 2 {
      coverWait = nil; let t = reveals
      // (and not when Client Assets has already gone again — back to Me quickly, before this: Me went for a moment, a
      //  black flash between Client Assets and Me — Haris 2026-11-05)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in guard let self = self, self.reveals == t, self.main.assetsCtl.isOpen, !self.main.assetsCtl.leaving else { return }; self.hide() }
      return
    }
    coverWait = nil
    hidden = true; borrowTimer?.invalidate()
    stack.forEach { $0.h.endEditing(true); $0.h.isHidden = true; $0.h.transform = .identity }
    main.edgePanOn(); main.updateCorner()
  }
  func reveal() {
    guard let s = stack.last else { return }
    reveals += 1
    hidden = false; borrowTimer?.invalidate()
    if s.h.isHidden || s.h.transform != .identity { s.h.transform = .identity; s.h.isHidden = false }
    front()
    main.edgePanOn(); main.updateCorner()
  }
  // (over the other tabs' screens — one made after Me, the Inbox the first time, went on top of it — under the top
  //  buttons and the tab bar)
  private func front() {
    let v = main.view!
    guard let s = stack.last, let i = v.subviews.firstIndex(of: s.h) else { return }
    let mine = Set(stack.map { ObjectIdentifier($0.h) })
    guard v.subviews[(i + 1)...].contains(where: { x in (x is HomeView || x is TaskPage) && !x.isHidden && !mine.contains(ObjectIdentifier(x)) }) else { return }
    for x in stack { if main.corner.superview === v { v.insertSubview(x.h, belowSubview: main.corner) } else { v.insertSubview(x.h, belowSubview: main.tabBar) } }
  }
  // shown at once under a page going back to Me (Client Assets' ‹): the page says so a moment later — if it doesn't,
  // out of sight again
  private var borrowTimer: Timer?
  func borrow() -> UIView? {
    guard let s = stack.last, main.selectedTabKey == tab else { return nil }
    s.h.isHidden = false
    borrowTimer?.invalidate()
    borrowTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in guard let self = self, self.hidden else { return }; self.stack.forEach { $0.h.isHidden = true } }
    return s.h
  }

  // ---------- opening ----------
  private func screen(_ kind: String, _ id: String?) -> Screen {
    let h = HomeView(frame: main.view.bounds)
    // (Content plans as a Social's own tab: a main page — the big title, as Home and the Inbox: Haris 2026-11-04)
    // (opened from Me: the same big title, with ‹ — Haris 2026-11-04: both Content plans pages, no name in the middle)
    let root = stack.isEmpty && kind == rootKind
    h.assets = kind == "me" ? "me" : (root && kind == "plans") ? "plansTab" : (root && kind == "overview") ? "overviewTab" : (root && kind == "team") ? "teamTab" : (root && kind == "claims") ? "claimsTab" : (root && kind == "expenses") ? "expensesTab" : (root && kind == "reviews") ? "reviewsTab" : kind == "plans" ? "plansPage" : "me." + kind
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.assetsBack = !(stack.isEmpty && kind == rootKind)
    h.present = { [weak self] vc in self?.main.topMost().present(vc, animated: true) }
    h.onEvent = { [weak self, weak h] ev in guard let self = self, let h = h else { return }; self.event(h, ev) }
    h.onAssetsDraw = { [weak self] h, _ in self?.blocks(h) }
    h.assetsMenu = { [] }
    h.cornerShared = true
    h.onCorner = { [weak self] in self?.main.updateCorner() }
    // (a tap anywhere puts the keyboard away — Team members' search; taps still reach what's under the finger)
    KeyboardShield.attach(h)
    // (Team members, Expenses, Reviews: a swipe across the middle switches the two lists, as the task page's Details ·
    //  Comments — Haris 2026-11-04; the edge is left to the swipe back)
    if ["team", "expenses", "reviews"].contains(kind) {
      SegSwipe.attach(h) { [weak self, weak h] dir in
        guard let self = self, let h = h, let s = self.screenOf(h) else { return }
        let to = dir < 0 ? 1 : 0
        switch s.kind {
        case "team": guard self.teamTab != to else { return }; self.teamTab = to
        case "expenses": guard self.exSeg != to else { return }; self.exSeg = to
        case "reviews": guard self.rvSeg != to else { return }; self.rvSeg = to
        default: return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        self.slideLists(h, dir: dir) { self.draw(s) }
      }
    }
    main.view.insertSubview(h, belowSubview: main.tabBar)
    return Screen(h: h, kind: kind, id: id)
  }
  // the two lists swapped with the task page's Details ↔ Comments slide: what's under the switch goes off to one side,
  // the other list comes in from the other (the bar and the switch stay put — Haris 2026-11-04 "same as comments/detail")
  private func slideLists(_ h: HomeView, dir: Int, _ change: () -> Void) {
    let W = h.bounds.width, H = h.bounds.height
    let segV = h.assetsParts["seg"] as? UIView
    let y0 = max(0, min(H, segV.map { $0.convert($0.bounds, to: h).maxY } ?? 0))
    let r = CGRect(x: 0, y: y0, width: W, height: H - y0)
    // (each side drawn into a picture there and then — iPhone's snapshot views are only filled in at the next screen
    //  update, by which time the list had already changed: the new list slid in over itself, twice — Haris 2026-11-05)
    // (only the list itself — the page's floating buttons (+ Add…, search, NOT JUST ANY AGENCY) stay where they are, over
    //  the slide: drawn into the pictures too, they slid as copies beside the real ones — Haris 2026-11-05)
    let list: UIView = h.subviews.first(where: { $0 is UIScrollView }) ?? h
    let shot = { (after: Bool) -> UIImageView in
      let f = UIGraphicsImageRendererFormat.preferred(); f.opaque = false
      let at = list === h ? CGRect(x: -r.minX, y: -r.minY, width: W, height: H) : CGRect(x: list.frame.minX - r.minX, y: list.frame.minY - r.minY, width: list.bounds.width, height: list.bounds.height)
      let img = UIGraphicsImageRenderer(size: r.size, format: f).image { _ in list.drawHierarchy(in: at, afterScreenUpdates: after) }
      return UIImageView(image: img)
    }
    guard h.window != nil, r.height > 0, r.width > 0 else {
      UIView.performWithoutAnimation { change(); h.setNeedsLayout(); h.layoutIfNeeded() }; return
    }
    let old = shot(false)
    UIView.performWithoutAnimation { change(); h.setNeedsLayout(); h.layoutIfNeeded() }
    let new = shot(true)
    let cover = UIView(frame: r); cover.backgroundColor = h.look.bg; cover.isUserInteractionEnabled = false; cover.clipsToBounds = true
    old.frame = cover.bounds; new.frame = cover.bounds.offsetBy(dx: CGFloat(-dir) * W, dy: 0)
    cover.addSubview(old); cover.addSubview(new)
    // (under the switch when it's stuck under the bar — a direct part of the page; else over the list, under the bar)
    // (it must be over the page's list — under it, the list itself showed through beside the slide: twice, Haris 2026-11-04)
    // (the switch is usually in the list itself — then its parent is the list's scroll view, and the slide went UNDER
    //  the list: the real new list showed at once with the picture sliding behind it, twice — Haris 2026-11-05)
    if let pin = segV?.superview, pin.superview === h, !(pin is UIScrollView) { h.insertSubview(cover, belowSubview: pin) }
    else if let sc = h.subviews.first(where: { $0 is UIScrollView }) { h.insertSubview(cover, aboveSubview: sc) }
    else { h.addSubview(cover) }
    UIView.animate(withDuration: 0.34, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      old.frame = cover.bounds.offsetBy(dx: CGFloat(dir) * W, dy: 0); new.frame = cover.bounds
    } completion: { _ in cover.removeFromSuperview() }
  }
  private func open(_ kind: String, _ id: String? = nil) {
    guard !leaving else { return }
    ProfileAskCard.current?.go()   // (another page: the birthday / city card slips away)
    if kind == "team" { teamTab = 0; teamQ = ""; send(["ev": "team", "on": true]) }
    if kind == "about" { loadAbout(false) }
    if kind == "profile" { send(["ev": "pf", "on": true]) }
    if kind == "trash" { send(["ev": "tr", "on": true]) }
    if kind == "plans" { plMonth = plMonth ?? ""; send(["ev": "pl", "on": true, "month": plMonth ?? ""]) }
    if kind == "plan", let id = id { let p = id.split(separator: "|").map(String.init); send(["ev": "plOpen", "pid": p.first ?? "", "month": p.count > 1 ? p[1] : ""]) }
    push(screen(kind, id), animated: true)
  }
  private func push(_ s: Screen, animated: Bool) {
    let W = main.view.bounds.width
    let u = stack.last?.h
    stack.append(s); watchTouches()
    draw(s)
    s.h.isHidden = false
    if animated && main.view.window != nil && u != nil {
      s.h.transform = CGAffineTransform(translationX: W, y: 0)
      UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        s.h.transform = .identity; u?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
      } completion: { _ in if !s.h.isHidden, s.h.transform == .identity { u?.isHidden = true; u?.transform = .identity }; self.main.updateCorner() }
    } else { s.h.transform = .identity; u?.isHidden = true }
    main.edgePanOn(); main.updateCorner()
  }
  func pop(animated: Bool = true) {
    guard stack.count > 1, let s = stack.last, !leaving else { return }
    let W = main.view.bounds.width
    let u = stack[stack.count - 2].h
    u.isHidden = false; u.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    leaving = true
    main.updateCorner()
    let finish = {
      s.h.removeFromSuperview()
      if let i = self.stack.firstIndex(where: { $0.h === s.h }) { self.stack.remove(at: i) }
      self.leaving = false
      if s.kind == "team", !self.stack.contains(where: { $0.kind == "team" }) { self.send(["ev": "team", "on": false]) }
      if s.kind == "profile" { self.send(["ev": "pf", "on": false]) }
      if s.kind == "plans" { self.send(["ev": "pl", "on": false]) }
      if s.kind == "plan" { self.send(["ev": "plOpen", "pid": ""]) }
      if s.kind == "trash" { self.send(["ev": "tr", "on": false]) }
      if let t = self.stack.last { self.draw(t) }
      self.main.edgePanOn(); self.main.updateCorner()
    }
    if animated {
      UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        s.h.transform = CGAffineTransform(translationX: W, y: 0); u.transform = .identity
      } completion: { _ in finish() }
    } else { u.transform = .identity; finish() }
  }
  // Me tapped again from a page under it: what's on top slides away to the right, Me comes back under it
  func backToRoot() {
    guard stack.count > 1, let topS = stack.last, !leaving else { stack.first?.h.scrollToTop(); return }
    let W = main.view.bounds.width
    let snap = topS.h.snapshotView(afterScreenUpdates: false)
    if let sn = snap { sn.frame = topS.h.frame; main.view.insertSubview(sn, belowSubview: main.tabBar) }
    let root = stack[0]
    let gone = stack.dropFirst()
    if gone.contains(where: { $0.kind == "team" }) { send(["ev": "team", "on": false]) }
    if gone.contains(where: { $0.kind == "profile" }) { send(["ev": "pf", "on": false]) }
    if gone.contains(where: { $0.kind == "trash" }) { send(["ev": "tr", "on": false]) }
    gone.forEach { $0.h.removeFromSuperview() }
    stack = [root]
    root.h.isHidden = false; root.h.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    draw(root)
    main.edgePanOn(); main.updateCorner()
    UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      snap?.transform = CGAffineTransform(translationX: W, y: 0); root.h.transform = .identity
    } completion: { _ in snap?.removeFromSuperview() }
  }
  // the root on screen at once, the rest gone (a page deeper than Me — My profile — going back with the tab's slide)
  func rootUnder() -> UIView? {
    guard let root = stack.first else { return nil }
    if stack.dropFirst().contains(where: { $0.kind == "team" }) { send(["ev": "team", "on": false]) }
    if stack.dropFirst().contains(where: { $0.kind == "profile" }) { send(["ev": "pf", "on": false]) }
    if stack.dropFirst().contains(where: { $0.kind == "trash" }) { send(["ev": "tr", "on": false]) }
    stack.dropFirst().forEach { $0.h.removeFromSuperview() }
    stack = [root]
    root.h.transform = .identity
    return borrow()
  }
  // the edge swipe: the top one follows the finger, the one under it coming back, the top buttons between them
  private var panFrom: ((CornerButton.Spot, CornerButton.Spot, CornerButton.Spot), (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot))?
  func edgePan(_ g: UIScreenEdgePanGestureRecognizer) {
    guard stack.count > 1, let s = stack.last, !leaving else { return }
    let W = main.view.bounds.width
    let x = max(0, g.translation(in: main.view).x)
    let u = stack[stack.count - 2].h
    switch g.state {
    case .began:
      s.h.endEditing(true)
      u.isHidden = false; u.transform = .identity; panFrom = (main.cornerTargetFor(s.h), main.cornerTargetFor(u))
      u.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    case .changed:
      s.h.transform = CGAffineTransform(translationX: x, y: 0)
      u.transform = CGAffineTransform(translationX: -W * 0.3 * (1 - x / W), y: 0)
      if let f = panFrom { main.corner.between(f.0, f.1, x / W) }
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: main.view).x
      let go = g.state == .ended && (v > 300 || (x > W * 0.4 && v > -200))
      panFrom = nil
      if go {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        leaving = true; main.updateCorner()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          s.h.transform = CGAffineTransform(translationX: W, y: 0); u.transform = .identity
        } completion: { _ in self.leaving = false; self.pop(animated: false) }
      } else {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          s.h.transform = .identity; u.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
        } completion: { _ in if s.h.transform == .identity { u.isHidden = true; u.transform = .identity } }
        main.updateCorner()
      }
    default: break
    }
  }
  // (for the self-test)
  func selfOpen(_ kind: String) { open(kind) }
  func geo(corner: String) -> [String: Any] {
    let h = stack.last?.h
    let groups: [[String: Any]] = ((model["team"] as? [String: Any])?["groups"] as? [[String: Any]]) ?? []
    var people = 0
    for g in groups { people += (g["people"] as? [Any])?.count ?? 0 }
    var rows = 0
    if let h = h { for v in h.assetsParts.values { if let g = v as? SetGroup, !g.isEmpty { rows += 1 } } }
    let parts: Int = h?.assetsParts.count ?? 0
    let card: Bool = model["card"] != nil
    let profile: Bool = model["profile"] is [String: Any]
    return ["open": isOpen, "screens": stack.count, "kind": kind, "parts": parts, "shown": shown != nil, "corner": corner, "people": people, "rows": rows, "card": card, "profile": profile]
  }
  func refresh() { if isOpen { main.pageJS("window.__e11MeResend && window.__e11MeResend()"); if stack.contains(where: { $0.kind == "about" }) { loadAbout(false) } } }

  // ---------- what's on each ----------
  func relight(_ l: Bool) { guard l != light else { return }; light = l; stack.forEach { draw($0) } }
  private func redrawRoot() { if let s = stack.first(where: { $0.kind == "me" }) { draw(s) } }
  private func draw(_ s: Screen) {
    var mm: [String: Any] = ["show": true, "me": me ?? "", "look": ["light": light]]
    if let l = main.homeLook as? [String: Any], (l["light"] as? Bool) == light { mm["look"] = l }
    if s.kind == "me" { mm["title"] = "Me"; mm["date"] = "E11 Console App" }
    if s.h.assets == "overviewTab" { mm["title"] = "Overview"; mm["date"] = Date().formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    if s.h.assets == "claimsTab" { mm["title"] = "Claims"; mm["date"] = "Reimbursements" }
    if s.h.assets == "reviewsTab" { let n = ((model["reviews"] as? [String: Any])?["waiting"] as? [Any])?.count ?? 0; mm["title"] = "Reviews"; mm["date"] = model["reviews"] == nil ? "" : n == 0 ? "Nothing waiting" : n == 1 ? "1 request waiting" : "\(n) requests waiting" }
    if s.h.assets == "expensesTab" { mm["title"] = "Expenses"; mm["date"] = exSeg == 0 ? "Subscriptions" : "Office expenses" }
    if s.h.assets == "teamTab" { mm["title"] = "Team members"; mm["date"] = team.isEmpty ? "" : "\(team["active"] as? Int ?? 0) active · \(team["pastN"] as? Int ?? 0) past" }
    if s.h.assets == "plansTab" || s.h.assets == "plansPage" { mm["title"] = "Content plans"; mm["date"] = (model["plans"] as? [String: Any])?["label"] as? String ?? "" }   // (the line under the big title, as the other tabs have — Haris 2026-11-03)
    s.h.bottomRoom = (main.tabBar.isHidden ? 40 : main.view.bounds.height - main.tabBar.frame.minY) + 96
    s.h.tabTop = main.tabBar.isHidden ? nil : main.tabPillTop
    s.h.update(mm)
  }
  private func part<T: UIView>(_ h: HomeView, _ k: String, _ make: () -> T) -> T {
    if let v = h.assetsParts[k] as? T { return v }
    let v = make(); h.assetsParts[k] = v; return v
  }
  private func head(_ h: HomeView, _ k: String, _ t: String) -> SetHead { let v = part(h, "h." + k) { SetHead() }; v.set(t); return v }
  private func group(_ h: HomeView, _ k: String, _ items: [SetItem]) -> SetGroup { let v = part(h, "g." + k) { SetGroup() }; v.set(items, look: h.look); return v }
  private func foot(_ h: HomeView, _ k: String, _ t: String, centered: Bool = false) -> SetFoot { let v = part(h, "f." + k) { SetFoot() }; v.set(t, centered: centered); return v }
  private func screenOf(_ h: HomeView) -> Screen? { stack.first { $0.h === h } }
  private static func rgb(_ a: [Int]) -> UIColor { UIColor(red: CGFloat(a[0]) / 255, green: CGFloat(a[1]) / 255, blue: CGFloat(a[2]) / 255, alpha: 1) }
  private var themeWord: String { switch model["theme"] as? String { case "light": return "Light"; case "dark": return "Dark"; default: return "Automatic" } }

  private func blocks(_ h: HomeView) {
    guard let s = screenOf(h) else { return }
    let L = h.look
    var out: [UIView] = []
    h.setFab("", "plus", nil)
    switch s.kind {
    case "me":
      if let c = model["card"] as? [String: Any] {
        let card = part(h, "card") { MeCardBlock() }
        card.set(c, look: L)
        card.onTap = { [weak self] in self?.open("profile") }   // (the app's own My profile, 2026-11-03)
        out.append(card)
      } else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n) }
      let work = ((model["work"] as? [[String: Any]]) ?? []).map { w -> SetItem in
        let k = w["k"] as? String ?? ""
        var it = SetItem(key: k, title: w["t"] as? String ?? "", sub: w["s"] as? String ?? "", sym: w["sym"] as? String, col: NativeSheetVC.color(w["col"]),
                       tap: { [weak self] in guard let self = self else { return }; if k == "team" || k == "trash" || k == "plans" { self.open(k) } else if k == "projects" { self.main.openClientsFromMe() } else { if k == "clients" { self.coverWait = Date() }; self.send(["ev": "nav", "to": k]) } })
        it.count = w["n"] as? Int ?? 0
        return it
      }
      if !work.isEmpty { out.append(head(h, "work", "Work")); out.append(group(h, "work", work)) }
      var phone: [SetItem] = [SetItem(key: "shortcuts", title: "Shortcuts", sub: "Quicker ways to do things", sym: "command", col: .systemBlue, badge: "New", tap: { [weak self] in self?.open("shortcuts") })]
      if let p = model["push"] as? [String: Any] {
        phone.append(SetItem(key: "push", title: "Notifications", sub: p["sub"] as? String ?? "", value: (p["busy"] as? Bool) == true ? "…" : p["label"] as? String ?? "", sym: "bell.badge.fill", col: .systemRed, tap: { [weak self] in self?.pushTap() }))
      }
      if let lk = model["lock"] as? [String: Any] {
        let kindW = lk["kind"] as? String ?? "Face ID"
        phone.append(SetItem(key: "lock", title: "\(kindW) lock", sub: "Asks for your face when E11 Console opens", sym: kindW == "Touch ID" ? "touchid" : "faceid", col: .systemGreen, toggle: (lk["on"] as? Bool) == true, flip: { [weak self] on in self?.lockFlip(on) }))
      }
      if let d = model["digest"] as? [String: Any] {
        phone.append(SetItem(key: "digest", title: "Morning summary", sub: "10:30 am, Monday to Friday", sym: "sun.max.fill", col: .systemYellow, toggle: (d["on"] as? Bool) == true, flip: { [weak self, weak h] on in self?.pfSet("digest", ["on": on], page: ["ev": "digest"]); if let h = h { self?.settle(h) } }))
      }
      phone.append(SetItem(key: "appearance", title: "Appearance", value: themeWord, sym: "circle.lefthalf.filled", col: .systemIndigo, tap: { [weak self] in self?.open("appearance") }))
      out.append(head(h, "phone", "This iPhone")); out.append(group(h, "phone", phone))
      if (model["about"] as? Bool) == true {
        out.append(head(h, "about", "About"))
        out.append(group(h, "about", [SetItem(key: "about", title: "About", sub: (model["canUpdate"] as? Bool) == true ? "What’s new · App updates" : "What’s new", sym: "info", col: .systemGray, tap: { [weak self] in self?.open("about") })]))
      }
      if let t = model["test"] as? [String: Any] {
        var test: [SetItem] = []
        if (t["viewAs"] as? Bool) == true {
          test.append(SetItem(key: "viewAs", title: "View as…", sub: (t["viewing"] as? String).map { "Viewing as \($0)" } ?? "Test site only — use the app as a team member", sym: "person.2.fill", col: .systemTeal, tap: { [weak self] in self?.viewAsPick() }))
          if t["viewing"] is String { test.append(SetItem(key: "backToMe", title: "Back to me", sym: "arrow.uturn.backward", col: .systemTeal, chevron: false, tap: { [weak self] in self?.viewAsSet(nil) })) }
        }
        // (the step 9 trial: the app without the website — Haris checks it before the website goes for good)
        test.append(SetItem(key: "noPage", title: "Without the website", sub: "Step 9 trial — the app on its own", sym: "bolt.horizontal.fill", col: .systemOrange, toggle: Main.noPage, flip: { [weak self] on in self?.main.setNoPage(on) }))
        if (t["sample"] as? Bool) == true { test.append(SetItem(key: "sample", title: "Start fresh with sample data", sub: "Test site only: wipes everything except you", chevron: false, danger: true, tap: { [weak self] in self?.send(["ev": "sample"]) })) }
        if !test.isEmpty { out.append(head(h, "test", "Test site")); out.append(group(h, "test", test)) }
      }
      out.append(head(h, "out", ""))
      out.append(group(h, "out", [SetItem(key: "signOut", title: "Sign out", chevron: false, danger: true, tap: { [weak self] in self?.signOutAsk() })]))
      // (the sync status in the version's place — Haris 2026-11-03; the version is on About)
      if let st = model["sync"] as? String, !st.isEmpty {
        let (t, c): (String, UIColor) = {
          switch st {
          case "saving": return ("Syncing…", .systemYellow)
          case "reconnecting": return ("Reconnecting…", .systemYellow)
          case "offline": return ("Offline — changes will sync", .systemRed)
          case "error": return ("Not synced to E11 Server", .systemRed)
          default: return ("Synced to E11 Server", .systemGreen)
          }
        }()
        let f = part(h, "f.ver") { SetFoot() }; f.setDot(t, c); out.append(f)
      }
    case "appearance":
      h.drawAssetsBar(name: "Appearance", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      let tb = part(h, "theme") { ThemeBlock() }
      tb.onPick = { [weak self] m in self?.setTheme(m) }
      tb.set(mode: model["theme"] as? String ?? "auto", now: model["themeNow"] as? String ?? "light", times: model["times"] as? String ?? "", look: L)
      out.append(tb)
      out.append(foot(h, "ap", (model["theme"] as? String ?? "auto") == "auto" ? "With Automatic on, the app switches by itself — the ticked picture is what it is now. Choosing Light or Dark turns Automatic off." : "Light or Dark all the time. Turn on Automatic to follow sunrise and sunset in Dubai."))
    case "about":
      h.drawAssetsBar(name: "About", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      var above: CGFloat = 0
      let W = h.bounds.width > 0 ? h.bounds.width : main.view.bounds.width
      if (model["canUpdate"] as? Bool) == true {
        let u = (about["updates"] as? [String: Any]) ?? [:]
        let card = part(h, "upd") { InfoCard() }
        var parts: [InfoCard.Part] = []
        if let busy = about["busy"] as? String, !busy.isEmpty { parts = [.title("arrow.down.circle", "Updating E11 Console…"), .note(busy)] }
        else if u.isEmpty { parts = [.note("Checking for updates…")] }
        else if (u["unmanaged"] as? Bool) == true { parts = [.note("This copy (\(u["running"] as? String ?? "")) isn’t managed by the updater.")] }
        else {
          let running: String = (u["running"] as? String ?? "") + ((u["test"] as? Bool) == true ? " · Test copy" : "")
          let checked: String = u["checked"] as? String ?? ""
          if let a = u["available"] as? [String: Any] {
            let tonight: String = (a["hour"] as? String).map { "Installs by itself tonight at \($0) if you don’t. " } ?? ""
            let name: String = a["name"] as? String ?? ""
            let can: Bool = (u["busy"] as? Bool) != true
            parts = [.kicker("Update available"), .big(name), .kv("Running", running), .kv("Last checked", checked),
                     .button("Update now", true, can, { [weak self] in self?.updateNow() }),
                     .note(tonight + "A copy of the data is made first; it takes about 10 seconds.")]
          } else {
            parts = [.status("✓ You’re up to date", .systemGreen), .kv("Running", running), .kv("Last checked", checked),
                     .button("Check again", false, true, { [weak self] in self?.loadAbout(true) })]
          }
          if let e = u["error"] as? String, !e.isEmpty { parts.insert(.note(e), at: 0) }
        }
        card.set(parts, sig: jsonString(u) + "|\(about["busy"] ?? "")", look: L)
        out.append(head(h, "upd", "App updates")); out.append(card)
      }
      if (model["owner"] as? Bool) == true && (model["canUpdate"] as? Bool) == true {
        let v = (about["video"] as? [String: Any]) ?? [:]
        let card = part(h, "vhw") { InfoCard() }
        var parts: [InfoCard.Part] = [.title("play.rectangle", "Video hardware")]
        if let e = v["error"] as? String { parts.append(.note(e)) }
        else if let c = v["checking"] as? String, !c.isEmpty, v["title"] == nil { parts.append(.note(c)) }
        else if let t = v["title"] as? String {
          let st = v["state"] as? String ?? ""
          parts.append(.status((st == "ready" ? "✓ " : st == "missing" ? "– " : "! ") + t, st == "ready" ? .systemGreen : st == "missing" ? .secondaryLabel : .systemOrange))
          let d = [v["detail"] as? String ?? "", (v["checked"] as? String).flatMap { $0.isEmpty ? nil : "checked \($0)" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
          if !d.isEmpty { parts.append(.note(d)) }
          if let l = v["light"] as? String, !l.isEmpty { parts.append(.note("Light copies of videos (720p, for viewing): " + l)) }
          if let c = v["checking"] as? String, !c.isEmpty { parts.append(.note(c)) }
        } else { parts.append(.note("Checking the NAS…")) }
        parts.append(.button("Check again", false, true, { [weak self] in self?.loadVideo(true) }))
        card.set(parts, sig: jsonString(v), look: L)
        out.append(card)
        let imp = part(h, "imp") { InfoCard() }
        imp.set([.title("square.and.arrow.down", "Move data from the Mac app"),
                  .note("Choose e11-data.json from the “E11 Console Data” folder on the Mac. Tasks, clients, comments, people, notifications and client assets are added to the server."),
                  .button("Choose e11-data.json…", false, true, { [weak self] in self?.send(["ev": "import"]) })], sig: "imp", look: L)
        out.append(imp)
      }
      // (What's new right under the cards' own gap)
      out.append(head(h, "wn", "What’s new"))
      let notes = part(h, "notes") { NotesBox() }
      let n = (about["notes"] as? [String: Any]) ?? [:]
      notes.set(name: n["name"] as? String ?? (model["version"] as? String ?? ""), date: n["at"] as? String ?? "", notes: n.isEmpty ? "Loading…" : n["notes"] as? String ?? "", look: L)
      for v in out { if let b = v as? HomeBlock { above += b.blockHeight(W) } }
      notes.fill = max(240, h.listBottom - h.listTop - above)
      out.append(notes)
    case "shortcuts":
      h.drawAssetsBar(name: "Shortcuts", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      out.append(foot(h, "lead", "Quicker ways to do things in the iPhone app."))
      for (i, sec) in MeCtl.shortcuts.enumerated() {
        out.append(head(h, "s\(i)", sec.0 + (sec.1.isEmpty ? "" : " · " + sec.1)))
        out.append(group(h, "s\(i)", sec.2.enumerated().map { j, r in SetItem(key: "\(i).\(j)", title: r.0, sub: r.1, sym: r.3, col: r.4, chevron: false, pill: r.2) }))
      }
      out.append(foot(h, "end", "Only in the iPhone app."))
    case "profile":
      profileBlocks(h, &out)
    case "trash":
      trashBlocks(h, &out)
    case "team":
      teamBlocks(h, &out)
    case "overview":
      overviewBlocks(h, &out)
    case "reviews": reviewsBlocks(h, &out)
    case "review": reviewBlocks(h, s.id ?? "", &out)
    case "claims":
      claimsBlocks(h, &out)
    case "expenses":
      expensesBlocks(h, &out)
    case "member":
      memberBlocks(h, s.id ?? "", &out)
    case "plans":
      plansBlocks(h, &out)
    case "plan":
      planBlocks(h, s.id ?? "", &out)
    default: break
    }
    // (a section title first on the page, or right after a card's own gap: the short one)
    for (i, v) in out.enumerated() { if let sh = v as? SetHead { sh.first = s.kind != "me" && (i == 0 || out[i - 1] is InfoCard) } }
    h.setContent(out)
  }
  // a switch the page may not change (Face ID asked and cancelled): back as the page has it, a moment later
  private func settle(_ h: HomeView) { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak h] in if let h = h { self?.blocks(h); h.setNeedsLayout() } } }

  private var team: [String: Any] { (model["team"] as? [String: Any]) ?? [:] }
  private func people(_ list: [[String: Any]], hold: Bool) -> [SetItem] {
    list.map { p in
      let id = p["id"] as? String ?? ""
      let pills: [(String, UIColor)] = ((p["pills"] as? [[String: Any]]) ?? []).map { x -> (String, UIColor) in (x["t"] as? String ?? "", NativeSheetVC.color(x["c"]) ?? .systemGray) }
      let pending: Bool = (p["pending"] as? Bool) == true
      let sub: String = pending ? "Hasn’t signed in yet" : (p["email"] as? String ?? "")
      let title: String = (p["name"] as? String ?? "") + ((p["you"] as? Bool) == true ? " (you)" : "")
      let pic: (photo: String?, ini: String, rgb: UIColor) = (p["photo"] as? String, p["ini"] as? String ?? "", NativeSheetVC.color(p["rgb"]) ?? .systemGray)
      let past: Bool = (p["past"] as? Bool) == true
      let held: (() -> Void)? = hold ? { [weak self] in self?.memberMenu(id) } : nil
      return SetItem(key: id, title: title, sub: sub, pills: pills, person: pic, warn: pending, dim: past, tap: { [weak self] in self?.open("member", id) }, hold: held)
    }
  }
  // an Office Admin's Overview (Haris 2026-11-04): with Finance — the three cards, then the latest 3 in Client Assets, the 3
  // claims waiting for HR approval and the latest 3 office expenses; without — the latest 10 in Client Assets
  private func overviewBlocks(_ h: HomeView, _ out: inout [UIView]) {
    guard let o = model["overview"] as? [String: Any] else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n); return }
    if let cards = o["cards"] as? [[String: Any]] { let c = part(h, "cards") { OvCards() }; c.set(cards, look: h.look); out.append(c) }
    let sec = { (k: String, t: String, to: String?) -> SetHead in
      let v = self.head(h, k, t); v.link(to == nil ? nil : "All"); v.onLink = { [weak self] in if let to = to { self?.ovGo(to) } }; return v }
    let files = ((o["assets"] as? [[String: Any]]) ?? []).map { f -> SetItem in
      var it = SetItem(key: "f." + (f["id"] as? String ?? ""), title: f["name"] as? String ?? "", sub: f["where"] as? String ?? "", value: f["when"] as? String ?? "", chevron: false, tap: { [weak self] in self?.send(["ev": "ovFile", "id": f["id"] as? String ?? "", "path": f["path"] as? String ?? "", "name": f["name"] as? String ?? ""]) })
      it.person = (photo: f["pic"] as? String, ini: f["ext"] as? String ?? "", rgb: NativeSheetVC.color(f["rgb"]) ?? .systemGray)
      return it
    }
    out.append(sec("ova", "Client Assets · latest", "assets"))
    if files.isEmpty { out.append(foot(h, "ova0", "No files yet.")) } else { out.append(group(h, "ova", files)) }
    if (o["fin"] as? Bool) == true {
      let cl = ((o["claims"] as? [[String: Any]]) ?? []).map { c -> SetItem in
        var it = SetItem(key: "c." + (c["id"] as? String ?? ""), title: c["name"] as? String ?? "", sub: c["sub"] as? String ?? "", value: c["amt"] as? String ?? "", tap: { [weak self] in self?.send(["ev": "ovClaim", "id": c["id"] as? String ?? ""]) })
        it.person = (photo: nil, ini: c["ini"] as? String ?? "", rgb: NativeSheetVC.color(c["rgb"]) ?? .systemGray)
        return it
      }
      out.append(sec("ovc", "Need HR approval", "claims"))
      if cl.isEmpty { out.append(foot(h, "ovc0", "No claims waiting.")) } else { out.append(group(h, "ovc", cl)) }
      let ex = ((o["expenses"] as? [[String: Any]]) ?? []).map { x in SetItem(key: "x." + (x["id"] as? String ?? ""), title: x["name"] as? String ?? "", sub: x["sub"] as? String ?? "", value: x["amt"] as? String ?? "", sym: "doc.text.fill", col: .systemGray, chevron: false) }
      out.append(sec("ovx", "Office expenses · latest", "expenses"))
      if ex.isEmpty { out.append(foot(h, "ovx0", "None this month yet.")) } else { out.append(group(h, "ovx", ex)) }
    }
  }
  // Overview's "All": that tab, as if tapped (Claims, Expenses, Client Assets) — never the website's Home underneath
  // (Haris 2026-11-04: it went to "E11 Day"); Client Assets with Finance is Me's page
  private func ovGo(_ to: String) {
    let key = ["assets": "clients", "claims": "fin-reimb", "expenses": "fin-expenses"][to] ?? ""
    // (on the list the section was about: Need approval; Office expenses — Haris 2026-11-04)
    if to == "claims" { clSeg = 0 }
    if to == "expenses" { exSeg = 1 }
    if main.tabKeys.contains(key) { main.selectTab(key); return }
    if key == "clients" { coverWait = Date(); send(["ev": "nav", "to": "clients"]) }
  }
  // ---------- the CD's Reviews (Haris 2026-11-04) ----------
  private func reviewsBlocks(_ h: HomeView, _ out: inout [UIView]) {
    guard let m = model["reviews"] as? [String: Any] else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n); return }
    let wait = (m["waiting"] as? [[String: Any]]) ?? [], done = (m["reviewed"] as? [[String: Any]]) ?? []
    // (an Inbox update about a request: Waiting or Reviewed, scrolled to it, and it pulses — Haris 2026-11-04)
    var focus: String? = nil
    if let f = m["focus"] as? [String: Any], let n = f["n"] as? Int, n != rvFocusN, let fid = f["id"] as? String {
      rvFocusN = n; focus = fid
      rvSeg = done.contains(where: { ($0["id"] as? String) == fid }) ? 1 : 0
    }
    let seg = part(h, "seg") { SegBlock() }
    seg.set("Waiting · \(wait.count)", "Reviewed · \(done.count)", rvSeg)
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h else { return }; self.rvSeg = i; UIView.performWithoutAnimation { self.blocks(h); h.setNeedsLayout(); h.layoutIfNeeded() } }
    // (Waiting · Reviewed stuck under the bar once it reaches it — the standard)
    let pin = part(h, "pin") { PinStack() }
    pin.set([seg])
    if h.pinHead !== pin { h.pinHead = pin }
    let rows = rvSeg == 0 ? wait : done
    if rows.isEmpty { out.append(foot(h, "rv0", rvSeg == 0 ? "All caught up — new requests appear here, and you get a notification." : "Decisions from the last 15 days appear here.", centered: true)); return }
    if rvSeg == 1 { out.append(foot(h, "rvsub", "Last 15 days")) }
    let list = part(h, rvSeg == 0 ? "rvw" : "rvd") { ReviewList() }
    list.set(rows, look: h.look, decided: rvSeg == 1)
    list.onOpen = { [weak self] id in self?.open("review", id) }
    out.append(list)
    if let fid = focus {
      if stack.count > 1, stack.first?.h === h { DispatchQueue.main.async { [weak self] in self?.backToRoot() } }   // (a request open on top: back to the list first)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak h, weak list] in guard let h = h, let list = list, let row = list.row(fid) else { return }; h.scrollToShow(row); list.pulse(fid) }
    }
  }
  private func reviewItem(_ id: String) -> ([String: Any], Bool, Int, Int)? {
    guard let m = model["reviews"] as? [String: Any] else { return nil }
    let wait = (m["waiting"] as? [[String: Any]]) ?? [], done = (m["reviewed"] as? [[String: Any]]) ?? []
    if let i = wait.firstIndex(where: { ($0["id"] as? String) == id }) { return (wait[i], false, i + 1, wait.count) }
    if let x = done.first(where: { ($0["id"] as? String) == id }) { return (x, true, 0, 0) }
    return nil
  }
  private func reviewBlocks(_ h: HomeView, _ id: String, _ out: inout [UIView]) {
    guard let it = reviewItem(id) else {
      h.drawAssetsBar(name: "Review request", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      let w = part(h, "wait") { AssetsNote() }; w.label.text = model["reviews"] == nil ? "Loading…" : "This request isn’t waiting any more."; out.append(w); return
    }
    let (x, decided, n, of) = it
    h.drawAssetsBar(name: decided ? "Review request" : "Review request · \(n) of \(of)", sub: x["task"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    let tid = x["tid"] as? String ?? ""
    let hero = part(h, "hero") { ReviewHero() }
    hero.set(x, look: h.look)
    hero.onFile = { [weak self] fid in self?.send(["ev": "rvFile", "id": id, "fid": fid]) }
    out.append(hero)
    if decided, let r = x["res"] as? [String: Any] {
      out.append(foot(h, "rvres", (r["long"] as? String ?? "") + " · " + (x["sub"] as? String ?? "").components(separatedBy: " · ").last!, centered: true))
      if let note = x["note"] as? String, !note.isEmpty { let v = part(h, "rvnote") { ReviewNote() }; v.set("Your note", note, look: h.look); out.append(v) }
    }
    if !decided, let last = x["last"] as? String, !last.isEmpty { let v = part(h, "rvlast") { ReviewNote() }; v.set("Your note last round", last, look: h.look); out.append(v) }
    if let b = x["brief"] as? String, !b.isEmpty { let v = part(h, "rvbrief") { ReviewNote() }; v.set("Brief", b, look: h.look); out.append(v) }
    out.append(group(h, "rvtask", [SetItem(key: "task", title: "Open task", sub: "", sym: "checklist", col: .systemBlue, tap: { [weak self] in self?.send(["ev": "rvTask", "tid": tid]) })]))
    guard !decided else { return }
    let acts = part(h, "acts") { ReviewActs() }
    acts.onApprove = { [weak self, weak h] in
      guard let self = self else { return }
      self.request(["ev": "rvApprove", "id": id]) { [weak h] r in
        if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.toast(["t": "Approved — \(x["first"] as? String ?? "") told"]); self.afterDecision(r["next"] as? String) }
        else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) }
      }
    }
    acts.onAmend = { [weak self, weak h] in
      guard let self = self else { return }
      let vc = AmendSheetVC(files: (x["files"] as? [[String: Any]]) ?? [], first: x["first"] as? String ?? "", dark: !self.light)
      vc.onFile = { [weak self] fid in self?.send(["ev": "rvFile", "id": id, "fid": fid]) }
      vc.onSend = { [weak self, weak h] need, note, done in
        var ev: [String: Any] = ["ev": "rvAmend", "id": id, "note": note]
        if let n = need { ev["need"] = n }
        self?.request(ev) { r in
          if (r["ok"] as? Bool) == true {
            done(nil)
            let okN = ((x["files"] as? [Any])?.count ?? 0) - (need?.count ?? ((x["files"] as? [Any])?.count ?? 0))
            h?.toast(["t": okN > 0 ? "\(okN) approved · \(need?.count ?? 0) sent back" : "Sent back to \(x["first"] as? String ?? "")"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self?.afterDecision(r["next"] as? String) }
          } else { done(r["error"] as? String ?? "That didn’t work — try again") }
        }
      }
      self.main.topMost().present(vc.inNav(), animated: true)
    }
    out.append(acts)
  }
  // decided: on to the next request waiting (it slides in), or back to the list when there's none
  private func afterDecision(_ next: String?) {
    guard let s = stack.last, s.kind == "review" else { return }
    if let n = next, !n.isEmpty, n != s.id {
      let W = main.view.bounds.width
      let old = s.h
      let ns = screen("review", n)
      stack[stack.count - 1] = ns
      draw(ns); ns.h.isHidden = false; ns.h.transform = CGAffineTransform(translationX: W, y: 0)
      UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        ns.h.transform = .identity; old.transform = CGAffineTransform(translationX: -W * 0.3, y: 0); old.alpha = 0
      } completion: { _ in old.removeFromSuperview(); self.main.updateCorner() }
      main.edgePanOn(); main.updateCorner()
    } else { pop() }
  }
  // ---------- an Office Admin's Claims (Haris 2026-11-04) ----------
  private func claimsBlocks(_ h: HomeView, _ out: inout [UIView]) {
    guard let m = model["claims"] as? [String: Any] else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n); return }
    let need = (m["need"] as? [[String: Any]]) ?? [], all = (m["all"] as? [[String: Any]]) ?? []
    let admin = (m["admin"] as? Bool) == true
    let seg = part(h, "seg") { SegBlock() }
    seg.set("Need approval · \(need.count)", "All · \(all.count)", clSeg)
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h else { return }; self.clSeg = i; UIView.performWithoutAnimation { self.blocks(h); h.setNeedsLayout(); h.layoutIfNeeded() } }
    out.append(seg)
    out.append(foot(h, "clsub", "\(m["label"] as? String ?? "") · \(m["sub"] as? String ?? "")"))
    let rows = clSeg == 0 ? need : all
    if rows.isEmpty { out.append(foot(h, "cl0", clSeg == 0 ? "Nothing waiting for HR approval." : "No claims this month yet.", centered: true)) }
    else {
      let list = part(h, "claims") { SwipeRows() }
      list.set(rows, look: h.look, admin: admin)
      list.onApprove = { [weak self, weak h] id in self?.request(["ev": "clApprove", "id": id]) { r in if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.toast(["t": "Marked HR approved"]) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } } }
      list.onOpen = { [weak self] id in self?.send(["ev": "clOpen", "id": id]) }
      list.onHold = { [weak self, weak h] id in guard let self = self, admin, let row = rows.first(where: { ($0["id"] as? String) == id }), (row["st"] as? String) != "paid" else { return }; self.paidOn(h, id, sub: "\(row["name"] as? String ?? "") · \(row["amt"] as? String ?? "")") }
      out.append(list)
    }
    h.setFab("Add claim", "plus", admin ? { [weak self, weak h] in if let h = h { self?.addClaim(h, m) } } : nil)
  }
  // hold a claim → Paid on: iPhone's own calendar (as the website, a submitted one is HR approved with it)
  private func paidOn(_ h: HomeView?, _ id: String, sub: String = "") {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let fmt = DateFormatter(); fmt.calendar = Calendar(identifier: .gregorian); fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyy-MM-dd"
    main.topMost().present(DateSheetVC(["value": fmt.string(from: Date()), "min": "", "max": "", "clearable": false, "md": false, "title": "Paid on", "sub": sub], dark: !light) { [weak self, weak h] r in
      if (r["cancel"] as? Bool) == true || (r["ok"] as? Bool) == false { return }
      guard let d = r["date"] as? String, !d.isEmpty else { return }
      self?.request(["ev": "clPaid", "id": id, "date": d]) { r in if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.toast(["t": "Marked paid"]) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } }
    }, animated: true)
  }
  private func addClaim(_ h: HomeView, _ m: [String: Any]) {
    let people = ((m["people"] as? [[String: Any]]) ?? []).map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") }
    let months = ((m["months"] as? [[String: Any]]) ?? []).map { ($0["m"] as? String ?? "", $0["t"] as? String ?? "") }
    let vc = MoneyFormVC(kind: .claim, people: people, months: months, dark: !light, cookies: main.serverHome.cookies)
    vc.onPerson = { [weak self] name, done in self?.request(["ev": "clPerson", "name": name]) { r in if (r["ok"] as? Bool) == true { done(r["id"] as? String, r["name"] as? String) } else { done(nil, nil) } } }
    vc.onSave = { [weak self, weak h] f, done in
      self?.request(["ev": "clAdd", "who": f["who"] ?? "", "amount": f["amount"] ?? "", "month": f["month"] ?? "", "pdf": f["file"] ?? NSNull()]) { r in
        if (r["ok"] as? Bool) == true { done(nil); h?.toast(["t": "Added — it waits for HR approval"]) } else { done(r["error"] as? String ?? "That didn’t work — try again") } }
    }
    main.topMost().present(vc.inNav(), animated: true)
  }
  // ---------- an Office Admin's Expenses ----------
  private func expensesBlocks(_ h: HomeView, _ out: inout [UIView]) {
    guard let m = model["expenses"] as? [String: Any] else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n); return }
    let subs = (m["subs"] as? [[String: Any]]) ?? [], office = (m["office"] as? [[String: Any]]) ?? []
    let admin = (m["admin"] as? Bool) == true
    let seg = part(h, "seg") { SegBlock() }
    seg.set("Subscriptions · \(subs.count)", "Office expenses · \(office.count)", exSeg)
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h else { return }; self.exSeg = i; if let s = self.stack.first(where: { $0.h === h }) { self.draw(s) }; UIView.performWithoutAnimation { h.setNeedsLayout(); h.layoutIfNeeded() } }
    out.append(seg)
    out.append(foot(h, "exsub", exSeg == 0 ? "\(subs.count) subscription\(subs.count == 1 ? "" : "s") · \(m["subsTotal"] as? String ?? "") a month" : "\(m["month"] as? String ?? "") · \(m["officeTotal"] as? String ?? "")"))
    let rows = exSeg == 0 ? subs : office
    if rows.isEmpty { out.append(foot(h, "ex0", exSeg == 0 ? "No monthly subscriptions." : "No office expenses this month yet.", centered: true)) }
    else {
      let items = rows.map { x -> SetItem in
        let id = x["id"] as? String ?? ""
        var it = SetItem(key: "e." + id, title: x["name"] as? String ?? "", sub: x["sub"] as? String ?? "", value: x["amt"] as? String ?? "", sym: exSeg == 0 ? "arrow.triangle.2.circlepath" : "doc.text.fill", col: exSeg == 0 ? .systemIndigo : .systemGray, chevron: (x["inv"] as? Bool) == true,
                         tap: (x["inv"] as? Bool) == true ? { [weak self] in self?.send(["ev": "exInv", "id": id]) } : nil)
        // (hold a subscription → Delete subscription, ending today — Haris 2026-11-04)
        if exSeg == 0, admin { it.hold = { [weak self, weak h] in self?.endSub(h, id, x["name"] as? String ?? "this subscription") } }
        return it
      }
      out.append(group(h, exSeg == 0 ? "exs" : "exo", items))
    }
    h.setFab(exSeg == 0 ? "Add subscription" : "Add office expense", "plus", admin ? { [weak self, weak h] in if let h = h { self?.addExpense(h, sub: self?.exSeg == 0) } } : nil)
  }
  private func endSub(_ h: HomeView?, _ id: String, _ name: String) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let today = Date().formatted(.dateTime.month(.abbreviated).day())
    let a = UIAlertController(title: "Delete \(name)?", message: "It ends today, \(today). It won’t be counted from next month — this month only if its billing day has passed. Months already recorded stay.", preferredStyle: .actionSheet)
    a.overrideUserInterfaceStyle = light ? .light : .dark
    a.addAction(UIAlertAction(title: "Delete subscription", style: .destructive) { [weak self, weak h] _ in
      self?.request(["ev": "exEnd", "id": id]) { r in if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.toast(["t": "Subscription deleted"]) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } }
    })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    main.topMost().present(a, animated: true)
  }
  private func addExpense(_ h: HomeView, sub: Bool?) {
    let isSub = sub == true
    let vc = MoneyFormVC(kind: isSub ? .sub : .expense, people: [], months: [], dark: !light, cookies: main.serverHome.cookies)
    vc.onSave = { [weak self, weak h] f, done in
      var ev: [String: Any] = ["ev": "exAdd", "kind": isSub ? "sub" : "expense", "name": f["name"] ?? "", "amount": f["amount"] ?? "", "invoice": f["file"] ?? NSNull()]
      if isSub { ev["day"] = f["day"] ?? 1 } else { ev["date"] = f["date"] ?? "" }
      self?.request(ev) { r in if (r["ok"] as? Bool) == true { done(nil); h?.toast(["t": isSub ? "Subscription added" : "Office expense added"]) } else { done(r["error"] as? String ?? "That didn’t work — try again") } }
    }
    main.topMost().present(vc.inNav(), animated: true)
  }
  // 🔍 on Claims (by name) and Expenses (by name): the list's own rows, found here
  private func listFind(_ h: HomeView, _ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { h.showFound([], hint: h.assets == "claimsTab" ? "Search claims by name." : "Search subscriptions and office expenses."); return }
    let words = q.split(separator: " ").map(String.init)
    let match = { (s: String) in let n = s.lowercased(); return words.allSatisfy { n.contains($0) } }
    if h.assets == "claimsTab" {
      let m = model["claims"] as? [String: Any] ?? [:]
      let rows = ((m["all"] as? [[String: Any]]) ?? []).filter { match($0["name"] as? String ?? "") }
      if rows.isEmpty { h.showFound([], hint: "No claims found."); return }
      let list = SwipeRows(); list.set(rows, look: h.look, admin: false)
      list.onOpen = { [weak self] id in self?.send(["ev": "clOpen", "id": id]) }
      h.showFound([list], hint: nil)
    } else {
      let m = model["expenses"] as? [String: Any] ?? [:]
      let rows = (((m["subs"] as? [[String: Any]]) ?? []) + ((m["office"] as? [[String: Any]]) ?? [])).filter { match($0["name"] as? String ?? "") }
      if rows.isEmpty { h.showFound([], hint: "Nothing found."); return }
      let g = SetGroup(); g.set(rows.map { x in let id = x["id"] as? String ?? ""; return SetItem(key: "f." + id, title: x["name"] as? String ?? "", sub: x["sub"] as? String ?? "", value: x["amt"] as? String ?? "", chevron: (x["inv"] as? Bool) == true, tap: (x["inv"] as? Bool) == true ? { [weak self] in self?.send(["ev": "exInv", "id": id]) } : nil) }, look: h.look)
      h.showFound([g], hint: nil)
    }
  }
  // 🔍 on Reviews: the waiting and reviewed requests — by task, client or who sent it
  private func reviewFind(_ h: HomeView, _ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { h.showFound([], hint: "Search requests by task, client or person."); return }
    let words = q.split(separator: " ").map(String.init)
    let m = model["reviews"] as? [String: Any] ?? [:]
    let fits = { (x: [String: Any]) -> Bool in let n = "\(x["task"] ?? "") \(x["client"] ?? "") \(x["who"] ?? "")".lowercased(); return words.allSatisfy { n.contains($0) } }
    let w = ((m["waiting"] as? [[String: Any]]) ?? []).filter(fits), d = ((m["reviewed"] as? [[String: Any]]) ?? []).filter(fits)
    if w.isEmpty && d.isEmpty { h.showFound([], hint: "No requests found."); return }
    var out: [UIView] = []
    if !w.isEmpty { let hd = SetHead(); hd.set("Waiting"); let l = ReviewList(); l.set(w, look: h.look, decided: false); l.onOpen = { [weak self] id in self?.open("review", id) }; out += [hd, l] }
    if !d.isEmpty { let hd = SetHead(); hd.set("Reviewed"); let l = ReviewList(); l.set(d, look: h.look, decided: true); l.onOpen = { [weak self] id in self?.open("review", id) }; out += [hd, l] }
    h.showFound(out, hint: nil)
  }
  // 🔍 on Overview: every client's files (Client Assets' search), a tap previews it — Haris 2026-11-04
  private func overviewFind(_ h: HomeView, _ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { h.showFound([], hint: "Search the files of every client — logos, guidelines, fonts…"); return }
    request(["ev": "ovFind", "q": q]) { [weak self, weak h] r in
      guard let self = self, let h = h, h.searching else { return }
      let found = (r["found"] as? [[String: Any]]) ?? []
      let items = found.map { f -> SetItem in
        var it = SetItem(key: "s." + (f["id"] as? String ?? ""), title: f["name"] as? String ?? "", sub: f["where"] as? String ?? "", chevron: false, tap: { [weak self] in self?.send(["ev": "ovFile", "id": f["id"] as? String ?? "", "path": f["path"] as? String ?? "", "name": f["name"] as? String ?? ""]) })
        it.person = (photo: f["pic"] as? String, ini: f["ext"] as? String ?? "", rgb: .systemGray)
        return it
      }
      if items.isEmpty { h.showFound([], hint: "No files found."); return }
      let g = SetGroup(); g.set(items, look: h.look)
      h.showFound([g], hint: (r["loose"] as? Bool) == true ? "Nothing matched exactly — close matches:" : nil)
    }
  }
  private func teamBlocks(_ h: HomeView, _ out: inout [UIView]) {
    let t = team
    let admin = (t["admin"] as? Bool) == true
    if h.assets != "teamTab" { h.drawAssetsBar(name: "Team members", sub: t.isEmpty ? "" : "\(t["active"] as? Int ?? 0) active · \(t["pastN"] as? Int ?? 0) past", logo: nil, rgb: nil, ini: nil, showLogo: false) }
    if t.isEmpty { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n); return }
    let seg = part(h, "seg") { SegBlock() }
    seg.set("Active · \(t["active"] as? Int ?? 0)", "Past · \(t["pastN"] as? Int ?? 0)", teamTab)
    // (Active ↔ Past: the other list there at once, as iPhone's own segmented lists — nothing slides into place;
    //  the note under it slid down, Haris 2026-11-03)
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h else { return }; self.teamTab = i; UIView.performWithoutAnimation { self.blocks(h); h.setNeedsLayout(); h.layoutIfNeeded() } }
    let find = part(h, "find") { AssetsFind() }
    find.field.placeholder = "Search people"
    find.onChange = { [weak self, weak h] q in guard let self = self, let h = h else { return }; self.teamQ = q; self.blocks(h); h.setNeedsLayout() }
    // (Active / Past and the search stuck under the bar once they reach it — the standard)
    let stack = part(h, "pin") { PinStack() }
    stack.set([seg, find])
    if h.pinHead !== stack { h.pinHead = stack }
    let norm = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let q = norm(teamQ.trimmingCharacters(in: .whitespaces))
    let fits = { (p: [String: Any]) -> Bool in q.isEmpty || norm("\(p["name"] ?? "") \(p["email"] ?? "") \(p["role"] ?? "")").contains(q) }
    var any = false
    var shownKeys = Set<String>()
    if teamTab == 0 {
      for g in (t["groups"] as? [[String: Any]]) ?? [] {
        let list = ((g["people"] as? [[String: Any]]) ?? []).filter(fits)
        guard !list.isEmpty else { continue }
        any = true
        let k = g["k"] as? String ?? ""
        shownKeys.insert(k)
        out.append(head(h, "t." + k, "\(g["name"] as? String ?? "") · \(list.count)"))
        out.append(group(h, "t." + k, people(list, hold: admin)))
      }
    } else {
      let list = ((t["past"] as? [[String: Any]]) ?? []).filter(fits)
      if !list.isEmpty { any = true; out.append(head(h, "t.past", "Past members · \(list.count)")); out.append(group(h, "t.past", people(list, hold: admin))) }
    }
    if !any {
      let n = part(h, "none") { AssetsNote() }
      n.label.text = !q.isEmpty ? "No one matches “\(teamQ.trimmingCharacters(in: .whitespaces))”" : teamTab == 1 ? "No past members — people you remove from the team show here, and you can restore their access." : "No one yet."
      out.append(n)
    }
    out.append(foot(h, "note", t["note"] as? String ?? ""))
    let guide = part(h, "guide") { RoleGuide() }
    guide.set((t["guide"] as? [[Any]]) ?? [], look: h.look)
    out.append(guide)
    if admin { h.setFab("Add member", "plus", { [weak self] in self?.addMember() }) }
  }
  // My profile (the locked mockup, Haris 2026-11-03): the photo, ABOUT YOU, ROLE, NOTIFICATIONS, NOTIFY ME ABOUT, the
  // CD's own, Owner view (the owner, live site). Everything is saved as it changes — no Save button.
  private func profileBlocks(_ h: HomeView, _ out: inout [UIView]) {
    h.drawAssetsBar(name: "My profile", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    guard let p = model["profile"] as? [String: Any] else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n); return }
    let top = part(h, "photo") { ProfileHead() }
    top.set(p, look: h.look)
    top.onChange = { [weak self] in
      guard let self = self else { return }
      self.main.topMost().present(AttachSheetVC(light: self.light, title: "Your photo") { [weak self] src in self?.pfPhoto(src) }, animated: true)
    }
    top.onRemove = { [weak self] in self?.pfPhotoOff() }
    out.append(top)
    let v: (String) -> String = { k in p[k] as? String ?? "" }
    let none = "Not set"
    var mail = SetItem(key: "email", title: "Email", value: v("email"), chevron: false)
    mail.tap = { [weak h] in UIPasteboard.general.string = v("email"); h?.toast(["t": "Email copied"]) }
    out.append(head(h, "you", "About you"))
    out.append(group(h, "you", [
      SetItem(key: "name", title: "Name", value: v("name").isEmpty ? none : v("name"), tap: { [weak self] in self?.pfName() }),
      mail,
      SetItem(key: "country", title: "Country", value: v("country").isEmpty ? none : v("country"), tap: { [weak self] in self?.pfPlace("country") }),
      SetItem(key: "city", title: "City", value: v("city").isEmpty ? none : v("city"), tap: { [weak self] in self?.pfPlace("city") }),
      SetItem(key: "bday", title: "Birthday", value: v("bday").isEmpty ? "Optional" : v("bday"), tap: { [weak self] in self?.pfBday() }),
    ]))
    out.append(foot(h, "you", "Your email can’t be changed here. People see your role and city when they look at your name. Your birthday stays private: on the day, the team is told it’s your birthday."))
    let pills: [(String, UIColor)] = ((p["pills"] as? [[String: Any]]) ?? []).map { ($0["t"] as? String ?? "", NativeSheetVC.color($0["c"]) ?? .systemGray) }
    out.append(head(h, "role", "Role"))
    out.append(group(h, "role", [SetItem(key: "role", title: "Your role", chevron: false, pills: pills)]))
    out.append(foot(h, "role", "Only Admins change roles and rights, in Team members."))
    out.append(head(h, "nt", "Notifications"))
    out.append(group(h, "nt", [
      SetItem(key: "sound", title: "Sound", sub: "Play a sound with new notifications", sym: "speaker.wave.2.fill", col: .systemPink, toggle: (p["sound"] as? Bool) != false, flip: { [weak self] on in self?.pfSet("sound", ["value": on], page: ["ev": "pfSound"]) }),
      SetItem(key: "test", title: "Send a test notification", sub: "See and hear what one looks like", sym: "bell.badge.fill", col: .systemRed, tap: { [weak self] in self?.send(["ev": "pfTest"]) }),
    ]))
    let kinds: ([[String: Any]], String) -> [SetItem] = { list, tag in list.map { x -> SetItem in
      let k = x["k"] as? String ?? ""
      return SetItem(key: tag + k, title: x["t"] as? String ?? "", sub: x["s"] as? String ?? "", toggle: (x["on"] as? Bool) == true, flip: { [weak self] on in self?.pfSet("notif", ["k": k, "on": on], page: ["ev": "pfNotif", "k": k]) })
    } }
    out.append(head(h, "about", "Notify me about"))
    out.append(group(h, "about", kinds((p["notify"] as? [[String: Any]]) ?? [], "n.")))
    out.append(foot(h, "about", "You’re notified about tasks you’re assigned to or created. Remove yourself from a task to stop getting its updates."))
    if let cd = p["cd"] as? [String: Any] {
      out.append(head(h, "cd", "As " + (cd["title"] as? String ?? "Creative Director")))
      out.append(group(h, "cd", kinds((cd["types"] as? [[String: Any]]) ?? [], "c.")))
    }
    if let ov = p["owner"] as? [String: Any] {
      let on = (ov["on"] as? Bool) == true, look = (ov["look"] as? Bool) == true
      var rows: [SetItem] = []
      if !on { rows.append(SetItem(key: "ovIn", title: "Step in as Admin", sub: "Look only to start", sym: "shield.lefthalf.filled", col: .systemIndigo, tap: { [weak self] in self?.send(["ev": "pfOwner", "mode": "look"]) })) }
      else {
        rows.append(SetItem(key: "ovNow", title: "Owner view is on", value: look ? "Look only" : "Changes allowed", sym: "shield.lefthalf.filled", col: .systemIndigo, chevron: false))
        rows.append(look ? SetItem(key: "ovEdit", title: "Allow changes", sym: "pencil", col: .systemOrange, tap: { [weak self] in self?.send(["ev": "pfOwner", "mode": "edit"]) })
                         : SetItem(key: "ovLook", title: "Look only", sym: "eye.fill", col: .systemTeal, tap: { [weak self] in self?.send(["ev": "pfOwner", "mode": "look"]) }))
        rows.append(SetItem(key: "ovOff", title: "Back to Production", chevron: false, danger: true, tap: { [weak self] in self?.send(["ev": "pfOwner", "mode": "off"]) }))
      }
      out.append(head(h, "ov", "Owner view"))
      out.append(group(h, "ov", rows))
      out.append(foot(h, "ov", on ? "On this device only. It ends after 15 minutes without use, or when the app reloads." : "Admin rights and Finance Admin on this device only. Nobody is told and your role stays the same for everyone. It starts look only — nothing can be changed until you choose Allow changes."))
    }
  }
  // Trash (the mockup, Haris 2026-11-03): search, Mail's categories, Today / This week / Earlier; swipe right Restore,
  // left Delete forever (Super Admins); a tap opens it (a task view only, a file its preview); touch and hold: its sheet
  private static let trashCats: [(String, String, String)] = [("all", "tray.full.fill", "All"), ("task", "checkmark.circle.fill", "Tasks"), ("project", "folder.fill", "Clients"), ("file", "doc.fill", "Files"), ("comment", "quote.bubble.fill", "Comments"), ("mine", "person.fill", "Deleted by me")]
  private func trashBlocks(_ h: HomeView, _ out: inout [UIView]) {
    let t = (model["trash"] as? [String: Any]) ?? [:]
    let n = t["n"] as? Int ?? 0
    h.drawAssetsBar(name: "Trash", sub: t.isEmpty ? "" : n == 0 ? "Empty" : "\(n) item\(n == 1 ? "" : "s") · restore within 30 days", logo: nil, rgb: nil, ini: nil, showLogo: false)
    h.assetsMenu = (t["empty"] as? Bool) == true ? { [weak self] in [CornerMenuItem(title: "Empty Trash", symbol: "trash", destructive: true, run: { self?.trEmpty() })] } : { [] }
    if t.isEmpty { let w = part(h, "wait") { AssetsNote() }; w.label.text = "Loading…"; out.append(w); return }
    let find = part(h, "find") { AssetsFind() }
    find.field.placeholder = "Search the Trash"
    if !find.field.isFirstResponder, (find.field.text ?? "") != (t["q"] as? String ?? "") { find.field.text = t["q"] as? String }
    find.onChange = { [weak self] q in self?.trQv = q; self?.send(["ev": "trQ", "q": q]) }
    let cats = part(h, "cats") { CatsBlock(items: MeCtl.trashCats.map { c in MailCats.Item(key: c.0, sym: c.1, name: c.2, fill: c.0 == "all" ? MailCats.neutral : c.0 == "mine" ? MailCats.purple : MailCats.blue) }) }
    cats.cats.light = h.look.light
    cats.choose((MeCtl.trashCats.firstIndex { $0.0 == (t["cat"] as? String ?? "all") }) ?? 0)
    cats.onPick = { [weak self] i in self?.trCatv = MeCtl.trashCats[i].0; self?.send(["ev": "trCat", "k": MeCtl.trashCats[i].0]) }
    let stack = part(h, "pin") { PinStack() }
    stack.set([find, cats])
    if h.pinHead !== stack { h.pinHead = stack }
    let groups = (t["groups"] as? [[String: Any]]) ?? []
    for g in groups {
      let items = (g["items"] as? [[String: Any]]) ?? []
      let k = g["name"] as? String ?? ""
      out.append(head(h, "tr." + k, "\(k) · \(items.count)"))
      let tg = part(h, "trg." + k) { TrashGroup() }
      tg.onEvent = { [weak self, weak h] ev in
        // (Restore: straight to the server — step 3 — with the page's own toast; the rest as before)
        if (ev["ev"] as? String) == "trRestore" { self?.request(ev) { r in h?.toast(["t": (r["ok"] as? Bool) == true ? (r["toast"] as? String ?? "Restored") : (r["error"] as? String ?? "That didn’t work — try again")]) }; return }
        if (ev["ev"] as? String) == "trForever", let id = ev["id"] as? String { self?.trForever(id); return }
        self?.send(ev)
      }
      tg.set(items, look: h.look)
      out.append(tg)
    }
    if let none = t["none"] as? String, !none.isEmpty { let w = part(h, "none") { AssetsNote() }; w.label.text = none; out.append(w) }
    out.append(foot(h, "trnote", t["note"] as? String ?? ""))
  }
  private func person(_ id: String) -> [String: Any]? {
    let t = team
    let all = (((t["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["people"] as? [[String: Any]]) ?? [] }) + ((t["past"] as? [[String: Any]]) ?? [])
    return all.first { ($0["id"] as? String) == id }
  }
  // ---------- Content plans (shell 35 — Haris 2026-11-04, the mockups): view only; the Social Manager and Carine approve or
  // ask for changes. Everything from the page's own rules (Plans.native in plans.js), live as the page's data changes ----------
  private static func stCol(_ k: String) -> UIColor {
    switch k { case "wait": return .systemOrange; case "chg": return .systemRed; case "ok": return .systemGreen; case "sent": return .systemBlue; case "prod": return .systemPurple; default: return .systemGray }
  }
  private static func progCol(_ k: String) -> UIColor {
    switch k { case "done": return .systemBlue; case "ready": return .systemGreen; case "cd": return .systemOrange; case "changes": return .systemRed; case "prod": return .systemPurple; default: return .systemGray }
  }
  private func plansBlocks(_ h: HomeView, _ out: inout [UIView]) {
    let m = (model["plans"] as? [String: Any]) ?? [:]
    if h.assets != "plansTab" && h.assets != "plansPage" { h.drawAssetsBar(name: "Content plans", sub: m["label"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false) }
    guard let rows = m["rows"] as? [[String: Any]] else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n); return }
    let month = m["month"] as? String ?? ""
    let mb = part(h, "month") { PlanMonthChips() }
    mb.light = h.look.light
    mb.set(month: month, first: m["first"] as? String ?? month, last: m["last"] as? String ?? month)
    mb.onPick = { [weak self] to in guard let self = self else { return }; UISelectionFeedbackGenerator().selectionChanged(); self.plMonth = to; self.send(["ev": "pl", "on": true, "month": to]) }
    out.append(mb)
    if let n = m["note"] as? String, !n.isEmpty { let f = foot(h, "plnote", n); f.label.textColor = .systemOrange; out.append(f) }
    let items = rows.map { r -> SetItem in
      let pid = r["pid"] as? String ?? "", st = r["st"] as? [String: Any] ?? [:]
      var it = SetItem(key: "p." + pid, title: r["name"] as? String ?? "", sub: r["sub"] as? String ?? "", tap: { [weak self] in self?.open("plan", "\(pid)|\(month)") })
      it.person = (photo: nil, ini: r["ini"] as? String ?? "", rgb: NativeSheetVC.color(r["rgb"]) ?? .systemGray)
      it.pills = [(st["t"] as? String ?? "", MeCtl.stCol(st["k"] as? String ?? ""))]
      return it
    }
    if items.isEmpty { let n = part(h, "none") { AssetsNote() }; n.label.text = "No clients to show."; out.append(n) }
    else { out.append(head(h, "pl", "")); out.append(group(h, "pl", items)) }
    out.append(foot(h, "plfoot", m["foot"] as? String ?? "", centered: true))
  }
  private func planBlocks(_ h: HomeView, _ id: String, _ out: inout [UIView]) {
    let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let pid = parts.first ?? "", month = parts.count > 1 ? parts[1] : ""
    guard let m = model["plan"] as? [String: Any], (m["pid"] as? String) == pid, month.isEmpty || (m["month"] as? String) == month else {
      h.drawAssetsBar(name: "Content plan", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      let n = part(h, "wait") { AssetsNote() }; n.label.text = model["plan"] is NSNull ? "This plan is no longer here." : "Loading…"; out.append(n); return
    }
    h.drawAssetsBar(name: m["name"] as? String ?? "", sub: m["sub"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    let st = m["st"] as? [String: Any] ?? [:]
    let top = part(h, "top") { PlanHead() }
    let b = m["banner"] as? [String: Any] ?? [:]
    top.set(st["t"] as? String ?? "", col: MeCtl.stCol(st["k"] as? String ?? ""), line: [b["t"] as? String, b["s"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "), note: b["note"] as? String ?? "")
    out.append(top)
    if let e = m["empty"] as? String { out.append(foot(h, "empty", e, centered: true)); return }
    let occs = (m["occs"] as? [[String: Any]]) ?? []
    if !occs.isEmpty {
      out.append(head(h, "occ", "Occasions this month"))
      out.append(group(h, "occ", occs.enumerated().map { i, o in
        let k = o["k"] as? String ?? ""
        return SetItem(key: "o.\(i)", title: o["t"] as? String ?? "", value: k == "ok" ? "Planned" : k == "skip" ? "Skipped" : "Not planned", sym: k == "ok" ? "checkmark" : k == "skip" ? "minus" : "exclamationmark", col: k == "ok" ? .systemGreen : k == "skip" ? .systemGray : .systemOrange, chevron: false)
      }))
    }
    let planId = m["id"] as? String ?? ""
    for d in (m["days"] as? [[String: Any]]) ?? [] {
      let dk = d["d"] as? String ?? ""
      let occ = d["occ"] as? String ?? ""
      out.append(head(h, "d." + dk, (d["label"] as? String ?? "") + (occ.isEmpty ? "" : " · " + occ)))
      out.append(group(h, "d." + dk, ((d["posts"] as? [[String: Any]]) ?? []).map { x in
        let xid = x["id"] as? String ?? ""
        var sub = [x["fmt"] as? String ?? "", x["ch"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        var it = SetItem(key: "x." + xid, title: x["title"] as? String ?? "", sub: "", sym: "photo.on.rectangle", col: NativeSheetVC.color(x["fcol"]) ?? .systemGray, tap: { [weak self] in self?.openPost(planId, xid) })
        if let c = x["check"] as? [String: Any] {
          sub += "\n" + (c["t"] as? String ?? "")
          it.pills = [((c["k"] as? String) == "ok" ? "✓" : "!", (c["k"] as? String) == "ok" ? .systemGreen : .systemOrange)]
        } else if let p = x["prog"] as? [String: Any] { it.pills = [(p["t"] as? String ?? "", MeCtl.progCol(p["k"] as? String ?? ""))] }
        it.sub = sub
        return it
      }))
    }
    if let ap = m["approve"] as? [String: Any] {
      let flagged = ap["flagged"] as? Int ?? 0
      let acts = part(h, "acts") { PlanActs() }
      acts.set(left: "Send back", right: "Approve skeleton")
      acts.fadeRight(flagged > 0)   // (changes asked on some posts: faded — a tap says why; Haris 2026-11-04)
      acts.onLeft = { [weak self] in self?.askNote(title: "Send back for changes", hint: flagged > 0 ? "A note for the whole skeleton (optional) — the posts you marked go with it." : "What should change?", optional: flagged > 0) { note, done in
        self?.request(["ev": "plBack", "plan": planId, "note": note]) { r in done((r["ok"] as? Bool) == true ? nil : r["error"] as? String ?? "That didn’t work — try again") } } }
      acts.onRight = { [weak self, weak h] in
        guard let self = self else { return }
        if flagged > 0 { UINotificationFeedbackGenerator().notificationOccurred(.warning); h?.toast(["t": "\(flagged) post\(flagged == 1 ? " is" : "s are") marked Ask for changes — send it back instead"]); return }
        let a = UIAlertController(title: "Approve this content skeleton?", message: "After this, tasks can be made from it on the computer.", preferredStyle: .alert)
        a.overrideUserInterfaceStyle = self.light ? .light : .dark
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Approve skeleton", style: .default) { [weak self] _ in
          self?.request(["ev": "plApprove", "plan": planId]) { [weak h] r in if (r["ok"] as? Bool) != true { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } else { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
        })
        self.main.topMost().present(a, animated: true)
      }
      out.append(acts)
    }
    if let f = m["foot"] as? String, !f.isEmpty { out.append(foot(h, "pfoot", f, centered: true)) }
  }
  // 🔍 on Content plans (Haris 2026-11-04): the months the app reaches — the one on screen first — clients and posts
  private func planFind(_ h: HomeView, _ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { h.showFound([], hint: "Search the plans — a client, or a post’s title, in every month you can open."); return }
    request(["ev": "plFind", "q": q, "month": plMonth ?? ""]) { [weak self, weak h] r in
      guard let self = self, let h = h, h.searching else { return }
      let groups = (r["found"] as? [[String: Any]]) ?? []
      var views: [UIView] = []
      for g in groups {
        let month = g["month"] as? String ?? ""
        let head = SetHead(); head.set(g["label"] as? String ?? ""); views.append(head)
        let items = ((g["items"] as? [[String: Any]]) ?? []).enumerated().map { i, x -> SetItem in
          let pid = x["pid"] as? String ?? "", post = x["post"] as? String, plan = x["plan"] as? String
          var it = SetItem(key: "\(month).\(i)", title: x["title"] as? String ?? "", sub: x["sub"] as? String ?? "", sym: post == nil ? nil : "photo.on.rectangle", col: post == nil ? nil : .systemOrange, tap: { [weak self, weak h] in
            guard let self = self else { return }
            h?.closeSearch()
            self.plMonth = month; self.send(["ev": "pl", "on": true, "month": month])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
              self?.open("plan", "\(pid)|\(month)")
              if let post = post, let plan = plan { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.openPost(plan, post) } }
            }
          })
          if post == nil { it.person = (photo: nil, ini: x["ini"] as? String ?? "", rgb: NativeSheetVC.color(x["rgb"]) ?? .systemGray) }
          return it
        }
        let grp = SetGroup(); grp.set(items, look: h.look); views.append(grp)
      }
      h.showFound(views, hint: views.isEmpty ? "Nothing found." : nil)
    }
  }
  private func openPost(_ plan: String, _ post: String) {
    request(["ev": "plPost", "plan": plan, "post": post]) { [weak self] r in
      guard let self = self else { return }
      guard let p = r["post"] as? [String: Any] else { (self.top)?.toast(["t": r["error"] as? String ?? "This post is no longer here"]); return }
      let vc = PlanPostVC(p, dark: !self.light)
      vc.onReview = { [weak self, weak vc] state in
        guard let self = self else { return }
        if state == "changes" {
          self.askNote(title: "Ask for changes", hint: "\(p["title"] as? String ?? "") — what should change?", optional: false, from: vc) { note, done in
            self.request(["ev": "plReview", "plan": plan, "post": post, "state": "changes", "note": note]) { r in
              if (r["ok"] as? Bool) == true { done(nil); vc?.dismiss(animated: true) } else { done(r["error"] as? String ?? "That didn’t work — try again") }
            }
          }
        } else {
          self.request(["ev": "plReview", "plan": plan, "post": post, "state": "ok"]) { r in
            if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); vc?.dismiss(animated: true) } else { vc?.alert(r["error"] as? String ?? "That didn’t work — try again") }
          }
        }
      }
      vc.onOpenFile = { [weak self] f in self?.send(["ev": "plFile", "path": f["path"] as? String ?? "", "name": f["name"] as? String ?? ""]) }
      let nav = UINavigationController(rootViewController: vc)
      nav.overrideUserInterfaceStyle = self.light ? .light : .dark
      if let sp = nav.sheetPresentationController { sp.detents = [.large()]; sp.prefersGrabberVisible = true }
      self.main.topMost().present(nav, animated: true)
    }
  }
  // a note, iPhone's own sheet: ✕ · the title · Send
  private func askNote(title: String, hint: String, optional: Bool, from: UIViewController? = nil, _ send: @escaping (String, @escaping (String?) -> Void) -> Void) {
    let vc = NoteVC(title: title, hint: hint, optional: optional, send: send)
    let nav = UINavigationController(rootViewController: vc)
    nav.overrideUserInterfaceStyle = light ? .light : .dark
    if let sp = nav.sheetPresentationController { sp.detents = [.custom { _ in 260 }, .large()]; sp.prefersGrabberVisible = true }
    (from ?? main.topMost()).present(nav, animated: true)
  }
  private func memberBlocks(_ h: HomeView, _ id: String, _ out: inout [UIView]) {
    let admin = (team["admin"] as? Bool) == true
    guard let p = person(id) else {
      h.drawAssetsBar(name: "Team member", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      let n = part(h, "gone") { AssetsNote() }; n.label.text = team.isEmpty ? "Loading…" : "No longer on the team list."; out.append(n); return
    }
    h.drawAssetsBar(name: p["name"] as? String ?? "", sub: p["role"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    let top = part(h, "head") { MemberHead() }
    top.set(p, look: h.look)
    out.append(top)
    var info: [SetItem] = [SetItem(key: "mail", title: "Email", value: "", chevron: false)]
    info[0].sub = p["email"] as? String ?? ""
    if let pl = p["place"] as? String, !pl.isEmpty { info.append(SetItem(key: "place", title: "Where", sub: pl, chevron: false)) }
    info.append(SetItem(key: "status", title: "Status", value: (p["past"] as? Bool) == true ? "Removed" : (p["pending"] as? Bool) == true ? "Hasn’t signed in yet" : "Active", chevron: false))
    if let n = p["open"] as? Int { info.append(SetItem(key: "open", title: "Open tasks", value: "\(n)", chevron: false)) }
    let email = p["email"] as? String ?? ""
    info[0].tap = { [weak self, weak h] in UIPasteboard.general.string = email; h?.toast(["t": "Email copied"]); _ = self }
    out.append(head(h, "info", "")); out.append(group(h, "info", info))
    if admin {
      var manage: [SetItem] = []
      if (p["locked"] as? Bool) == true { manage.append(SetItem(key: "locked", title: "Only the owner can change this account", sym: "lock.fill", col: .systemGray, chevron: false)) }
      else {
        manage.append(SetItem(key: "manage", title: "Role, rights and access", sub: "Change role, Super Admin rights, Finance access…", sym: "slider.horizontal.3", col: .systemBlue, tap: { [weak self] in self?.memberMenu(id) }))
        if let cd = p["cd"] as? [String: Any] {
          manage.append(SetItem(key: "cd", title: "Creative Director", sub: cd["label"] as? String ?? "", sym: "star.fill", col: .systemPurple, toggle: (cd["on"] as? Bool) == true, flip: { [weak self, weak h] _ in self?.cdFlow(id); if let h = h { self?.settle(h) } }))
        }
      }
      out.append(head(h, "manage", "Admin")); out.append(group(h, "manage", manage))
    }
  }

  // ---------- taps ----------
  private func event(_ h: HomeView, _ ev: [String: Any]) {
    switch ev["ev"] as? String ?? "" {
    case "back": if h === stack.last?.h { pop() }
    case "toast": send(["ev": "toast"])
    // (your photo on the Content plans tab: the Me tab, as from every other tab — Haris 2026-11-04)
    case "me" where MeCtl.tabRoots.contains(h.assets ?? ""): main.selectTab("me")
    case "find" where h.assets == "overviewTab": overviewFind(h, ev["q"] as? String ?? "")
    case "find" where h.assets == "claimsTab" || h.assets == "expensesTab": listFind(h, ev["q"] as? String ?? "")
    case "find" where h.assets == "reviewsTab": reviewFind(h, ev["q"] as? String ?? "")
    case "find" where h.assets == "plansPage" || h.assets == "me.plan" || h.assets == "plansTab": planFind(h, ev["q"] as? String ?? "")
    default: break
    }
  }

  // ---------- the page's questions, as iPhone's own (dialog, choiceDialog, formDialog over the app's Me) ----------
  func ask(_ a: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    let kind = a["kind"] as? String ?? "alert"
    let dark = !light
    if kind == "form" {
      let vc = MeFormVC(a, dark: dark, done: done); let nav = UINavigationController(rootViewController: vc); nav.overrideUserInterfaceStyle = dark ? .dark : .light
      // (as tall as its fields — one name isn't a whole page: Haris 2026-11-03)
      let n = CGFloat(((a["fields"] as? [Any]) ?? []).count)
      let h: CGFloat = 110 + n * 96 + ((a["intro"] as? String ?? "").isEmpty ? 0 : 44) + ((a["error"] as? String ?? "").isEmpty ? 0 : 28)
      if let sp = nav.sheetPresentationController { sp.detents = [.custom { _ in h }, .large()]; sp.prefersGrabberVisible = true }
      main.topMost().present(nav, animated: true); return
    }
    let title = a["title"] as? String, body = a["body"] as? String
    let ac = UIAlertController(title: title, message: (body ?? "").isEmpty ? nil : body, preferredStyle: kind == "choice" ? .actionSheet : .alert)
    ac.overrideUserInterfaceStyle = dark ? .dark : .light
    if kind == "choice" {
      var hadCancel = false   // (iPhone allows one Cancel)
      for (i, c) in ((a["choices"] as? [[String: Any]]) ?? []).enumerated() {
        let cancel = (c["cancel"] as? Bool) == true && !hadCancel
        if cancel { hadCancel = true }
        ac.addAction(UIAlertAction(title: c["label"] as? String ?? "", style: cancel ? .cancel : (c["danger"] as? Bool) == true ? .destructive : .default) { _ in done(["ok": !cancel, "index": i]) })
      }
      if let pop = ac.popoverPresentationController { pop.sourceView = main.view; pop.sourceRect = askAnchor(); pop.permittedArrowDirections = [.down, .up] }
    } else {
      if let inp = a["input"] as? [String: Any] { ac.addTextField { t in t.text = inp["value"] as? String; t.placeholder = inp["placeholder"] as? String; t.clearButtonMode = .whileEditing } }
      if let c = a["cancelText"] as? String, !c.isEmpty { ac.addAction(UIAlertAction(title: c, style: .cancel) { _ in done(["ok": false]) }) }
      let ok = UIAlertAction(title: a["okText"] as? String ?? "OK", style: (a["danger"] as? Bool) == true ? .destructive : .default) { [weak ac] _ in done(["ok": true, "text": ac?.textFields?.first?.text ?? ""]) }
      ac.addAction(ok); ac.preferredAction = ok
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    main.topMost().present(ac, animated: true)
  }

  // ---------- This iPhone: Notifications, the Face ID lock, Sign out — the app's own (Part B step 8; the page's Push
  // rows in phone.js and signOut in app.js, done here) ----------
  private func pushModel(_ st: String) -> [String: Any] {
    let label = ["on": "On", "off": "Off", "denied": "Blocked"][st] ?? ""
    let sub = ["on": "A banner for every Inbox update", "off": "Get a banner even when the app is closed", "denied": "Allow them in iPhone Settings → Notifications → E11 Console"][st] ?? ""
    return ["state": st, "busy": pushBusy, "label": label, "sub": sub]
  }
  // (asked of iPhone again at most every 2 s — coming back from Settings changes it; drawn again only when it changed)
  private func pushCheck() {
    if let t = pushAsked, Date().timeIntervalSince(t) < 2 { return }
    pushAsked = Date()
    main.pushState { [weak self] st in
      guard let self = self, st != self.pushNow else { return }
      self.pushNow = st; self.redraw()
    }
  }
  private func pushTap() {
    guard !pushBusy else { return }
    guard let st = pushNow else { send(["ev": "push"]); return }   // (not asked of iPhone yet: the page's way, as before)
    switch st {
    case "denied":
      ask(["kind": "alert", "title": "Notifications are off in Settings", "body": "Turn on Allow Notifications for E11 Console in the iPhone’s Settings.", "okText": "Open Settings", "cancelText": "Cancel"]) { r in
        if (r["ok"] as? Bool) == true, let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
      }
    case "off": pushOn()
    default:
      // (the app's own sheet, as the page's menu was — not iPhone's pop-up bubble: Haris 2026-11-05)
      sheet(["sheet": ["sections": [["rows": [["i": 0, "label": "Send a test notification", "icon": "bell"], ["i": 1, "label": "Turn off on this phone", "icon": "x", "danger": true]]]]],
             "acts": [["do": "test"], ["do": "off"]]]) { [weak self] act in
        if (act["do"] as? String) == "test" { self?.pushTest() } else { self?.pushOff() }
      }
    }
  }
  private func pushOn() {
    pushBusy = true; redraw()
    let finish = { [weak self] (st: String, say: String?) in
      guard let self = self else { return }
      self.pushBusy = false; self.pushNow = st; self.pushAsked = Date(); self.redraw()
      if let t = say { self.top?.toast(["t": t]) }
    }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] ok, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if !ok { self.main.pushState { st in finish(st == "on" ? "off" : st, nil) }; return }
        UserDefaults.standard.set(false, forKey: PUSH_OFF_KEY)
        // (on once this phone's address is in — main.gotToken sends it to the server)
        self.main.pushWaiters.append { r in
          if (r["ok"] as? Bool) == true { finish("on", "Notifications on") } else { finish("off", r["error"] as? String ?? "Notifications failed") }
        }
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }
  private func pushOff() {
    UserDefaults.standard.set(true, forKey: PUSH_OFF_KEY)
    if let tk = main.lastToken { main.serverTask.request("/api/apns/unregister", body: ["token": tk]) { _ in } }
    pushNow = "off"; pushAsked = Date(); redraw()
    top?.toast(["t": "Notifications off"])
  }
  private func pushTest() {
    main.serverTask.request("/api/push/test", body: ["token": main.lastToken ?? ""]) { [weak self] r in
      self?.top?.toast(["t": r.map { MeCtl.testSaid($0) } ?? "No connection — try again"])
    }
  }
  // what a test notification did, in words — this phone's own answer from Apple (phone.js testSaid)
  static func testSaid(_ r: [String: Any]) -> String {
    if let e = r["error"] as? String, (r["ok"] as? Bool) == false { return e }
    if let me = r["thisPhone"] as? [String: Any] {
      let status = me["status"] as? Int, reason = me["reason"] as? String
      if status == 200 { return "Sent to this phone — Apple accepted it. Nothing showing? Check Focus and Settings → Notifications → E11 Console" }
      if (r["apnsWhy"] as? String) == "no-key" { return "This site can’t send Apple notifications yet (its Apple push key isn’t set up)" }
      if reason == "not registered on this site" { return "This phone isn’t registered on this site — turn notifications off and on here" }
      return "Apple didn’t accept it for this phone (\(status.map { String($0) } ?? "no answer")\(reason.map { " · " + $0 } ?? ""))"
    }
    let ds = (r["devices"] as? [[String: Any]]) ?? []
    if !ds.isEmpty {
      return "Apple devices on this site: " + ds.map { d in
        let name = (d["platform"] as? String) == "mac" ? "Mac" : "iPhone", st = d["status"] as? Int
        return st == 200 ? "\(name) ✓ accepted" : "\(name) ✗ \(st.map { String($0) } ?? "no answer")\((d["reason"] as? String).map { " " + $0 } ?? "")"
      }.joined(separator: " · ")
    }
    switch r["apnsWhy"] as? String {
    case "no-key": return "This site can’t send Apple notifications (its Apple push key isn’t set up)"
    case "no-devices": return "No iPhone is registered on this site — turn notifications off and on on the phone"
    default: return (r["sent"] as? Bool) == true ? "Sent — it may take a few seconds" : "Couldn’t reach this phone — switch it off and on again"
    }
  }
  // the Face ID lock: on asks for your face first (as the page's setLock); off at once
  private func lockFlip(_ on: Bool) {
    if !on { UserDefaults.standard.set(false, forKey: LOCK_KEY); redraw(); return }
    let ctx = LAContext(); var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { top?.toast(["t": "This iPhone has no Face ID or passcode set up"]); redraw(); return }
    main.authing = true
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Lock E11 Console with Face ID") { [weak self] ok, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if ok { UserDefaults.standard.set(true, forKey: LOCK_KEY) }
        self.redraw()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.main.authing = false }
      }
    }
  }
  private func signOutAsk() {
    let review = UserDefaults.standard.string(forKey: "e11_server") == "review"
    ask(["kind": "alert", "title": "Sign out?", "body": review ? "You’ll need the App Review password to sign in again." : "You’ll need the code from your email to sign in again.", "okText": "Sign out", "danger": true, "cancelText": "Cancel"]) { [weak self] r in
      if (r["ok"] as? Bool) == true { self?.main.signOutNative() }
    }
  }

  // ---------- Shortcuts (all real today — checked in the code; a new gesture → a row here) ----------
  private static let shortcuts: [(String, String, [(String, String, String?, String, UIColor)])] = [
    ("Writing", "In comments and the description", [
      ("Mention someone", "Type @ and a name", "@", "at", .systemBlue),
      ("Add a task file", "Type # and part of its name", "#", "number", .systemIndigo),
      ("Paste a copied file", "Copy in a preview, then Paste", "Copy · Paste", "doc.on.clipboard", .systemTeal),
      ("Attach into the description", "📎 in the format bar — Camera, Photos, Files", nil, "paperclip", .systemGray),
      ("Voice message", "Hold the mic · slide left to cancel · up to lock", "Hold", "mic.fill", .systemRed)]),
    ("Tabs", "", [
      ("Back to a tab’s first page", "Tap its tab again", "Tap", "square.grid.2x2", .systemBlue),
      ("Back to the top", "Tap the tab you’re on, on its first page", "Tap", "arrow.up.to.line", .systemGray)]),
    ("Task cards", "Home, My Tasks and Search", [
      ("Done · Due date", "Swipe a card right", "→", "checkmark.circle.fill", .systemGreen),
      ("Copy link · Delete", "Swipe a card left", "←", "link", .systemOrange),
      ("More for a task", "Touch and hold a card", "Hold", "ellipsis.circle.fill", .systemPurple)]),
    ("Inbox", "", [("Read · Unread", "Swipe an update right", "→", "envelope.open.fill", .systemBlue)]),
    ("Clients", "", [
      ("A client’s details", "Touch and hold a client", "Hold", "person.crop.square.fill", .systemTeal),
      ("Inactive clients", "Tap the heading to open or close them", "Tap", "chevron.right.circle.fill", .systemGray)]),
    ("Client Assets", "", [
      ("Copy · Download · Info", "Touch and hold a file or folder", "Hold", "folder.fill", .systemOrange),
      ("Back", "Swipe from the left edge", "Edge", "chevron.backward", .systemGray)]),
    ("Task page", "", [
      ("Details ↔ Comments", "Swipe sideways on the page", "↔", "arrow.left.arrow.right", .systemIndigo),
      ("Back", "Swipe from the left edge", "Edge", "chevron.backward", .systemGray),
      ("Edit the description", "Tap it — Done saves", nil, "pencil", .systemBlue),
      ("Open · Copy · Download a file", "Touch and hold its card", "Hold", "doc.fill", .systemTeal)]),
    ("Comments", "", [
      ("Cancel a reply", "Tap the “Replying to” pill", nil, "arrowshape.turn.up.left.fill", .systemBlue),
      ("Close the keyboard", "Tap the list, or drag down onto the keyboard", nil, "keyboard.chevron.compact.down", .systemGray)]),
    ("Previews", "", [
      ("Next file", "Swipe sideways, or tap one in the strip", "↔", "photo.on.rectangle", .systemGreen),
      ("Zoom", "Pinch, or double-tap", "Pinch", "plus.magnifyingglass", .systemOrange),
      ("Close", "Pull down", "↓", "xmark.circle.fill", .systemGray)]),
    ("Opening the app", "", [("Skip the startup screen", "Tap anywhere", "Tap", "sparkles", .systemPink)]),
  ]
}

// the page's form (formDialog — Add team member…) as iPhone's own: its fields in a grouped list, a choice as a menu
final class MeFormVC: UITableViewController, UITextFieldDelegate {
  private let a: [String: Any]
  private var fields: [[String: Any]]
  private var values: [String: String] = [:]
  private let done: ([String: Any]) -> Void
  private var answered = false
  init(_ a: [String: Any], dark: Bool, done: @escaping ([String: Any]) -> Void) {
    self.a = a; self.done = done
    fields = (a["fields"] as? [[String: Any]]) ?? []
    super.init(style: .insetGrouped)
    for f in fields { values[f["key"] as? String ?? ""] = (f["value"] as? String) ?? "" }
    overrideUserInterfaceStyle = dark ? .dark : .light
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = a["title"] as? String
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.finish(["ok": false]) })
    let ok = UIBarButtonItem(title: a["okText"] as? String ?? "Save", image: nil, primaryAction: UIAction { [weak self] _ in self?.submit() }, menu: nil)
    ok.style = .done
    navigationItem.rightBarButtonItem = ok
    tableView.keyboardDismissMode = .interactive
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if let i = fields.firstIndex(where: { ($0["options"] as? [Any]) == nil && ($0["readonly"] as? Bool) != true }), let c = tableView.cellForRow(at: IndexPath(row: 0, section: i)), let t = c.contentView.viewWithTag(5) as? UITextField { t.becomeFirstResponder() }
  }
  override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); if !answered { answered = true; done(["ok": false]) } }
  private func finish(_ r: [String: Any]) { view.endEditing(true); answered = true; dismiss(animated: true) { self.done(r) } }
  private func submit() { view.endEditing(true); finish(["ok": true, "values": values]) }
  override func numberOfSections(in tableView: UITableView) -> Int { fields.count }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { fields[section]["label"] as? String }
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    var parts: [String] = []
    if section == 0, let intro = a["intro"] as? String, !intro.isEmpty { parts.append(intro) }
    if let h = fields[section]["hint"] as? String, !h.isEmpty { parts.append(h) }
    if section == fields.count - 1, let e = a["error"] as? String, !e.isEmpty { parts.append("⚠︎ " + e) }
    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
  }
  private func label(_ f: [String: Any]) -> String {
    let v = values[f["key"] as? String ?? ""] ?? ""
    let opts = (f["options"] as? [[Any]]) ?? []
    return (opts.first { "\($0.first ?? "")" == v }?.last as? String) ?? v
  }
  override func tableView(_ tableView: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let f = fields[ip.section], key = f["key"] as? String ?? ""
    let c = UITableViewCell(style: .default, reuseIdentifier: nil)
    if let opts = f["options"] as? [[Any]] {
      var conf = UIButton.Configuration.plain()
      conf.title = label(f); conf.baseForegroundColor = .label; conf.contentInsets = .zero
      conf.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)); conf.imagePlacement = .trailing; conf.imagePadding = 6
      let b = UIButton(configuration: conf); b.contentHorizontalAlignment = .leading
      b.menu = UIMenu(children: opts.map { o -> UIMenuElement in
        let v = "\(o.first ?? "")", l = o.last as? String ?? v
        return UIAction(title: l, state: values[key] == v ? .on : .off) { [weak self] _ in self?.values[key] = v; self?.tableView.reloadSections(IndexSet(integer: ip.section), with: .none) }
      })
      b.showsMenuAsPrimaryAction = true
      b.translatesAutoresizingMaskIntoConstraints = false
      c.contentView.addSubview(b)
      NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.leadingAnchor), b.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor), b.topAnchor.constraint(equalTo: c.contentView.topAnchor), b.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor), b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
    } else {
      let t = UITextField(); t.tag = 5
      t.text = values[key]; t.placeholder = f["placeholder"] as? String; t.clearButtonMode = .whileEditing
      t.isEnabled = (f["readonly"] as? Bool) != true
      let type = f["type"] as? String ?? "text"
      t.keyboardType = type == "email" ? .emailAddress : .default
      t.autocapitalizationType = type == "email" ? .none : .words; t.autocorrectionType = .no
      t.textContentType = type == "email" ? .emailAddress : .name
      t.returnKeyType = .next; t.delegate = self
      t.addAction(UIAction { [weak self, weak t] _ in self?.values[key] = t?.text ?? "" }, for: .editingChanged)
      t.translatesAutoresizingMaskIntoConstraints = false
      c.contentView.addSubview(t)
      NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.leadingAnchor), t.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor), t.topAnchor.constraint(equalTo: c.contentView.topAnchor), t.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor), t.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
    }
    c.selectionStyle = .none
    return c
  }
  func textFieldShouldReturn(_ t: UITextField) -> Bool {
    // (the next box, or the last: done)
    if let cell = t.superview?.superview as? UITableViewCell, let ip = tableView.indexPath(for: cell) {
      for s in (ip.section + 1)..<max(ip.section + 1, fields.count) where (fields[s]["options"] as? [Any]) == nil {
        if let n = tableView.cellForRow(at: IndexPath(row: 0, section: s))?.contentView.viewWithTag(5) as? UITextField { n.becomeFirstResponder(); return true }
      }
    }
    t.resignFirstResponder(); return true
  }
}

// (only notes where a finger comes down — never takes a touch from anything)
final class TouchSpot: UIGestureRecognizer, UIGestureRecognizerDelegate {
  private(set) var at: CGPoint?
  init() { super.init(target: nil, action: nil); cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false; delegate = self }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { if let v = view, let t = touches.first { at = t.location(in: v) }; state = .failed }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}

// ---------- Content plans' pieces ----------
// ‹ December 2026 › (any month, from this one on)
// Content plans' months (Haris 2026-11-04, "C"): pills as the Inbox's (MailCats' colours — not glass), the chosen one
// always in the middle, wide, blue with white, its full name; the others grey with their short name. The running month
// to 6 months after the one being planned can be tapped or swiped to (swipe the row, as the Inbox's); the months either
// side show faded and can't be. A tap or swipe slides the row and grows / shrinks the pills in the Inbox's timing.
// Overview's three cards (Haris 2026-11-04): a big number, a small "/ 18" beside it, a line under
final class OvCards: UIView, HomeBlock {
  private var tiles: [(box: UIView, n: UILabel, t: UILabel)] = []
  func set(_ cards: [[String: Any]], look L: HomeLook) {
    while tiles.count < cards.count {
      let b = UIView(); b.layer.cornerRadius = 16; b.layer.cornerCurve = .continuous
      let n = UILabel(); n.adjustsFontSizeToFitWidth = true; n.minimumScaleFactor = 0.6
      let t = UILabel(); t.font = .systemFont(ofSize: 12); t.textColor = .secondaryLabel; t.numberOfLines = 3
      b.addSubview(n); b.addSubview(t); addSubview(b); tiles.append((b, n, t))
    }
    for (i, c) in cards.enumerated() {
      let x = tiles[i]; x.box.backgroundColor = L.card
      let s = NSMutableAttributedString(string: c["n"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: UIColor.label])
      if let of = c["of"] as? String { s.append(NSAttributedString(string: " " + of, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.secondaryLabel])) }
      x.n.attributedText = s; x.t.text = c["t"] as? String
    }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { 104 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let gap: CGFloat = 9, w = (bounds.width - 32 - gap * 2) / 3
    for (i, x) in tiles.enumerated() {
      x.box.frame = CGRect(x: 16 + CGFloat(i) * (w + gap), y: 6, width: w, height: 92)
      x.n.frame = CGRect(x: 12, y: 10, width: w - 24, height: 30); x.t.frame = CGRect(x: 12, y: 42, width: w - 24, height: 44)
    }
  }
}
final class PlanMonthChips: UIView, HomeBlock {
  static let H: CGFloat = 38
  var onPick: ((String) -> Void)?
  var light = true { didSet { if oldValue != light { paint() } } }
  private var months: [String] = [], first = "", last = "", selected = ""
  private var pills: [String: (bg: UIView, label: UILabel)] = [:]
  private static let short = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  private static let full = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  static func add(_ m: String, _ n: Int) -> String {
    let p = m.split(separator: "-").compactMap { Int($0) }; guard p.count == 2 else { return m }
    let t = p[0] * 12 + (p[1] - 1) + n
    return String(format: "%04d-%02d", t / 12, t % 12 + 1)
  }
  private static func name(_ m: String, on: Bool) -> String {
    let p = m.split(separator: "-").compactMap { Int($0) }; guard p.count == 2, (1...12).contains(p[1]) else { return m }
    return on ? "\(full[p[1] - 1]) \(p[0])" : short[p[1] - 1]
  }
  private func usable(_ m: String) -> Bool { m >= first && m <= last }
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    for d in [UISwipeGestureRecognizer.Direction.left, .right] {
      let sw = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:))); sw.direction = d; addGestureRecognizer(sw)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(month: String, first f: String, last l: String) {
    let changedRange = f != first || l != last
    first = f; last = l
    // (three faded months either side of what can be picked)
    let want = (-3...(monthsBetween(f, l) + 3)).map { PlanMonthChips.add(f, $0) }
    if want != months || changedRange {
      months = want
      for (k, p) in pills where !want.contains(k) { p.bg.removeFromSuperview(); pills[k] = nil }
      UIView.performWithoutAnimation {
        for m in want where pills[m] == nil {
          let bg = UIView(); bg.layer.cornerRadius = PlanMonthChips.H / 2; bg.layer.cornerCurve = .continuous; bg.clipsToBounds = true
          let lb = UILabel(); lb.font = .systemFont(ofSize: 17, weight: .semibold); lb.textAlignment = .center
          bg.addSubview(lb); addSubview(bg)
          bg.isAccessibilityElement = true; bg.accessibilityIdentifier = "plm-" + m
          bg.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
          pills[m] = (bg, lb)
        }
        if month == selected { paint(); place() }
      }
    }
    if month != selected {
      let was = selected; selected = month
      if was.isEmpty || bounds.width == 0 { UIView.performWithoutAnimation { paint(); place() } } else { slide() }
    }
  }
  private func monthsBetween(_ a: String, _ b: String) -> Int {
    let x = a.split(separator: "-").compactMap { Int($0) }, y = b.split(separator: "-").compactMap { Int($0) }
    guard x.count == 2, y.count == 2 else { return 0 }
    return max(0, (y[0] * 12 + y[1]) - (x[0] * 12 + x[1]))
  }
  @objc private func tapped(_ g: UITapGestureRecognizer) {
    guard let v = g.view, let m = pills.first(where: { $0.value.bg === v })?.key else { return }
    pick(m)
  }
  @objc private func swiped(_ g: UISwipeGestureRecognizer) { pick(PlanMonthChips.add(selected, g.direction == .left ? 1 : -1)) }
  private func pick(_ m: String) {
    guard m != selected else { return }
    guard usable(m) else { bounce(m > selected ? -1 : 1); return }
    selected = m; slide(); onPick?(m)
  }
  // (at an end: the row gives a little and comes back, as iPhone's lists)
  private func bounce(_ dir: CGFloat) {
    UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { self.pills.values.forEach { $0.bg.center.x += 14 * dir } } completion: { _ in
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.place() }
    }
  }
  private func slide() {
    UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) { self.paint(); self.place() }
  }
  private func paint() {
    let idle = light ? UIColor(red: 234 / 255, green: 234 / 255, blue: 236 / 255, alpha: 1) : UIColor(red: 39 / 255, green: 39 / 255, blue: 41 / 255, alpha: 1)
    let idleInk = light ? UIColor(red: 134 / 255, green: 134 / 255, blue: 137 / 255, alpha: 1) : UIColor(red: 157 / 255, green: 156 / 255, blue: 164 / 255, alpha: 1)
    for (m, p) in pills {
      let on = m == selected, ok = usable(m)
      p.bg.backgroundColor = on ? MailCats.blue(light) : idle
      p.label.textColor = on ? .white : idleInk
      p.label.text = PlanMonthChips.name(m, on: on)
      p.bg.alpha = ok ? 1 : 0.4
      p.bg.isUserInteractionEnabled = ok
      p.bg.accessibilityLabel = PlanMonthChips.name(m, on: true)
      p.bg.accessibilityTraits = on ? [.button, .selected] : ok ? .button : .notEnabled
    }
  }
  private func width(_ m: String) -> CGFloat {
    let f = UIFont.systemFont(ofSize: 17, weight: .semibold)
    return ceil((PlanMonthChips.name(m, on: m == selected) as NSString).size(withAttributes: [.font: f]).width) + 32
  }
  private func place() {
    guard let i = months.firstIndex(of: selected), bounds.width > 0 else { return }
    let gap: CGFloat = 9, y: CGFloat = 9
    // (the chosen one's middle in the page's middle; the rest laid out either side of it)
    let ws = months.map { width($0) }
    var x = bounds.width / 2 - ws[i] / 2
    for k in stride(from: i - 1, through: 0, by: -1) { x -= ws[k] + gap }
    for (k, m) in months.enumerated() {
      guard let p = pills[m] else { continue }
      p.bg.bounds = CGRect(x: 0, y: 0, width: ws[k], height: PlanMonthChips.H)
      p.bg.center = CGPoint(x: x + ws[k] / 2, y: y + PlanMonthChips.H / 2)
      p.label.frame = p.bg.bounds
      x += ws[k] + gap
    }
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { PlanMonthChips.H + 18 }
  // (placed again only when the page's width changes — a redraw mid-slide mustn't snap it)
  private var placedW: CGFloat = 0
  override func layoutSubviews() { super.layoutSubviews(); if bounds.width != placedW { placedW = bounds.width; UIView.performWithoutAnimation { place() } } }
}
final class PlanMonthBar: UIView, HomeBlock {
  private let prevB = UIButton(type: .system), nextB = UIButton(type: .system), label = UILabel()
  var onShift: ((Int) -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    for (b, s, d) in [(prevB, "chevron.left", -1), (nextB, "chevron.right", 1)] {
      if #available(iOS 26.0, *) { var c = UIButton.Configuration.glass(); c.image = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)); c.baseForegroundColor = .label; b.configuration = c }
      else { b.setImage(UIImage(systemName: s), for: .normal); b.tintColor = .label; b.backgroundColor = .tertiarySystemFill; b.layer.cornerRadius = 18 }
      b.addAction(UIAction { [weak self] _ in self?.onShift?(d) }, for: .touchUpInside)
      addSubview(b)
    }
    label.font = .systemFont(ofSize: 17, weight: .semibold); label.textAlignment = .center; addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ t: String, canPrev: Bool) { label.text = t; prevB.isEnabled = canPrev; prevB.alpha = canPrev ? 1 : 0.35 }
  func blockHeight(_ W: CGFloat) -> CGFloat { 56 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    prevB.frame = CGRect(x: 16, y: 8, width: 40, height: 40); nextB.frame = CGRect(x: W - 56, y: 8, width: 40, height: 40)
    label.frame = CGRect(x: 64, y: 8, width: W - 128, height: 40)
  }
}
// the skeleton's status: its pill, who / when, and the approver's note
final class PlanHead: UIView, HomeBlock {
  private let pill = PaddedLabel(), line = UILabel(), note = PaddedLabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    pill.font = .systemFont(ofSize: 13, weight: .semibold); pill.layer.cornerRadius = 9; pill.clipsToBounds = true; pill.insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    line.font = .systemFont(ofSize: 13); line.textColor = .secondaryLabel; line.numberOfLines = 0
    note.font = .systemFont(ofSize: 14); note.numberOfLines = 0; note.layer.cornerRadius = 14; note.clipsToBounds = true; note.insets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    note.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.14); note.textColor = .label
    [pill, line, note].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ t: String, col: UIColor, line l: String, note n: String) {
    pill.text = t; pill.textColor = col; pill.backgroundColor = col.withAlphaComponent(0.15)
    line.text = l; note.text = n.isEmpty ? nil : "“\(n)”"; note.isHidden = n.isEmpty
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat {
    let lh = (line.text ?? "").isEmpty ? 0 : ceil(line.sizeThatFits(CGSize(width: W - 40, height: 200)).height) + 6
    let nh = note.isHidden ? 0 : ceil(note.sizeThatFits(CGSize(width: W - 32, height: 400)).height) + 12
    return 8 + 26 + lh + nh + 10
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    let ps = pill.sizeThatFits(CGSize(width: W - 40, height: 26))
    pill.frame = CGRect(x: 20, y: 8, width: ps.width, height: 26)
    let lh = (line.text ?? "").isEmpty ? 0 : ceil(line.sizeThatFits(CGSize(width: W - 40, height: 200)).height)
    line.frame = CGRect(x: 20, y: pill.frame.maxY + 6, width: W - 40, height: lh)
    let nh = ceil(note.sizeThatFits(CGSize(width: W - 32, height: 400)).height)
    note.frame = CGRect(x: 16, y: line.frame.maxY + 12, width: W - 32, height: nh)
  }
}
// two capsules side by side: Send back · Approve skeleton
final class PlanActs: UIView, HomeBlock {
  private var l: UIButton!, r: UIButton!
  var onLeft: (() -> Void)?, onRight: (() -> Void)?
  func set(left: String, right: String) {
    guard l == nil else { return }
    l = Pop.capsule(left, filled: false) { [weak self] in self?.onLeft?() }; r = Pop.capsule(right, filled: true) { [weak self] in self?.onRight?() }
    [l!, r!].forEach { b in NSLayoutConstraint.deactivate(b.constraints); b.translatesAutoresizingMaskIntoConstraints = true; addSubview(b) }
  }
  func fadeRight(_ on: Bool) { r?.alpha = on ? 0.45 : 1; r?.accessibilityHint = on ? "Some posts have changes asked" : nil }
  func blockHeight(_ W: CGFloat) -> CGFloat { 76 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, w = (W - 32 - 10) / 2
    l?.frame = CGRect(x: 16, y: 12, width: w, height: 52); r?.frame = CGRect(x: 16 + w + 10, y: 12, width: w, height: 52)
  }
}
// a post, read only: what's in it; Looks good / Ask for changes for the approver
final class PlanPostVC: UIViewController {
  private let p: [String: Any], dark: Bool
  var onReview: ((String) -> Void)?, onOpenFile: (([String: Any]) -> Void)?
  init(_ p: [String: Any], dark: Bool) { self.p = p; self.dark = dark; super.init(nibName: nil, bundle: nil); overrideUserInterfaceStyle = dark ? .dark : .light }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    title = "Post"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let scroll = UIScrollView(); scroll.alwaysBounceVertical = true
    let st = UIStackView(); st.axis = .vertical; st.spacing = 6; st.alignment = .fill
    scroll.translatesAutoresizingMaskIntoConstraints = false; st.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll); scroll.addSubview(st)
    let review = (p["review"] as? Bool) == true
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      st.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8), st.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
      st.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20), st.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: review ? -100 : -30),
    ])
    st.addArrangedSubview(Pop.label(p["title"] as? String ?? "", 24, .bold))
    let meta = [p["fmt"] as? String, p["day"] as? String, p["occ"] as? String, p["ch"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    st.addArrangedSubview(Pop.label(meta, 14, .regular, .secondaryLabel))
    if let pr = p["prog"] as? [String: Any] { st.addArrangedSubview(Pop.label(pr["t"] as? String ?? "", 14, .semibold, .systemPurple)) }
    if let c = p["check"] as? [String: Any] { sec(st, "Review"); st.addArrangedSubview(box(c["t"] as? String ?? "", tint: (c["k"] as? String) == "ok" ? .systemGreen : .systemOrange)) }
    let made = (p["made"] as? [[String: Any]]) ?? []
    if !made.isEmpty { sec(st, "The finished work"); st.addArrangedSubview(files(made)) }
    for (k, t) in [("desc", "Description"), ("shots", "Shots"), ("copyEn", "Copy · English"), ("copyAr", "Copy · Arabic")] {
      guard let v = p[k] as? String, !v.isEmpty else { continue }
      sec(st, t); let b = box(v, tint: nil); if k == "copyAr" { (b.subviews.first as? UILabel)?.textAlignment = .right; b.semanticContentAttribute = .forceRightToLeft }; st.addArrangedSubview(b)
    }
    let refs = (p["refs"] as? [[String: Any]]) ?? []
    if !refs.isEmpty { sec(st, "References"); st.addArrangedSubview(files(refs)) }
    if review {
      let l = Pop.capsule("Ask for changes", filled: false) { [weak self] in self?.onReview?("changes") }
      let r = Pop.capsule("Looks good", filled: true) { [weak self] in self?.onReview?("ok") }
      let row = UIStackView(arrangedSubviews: [l, r]); row.axis = .horizontal; row.spacing = 10; row.distribution = .fillEqually
      row.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(row)
      NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), row.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)])
    }
  }
  private func sec(_ st: UIStackView, _ t: String) {
    let l = Pop.label(t.uppercased(), 12, .semibold, .secondaryLabel)
    st.setCustomSpacing(16, after: st.arrangedSubviews.last ?? l); st.addArrangedSubview(l)
  }
  private func box(_ t: String, tint: UIColor?) -> UIView {
    let v = UIView(); v.backgroundColor = tint?.withAlphaComponent(0.14) ?? .secondarySystemGroupedBackground; v.layer.cornerRadius = 14; v.layer.cornerCurve = .continuous
    let l = Pop.label(t, 15, .regular, tint == nil ? .label : .label); l.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(l)
    NSLayoutConstraint.activate([l.topAnchor.constraint(equalTo: v.topAnchor, constant: 10), l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -10), l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12), l.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12)])
    return v
  }
  // pictures as small tiles, other files and links as their names; a tap opens the file
  private func files(_ list: [[String: Any]]) -> UIView {
    let col = UIStackView(); col.axis = .vertical; col.spacing = 8
    let pics = UIStackView(); pics.axis = .horizontal; pics.spacing = 8
    for f in list {
      if (f["img"] as? Bool) == true, let u = f["url"] as? String {
        let i = UIImageView(); i.backgroundColor = .tertiarySystemFill; i.layer.cornerRadius = 12; i.clipsToBounds = true; i.contentMode = .scaleAspectFill; i.isUserInteractionEnabled = true
        i.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([i.widthAnchor.constraint(equalToConstant: 72), i.heightAnchor.constraint(equalToConstant: 72)])
        FeedLoader.shared.image(u + (u.contains("?") ? "&" : "?") + "w=320") { [weak i] img in i?.image = img }
        i.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapFile(_:)))); i.accessibilityValue = jsonString(f)
        pics.addArrangedSubview(i)
      } else {
        let b = UIButton(type: .system); b.contentHorizontalAlignment = .leading
        b.setTitle((f["link"] != nil ? "🔗 " : "📎 ") + (f["name"] as? String ?? ""), for: .normal); b.titleLabel?.font = .systemFont(ofSize: 15); b.titleLabel?.lineBreakMode = .byTruncatingMiddle
        b.addAction(UIAction { [weak self] _ in
          if let l = f["link"] as? String, let u = URL(string: l) { UIApplication.shared.open(u) } else { self?.onOpenFile?(f) }
        }, for: .touchUpInside)
        col.addArrangedSubview(b)
      }
    }
    if !pics.arrangedSubviews.isEmpty { pics.addArrangedSubview(UIView()); col.insertArrangedSubview(pics, at: 0) }
    return col
  }
  @objc private func tapFile(_ g: UITapGestureRecognizer) {
    guard let s = g.view?.accessibilityValue, let d = s.data(using: .utf8), let f = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
    onOpenFile?(f)
  }
  func alert(_ t: String) { let a = UIAlertController(title: t, message: nil, preferredStyle: .alert); a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true) }
}
// a note to send: ✕ · title · Send (Send waits for something written unless it's optional)
final class NoteVC: UIViewController, UITextViewDelegate {
  private let text = UITextView(), hint = UILabel(), optional: Bool
  private let sendFn: (String, @escaping (String?) -> Void) -> Void
  init(title: String, hint h: String, optional: Bool, send: @escaping (String, @escaping (String?) -> Void) -> Void) {
    self.optional = optional; sendFn = send
    super.init(nibName: nil, bundle: nil); self.title = title; hint.text = h
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let s = UIBarButtonItem(title: "Send", primaryAction: UIAction { [weak self] _ in self?.go() }); s.style = .done
    if #available(iOS 26.0, *) { s.tintColor = .systemBlue }
    s.isEnabled = optional; navigationItem.rightBarButtonItem = s
    hint.font = .systemFont(ofSize: 13); hint.textColor = .secondaryLabel; hint.numberOfLines = 0
    text.font = .systemFont(ofSize: 16); text.backgroundColor = .secondarySystemGroupedBackground; text.layer.cornerRadius = 14; text.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8); text.delegate = self
    [hint, text].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    NSLayoutConstraint.activate([
      hint.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      text.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8), text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      text.heightAnchor.constraint(equalToConstant: 110),
    ])
  }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); text.becomeFirstResponder() }
  func textViewDidChange(_ tv: UITextView) { navigationItem.rightBarButtonItem?.isEnabled = optional || !tv.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private func go() {
    navigationItem.rightBarButtonItem?.isEnabled = false
    sendFn(text.text.trimmingCharacters(in: .whitespacesAndNewlines)) { [weak self] err in
      guard let self = self else { return }
      if let e = err { self.navigationItem.rightBarButtonItem?.isEnabled = true; let a = UIAlertController(title: e, message: nil, preferredStyle: .alert); a.addAction(UIAlertAction(title: "OK", style: .default)); self.present(a, animated: true); return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      self.dismiss(animated: true)
    }
  }
}

// ---------- an Office Admin's claim rows (Haris 2026-11-04): a short swipe shows a button, then it's tapped —
// right: HR approved (a submitted claim, Finance Admins); left: Open claim (its PDF). Held: Paid on. A tap opens it too.
// Each row kept by its id and only drawn again when what it shows changed. ----------
final class SwipeRows: UIView, HomeBlock {
  var onApprove: ((String) -> Void)?, onOpen: ((String) -> Void)?, onHold: ((String) -> Void)?
  private let box = UIView()
  private var rows: [String: SwipeRow] = [:], order: [String] = [], seps: [UIView] = []
  private static let H: CGFloat = 70
  override init(frame: CGRect) { super.init(frame: frame); box.layer.cornerRadius = 16; box.layer.cornerCurve = .continuous; box.clipsToBounds = true; addSubview(box) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ list: [[String: Any]], look L: HomeLook, admin: Bool) {
    box.backgroundColor = L.card
    let ids = list.compactMap { $0["id"] as? String }
    for (id, r) in rows where !ids.contains(id) { r.removeFromSuperview(); rows[id] = nil }
    UIView.performWithoutAnimation {
      for x in list {
        guard let id = x["id"] as? String else { continue }
        let r = rows[id] ?? { let r = SwipeRow(); r.owner = self; box.addSubview(r); rows[id] = r; return r }()
        r.set(x, look: L, canApprove: admin && (x["st"] as? String) == "submitted")
        r.onApprove = { [weak self] in self?.onApprove?(id) }; r.onOpen = { [weak self] in self?.onOpen?(id) }; r.onHold = { [weak self] in self?.onHold?(id) }
      }
    }
    order = ids
    while seps.count < max(0, ids.count - 1) { let v = UIView(); v.backgroundColor = UIColor.separator; box.addSubview(v); seps.append(v) }
    seps.enumerated().forEach { $0.element.isHidden = $0.offset >= ids.count - 1 }
    setNeedsLayout()
  }
  func closeOthers(_ keep: SwipeRow) { rows.values.filter { $0 !== keep }.forEach { $0.close() } }
  func blockHeight(_ W: CGFloat) -> CGFloat { CGFloat(order.count) * SwipeRows.H + 8 }
  override func layoutSubviews() {
    super.layoutSubviews()
    box.frame = CGRect(x: 16, y: 4, width: bounds.width - 32, height: CGFloat(order.count) * SwipeRows.H)
    for (i, id) in order.enumerated() { if let r = rows[id] { r.bounds = CGRect(x: 0, y: 0, width: box.bounds.width, height: SwipeRows.H); r.center = CGPoint(x: box.bounds.width / 2, y: CGFloat(i) * SwipeRows.H + SwipeRows.H / 2) } }
    for (i, v) in seps.enumerated() where !v.isHidden { v.frame = CGRect(x: 62, y: CGFloat(i + 1) * SwipeRows.H - 0.5, width: box.bounds.width - 62, height: 0.5); box.bringSubviewToFront(v) }
  }
}
final class SwipeRow: UIView, UIGestureRecognizerDelegate {
  weak var owner: SwipeRows?
  var onApprove: (() -> Void)?, onOpen: (() -> Void)?, onHold: (() -> Void)?
  private let front = UIView(), pic = UIImageView(), name = UILabel(), sub = UILabel(), amt = UILabel(), pill = PaddedLabel()
  private let left = UIButton(type: .system), right = UIButton(type: .system)
  private var canApprove = false, offset: CGFloat = 0, photoPath: String?
  private static let W: CGFloat = 84
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    for (b, t, s, c) in [(left, "HR approved", "checkmark", UIColor.systemGreen), (right, "Open claim", "doc.text", UIColor.systemBlue)] {
      var cfg = UIButton.Configuration.plain(); cfg.image = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)); cfg.imagePlacement = .top; cfg.imagePadding = 4
      cfg.attributedTitle = AttributedString(t, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 12, weight: .semibold)])); cfg.baseForegroundColor = .white
      // square, as Mail's swipe buttons — no rounded corners (Haris 2026-11-04)
      cfg.cornerStyle = .fixed; cfg.background.cornerRadius = 0; cfg.background.backgroundColor = c
      b.configuration = cfg; b.backgroundColor = c; b.layer.cornerRadius = 0; b.alpha = 0; addSubview(b)
    }
    left.addAction(UIAction { [weak self] _ in UINotificationFeedbackGenerator().notificationOccurred(.success); self?.close(); self?.onApprove?() }, for: .touchUpInside)
    right.addAction(UIAction { [weak self] _ in self?.close(); self?.onOpen?() }, for: .touchUpInside)
    pic.layer.cornerRadius = 18; pic.clipsToBounds = true; pic.contentMode = .scaleAspectFill
    name.font = .systemFont(ofSize: 16, weight: .medium); sub.font = .systemFont(ofSize: 13); sub.textColor = .secondaryLabel
    amt.font = .systemFont(ofSize: 15, weight: .semibold); amt.textAlignment = .right
    pill.font = .systemFont(ofSize: 11.5, weight: .semibold); pill.layer.cornerRadius = 7; pill.clipsToBounds = true; pill.insets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
    [pic, name, sub, amt, pill].forEach { front.addSubview($0) }
    addSubview(front)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:))); pan.delegate = self; front.addGestureRecognizer(pan)
    front.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:))); hold.minimumPressDuration = 0.45; front.addGestureRecognizer(hold)
    _ = PressShrink.add(to: front)
  }
  required init?(coder: NSCoder) { fatalError() }
  private var sig = ""
  func set(_ x: [String: Any], look L: HomeLook, canApprove ok: Bool) {
    canApprove = ok
    front.backgroundColor = L.card
    let s = "\(x["name"] ?? "")|\(x["sub"] ?? "")|\(x["amt"] ?? "")|\(x["pill"] ?? "")|\(x["pk"] ?? "")|\(x["photo"] ?? "")|\(ok)|\(L.light)"
    guard s != sig else { return }
    sig = s
    name.text = x["name"] as? String; sub.text = x["sub"] as? String; amt.text = x["amt"] as? String
    pill.text = x["pill"] as? String
    let col: UIColor = (x["pk"] as? String) == "sub" ? .systemOrange : (x["pk"] as? String) == "ok" ? .systemGreen : .secondaryLabel
    pill.textColor = col; pill.backgroundColor = (x["pk"] as? String) == "paid" ? UIColor.tertiarySystemFill : col.withAlphaComponent(0.16)
    let ini = x["ini"] as? String ?? "", rgb = NativeSheetVC.color(x["rgb"]) ?? .systemGray
    let ph = x["photo"] as? String
    if ph != photoPath || pic.image == nil {
      photoPath = ph; pic.image = roundPic(nil, initials: ini, color: rgb, size: 36)
      if let p = ph { FeedLoader.shared.image(p) { [weak self] i in guard let self = self, self.photoPath == p, let i = i else { return }; self.pic.image = roundPic(i, initials: nil, color: nil, size: 36) } }
    }
    left.isHidden = !ok
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    left.frame = CGRect(x: 0, y: 0, width: SwipeRow.W, height: H); right.frame = CGRect(x: W - SwipeRow.W, y: 0, width: SwipeRow.W, height: H)
    front.bounds = CGRect(x: 0, y: 0, width: W, height: H); front.center = CGPoint(x: W / 2 + offset, y: H / 2)
    // the buttons only while the row is swiped — a touch and hold shrinks the row, and nothing may show behind it
    if offset > 0 { left.alpha = 1 } else if offset < 0 { right.alpha = 1 }
    pic.frame = CGRect(x: 14, y: (H - 36) / 2, width: 36, height: 36)
    let aw = max(ceil(amt.sizeThatFits(CGSize(width: 160, height: 20)).width), ceil(pill.sizeThatFits(CGSize(width: 160, height: 20)).width))
    amt.frame = CGRect(x: W - 14 - aw, y: H / 2 - 20, width: aw, height: 20)
    let pw = ceil(pill.sizeThatFits(CGSize(width: 160, height: 20)).width); pill.frame = CGRect(x: W - 14 - pw, y: H / 2 + 3, width: pw, height: 18)
    name.frame = CGRect(x: 62, y: H / 2 - 20, width: W - 62 - aw - 24, height: 20); sub.frame = CGRect(x: 62, y: H / 2 + 2, width: W - 62 - aw - 24, height: 18)
  }
  func close() { guard offset != 0 else { return }; offset = 0; UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, animations: { self.layoutSubviews() }) { _ in self.hideButtons() } }
  private func hideButtons() { if offset == 0 { left.alpha = 0; right.alpha = 0 } }
  @objc private func tapped() { if offset != 0 { close(); return }; onOpen?() }
  @objc private func held(_ g: UILongPressGestureRecognizer) { if g.state == .began { close(); onHold?() } }
  private var startOffset: CGFloat = 0
  @objc private func panned(_ g: UIPanGestureRecognizer) {
    let dx = g.translation(in: self).x
    switch g.state {
    case .began: startOffset = offset; owner?.closeOthers(self)
    case .changed:
      var o = startOffset + dx
      o = min(canApprove ? SwipeRow.W + 20 : 0, max(-SwipeRow.W - 20, o))
      offset = o; layoutSubviews()
    default:
      let v = g.velocity(in: self).x
      let to: CGFloat = (offset > 36 || (v > 400 && offset > 0)) && canApprove ? SwipeRow.W : (offset < -36 || (v < -400 && offset < 0)) ? -SwipeRow.W : 0
      if to != 0 && to != startOffset { UISelectionFeedbackGenerator().selectionChanged() }
      offset = to
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, animations: { self.layoutSubviews() }) { _ in self.hideButtons() }
    }
  }
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard let p = g as? UIPanGestureRecognizer else { return true }
    let v = p.velocity(in: self); return abs(v.x) > abs(v.y) * 1.2
  }
}

// ---------- the add sheets (Haris 2026-11-04): a claim by hand (Person, Amount, last / this month, its PDF), a subscription
// (Name, Amount, Billing day, Invoice), an office expense (Name, Amount, Payment date, Invoice) ----------
final class MoneyFormVC: UIViewController {
  enum Kind { case claim, sub, expense }
  let kind: Kind
  var onSave: (([String: Any], @escaping (String?) -> Void) -> Void)?
  var onPerson: ((String, @escaping (String?, String?) -> Void) -> Void)?
  private let people: [(String, String)], months: [(String, String)], dark: Bool
  private let cookies: (@escaping (String) -> Void) -> Void
  private let stack = UIStackView(), nameF = UITextField(), amountF = UITextField(), personB = UIButton(type: .system), dayB = UIButton(type: .system), fileB = UIButton(type: .system)
  private let monthSeg = UISegmentedControl(), datePick = UIDatePicker(), err = UILabel()
  private var who: String?, day = Calendar.current.component(.day, from: Date()), file: [String: Any]?, busy = false
  private var peopleList: [(String, String)]
  init(kind: Kind, people: [(String, String)], months: [(String, String)], dark: Bool, cookies: @escaping (@escaping (String) -> Void) -> Void) {
    self.kind = kind; self.people = people; self.peopleList = people; self.months = months; self.dark = dark; self.cookies = cookies
    super.init(nibName: nil, bundle: nil); overrideUserInterfaceStyle = dark ? .dark : .light
  }
  required init?(coder: NSCoder) { fatalError() }
  func inNav() -> UIViewController {
    let n = UINavigationController(rootViewController: self); n.overrideUserInterfaceStyle = overrideUserInterfaceStyle
    if let s = n.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
    return n
  }
  private func label(_ t: String) -> UILabel { let l = UILabel(); l.text = t.uppercased(); l.font = .systemFont(ofSize: 13); l.textColor = .secondaryLabel; return l }
  private func boxed(_ v: UIView) -> UIView {
    let b = UIView(); b.backgroundColor = .secondarySystemGroupedBackground; b.layer.cornerRadius = 12; b.layer.cornerCurve = .continuous
    v.translatesAutoresizingMaskIntoConstraints = false; b.addSubview(v)
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 14), v.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -14), v.topAnchor.constraint(equalTo: b.topAnchor, constant: 6), v.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -6), b.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)])
    return b
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    title = kind == .claim ? "Add claim by hand" : kind == .sub ? "Add subscription" : "Add office expense"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", primaryAction: UIAction { [weak self] _ in self?.save() })
    let scroll = UIScrollView(); scroll.keyboardDismissMode = .interactive
    stack.axis = .vertical; stack.spacing = 8
    scroll.translatesAutoresizingMaskIntoConstraints = false; stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll); scroll.addSubview(stack)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -18), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24)])
    if kind == .claim {
      stack.addArrangedSubview(label("Person"))
      personB.contentHorizontalAlignment = .leading; personB.showsMenuAsPrimaryAction = true; personB.titleLabel?.font = .systemFont(ofSize: 17)
      paintPerson(); stack.addArrangedSubview(boxed(personB))
    } else {
      stack.addArrangedSubview(label("Name"))
      nameF.placeholder = kind == .sub ? "e.g. Adobe Creative Cloud" : "e.g. Studio lights"; nameF.font = .systemFont(ofSize: 17); nameF.autocapitalizationType = .words
      stack.addArrangedSubview(boxed(nameF))
    }
    stack.addArrangedSubview(label("Amount (\u{20C3})"))
    amountF.placeholder = "0.00"; amountF.keyboardType = .decimalPad; amountF.font = .systemFont(ofSize: 17)
    stack.addArrangedSubview(boxed(amountF))
    switch kind {
    case .claim:
      stack.addArrangedSubview(label("Month"))
      for (i, m) in months.enumerated() { monthSeg.insertSegment(withTitle: m.1, at: i, animated: false) }
      monthSeg.selectedSegmentIndex = max(0, months.count - 1)
      stack.addArrangedSubview(monthSeg)
      let hint = UILabel(); hint.text = "It joins that month’s claims as Submitted — then HR approved and Paid on, as every claim."; hint.font = .systemFont(ofSize: 12.5); hint.textColor = .secondaryLabel; hint.numberOfLines = 0
      stack.addArrangedSubview(hint)
    case .sub:
      stack.addArrangedSubview(label("Billing day each month"))
      dayB.contentHorizontalAlignment = .leading; dayB.showsMenuAsPrimaryAction = true; dayB.titleLabel?.font = .systemFont(ofSize: 17)
      paintDay(); stack.addArrangedSubview(boxed(dayB))
    case .expense:
      stack.addArrangedSubview(label("Payment date"))
      datePick.datePickerMode = .date; datePick.preferredDatePickerStyle = .compact; datePick.maximumDate = Date()
      let row = UIStackView(arrangedSubviews: [datePick, UIView()]); stack.addArrangedSubview(boxed(row))
    }
    stack.addArrangedSubview(label(kind == .claim ? "PDF" : "Invoice"))
    fileB.contentHorizontalAlignment = .leading; fileB.showsMenuAsPrimaryAction = true; fileB.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    paintFile(); stack.addArrangedSubview(boxed(fileB))
    err.font = .systemFont(ofSize: 14); err.textColor = .systemRed; err.numberOfLines = 0
    stack.addArrangedSubview(err)
    for v in stack.arrangedSubviews where v is UILabel && (v as! UILabel).font.pointSize == 13 { stack.setCustomSpacing(6, after: v) }
  }
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if kind == .claim { amountF.becomeFirstResponder() } else { nameF.becomeFirstResponder() } }
  private func paintPerson() {
    personB.setTitle(peopleList.first(where: { $0.0 == who })?.1 ?? "Choose a person…", for: .normal)
    personB.setTitleColor(who == nil ? .secondaryLabel : .label, for: .normal)
    let team = peopleList.filter { $0.0.hasPrefix("u:") }.map { p in UIAction(title: p.1, state: p.0 == who ? .on : .off) { [weak self] _ in self?.who = p.0; self?.paintPerson() } }
    let other = peopleList.filter { $0.0.hasPrefix("p:") }.map { p in UIAction(title: p.1, state: p.0 == who ? .on : .off) { [weak self] _ in self?.who = p.0; self?.paintPerson() } }
    let add = UIAction(title: "Someone who isn’t a team member…", image: UIImage(systemName: "plus")) { [weak self] _ in self?.askPerson() }
    personB.menu = UIMenu(children: [UIMenu(title: "Team members", options: .displayInline, children: team)] + (other.isEmpty ? [] : [UIMenu(title: "Other people", options: .displayInline, children: other)]) + [UIMenu(options: .displayInline, children: [add])])
  }
  private func askPerson() {
    let a = UIAlertController(title: "Someone who isn’t a team member", message: nil, preferredStyle: .alert)
    a.addTextField { $0.placeholder = "Name"; $0.autocapitalizationType = .words }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak a] _ in
      let n = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
      self?.onPerson?(n) { id, name in guard let self = self, let id = id else { self?.err.text = "Couldn’t add that person — try again"; return }; self.peopleList.append((id, name ?? n)); self.who = id; self.paintPerson() }
    })
    present(a, animated: true)
  }
  private func paintDay() {
    let ord = { (n: Int) -> String in n % 10 == 1 && n != 11 ? "\(n)st" : n % 10 == 2 && n != 12 ? "\(n)nd" : n % 10 == 3 && n != 13 ? "\(n)rd" : "\(n)th" }
    dayB.setTitle(ord(day), for: .normal); dayB.setTitleColor(.label, for: .normal)
    dayB.menu = UIMenu(children: (1...31).map { n in UIAction(title: ord(n), state: n == day ? .on : .off) { [weak self] _ in self?.day = n; self?.paintDay() } })
  }
  private func paintFile() {
    let has = file != nil
    fileB.setTitle(busy ? "Uploading…" : has ? "📎 \(file?["name"] as? String ?? "File")" : (kind == .claim ? "📎 Attach the claim (PDF)" : "📎 Attach invoice"), for: .normal)
    fileB.setTitleColor(.systemBlue, for: .normal)
    var acts = [("Files", "folder", "files"), ("Photos", "photo.on.rectangle", "photos"), ("Camera", "camera", "camera")].map { t in UIAction(title: t.0, image: UIImage(systemName: t.1)) { [weak self] _ in self?.pick(t.2) } }
    if has { acts.append(UIAction(title: "Remove", image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in self?.file = nil; self?.paintFile() }) }
    fileB.menu = UIMenu(children: acts)
  }
  private func monthNow() -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"; return f.string(from: Date()) }
  private func pick(_ src: String) {
    Picker.shared.pick(from: self, single: true, source: src) { [weak self] r in
      guard let self = self, let x = ((r["files"] as? [[String: Any]]) ?? []).first, let tok = x["token"] as? String, let url = Picker.shared.url(tok) else { return }
      let name = x["name"] as? String ?? "File"
      let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
      let month = self.kind == .claim && self.monthSeg.selectedSegmentIndex >= 0 && self.monthSeg.selectedSegmentIndex < self.months.count ? self.months[self.monthSeg.selectedSegmentIndex].0 : self.monthNow()
      let dest = "Finance/" + (self.kind == .claim ? "Reimbursements" : self.kind == .sub ? "Subscriptions" : "Expenses") + "/" + month
      self.busy = true; self.paintFile()
      Uploader.send(url, name: name, task: "", dest: dest, cookies: self.cookies, progress: { _ in }) { [weak self] path in
        guard let self = self else { return }
        self.busy = false
        if let p = path { self.file = ["path": p, "name": name, "size": size]; self.err.text = nil } else { self.err.text = "Couldn’t upload — try again" }
        self.paintFile()
      }
    }
  }
  private func save() {
    guard !busy else { err.text = "Still uploading — one moment"; return }
    var f: [String: Any] = ["amount": (amountF.text ?? "").replacingOccurrences(of: ",", with: "")]
    switch kind {
    case .claim:
      f["who"] = who ?? ""
      f["month"] = monthSeg.selectedSegmentIndex >= 0 && monthSeg.selectedSegmentIndex < months.count ? months[monthSeg.selectedSegmentIndex].0 : monthNow()
    case .sub: f["name"] = nameF.text ?? ""; f["day"] = day
    case .expense:
      f["name"] = nameF.text ?? ""
      let d = DateFormatter(); d.calendar = Calendar(identifier: .gregorian); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = "yyyy-MM-dd"; f["date"] = d.string(from: datePick.date)
    }
    if let x = file { f["file"] = x }
    navigationItem.rightBarButtonItem?.isEnabled = false
    onSave?(f) { [weak self] e in
      guard let self = self else { return }
      self.navigationItem.rightBarButtonItem?.isEnabled = true
      if let e = e { UINotificationFeedbackGenerator().notificationOccurred(.error); self.err.text = e } else { UINotificationFeedbackGenerator().notificationOccurred(.success); self.dismiss(animated: true) }
    }
  }
}

// ---------- the CD's Reviews (Haris 2026-11-04, the approved mockup): Waiting · Reviewed, a request, Request amendments.
// Tap only — no swipes, no hold: she opens a request to decide. ----------

// the requests: one rounded group, a row each — the sender's photo, the task, the client, who sent what and when, the
// files' pictures (waiting) or the result (reviewed), the Round tag. Rows kept by id, only what changed is drawn again.
final class ReviewList: UIView, HomeBlock {
  var onOpen: ((String) -> Void)?
  private let box = UIView()
  private var rows: [String: ReviewRow] = [:], order: [String] = [], seps: [UIView] = []
  override init(frame: CGRect) { super.init(frame: frame); box.layer.cornerRadius = 16; box.layer.cornerCurve = .continuous; box.clipsToBounds = true; addSubview(box) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ items: [[String: Any]], look L: HomeLook, decided: Bool) {
    box.backgroundColor = L.card
    let ids = items.map { $0["id"] as? String ?? "" }
    UIView.performWithoutAnimation {
      for (id, r) in rows where !ids.contains(id) { r.removeFromSuperview(); rows[id] = nil }
      for x in items {
        let id = x["id"] as? String ?? ""
        let r = rows[id] ?? { let r = ReviewRow(); box.addSubview(r); rows[id] = r; return r }()
        r.onTap = { [weak self] in self?.onOpen?(id) }
        r.set(x, look: L, decided: decided)
      }
      while seps.count < max(0, ids.count - 1) { let v = UIView(); box.addSubview(v); seps.append(v) }
      for (i, v) in seps.enumerated() { v.isHidden = i >= ids.count - 1; v.backgroundColor = .separator }   // (iPhone's own line, as the app's other lists — Haris 2026-11-04)
    }
    order = ids
    setNeedsLayout()
  }
  private func hOf(_ id: String, _ w: CGFloat) -> CGFloat { rows[id]?.height(w) ?? 64 }
  func row(_ id: String) -> UIView? { rows[id] }
  // the WhatsApp pulse on one row: a see-through grey over it, once
  func pulse(_ id: String) {
    guard let r = rows[id] else { return }
    let band = UIView(frame: r.bounds); band.isUserInteractionEnabled = false; band.alpha = 0
    band.backgroundColor = traitCollection.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.13) : UIColor.black.withAlphaComponent(0.08)
    r.addSubview(band)
    UIView.animate(withDuration: 0.2, delay: 0.35, options: [.curveEaseOut]) { band.alpha = 1 } completion: { _ in
      UIView.animate(withDuration: 0.6, delay: 0.6, options: [.curveEaseInOut]) { band.alpha = 0 } completion: { _ in band.removeFromSuperview() }
    }
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { order.reduce(0) { $0 + hOf($1, W - 32) } + 8 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width - 32
    box.frame = CGRect(x: 16, y: 4, width: w, height: order.reduce(0) { $0 + hOf($1, w) })
    var y: CGFloat = 0
    for (i, id) in order.enumerated() {
      guard let r = rows[id] else { continue }
      let h = hOf(id, w)
      r.bounds = CGRect(x: 0, y: 0, width: box.bounds.width, height: h); r.center = CGPoint(x: box.bounds.width / 2, y: y + h / 2)
      y += h
      let px = 1 / max(1, window?.screen.scale ?? UIScreen.main.scale)
      if i < seps.count, !seps[i].isHidden { seps[i].frame = CGRect(x: 62, y: y - px / 2, width: box.bounds.width - 62, height: px); box.bringSubviewToFront(seps[i]) }
    }
  }
}
final class ReviewRow: UIView {
  var onTap: (() -> Void)?
  private let pic = UIImageView(), title = UILabel(), client = UILabel(), dot = UIView(), sub = UILabel(), rtag = PaddedLabel()
  private var thumbs: [UIImageView] = []
  private var sig = "", photoPath: String?, decided = false
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.layer.cornerRadius = 18; pic.clipsToBounds = true; pic.contentMode = .scaleAspectFill
    title.font = .systemFont(ofSize: 16, weight: .medium); title.numberOfLines = 2
    client.font = .systemFont(ofSize: 13); client.textColor = .secondaryLabel
    sub.font = .systemFont(ofSize: 13); sub.textColor = .secondaryLabel
    dot.layer.cornerRadius = 4
    rtag.font = .systemFont(ofSize: 11.5, weight: .semibold); rtag.layer.cornerRadius = 7; rtag.clipsToBounds = true; rtag.insets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
    [pic, title, client, dot, sub, rtag].forEach { addSubview($0) }
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    _ = PressShrink.add(to: self)
    accessibilityTraits = .button; isAccessibilityElement = true
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func tapped() { UISelectionFeedbackGenerator().selectionChanged(); onTap?() }
  func set(_ x: [String: Any], look L: HomeLook, decided d: Bool) {
    decided = d
    let files = (x["files"] as? [[String: Any]]) ?? []
    let res = x["res"] as? [String: Any]
    let s = "\(x["task"] ?? "")|\(x["client"] ?? "")|\(x["sub"] ?? "")|\(x["round"] ?? "")|\(x["carried"] ?? "")|\(res?["t"] ?? "")|\(files.map { "\($0["id"] ?? "")" })|\(x["photo"] ?? "")|\(L.light)|\(d)"
    guard s != sig else { return }
    sig = s
    title.text = x["task"] as? String; client.text = x["client"] as? String; sub.text = x["sub"] as? String
    dot.backgroundColor = NativeSheetVC.color(x["crgb"]) ?? .systemGray
    let round = x["round"] as? Int ?? 1, carried = x["carried"] as? Int ?? 0
    if let r = res {
      let k = r["k"] as? String ?? ""
      let c: UIColor = k == "ok" ? .systemGreen : k == "mix" ? .systemPurple : .systemOrange
      rtag.text = r["t"] as? String; rtag.textColor = c; rtag.backgroundColor = c.withAlphaComponent(0.15)
    } else {
      rtag.text = "Round \(round)" + (carried > 0 ? " · \(carried) ✓" : ""); rtag.textColor = .systemBlue; rtag.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
    }
    let ini = x["ini"] as? String ?? "", rgb = NativeSheetVC.color(x["rgb"]) ?? .systemGray
    let ph = x["photo"] as? String
    if ph != photoPath || pic.image == nil {
      photoPath = ph; pic.image = roundPic(nil, initials: ini, color: rgb, size: 36)
      if let p = ph { FeedLoader.shared.image(p) { [weak self] i in guard let self = self, self.photoPath == p, let i = i else { return }; self.pic.image = roundPic(i, initials: nil, color: nil, size: 36) } }
    }
    // (waiting: up to 4 of the files' pictures)
    let show = d ? [] : Array(files.prefix(4))
    while thumbs.count < show.count { let v = UIImageView(); v.layer.cornerRadius = 8; v.layer.cornerCurve = .continuous; v.clipsToBounds = true; v.contentMode = .scaleAspectFill; addSubview(v); thumbs.append(v) }
    for (i, v) in thumbs.enumerated() {
      v.isHidden = i >= show.count
      guard i < show.count else { continue }
      let f = show[i]; v.backgroundColor = UIColor.tertiarySystemFill; v.image = nil
      if let p = f["pic"] as? String { FeedLoader.shared.image(p) { [weak v] img in v?.image = img } }
    }
    accessibilityLabel = "\(x["task"] ?? ""), \(x["client"] ?? ""), \(x["sub"] ?? ""), \(rtag.text ?? "")"
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    let tw = ceil(rtag.sizeThatFits(CGSize(width: 160, height: 20)).width)
    rtag.frame = CGRect(x: W - 14 - tw, y: 13, width: tw, height: 18)
    pic.frame = CGRect(x: 14, y: 12, width: 36, height: 36)
    let x: CGFloat = 62, w = W - x - tw - 26
    let th = min(40, ceil(title.sizeThatFits(CGSize(width: w, height: 60)).height))
    title.frame = CGRect(x: x, y: 11, width: w, height: th)
    dot.frame = CGRect(x: x, y: title.frame.maxY + 7, width: 8, height: 8)
    client.frame = CGRect(x: x + 13, y: title.frame.maxY + 2, width: W - x - 27, height: 17)
    sub.frame = CGRect(x: x, y: client.frame.maxY + 1, width: W - x - 14, height: 17)
    var y = sub.frame.maxY
    if thumbs.contains(where: { !$0.isHidden }) {
      for (i, v) in thumbs.enumerated() where !v.isHidden { v.frame = CGRect(x: x + CGFloat(i) * 50, y: y + 8, width: 44, height: 44) }
      y += 52
    }
  }
  // (its height for a width: the title's lines, the client, who sent what, the pictures)
  func height(_ W: CGFloat) -> CGFloat {
    let tw = ceil(rtag.sizeThatFits(CGSize(width: 160, height: 20)).width)
    let th = min(40, ceil(title.sizeThatFits(CGSize(width: W - 62 - tw - 26, height: 60)).height))
    return max(64, 11 + th + 2 + 17 + 1 + 17 + (thumbs.contains(where: { !$0.isHidden }) ? 52 : 0) + 12)
  }
}

// a request's top: who sent it (photo, "Yousef sent 3 files", the client, the Round tag), the files large — swiped
// sideways, a tap opens it in the preview (videos play there) — and the strip of all of them under it (✓ = approved)
final class ReviewHero: UIView, HomeBlock, UIScrollViewDelegate {
  var onFile: ((String) -> Void)?
  private let pic = UIImageView(), who = UILabel(), meta = UILabel(), dot = UIView(), rtag = PaddedLabel()
  private let pager = UIScrollView(), strip = UIScrollView()
  private var pages: [UIView] = [], chips: [UIImageView] = [], files: [[String: Any]] = []
  private var sig = "", page = 0, photoPath: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.layer.cornerRadius = 18; pic.clipsToBounds = true
    who.font = .systemFont(ofSize: 15, weight: .semibold); meta.font = .systemFont(ofSize: 13); meta.textColor = .secondaryLabel
    dot.layer.cornerRadius = 4
    rtag.font = .systemFont(ofSize: 11.5, weight: .semibold); rtag.layer.cornerRadius = 7; rtag.clipsToBounds = true; rtag.insets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
    rtag.textColor = .systemBlue; rtag.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
    pager.isPagingEnabled = true; pager.showsHorizontalScrollIndicator = false; pager.delegate = self; pager.clipsToBounds = true
    strip.showsHorizontalScrollIndicator = false; strip.clipsToBounds = false
    [pic, who, meta, dot, rtag, pager, strip].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ x: [String: Any], look L: HomeLook) {
    let fl = ((x["files"] as? [[String: Any]]) ?? []) + ((x["carriedFiles"] as? [[String: Any]]) ?? []).map { var f = $0; f["carried"] = true; return f }
    let s = "\(fl.map { "\($0["id"] ?? "")\($0["mark"] ?? "")" })|\(x["sub"] ?? "")|\(x["round"] ?? "")|\(x["photo"] ?? "")|\(L.light)"
    guard s != sig else { return }
    sig = s; files = fl
    who.text = "\(x["first"] as? String ?? "") sent \((x["files"] as? [Any])?.count ?? 0) file\(((x["files"] as? [Any])?.count ?? 0) == 1 ? "" : "s")"
    let carried = x["carried"] as? Int ?? 0
    meta.text = [x["client"] as? String ?? "", carried > 0 ? "\(carried) already approved" : (x["sub"] as? String ?? "").components(separatedBy: " · ").last ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    dot.backgroundColor = NativeSheetVC.color(x["crgb"]) ?? .systemGray
    rtag.text = "Round \(x["round"] as? Int ?? 1)"
    let ini = x["ini"] as? String ?? "", rgb = NativeSheetVC.color(x["rgb"]) ?? .systemGray, ph = x["photo"] as? String
    if ph != photoPath || pic.image == nil { photoPath = ph; pic.image = roundPic(nil, initials: ini, color: rgb, size: 36); if let p = ph { FeedLoader.shared.image(p) { [weak self] i in guard let self = self, self.photoPath == p, let i = i else { return }; self.pic.image = roundPic(i, initials: nil, color: nil, size: 36) } } }
    UIView.performWithoutAnimation {
      pages.forEach { $0.removeFromSuperview() }; chips.forEach { $0.removeFromSuperview() }
      pages = fl.enumerated().map { (i, f) -> UIView in
        let v = UIView(); v.backgroundColor = .tertiarySystemFill; v.layer.cornerRadius = 18; v.layer.cornerCurve = .continuous; v.clipsToBounds = true
        let im = UIImageView(); im.contentMode = .scaleAspectFit; im.tag = 1; v.addSubview(im)
        let ext = UILabel(); ext.text = f["ext"] as? String; ext.font = .systemFont(ofSize: 28, weight: .bold); ext.textColor = .secondaryLabel; ext.textAlignment = .center; ext.tag = 2; v.addSubview(ext)
        let name = PaddedLabel(); name.text = ((f["video"] as? Bool) == true ? "▶ " : "") + (f["name"] as? String ?? ""); name.font = .systemFont(ofSize: 12.5, weight: .semibold); name.textColor = .white
        name.backgroundColor = UIColor.black.withAlphaComponent(0.45); name.layer.cornerRadius = 9; name.clipsToBounds = true; name.insets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9); name.tag = 3; v.addSubview(name)
        let mk = (f["mark"] as? String) ?? ""
        if mk == "ok" || mk == "need" {
          let b = PaddedLabel(); b.text = (f["carried"] as? Bool) == true ? "✓ Approved earlier" : mk == "ok" ? "✓ Approved" : "✎ Changes"; b.font = .systemFont(ofSize: 12, weight: .bold); b.textColor = .white
          b.backgroundColor = mk == "ok" ? UIColor.systemGreen.withAlphaComponent(0.9) : UIColor.systemOrange.withAlphaComponent(0.92); b.layer.cornerRadius = 9; b.clipsToBounds = true; b.insets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9); b.tag = 4; v.addSubview(b)
        }
        if let p = f["big"] as? String { FeedLoader.shared.image(p) { [weak im, weak ext] img in im?.image = img; ext?.isHidden = img != nil } }
        let t = UITapGestureRecognizer(target: self, action: #selector(tappedPage(_:))); v.addGestureRecognizer(t); v.accessibilityLabel = f["name"] as? String; v.isAccessibilityElement = true; v.accessibilityTraits = .button
        _ = i; pager.addSubview(v); return v
      }
      chips = fl.enumerated().map { (i, f) -> UIImageView in
        // (the picture in a box of its own that clips it — the ✓ sits outside that box: a picture went out of its
        //  square, Haris 2026-11-04)
        let v = UIImageView(); v.isUserInteractionEnabled = true; v.tag = i; v.clipsToBounds = false
        let pic = UIImageView(); pic.contentMode = .scaleAspectFill; pic.clipsToBounds = true; pic.layer.cornerRadius = 10; pic.layer.cornerCurve = .continuous; pic.backgroundColor = .tertiarySystemFill; pic.tag = 8
        pic.layer.borderColor = UIColor.systemBlue.cgColor; v.addSubview(pic)
        if let p = f["pic"] as? String { FeedLoader.shared.image(p) { [weak pic] img in pic?.image = img } }
        v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tappedChip(_:))))
        if (f["mark"] as? String) == "ok" { let ck = UIImageView(image: UIImage(systemName: "checkmark.circle.fill")); ck.tintColor = .systemGreen; ck.backgroundColor = .systemBackground; ck.layer.cornerRadius = 9; ck.clipsToBounds = true; ck.tag = 9; ck.frame = CGRect(x: 0, y: 0, width: 18, height: 18); v.addSubview(ck) }
        strip.addSubview(v); return v
      }
      page = min(page, max(0, fl.count - 1))
    }
    strip.isHidden = fl.count < 2
    setNeedsLayout()
  }
  private var bigH: CGFloat { let W = bounds.width > 0 ? bounds.width : 390; return min(440, (W - 32) * 1.05) }
  func blockHeight(_ W: CGFloat) -> CGFloat { 60 + min(440, (W - 32) * 1.05) + (files.count < 2 ? 12 : 78) }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    pic.frame = CGRect(x: 18, y: 10, width: 36, height: 36)
    let tw = ceil(rtag.sizeThatFits(CGSize(width: 120, height: 20)).width)
    rtag.frame = CGRect(x: W - 18 - tw, y: 19, width: tw, height: 18)
    who.frame = CGRect(x: 64, y: 9, width: W - 64 - tw - 30, height: 20)
    dot.frame = CGRect(x: 64, y: 35, width: 8, height: 8)
    meta.frame = CGRect(x: 77, y: 30, width: W - 77 - tw - 30, height: 17)
    let H = bigH
    pager.frame = CGRect(x: 16, y: 60, width: W - 32, height: H)
    pager.contentSize = CGSize(width: (W - 32) * CGFloat(pages.count), height: H)
    for (i, v) in pages.enumerated() {
      v.frame = CGRect(x: CGFloat(i) * (W - 32), y: 0, width: W - 32, height: H).insetBy(dx: 0, dy: 0)
      v.viewWithTag(1)?.frame = v.bounds
      v.viewWithTag(2)?.frame = v.bounds
      if let n = v.viewWithTag(3) as? UILabel { let s = n.sizeThatFits(CGSize(width: v.bounds.width - 24, height: 30)); n.frame = CGRect(x: 12, y: v.bounds.height - 12 - s.height, width: min(s.width, v.bounds.width - 24), height: s.height) }
      if let b = v.viewWithTag(4) as? UILabel { let s = b.sizeThatFits(CGSize(width: 200, height: 30)); b.frame = CGRect(x: v.bounds.width - 12 - s.width, y: 12, width: s.width, height: s.height) }
    }
    if !pager.isDragging && !pager.isDecelerating { pager.contentOffset.x = CGFloat(page) * (W - 32) }
    strip.frame = CGRect(x: 0, y: 60 + H + 12, width: W, height: 56)
    let cw: CGFloat = 50, gap: CGFloat = 8, total = CGFloat(chips.count) * cw + CGFloat(max(0, chips.count - 1)) * gap
    let x0 = max(16, (W - total) / 2)
    for (i, v) in chips.enumerated() {
      v.frame = CGRect(x: x0 + CGFloat(i) * (cw + gap), y: 3, width: cw, height: cw)
      v.viewWithTag(8)?.frame = v.bounds
      v.viewWithTag(9)?.frame = CGRect(x: cw - 12, y: -6, width: 18, height: 18)
      v.viewWithTag(8)?.layer.borderWidth = i == page ? 2.5 : 0; v.alpha = i == page ? 1 : 0.6
    }
    strip.contentSize = CGSize(width: x0 * 2 + total, height: 56)
  }
  func scrollViewDidEndDecelerating(_ s: UIScrollView) { let w = max(1, s.bounds.width); let p = Int(round(s.contentOffset.x / w)); if p != page { page = p; UISelectionFeedbackGenerator().selectionChanged(); paintChips() } }
  private func paintChips() { for (i, v) in chips.enumerated() { UIView.animate(withDuration: 0.2) { v.alpha = i == self.page ? 1 : 0.6 }; v.viewWithTag(8)?.layer.borderWidth = i == page ? 2.5 : 0 } }
  @objc private func tappedChip(_ g: UITapGestureRecognizer) { guard let i = g.view?.tag, i < pages.count else { return }; page = i; UISelectionFeedbackGenerator().selectionChanged(); UIView.animate(withDuration: 0.3) { self.pager.contentOffset.x = CGFloat(i) * self.pager.bounds.width }; paintChips() }
  @objc private func tappedPage(_ g: UITapGestureRecognizer) { guard let v = g.view, let i = pages.firstIndex(of: v), i < files.count, let id = files[i]["id"] as? String else { return }; onFile?(id) }
}

// a card of words with a small caption (the brief; your note last round; the decision's note)
final class ReviewNote: UIView, HomeBlock {
  private let box = UIView(), cap = UILabel(), body = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    box.layer.cornerRadius = 14; box.layer.cornerCurve = .continuous
    cap.font = .systemFont(ofSize: 12, weight: .semibold); cap.textColor = .secondaryLabel
    body.font = .systemFont(ofSize: 15); body.numberOfLines = 0
    addSubview(box); box.addSubview(cap); box.addSubview(body)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ c: String, _ t: String, look L: HomeLook) { cap.text = c.uppercased(); if body.text != t { body.text = t; setNeedsLayout() }; box.backgroundColor = L.card }
  func blockHeight(_ W: CGFloat) -> CGFloat { 12 + 12 + 18 + ceil(body.sizeThatFits(CGSize(width: W - 32 - 26, height: 600)).height) + 12 }
  override func layoutSubviews() {
    super.layoutSubviews()
    box.frame = CGRect(x: 16, y: 12, width: bounds.width - 32, height: bounds.height - 12)
    cap.frame = CGRect(x: 13, y: 11, width: box.bounds.width - 26, height: 15)
    body.frame = CGRect(x: 13, y: 29, width: box.bounds.width - 26, height: box.bounds.height - 29 - 11)
  }
}

// Request amendments (orange) and Approve (green), side by side
final class ReviewActs: UIView, HomeBlock {
  var onAmend: (() -> Void)?, onApprove: (() -> Void)?
  private let a = UIButton(type: .system), b = UIButton(type: .system)
  override init(frame: CGRect) {
    super.init(frame: frame)
    for (btn, t, c) in [(a, "Request amendments", UIColor.systemOrange), (b, "Approve", UIColor.systemGreen)] {
      var cfg = UIButton.Configuration.filled(); cfg.cornerStyle = .capsule; cfg.baseBackgroundColor = c; cfg.baseForegroundColor = .white
      var s = AttributedString(t); s.font = .systemFont(ofSize: 16, weight: .semibold); cfg.attributedTitle = s
      cfg.titleLineBreakMode = .byTruncatingTail; btn.configuration = cfg; addSubview(btn)
    }
    a.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onAmend?() }, for: .touchUpInside)
    b.addAction(UIAction { [weak self] _ in self?.onApprove?() }, for: .touchUpInside)
  }
  required init?(coder: NSCoder) { fatalError() }
  func blockHeight(_ W: CGFloat) -> CGFloat { 80 }
  override func layoutSubviews() { super.layoutSubviews(); let W = bounds.width, w = (W - 32 - 10); a.frame = CGRect(x: 16, y: 16, width: w * 0.56, height: 52); b.frame = CGRect(x: 16 + w * 0.56 + 10, y: 16, width: w * 0.44, height: 52) }
}

// iPhone's own sheet: tick the files that need changes (each its own note), the rest are approved; a general note on
// top (optional — or the only note, for a single file). ✕ and the blue ↑ to send. "Yousef is notified on the task."
final class AmendSheetVC: UIViewController, UITextViewDelegate {
  var onSend: ((_ need: [String: String]?, _ note: String, _ done: @escaping (String?) -> Void) -> Void)?
  private let files: [[String: Any]], first: String, dark: Bool
  private var ticked: Set<String> = [], notes: [String: UITextView] = [:], wills: [String: UILabel] = [:], ticks: [String: UIButton] = [:]
  private let general = UITextView(), err = UILabel(), stack = UIStackView()
  private var sending = false
  init(files: [[String: Any]], first: String, dark: Bool) { self.files = files; self.first = first; self.dark = dark; super.init(nibName: nil, bundle: nil); overrideUserInterfaceStyle = dark ? .dark : .light }
  required init?(coder: NSCoder) { fatalError() }
  func inNav() -> UIViewController {
    let n = UINavigationController(rootViewController: self); n.overrideUserInterfaceStyle = overrideUserInterfaceStyle
    if let s = n.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
    n.isModalInPresentation = true
    return n
  }
  private var multi: Bool { files.count > 1 }
  private func box(_ v: UITextView, _ hint: String) -> UIView {
    v.font = .systemFont(ofSize: 16); v.backgroundColor = .clear; v.isScrollEnabled = false; v.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8); v.delegate = self
    let b = UIView(); b.backgroundColor = .secondarySystemGroupedBackground; b.layer.cornerRadius = 12; b.layer.cornerCurve = .continuous
    let ph = UILabel(); ph.text = hint; ph.font = .systemFont(ofSize: 16); ph.textColor = .tertiaryLabel; ph.tag = 77
    [v, ph].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; b.addSubview($0) }
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 4), v.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -4), v.topAnchor.constraint(equalTo: b.topAnchor), v.bottomAnchor.constraint(equalTo: b.bottomAnchor),
      v.heightAnchor.constraint(greaterThanOrEqualToConstant: 44), ph.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 17), ph.topAnchor.constraint(equalTo: b.topAnchor, constant: 11), ph.trailingAnchor.constraint(lessThanOrEqualTo: b.trailingAnchor, constant: -12)])
    return b
  }
  func textViewDidChange(_ v: UITextView) { v.superview?.viewWithTag(77)?.isHidden = !v.text.isEmpty; err.text = nil }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    title = "Request amendments"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close() })
    let send = UIBarButtonItem(image: UIImage(systemName: "arrow.up"), primaryAction: UIAction { [weak self] _ in self?.send() })
    send.style = .done
    send.tintColor = .systemBlue; send.accessibilityLabel = "Send back"
    navigationItem.rightBarButtonItem = send
    let scroll = UIScrollView(); scroll.keyboardDismissMode = .interactive; scroll.alwaysBounceVertical = true
    stack.axis = .vertical; stack.spacing = 10
    scroll.translatesAutoresizingMaskIntoConstraints = false; stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll); scroll.addSubview(stack)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -18), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24)])
    let hint = UILabel(); hint.font = .systemFont(ofSize: 13); hint.textColor = .secondaryLabel; hint.numberOfLines = 0; hint.textAlignment = .center
    hint.text = multi ? "Tick the files that need changes — the rest are approved" : "Tell \(first) what to change"
    stack.addArrangedSubview(hint)
    stack.addArrangedSubview(box(general, multi ? "General note (optional)" : "What needs changing?"))
    if multi {
      for f in files {
        let id = f["id"] as? String ?? ""
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 12; row.alignment = .top
        let tick = UIButton(type: .system); tick.setImage(UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)), for: .normal); tick.tintColor = .tertiaryLabel
        tick.addAction(UIAction { [weak self] _ in self?.toggle(id) }, for: .touchUpInside); tick.accessibilityLabel = "Needs changes: \(f["name"] as? String ?? "")"
        ticks[id] = tick
        let th = UIImageView(); th.contentMode = .scaleAspectFill; th.clipsToBounds = true; th.layer.cornerRadius = 10; th.backgroundColor = .tertiarySystemFill
        if let p = f["pic"] as? String { FeedLoader.shared.image(p) { [weak th] i in th?.image = i } }
        th.isUserInteractionEnabled = true; th.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(thumbTap(_:)))); th.accessibilityIdentifier = id
        let col = UIStackView(); col.axis = .vertical; col.spacing = 5
        let name = UILabel(); name.text = f["name"] as? String; name.font = .systemFont(ofSize: 15, weight: .semibold); name.lineBreakMode = .byTruncatingMiddle
        let will = UILabel(); will.text = "✓ Will be approved"; will.font = .systemFont(ofSize: 13); will.textColor = .systemGreen; wills[id] = will
        let n = UITextView(); let nb = box(n, "What needs changing?"); nb.isHidden = true; notes[id] = n
        [name, will, nb].forEach { col.addArrangedSubview($0) }
        [tick, th, col].forEach { row.addArrangedSubview($0) }
        tick.translatesAutoresizingMaskIntoConstraints = false; th.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([tick.widthAnchor.constraint(equalToConstant: 30), tick.heightAnchor.constraint(equalToConstant: 58), th.widthAnchor.constraint(equalToConstant: 58), th.heightAnchor.constraint(equalToConstant: 58)])
        stack.addArrangedSubview(row)
      }
    }
    let foot = UILabel(); foot.text = "\(first) is notified on the task — one comment\(multi ? ", grouped by file" : "")."; foot.font = .systemFont(ofSize: 13); foot.textColor = .secondaryLabel; foot.numberOfLines = 0
    err.font = .systemFont(ofSize: 14); err.textColor = .systemRed; err.numberOfLines = 0
    stack.addArrangedSubview(foot); stack.addArrangedSubview(err)
  }
  var onFile: ((String) -> Void)?
  @objc private func thumbTap(_ g: UITapGestureRecognizer) { if let id = g.view?.accessibilityIdentifier { onFile?(id) } }
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if !multi { general.becomeFirstResponder() } }
  private func toggle(_ id: String) {
    UISelectionFeedbackGenerator().selectionChanged(); err.text = nil
    let on = !ticked.contains(id)
    if on { ticked.insert(id) } else { ticked.remove(id) }
    ticks[id]?.setImage(UIImage(systemName: on ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)), for: .normal)
    ticks[id]?.tintColor = on ? .systemOrange : .tertiaryLabel
    UIView.animate(withDuration: 0.25) {
      self.wills[id]?.isHidden = on
      self.notes[id]?.superview?.isHidden = !on
      self.stack.layoutIfNeeded()
    }
    if on { notes[id]?.becomeFirstResponder() }
  }
  private var dirty: Bool { !general.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ticked.isEmpty }
  private func close() {
    guard dirty else { dismiss(animated: true); return }
    let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    a.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in self?.dismiss(animated: true) })
    a.addAction(UIAlertAction(title: "Keep editing", style: .cancel))
    a.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
    present(a, animated: true)
  }
  private func send() {
    guard !sending else { return }
    let g = general.text.trimmingCharacters(in: .whitespacesAndNewlines)
    var need: [String: String]? = nil
    if multi {
      if ticked.isEmpty { err.text = "Tick the files that need changes — or go back and Approve"; UINotificationFeedbackGenerator().notificationOccurred(.warning); return }
      var m: [String: String] = [:]
      for id in ticked { m[id] = (notes[id]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
      if g.isEmpty, let blank = m.first(where: { $0.value.isEmpty })?.key { err.text = "Say what needs changing"; notes[blank]?.becomeFirstResponder(); UINotificationFeedbackGenerator().notificationOccurred(.warning); return }
      need = m
    } else if g.isEmpty { err.text = "Say what needs changing"; general.becomeFirstResponder(); UINotificationFeedbackGenerator().notificationOccurred(.warning); return }
    sending = true; navigationItem.rightBarButtonItem?.isEnabled = false
    onSend?(need, g) { [weak self] e in
      guard let self = self else { return }
      self.sending = false; self.navigationItem.rightBarButtonItem?.isEnabled = true
      if let e = e { self.err.text = e; UINotificationFeedbackGenerator().notificationOccurred(.error) } else { UINotificationFeedbackGenerator().notificationOccurred(.success); self.dismiss(animated: true) }
    }
  }
}

// a swipe across the middle of a page (not from its edge, not while searching): left → the second list, right → the first
final class SegSwipe: NSObject, UIGestureRecognizerDelegate {
  private let act: (Int) -> Void
  private var done = false
  private static var kept: [ObjectIdentifier: SegSwipe] = [:]
  private init(_ act: @escaping (Int) -> Void) { self.act = act }
  static func attach(_ v: UIView, _ act: @escaping (Int) -> Void) {
    let s = SegSwipe(act)
    let g = UIPanGestureRecognizer(target: s, action: #selector(panned(_:))); g.delegate = s; g.cancelsTouchesInView = false
    v.addGestureRecognizer(g)
    kept[ObjectIdentifier(v)] = s
  }
  @objc private func panned(_ g: UIPanGestureRecognizer) {
    switch g.state {
    case .began: done = false
    case .changed:
      guard !done, let v = g.view else { return }
      let t = g.translation(in: v)
      if abs(t.x) > 60 && abs(t.x) > abs(t.y) * 1.6 { done = true; act(t.x < 0 ? -1 : 1) }
    default: done = false
    }
  }
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard let p = g as? UIPanGestureRecognizer, let v = g.view else { return false }
    if let h = v as? HomeView, h.searching { return false }
    if p.location(in: v).x < 28 { return false }   // (the edge: iPhone's swipe back)
    let vel = p.velocity(in: v); return abs(vel.x) > abs(vel.y) * 1.6
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}
