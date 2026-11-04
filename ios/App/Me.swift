import UIKit
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
  func blockHeight(_ W: CGFloat) -> CGFloat { first ? 24 : (label.text ?? "").isEmpty ? 20 : 44 }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = CGRect(x: 36, y: bounds.height - 25, width: bounds.width - 72, height: 18) }
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
  var pills: [(String, UIColor)] = []
  var person: (photo: String?, ini: String, rgb: UIColor)? = nil
  var warn = false                 // (the line under it in orange — "Hasn't signed in yet")
  var dim = false
  var tap: (() -> Void)? = nil
  var hold: (() -> Void)? = nil
  var flip: ((Bool) -> Void)? = nil
  var sig: String { "\(title)|\(sub)|\(value)|\(sym ?? "")|\(col?.description ?? "")|\(chevron)|\(toggle != nil)|\(danger)|\(pill ?? "")|\(badge ?? "")|\(pills.map { $0.0 }.joined(separator: ","))|\(person?.photo ?? "")|\(person?.ini ?? "")|\(warn)|\(dim)|\(tap != nil)|\(hold != nil)" }
}

final class SetRow: AssetTile {
  let icon = SettingsIcon(), sym = UIImageView(), pic = UIImageView(), name = UILabel(), sub = UILabel(), value = UILabel(), chev = UIImageView(), sw = UISwitch(), pill = UILabel(), badge = UILabel()
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
    [icon, pic, name, sub, value, chev, pill, badge].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
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
  private var rootKind: String { tab == "plans" ? "plans" : "me" }
  // (a question to the page, its answer back — Content plans' post, approve, send back)
  private func request(_ ev: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    let rid = UUID().uuidString
    var e = ev; e["rid"] = rid
    asks[rid] = done
    send(e)
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.asks.removeValue(forKey: rid)?(["ok": false, "error": "No answer — try again"]) }
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
  var shown: HomeView? {
    guard !hidden, let s = stack.last, !s.h.isHidden else { return nil }
    if leaving { return stack.count >= 2 ? stack[stack.count - 2].h : nil }
    return s.h
  }
  var isOpen: Bool { !stack.isEmpty && !hidden }
  var depth: Int { stack.count }
  var screens: [HomeView] { stack.map { $0.h } }
  var kind: String { stack.last?.kind ?? "" }

  private func send(_ ev: [String: Any]) { main.pageJS("window.__e11Me && window.__e11Me(\(jsonString(ev)))") }

