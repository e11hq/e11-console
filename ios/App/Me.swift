import UIKit
import SafariServices
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
  var bold = false                 // (a title in semibold, its lines under it in full — a skeleton's status cell)
  var tap: (() -> Void)? = nil
  var hold: (() -> Void)? = nil
  var menu: (() -> UIMenu?)? = nil   // (touch and hold: Apple's own menu straight away — a team member, Haris 2026-11-10)
  var popup: (() -> UIMenu)? = nil   // (the value as Apple's pull-down menu — a member's Role and Finance Access)
  var flip: ((Bool) -> Void)? = nil
  // (Apple's own swipes on the row — a claim's HR Approved / Paid On…, an office expense's or a Trash item's Delete:
  //  Haris 2026-11-11, "A–I go for it")
  var lead: [MeSwipe] = []
  var trail: [MeSwipe] = []
  var line3: (String, UIColor)? = nil   // (a third line in its own colour — a subscription's invoices, days left in the Trash)
  var pic: String? = nil                // (a file's own picture as the row's picture — the Trash's G1)
  var sig: String { "\(sigBase)|\(lead.map { $0.title }.joined(separator: ","))|\(trail.map { $0.title }.joined(separator: ","))|\(line3?.0 ?? "")|\(line3?.1.description ?? "")|\(pic ?? "")" }
  private var sigBase: String { "\(title)|\(sub)|\(value)|\(sym ?? "")|\(col?.description ?? "")|\(chevron)|\(toggle != nil)|\(danger)|\(pill ?? "")|\(badge ?? "")|\(count)|\(pills.map { $0.0 }.joined(separator: ","))|\(person?.photo ?? "")|\(person?.ini ?? "")|\(warn)|\(dim)|\(bold)|\(tap != nil)|\(hold != nil)|\(menu != nil)|\(popup != nil)" }
}

// one of Apple's swipe buttons on a settings row
struct MeSwipe {
  var title: String
  var sym: String
  var col: UIColor
  var destructive = false
  var run: (@escaping (Bool) -> Void) -> Void
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
  // (what it shows — Me in Apple's list draws these as iPhone Settings' own cells: HomeView.applyMeList)
  private(set) var items: [SetItem] = []
  func set(_ items: [SetItem], look L: HomeLook) {
    self.items = items
    box.backgroundColor = L.card
    var keep = made; made = [:]
    var fresh: [SetRow] = []
    // (each key once — a second with the same key gets its own)
    var seen = Set<String>()
    let items = items.enumerated().map { i, x -> SetItem in var y = x; if !seen.insert(y.key).inserted { y.key += "#\(i)" }; return y }
    UIView.performWithoutAnimation {
      rows = items.map { it in
        let sig = it.sig + "|\(L.key)"
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
  private func paintPic() { pic.image = MePhoto.shared.picture(62) ?? roundPic(nil, initials: ini, color: rgb, size: 62); onPhoto?() }
  // (what it shows — Me in Apple's list draws it as an Apple cell, as Settings' account row: HomeView.applyMeList)
  var onPhoto: (() -> Void)?
  var info: (name: String, role: String, email: String) { (name.text ?? "", role.text ?? "", mail.text ?? "") }
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
    guard s + "|\(L.key)" != sig else { return }
    sig = s + "|\(L.key)"
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
    let cardC = L.card
    followLook("fade") { [weak self] tc in let c = cardC.resolvedColor(with: tc); self?.fade.colors = [c.withAlphaComponent(0).cgColor, c.cgColor] }
    let s = "\(name)|\(date)|\(notes)|\(L.key)"
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

// My profile's top, as iPhone Settings' account page (Haris 2026-11-11, the mock-up's I1): your photo (or initials), Edit
// under it — Apple's own menu: Take Photo · Choose Photo · Remove Photo — then your name and your role
final class ProfileHead: UIView, HomeBlock {
  private let pic = UIImageView(), edit = UIButton(configuration: .plain()), name = UILabel(), role = UILabel()
  private var photoPath: String?, ini = "", hasPhoto = false
  // (uploading: the photo dimmed with iPhone's spinner on it, until the new photo has come — Haris 2026-11-03)
  private let dim = UIView(), spin = UIActivityIndicatorView(style: .medium)
  private var busy = false, waitingNew = false
  var onPick: ((String) -> Void)?, onRemove: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.layer.cornerRadius = 48; pic.clipsToBounds = true
    var bc = UIButton.Configuration.plain(); bc.title = "Edit"; bc.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
    bc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 15, weight: .medium); return a }
    edit.configuration = bc; edit.showsMenuAsPrimaryAction = true
    name.font = .systemFont(ofSize: 24, weight: .bold); name.textAlignment = .center; name.adjustsFontSizeToFitWidth = true; name.minimumScaleFactor = 0.7
    role.font = .systemFont(ofSize: 15); role.textColor = .secondaryLabel; role.textAlignment = .center
    [pic, edit, name, role].forEach { addSubview($0) }
    dim.backgroundColor = UIColor.black.withAlphaComponent(0.4); dim.layer.cornerRadius = 48; dim.alpha = 0; dim.isUserInteractionEnabled = false
    spin.color = .white; spin.hidesWhenStopped = true
    addSubview(dim); addSubview(spin)
    paintMenu()
  }
  required init?(coder: NSCoder) { fatalError() }
  private func paintMenu() {
    var a: [UIMenuElement] = [UIAction(title: "Take Photo", image: UIImage(systemName: "camera")) { [weak self] _ in self?.onPick?("camera") },
                              UIAction(title: "Choose Photo", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in self?.onPick?("photos") }]
    if hasPhoto { a.append(UIMenu(options: .displayInline, children: [UIAction(title: "Remove Photo", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.onRemove?() }])) }
    edit.menu = UIMenu(children: a)
  }
  private func setBusy(_ on: Bool) {
    if on { spin.startAnimating() } else { spin.stopAnimating() }
    UIView.animate(withDuration: 0.2) { self.dim.alpha = on ? 1 : 0 }
    edit.isEnabled = !on
  }
  func set(_ p: [String: Any], look L: HomeLook) {
    let had = hasPhoto
    hasPhoto = (p["hasPhoto"] as? Bool) == true
    if had != hasPhoto { paintMenu() }
    let nowBusy = (p["photoBusy"] as? Bool) == true
    if nowBusy && !busy { busy = true; waitingNew = true; setBusy(true) }
    else if !nowBusy && busy { busy = false; if (p["photo"] as? String) == photoPath || p["photo"] == nil { waitingNew = false; setBusy(false) } }
    let nm = p["name"] as? String ?? ""
    let roles = ((p["pills"] as? [[String: Any]]) ?? []).compactMap { $0["t"] as? String }.joined(separator: " ")
    let line = [roles, p["city"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    if name.text != nm { name.text = nm }
    if role.text != line { role.text = line }
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
  func blockHeight(_ W: CGFloat) -> CGFloat { 8 + 96 + 4 + 32 + 30 + 22 + 8 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    pic.frame = CGRect(x: (W - 96) / 2, y: 8, width: 96, height: 96)
    dim.frame = pic.frame; spin.center = CGPoint(x: pic.frame.midX, y: pic.frame.midY)
    let ew = ceil(edit.sizeThatFits(CGSize(width: 200, height: 32)).width)
    edit.frame = CGRect(x: (W - ew) / 2, y: 108, width: ew, height: 32)
    name.frame = CGRect(x: 20, y: 140, width: W - 40, height: 30)
    role.frame = CGRect(x: 20, y: 170, width: W - 40, height: 22)
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
    frame = p.bounds; p.bringSubviewToFront(self); isHidden = false; KeyboardShield.current = self
  }
  @objc private func down() { isHidden = true; if KeyboardShield.current === self { KeyboardShield.current = nil } }
  // (the shield that's up now — a list's KeyTap only puts the keyboard down while there is one)
  static weak var current: KeyboardShield?
  override func hitTest(_ pt: CGPoint, with e: UIEvent?) -> UIView? {
    guard !isHidden, let p = page, !p.isHidden else { return nil }
    guard let f = typing(p) else { isHidden = true; return nil }
    // (🔍's results: a tap opens what's tapped at once, as iPhone's own search — Haris 2026-11-04)
    if let h = p as? HomeView, h.searching { return nil }
    // (the box being typed in — and its clear button — still works)
    if f.convert(f.bounds, to: self).insetBy(dx: -6, dy: -6).contains(pt) { return nil }
    // (the comments and replies list puts the keyboard down itself on a tap, and still scrolls — the cover took a scroll
    //  as a tap there: Haris 2026-11-08)
    isHidden = true; let under = p.hitTest(convert(pt, to: p), with: e); isHidden = false
    var v = under; while let x = v { if x is CommentsFeed { return nil }; v = x.superview }
    // (a list under the finger, everywhere — Haris 2026-11-08: the page still scrolls while typing, dragging down takes
    //  the keyboard with the finger, and a tap only puts it down (its KeyTap). A button or switch under the finger: the
    //  cover takes it, so it only puts the keyboard down)
    v = under
    while let x = v {
      if x is UIControl && !(x is UITextField) { return self }
      if let sv = x as? UIScrollView, !(sv is UITextView) { KeyTap.add(to: sv); return nil }
      v = x.superview
    }
    return self
  }
  override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { if let w = page?.window { w.endEditing(true) } else { page?.endEditing(true) }; isHidden = true }
}

// a tap on a list while the keyboard is up (KeyboardShield): it only puts the keyboard down — the list's own taps (a card,
// a row) wait for it, and Apple's tap recognizer never takes a scroll (Haris 2026-11-08)
final class KeyTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
  static func add(to sv: UIScrollView) {
    if sv.keyboardDismissMode == .none { sv.keyboardDismissMode = .interactive }
    guard !(sv.gestureRecognizers ?? []).contains(where: { $0 is KeyTap }) else { return }
    let t = KeyTap(target: nil, action: nil); t.addTarget(t, action: #selector(fire))
    t.cancelsTouchesInView = true; t.delegate = t
    sv.addGestureRecognizer(t)
  }
  @objc private func fire() { view?.window?.endEditing(true) }
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { KeyboardShield.current?.isHidden == false }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    KeyboardShield.current?.isHidden == false && other is UITapGestureRecognizer && !(other is KeyTap)
  }
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
  private var clSeg = 0, exSeg = 0, rvSeg = 0, rvFocusN = 0, rvQ = ""
  private var clFocus: String?   // (a claim opened from the Inbox or a notification: shown and pulsing on the Claims tab)
  func focusClaim(_ id: String?) {
    guard let id = id, !id.isEmpty else { return }
    clFocus = id
    if let s = stack.first, s.kind == "claims" { if stack.count > 1 { backToRoot() }; draw(s) }
  }
  // ---------- Part B step 2: the pages' contents from the app's own copy (web/appme-*.js), the page's only where the copy
  // can't say (the device's own state: notifications, Face ID, theme, the sync line…) — each group on its own server
  // switch (kv app-me-<group>); until the copy is this person's, the page's as before ----------
  private var pageModel: [String: Any] = [:]
  var hasModel: Bool { !pageModel.isEmpty }   // (Me given its rows yet — drawBeforeShow)
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
    // (the month picked in ••• — Claims and Office expenses, the last 12: Haris 2026-11-11 B1; a claim open: its page, E1)
    if tab == "fin-reimb" || has("claims") || kinds.contains("claim"), let x = AppData.shared.meModel("claims", "claims", [clMonth ?? ""]) { m["claims"] = x }
    if let s = stack.last(where: { $0.kind == "claim" }), let id = s.id, let x = AppData.shared.meModel("claims", "claim", [id]) { m["claim"] = x }
    if tab == "fin-expenses" || has("expenses"), let x = AppData.shared.meModel("expenses", "expenses", [exMonth ?? ""]) { m["expenses"] = x }
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
  private static let serverActs: Set<String> = ["rvApprove", "rvAmend", "clApprove", "clPaid", "clAdd", "clPerson", "exAdd", "exEnd", "exInv", "exDel", "plApprove", "plBack", "plReview", "plTrash", "trRestore"]
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
    // (no website: the searches answered from the app's own copy — Overview's files, Content plans; they waited 15 s for a
    //  page that isn't there: Haris 2026-11-06)
    if let r = ownAnswer(ev) { done(r); return }
    let rid = UUID().uuidString
    var e = ev; e["rid"] = rid
    asks[rid] = done
    send(e)
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.asks.removeValue(forKey: rid)?(["ok": false, "error": "No answer — try again"]) }
  }
  private func ownAnswer(_ ev: [String: Any]) -> [String: Any]? {
    let q = (ev["q"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    switch ev["ev"] as? String ?? "" {
    case "plFind": return AppData.shared.meModel("plans", "plansFind", [q, ev["month"] as? String ?? ""])
    // (a plan's post, from the app's own copy — without the website nothing answered and it never opened: Haris 2026-11-08)
    case "plPost":
      guard AppData.shared.tabsOn else { return nil }
      if let p = AppData.shared.meModel("plans", "plansPost", [ev["plan"] as? String ?? "", ev["post"] as? String ?? ""]) { return ["ok": true, "post": p] }
      return ["ok": false, "error": "This post is no longer here"]
    case "ovFind":
      guard let all = (AppData.shared.meModel("assets", "assets", [NSNull()])?["files"] as? [[String: Any]]) else { return nil }
      let fd = Find.filter(all, q) { "\($0["name"] ?? "") \($0["where"] ?? "")" }
      let found = fd.items.prefix(60).map { f -> [String: Any] in
        ["id": f["id"] ?? "", "name": f["name"] ?? "", "path": f["file"] ?? "", "where": f["where"] ?? "", "pic": f["thumbUrl"] ?? NSNull(), "ext": ((f["ext"] as? String) ?? "file").uppercased().prefix(4).description]
      }
      return ["ok": true, "q": q, "found": Array(found), "loose": fd.loose, "marks": fd.marks]
    default: return nil
    }
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
    let vc = NativeSheetVC(a, pick: multi ? pickOne : nil) { i, _ in if !multi { pickOne(i) } }
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
    // (iPhone's own small pop-up with the name in it, not a sheet sliding up — Haris 2026-11-06)
    func once(_ v: String, _ err: String) {
      let a = UIAlertController(title: "Full name", message: err.isEmpty ? nil : err, preferredStyle: .alert)
      a.addTextField { t in t.text = v; t.placeholder = "Your full name"; t.autocapitalizationType = .words; t.textContentType = .name; t.clearButtonMode = .whileEditing; t.returnKeyType = .done }
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      let save = UIAlertAction(title: "Save", style: .default) { [weak self, weak a] _ in
        let n = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { once(n, "Please enter your name") }; return }
        if n != cur { self?.pfSet("name", ["value": n], page: ["ev": "pfName"]) }
      }
      a.addAction(save); a.preferredAction = save
      main.topMost().present(a, animated: true)
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
    let vc = NativeSheetVC(a) { [weak self] i, typed in
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
    main.topMost().present(DateSheetVC(["value": md.isEmpty ? "" : "\(year)-\(md)", "min": "", "max": "", "clearable": !md.isEmpty, "md": true]) { [weak self] r in
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
  // a Trash item (the mock-up "Remaining pages — fully Apple", Haris 2026-11-11 · G1 · H1): a task opens its own task page,
  // view only, Restore on Apple's toolbar; a file or folder its preview; touch and hold: Apple's menu — Open (View Only) or
  // Preview, Restore, Delete Forever (Super Admins). From the copy (web/appme-people.js trashItem).
  private func trashTap(_ id: String) {
    guard let it = brain("trash", "trashItem", [id]) else { return }
    if (it["type"] as? String) == "task", let tid = it["taskId"] as? String { main.openTaskPage(tid, tab: "details", focus: "", trash: id); return }
    let files = (it["files"] as? [[String: Any]]) ?? []
    if !files.isEmpty { main.openFiles(files.map { ["id": $0["id"] ?? "", "path": $0["path"] ?? "", "name": $0["name"] ?? "File", "size": $0["size"] ?? 0] }, at: 0) }
  }
  private func trashMenu(_ h: HomeView?, _ id: String) -> UIMenu? {
    guard let it = brain("trash", "trashItem", [id]) else { return nil }
    let task = (it["type"] as? String) == "task", files = (it["files"] as? [[String: Any]]) ?? []
    var a: [UIMenuElement] = []
    if task { a.append(UIAction(title: "Open (View Only)", image: UIImage(systemName: "eye")) { [weak self] _ in self?.trashTap(id) }) }
    else if !files.isEmpty { a.append(UIAction(title: files.count == 1 ? "Preview" : "Preview Files", image: UIImage(systemName: "eye")) { [weak self] _ in self?.trashTap(id) }) }
    if (it["restore"] as? Bool) == true { a.append(UIAction(title: "Restore", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self, weak h] _ in self?.trRestore(h, id) }) }
    if (it["forever"] as? Bool) == true { a.append(UIMenu(options: .displayInline, children: [UIAction(title: "Delete Forever", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.trForever(id) }])) }
    return a.isEmpty ? nil : UIMenu(children: a)
  }
  private func trRestore(_ h: HomeView?, _ id: String, done: ((Bool) -> Void)? = nil) {
    request(["ev": "trRestore", "id": id]) { [weak self] r in
      let ok = (r["ok"] as? Bool) == true
      if ok { UINotificationFeedbackGenerator().notificationOccurred(.success) }
      (h ?? self?.top)?.toast(["t": ok ? (r["toast"] as? String ?? "Restored") : (r["error"] as? String ?? "That didn’t work — try again")])
      done?(ok)
    }
  }
  // (a trashed task's own page — its Restore and Delete Forever: TaskVC, when the task page shows a task from the Trash)
  func trashActs(_ id: String) -> (restore: Bool, forever: Bool) {
    guard let it = brain("trash", "trashItem", [id]) else { return (false, false) }
    return ((it["restore"] as? Bool) == true, (it["forever"] as? Bool) == true)
  }
  func trashRestore(_ id: String, _ done: @escaping (Bool) -> Void) { trRestore(nil, id, done: done) }
  func trashForever(_ id: String) { trForever(id) }
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
  // A team member's actions, from the shared brain (appme-people.js memberMenu — every rule of who may change what: the
  // owner's account locked, your own row only your Finance access, the last Super Admin), as Apple's own menus — the
  // approved mock-up "Team members — fully Apple" (Haris 2026-11-10): Social Manager one of the roles, as the website shows
  // it (underneath: a Social person picked as Social Manager); Make Creative Director in it too (F1)
  private struct MemberParts {
    var locked: String?, roles: [UIMenuElement] = [], roleNow = "", fin: [UIMenuElement] = [], finNow = ""
    var admin: (on: Bool, run: () -> Void)?, clients: (() -> Void)?, restore: (() -> Void)?, remove: (() -> Void)?
  }
  private func memberParts(_ id: String) -> MemberParts? {
    guard let m = brain("team", "memberMenu", [id, envNow]), let secs = (m["sheet"] as? [String: Any])?["sections"] as? [[String: Any]] else { return nil }
    let acts = (m["acts"] as? [[String: Any]]) ?? []
    let act = { (i: Int) -> [String: Any]? in i >= 0 && i < acts.count ? acts[i] : nil }
    let p = person(id) ?? [:]
    var o = MemberParts()
    o.roleNow = p["role"] as? String ?? ""
    let isSM = o.roleNow == "Social Manager"
    let smAct = acts.first { ($0["act"] as? String) == "socialMgr" }
    for sec in secs {
      let header = sec["header"] as? String ?? ""
      let rows = (sec["rows"] as? [[String: Any]]) ?? []
      if header.hasPrefix("Only the owner") { o.locked = header; continue }
      if header == "Change role" || header.hasPrefix("Your role") {
        for r in rows {
          let label = r["label"] as? String ?? "", a = act(r["i"] as? Int ?? -1), on = (r["checked"] as? Bool) == true
          o.roles.append(UIAction(title: label, state: on && !(label == "Social" && isSM) ? .on : .off) { [weak self] _ in
            guard let self = self else { return }
            if label == "Social", isSM, let sm = smAct { self.memberAct(id, sm); return }   // (Social Manager → Social)
            if on { return }
            if isSM, let sm = smAct, let a = a { self.memberAct(id, sm) { self.memberAct(id, a) }; return }   // (no longer SM, then the role)
            if let a = a { self.memberAct(id, a) }
          })
          // (Social Manager, after Social — a Social person picked as it; anyone else made Social first)
          if label == "Social", header == "Change role", smAct != nil || !on {
            o.roles.append(UIAction(title: "Social Manager", state: isSM ? .on : .off) { [weak self] _ in
              guard let self = self, !isSM else { return }
              if on, let sm = smAct { self.memberAct(id, sm) }
              else if let a = a { self.memberAct(id, a) { [weak self] in
                guard let self = self, let sm = (self.brain("team", "memberMenu", [id, self.envNow])?["acts"] as? [[String: Any]])?.first(where: { ($0["act"] as? String) == "socialMgr" }) else { return }
                self.memberAct(id, sm) } }
            })
          }
        }
        continue
      }
      for r in rows {
        let label = r["label"] as? String ?? "", a = act(r["i"] as? Int ?? -1), on = (r["checked"] as? Bool) == true
        switch r["icon"] as? String ?? "" {
        case "coin":
          if on { o.finNow = label }
          o.fin.append(UIAction(title: label, state: on ? .on : .off) { [weak self] _ in if !on, let a = a { self?.memberAct(id, a) } })
        case "shield": if let a = a { o.admin = (on, { [weak self] in self?.memberAct(id, a) }) }
        case "folder": if let a = a { o.clients = { [weak self] in self?.memberAct(id, a) } }
        case "user": if let a = a { o.restore = { [weak self] in self?.memberAct(id, a) } }
        case "trash": if let a = a, (r["danger"] as? Bool) == true { o.remove = { [weak self] in self?.memberAct(id, a) } }
        default: break   // (Social Manager: one of the roles now)
        }
      }
    }
    return o
  }
  private func memberUIMenu(_ id: String) -> UIMenu? {
    guard let o = memberParts(id) else { return nil }
    if let l = o.locked { return UIMenu(title: l, children: [UIAction(title: "Change Role", image: UIImage(systemName: "lock.fill"), attributes: .disabled) { _ in }]) }
    var main: [UIMenuElement] = []
    if !o.roles.isEmpty { main.append(UIMenu(title: "Change Role", subtitle: o.roleNow, image: UIImage(systemName: "person.crop.circle"), children: o.roles)) }
    if let a = o.admin { main.append(UIAction(title: "Super Admin Rights", image: UIImage(systemName: "shield"), state: a.on ? .on : .off) { _ in a.run() }) }
    if !o.fin.isEmpty { main.append(UIMenu(title: "Finance Access", subtitle: o.finNow, image: UIImage(systemName: "dollarsign.circle"), children: o.fin)) }
    if let c = o.clients { main.append(UIAction(title: "Clients They Can See…", image: UIImage(systemName: "folder")) { _ in c() }) }
    if let cd = person(id)?["cd"] as? [String: Any] {
      let isCD = (cd["on"] as? Bool) == true
      main.append(UIAction(title: isCD ? cd["label"] as? String ?? "Creative Director" : "Make Creative Director", image: UIImage(systemName: "star"), state: isCD ? .on : .off) { [weak self] _ in self?.cdFlow(id) })
    }
    var last: [UIMenuElement] = []
    if let r = o.restore { last.append(UIAction(title: "Restore Access", image: UIImage(systemName: "person.badge.plus")) { _ in r() }) }
    if let r = o.remove { last.append(UIAction(title: "Remove from Team", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in r() }) }
    return UIMenu(children: [UIMenu(options: .displayInline, children: main), UIMenu(options: .displayInline, children: last)])
  }
  private func memberAct(_ id: String, _ act: [String: Any], then next: (() -> Void)? = nil) {
    if (act["open"] as? String) == "clients" { clientsMenu(id); return }
    var b = act; b["ev"] = "member"; b["id"] = id; b.removeValue(forKey: "ask")
    let go: () -> Void = { [weak self] in
      // (what you do shows at once: a role or Finance access set on the phone's copy, put back if the server says no)
      var undo: String?
      if (b["act"] as? String) == "role", let r = b["role"] as? String { undo = AppData.shared.patch("users", id, ["role": r]) }
      if (b["act"] as? String) == "fin" { let f = b["fin"] as? String ?? ""; undo = AppData.shared.patch("users", id, ["fin": f.isEmpty ? NSNull() : f]) }
      self?.direct(b, or: ["ev": "member", "id": id]) { j in
        if (j["ok"] as? Bool) != true { AppData.shared.putBack(undo); return }
        if (j["clients"] as? Bool) == true { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.clientsMenu(id) } }
        next?()
      }
    }
    if let q = act["ask"] as? [String: Any] { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.confirm(q, go) } } else { go() }
  }
  // the clients a freelancer can see: each tick saved at once (the sheet stays open)
  private func clientsMenu(_ id: String) {
    guard let m = brain("team", "clientsMenu", [id]), m["sheet"] != nil else { return }
    sheet(m, multi: true) { [weak self] act in var b = act; b["ev"] = "member"; b["id"] = id; self?.direct(b, or: nil) }
  }
  // (from the member page's switch: Apple's question comes from the switch, and a Cancel — or a tap away — puts the switch
  //  back: Haris 2026-11-10)
  private func cdFlow(_ id: String, _ h: HomeView? = nil) {
    let from = h?.meSwitchView("cd")
    let back: () -> Void = { [weak self, weak h] in h?.meSwitchBack("cd"); self?.redraw() }
    guard let q = brain("team", "cdAsk", [id]) else { send(["ev": "cd", "id": id]); return }
    let send2: ([String: Any]) -> Void = { [weak self] extra in
      var b: [String: Any] = ["ev": "cd", "id": id]; for (k, v) in extra { b[k] = v }
      self?.direct(b, or: ["ev": "cd", "id": id]) { j in
        // (someone else is CD: the server's question — take over, or Acting CD while they're away)
        guard (j["need"] as? String) == "choice", let a = j["ask"] as? [String: Any] else { return }
        let choices = (a["choices"] as? [[String: Any]]) ?? []
        var c2: [[String: Any]] = choices.map { ["label": $0["label"] as? String ?? "", "primary": ($0["primary"] as? Bool) == true] }
        c2.append(["label": "Cancel", "cancel": true])
        self?.ask(["kind": "choice", "title": a["title"] ?? "", "body": a["body"] ?? "", "choices": c2], from: from) { r in
          guard (r["ok"] as? Bool) == true, let i = r["index"] as? Int, i < choices.count, let v = choices[i]["value"] as? String else { back(); return }
          self?.direct(["ev": "cd", "id": id, "choice": v], or: nil)
        }
      }
    }
    if (q["choice"] as? Bool) == true { send2([:]); return }
    if q["title"] == nil { back(); return }
    var a = q; a["kind"] = "alert"; a["cancelText"] = "Cancel"
    ask(a) { r in if (r["ok"] as? Bool) == true { send2([:]) } else { back() } }
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
    // (the tick moves to it at once — it waited for the crossfade, so Appearance felt slow to answer: Haris 2026-11-05)
    redraw()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      let apply = {
        if v == "auto" { self.main.ownAppearanceTick() } else { self.main.keepAppearance(v) }
        self.redraw()
      }
      if let w = self.main.view.window { UIView.transition(with: w, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction], animations: { UIView.performWithoutAnimation(apply) }) } else { apply() }
    }
  }
  // View as (test site only): the team in the app's own sheet; a tap switches — the server remembers it, and the app
  // starts again as them
  func viewAsPick() {
    let pageWay = { [weak self] in (self?.top ?? self?.shown)?.toast(["t": "Couldn’t load the team — try again"]); return }
    main.serverTask.request("/api/me", body: nil) { [weak self] j in
      guard let self = self, let va = j?["viewAs"] as? [String: Any], let real = (va["real"] as? [String: Any])?["id"] as? String,
            let list = self.brain("me", "viewAsPeople", [real, self.envNow])?["people"] as? [[String: Any]] else { pageWay(); return }
      let ppl: [ViewAsSheet.Person] = list.compactMap { p in
        guard let id = p["id"] as? String else { return nil }
        return .init(id: id, name: p["name"] as? String ?? "", role: p["role"] as? String ?? "", ini: p["ini"] as? String ?? "", color: UIColor(hex: p["color"] as? String ?? "") ?? .systemGray, photo: p["photo"] as? String)
      }
      let s = ViewAsSheet(people: ppl, viewing: (va["as"] as? [String: Any])?["id"] as? String)
      s.closesOnPick = true
      s.onPick = { [weak self] id in self?.viewAsSet(id) }
      s.show(from: self.main.topMost())
    }
  }
  func viewAsSet(_ id: String?) {
    let b: [String: Any] = ["userId": id.map { $0 as Any } ?? NSNull()]
    main.serverTask.request("/api/view-as", body: b) { [weak self] j in
      guard let self = self else { return }
      guard j != nil else { (self.top ?? self.shown)?.toast(["t": "No connection — try again"]); return }
      // (what's on screen now is the other person's: put away at once — task pages, Client Assets, Me's screens, the other
      //  lists — so the new person's first tab shows, never the old one's page under their tab: Back to me left an
      //  Office Admin's page showing under Home's tab, Haris 2026-11-05)
      self.main.putAwayForSwitch()
      // (the app starts again itself as the chosen person)
      self.main.restartApp()
    }
  }
  // the Trash, searched for something (a deleted task's update tapped — step 9)
  // Content plans: its own tab (Social), else Me's page
  func openPlans() {
    if main.tabKeys.contains("plans") { main.selectTab("plans"); return }
    if main.selectedTabKey == "me", tab == "me", !hidden, !stack.isEmpty { openSoon("plans") } else { wantOpen = "plans"; main.selectTab("me") }
  }
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
  // (Me in its own Apple navigation — AppleMe.swift: Me its tab's first screen, its pages pushed on it Apple's way; the
  //  role tabs this also serves — Content plans, Overview, Team, Claims, Expenses, Reviews — as before, for now)
  private var appleNav: UINavigationController? { main.meApple && tab == "me" ? AppleTabs.shared?.meNav : main.roleApple(tab) ? AppleTabs.shared?.roleNavs[tab] : nil }
  var apple: Bool { appleNav != nil }
  private func appleVC(_ h: HomeView) -> MePageVC? { appleNav?.viewControllers.first { ($0 as? MePageVC)?.h === h } as? MePageVC }
  // (everything taken off — someone else now, another tab's pages: Me's navigation back to Me too)
  private func clearStack() {
    if let n = appleNav, n.viewControllers.count > 1 {
      n.viewControllers.forEach { ($0 as? MePageVC)?.onGone = nil }
      n.popToRootViewController(animated: false)
    }
    stack.forEach { $0.h.removeFromSuperview() }; stack = []; pageVCs = [:]
  }
  // (a page no longer there: what the page is told as it goes)
  private func left(_ s: Screen) {
    if s.kind == "team", !stack.contains(where: { $0.kind == "team" }) { send(["ev": "team", "on": false]) }
    if s.kind == "profile" { send(["ev": "pf", "on": false]) }
    if s.kind == "plans" { send(["ev": "pl", "on": false]) }
    if s.kind == "plan" { send(["ev": "plOpen", "pid": ""]) }
    if s.kind == "trash" { send(["ev": "tr", "on": false]) }
  }
  // a page pushed in Me's navigation gone (‹, the swipe back, popped): off the stack, the one under it drawn again
  private func navGone(_ h: HomeView) {
    guard let i = stack.firstIndex(where: { $0.h === h }), i > 0 else { return }
    let s = stack.remove(at: i)
    pageVCs[ObjectIdentifier(h)] = nil
    left(s)
    if let t = stack.last { draw(t) }
    main.updateCorner()
  }
  // (Me's navigation settled — the tab tapped again pops them all at once, and only the top one hears it)
  // (Me's first screen made as its tab first comes up — in it from the start, filled as its model comes: the tab never
  //  comes up empty, and Apple's bar has its list before the first look — Haris 2026-11-08)
  func prepareRoot() {
    guard apple, stack.isEmpty else { return }
    push(screen(rootKind, nil), animated: false)
  }
  // (Me and Social's Plans tab — two Apple tabs this one page-keeper serves: the one about to show gets its first screen
  //  before iPhone draws it, never a blank tab for a moment as the other gives it up)
  func willShowTab(_ key: String) {
    guard key != tab, let me = me ?? AppData.shared.me else { prepareRoot(); return }
    command(["show": true, "me": me, "tab": key, "model": ["env": ["shell": SHELL_VERSION]]])
  }
  func reconcile(_ vcs: [UIViewController]) {
    guard apple else { return }
    // (a page still on its way in — pushed just after another went back — isn't gone)
    for s in stack.dropFirst() where !vcs.contains(where: { ($0 as? MePageVC)?.h === s.h }) {
      if let vc = pageVCs[ObjectIdentifier(s.h)], !vc.appeared { continue }
      navGone(s.h)
    }
  }
  private var pageVCs: [ObjectIdentifier: MePageVC] = [:]
  private var model: [String: Any] = [:]
  private var about: [String: Any] = [:]
  private var me: String?
  private(set) var leaving = false
  private var hidden = false          // (the page went elsewhere — another tab, My profile…: kept, out of sight)
  private var teamTab = 0, teamQ = "", teamMarks: [String] = []
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
    nativeEv(ev)   // (the app does it itself — no website)
  }
  // ---------- Step 9: what the page did for Me, done by the app (phone.js NativeMe __e11Me) ----------
  private func nativeEv(_ ev: [String: Any]) {
    let say = { [weak self] (t: String) in (self?.top ?? self?.shown)?.toast(["t": t]) }
    switch ev["ev"] as? String ?? "" {
    case "nav":
      switch ev["to"] as? String ?? "" {
      case "clients":
        // (as the page opened it: in this look, for this person — it showed in the wrong look and without its top buttons;
        //  then Me goes once it has slid in over it, and comes back when Client Assets is left — Haris 2026-11-05)
        main.assetsCtl.command(["show": true, "me": me ?? "", "start": [String: Any]()])
        if !apple { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in if self?.main.assetsCtl.isOpen == true { self?.hide() } } }
      case "calendar": say("The content calendar is on the computer")
      case "projects": say("Every client’s tasks are on the computer for now")
      default: break
      }
    case "rvTask": if let t = ev["tid"] as? String, !t.isEmpty { main.openTaskPage(t, tab: "details", focus: "") }
    case "rvFile":
      // (the request's files, from its task's own page model — they carry where each file is)
      guard let it = reviewItem(ev["id"] as? String ?? ""), let tid = it.0["tid"] as? String,
            let tm = AppData.shared.screen("task", tid).model else { return }
      let all = ((tm["files"] as? [[String: Any]]) ?? []) + ((tm["commentFiles"] as? [[String: Any]]) ?? [])
      let want = (((it.0["files"] as? [[String: Any]]) ?? []) + ((it.0["carriedFiles"] as? [[String: Any]]) ?? [])).compactMap { $0["id"] as? String }
      let list = want.compactMap { id in all.first { ($0["id"] as? String) == id } }
      if let i = list.firstIndex(where: { ($0["id"] as? String) == (ev["fid"] as? String) }) { main.openFiles(list, at: i) }
    case "pfTest":
      main.withToken { [weak self] t, why in
        guard let t = t else { say(why ?? "iPhone gave no notification address"); return }
        self?.main.serverTask.request("/api/push/test", body: ["token": t]) { r in say(r.map { MeCtl.testSaid($0) } ?? "No connection — try again") }
      }
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
    // (the phone's own way couldn't run yet — the rules not loaded, or the copy not this person's yet: these went to the
    //  website, which isn't there, and the tap did nothing — Haris 2026-11-11: say so instead)
    case "addMember", "cd", "pfName", "pfBday", "pfPhoto", "pfPhotoOff", "push", "theme", "trEmpty", "trForever":
      say("Not ready yet — try again in a moment")
    case "import": say("Moving data from the Mac app is done on the Mac")
    case "update", "videoCheck": say("Not available here right now — try again in a moment")
    // (a page's own view changed — the content plans' month, a list's filter: drawn again from the copy with it; the month
    //  bar moved but the plans and the line under the title stayed on the old month — found by the crawl, 2026-11-06)
    // (and the Trash's search and categories — they kept the same list: Haris 2026-11-06)
    case "pl", "cl", "ex", "tr", "team", "pf", "trQ", "trCat":
      DispatchQueue.main.async { [weak self] in guard let self = self, !self.stack.isEmpty else { return }; self.model = self.own(self.pageModel); if !self.hidden { self.stack.forEach { self.draw($0) } } }
    default: break   // (toasts: only the page needed to hear them)
    }
  }

