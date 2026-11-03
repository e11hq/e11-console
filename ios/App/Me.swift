import UIKit

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
  func blockHeight(_ W: CGFloat) -> CGFloat { (label.text ?? "").isEmpty ? 0 : ceil(label.sizeThatFits(CGSize(width: W - 72, height: 600)).height) + 14 }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = CGRect(x: 36, y: 7, width: bounds.width - 72, height: max(0, bounds.height - 14)) }
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
  let icon = UIView(), sym = UIImageView(), pic = UIImageView(), name = UILabel(), sub = UILabel(), value = UILabel(), chev = UIImageView(), sw = UISwitch(), pill = UILabel(), badge = UILabel()
  private var pillViews: [UILabel] = []
  var item: SetItem!
  private var photoPath: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    icon.layer.cornerRadius = 7; icon.layer.cornerCurve = .continuous
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
    icon.isHidden = it.sym == nil; icon.backgroundColor = it.col ?? .systemGray
    sym.image = it.sym.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)) }
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

// ---------- the screens ----------

// (a tap anywhere but in a text box puts the keyboard away)
final class KeyboardAway: NSObject, UIGestureRecognizerDelegate {
  static let shared = KeyboardAway()
  @objc func tapped(_ g: UITapGestureRecognizer) { g.view?.endEditing(true) }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
    var v = t.view
    while let x = v { if x is UITextField || x is UITextView { return false }; v = x.superview }
    return true
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}

final class MeCtl {
  private unowned let main: Main
  init(_ m: Main) { main = m }
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
    if stack.isEmpty { push(screen("me", nil), animated: false) }
    reveal()
    stack.forEach { draw($0) }
    main.updateCorner()
  }
  // out of sight, kept as it is (Me comes back where it was, as iPhone's own tabs)
  func hide() {
    guard !stack.isEmpty, !hidden else { return }
    hidden = true; borrowTimer?.invalidate()
    stack.forEach { $0.h.endEditing(true); $0.h.isHidden = true; $0.h.transform = .identity }
    main.edgePanOn(); main.updateCorner()
  }
  func reveal() {
    guard let s = stack.last else { return }
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
    guard let s = stack.last, main.selectedTabKey == "me" else { return nil }
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
    h.assetsBack = kind != "me"
    h.present = { [weak self] vc in self?.main.topMost().present(vc, animated: true) }
    h.onEvent = { [weak self, weak h] ev in guard let self = self, let h = h else { return }; self.event(h, ev) }
    h.onAssetsDraw = { [weak self] h, _ in self?.blocks(h) }
    h.assetsMenu = { [] }
    h.cornerShared = true
    h.onCorner = { [weak self] in self?.main.updateCorner() }
    // (a tap anywhere puts the keyboard away — Team members' search; taps still reach what's under the finger)
    let tap = UITapGestureRecognizer(target: KeyboardAway.shared, action: #selector(KeyboardAway.tapped(_:))); tap.cancelsTouchesInView = false; tap.delegate = KeyboardAway.shared
    h.addGestureRecognizer(tap)
    main.view.insertSubview(h, belowSubview: main.tabBar)
    return Screen(h: h, kind: kind, id: id)
  }
  private func open(_ kind: String, _ id: String? = nil) {
    guard !leaving else { return }
    if kind == "team" { teamTab = 0; teamQ = ""; send(["ev": "team", "on": true]) }
    if kind == "about" { send(["ev": "about"]) }
    push(screen(kind, id), animated: true)
  }
  private func push(_ s: Screen, animated: Bool) {
    let W = main.view.bounds.width
    let u = stack.last?.h
    stack.append(s)
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
    return ["open": isOpen, "screens": stack.count, "kind": kind, "parts": parts, "shown": shown != nil, "corner": corner, "people": people, "rows": rows, "card": card]
  }
  func refresh() { if isOpen { main.pageJS("window.__e11MeResend && window.__e11MeResend()"); if stack.contains(where: { $0.kind == "about" }) { send(["ev": "about"]) } } }

  // ---------- what's on each ----------
  private func draw(_ s: Screen) {
    var mm: [String: Any] = ["show": true, "me": me ?? "", "look": ["light": light]]
    if let l = main.homeLook as? [String: Any], (l["light"] as? Bool) == light { mm["look"] = l }
    if s.kind == "me" { mm["title"] = "Me"; mm["date"] = "" }
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
        card.onTap = { [weak self] in self?.send(["ev": "profile"]) }
        out.append(card)
      } else { let n = part(h, "wait") { AssetsNote() }; n.label.text = "Loading…"; out.append(n) }
      let work = ((model["work"] as? [[String: Any]]) ?? []).map { w -> SetItem in
        let k = w["k"] as? String ?? ""
        return SetItem(key: k, title: w["t"] as? String ?? "", sub: w["s"] as? String ?? "", sym: w["sym"] as? String, col: NativeSheetVC.color(w["col"]),
                       tap: { [weak self] in guard let self = self else { return }; if k == "team" { self.open("team") } else { self.send(["ev": "nav", "to": k]) } })
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
      if let v = model["version"] as? String, !v.isEmpty { out.append(foot(h, "ver", v, centered: true)) }
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
    case "team":
      teamBlocks(h, &out)
    case "member":
      memberBlocks(h, s.id ?? "", &out)
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
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h else { return }; self.teamTab = i; self.blocks(h); h.relayout() }
    out.append(seg)
    let find = part(h, "find") { AssetsFind() }
    find.field.placeholder = "Search people"
    find.onChange = { [weak self, weak h] q in guard let self = self, let h = h else { return }; self.teamQ = q; self.blocks(h); h.setNeedsLayout() }
    out.append(find)
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
  private func person(_ id: String) -> [String: Any]? {
    let t = team
    let all = (((t["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["people"] as? [[String: Any]]) ?? [] }) + ((t["past"] as? [[String: Any]]) ?? [])
    return all.first { ($0["id"] as? String) == id }
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
    if kind == "form" { let vc = MeFormVC(a, dark: dark, done: done); let nav = UINavigationController(rootViewController: vc); nav.overrideUserInterfaceStyle = dark ? .dark : .light; main.topMost().present(nav, animated: true); return }
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
      if let pop = ac.popoverPresentationController { pop.sourceView = main.view; pop.sourceRect = CGRect(x: main.view.bounds.midX, y: main.view.bounds.midY, width: 1, height: 1) }
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