  // ---------- from the page ----------
  func command(_ a: [String: Any]) {
    if let rid = a["rid"] as? String { asks.removeValue(forKey: rid)?(a); return }
    // (a Content plan opened on the page — an Inbox update, a notification: the app's own page for it)
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
    if let m = a["model"] as? [String: Any] { model = m }
    // (the other tab now — Me ↔ Content plans: its own first page)
    let want = (a["tab"] as? String) == "plans" ? "plans" : "me"
    if want != tab {
      if stack.contains(where: { $0.kind == "plans" }) { send(["ev": "pl", "on": false]) }
      stack.forEach { $0.h.removeFromSuperview() }; stack = []; tab = want
    }
    if stack.isEmpty {
      if rootKind == "plans" { plMonth = plMonth ?? ""; send(["ev": "pl", "on": true, "month": plMonth ?? ""]) }
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
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in guard let self = self, self.reveals == t else { return }; self.hide() }
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
    h.assets = kind == "me" ? "me" : "me." + kind
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
    main.view.insertSubview(h, belowSubview: main.tabBar)
    return Screen(h: h, kind: kind, id: id)
  }
  private func open(_ kind: String, _ id: String? = nil) {
    guard !leaving else { return }
    ProfileAskCard.current?.go()   // (another page: the birthday / city card slips away)
    if kind == "team" { teamTab = 0; teamQ = ""; send(["ev": "team", "on": true]) }
    if kind == "about" { send(["ev": "about"]) }
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
  func refresh() { if isOpen { main.pageJS("window.__e11MeResend && window.__e11MeResend()"); if stack.contains(where: { $0.kind == "about" }) { send(["ev": "about"]) } } }

  // ---------- what's on each ----------
  func relight(_ l: Bool) { guard l != light else { return }; light = l; stack.forEach { draw($0) } }
  private func redrawRoot() { if let s = stack.first(where: { $0.kind == "me" }) { draw(s) } }
  private func draw(_ s: Screen) {
    var mm: [String: Any] = ["show": true, "me": me ?? "", "look": ["light": light]]
    if let l = main.homeLook as? [String: Any], (l["light"] as? Bool) == light { mm["look"] = l }
    if s.kind == "me" { mm["title"] = "Me"; mm["date"] = "E11 Console App" }   // (the line under the big title, as the other tabs have — Haris 2026-11-03)
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
        return SetItem(key: k, title: w["t"] as? String ?? "", sub: w["s"] as? String ?? "", sym: w["sym"] as? String, col: NativeSheetVC.color(w["col"]),
                       tap: { [weak self] in guard let self = self else { return }; if k == "team" || k == "trash" || k == "plans" { self.open(k) } else { if k == "clients" { self.coverWait = Date() }; self.send(["ev": "nav", "to": k]) } })
      }
      if !work.isEmpty { out.append(head(h, "work", "Work")); out.append(group(h, "work", work)) }
      var phone: [SetItem] = [SetItem(key: "shortcuts", title: "Shortcuts", sub: "Quicker ways to do things", sym: "command", col: .systemBlue, badge: "New", tap: { [weak self] in self?.open("shortcuts") })]
      if let p = model["push"] as? [String: Any] {
        phone.append(SetItem(key: "push", title: "Notifications", sub: p["sub"] as? String ?? "", value: (p["busy"] as? Bool) == true ? "…" : p["label"] as? String ?? "", sym: "bell.badge.fill", col: .systemRed, tap: { [weak self] in self?.send(["ev": "push"]) }))
      }
      if let lk = model["lock"] as? [String: Any] {
        let kindW = lk["kind"] as? String ?? "Face ID"
        phone.append(SetItem(key: "lock", title: "\(kindW) lock", sub: "Asks for your face when E11 Console opens", sym: kindW == "Touch ID" ? "touchid" : "faceid", col: .systemGreen, toggle: (lk["on"] as? Bool) == true, flip: { [weak self, weak h] _ in self?.send(["ev": "lock"]); if let h = h { self?.settle(h) } }))
      }
      if let d = model["digest"] as? [String: Any] {
        phone.append(SetItem(key: "digest", title: "Morning summary", sub: "10:30 am, Monday to Friday", sym: "sun.max.fill", col: .systemYellow, toggle: (d["on"] as? Bool) == true, flip: { [weak self, weak h] _ in self?.send(["ev": "digest"]); if let h = h { self?.settle(h) } }))
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
          test.append(SetItem(key: "viewAs", title: "View as…", sub: (t["viewing"] as? String).map { "Viewing as \($0)" } ?? "Test site only — use the app as a team member", sym: "person.2.fill", col: .systemTeal, tap: { [weak self] in self?.send(["ev": "viewAs"]) }))
          if t["viewing"] is String { test.append(SetItem(key: "backToMe", title: "Back to me", sym: "arrow.uturn.backward", col: .systemTeal, chevron: false, tap: { [weak self] in self?.send(["ev": "backToMe"]) })) }
        }
        if (t["sample"] as? Bool) == true { test.append(SetItem(key: "sample", title: "Start fresh with sample data", sub: "Test site only: wipes everything except you", chevron: false, danger: true, tap: { [weak self] in self?.send(["ev": "sample"]) })) }
        if !test.isEmpty { out.append(head(h, "test", "Test site")); out.append(group(h, "test", test)) }
      }
      out.append(head(h, "out", ""))
      out.append(group(h, "out", [SetItem(key: "signOut", title: "Sign out", chevron: false, danger: true, tap: { [weak self] in self?.send(["ev": "signOut"]) })]))
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
      tb.onPick = { [weak self] m in self?.send(["ev": "theme", "mode": m]) }
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
                     .button("Update now", true, can, { [weak self] in self?.send(["ev": "update"]) }),
                     .note(tonight + "A copy of the data is made first; it takes about 10 seconds.")]
          } else {
            parts = [.status("✓ You’re up to date", .systemGreen), .kv("Running", running), .kv("Last checked", checked),
                     .button("Check again", false, true, { [weak self] in self?.send(["ev": "about", "fresh": true]) })]
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
        parts.append(.button("Check again", false, true, { [weak self] in self?.send(["ev": "videoCheck"]) }))
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
      let held: (() -> Void)? = hold ? { [weak self] in self?.send(["ev": "member", "id": id]) } : nil
      return SetItem(key: id, title: title, sub: sub, pills: pills, person: pic, warn: pending, dim: past, tap: { [weak self] in self?.open("member", id) }, hold: held)
    }
  }
  private func teamBlocks(_ h: HomeView, _ out: inout [UIView]) {
    let t = team
    let admin = (t["admin"] as? Bool) == true
    h.drawAssetsBar(name: "Team members", sub: t.isEmpty ? "" : "\(t["active"] as? Int ?? 0) active · \(t["pastN"] as? Int ?? 0) past", logo: nil, rgb: nil, ini: nil, showLogo: false)
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
    if admin { h.setFab("Add member", "plus", { [weak self] in self?.send(["ev": "addMember"]) }) }
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
      self.main.topMost().present(AttachSheetVC(light: self.light, title: "Your photo") { [weak self] src in self?.send(["ev": "pfPhoto", "source": src]) }, animated: true)
    }
    top.onRemove = { [weak self] in self?.send(["ev": "pfPhotoOff"]) }
    out.append(top)
    let v: (String) -> String = { k in p[k] as? String ?? "" }
    let none = "Not set"
    var mail = SetItem(key: "email", title: "Email", value: v("email"), chevron: false)
    mail.tap = { [weak h] in UIPasteboard.general.string = v("email"); h?.toast(["t": "Email copied"]) }
    out.append(head(h, "you", "About you"))
    out.append(group(h, "you", [
      SetItem(key: "name", title: "Name", value: v("name").isEmpty ? none : v("name"), tap: { [weak self] in self?.send(["ev": "pfName"]) }),
      mail,
      SetItem(key: "country", title: "Country", value: v("country").isEmpty ? none : v("country"), tap: { [weak self] in self?.send(["ev": "pfCountry"]) }),
      SetItem(key: "city", title: "City", value: v("city").isEmpty ? none : v("city"), tap: { [weak self] in self?.send(["ev": "pfCity"]) }),
      SetItem(key: "bday", title: "Birthday", value: v("bday").isEmpty ? "Optional" : v("bday"), tap: { [weak self] in self?.send(["ev": "pfBday"]) }),
    ]))
    out.append(foot(h, "you", "Your email can’t be changed here. People see your role and city when they look at your name. Your birthday stays private: on the day, the team is told it’s your birthday."))
    let pills: [(String, UIColor)] = ((p["pills"] as? [[String: Any]]) ?? []).map { ($0["t"] as? String ?? "", NativeSheetVC.color($0["c"]) ?? .systemGray) }
    out.append(head(h, "role", "Role"))
    out.append(group(h, "role", [SetItem(key: "role", title: "Your role", chevron: false, pills: pills)]))
    out.append(foot(h, "role", "Only Admins change roles and rights, in Team members."))
    out.append(head(h, "nt", "Notifications"))
    out.append(group(h, "nt", [
      SetItem(key: "sound", title: "Sound", sub: "Play a sound with new notifications", sym: "speaker.wave.2.fill", col: .systemPink, toggle: (p["sound"] as? Bool) != false, flip: { [weak self] _ in self?.send(["ev": "pfSound"]) }),
      SetItem(key: "test", title: "Send a test notification", sub: "See and hear what one looks like", sym: "bell.badge.fill", col: .systemRed, tap: { [weak self] in self?.send(["ev": "pfTest"]) }),
    ]))
    let kinds: ([[String: Any]], String) -> [SetItem] = { list, tag in list.map { x -> SetItem in
      let k = x["k"] as? String ?? ""
      return SetItem(key: tag + k, title: x["t"] as? String ?? "", sub: x["s"] as? String ?? "", toggle: (x["on"] as? Bool) == true, flip: { [weak self] _ in self?.send(["ev": "pfNotif", "k": k]) })
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
    h.assetsMenu = (t["empty"] as? Bool) == true ? { [weak self] in [CornerMenuItem(title: "Empty Trash", symbol: "trash", destructive: true, run: { self?.send(["ev": "trEmpty"]) })] } : { [] }
    if t.isEmpty { let w = part(h, "wait") { AssetsNote() }; w.label.text = "Loading…"; out.append(w); return }
    let find = part(h, "find") { AssetsFind() }
    find.field.placeholder = "Search the Trash"
    if !find.field.isFirstResponder, (find.field.text ?? "") != (t["q"] as? String ?? "") { find.field.text = t["q"] as? String }
    find.onChange = { [weak self] q in self?.send(["ev": "trQ", "q": q]) }
    let cats = part(h, "cats") { CatsBlock(items: MeCtl.trashCats.map { c in MailCats.Item(key: c.0, sym: c.1, name: c.2, fill: c.0 == "all" ? MailCats.neutral : c.0 == "mine" ? MailCats.purple : MailCats.blue) }) }
    cats.cats.light = h.look.light
    cats.choose((MeCtl.trashCats.firstIndex { $0.0 == (t["cat"] as? String ?? "all") }) ?? 0)
    cats.onPick = { [weak self] i in self?.send(["ev": "trCat", "k": MeCtl.trashCats[i].0]) }
    let stack = part(h, "pin") { PinStack() }
    stack.set([find, cats])
    if h.pinHead !== stack { h.pinHead = stack }
    let groups = (t["groups"] as? [[String: Any]]) ?? []
    for g in groups {
      let items = (g["items"] as? [[String: Any]]) ?? []
      let k = g["name"] as? String ?? ""
      out.append(head(h, "tr." + k, "\(k) · \(items.count)"))
      let tg = part(h, "trg." + k) { TrashGroup() }
      tg.onEvent = { [weak self] ev in self?.send(ev) }
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
    h.drawAssetsBar(name: "Content plans", sub: m["label"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
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
        manage.append(SetItem(key: "manage", title: "Role, rights and access", sub: "Change role, Super Admin rights, Finance access…", sym: "slider.horizontal.3", col: .systemBlue, tap: { [weak self] in self?.send(["ev": "member", "id": id]) }))
        if let cd = p["cd"] as? [String: Any] {
          manage.append(SetItem(key: "cd", title: "Creative Director", sub: cd["label"] as? String ?? "", sym: "star.fill", col: .systemPurple, toggle: (cd["on"] as? Bool) == true, flip: { [weak self, weak h] _ in self?.send(["ev": "cd", "id": id]); if let h = h { self?.settle(h) } }))
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