  // ---------- from the page ----------
  func command(_ a: [String: Any]) {
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
    if let m = a["me"] as? String {
      // (someone else now — View as…, signed in again: Me from the start)
      if let was = me, was != m { clearStack() }
      me = m
    }
    if let m = a["model"] as? [String: Any] { pageModel = m; model = own(m) }
    if copyWatch == nil { copyWatch = AppData.shared.listen { [weak self] in guard let self = self, !self.pageModel.isEmpty, !self.stack.isEmpty else { return }; self.model = self.own(self.pageModel); if !self.hidden { self.stack.forEach { self.draw($0) } } } }
    // (the other tab now — Me ↔ Content plans: its own first page)
    let want = ["plans", "today", "team", "fin-reimb", "fin-expenses", "reviews"].contains(a["tab"] as? String ?? "") ? (a["tab"] as! String) : "me"
    if want != tab {
      if stack.contains(where: { $0.kind == "plans" }) { send(["ev": "pl", "on": false]) }
      clearStack(); tab = want
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
    // (in Apple's navigation: another tab is Apple's to show — Me stays as it is in its own tab)
    // (and only when Me's tab isn't the one on — Client Assets pushed over Me keeps Me as it is, under it)
    if apple { coverWait = nil; if main.selectedTabKey == tab { return }; hidden = true; borrowTimer?.invalidate(); stack.forEach { _ = $0.h.endEditing(true) }; main.edgePanOn(); main.updateCorner(); return }
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
    if apple { main.edgePanOn(); main.updateCorner(); return }
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
    for x in stack { if main.corner.superview === v { v.insertSubview(x.h, belowSubview: main.corner) } else { v.insertSubview(x.h, belowSubview: main.tabsMark) } }
  }
  // shown at once under a page going back to Me (Client Assets' ‹): the page says so a moment later — if it doesn't,
  // out of sight again
  private var borrowTimer: Timer?
  func borrow() -> UIView? {
    guard let s = stack.last, main.selectedTabKey == tab, !apple else { return nil }
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
    if kind == "expenses" {   // (Team members, Reviews: Apple's own controls in Apple's navigation, no swipe of ours)
      SegSwipe.attach(h) { [weak self, weak h] dir in
        guard let self = self, let h = h, let s = self.screenOf(h) else { return }
        let to = dir < 0 ? 1 : 0
        switch s.kind {
        case "expenses": guard self.exSeg != to else { return }; self.exSeg = to
        default: return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        self.slideLists(h, dir: dir) { self.draw(s) }
      }
    }
    if appleNav == nil { main.view.insertSubview(h, belowSubview: main.tabsMark) }
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
    if let n = appleNav {
      stack.append(s); watchTouches()
      if !pageModel.isEmpty { model = own(pageModel) }
      // (Me: its tab's first screen)
      if stack.count == 1, let vc = MeTabVC.byKey[tab], main.roleApple(tab) { vc.adopt(s.h); draw(s); main.updateCorner(); return }   // (a role's own tab — Social's Plans, an Office Admin's Team)
      if stack.count == 1, let vc = MeVC.shared { vc.adopt(s.h); draw(s); main.updateCorner(); return }
      // (its Apple page made first: what it draws knows it's in Apple's navigation — Team members' search in Apple's bar)
      let vc = MePageVC(s.h)
      pageVCs[ObjectIdentifier(s.h)] = vc
      draw(s)
      vc.onGone = { [weak self, weak h = s.h] in if let h = h { self?.navGone(h) } }
      vc.loadViewIfNeeded()
      draw(s)   // (in Apple's list now)
      // (Apple's navigation still moving — a page going back: pushed once it has settled, else Apple drops the push)
      let go = { [weak n] in guard let n = n else { return }; n.pushViewController(vc, animated: animated && n.view.window != nil) }
      if let tc = n.transitionCoordinator { tc.animate(alongsideTransition: nil) { _ in DispatchQueue.main.async { go() } } } else { go() }
      main.updateCorner()
      return
    }
    let W = main.view.bounds.width
    let u = stack.last?.h
    stack.append(s); watchTouches()
    // (its contents from the app's copy now that it's in the stack — My profile, Team, Trash, Content plans: without the
    //  website nothing else sends them, and they stayed on "Loading…" — Haris 2026-11-05)
    if !pageModel.isEmpty { model = own(pageModel) }
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
    if let n = appleNav {
      // (Apple's pop — what follows is done as the page goes: navGone)
      if let vc = appleVC(s.h), n.topViewController === vc { n.popViewController(animated: animated && n.view.window != nil) } else { navGone(s.h) }
      return
    }
    let W = main.view.bounds.width
    let u = stack[stack.count - 2].h
    u.isHidden = false; u.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    leaving = true
    main.updateCorner()
    let finish = {
      s.h.removeFromSuperview()
      if let i = self.stack.firstIndex(where: { $0.h === s.h }) { self.stack.remove(at: i) }
      self.leaving = false
      self.left(s)
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
    if let n = appleNav {
      // (Apple's own: back to Me — on Me already: up to the top)
      if n.transitionCoordinator != nil { return }
      if n.viewControllers.count > 1 { n.popToRootViewController(animated: n.view.window != nil) } else { stack.first?.h.scrollToTop() }
      return
    }
    guard stack.count > 1, let topS = stack.last, !leaving else { stack.first?.h.scrollToTop(); return }
    let W = main.view.bounds.width
    let snap = topS.h.snapshotView(afterScreenUpdates: false)
    if let sn = snap { sn.frame = topS.h.frame; main.view.insertSubview(sn, belowSubview: main.tabsMark) }
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
    if apple { backToRoot(); return nil }
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
    guard stack.count > 1, let s = stack.last, !leaving, !apple else { return }
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
  // Team members, as the phone shows them (the no-website self-test — Haris 2026-11-10, the approved mock-up): the list's
  // people with their role, a person's Apple menu, and their page's rows
  func selfTeam() -> [String: Any] {
    let t = team
    let people = ((t["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["people"] as? [[String: Any]]) ?? [] }
    let other = people.first { ($0["you"] as? Bool) != true && ($0["locked"] as? Bool) != true }
    var o: [String: Any] = ["kind": stack.last?.kind ?? "", "people": people.count, "roles": people.prefix(6).map { "\($0["name"] ?? ""): \($0["role"] ?? "")" }, "admin": (t["admin"] as? Bool) == true]
    if let id = other?["id"] as? String, let m = memberUIMenu(id) {
      let flat = m.children.flatMap { ($0 as? UIMenu)?.children ?? [$0] }
      o["menu"] = flat.map { e -> String in (e as? UIMenu).map { "\($0.title) ›" } ?? (e as? UIAction)?.title ?? "?" }
      o["roleMenu"] = ((flat.first { ($0 as? UIMenu)?.title == "Change Role" } as? UIMenu)?.children ?? []).compactMap { ($0 as? UIAction)?.title }
      o["other"] = id
    }
    if let s = stack.last, s.kind == "member" { o["rows"] = s.h.meKeys }
    return o
  }
  func selfOpenMember(_ id: String) { open("member", id) }
  // the CD's Reviews, as the phone shows them (the no-website self-test — Haris 2026-11-10)
  func selfReviews() -> [String: Any] {
    guard let s = stack.last else { return ["open": false] }
    let m = model["reviews"] as? [String: Any]
    var o: [String: Any] = ["kind": s.kind, "tab": tab, "apple": apple, "waiting": (m?["waiting"] as? [Any])?.count ?? -1, "reviewed": (m?["reviewed"] as? [Any])?.count ?? -1, "skeletons": rvSkeletons.count, "rows": s.h.meKeys.count]
    if let e = s.h.assetsParts["wait"] as? AppleEmpty, e.superview != nil { o["loading"] = e.loading }
    o["seg"] = s.h.assetsParts["seg"]?.superview != nil
    if let x = ((m?["waiting"] as? [[String: Any]]) ?? []).first, let menu = rvItem(x, decided: false).menu?() {
      o["menu"] = menu.children.flatMap { ($0 as? UIMenu)?.children ?? [$0] }.compactMap { ($0 as? UIAction)?.title }
    }
    if let vc = pageVCs[ObjectIdentifier(s.h)] { o["tools"] = (vc.toolbarItems ?? []).compactMap { $0.title } }
    return o
  }
  func selfOpenReview() -> String? {
    guard let id = (((model["reviews"] as? [String: Any])?["waiting"] as? [[String: Any]])?.first?["id"] as? String) else { return nil }
    open("review", id); return id
  }
  // an Office Admin's tabs and Me › Trash, as the phone shows them (the no-website self-test — Haris 2026-11-11): what's on
  // show, a claim's swipes and menu, a claim opened with its toolbar; a Trash item's swipes and menu
  func selfOffice() -> [String: Any] {
    guard let s = stack.last else { return ["open": false] }
    var o: [String: Any] = ["kind": s.kind, "tab": tab, "apple": apple, "rows": s.h.meKeys.count]
    if let e = s.h.assetsParts["wait"] as? AppleEmpty, e.superview != nil { o["loading"] = e.loading }
    let titles = { (m: UIMenu?) -> [String] in (m?.children ?? []).flatMap { ($0 as? UIMenu)?.children ?? [$0] }.compactMap { ($0 as? UIAction)?.title } }
    if let c = model["claims"] as? [String: Any] {
      let all = (c["all"] as? [[String: Any]]) ?? []
      o["claims"] = all.count; o["need"] = ((c["need"] as? [Any]) ?? []).count; o["pick"] = ((c["pick"] as? [Any]) ?? []).count
      if let x = all.first(where: { ($0["legacy"] as? Bool) != true }), let h = stack.first?.h {
        let it = claimItem(h, x, admin: (c["admin"] as? Bool) == true)
        o["menu"] = titles(it.menu?()); o["lead"] = it.lead.map { $0.title }; o["trail"] = it.trail.map { $0.title }
      }
    }
    if let x = model["expenses"] as? [String: Any] { o["subs"] = ((x["subs"] as? [Any]) ?? []).count; o["ended"] = ((x["ended"] as? [Any]) ?? []).count }
    if let ov = model["overview"] as? [String: Any] { o["fin"] = ov["fin"] ?? false; o["numbers"] = MeCtl.shows(AppleTabs.shared?.roleNavs[tab]?.view ?? s.h, "Claims submitted") }
    if s.kind == "trash", let t = model["trash"] as? [String: Any], let x = ((t["groups"] as? [[String: Any]])?.first?["items"] as? [[String: Any]])?.first {
      let it = trashRow(s.h, x)
      o["items"] = t["n"] ?? 0; o["menu"] = titles(it.menu?()); o["lead"] = it.lead.map { $0.title }; o["trail"] = it.trail.map { $0.title }
    }
    if let vc = pageVCs[ObjectIdentifier(s.h)] { o["tools"] = (vc.toolbarItems ?? []).compactMap { $0.title } }
    return o
  }
  // (the self-test: a row with these words on screen — Apple's list cell or a label — wherever it's drawn)
  static func shows(_ v: UIView, _ t: String) -> Bool {
    if let c = v as? UICollectionViewCell, (c.contentConfiguration as? UIListContentConfiguration)?.text == t { return true }
    if let c = v as? UITableViewCell, (c.contentConfiguration as? UIListContentConfiguration)?.text == t { return true }
    if let l = v as? UILabel, l.text == t { return true }
    return v.subviews.contains { shows($0, t) }
  }
  func selfOpenClaim() -> String? {
    guard let id = (((model["claims"] as? [String: Any])?["all"] as? [[String: Any]])?.first(where: { ($0["legacy"] as? Bool) != true })?["id"] as? String) else { return nil }
    open("claim", id); return id
  }
  func selfOpenTrash() { open("trash") }
  // Content plans, as the phone shows them (the no-website self-test — Haris 2026-11-10): the list, and a client's month
  func selfOpenPlan() -> String? {
    guard let r = ((model["plans"] as? [String: Any])?["rows"] as? [[String: Any]])?.first, let pid = r["pid"] as? String else { return nil }
    open("plan", "\(pid)|\((model["plans"] as? [String: Any])?["month"] as? String ?? "")"); return pid
  }
  func selfPlans() -> [String: Any] {
    guard let s = stack.last else { return ["open": false] }
    let parts = s.h.assetsParts
    var o: [String: Any] = ["open": true, "kind": s.kind, "tab": tab, "kinds": stack.map { $0.kind }, "apple": apple, "line": plansLine]
    if let e = parts["wait"] as? AppleEmpty, e.superview != nil { o["loading"] = e.loading }
    if let e = parts["none"] as? AppleEmpty, e.superview != nil { o["empty"] = e.title }
    o["rows"] = ((model["plans"] as? [String: Any])?["rows"] as? [[String: Any]])?.count ?? -1
    o["waitGroup"] = parts["g.plw"]?.superview != nil
    o["status"] = parts["g.st"]?.superview != nil
    if let vc = pageVCs[ObjectIdentifier(s.h)] { o["tools"] = vc.toolbarItems?.count ?? 0; o["title"] = vc.navigationItem.title ?? "" }
    if s.kind == "plan" { o["model"] = (model["plan"] as? [String: Any]).map { ["pid": $0["pid"] ?? "", "st": ($0["st"] as? [String: Any])?["t"] ?? "", "empty": $0["empty"] != nil, "trash": $0["trash"] ?? false] } ?? "none" }
    return o
  }
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
    // (apple: Me in its own Apple navigation — its pages have Apple's ‹, not the shared one)
    return ["open": isOpen, "screens": stack.count, "kind": kind, "parts": parts, "shown": shown != nil, "corner": corner, "people": people, "rows": rows, "card": card, "profile": profile, "apple": apple]
  }
  func refresh() { if isOpen, stack.contains(where: { $0.kind == "about" }) { loadAbout(false) } }

  // ---------- what's on each ----------
  private func redrawRoot() { if let s = stack.first(where: { $0.kind == "me" }) { draw(s) } }
  private func draw(_ s: Screen) {
    var mm: [String: Any] = ["show": true, "me": me ?? "", "look": main.lookBoth]
    if s.kind == "me" { mm["title"] = apple ? "Settings" : "Me"; mm["date"] = "E11 Console App" }   // (in Apple's navigation: "Settings" — Haris 2026-11-08; the tab stays "Me")
    if s.h.assets == "overviewTab" { mm["title"] = "Overview"; mm["date"] = Date().formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    if s.h.assets == "claimsTab" { mm["title"] = "Claims"; mm["date"] = (model["claims"] as? [String: Any])?["sub"] as? String ?? "" }
    if s.h.assets == "reviewsTab" {
      // (the requests and the skeletons waiting for you — one decided here already gone)
      let w = ((model["reviews"] as? [String: Any])?["waiting"] as? [[String: Any]]) ?? []
      let n = w.filter { !rvGone.contains($0["id"] as? String ?? "") }.count + rvSkeletons.count
      mm["title"] = "Reviews"; mm["date"] = model["reviews"] == nil ? "" : n == 0 ? "Nothing waiting" : n == 1 ? "1 request waiting" : "\(n) requests waiting"
    }
    if s.h.assets == "expensesTab" {
      let x = (model["expenses"] as? [String: Any]) ?? [:]
      let n = x["subsN"] as? Int ?? 0, o = x["officeN"] as? Int ?? 0
      mm["title"] = "Expenses"
      mm["date"] = x.isEmpty ? "" : exSeg == 0 ? "\(n) subscription\(n == 1 ? "" : "s") · \(x["subsTotal"] as? String ?? "") a month" : "\(x["omName"] as? String ?? "") · \(o) expense\(o == 1 ? "" : "s") · \(x["officeTotal"] as? String ?? "")"
    }
    if s.h.assets == "teamTab" { mm["title"] = "Team members"; mm["date"] = team.isEmpty ? "" : "\(team["active"] as? Int ?? 0) active · \(team["pastN"] as? Int ?? 0) past" }
    if s.h.assets == "plansTab" || s.h.assets == "plansPage" { mm["title"] = "Content plans"; mm["date"] = plansLine }   // (the line under the big title, as the other tabs have — Haris 2026-11-03)
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
      } else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n) }
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
      if !FOLLOW_DEVICE { phone.append(SetItem(key: "appearance", title: "Appearance", value: themeWord, sym: "circle.lefthalf.filled", col: .systemIndigo, tap: { [weak self] in self?.open("appearance") })) }
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
    case "claim": claimBlocks(h, s.id ?? "", &out)
    case "review": reviewBlocks(h, s.id ?? "", &out)
    case "claims":
      claimsBlocks(h, &out)
    case "expenses":
      expensesBlocks(h, &out)
    case "member":
      memberBlocks(h, s.id ?? "", &out)
    case "roles":
      rolesBlocks(h, &out)
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
  // each person's role as the website's Role column shows it (Creative Director and Social Manager are roles there —
  // Haris 2026-11-10), its colour as the website's role pill, then the extras (+ Admin, + Finance Admin, N clients)
  static func roleCol(_ r: String) -> UIColor {
    switch r {
    case "Super Admin", "Office Admin": return .systemIndigo
    case "Account Manager": return .systemBlue
    case "Production": return .systemOrange
    case "Social", "Social Manager", "Creative Director", "Acting CD", "Acting Creative Director": return .systemPink
    case "Freelancer": return .systemTeal
    default: return r.hasPrefix("Finance") ? .systemGreen : .systemGray
    }
  }
  private func people(_ list: [[String: Any]], hold: Bool) -> [SetItem] {
    list.map { p in
      let id = p["id"] as? String ?? ""
      let role = p["role"] as? String ?? ""
      let extras: [(String, UIColor)] = ((p["pills"] as? [[String: Any]]) ?? []).compactMap { x -> (String, UIColor)? in
        let t = x["t"] as? String ?? ""
        return t == role || t == "Creative Director" || t == "Acting CD" || t == "Social Manager" ? nil : (t, NativeSheetVC.color(x["c"]) ?? .systemGray)
      }
      let pills: [(String, UIColor)] = (role.isEmpty ? [] : [(role, MeCtl.roleCol(role))]) + extras
      let pending: Bool = (p["pending"] as? Bool) == true
      let sub: String = pending ? "Hasn’t signed in yet" : (p["email"] as? String ?? "")
      let title: String = (p["name"] as? String ?? "") + ((p["you"] as? Bool) == true ? " (you)" : "")
      let pic: (photo: String?, ini: String, rgb: UIColor) = (p["photo"] as? String, p["ini"] as? String ?? "", NativeSheetVC.color(p["rgb"]) ?? .systemGray)
      let past: Bool = (p["past"] as? Bool) == true
      var it = SetItem(key: id, title: title, sub: sub, pills: pills, person: pic, warn: pending, dim: past, tap: { [weak self] in self?.open("member", id) })
      // (touch and hold, Admins: Apple's own lift and Apple's own menu with every action in it — the mock-up's A1)
      if hold { it.menu = { [weak self] in self?.memberUIMenu(id) } }
      return it
    }
  }
  // ---------- an Office Admin's Overview — fully Apple (Haris 2026-11-11 07:25, the mock-up "Remaining pages — fully
  //  Apple", A1) ----------
  // Its tab (MeTabVC "today"): Apple's big title "Overview" with the day, Apple's search for every client's files, your
  // photo. With Finance: the month's three numbers as Apple's cells, each opening its tab; Need HR approval (a claim opens
  // its page), the month's office expenses and the latest in Client Assets, each with See All. Without: the latest 10 in
  // Client Assets.
  private var ovQ = "", ovAsked = "", ovFound: [String: Any]? = nil
  private func overviewBlocks(_ h: HomeView, _ out: inout [UIView]) {
    if h.assets == "overviewTab", let vc = MeTabVC.byKey["today"] {
      vc.onSearch = { [weak self, weak h] q in guard let self = self, let h = h, self.ovQ != q else { return }; self.ovQ = q; self.ovSearch(h) }
    }
    let q = ovQ.trimmingCharacters(in: .whitespaces)
    if !q.isEmpty {
      guard let r = ovFound, ovAsked == q else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
      let found = (r["found"] as? [[String: Any]]) ?? []
      if found.isEmpty { let n = part(h, "none") { AppleEmpty() }; n.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); out.append(n); return }
      let items = found.map { f -> SetItem in
        var it = SetItem(key: "s." + (f["id"] as? String ?? ""), title: f["name"] as? String ?? "", sub: f["where"] as? String ?? "", chevron: false, tap: { [weak self] in self?.openOne(f["path"] as? String ?? "", f["name"] as? String ?? "File") })
        it.person = (photo: f["pic"] as? String, ini: f["ext"] as? String ?? "", rgb: .systemGray)
        return it
      }
      out.append(head(h, "ovs", (r["loose"] as? Bool) == true ? "Close matches" : "Files · \(items.count)"))
      let g = group(h, "ovs", items); Find.mark([g], (r["marks"] as? [String]) ?? Find.terms(q)); out.append(g)
      return
    }
    guard let o = model["overview"] as? [String: Any] else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    let sec = { (k: String, t: String, to: String) -> SetHead in
      let v = self.head(h, k, t); v.link("See All"); v.onLink = { [weak self] in self?.ovGo(to) }; return v }
    let files = ((o["assets"] as? [[String: Any]]) ?? []).map { f -> SetItem in
      var it = SetItem(key: "f." + (f["id"] as? String ?? ""), title: f["name"] as? String ?? "", sub: f["where"] as? String ?? "", value: f["when"] as? String ?? "", chevron: false, tap: { [weak self] in self?.openOne(f["path"] as? String ?? "", f["name"] as? String ?? "File") })
      it.person = (photo: f["pic"] as? String, ini: f["ext"] as? String ?? "", rgb: NativeSheetVC.color(f["rgb"]) ?? .systemGray)
      return it
    }
    if (o["fin"] as? Bool) == true {
      // (the month's numbers — Apple's cells, each opening its tab)
      let cards = (o["cards"] as? [[String: Any]]) ?? []
      let n = { (i: Int) -> String in i < cards.count ? (cards[i]["n"] as? String ?? "") : "" }
      let of = cards.first?["of"] as? String ?? ""
      out.append(head(h, "ovn", o["cm"] as? String ?? ""))
      out.append(group(h, "ovn", [
        SetItem(key: "n.cl", title: "Claims submitted", value: of.isEmpty ? n(0) : "\(n(0)) of \(of.replacingOccurrences(of: "/ ", with: ""))", sym: "person.2.fill", col: .systemIndigo, tap: { [weak self] in self?.ovGo("claimsAll") }),
        SetItem(key: "n.ex", title: "Office expenses so far", value: n(1), sym: "doc.text.fill", col: .systemGray, tap: { [weak self] in self?.ovGo("expenses") }),
        SetItem(key: "n.sb", title: "Monthly subscriptions", value: n(2), sym: "arrow.triangle.2.circlepath", col: .systemIndigo, tap: { [weak self] in self?.ovGo("subs") }),
      ]))
      let cl = ((o["claims"] as? [[String: Any]]) ?? []).map { c -> SetItem in
        let id = c["id"] as? String ?? ""
        var it = SetItem(key: "c." + id, title: c["name"] as? String ?? "", sub: c["sub"] as? String ?? "", value: c["amt"] as? String ?? "", tap: { [weak self] in self?.open("claim", id) })
        it.person = (photo: c["photo"] as? String, ini: c["ini"] as? String ?? "", rgb: NativeSheetVC.color(c["rgb"]) ?? .systemGray)
        return it
      }
      out.append(sec("ovc", "Need HR approval · \(o["needN"] as? Int ?? cl.count)", "claims"))
      if cl.isEmpty { out.append(foot(h, "ovc0", "No claims waiting.")) } else { out.append(group(h, "ovc", cl)) }
      let ex = ((o["expenses"] as? [[String: Any]]) ?? []).map { x in SetItem(key: "x." + (x["id"] as? String ?? ""), title: x["name"] as? String ?? "", sub: x["sub"] as? String ?? "", value: x["amt"] as? String ?? "", sym: "doc.text.fill", col: .systemGray, chevron: false) }
      out.append(sec("ovx", "Office expenses · \(o["nowName"] as? String ?? "")", "expenses"))
      if ex.isEmpty { out.append(foot(h, "ovx0", "None this month yet.")) } else { out.append(group(h, "ovx", ex)) }
      out.append(sec("ova", "Client Assets · latest", "assets"))
    } else {
      out.append(sec("ova", "Client Assets · latest", "assets"))
    }
    if files.isEmpty { out.append(foot(h, "ova0", "No files yet.")) } else { out.append(group(h, "ova", files)) }
  }
  // Overview's search: every client's files (Client Assets' own search, from the phone's copy)
  private func ovSearch(_ h: HomeView) {
    let q = ovQ.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { ovFound = nil; ovAsked = ""; blocks(h); return }
    request(["ev": "ovFind", "q": q]) { [weak self, weak h] r in
      guard let self = self, let h = h, self.ovQ.trimmingCharacters(in: .whitespaces) == q else { return }
      self.ovFound = r; self.ovAsked = q; self.blocks(h)
    }
    blocks(h)
  }
  private func openOne(_ path: String, _ name: String) { guard !path.isEmpty else { return }; main.openFiles([["id": path, "path": path, "name": name]], at: 0) }
  // Overview's See All and its numbers: that tab, as if tapped (Claims, Expenses, Client Assets) — never the website's Home
  // underneath (Haris 2026-11-04: it went to "E11 Day"); Client Assets with Finance is Me's page
  private func ovGo(_ to: String) {
    let key = ["assets": "clients", "claims": "fin-reimb", "claimsAll": "fin-reimb", "expenses": "fin-expenses", "subs": "fin-expenses"][to] ?? ""
    // (on the list the row was about: Need approval, or All; Office expenses, or Subscriptions — Haris 2026-11-04)
    if to == "claims" { clSeg = 0 }
    if to == "claimsAll" { clSeg = 1 }
    if to == "expenses" { exSeg = 1; exMonth = nil }
    if to == "subs" { exSeg = 0 }
    if main.tabKeys.contains(key) { main.selectTab(key); return }
    if key == "clients" { coverWait = Date(); send(["ev": "nav", "to": "clients"]) }
  }
  // ---------- the CD's Reviews — fully Apple (Haris 2026-11-10, the approved mock-up "Review Requests — fully Apple":
  //  A2 · B1 · C1 · D2 · E2 · F2 · G2) ----------
  // Its tab: Apple's big title "Reviews" and its line, Apple's search, your photo (MeTabVC); Waiting · Reviewed as Apple's
  // segmented control at the top of the list, scrolling away with it (E2); the skeletons sent to you their own group
  // "Content plans" on top of Waiting, opening the skeleton (A2); every request Apple's list cell — the sender's picture,
  // the task, the client and who sent what when, ours only the Round / result words; touch and hold: Apple's menu with
  // Approve · Request Amendments… · Open Task (C1).
  private func reviewsBlocks(_ h: HomeView, _ out: inout [UIView]) {
    guard let m = model["reviews"] as? [String: Any] else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    let wait = ((m["waiting"] as? [[String: Any]]) ?? []).filter { !rvGone.contains($0["id"] as? String ?? "") }
    let done = (m["reviewed"] as? [[String: Any]]) ?? []
    let skels = rvSkeletons
    if let vc = MeTabVC.byKey["reviews"], h.assets == "reviewsTab" {
      vc.onSearch = { [weak self, weak h] q in guard let self = self, let h = h, self.rvQ != q else { return }; self.rvQ = q; self.blocks(h) }
    }
    // (an Inbox update about a request, or a notification: that request opened — Waiting or Reviewed under it)
    if let f = m["focus"] as? [String: Any], let n = f["n"] as? Int, n != rvFocusN, let fid = f["id"] as? String {
      rvFocusN = n
      rvSeg = done.contains(where: { ($0["id"] as? String) == fid }) ? 1 : 0
      DispatchQueue.main.async { [weak self] in guard let self = self else { return }; if self.stack.count > 1 { self.backToRoot() }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.open("review", fid) } }
    }
    let q = rvQ.trimmingCharacters(in: .whitespaces)
    if !q.isEmpty {
      // (search: by task, client or person — typos forgiven, the words marked; Waiting and Reviewed both)
      let text = { (x: [String: Any]) in "\(x["task"] ?? "") \(x["client"] ?? "") \(x["who"] ?? "")" }
      let fw = Find.filter(wait, q, text: text), fd = Find.filter(done, q, text: text)
      if fw.items.isEmpty && fd.items.isEmpty { let e = part(h, "none") { AppleEmpty() }; e.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); out.append(e); return }
      if !fw.items.isEmpty { out.append(head(h, "rqw", "Waiting · \(fw.items.count)")); let g = group(h, "rqw", fw.items.map { rvItem($0, decided: false) }); Find.mark([g], fw.marks); out.append(g) }
      if !fd.items.isEmpty { out.append(head(h, "rqd", "Reviewed · \(fd.items.count)")); let g = group(h, "rqd", fd.items.map { rvItem($0, decided: true) }); Find.mark([g], fd.marks); out.append(g) }
      return
    }
    let seg = part(h, "seg") { SegBlock() }
    seg.set("Waiting · \(wait.count + skels.count)", "Reviewed · \(done.count)", rvSeg)
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h, self.rvSeg != i else { return }; self.rvSeg = i; self.blocks(h) }
    out.append(seg)
    if rvSeg == 0 {
      if wait.isEmpty && skels.isEmpty { let e = part(h, "none0") { AppleEmpty() }; e.set("checkmark.circle", "All Caught Up", "New requests appear here, and you get a notification."); out.append(e); return }
      if !skels.isEmpty {
        out.append(head(h, "rvp", "Content plans · \(skels.count)"))
        out.append(group(h, "rvp", skels.map { r in
          let pid = r["pid"] as? String ?? "", month = r["month"] as? String ?? ""
          var it = SetItem(key: "p." + (r["id"] as? String ?? ""), title: r["title"] as? String ?? "", sub: r["sub"] as? String ?? "", tap: { [weak self] in self?.open("plan", "\(pid)|\(month)") })
          it.person = (photo: nil, ini: r["ini"] as? String ?? "", rgb: NativeSheetVC.color(r["rgb"]) ?? .systemGray)
          return it
        }))
      }
      if !wait.isEmpty {
        out.append(head(h, "rvw", skels.isEmpty ? "" : "Files for review · \(wait.count)"))
        out.append(group(h, "rvw", wait.map { rvItem($0, decided: false) }))
        out.append(foot(h, "rvwf", "Oldest first."))
      }
    } else {
      if done.isEmpty { let e = part(h, "none1") { AppleEmpty() }; e.set("clock", "Nothing Reviewed Yet", "Decisions from the last 15 days appear here."); out.append(e); return }
      out.append(head(h, "rvd", "Last 15 days"))
      out.append(group(h, "rvd", done.map { rvItem($0, decided: true) }))
      out.append(foot(h, "rvdf", "Newest first — each leaves this list 15 days after it was decided."))
    }
  }
  // the skeletons waiting for you, every month (the engine's plansForMe)
  private var rvSkeletons: [[String: Any]] { ((AppData.shared.meModel("plans", "plansForMe") ?? [:])["rows"] as? [[String: Any]]) ?? [] }
  // a request as Apple's list cell
  private func rvItem(_ x: [String: Any], decided: Bool) -> SetItem {
    let id = x["id"] as? String ?? "", tid = x["tid"] as? String ?? ""
    let client = x["client"] as? String ?? "", carried = x["carried"] as? Int ?? 0, round = x["round"] as? Int ?? 1
    var lines = [[client, x["sub"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")]
    if !decided, carried > 0 { lines.append("\(carried) already approved") }
    var it = SetItem(key: "r." + id, title: x["task"] as? String ?? "", sub: lines.joined(separator: "\n"), tap: { [weak self] in self?.open("review", id) })
    it.person = (photo: x["photo"] as? String, ini: x["ini"] as? String ?? "", rgb: NativeSheetVC.color(x["rgb"]) ?? .systemGray)
    if decided, let r = x["res"] as? [String: Any] { it.pills = [(r["t"] as? String ?? "", (r["k"] as? String) == "ok" ? .systemGreen : .systemOrange)] }
    else if round > 1 { it.pills = [("Round \(round)", .systemOrange)] }
    // (touch and hold a waiting one: Apple's menu — Approve · Request Amendments… · Open Task; a reviewed one: Open Task)
    it.menu = { [weak self] in
      var acts: [UIMenuElement] = []
      if !decided {
        acts.append(UIMenu(options: .displayInline, children: [
          UIAction(title: "Approve", image: UIImage(systemName: "checkmark")) { _ in self?.rvApprove(x) },
          UIAction(title: "Request Amendments…", image: UIImage(systemName: "pencil")) { _ in self?.rvAmend(x) }
        ]))
      }
      acts.append(UIAction(title: "Open Task", image: UIImage(systemName: "checklist")) { _ in self?.send(["ev": "rvTask", "tid": tid]) })
      return UIMenu(children: acts)
    }
    return it
  }
  private func reviewItem(_ id: String) -> ([String: Any], Bool, Int, Int)? {
    guard let m = model["reviews"] as? [String: Any] else { return nil }
    let wait = ((m["waiting"] as? [[String: Any]]) ?? []).filter { !rvGone.contains($0["id"] as? String ?? "") }, done = (m["reviewed"] as? [[String: Any]]) ?? []
    if let i = wait.firstIndex(where: { ($0["id"] as? String) == id }) { return (wait[i], false, i + 1, wait.count) }
    if let x = done.first(where: { ($0["id"] as? String) == id }) { return (x, true, 0, 0) }
    return nil
  }
  // A request: Apple's push, ‹ · "Review request · 1 of 3" and the task; the sender and the files large and swipeable on
  // the page, as now (D2 — a tap opens Quick Look); your note last round, the brief, Open Task as Apple's cells;
  // Request Amendments · Approve on Apple's toolbar (B1); no download on the iPhone (G2).
  private func reviewBlocks(_ h: HomeView, _ id: String, _ out: inout [UIView]) {
    let vc = pageVCs[ObjectIdentifier(h)]
    guard let it = reviewItem(id) else {
      h.drawAssetsBar(name: "Review request", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      vc?.setTools("", nil)
      // (gone while it's open — withdrawn, or the task closed elsewhere: the page goes back with a toast, as every page)
      if model["reviews"] != nil, !rvGone.contains(id), apple, let vc = vc, vc.appeared, AppData.shared.ready, vc.navigationController?.topViewController === vc {
        vc.navigationController?.popViewController(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.top?.toast(["t": "This request isn’t waiting any more"]) }
      }
      let w = part(h, "wait") { AppleEmpty() }; if model["reviews"] == nil { w.setLoading() } else { w.set("checkmark.circle", "Not Waiting", "This request isn’t waiting any more.") }; out.append(w); return
    }
    let (x, decided, n, of) = it
    h.drawAssetsBar(name: decided ? "Review request" : "Review request · \(n) of \(of)", sub: x["task"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    let tid = x["tid"] as? String ?? ""
    let hero = part(h, "hero") { ReviewHero() }
    hero.set(x, look: h.look)
    hero.onFile = { [weak self] fid in self?.send(["ev": "rvFile", "id": id, "fid": fid]) }
    out.append(hero)
    if decided, let r = x["res"] as? [String: Any] {
      var res = SetItem(key: "res", title: r["long"] as? String ?? "", sub: "Decided " + ((x["sub"] as? String ?? "").components(separatedBy: " · ").last ?? ""), chevron: false)
      res.bold = true
      out.append(head(h, "rvres", "")); out.append(group(h, "rvres", [res]))
      if let note = x["note"] as? String, !note.isEmpty { out.append(head(h, "rvnote", "Your note")); out.append(group(h, "rvnote", [SetItem(key: "note", title: note, chevron: false)])) }
    }
    if !decided, let last = x["last"] as? String, !last.isEmpty { out.append(head(h, "rvlast", "Your note last round")); out.append(group(h, "rvlast", [SetItem(key: "last", title: last, chevron: false)])) }
    if let b = x["brief"] as? String, !b.isEmpty { out.append(head(h, "rvbrief", "Brief")); out.append(group(h, "rvbrief", [SetItem(key: "brief", title: b, chevron: false)])) }
    out.append(head(h, "rvtask", ""))
    out.append(group(h, "rvtask", [SetItem(key: "task", title: "Open Task", sub: "", sym: "checklist", col: .systemBlue, tap: { [weak self] in self?.send(["ev": "rvTask", "tid": tid]) })]))
    if decided { out.append(foot(h, "rvleave", "Leaves Reviewed 15 days after it was decided.")) }
    guard !decided else { vc?.setTools("", nil); return }
    // (Request Amendments · Approve on Apple's toolbar — Approve Apple's prominent button)
    vc?.setTools("rv|\(id)") { [weak self] in
      let amend = UIBarButtonItem(title: "Request Amendments", primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.rvAmend(x) })
      amend.tintColor = .systemOrange
      let ok = UIBarButtonItem(title: "Approve", primaryAction: UIAction { _ in self?.rvApprove(x) })
      if #available(iOS 26.0, *) { ok.style = .prominent; ok.tintColor = .systemGreen } else { ok.style = .done; ok.tintColor = .systemGreen }
      return [amend, .flexibleSpace(), ok]
    }
  }
  // the requests decided here, gone from Waiting at once — until the server's answer (a no brings it back with why)
  private var rvGone: Set<String> = []
  // after a decision: back to the list, the decided one fading out of Waiting (F2)
  private func rvDecided(_ id: String) {
    rvGone.insert(id)
    if let s = stack.last, s.kind == "review", s.id == id, let vc = pageVCs[ObjectIdentifier(s.h)] { vc.navigationController?.popViewController(animated: true) }
    if let root = stack.first, root.kind == "reviews" { draw(root) }
  }
  private func rvBack(_ id: String, _ why: String?) {
    rvGone.remove(id)
    if let root = stack.first, root.kind == "reviews" { draw(root) }
    top?.toast(["t": why ?? "That didn’t work — try again"])
  }
  private func rvApprove(_ x: [String: Any]) {
    let id = x["id"] as? String ?? "", first = x["first"] as? String ?? ""
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    rvDecided(id)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.top?.toast(["t": "Approved — \(first) told"]) }
    request(["ev": "rvApprove", "id": id]) { [weak self] r in
      if (r["ok"] as? Bool) == true { self?.rvGone.remove(id) } else { self?.rvBack(id, r["error"] as? String) }
    }
  }
  private func rvAmend(_ x: [String: Any]) {
    let id = x["id"] as? String ?? "", first = x["first"] as? String ?? "", files = (x["files"] as? [[String: Any]]) ?? []
    let vc = AmendSheetVC(files: files, first: first)
    vc.onFile = { [weak self] fid in self?.send(["ev": "rvFile", "id": id, "fid": fid]) }
    vc.onSend = { [weak self] need, note, done in
      var ev: [String: Any] = ["ev": "rvAmend", "id": id, "note": note]
      if let n = need { ev["need"] = n }
      // (at once: the sheet goes, the request leaves Waiting; the server's answer then)
      done(nil)
      let okN = files.count - (need?.count ?? files.count)
      self?.rvDecided(id)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self?.top?.toast(["t": okN > 0 ? "\(okN) approved · \(need?.count ?? 0) sent back to \(first)" : "Sent back to \(first)"]) }
      self?.request(ev) { r in if (r["ok"] as? Bool) == true { self?.rvGone.remove(id) } else { self?.rvBack(id, r["error"] as? String) } }
    }
    main.topMost().present(vc.inNav(), animated: true)
  }
  // ---------- an Office Admin's Claims — fully Apple (Haris 2026-11-11 07:25, the mock-up "Remaining pages — fully Apple":
  //  B1 · C1 · D1 · E1) ----------
  // Its tab (MeTabVC "fin-reimb"): Apple's big title "Claims", its line the month, how many and the total; Apple's search
  // (by name); ••• Apple's menu — Mark All HR Approved, Set All Paid On… (Finance Admins) and Month (the last 12, as the
  // website); Need Approval · All as Apple's segmented control at the top of the list; each claim Apple's cell (the
  // person, what's in it, the amount, its status in its colour — ours), Apple's swipes (right: HR Approved, left: Paid
  // On…), touch and hold: Apple's menu (Open Claim, Share PDF, HR Approved, Paid On…); a tap opens its page (E1). Under All:
  // No claims and Not answered yet (D1).
  private var clMonth: String?, clQ = ""
  private func clPill(_ r: [String: Any]) -> [(String, UIColor)] {
    let t = r["pill"] as? String ?? ""
    guard !t.isEmpty else { return [] }
    return [(t, r["pk"] as? String == "paid" ? .systemGreen : r["pk"] as? String == "ok" ? .systemBlue : .systemOrange)]
  }
  private func claimItem(_ h: HomeView, _ r: [String: Any], admin: Bool) -> SetItem {
    let id = r["id"] as? String ?? "", st = r["st"] as? String ?? ""
    let legacy = (r["legacy"] as? Bool) == true
    let inv = r["inv"] as? [String: Any]
    let tap: (() -> Void)?
    if !legacy { tap = { [weak self] in self?.open("claim", id) } }
    else if let f = inv { tap = { [weak self] in self?.openOne(f["path"] as? String ?? "", f["name"] as? String ?? "Invoice") } }
    else { tap = nil }
    var it = SetItem(key: "c." + id, title: r["name"] as? String ?? "", sub: r["sub"] as? String ?? "", value: r["amt"] as? String ?? "", chevron: tap != nil, pills: clPill(r), tap: tap)
    it.person = (photo: r["photo"] as? String, ini: r["ini"] as? String ?? "", rgb: NativeSheetVC.color(r["rgb"]) ?? .systemGray)
    guard !legacy else { return it }
    if admin, st == "submitted" { it.lead = [MeSwipe(title: "HR Approved", sym: "checkmark", col: TaskSwipe.green) { [weak self, weak h] fin in fin(true); self?.clApprove(h, [id]) }] }
    if admin, st != "paid" { it.trail = [MeSwipe(title: "Paid On…", sym: "calendar", col: .systemBlue) { [weak self, weak h] fin in fin(true); self?.paidOn(h, [id], sub: "\(r["name"] as? String ?? "") · \(r["amt"] as? String ?? "")") }] }
    it.menu = { [weak self, weak h] in
      guard self != nil else { return nil }
      var a: [UIMenuElement] = [UIAction(title: "Open Claim", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.open("claim", id) },
                                UIAction(title: "Share PDF", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.claimPdf(id) }]
      var b: [UIMenuElement] = []
      if admin, st == "submitted" { b.append(UIAction(title: "HR Approved", image: UIImage(systemName: "checkmark.circle")) { [weak self, weak h] _ in self?.clApprove(h, [id]) }) }
      if admin, st != "paid" { b.append(UIAction(title: "Paid On…", image: UIImage(systemName: "calendar")) { [weak self, weak h] _ in self?.paidOn(h, [id], sub: "\(r["name"] as? String ?? "") · \(r["amt"] as? String ?? "")") }) }
      if !b.isEmpty { a.append(UIMenu(options: .displayInline, children: b)) }
      return UIMenu(children: a)
    }
    return it
  }
  private func claimsBlocks(_ h: HomeView, _ out: inout [UIView]) {
    guard let m = model["claims"] as? [String: Any] else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    let need = (m["need"] as? [[String: Any]]) ?? [], all = (m["all"] as? [[String: Any]]) ?? []
    let admin = (m["admin"] as? Bool) == true
    if h.assets == "claimsTab", let vc = MeTabVC.byKey["fin-reimb"] {
      vc.onSearch = { [weak self, weak h] q in guard let self = self, let h = h, self.clQ != q else { return }; self.clQ = q; self.blocks(h) }
      vc.useMore { [weak self, weak h] in self?.claimsMenu(h) ?? [] }
    }
    // (a claim from the Inbox: its list picked — Need approval if it waits there, else All — shown and lit a moment;
    //  another month on show: back to the claim month, where it is)
    var focus: String? = nil
    if let fid = clFocus {
      clFocus = nil
      if need.contains(where: { ($0["id"] as? String) == fid }) { clSeg = 0; focus = fid } else if all.contains(where: { ($0["id"] as? String) == fid }) { clSeg = 1; focus = fid }
      else if clMonth != nil { clMonth = nil; clFocus = fid; DispatchQueue.main.async { [weak self] in self?.redraw() } }
      clQ = ""
    }
    let q = clQ.trimmingCharacters(in: .whitespaces)
    if !q.isEmpty {
      let f = Find.filter(all, q) { "\($0["name"] ?? "") \($0["sub"] ?? "")" }
      if f.items.isEmpty { let n = part(h, "none") { AppleEmpty() }; n.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); out.append(n); return }
      out.append(head(h, "cls", f.loose ? "Close matches" : "Claims · \(f.items.count)"))
      let g = group(h, "cls", f.items.map { claimItem(h, $0, admin: admin) }); Find.mark([g], f.marks); out.append(g)
      return
    }
    let seg = part(h, "seg") { SegBlock() }
    seg.set("Need Approval · \(need.count)", "All · \(all.count)", clSeg)
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h else { return }; self.clSeg = i; self.blocks(h) }
    out.append(seg)
    let rows = clSeg == 0 ? need : all
    if rows.isEmpty {
      let n = part(h, "cl0") { AppleEmpty() }
      if clSeg == 0 { n.set("checkmark.circle", "All Caught Up", "No claims are waiting for HR approval.") } else { n.set("doc.text", "No Claims Yet", "Claims sent from the app for \(m["label"] as? String ?? "this month") show here.") }
      out.append(n)
    } else {
      out.append(head(h, "cl", ""))
      out.append(group(h, "cl", rows.map { claimItem(h, $0, admin: admin) }))
      out.append(foot(h, "cl", (m["foot"] as? String ?? "") + (admin ? " Swipe right for HR Approved, left for Paid On…" : "")))
    }
    // (D1 — as the website's Finance page: who said they have none, and who hasn't answered while the month is open)
    if clSeg == 1 {
      let none = (m["none"] as? [[String: Any]]) ?? [], waiting = (m["waiting"] as? [[String: Any]]) ?? []
      let person = { (p: [String: Any]) -> SetItem in var it = SetItem(key: p["id"] as? String ?? "", title: p["name"] as? String ?? "", chevron: false); it.person = (photo: p["photo"] as? String, ini: p["ini"] as? String ?? "", rgb: NativeSheetVC.color(p["rgb"]) ?? .systemGray); it.dim = true; return it }
      if !none.isEmpty { out.append(head(h, "cln", "No claims · \(none.count)")); out.append(group(h, "cln", none.map(person))) }
      if !waiting.isEmpty { out.append(head(h, "clw", "Not answered yet · \(waiting.count)")); out.append(group(h, "clw", waiting.map(person))); out.append(foot(h, "clw", "They can still send theirs from the app until the 27th.")) }
    }
    if let fid = focus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak h] in h?.meFlash("c." + fid) } }
    h.setFab("Add claim", "plus", admin ? { [weak self, weak h] in if let h = h { self?.addClaim(h, m) } } : nil)
  }
  // Claims' •••: Mark All HR Approved and Set All Paid On… (the month on show, Finance Admins — the website's two buttons),
  // then the month (the last 12)
  private func claimsMenu(_ h: HomeView?) -> [UIMenuElement] {
    guard let m = model["claims"] as? [String: Any] else { return [] }
    let all = (m["all"] as? [[String: Any]]) ?? []
    let open = all.filter { ($0["legacy"] as? Bool) != true && ($0["st"] as? String) != "paid" }.compactMap { $0["id"] as? String }
    let sub = all.filter { ($0["st"] as? String) == "submitted" }.compactMap { $0["id"] as? String }
    var out: [UIMenuElement] = []
    if (m["admin"] as? Bool) == true {
      let a = UIAction(title: "Mark All HR Approved", image: UIImage(systemName: "checkmark.circle"), attributes: sub.isEmpty ? .disabled : []) { [weak self, weak h] _ in self?.clApprove(h, sub) }
      let p = UIAction(title: "Set All Paid On…", image: UIImage(systemName: "calendar"), attributes: open.isEmpty ? .disabled : []) { [weak self, weak h] _ in self?.paidOn(h, open, sub: "\(open.count) claim\(open.count == 1 ? "" : "s") · \(m["label"] as? String ?? "")") }
      out.append(UIMenu(options: .displayInline, children: [a, p]))
    }
    let cur = m["month"] as? String ?? ""
    let months = ((m["pick"] as? [[String: Any]]) ?? []).map { x -> UIAction in
      let v = x["m"] as? String ?? ""
      return UIAction(title: x["t"] as? String ?? v, state: v == cur ? .on : .off) { [weak self] _ in
        guard let self = self, v != cur else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        self.clMonth = v; self.redraw()
      }
    }
    out.append(UIMenu(title: "Month", options: .displayInline, children: months))
    return out
  }
  // HR approved — one claim or all at once: shown at once (the rule "what you do shows at once"), the server's answer then
  private func clApprove(_ h: HomeView?, _ ids: [String]) {
    guard !ids.isEmpty else { return }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    request(["ev": "clApprove", "ids": ids]) { r in
      if (r["ok"] as? Bool) == true { h?.toast(["t": (r["text"] as? String) ?? (ids.count > 1 ? "\(ids.count) claims marked HR approved" : "Marked HR approved")]) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) }
    }
  }
  // Paid on — iPhone's own calendar (as the website, a submitted one is HR approved with it); one claim or all at once
  private func paidOn(_ h: HomeView?, _ ids: [String], sub: String = "") {
    guard !ids.isEmpty else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let fmt = DateFormatter(); fmt.calendar = Calendar(identifier: .gregorian); fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyy-MM-dd"
    main.topMost().present(DateSheetVC(["value": fmt.string(from: Date()), "min": "", "max": "", "clearable": false, "md": false, "title": "Paid on", "sub": sub]) { [weak self, weak h] r in
      if (r["cancel"] as? Bool) == true || (r["ok"] as? Bool) == false { return }
      guard let d = r["date"] as? String, !d.isEmpty else { return }
      self?.request(["ev": "clPaid", "ids": ids, "date": d]) { r in if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.toast(["t": (r["text"] as? String) ?? "Marked paid"]) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } }
    }, animated: true)
  }
  // a claim's PDF, made by the server (its sheet, receipts and signature) — shared with iPhone's own share sheet
  private func claimPdf(_ id: String) {
    top?.toast(["t": "Preparing the PDF…"])
    main.serverTask.request("/api/app/claimPdf", body: ["id": id]) { [weak self] r in
      guard let self = self else { return }
      guard let r = r, (r["ok"] as? Bool) == true, let p = r["path"] as? String else { self.top?.toast(["t": r?["error"] as? String ?? "Could not make the PDF"]); return }
      let name = r["name"] as? String ?? "Expense claim.pdf"
      let url = "/__file/" + p.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
      FeedLoader.shared.data(url) { [weak self] d in
        DispatchQueue.main.async {
          guard let self = self else { return }
          guard let d = d, !d.isEmpty else { self.top?.toast(["t": "Couldn’t get the PDF — try again"]); return }
          let f = FileManager.default.temporaryDirectory.appendingPathComponent(name)
          try? d.write(to: f, options: .atomic)
          let a = UIActivityViewController(activityItems: [f], applicationActivities: nil)
          a.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: f) }
          if let pop = a.popoverPresentationController { pop.sourceView = self.main.view; pop.sourceRect = CGRect(x: self.main.view.bounds.midX, y: self.main.view.bounds.midY, width: 1, height: 1) }
          self.main.topMost().present(a, animated: true)
        }
      }
    }
  }
  // A claim opened (E1): pushed — the person and its total, its items under their day (a tap opens the receipt in Quick
  // Look, swiping through all of them), Share PDF; Paid On… · HR Approved on Apple's toolbar (Finance Admins)
  private func claimBlocks(_ h: HomeView, _ id: String, _ out: inout [UIView]) {
    let vc = pageVCs[ObjectIdentifier(h)]
    guard let c = model["claim"] as? [String: Any], (c["id"] as? String) == id else {
      h.drawAssetsBar(name: "Claim", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      vc?.setTools("", nil)
      let w = part(h, "wait") { AppleEmpty() }; w.setLoading(); out.append(w); return
    }
    if (c["gone"] as? Bool) == true {
      vc?.setTools("", nil)
      // (gone while it's open — deleted, or taken back: the page goes back with a toast, as every page)
      if apple, let vc = vc, vc.appeared, vc.navigationController?.topViewController === vc {
        vc.navigationController?.popViewController(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.top?.toast(["t": "This claim isn’t here any more"]) }
      }
      let w = part(h, "wait") { AppleEmpty() }; w.set("doc.text", "Not Here", "This claim isn’t here any more."); out.append(w); return
    }
    let st = c["st"] as? String ?? "", admin = (c["admin"] as? Bool) == true
    h.drawAssetsBar(name: c["name"] as? String ?? "Claim", sub: "\(c["month"] as? String ?? "") · \(c["pill"] as? String ?? "")", logo: nil, rgb: nil, ini: nil, showLogo: false)
    var who = SetItem(key: "who", title: c["name"] as? String ?? "", sub: c["sub"] as? String ?? "", value: c["amt"] as? String ?? "", chevron: false, pills: clPill(["pill": c["pill"] ?? "", "pk": st == "paid" ? "paid" : st == "approved" ? "ok" : "sub"]))
    who.person = (photo: c["photo"] as? String, ini: c["ini"] as? String ?? "", rgb: NativeSheetVC.color(c["rgb"]) ?? .systemGray)
    who.bold = true
    out.append(head(h, "who", "")); out.append(group(h, "who", [who]))
    let groups = (c["groups"] as? [[String: Any]]) ?? []
    let receipts: [[String: Any]] = groups.flatMap { ($0["items"] as? [[String: Any]]) ?? [] }.compactMap { i in (i["receipt"] as? [String: Any]).map { ["id": $0["path"] ?? "", "path": $0["path"] ?? "", "name": $0["name"] ?? "Receipt", "size": $0["size"] ?? 0] } }
    for (gi, g) in groups.enumerated() {
      let items = ((g["items"] as? [[String: Any]]) ?? []).map { i -> SetItem in
        let rc = i["receipt"] as? [String: Any], path = rc?["path"] as? String ?? ""
        var it = SetItem(key: i["id"] as? String ?? "", title: i["desc"] as? String ?? "", value: i["amt"] as? String ?? "", chevron: false,
                         tap: rc == nil ? nil : { [weak self] in if let at = receipts.firstIndex(where: { ($0["path"] as? String) == path }) { self?.main.openFiles(receipts, at: at) } })
        if rc != nil { it.sym = "paperclip"; it.col = .systemGray }
        return it
      }
      out.append(head(h, "g\(gi)", g["head"] as? String ?? ""))
      out.append(group(h, "g\(gi)", items))
    }
    if !receipts.isEmpty { out.append(foot(h, "rc", "A tap on an item opens its receipt.")) }
    out.append(head(h, "pdf", ""))
    out.append(group(h, "pdf", [SetItem(key: "pdf", title: "Share PDF", sym: "square.and.arrow.up", col: .systemBlue, chevron: false, tap: { [weak self] in self?.claimPdf(id) })]))
    out.append(foot(h, "pdf", "The claim as the website’s PDF, with its receipts and signature."))
    guard admin, st != "paid" else { vc?.setTools("", nil); return }
    let nm = "\(c["name"] as? String ?? "") · \(c["amt"] as? String ?? "")"
    vc?.setTools("cl|\(id)|\(st)") { [weak self, weak h] in
      let paid = UIBarButtonItem(title: "Paid On…", primaryAction: UIAction { _ in self?.paidOn(h, [id], sub: nm) })
      guard st == "submitted" else { return [.flexibleSpace(), paid] }
      let ok = UIBarButtonItem(title: "HR Approved", primaryAction: UIAction { _ in self?.clApprove(h, [id]) })
      if #available(iOS 26.0, *) { ok.style = .prominent; ok.tintColor = .systemGreen } else { ok.style = .done; ok.tintColor = .systemGreen }
      return [paid, .flexibleSpace(), ok]
    }
  }
  private func addClaim(_ h: HomeView, _ m: [String: Any]) {
    let people = ((m["people"] as? [[String: Any]]) ?? []).map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") }
    let months = ((m["months"] as? [[String: Any]]) ?? []).map { ($0["m"] as? String ?? "", $0["t"] as? String ?? "") }
    let vc = MoneyFormVC(kind: .claim, people: people, months: months, cookies: main.serverHome.cookies)
    vc.onPerson = { [weak self] name, done in self?.request(["ev": "clPerson", "name": name]) { r in if (r["ok"] as? Bool) == true { done(r["id"] as? String, r["name"] as? String) } else { done(nil, nil) } } }
    vc.onSave = { [weak self, weak h] f, done in
      self?.request(["ev": "clAdd", "who": f["who"] ?? "", "amount": f["amount"] ?? "", "month": f["month"] ?? "", "pdf": f["file"] ?? NSNull()]) { r in
        if (r["ok"] as? Bool) == true { done(nil); h?.toast(["t": "Added — it waits for HR approval"]) } else { done(r["error"] as? String ?? "That didn’t work — try again") } }
    }
    main.topMost().present(vc.inNav(), animated: true)
  }
  // ---------- an Office Admin's Expenses — fully Apple (the mock-up's B1 · F1) ----------
  // Its tab (MeTabVC "fin-expenses"): Apple's big title "Expenses" and its line; Apple's search; Subscriptions · Office
  // Expenses as Apple's segmented control; each one Apple's cell — a subscription's billing day and its invoices (this
  // month's, the months still missing one), touch and hold: its invoice, Add … Invoice, Delete Subscription; the ended ones
  // their own faded group (F1). Office expenses: the month picked in ••• (the last 12, B1), a tap opens the invoice or adds
  // it, Apple's swipe to Delete, touch and hold: Invoice / Add Invoice, Delete. "+ Add …" as Home's + New task.
  private var exMonth: String?, exQ = ""
  private func subItem(_ h: HomeView, _ x: [String: Any], admin: Bool) -> SetItem {
    let id = x["id"] as? String ?? "", ended = (x["ended"] as? Bool) == true
    let inv = x["invFile"] as? [String: Any]
    let lk = x["lk"] as? String ?? ""
    var tap: (() -> Void)? = nil
    if !ended, let f = inv { tap = { [weak self] in self?.openOne(f["path"] as? String ?? "", f["name"] as? String ?? "Invoice") } }
    var it = SetItem(key: "s." + id, title: x["name"] as? String ?? "", sub: x["sub"] as? String ?? "", value: x["amt"] as? String ?? "", sym: "arrow.triangle.2.circlepath", col: ended ? .systemGray : .systemIndigo, chevron: false, tap: tap)
    let lc: UIColor = lk == "miss" ? UIColor.systemOrange : lk == "ok" ? UIColor.systemGreen : UIColor.secondaryLabel
    it.line3 = (x["line"] as? String ?? "", lc)
    it.dim = ended
    guard admin, !ended else { return it }
    it.menu = { [weak self, weak h] in
      guard let self = self else { return nil }
      var a: [UIMenuElement] = []
      let nowName = x["nowName"] as? String ?? "", nowM = x["nowMonth"] as? String ?? ""
      if let f = inv { a.append(UIAction(title: "Open \(nowName) Invoice", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.openOne(f["path"] as? String ?? "", f["name"] as? String ?? "Invoice") }) }
      else { a.append(self.invoiceMenu("Add \(nowName) Invoice", h, id: id, month: nowM, folder: "Subscriptions")) }
      for m in (x["missing"] as? [[String: Any]]) ?? [] { a.append(self.invoiceMenu("Add \(m["t"] as? String ?? "") Invoice", h, id: id, month: m["m"] as? String ?? "", folder: "Subscriptions")) }
      a.append(UIMenu(options: .displayInline, children: [UIAction(title: "Delete Subscription", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self, weak h] _ in self?.endSub(h, id, x["name"] as? String ?? "this subscription") }]))
      return UIMenu(children: a)
    }
    return it
  }
  private func officeItem(_ h: HomeView, _ x: [String: Any], admin: Bool) -> SetItem {
    let id = x["id"] as? String ?? "", inv = x["invFile"] as? [String: Any], month = x["month"] as? String ?? ""
    var it = SetItem(key: "o." + id, title: x["name"] as? String ?? "", sub: x["sub"] as? String ?? "", value: x["amt"] as? String ?? "", sym: "doc.text.fill", col: .systemGray, chevron: false,
                     tap: inv != nil ? { [weak self] in self?.openOne(inv?["path"] as? String ?? "", inv?["name"] as? String ?? "Invoice") } : nil)
    it.line3 = inv != nil ? ("Invoice", UIColor.secondaryLabel) : (admin ? "No invoice — hold to add it" : "No invoice", UIColor.systemOrange)
    guard admin else { return it }
    it.trail = [MeSwipe(title: "Delete", sym: "trash", col: .systemRed, destructive: true) { [weak self, weak h] fin in self?.delExpense(h, id, x["name"] as? String ?? "this expense", fin) }]
    it.menu = { [weak self, weak h] in
      guard let self = self else { return nil }
      var a: [UIMenuElement] = []
      if let f = inv { a.append(UIAction(title: "Open Invoice", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.openOne(f["path"] as? String ?? "", f["name"] as? String ?? "Invoice") }) }
      else { a.append(self.invoiceMenu("Add Invoice", h, id: id, month: month, folder: "Expenses")) }
      a.append(UIMenu(options: .displayInline, children: [UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self, weak h] _ in self?.delExpense(h, id, x["name"] as? String ?? "this expense", nil) }]))
      return UIMenu(children: a)
    }
    return it
  }
  private func expensesBlocks(_ h: HomeView, _ out: inout [UIView]) {
    guard let m = model["expenses"] as? [String: Any] else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    let subs = (m["subs"] as? [[String: Any]]) ?? [], ended = (m["ended"] as? [[String: Any]]) ?? [], office = (m["office"] as? [[String: Any]]) ?? []
    let admin = (m["admin"] as? Bool) == true
    if h.assets == "expensesTab", let vc = MeTabVC.byKey["fin-expenses"] {
      vc.onSearch = { [weak self, weak h] q in guard let self = self, let h = h, self.exQ != q else { return }; self.exQ = q; self.blocks(h) }
      if exSeg == 1 { vc.useMore { [weak self] in self?.expensesMenu() ?? [] } } else { vc.useMore(nil) }
    }
    let q = exQ.trimmingCharacters(in: .whitespaces)
    if !q.isEmpty {
      let f = Find.filter(subs + office, q) { "\($0["name"] ?? "") \($0["sub"] ?? "")" }
      if f.items.isEmpty { let n = part(h, "none") { AppleEmpty() }; n.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); out.append(n); return }
      out.append(head(h, "exf", f.loose ? "Close matches" : "Found · \(f.items.count)"))
      let g = group(h, "exf", f.items.map { x in x["month"] != nil ? officeItem(h, x, admin: admin) : subItem(h, x, admin: admin) }); Find.mark([g], f.marks); out.append(g)
      return
    }
    let seg = part(h, "seg") { SegBlock() }
    seg.set("Subscriptions · \(subs.count)", "Office Expenses · \(office.count)", exSeg)
    seg.onPick = { [weak self, weak h] i in guard let self = self, let h = h else { return }; self.exSeg = i; if let s = self.stack.first(where: { $0.h === h }) { self.draw(s) }; self.blocks(h) }
    out.append(seg)
    if exSeg == 0 {
      if subs.isEmpty { let n = part(h, "ex0") { AppleEmpty() }; n.set("arrow.triangle.2.circlepath", "No Subscriptions", "Monthly subscriptions you add are recorded as an expense on their billing day."); out.append(n) }
      else {
        out.append(head(h, "exs", ""))
        out.append(group(h, "exs", subs.map { subItem(h, $0, admin: admin) }))
        out.append(foot(h, "exs", "Each is recorded as an expense on its billing day." + (admin ? " Touch and hold one for its invoices." : "")))
      }
      if !ended.isEmpty { out.append(head(h, "exe", "Ended · \(ended.count)")); out.append(group(h, "exe", ended.map { subItem(h, $0, admin: admin) })); out.append(foot(h, "exe", "Past months stay in the records.")) }
    } else {
      if office.isEmpty { let n = part(h, "ex0") { AppleEmpty() }; n.set("doc.text", "No Office Expenses", "Nothing added for \(m["omName"] as? String ?? "this month") yet."); out.append(n) }
      else {
        out.append(head(h, "exo", ""))
        out.append(group(h, "exo", office.map { officeItem(h, $0, admin: admin) }))
        out.append(foot(h, "exo", admin ? "Swipe left to delete. Touch and hold for the invoice." : ""))
      }
    }
    h.setFab(exSeg == 0 ? "Add subscription" : "Add office expense", "plus", admin ? { [weak self, weak h] in if let h = h { self?.addExpense(h, sub: self?.exSeg == 0) } } : nil)
  }
  // Office Expenses' •••: the month (the last 12)
  private func expensesMenu() -> [UIMenuElement] {
    guard let m = model["expenses"] as? [String: Any] else { return [] }
    let cur = m["om"] as? String ?? ""
    let months = ((m["pick"] as? [[String: Any]]) ?? []).map { x -> UIAction in
      let v = x["m"] as? String ?? ""
      return UIAction(title: x["t"] as? String ?? v, state: v == cur ? .on : .off) { [weak self] _ in
        guard let self = self, v != cur else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        self.exMonth = v; self.redraw()
      }
    }
    return [UIMenu(title: "Month", options: .displayInline, children: months)]
  }
  // an invoice added afterwards (the website's subInvoice / txInvoice): picked from Files, Photos or the Camera — Apple's
  // menu — sent up into Finance/<folder>/<month>, then saved on the record
  private func invoiceMenu(_ title: String, _ h: HomeView?, id: String, month: String, folder: String) -> UIMenu {
    let src = [("Files", "folder", "files"), ("Photos", "photo.on.rectangle", "photos"), ("Camera", "camera", "camera")].map { t in
      UIAction(title: t.0, image: UIImage(systemName: t.1)) { [weak self, weak h] _ in self?.addInvoice(h, id: id, month: month, folder: folder, source: t.2) }
    }
    return UIMenu(title: title, image: UIImage(systemName: "paperclip"), children: src)
  }
  private func addInvoice(_ h: HomeView?, id: String, month: String, folder: String, source: String) {
    Picker.shared.pick(from: main.topMost(), single: true, source: source) { [weak self, weak h] r in
      guard let self = self, let x = ((r["files"] as? [[String: Any]]) ?? []).first, let tok = x["token"] as? String, let url = Picker.shared.url(tok) else { return }
      let name = x["name"] as? String ?? "Invoice"
      let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
      h?.toast(["t": "Adding the invoice…"])
      Uploader.send(url, name: name, task: "", dest: "Finance/\(folder)/\(month)", cookies: self.main.serverHome.cookies, progress: { _ in }) { [weak self, weak h] path in
        guard let self = self else { return }
        guard let p = path else { h?.toast(["t": "Couldn’t upload — try again"]); return }
        self.request(["ev": "exInv", "id": id, "month": month, "invoice": ["path": p, "name": name, "size": size]]) { r in
          if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.toast(["t": (r["text"] as? String) ?? "Invoice added"]) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) }
        }
      }
    }
  }
  private func endSub(_ h: HomeView?, _ id: String, _ name: String) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let today = Date().formatted(.dateTime.month(.abbreviated).day())
    let a = UIAlertController(title: "Delete \(name)?", message: "It ends today, \(today). It won’t be counted from next month — this month only if its billing day has passed. Months already recorded stay.", preferredStyle: .actionSheet)
    a.addAction(UIAlertAction(title: "Delete Subscription", style: .destructive) { [weak self, weak h] _ in
      self?.request(["ev": "exEnd", "id": id]) { r in if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success); h?.toast(["t": "Subscription deleted"]) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } }
    })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let pop = a.popoverPresentationController { pop.sourceView = main.view; pop.sourceRect = CGRect(x: main.view.bounds.midX, y: main.view.bounds.maxY - 80, width: 1, height: 1) }
    main.topMost().present(a, animated: true)
  }
  // an office expense removed (the website's remove: it no longer counts) — asked first, as the website
  private func delExpense(_ h: HomeView?, _ id: String, _ name: String, _ fin: ((Bool) -> Void)?) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let a = UIAlertController(title: "Remove \(name)?", message: "It will no longer count in the expenses.", preferredStyle: .actionSheet)
    a.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self, weak h] _ in
      fin?(true)
      self?.request(["ev": "exDel", "id": id]) { r in if (r["ok"] as? Bool) == true { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } }
    })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in fin?(false) })
    if let pop = a.popoverPresentationController { pop.sourceView = main.view; pop.sourceRect = CGRect(x: main.view.bounds.midX, y: main.view.bounds.maxY - 80, width: 1, height: 1) }
    main.topMost().present(a, animated: true)
  }
  private func addExpense(_ h: HomeView, sub: Bool?) {
    let isSub = sub == true
    let vc = MoneyFormVC(kind: isSub ? .sub : .expense, people: [], months: [], cookies: main.serverHome.cookies)
    vc.onSave = { [weak self, weak h] f, done in
      var ev: [String: Any] = ["ev": "exAdd", "kind": isSub ? "sub" : "expense", "name": f["name"] ?? "", "amount": f["amount"] ?? "", "invoice": f["file"] ?? NSNull()]
      if isSub { ev["day"] = f["day"] ?? 1 } else { ev["date"] = f["date"] ?? "" }
      self?.request(ev) { r in if (r["ok"] as? Bool) == true { done(nil); h?.toast(["t": isSub ? "Subscription added" : "Office expense added"]) } else { done(r["error"] as? String ?? "That didn’t work — try again") } }
    }
    main.topMost().present(vc.inNav(), animated: true)
  }
  private func teamBlocks(_ h: HomeView, _ out: inout [UIView]) {
    let t = team
    let admin = (t["admin"] as? Bool) == true
    let line = t.isEmpty ? "" : "\(t["active"] as? Int ?? 0) active · \(t["pastN"] as? Int ?? 0) past"
    if h.assets != "teamTab" { h.drawAssetsBar(name: "Team members", sub: line, logo: nil, rgb: nil, ini: nil, showLogo: false) }
    if t.isEmpty { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    // (Apple's own search in Apple's bar, Active · Past as its scope bar — Me › Team members pushed, or an Office Admin's own
    //  Team tab; Add member: Apple's + in the bar on the pushed page, "+ Add member" as Home's + New task on the tab — the
    //  approved mock-up "Team members — fully Apple", Haris 2026-11-10)
    let scopes = ["Active · \(t["active"] as? Int ?? 0)", "Past · \(t["pastN"] as? Int ?? 0)"]
    let onSearch: (String) -> Void = { [weak self, weak h] q in guard let self = self, let h = h, self.teamQ != q else { return }; self.teamQ = q; self.blocks(h) }
    let onScope: (Int) -> Void = { [weak self, weak h] i in guard let self = self, let h = h, self.teamTab != i else { return }; self.teamTab = i; self.blocks(h) }
    if let vc = pageVCs[ObjectIdentifier(h)] {
      vc.useSearch("Search people", scopes: scopes, selected: teamTab)
      vc.onSearch = onSearch; vc.onScope = onScope
      vc.usePlus(admin ? { [weak self] in self?.addMember() } : nil)
    } else if h.assets == "teamTab", let vc = MeTabVC.byKey["team"] {
      vc.useScopes(scopes, selected: teamTab)
      vc.onSearch = onSearch; vc.onScope = onScope
      if admin { h.setFab("Add member", "plus", { [weak self] in self?.addMember() }) }
    }
    let norm = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let q = norm(teamQ.trimmingCharacters(in: .whitespaces))
    // (typos forgiven, the words marked — every search alike: Haris 2026-11-06)
    let everyone = ((t["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["people"] as? [[String: Any]]) ?? [] } + ((t["past"] as? [[String: Any]]) ?? [])
    let tf = Find.filter(everyone, q) { "\($0["name"] ?? "") \($0["email"] ?? "") \($0["role"] ?? "")" }
    let keep = Set(tf.items.compactMap { $0["id"] as? String })
    teamMarks = q.isEmpty ? [] : tf.marks
    let fits = { (p: [String: Any]) -> Bool in q.isEmpty || keep.contains(p["id"] as? String ?? "") }
    var any = false
    if teamTab == 0 {
      for g in (t["groups"] as? [[String: Any]]) ?? [] {
        let list = ((g["people"] as? [[String: Any]]) ?? []).filter(fits)
        guard !list.isEmpty else { continue }
        any = true
        let k = g["k"] as? String ?? ""
        out.append(head(h, "t." + k, "\(g["name"] as? String ?? "") · \(list.count)"))
        let gv = group(h, "t." + k, people(list, hold: admin)); Find.mark([gv], teamMarks)
        out.append(gv)
      }
    } else {
      let list = ((t["past"] as? [[String: Any]]) ?? []).filter(fits)
      if !list.isEmpty { any = true; out.append(head(h, "t.past", "Past members · \(list.count)")); let gv = group(h, "t.past", people(list, hold: admin)); Find.mark([gv], teamMarks); out.append(gv) }
      if !list.isEmpty, admin { out.append(foot(h, "pastnote", "Touch and hold someone to restore their access.")) }
    }
    if !any {
      let n = part(h, "none") { AppleEmpty() }
      if !q.isEmpty { n.set("magnifyingglass", "No Results", "Check the spelling or try a new search.") }
      else if teamTab == 1 { n.set("person.crop.circle.badge.clock", "No Past Members", "People you remove from the team show here, and you can restore their access.") }
      else { n.set("person.2", "No One Yet") }
      out.append(n)
    }
    // (what each role can do: its own page — the mock-up's B1. One for each list, so switching Active · Past fades it with
    //  the list instead of sliding it from where it was — Haris 2026-11-10: "come sliding in on tabs")
    out.append(head(h, "guide\(teamTab)", ""))
    out.append(group(h, "guide\(teamTab)", [SetItem(key: "guide", title: "What Each Role Can Do", sym: "info", col: .systemBlue, tap: { [weak self] in self?.open("roles") })]))
    out.append(foot(h, "note\(teamTab)", t["note"] as? String ?? ""))
  }
  // What Each Role Can Do (the mock-up's B1): each role and what it can do, as Apple's cells
  private func rolesBlocks(_ h: HomeView, _ out: inout [UIView]) {
    h.drawAssetsBar(name: "What Each Role Can Do", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    let guide = (team["guide"] as? [[Any]]) ?? []
    if guide.isEmpty { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    let items = guide.enumerated().map { i, g -> SetItem in
      var it = SetItem(key: "r.\(i)", title: g.first as? String ?? "", sub: g.count > 2 ? g[2] as? String ?? "" : "", sym: "person.fill", col: NativeSheetVC.color(g.count > 1 ? Optional(g[1]) : nil) ?? .systemGray, chevron: false)
      it.bold = true
      return it
    }
    out.append(head(h, "roles", "")); out.append(group(h, "roles", items))
  }
  // My profile (the locked mockup, Haris 2026-11-03): the photo, ABOUT YOU, ROLE, NOTIFICATIONS, NOTIFY ME ABOUT, the
  // CD's own, Owner view (the owner, live site). Everything is saved as it changes — no Save button.
  private func profileBlocks(_ h: HomeView, _ out: inout [UIView]) {
    h.drawAssetsBar(name: "My profile", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    guard let p = model["profile"] as? [String: Any] else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    let top = part(h, "photo") { ProfileHead() }
    top.set(p, look: h.look)
    top.onPick = { [weak self] src in self?.pfPhoto(src) }
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
    if t.isEmpty { let w = part(h, "wait") { AppleEmpty() }; w.setLoading(); out.append(w); return }
    // (in Apple's navigation: Apple's own search bar in Apple's bar; the kinds as Mail's buttons at the top of Apple's list,
    //  scrolling away with it, as the Inbox's — nothing of ours over Apple's bar: Haris 2026-11-08)
    if let vc = pageVCs[ObjectIdentifier(h)] {
      vc.useSearch("Search the Trash", scopes: [], selected: 0)
      vc.onSearch = { [weak self] q in guard let self = self, self.trQv != q else { return }; self.trQv = q; self.send(["ev": "trQ", "q": q]) }
      let cats = part(h, "cats") { CatsBlock(items: MeCtl.trashCats.map { c in MailCats.Item(key: c.0, sym: c.1, name: c.2, fill: c.0 == "all" ? MailCats.neutral : c.0 == "mine" ? MailCats.purple : MailCats.blue) }) }
      cats.choose((MeCtl.trashCats.firstIndex { $0.0 == (t["cat"] as? String ?? "all") }) ?? 0)
      cats.onPick = { [weak self] i in self?.trCatv = MeCtl.trashCats[i].0; self?.send(["ev": "trCat", "k": MeCtl.trashCats[i].0]) }
      out.append(cats)
    }
    let groups = (t["groups"] as? [[String: Any]]) ?? []
    let tq = t["q"] as? String ?? ""
    for g in groups {
      let items = (g["items"] as? [[String: Any]]) ?? []
      let k = g["name"] as? String ?? ""
      out.append(head(h, "tr." + k, "\(k) · \(items.count)"))
      let gv = group(h, "tr." + k, items.map { trashRow(h, $0) })
      // (the words searched for, marked — every search alike: Haris 2026-11-06)
      Find.mark([gv], tq.isEmpty ? [] : Find.filter(items, tq) { "\($0["t"] ?? "") \($0["s"] ?? "")" }.marks)
      out.append(gv)
    }
    if let none = t["none"] as? String, !none.isEmpty { let w = part(h, "none") { AppleEmpty() }
      // (Apple's own: a search with nothing found — No Results; the Trash empty — its title, the server's words under it)
      if !(t["q"] as? String ?? "").isEmpty { w.set("magnifyingglass", "No Results", "Check the spelling or try a new search.") }
      else { let parts = none.components(separatedBy: " — "); let rest = parts.dropFirst().joined(separator: " — "); w.set("trash", parts.count > 1 ? "Trash Is Empty" : none, rest.isEmpty ? nil : rest.prefix(1).uppercased() + rest.dropFirst()) }
      out.append(w) }
    out.append(foot(h, "trnote", t["note"] as? String ?? ""))
  }
  // one Trash item as Apple's cell: its kind's symbol (a file or folder: its own picture — G1), name, kind · where · who ·
  // when, days left (red near the end); Apple's swipes — right Restore, left Delete Forever (Super Admins); touch and hold:
  // Apple's menu
  private func trashRow(_ h: HomeView, _ x: [String: Any]) -> SetItem {
    let id = x["id"] as? String ?? "", type = x["type"] as? String ?? ""
    let col = (x["col"] as? [Int]).map { MeCtl.rgb($0) } ?? .systemGray
    let files = (x["files"] as? [[String: Any]]) ?? []
    let opens = (x["task"] as? Bool) == true || !files.isEmpty
    var it = SetItem(key: "t." + id, title: x["t"] as? String ?? "", sub: x["s"] as? String ?? "", sym: x["sym"] as? String ?? "trash.fill", col: col, chevron: false, tap: opens ? { [weak self] in self?.trashTap(id) } : nil)
    it.line3 = (x["left"] as? String ?? "", (x["soon"] as? Bool) == true ? UIColor.systemRed : UIColor.secondaryLabel)
    if type != "task", type != "comment", let p = files.first?["pic"] as? String { it.pic = p }
    if (x["restore"] as? Bool) == true { it.lead = [MeSwipe(title: "Restore", sym: "arrow.uturn.backward", col: TaskSwipe.green) { [weak self, weak h] fin in fin(true); self?.trRestore(h, id) }] }
    if (x["forever"] as? Bool) == true { it.trail = [MeSwipe(title: "Delete Forever", sym: "trash", col: .systemRed, destructive: true) { [weak self] fin in fin(false); self?.trForever(id) }] }
    it.menu = { [weak self, weak h] in self?.trashMenu(h, id) }
    return it
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
  // (the month and what's waiting for you, in the line under the title — mock-up "Content plans — fully Apple", 2026-11-10)
  private var plansLine: String {
    let m = (model["plans"] as? [String: Any]) ?? [:]
    let mine = ((m["rows"] as? [[String: Any]]) ?? []).filter { ($0["mine"] as? Bool) == true }.map { (($0["st"] as? [String: Any])?["k"] as? String) ?? "" }
    let nWait = mine.filter { $0 == "wait" }.count, nBack = mine.filter { $0 == "chg" }.count
    return [m["label"] as? String ?? "", nWait > 0 ? "\(nWait) waiting for you" : nBack > 0 ? "\(nBack) sent back" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
  }
  private func plansBlocks(_ h: HomeView, _ out: inout [UIView]) {
    let m = (model["plans"] as? [String: Any]) ?? [:]
    let rows0 = (m["rows"] as? [[String: Any]]) ?? []
    // (the month and what's waiting for you, in the line under the title — mock-up "Content plans — fully Apple", 2026-11-10)
    let mineRows = rows0.filter { ($0["mine"] as? Bool) == true }
    if h.assets != "plansTab" && h.assets != "plansPage" { h.drawAssetsBar(name: "Content plans", sub: plansLine, logo: nil, rgb: nil, ini: nil, showLogo: false) }
    guard let rows = m["rows"] as? [[String: Any]] else { let n = part(h, "wait") { AppleEmpty() }; n.setLoading(); out.append(n); return }
    let month = m["month"] as? String ?? ""
    let mb = part(h, "month") { PlanMonthChips() }
    if let n = pageVCs[ObjectIdentifier(h)]?.navigationController as? AppleNav ?? (appleNav as? AppleNav), pageVCs[ObjectIdentifier(h)] != nil, let g = n.backAnywhere { mb.backWaits(for: g) }
    mb.set(month: month, first: m["first"] as? String ?? month, last: m["last"] as? String ?? month)
    mb.onPick = { [weak self] to in guard let self = self else { return }; UISelectionFeedbackGenerator().selectionChanged(); self.plMonth = to; self.send(["ev": "pl", "on": true, "month": to]) }
    out.append(mb)
    let item = { [weak self] (r: [String: Any]) -> SetItem in
      let pid = r["pid"] as? String ?? "", st = r["st"] as? [String: Any] ?? [:]
      var it = SetItem(key: "p." + pid, title: r["name"] as? String ?? "", sub: r["sub"] as? String ?? "", tap: { self?.open("plan", "\(pid)|\(month)") })
      it.person = (photo: nil, ini: r["ini"] as? String ?? "", rgb: NativeSheetVC.color(r["rgb"]) ?? .systemGray)
      it.pills = [(st["t"] as? String ?? "", MeCtl.stCol(st["k"] as? String ?? ""))]
      return it
    }
    // (waiting for you first, its own group with its count in orange; then every client — mock-up 2026-11-10)
    let rest = rows.filter { ($0["mine"] as? Bool) != true }
    if rows.isEmpty { let n = part(h, "none") { AppleEmpty() }; n.set("person.2", "No Clients"); out.append(n) }
    else if mineRows.isEmpty { out.append(head(h, "pl", "")); out.append(group(h, "pl", rows.map(item))) }
    else {
      let wh = head(h, "plw", "Waiting for you · \(mineRows.count)"); wh.label.textColor = .systemOrange; out.append(wh)
      out.append(group(h, "plw", mineRows.map(item)))
      if !rest.isEmpty { out.append(head(h, "pl", "All clients")); out.append(group(h, "pl", rest.map(item))) }
    }
    out.append(foot(h, "plfoot", m["foot"] as? String ?? "", centered: true))
  }
  private func planBlocks(_ h: HomeView, _ id: String, _ out: inout [UIView]) {
    let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let pid = parts.first ?? "", month = parts.count > 1 ? parts[1] : ""
    guard let m = model["plan"] as? [String: Any], (m["pid"] as? String) == pid, month.isEmpty || (m["month"] as? String) == month else {
      h.drawAssetsBar(name: "Content plan", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      // (gone while it's open — trashed or deleted elsewhere: the page goes back with a toast, as every page — Live rule)
      if model["plan"] is NSNull || model["plan"] == nil, apple, let vc = pageVCs[ObjectIdentifier(h)], vc.appeared, AppData.shared.ready {
        if trashing == nil, vc.navigationController?.topViewController === vc { vc.navigationController?.popViewController(animated: true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.top?.toast(["t": "This content skeleton is no longer here"]) } }
      }
      let n = part(h, "wait") { AppleEmpty() }; if model["plan"] is NSNull { n.set("calendar", "No Longer Here", "This plan is no longer here.") } else { n.setLoading() }; out.append(n); return
    }
    h.drawAssetsBar(name: m["name"] as? String ?? "", sub: m["sub"] as? String ?? "", logo: nil, rgb: nil, ini: nil, showLogo: false)
    let st = m["st"] as? [String: Any] ?? [:]
    // (not started: Apple's own empty state — mock-up "Content plans — fully Apple", 2026-11-10)
    if m["empty"] is String { let n = part(h, "none") { AppleEmpty() }; n.set("calendar.badge.plus", "Not Started Yet", "Content skeletons are made on the computer."); out.append(n); return }
    // (where it stands: Apple's own list cell — its symbol in the status colour, who and when under it)
    let b = m["banner"] as? [String: Any] ?? [:], k = st["k"] as? String ?? ""
    let sym = ["wait": "clock.fill", "chg": "arrow.uturn.backward", "prod": "gearshape.fill", "sent": "paperplane.fill", "ok": "checkmark", "draft": "pencil"][k] ?? "circle.dashed"
    var lines = [b["t"] as? String, b["s"] as? String].compactMap { $0 }.filter { !$0.isEmpty }
    if let n = b["note"] as? String, !n.isEmpty { lines.append("“\(n)”") }
    out.append(head(h, "st", ""))
    var stItem = SetItem(key: "st", title: st["t"] as? String ?? "", sub: lines.joined(separator: "\n"), sym: sym, col: MeCtl.stCol(k), chevron: false)
    stItem.bold = true
    out.append(group(h, "st", [stItem]))
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
        // (each format its own symbol in its colour — the mock-up's)
        let fsym = ["Carousel": "square.stack.fill", "Reel": "play.rectangle.fill", "Story": "circle.dashed", "Video": "video.fill"][x["fmt"] as? String ?? ""] ?? "photo.fill"
        var it = SetItem(key: "x." + xid, title: x["title"] as? String ?? "", sub: "", sym: fsym, col: NativeSheetVC.color(x["fcol"]) ?? .systemGray, tap: { [weak self] in self?.openPost(planId, xid) })
        var check = x["check"] as? [String: Any]
        if let n = checksNow[xid] { check = ["k": n.state == "ok" ? "ok" : "chg", "t": n.state == "ok" ? "Looks good — you" : "You: “\(n.note)”"] }
        if let c = check {
          sub += "\n" + (c["t"] as? String ?? "")
          it.pills = [((c["k"] as? String) == "ok" ? "✓" : "!", (c["k"] as? String) == "ok" ? .systemGreen : .systemOrange)]
        } else if let p = x["prog"] as? [String: Any] { it.pills = [(p["t"] as? String ?? "", MeCtl.progCol(p["k"] as? String ?? ""))] }
        it.sub = sub
        return it
      }))
    }
    // ••• Apple's own menu: Copy Link, and Trash Skeleton for its maker and the Social Manager before any task is made
    // from it (Haris 2026-11-10, the mock-up's D)
    let canTrash = (m["trash"] as? Bool) == true, client = m["name"] as? String ?? "", monthName = m["sub"] as? String ?? ""
    h.assetsMenu = { [weak self, weak h] in
      var out = [CornerMenuItem(title: "Copy Link", symbol: "link", run: { self?.main.copyPlanLink(planId) })]
      if canTrash { out.append(CornerMenuItem(title: "Trash Skeleton", symbol: "trash", destructive: true, run: {
        let a = UIAlertController(title: "Move this content skeleton to the Trash?", message: "\(client)’s \(monthName) skeleton goes to the Trash for 30 days.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Move to Trash", style: .destructive) { _ in
          // (at once, on the phone's copy: the page goes and the list has it gone; the server's answer then — a no puts it
          //  back with why — Haris 2026-11-09 "what you do shows at once")
          let undo = AppData.shared.patch("plans", planId, [:])
          self?.trashing = planId
          if undo != nil { AppData.shared.applyLocal([["kind": "plans", "id": planId, "deleted": true]]) }
          UINotificationFeedbackGenerator().notificationOccurred(.success)
          if let h = h, let vc = self?.pageVCs[ObjectIdentifier(h)] { vc.navigationController?.popViewController(animated: true) }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self?.top?.toast(["t": "Moved to the Trash"]) }
          self?.request(["ev": "plTrash", "plan": planId]) { r in
            self?.trashing = nil
            guard (r["ok"] as? Bool) == true else { AppData.shared.putBack(undo); self?.top?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]); return }
          }
        })
        self?.main.topMost().present(a, animated: true)
      })) }
      return out
    }
    pageVCs[ObjectIdentifier(h)]?.menuChanged()
    // Send Back · Approve on Apple's toolbar (Approve Apple's prominent button; dimmed while a post is marked for changes —
    // a tap says why). Only for the one who approves it now; gone the moment it's no longer theirs.
    let vc = pageVCs[ObjectIdentifier(h)]
    if let ap = m["approve"] as? [String: Any] {
      // (with the marks just made, before the server's answer)
      let posts = ((m["days"] as? [[String: Any]]) ?? []).flatMap { ($0["posts"] as? [[String: Any]]) ?? [] }
      let flagged = checksNow.isEmpty ? ap["flagged"] as? Int ?? 0 : posts.filter { x in
        if let n = checksNow[x["id"] as? String ?? ""] { return n.state == "changes" }
        return ((x["check"] as? [String: Any])?["k"] as? String) == "chg"
      }.count
      vc?.setTools("\(planId)|\(flagged)") { [weak self, weak h] in
        let back = UIBarButtonItem(title: "Send Back", primaryAction: UIAction { _ in self?.askNote(title: "Send back for changes", hint: flagged > 0 ? "A note for the whole skeleton (optional) — the posts you marked go with it." : "What should change?", optional: flagged > 0) { note, done in
          // (at once: sent back on the phone's copy, the note sheet gone; a no from the server puts it back with why)
          let undo = AppData.shared.patch("plans", planId, ["status": "changes"])
          done(nil)
          self?.request(["ev": "plBack", "plan": planId, "note": note]) { r in if (r["ok"] as? Bool) != true { AppData.shared.putBack(undo); self?.top?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } } } })
        let ok = UIBarButtonItem(title: "Approve", primaryAction: UIAction { _ in
          guard let self = self else { return }
          if flagged > 0 { UINotificationFeedbackGenerator().notificationOccurred(.warning); h?.toast(["t": "\(flagged) post\(flagged == 1 ? " is" : "s are") marked Ask for Changes — send it back instead"]); return }
          let a = UIAlertController(title: "Approve this content skeleton?", message: "After this, tasks can be made from it on the computer.", preferredStyle: .alert)
          a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
          a.addAction(UIAlertAction(title: "Approve", style: .default) { [weak self] _ in
            // (at once: approved on the phone's copy; a no from the server puts it back with why)
            let undo = AppData.shared.patch("plans", planId, ["status": "approved"])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self?.request(["ev": "plApprove", "plan": planId]) { [weak h] r in if (r["ok"] as? Bool) != true { AppData.shared.putBack(undo); h?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) } }
          })
          a.preferredAction = a.actions.last
          self.main.topMost().present(a, animated: true)
        })
        if flagged > 0 { ok.tintColor = .tertiaryLabel } else if #available(iOS 26.0, *) { ok.style = .prominent } else { ok.style = .done }
        return [back, .flexibleSpace(), ok]
      }
    } else { vc?.setTools("", nil) }
    if let f = m["foot"] as? String, !f.isEmpty { out.append(foot(h, "pfoot", f, centered: true)) }
    DispatchQueue.main.async { [weak self] in self?.refreshPost() }
  }
  // 🔍 on Content plans (Haris 2026-11-04): the months the app reaches — the one on screen first — clients and posts
  private func planFind(_ h: HomeView, _ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { h.showFound([], hint: nil); return }
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
      // (nothing found: Apple's own "No Results"; close matches said in the footer — mock-up 2026-11-10)
      if views.isEmpty { let e = AppleEmpty(); e.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); views.append(e) }
      else { let f = SetFoot(); f.set((r["loose"] as? Bool) == true ? "Nothing matched exactly — these are close. The month showing first, then every month you can open." : "The month showing first, then every month you can open.", centered: true); views.append(f) }
      h.showFound(views, hint: nil)
      let titles = groups.flatMap { ($0["items"] as? [[String: Any]]) ?? [] }
      Find.mark(views, (r["marks"] as? [String]) ?? Find.filter(titles, q) { "\($0["title"] ?? "") \($0["sub"] ?? "")" }.marks)
    }
  }
  // a post marked, shown on the skeleton at once (its line under it, and Approve dimmed or not) until the server's answer
  // is in the copy; a no puts it back with why (Haris 2026-11-09 "what you do shows at once")
  private var checksNow: [String: (state: String, note: String)] = [:]
  private var trashing: String?
  // the post open in its sheet: drawn again from the copy as it changes (Live), gone with a toast if the post is gone
  private weak var postShown: PlanPostVC?
  private func refreshPost() {
    guard let vc = postShown, vc.presentingViewController != nil else { return }
    if let np = AppData.shared.meModel("plans", "plansPost", [vc.planId, vc.postId]) { vc.update(np); return }
    postShown = nil
    vc.dismiss(animated: true) { [weak self] in self?.top?.toast(["t": "This post is no longer here"]) }
  }
  private func reviewNow(_ plan: String, _ post: String, _ state: String, _ note: String) {
    checksNow[post] = (state, note)
    stack.filter { $0.kind == "plan" }.forEach { draw($0) }
    request(["ev": "plReview", "plan": plan, "post": post, "state": state, "note": note]) { [weak self] r in
      guard let self = self else { return }
      self.checksNow[post] = nil
      if (r["ok"] as? Bool) != true { self.top?.toast(["t": r["error"] as? String ?? "That didn’t work — try again"]) }
      self.stack.filter { $0.kind == "plan" }.forEach { self.draw($0) }
    }
  }
  private func openPost(_ plan: String, _ post: String) {
    request(["ev": "plPost", "plan": plan, "post": post]) { [weak self] r in
      guard let self = self else { return }
      guard let p = r["post"] as? [String: Any] else { (self.top)?.toast(["t": r["error"] as? String ?? "This post is no longer here"]); return }
      let client = ((self.model["plan"] as? [String: Any])?["name"] as? String) ?? ""
      let vc = PlanPostVC(p, line: [client, p["day"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), plan: plan, post: post)
      self.postShown = vc
      vc.onReview = { [weak self, weak vc] state in
        guard let self = self else { return }
        if state == "changes" {
          self.askNote(title: "Ask for changes", hint: "\(p["title"] as? String ?? "") — what should change?", optional: false, from: vc) { note, done in
            done(nil); vc?.dismiss(animated: true)
            self.reviewNow(plan, post, "changes", note)
          }
        } else {
          UINotificationFeedbackGenerator().notificationOccurred(.success); vc?.dismiss(animated: true)
          self.reviewNow(plan, post, "ok", "")
        }
      }
      vc.onOpenFile = { [weak self] all, i in self?.main.openFiles(all.map { ["id": $0["path"] as? String ?? "", "path": $0["path"] as? String ?? "", "name": $0["name"] as? String ?? "File"] }, at: i) }
      let nav = UINavigationController(rootViewController: vc)
      if let sp = nav.sheetPresentationController { sp.detents = [.large()]; sp.prefersGrabberVisible = true }
      self.main.topMost().present(nav, animated: true)
    }
  }
  // a note, iPhone's own sheet: ✕ · the title · Send
  private func askNote(title: String, hint: String, optional: Bool, from: UIViewController? = nil, _ send: @escaping (String, @escaping (String?) -> Void) -> Void) {
    let vc = NoteVC(title: title, hint: hint, optional: optional, send: send)
    let nav = UINavigationController(rootViewController: vc)
    if let sp = nav.sheetPresentationController { sp.detents = [.custom { _ in 260 }, .large()]; sp.prefersGrabberVisible = true }
    (from ?? main.topMost()).present(nav, animated: true)
  }
  private func memberBlocks(_ h: HomeView, _ id: String, _ out: inout [UIView]) {
    let admin = (team["admin"] as? Bool) == true
    guard let p = person(id) else {
      h.drawAssetsBar(name: "Team member", sub: "", logo: nil, rgb: nil, ini: nil, showLogo: false)
      let n = part(h, "gone") { AppleEmpty() }; if team.isEmpty { n.setLoading() } else { n.set("person.crop.circle.badge.xmark", "Not on the Team", "No longer on the team list.") }; out.append(n); return
    }
    let role = p["role"] as? String ?? ""
    h.drawAssetsBar(name: p["name"] as? String ?? "", sub: role, logo: nil, rgb: nil, ini: nil, showLogo: false)
    // (the person as Apple's cell on top — their picture, name, role and designation; the approved mock-up)
    var top = SetItem(key: "who", title: p["name"] as? String ?? "", sub: [role, (p["designation"] as? String).flatMap { $0 == role ? nil : $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), chevron: false)
    top.person = (photo: p["photo"] as? String, ini: p["ini"] as? String ?? "", rgb: NativeSheetVC.color(p["rgb"]) ?? .systemGray)
    top.bold = true
    out.append(head(h, "who", "")); out.append(group(h, "who", [top]))
    var info: [SetItem] = [SetItem(key: "mail", title: "Email", value: "", chevron: false)]
    info[0].sub = p["email"] as? String ?? ""
    if let pl = p["place"] as? String, !pl.isEmpty { info.append(SetItem(key: "place", title: "Where", value: pl, chevron: false)) }
    info.append(SetItem(key: "status", title: "Status", value: (p["past"] as? Bool) == true ? "Removed" : (p["pending"] as? Bool) == true ? "Hasn’t signed in yet" : "Active", chevron: false))
    if let n = p["open"] as? Int { info.append(SetItem(key: "open", title: "Open tasks", value: "\(n)", chevron: false)) }
    let email = p["email"] as? String ?? ""
    info[0].tap = { [weak self, weak h] in UIPasteboard.general.string = email; h?.toast(["t": "Email copied"]); _ = self }
    out.append(head(h, "info", "")); out.append(group(h, "info", info))
    out.append(foot(h, "infonote", "Tap the email to copy it."))
    // ROLE AND ACCESS (Admins): Role and Finance Access as Apple's pull-down menus, Super Admin Rights and Creative Director
    // as Apple's switches, a Freelancer's clients — the approved mock-up's D1; Remove from Team only in the hold menu (E2)
    guard admin, let o = memberParts(id) else { return }
    var manage: [SetItem] = []
    if let l = o.locked { manage.append(SetItem(key: "locked", title: l, sym: "lock.fill", col: .systemGray, chevron: false)) }
    else {
      if !o.roles.isEmpty { var it = SetItem(key: "role", title: "Role", value: o.roleNow, chevron: false); it.popup = { UIMenu(children: o.roles) }; manage.append(it) }
      if let a = o.admin { manage.append(SetItem(key: "admin", title: "Super Admin Rights", toggle: a.on, flip: { [weak self, weak h] _ in a.run(); if let h = h { self?.settle(h) } })) }
      if !o.fin.isEmpty { var it = SetItem(key: "fin", title: "Finance Access", value: o.finNow, chevron: false); it.popup = { UIMenu(children: o.fin) }; manage.append(it) }
      if let cd = p["cd"] as? [String: Any] {
        manage.append(SetItem(key: "cd", title: "Creative Director", sub: "Reviews every file sent for CD review", toggle: (cd["on"] as? Bool) == true, flip: { [weak self, weak h] _ in self?.cdFlow(id, h); if let h = h { self?.settle(h) } }))
      }
      if let c = o.clients { manage.append(SetItem(key: "clients", title: "Clients They Can See", tap: c)) }
    }
    guard !manage.isEmpty else { return }
    out.append(head(h, "manage", "Role and access")); out.append(group(h, "manage", manage))
    if p["cd"] != nil { out.append(foot(h, "cdnote", "Creative Director: one person at a time — switching it on while someone else is CD asks whether they take over, or act for them while away.")) }
  }

  // ---------- taps ----------
  private func event(_ h: HomeView, _ ev: [String: Any]) {
    switch ev["ev"] as? String ?? "" {
    case "back": if h === stack.last?.h { pop() }
    case "toast": send(["ev": "toast"])
    // (your photo on the Content plans tab: the Me tab, as from every other tab — Haris 2026-11-04)
    case "me" where MeCtl.tabRoots.contains(h.assets ?? ""): main.selectTab("me")
    case "find" where h.assets == "plansPage" || h.assets == "me.plan" || h.assets == "plansTab": planFind(h, ev["q"] as? String ?? "")
    default: break
    }
  }

  // ---------- the page's questions, as iPhone's own (dialog, choiceDialog, formDialog over the app's Me) ----------
  func ask(_ a: [String: Any], from: UIView? = nil, _ done: @escaping ([String: Any]) -> Void) {
    let kind = a["kind"] as? String ?? "alert"
    if kind == "form" {
      let vc = MeFormVC(a, done: done); let nav = UINavigationController(rootViewController: vc)
      // (as tall as its fields — one name isn't a whole page: Haris 2026-11-03)
      let n = CGFloat(((a["fields"] as? [Any]) ?? []).count)
      let h: CGFloat = 110 + n * 96 + ((a["intro"] as? String ?? "").isEmpty ? 0 : 44) + ((a["error"] as? String ?? "").isEmpty ? 0 : 28)
      if let sp = nav.sheetPresentationController { sp.detents = [.custom { _ in h }, .large()]; sp.prefersGrabberVisible = true }
      main.topMost().present(nav, animated: true); return
    }
    let title = a["title"] as? String, body = a["body"] as? String
    let ac = UIAlertController(title: title, message: (body ?? "").isEmpty ? nil : body, preferredStyle: kind == "choice" ? .actionSheet : .alert)
    if kind == "choice" {
      var hadCancel = false   // (iPhone allows one Cancel)
      for (i, c) in ((a["choices"] as? [[String: Any]]) ?? []).enumerated() {
        let cancel = (c["cancel"] as? Bool) == true && !hadCancel
        if cancel { hadCancel = true }
        ac.addAction(UIAlertAction(title: c["label"] as? String ?? "", style: cancel ? .cancel : (c["danger"] as? Bool) == true ? .destructive : .default) { _ in done(["ok": !cancel, "index": i]) })
      }
      if let pop = ac.popoverPresentationController {
        if let v = from { pop.sourceView = v; pop.sourceRect = v.bounds } else { pop.sourceView = main.view; pop.sourceRect = askAnchor() }
        pop.permittedArrowDirections = [.down, .up]
      }
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
  func warm() { pushCheck() }
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
    main.withToken { [weak self] t, why in
      guard let t = t else { self?.top?.toast(["t": why ?? "iPhone gave no notification address"]); return }
      self?.main.serverTask.request("/api/push/test", body: ["token": t]) { [weak self] r in
        self?.top?.toast(["t": r.map { MeCtl.testSaid($0) } ?? "No connection — try again"])
      }
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
  init(_ a: [String: Any], done: @escaping ([String: Any]) -> Void) {
    self.a = a; self.done = done
    fields = (a["fields"] as? [[String: Any]]) ?? []
    super.init(style: .insetGrouped)
    for f in fields { values[f["key"] as? String ?? ""] = (f["value"] as? String) ?? "" }
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
  // (a field's note under it: Apple's own grouped footer, set with its lines wrapping — given as a title, iPhone drew it in
  //  one line wider than the sheet (measured in 1599: 570 and 698 pt in a 402 pt table, 1 line), and it ran off the
  //  sheet: Haris 2026-11-09)
  override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
    guard let t = footerText(section) else { return nil }
    let v = UITableViewHeaderFooterView(reuseIdentifier: nil)
    var c = UIListContentConfiguration.groupedFooter()
    c.text = t; c.textProperties.numberOfLines = 0
    v.contentConfiguration = c
    return v
  }
  private func footerText(_ section: Int) -> String? {
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
      if d == .right { rightSwipe = sw }
    }
  }
  // (on a page pushed in Apple's navigation: Apple's swipe back from anywhere waits for the months' own swipe — a swipe on
  //  the months changes the month, anywhere else goes back; Apple's way for two gestures, as the task page's pager —
  //  Haris 2026-11-08: the swipe on the months went back a page)
  private var rightSwipe: UISwipeGestureRecognizer?
  private weak var waiting: UIGestureRecognizer?
  func backWaits(for g: UIGestureRecognizer) {
    guard waiting !== g, let r = rightSwipe else { return }
    waiting = g; g.require(toFail: r)
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
    let idle = Look.c(UIColor(red: 39 / 255, green: 39 / 255, blue: 41 / 255, alpha: 1), UIColor(red: 234 / 255, green: 234 / 255, blue: 236 / 255, alpha: 1))
    let idleInk = Look.c(UIColor(red: 157 / 255, green: 156 / 255, blue: 164 / 255, alpha: 1), UIColor(red: 134 / 255, green: 134 / 255, blue: 137 / 255, alpha: 1))
    for (m, p) in pills {
      let on = m == selected, ok = usable(m)
      p.bg.backgroundColor = on ? Look.c(MailCats.blue(false), MailCats.blue(true)) : idle
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
// a post, read only — Apple's sheet (mock-up "Content plans — fully Apple", 2026-11-10): its bar ✕ · the post's title and
// the client · day under it; what's in it as Apple's grouped list; Ask for Changes · Looks Good on Apple's toolbar for the
// approver. A file tapped: the app's Quick Look over the sheet, sideways through all the post's files; a link: Safari in the app.
final class PlanPostVC: UITableViewController {
  private var p: [String: Any]
  private let line: String
  let planId: String, postId: String
  var onReview: ((String) -> Void)?, onOpenFile: (([[String: Any]], Int) -> Void)?
  private struct Row { var title: String; var value = ""; var sub = ""; var col: UIColor? = nil; var sym: String? = nil; var file: [String: Any]? = nil; var rtl = false; var body = false }
  private var secs: [(head: String, rows: [Row])] = []
  init(_ p: [String: Any], line: String, plan: String, post: String) { self.p = p; self.line = line; planId = plan; postId = post; super.init(style: .insetGrouped) }
  // (live: changed elsewhere while it's open — its rows again, crossfading; only when what it shows changed)
  func update(_ np: [String: Any]) {
    guard isViewLoaded, (try? JSONSerialization.data(withJSONObject: np, options: .sortedKeys)) != (try? JSONSerialization.data(withJSONObject: p, options: .sortedKeys)) else { return }
    p = np; build()
    UIView.transition(with: tableView, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.tableView.reloadData() }
  }
  required init?(coder: NSCoder) { fatalError() }
  private var files: [[String: Any]] { (((p["made"] as? [[String: Any]]) ?? []) + ((p["refs"] as? [[String: Any]]) ?? [])).filter { $0["link"] == nil } }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = p["title"] as? String ?? "Post"
    if #available(iOS 26.0, *) { navigationItem.subtitle = line.isEmpty ? nil : line }
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "r")
    tableView.separatorColor = HomeLook.line
    build()
  }
  private func build() {
    secs = []
    var top: [Row] = [Row(title: "Format", value: p["fmt"] as? String ?? ""), Row(title: "Day", value: p["day"] as? String ?? "")]
    if let o = p["occ"] as? String, !o.isEmpty { top.append(Row(title: "Occasion", value: o)) }
    if let c = p["ch"] as? String, !c.isEmpty { top.append(Row(title: "Channels", value: c)) }
    if let pr = p["prog"] as? [String: Any] { top.append(Row(title: "Progress", value: pr["t"] as? String ?? "", col: .systemPurple)) }
    secs.append(("", top))
    if let c = p["check"] as? [String: Any] { let ok = (c["k"] as? String) == "ok"; secs.append(((p["review"] as? Bool) == true ? "Your review" : "Review", [Row(title: c["t"] as? String ?? "", col: ok ? .systemGreen : .systemOrange, body: true)])) }
    let fileRow = { (f: [String: Any]) -> Row in
      if f["link"] != nil { return Row(title: f["name"] as? String ?? "", sub: f["link"] as? String ?? "", sym: "link", file: f) }
      return Row(title: f["name"] as? String ?? "File", sym: (f["img"] as? Bool) == true ? "photo" : "doc", file: f)
    }
    let made = (p["made"] as? [[String: Any]]) ?? []
    if !made.isEmpty { secs.append(("The finished work", made.map(fileRow))) }
    for (k, t) in [("desc", "Description"), ("shots", "Shots"), ("copyEn", "Copy · English"), ("copyAr", "Copy · Arabic")] {
      if let v = p[k] as? String, !v.isEmpty { secs.append((t, [Row(title: v, rtl: k == "copyAr", body: true)])) }
    }
    let refs = (p["refs"] as? [[String: Any]]) ?? []
    if !refs.isEmpty { secs.append(("References", refs.map(fileRow))) }
    // (the approver's two answers on Apple's toolbar — Looks Good Apple's prominent button)
    if (p["review"] as? Bool) == true {
      let ask = UIBarButtonItem(title: "Ask for Changes", primaryAction: UIAction { [weak self] _ in self?.onReview?("changes") })
      let ok = UIBarButtonItem(title: "Looks Good", primaryAction: UIAction { [weak self] _ in self?.onReview?("ok") })
      if #available(iOS 26.0, *) { ok.style = .prominent } else { ok.style = .done }
      if toolbarItems == nil { toolbarItems = [ask, .flexibleSpace(), ok] }
    } else if toolbarItems != nil { toolbarItems = nil; navigationController?.setToolbarHidden(true, animated: true) }
  }
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); navigationController?.setToolbarHidden(toolbarItems?.isEmpty ?? true, animated: false) }
  override func numberOfSections(in tv: UITableView) -> Int { secs.count }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { secs[s].rows.count }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { secs[s].head.isEmpty ? nil : secs[s].head }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let r = secs[ip.section].rows[ip.row]
    let c = tv.dequeueReusableCell(withIdentifier: "r", for: ip)
    var cf = r.value.isEmpty ? (r.sub.isEmpty ? UIListContentConfiguration.cell() : .subtitleCell()) : .valueCell()
    cf.text = r.title
    if !r.value.isEmpty { cf.secondaryText = r.value; if let col = r.col { cf.secondaryTextProperties.color = col } }
    else if !r.sub.isEmpty { cf.secondaryText = r.sub; cf.secondaryTextProperties.color = .secondaryLabel; cf.secondaryTextProperties.numberOfLines = 1 }
    if r.body { cf.textProperties.numberOfLines = 0; if let col = r.col { cf.textProperties.color = col }; if r.rtl { cf.textProperties.alignment = .justified } }
    if let sym = r.sym { cf.image = UIImage(systemName: sym); cf.imageProperties.tintColor = .systemBlue }
    if r.file != nil { cf.textProperties.color = .label; cf.textProperties.numberOfLines = 1; cf.textProperties.lineBreakMode = .byTruncatingMiddle }
    c.contentConfiguration = cf
    c.semanticContentAttribute = r.rtl ? .forceRightToLeft : .unspecified
    c.contentView.semanticContentAttribute = c.semanticContentAttribute
    c.accessoryType = r.file != nil ? .disclosureIndicator : .none
    c.selectionStyle = r.file != nil ? .default : .none
    // (a picture's own thumbnail where the symbol is)
    if let f = r.file, (f["img"] as? Bool) == true, let u = f["url"] as? String {
      let key = u
      c.accessibilityIdentifier = key
      FeedLoader.shared.image(u + (u.contains("?") ? "&" : "?") + "w=120") { [weak c] img in
        DispatchQueue.main.async {
          guard let c = c, c.accessibilityIdentifier == key, let img = img, var cf2 = c.contentConfiguration as? UIListContentConfiguration else { return }
          cf2.image = img; cf2.imageProperties.maximumSize = CGSize(width: 34, height: 34); cf2.imageProperties.reservedLayoutSize = CGSize(width: 34, height: 34); cf2.imageProperties.cornerRadius = 6
          c.contentConfiguration = cf2
        }
      }
    } else { c.accessibilityIdentifier = nil }
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard let f = secs[ip.section].rows[ip.row].file else { return }
    if let l = f["link"] as? String, let u = URL(string: l), ["http", "https"].contains(u.scheme?.lowercased() ?? "") { present(SFSafariViewController(url: u), animated: true); return }
    let all = files
    let i = all.firstIndex { ($0["path"] as? String) == (f["path"] as? String) } ?? 0
    onOpenFile?(all, i)
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

// ---------- the add sheets — Apple's form sheet (Haris 2026-11-11 07:25, the mock-up "Remaining pages — fully Apple"):
// Apple's grouped list in iPhone's own sheet, ✕ and ✓ in its bar. A claim by hand: Person (Apple's pull-down menu — the
// team, other people, someone who isn't a team member), Amount, Month (last / this, Apple's segmented control), the
// claim's PDF; a subscription: Name, Amount, Billing Day (Apple's menu, 1st–31st), the invoice; an office expense: Name,
// Amount, Payment Date (Apple's date picker), the invoice. The file: Apple's menu — Files, Photos, Camera. ✓ lights up once
// what it needs is in. ----------
final class MoneyFormVC: UITableViewController, UITextFieldDelegate {
  enum Kind { case claim, sub, expense }
  let kind: Kind
  var onSave: (([String: Any], @escaping (String?) -> Void) -> Void)?
  var onPerson: ((String, @escaping (String?, String?) -> Void) -> Void)?
  private let months: [(String, String)]
  private let cookies: (@escaping (String) -> Void) -> Void
  private let nameF = UITextField(), amountF = UITextField(), monthSeg = UISegmentedControl(), datePick = UIDatePicker()
  private var who: String?, day = Calendar.current.component(.day, from: Date()), file: [String: Any]?, busy = false, saving = false, err: String?
  private var peopleList: [(String, String)]
  private var ok: UIBarButtonItem?
  init(kind: Kind, people: [(String, String)], months: [(String, String)], cookies: @escaping (@escaping (String) -> Void) -> Void) {
    self.kind = kind; self.peopleList = people; self.months = months; self.cookies = cookies
    super.init(style: .insetGrouped)
  }
  required init?(coder: NSCoder) { fatalError() }
  func inNav() -> UIViewController {
    let n = UINavigationController(rootViewController: self)
    if let s = n.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
    return n
  }
  // the rows of each group: (what, label)
  private enum Row { case person, name, amount, month, day, date, file }
  private var groups: [[Row]] {
    switch kind {
    case .claim: return [[.person, .amount, .month], [.file]]
    case .sub: return [[.name, .amount, .day], [.file]]
    case .expense: return [[.name, .amount, .date], [.file]]
    }
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = kind == .claim ? "Add Claim" : kind == .sub ? "Add Subscription" : "Add Office Expense"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let b = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.save() })
    ok = b; navigationItem.rightBarButtonItem = b
    tableView.keyboardDismissMode = .interactive
    nameF.placeholder = kind == .sub ? "e.g. Adobe Creative Cloud" : "e.g. Studio lights"; nameF.autocapitalizationType = .words
    amountF.placeholder = "\u{20C3} 0.00"; amountF.keyboardType = .decimalPad
    for f in [nameF, amountF] { f.font = .systemFont(ofSize: 17); f.clearButtonMode = .whileEditing; f.delegate = self; f.addAction(UIAction { [weak self] _ in self?.paintOK() }, for: .editingChanged) }
    nameF.textAlignment = .left; amountF.textAlignment = .right
    for (i, m) in months.enumerated() { monthSeg.insertSegment(withTitle: m.1.components(separatedBy: " ").first ?? m.1, at: i, animated: false) }
    monthSeg.selectedSegmentIndex = max(0, months.count - 1)
    datePick.datePickerMode = .date; datePick.preferredDatePickerStyle = .compact; datePick.maximumDate = Date()
    paintOK()
  }
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if kind == .claim { amountF.becomeFirstResponder() } else { nameF.becomeFirstResponder() } }
  private func paintOK() {
    let amount = Double((amountF.text ?? "").replacingOccurrences(of: ",", with: "")) ?? 0
    let named = kind == .claim ? who != nil : !(nameF.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    ok?.isEnabled = !saving && !busy && amount > 0 && named && (kind != .claim || file != nil)
  }
  override func numberOfSections(in tableView: UITableView) -> Int { groups.count }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { groups[section].count }
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 1 ? (kind == .claim ? "Claim PDF" : "Invoice") : nil }
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    if section == 1, let e = err { return e }
    switch (kind, section) {
    case (.claim, 0): return "Added by hand, it waits for HR approval like a claim sent from the app."
    case (.sub, 0): return "Recorded as an expense on this day every month."
    case (.claim, 1): return "Required — the claim with its receipts."
    default: return section == 1 ? "Optional — it can be added later." : nil
    }
  }
  override func tableView(_ tableView: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .default, reuseIdentifier: nil)
    c.selectionStyle = .none
    var cf = UIListContentConfiguration.valueCell()
    let row = groups[ip.section][ip.row]
    switch row {
    case .person:
      cf.text = "Person"
      c.contentConfiguration = cf
      c.accessoryView = personButton()
    case .name:
      cf.text = "Name"; c.contentConfiguration = cf
      field(nameF, in: c, leading: 92)
    case .amount:
      cf.text = "Amount"; c.contentConfiguration = cf
      field(amountF, in: c, leading: 110)
    case .month:
      cf.text = "Month"; c.contentConfiguration = cf
      monthSeg.sizeToFit(); c.accessoryView = monthSeg
    case .day:
      cf.text = "Billing Day"; c.contentConfiguration = cf
      c.accessoryView = dayButton()
    case .date:
      cf.text = "Payment Date"; c.contentConfiguration = cf
      datePick.sizeToFit(); c.accessoryView = datePick
    case .file:
      var f = UIListContentConfiguration.cell()
      f.text = busy ? "Uploading…" : file.map { $0["name"] as? String ?? "File" } ?? (kind == .claim ? "Attach PDF" : "Attach Invoice")
      f.textProperties.color = file == nil ? .tintColor : .label
      f.image = UIImage(systemName: file == nil ? "paperclip" : "doc.fill")
      c.contentConfiguration = f
      c.accessoryView = fileButton()
    }
    return c
  }
  private func field(_ f: UITextField, in c: UITableViewCell, leading: CGFloat) {
    f.removeFromSuperview()
    f.translatesAutoresizingMaskIntoConstraints = false
    c.contentView.addSubview(f)
    NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: c.contentView.leadingAnchor, constant: leading), f.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor),
                                 f.centerYAnchor.constraint(equalTo: c.contentView.centerYAnchor), f.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)])
  }
  // (Apple's pop-up buttons: the choice as the button's words, its menu on a tap)
  private func popup(_ title: String, _ menu: UIMenu, dim: Bool = false) -> UIButton {
    var bc = UIButton.Configuration.plain()
    bc.title = title; bc.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    bc.imagePlacement = .trailing; bc.imagePadding = 5; bc.baseForegroundColor = dim ? .secondaryLabel : .label; bc.contentInsets = .zero
    let b = UIButton(configuration: bc); b.menu = menu; b.showsMenuAsPrimaryAction = true; b.sizeToFit()
    return b
  }
  private func personButton() -> UIButton {
    let pick = { [weak self] (id: String) in self?.who = id; self?.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none); self?.paintOK() }
    let team = peopleList.filter { $0.0.hasPrefix("u:") }.map { p in UIAction(title: p.1, state: p.0 == who ? .on : .off) { _ in pick(p.0) } }
    let other = peopleList.filter { $0.0.hasPrefix("p:") }.map { p in UIAction(title: p.1, state: p.0 == who ? .on : .off) { _ in pick(p.0) } }
    let add = UIAction(title: "Someone Who Isn’t a Team Member…", image: UIImage(systemName: "plus")) { [weak self] _ in self?.askPerson() }
    let m = UIMenu(children: [UIMenu(title: "Team members", options: .displayInline, children: team)] + (other.isEmpty ? [] : [UIMenu(title: "Other people", options: .displayInline, children: other)]) + [UIMenu(options: .displayInline, children: [add])])
    return popup(peopleList.first(where: { $0.0 == who })?.1 ?? "Choose", m, dim: who == nil)
  }
  private func askPerson() {
    let a = UIAlertController(title: "Someone who isn’t a team member", message: nil, preferredStyle: .alert)
    a.addTextField { $0.placeholder = "Name"; $0.autocapitalizationType = .words }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak a] _ in
      let n = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
      self?.onPerson?(n) { id, name in
        guard let self = self else { return }
        guard let id = id else { self.err = "Couldn’t add that person — try again"; self.tableView.reloadSections([1], with: .none); return }
        self.peopleList.append((id, name ?? n)); self.who = id; self.err = nil
        self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none); self.paintOK()
      }
    })
    present(a, animated: true)
  }
  private static func ord(_ n: Int) -> String { n % 10 == 1 && n != 11 ? "\(n)st" : n % 10 == 2 && n != 12 ? "\(n)nd" : n % 10 == 3 && n != 13 ? "\(n)rd" : "\(n)th" }
  private func dayButton() -> UIButton {
    let m = UIMenu(children: (1...31).map { n in UIAction(title: MoneyFormVC.ord(n), state: n == day ? .on : .off) { [weak self] _ in self?.day = n; self?.tableView.reloadRows(at: [IndexPath(row: 2, section: 0)], with: .none) } })
    return popup(MoneyFormVC.ord(day), m)
  }
  private func fileButton() -> UIView? {
    var acts = [("Files", "folder", "files"), ("Photos", "photo.on.rectangle", "photos"), ("Camera", "camera", "camera")].map { t in UIAction(title: t.0, image: UIImage(systemName: t.1)) { [weak self] _ in self?.pick(t.2) } }
    if file != nil { acts.append(UIAction(title: "Remove", image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in self?.file = nil; self?.tableView.reloadSections([1], with: .none); self?.paintOK() }) }
    if busy { let s = UIActivityIndicatorView(style: .medium); s.startAnimating(); return s }
    var bc = UIButton.Configuration.plain(); bc.image = UIImage(systemName: file == nil ? "plus.circle.fill" : "ellipsis.circle"); bc.contentInsets = .zero
    let b = UIButton(configuration: bc); b.menu = UIMenu(children: acts); b.showsMenuAsPrimaryAction = true; b.sizeToFit()
    return b
  }
  private func monthNow() -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"; return f.string(from: Date()) }
  private func pick(_ src: String) {
    Picker.shared.pick(from: self, single: true, source: src) { [weak self] r in
      guard let self = self, let x = ((r["files"] as? [[String: Any]]) ?? []).first, let tok = x["token"] as? String, let url = Picker.shared.url(tok) else { return }
      let name = x["name"] as? String ?? "File"
      let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
      let month = self.kind == .claim && self.monthSeg.selectedSegmentIndex >= 0 && self.monthSeg.selectedSegmentIndex < self.months.count ? self.months[self.monthSeg.selectedSegmentIndex].0 : self.monthNow()
      let dest = "Finance/" + (self.kind == .claim ? "Reimbursements" : self.kind == .sub ? "Subscriptions" : "Expenses") + "/" + month
      self.busy = true; self.err = nil; self.tableView.reloadSections([1], with: .none); self.paintOK()
      Uploader.send(url, name: name, task: "", dest: dest, cookies: self.cookies, progress: { _ in }) { [weak self] path in
        guard let self = self else { return }
        self.busy = false
        if let p = path { self.file = ["path": p, "name": name, "size": size] } else { self.err = "Couldn’t upload — try again" }
        self.tableView.reloadSections([1], with: .none); self.paintOK()
      }
    }
  }
  private func save() {
    guard !busy else { return }
    view.endEditing(true)
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
    saving = true; paintOK()
    onSave?(f) { [weak self] e in
      guard let self = self else { return }
      self.saving = false; self.paintOK()
      if let e = e { UINotificationFeedbackGenerator().notificationOccurred(.error); self.err = e; self.tableView.reloadSections([1], with: .none) } else { UINotificationFeedbackGenerator().notificationOccurred(.success); self.dismiss(animated: true) }
    }
  }
}

// ---------- the CD's Reviews' pieces of ours (the mock-up "Review Requests — fully Apple", 2026-11-10): a request's files
// as now, and Request Amendments' sheet ----------

// The CD's review files ready before she opens a request (Haris 2026-11-11 07:08: "You can do these 3"): each request
// in Waiting has its pictures fetched quietly as the phone's copy changes — the strip's small ones first, then the large
// ones — into the phone's picture store (FeedLoader → DiskPics), so a request opens with its files already there, offline
// too. Only for whoever has the Reviews tab; one picture at a time; a picture that won't come is tried twice, no more.
enum ReviewWarm {
  private static var started = false, busy = false, again = false, queued = false
  private static var have = Set<String>(), tries: [String: Int] = [:]
  static func start() {
    guard !started else { return }
    started = true
    AppData.shared.listen { soon() }
    soon()
  }
  // (the pictures let go — a sign-out, someone else here: fetched again when needed)
  static func forget() { have.removeAll(); tries.removeAll() }
  // (the copy can change many times in a row: worked out once it has settled)
  private static func soon() {
    guard !queued else { return }
    queued = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { queued = false; warm() }
  }
  private static func warm() {
    guard Main.shared.tabKeys.contains("reviews") else { return }
    if busy { again = true; return }
    guard let m = AppData.shared.meModel("reviews", "reviews") else { return }
    var small: [String] = [], large: [String] = []
    for r in (m["waiting"] as? [[String: Any]]) ?? [] {
      for f in ((r["files"] as? [[String: Any]]) ?? []) + ((r["carriedFiles"] as? [[String: Any]]) ?? []) {
        if let p = f["pic"] as? String { small.append(p) }
        if let p = f["big"] as? String { large.append(p) }
      }
    }
    var seen = Set<String>()
    let list = (small + large).filter { !have.contains($0) && (tries[$0] ?? 0) < 2 && seen.insert($0).inserted }
    guard !list.isEmpty else { return }
    busy = true
    func next(_ i: Int) {
      guard i < list.count else { busy = false; if again { again = false; soon() }; return }
      let p = list[i]
      FeedLoader.shared.image(p) { img in
        if img != nil { have.insert(p) } else { tries[p, default: 0] += 1 }
        next(i + 1)
      }
    }
    next(0)
  }
}

// the sender and the files, large and swipeable (the mock-up's D2 — a tap opens Quick Look; the strip under them)
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
    let s = "\(fl.map { "\($0["id"] ?? "")\($0["mark"] ?? "")" })|\(x["sub"] ?? "")|\(x["round"] ?? "")|\(x["photo"] ?? "")|\(L.key)"
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
        // (never an empty box — Haris 2026-11-11: the strip's small picture fills it at once, the sharp one fades in over it)
        if let p = f["big"] as? String {
          var sharp = false
          FeedLoader.shared.image(p) { [weak im, weak ext] img in
            guard let im = im, let img = img else { return }
            sharp = true; ext?.isHidden = true
            if im.image == nil { im.image = img } else { UIView.transition(with: im, duration: 0.25, options: .transitionCrossDissolve) { im.image = img } }
          }
          if !sharp, let s = f["pic"] as? String, s != p {
            FeedLoader.shared.image(s) { [weak im, weak ext] img in guard let im = im, let img = img, !sharp else { return }; im.image = img; ext?.isHidden = true }
          }
        }
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

// iPhone's own sheet: tick the files that need changes (each its own note), the rest are approved; a general note on
// top (optional — or the only note, for a single file). ✕ and the blue ↑ to send. "Yousef is notified on the task."
final class AmendSheetVC: UIViewController, UITextViewDelegate {
  var onSend: ((_ need: [String: String]?, _ note: String, _ done: @escaping (String?) -> Void) -> Void)?
  private let files: [[String: Any]], first: String
  private var ticked: Set<String> = [], notes: [String: UITextView] = [:], wills: [String: UILabel] = [:], ticks: [String: UIButton] = [:]
  private let general = UITextView(), err = UILabel(), stack = UIStackView()
  private var sending = false
  init(files: [[String: Any]], first: String) { self.files = files; self.first = first; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  func inNav() -> UIViewController {
    let n = UINavigationController(rootViewController: self)
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
