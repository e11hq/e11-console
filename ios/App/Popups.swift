import UIKit

/* The six pop-ups as the app's own (Haris 2026-11-03 — the approved mockups, project doc claude/ios-popups-plan.md):
   1 Announcement · 2 Expense claims reminder · 3 Greetings (birthday / an occasion) · 4 the birthday / city card ·
   5 What's new · 6 View as…
   For now they open only from Me's temporary "Pop-up tests" rows (the test site), with made-up data; once Haris approves
   them the rows go and each pop-up goes to its own place. */

enum Pop {
  // (the big capsule: blue with white words, or grey with the page's ink — as the mockups)
  static func capsule(_ t: String, filled: Bool, small: Bool = false, _ act: @escaping () -> Void) -> UIButton {
    let b = UIButton(type: .system)
    var c = UIButton.Configuration.filled()
    c.cornerStyle = .capsule
    c.baseBackgroundColor = filled ? .systemBlue : .tertiarySystemFill
    c.baseForegroundColor = filled ? .white : .label
    var a = AttributedString(t); a.font = .systemFont(ofSize: small ? 15 : 17, weight: .semibold)
    c.attributedTitle = a
    c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: small ? 14 : 20, bottom: 0, trailing: small ? 14 : 20)
    b.configuration = c
    b.translatesAutoresizingMaskIntoConstraints = false
    b.heightAnchor.constraint(equalToConstant: small ? 34 : 52).isActive = true
    b.addAction(UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); act() }, for: .touchUpInside)
    return b
  }
  // (blue words, as "Remind me tomorrow")
  static func link(_ t: String, _ act: @escaping () -> Void) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(t, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 16); b.tintColor = .systemBlue
    b.translatesAutoresizingMaskIntoConstraints = false
    b.heightAnchor.constraint(equalToConstant: 36).isActive = true
    b.addAction(UIAction { _ in act() }, for: .touchUpInside)
    return b
  }
  static func label(_ t: String?, _ size: CGFloat, _ w: UIFont.Weight = .regular, _ color: UIColor = .label, lines: Int = 0, center: Bool = false) -> UILabel {
    let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: size, weight: w); l.textColor = color; l.numberOfLines = lines
    if center { l.textAlignment = .center }
    return l
  }
  // (a rounded tile with a symbol or words in it)
  static func tile(_ size: CGFloat, bg: UIColor, sym: String? = nil, text: String? = nil, ink: UIColor = .white, radius: CGFloat? = nil) -> UIView {
    let v = UIView(); v.backgroundColor = bg; v.layer.cornerRadius = radius ?? size * 0.26; v.layer.cornerCurve = .continuous
    v.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: size), v.heightAnchor.constraint(equalToConstant: size)])
    let inner: UIView
    if let s = sym {
      let i = UIImageView(image: UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)))
      i.tintColor = ink; inner = i
    } else {
      let l = UILabel(); l.text = text; l.textColor = ink; l.font = .systemFont(ofSize: size * ((text?.count ?? 0) > 2 ? 0.34 : 0.5), weight: .heavy); inner = l
    }
    inner.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(inner)
    NSLayoutConstraint.activate([inner.centerXAnchor.constraint(equalTo: v.centerXAnchor), inner.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
    return v
  }
  static func image(_ img: UIImage, _ size: CGFloat) -> UIImageView {
    let i = UIImageView(image: img); i.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([i.widthAnchor.constraint(equalToConstant: size), i.heightAnchor.constraint(equalToConstant: size)])
    return i
  }
  static func row(_ views: [UIView], spacing: CGFloat, align: UIStackView.Alignment = .center) -> UIStackView {
    let s = UIStackView(arrangedSubviews: views); s.axis = .horizontal; s.spacing = spacing; s.alignment = align; return s
  }
  static func col(_ views: [UIView], spacing: CGFloat) -> UIStackView {
    let s = UIStackView(arrangedSubviews: views); s.axis = .vertical; s.spacing = spacing; s.alignment = .fill; return s
  }
}

/* ---------- 1, 2, 5: the app's own glass sheet from the bottom, as tall as what's on it ---------- */
class PopSheetVC: UIViewController {
  let stack = UIStackView()
  var onGone: (() -> Void)?
  private let dark: Bool
  init(dark: Bool) {
    self.dark = dark
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = dark ? .dark : .light
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26.0, *) { view.backgroundColor = .clear } else { view.backgroundColor = .systemBackground }
    stack.axis = .vertical; stack.spacing = 14; stack.alignment = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
  }
  // (presented as tall as its contents — a grab handle; pulled down = closed)
  func show(from vc: UIViewController) {
    loadViewIfNeeded()
    let W = vc.view.bounds.width
    let fit = stack.systemLayoutSizeFitting(CGSize(width: W - 48, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    let h = fit + 30 + 22
    if let sp = sheetPresentationController {
      sp.detents = [.custom { ctx in min(h, ctx.maximumDetentValue) }]
      sp.prefersGrabberVisible = true
      sp.preferredCornerRadius = 34
    }
    vc.present(self, animated: true)
  }
  func close() { dismiss(animated: true) }
  override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); if isBeingDismissed || presentingViewController == nil { onGone?(); onGone = nil } }
}

// 1 · Announcement
final class AnnouncementSheet: PopSheetVC {
  init(dark: Bool, title: String, body: String, ask: String, from: String, fromIni: String, fromColor: UIColor, when: String) {
    super.init(dark: dark)
    loadViewIfNeeded()
    let tile = Pop.tile(44, bg: .systemOrange, sym: "megaphone.fill", radius: 12)
    let head = Pop.col([Pop.label("ANNOUNCEMENT", 13, .medium, .secondaryLabel), Pop.label(title, 21, .bold)], spacing: 2)
    stack.addArrangedSubview(Pop.row([tile, head], spacing: 14))
    stack.addArrangedSubview(Pop.label(body, 17))
    stack.addArrangedSubview(Pop.label(ask, 14, .regular, .secondaryLabel))
    let who = Pop.image(roundPic(nil, initials: fromIni, color: fromColor, size: 22), 22)
    stack.addArrangedSubview(Pop.row([who, Pop.label("From \(from) · \(when)", 14, .regular, .secondaryLabel)], spacing: 8))
    stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(Pop.capsule("Got it", filled: true) { [weak self] in self?.close() })
  }
  required init?(coder: NSCoder) { fatalError() }
}

// 2 · Expense claims reminder
final class ClaimsSheet: PopSheetVC {
  var onAnswer: ((String) -> Void)?   // none · offline · tomorrow
  init(dark: Bool, month: String, today: Int) {
    super.init(dark: dark)
    loadViewIfNeeded()
    let tile = Pop.tile(44, bg: dark ? .white : .black, text: "E11", ink: dark ? .black : .white, radius: 12)
    let head = Pop.col([Pop.label("EXPENSE CLAIMS · \(month.uppercased())", 13, .medium, .secondaryLabel), Pop.label("Any expenses to claim this month?", 21, .bold)], spacing: 2)
    stack.addArrangedSubview(Pop.row([tile, head], spacing: 14, align: .top))
    let body = NSMutableAttributedString(string: "Submit your \(month) claim by ", attributes: [.font: UIFont.systemFont(ofSize: 17)])
    body.append(NSAttributedString(string: "27 \(month)", attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    body.append(NSAttributedString(string: ". Claims can’t be submitted from the 28th.", attributes: [.font: UIFont.systemFont(ofSize: 17)]))
    let bl = Pop.label(nil, 17); bl.attributedText = body; bl.textColor = .label
    stack.addArrangedSubview(bl)
    // (the days 20–27: past faded, today orange)
    var days: [UIView] = []
    for d in 20...27 {
      let l = UILabel(); l.text = "\(d)"; l.textAlignment = .center; l.font = .systemFont(ofSize: 14, weight: d == today ? .bold : .medium)
      l.backgroundColor = d == today ? .systemOrange : d < today ? .quaternarySystemFill : .tertiarySystemFill
      l.textColor = d == today ? .white : d < today ? .tertiaryLabel : .label
      l.layer.cornerRadius = 15; l.clipsToBounds = true
      l.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([l.widthAnchor.constraint(equalToConstant: 30), l.heightAnchor.constraint(equalToConstant: 30)])
      days.append(l)
    }
    let dr = Pop.row(days, spacing: 8); dr.alignment = .center
    let dw = UIStackView(arrangedSubviews: [dr, UIView()]); dw.axis = .horizontal
    stack.addArrangedSubview(dw)
    let left = max(0, 27 - today)
    stack.addArrangedSubview(Pop.label("Daily reminder · " + (left == 0 ? "today is the last day to submit" : "\(left) more day\(left == 1 ? "" : "s") to submit"), 14, .regular, .secondaryLabel))
    stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(Pop.capsule("I don’t have claims", filled: true) { [weak self] in self?.answer("none") })
    stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(Pop.capsule("Submitted offline", filled: false) { [weak self] in self?.answer("offline") })
    stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(Pop.link("Remind me tomorrow") { [weak self] in self?.answer("tomorrow") })
    stack.setCustomSpacing(2, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(Pop.label("Claims are filled in on the computer — My profile › My reimbursements.", 13, .regular, .tertiaryLabel, center: true))
  }
  required init?(coder: NSCoder) { fatalError() }
  private func answer(_ a: String) { onAnswer?(a); close() }
}

// 5 · What's new
final class WhatsNewSheet: PopSheetVC {
  var onAllNotes: (() -> Void)?
  init(dark: Bool, version: String, when: String, sections: [(String, [String])]) {
    super.init(dark: dark)
    loadViewIfNeeded()
    let cap = UILabel()
    let a = NSMutableAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "arrow.down.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))!.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)))
    a.append(NSAttributedString(string: " WHAT’S NEW", attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: UIColor.systemBlue]))
    cap.attributedText = a
    stack.addArrangedSubview(Pop.col([cap, Pop.label(version, 26, .bold), Pop.label(when, 14, .regular, .secondaryLabel)], spacing: 3))
    // (the notes in their own rounded box that scrolls, a soft fade at its end)
    let box = NotesBox(sections)
    box.translatesAutoresizingMaskIntoConstraints = false
    box.heightAnchor.constraint(equalToConstant: min(300, box.wanted(width: UIScreen.main.bounds.width - 48))).isActive = true
    stack.addArrangedSubview(box)
    stack.setCustomSpacing(20, after: box)
    stack.addArrangedSubview(Pop.capsule("Got it", filled: true) { [weak self] in self?.close() })
    stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(Pop.link("All notes in Me › About") { [weak self] in guard let self = self else { return }; let go = self.onAllNotes; self.dismiss(animated: true) { go?() } })
  }
  required init?(coder: NSCoder) { fatalError() }
}
final class NotesBox: UIView {
  private let text = UITextView(), fade = CAGradientLayer()
  init(_ sections: [(String, [String])]) {
    super.init(frame: .zero)
    backgroundColor = .tertiarySystemFill; layer.cornerRadius = 18; layer.cornerCurve = .continuous; clipsToBounds = true
    let s = NSMutableAttributedString()
    let para = NSMutableParagraphStyle(); para.headIndent = 16; para.firstLineHeadIndent = 0; para.paragraphSpacing = 6
    para.tabStops = [NSTextTab(textAlignment: .left, location: 16)]
    for (i, (h, items)) in sections.enumerated() {
      let hp = NSMutableParagraphStyle(); hp.paragraphSpacingBefore = i == 0 ? 0 : 10; hp.paragraphSpacing = 6
      s.append(NSAttributedString(string: h.uppercased() + "\n", attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: hp]))
      for it in items { s.append(NSAttributedString(string: "•\t" + it + "\n", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label, .paragraphStyle: para])) }
    }
    text.attributedText = s
    text.isEditable = false; text.backgroundColor = .clear
    text.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 22, right: 12)
    addSubview(text)
    fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    layer.mask = nil
  }
  required init?(coder: NSCoder) { fatalError() }
  func wanted(width: CGFloat) -> CGFloat { text.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height }
  override func layoutSubviews() {
    super.layoutSubviews()
    text.frame = bounds
    // (a soft fade at its end, only when there's more to scroll)
    if text.contentSize.height > bounds.height + 1 {
      fade.frame = bounds; fade.locations = [0, NSNumber(value: Double(max(0, (bounds.height - 34) / max(1, bounds.height)))), 1]
      layer.mask = fade
    } else { layer.mask = nil }
  }
}

/* ---------- 6 · View as… (test site, the owner): a tall glass sheet ---------- */
final class ViewAsSheet: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
  struct Person { let id: String; let name: String; let role: String; let ini: String; let color: UIColor }
  private let people: [Person]
  private var shown: [Person]
  private var viewing: String?
  var onPick: ((String?) -> Void)?   // (nil: Back to me)
  private let table = UITableView(frame: .zero, style: .plain), search = UISearchBar(), heading = UILabel(), back = UIView()
  private var backBtn: UIButton!
  init(dark: Bool, people: [Person], viewing: String?) {
    self.people = people; shown = people; self.viewing = viewing
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = dark ? .dark : .light
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26.0, *) { view.backgroundColor = .clear } else { view.backgroundColor = .systemBackground }
    let close = UIButton(type: .system)
    if #available(iOS 26.0, *) { var c = UIButton.Configuration.glass(); c.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)); c.baseForegroundColor = .label; close.configuration = c }
    else { close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal); close.tintColor = .secondaryLabel }
    close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    let title = Pop.label("View as…", 17, .semibold, center: true)
    let note = Pop.label("Test site only. Use the app as this person, with their role — what they see and what they can do. It stays until you choose Back to me.", 14, .regular, .secondaryLabel)
    search.placeholder = "Search the team"; search.searchBarStyle = .minimal; search.delegate = self
    heading.font = .systemFont(ofSize: 13, weight: .medium); heading.textColor = .secondaryLabel
    table.dataSource = self; table.delegate = self; table.backgroundColor = .clear; table.rowHeight = 60
    table.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0); table.keyboardDismissMode = .onDrag
    backBtn = Pop.capsule("Back to me", filled: true) { [weak self] in self?.pick(nil) }
    [close, title, note, search, heading, table, backBtn].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    let g = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      close.topAnchor.constraint(equalTo: view.topAnchor, constant: 18), close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
      title.centerYAnchor.constraint(equalTo: close.centerYAnchor), title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      note.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 12), note.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), note.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      search.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 8), search.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), search.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
      heading.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6), heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      table.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4), table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      table.bottomAnchor.constraint(equalTo: backBtn.topAnchor, constant: -10),
      backBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), backBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      backBtn.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -10),
    ])
    paintViewing()
  }
  func show(from vc: UIViewController) {
    if let sp = sheetPresentationController { sp.detents = [.large()]; sp.prefersGrabberVisible = true; sp.preferredCornerRadius = 34 }
    vc.present(self, animated: true)
  }
  private func paintViewing() {
    let p = people.first { $0.id == viewing }
    heading.text = p.map { "VIEWING AS \($0.name.split(separator: " ").first.map(String.init)?.uppercased() ?? "") · \($0.role.uppercased())" }
    heading.isHidden = p == nil
    backBtn.isHidden = p == nil
  }
  private func pick(_ id: String?) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    viewing = id; onPick?(id); paintViewing(); table.reloadData()
  }
  func numberOfSections(in tableView: UITableView) -> Int { 1 }
  func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { shown.count }
  func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let p = shown[ip.row]
    let c = t.dequeueReusableCell(withIdentifier: "p") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "p")
    c.backgroundColor = .clear
    var cf = c.defaultContentConfiguration()
    cf.text = p.name; cf.textProperties.font = .systemFont(ofSize: 17)
    cf.secondaryText = p.role; cf.secondaryTextProperties.color = .secondaryLabel; cf.secondaryTextProperties.font = .systemFont(ofSize: 14)
    cf.image = roundPic(nil, initials: p.ini, color: p.color, size: 40); cf.imageProperties.maximumSize = CGSize(width: 40, height: 40)
    cf.imageToTextPadding = 14
    c.contentConfiguration = cf
    c.accessoryType = p.id == viewing ? .checkmark : .none
    c.tintColor = .systemBlue
    return c
  }
  func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) { t.deselectRow(at: ip, animated: true); pick(shown[ip.row].id) }
  func searchBar(_ s: UISearchBar, textDidChange q: String) {
    let k = q.trimmingCharacters(in: .whitespaces).lowercased()
    shown = k.isEmpty ? people : people.filter { $0.name.lowercased().contains(k) || $0.role.lowercased().contains(k) }
    table.reloadData()
  }
}

/* ---------- 3 · Greetings: the page softly blurred, confetti falling, a Liquid Glass card in the middle ---------- */
final class GreetingView: UIView {
  private let blur = UIVisualEffectView(effect: nil), card = UIVisualEffectView(effect: nil), confetti = CAEmitterLayer()
  private let stack = UIStackView()
  init(dark: Bool, top: UIView, title: String, sub: String) {
    super.init(frame: .zero)
    overrideUserInterfaceStyle = dark ? .dark : .light
    addSubview(blur)
    if !UIAccessibility.isReduceMotionEnabled { layer.addSublayer(confetti) }
    if #available(iOS 26.0, *) { card.effect = UIGlassEffect(style: .regular) } else { card.effect = UIBlurEffect(style: .systemThickMaterial) }
    card.layer.cornerRadius = 34; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
    addSubview(card)
    stack.axis = .vertical; stack.alignment = .center; stack.spacing = 8
    stack.addArrangedSubview(top); stack.setCustomSpacing(18, after: top)
    stack.addArrangedSubview(Pop.label(title, 28, .bold, center: true))
    stack.addArrangedSubview(Pop.label(sub, 16, .regular, .secondaryLabel, center: true))
    let tap = Pop.label("Tap anywhere to continue", 13, .regular, .tertiaryLabel, center: true)
    stack.addArrangedSubview(tap); stack.setCustomSpacing(18, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
    card.contentView.addSubview(stack)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(go)))
  }
  required init?(coder: NSCoder) { fatalError() }
  // (the person's photo in a ring)
  static func photoRing(_ img: UIImage) -> UIView {
    let ring = UIView(); ring.layer.borderWidth = 4; ring.layer.borderColor = UIColor.systemPurple.withAlphaComponent(0.8).cgColor
    ring.layer.cornerRadius = 64; ring.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([ring.widthAnchor.constraint(equalToConstant: 128), ring.heightAnchor.constraint(equalToConstant: 128)])
    let i = Pop.image(roundPic(img, initials: nil, color: nil, size: 112), 112); ring.addSubview(i)
    NSLayoutConstraint.activate([i.centerXAnchor.constraint(equalTo: ring.centerXAnchor), i.centerYAnchor.constraint(equalTo: ring.centerYAnchor)])
    return ring
  }
  static func occasionTile(_ emoji: String) -> UIView {
    let v = Pop.tile(112, bg: UIColor(red: 0.05, green: 0.42, blue: 0.30, alpha: 1), text: nil, radius: 28)
    let l = UILabel(); l.text = emoji; l.font = .systemFont(ofSize: 60); l.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(l)
    NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: v.centerXAnchor), l.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
    return v
  }
  func show(in host: UIView) {
    frame = host.bounds; autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.addSubview(self)
    layoutIfNeeded()
    card.alpha = 0; card.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
    startConfetti()
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    UIView.animate(withDuration: 0.35) { self.blur.effect = UIBlurEffect(style: .systemUltraThinMaterial) }
    UIView.animate(withDuration: 0.55, delay: 0.05, usingSpringWithDamping: 0.72, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.card.alpha = 1; self.card.transform = .identity }
  }
  @objc func go() {
    confetti.birthRate = 0
    UIView.animate(withDuration: 0.3, animations: { self.alpha = 0; self.card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94) }) { _ in self.removeFromSuperview() }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    blur.frame = bounds
    let W = min(bounds.width - 64, 340)
    stack.frame = CGRect(x: 24, y: 0, width: W - 48, height: 0)
    let h = stack.systemLayoutSizeFitting(CGSize(width: W - 48, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    card.bounds = CGRect(x: 0, y: 0, width: W, height: h + 64); card.center = CGPoint(x: bounds.midX, y: bounds.midY - 30)
    stack.frame = CGRect(x: 24, y: 32, width: W - 48, height: h)
    confetti.emitterPosition = CGPoint(x: bounds.midX, y: -20); confetti.emitterSize = CGSize(width: bounds.width * 1.2, height: 1)
  }
  private func startConfetti() {
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    confetti.emitterShape = .line
    let colors: [UIColor] = [.systemPink, .systemPurple, .systemBlue, .systemGreen, .systemYellow, .systemOrange, .white]
    confetti.emitterCells = colors.map { c in
      let cell = CAEmitterCell()
      cell.contents = GreetingView.piece(c).cgImage
      cell.birthRate = 5; cell.lifetime = 9; cell.velocity = 150; cell.velocityRange = 70
      cell.emissionLongitude = .pi; cell.emissionRange = .pi / 6
      cell.yAcceleration = 60; cell.spin = 3; cell.spinRange = 5; cell.scale = 1; cell.scaleRange = 0.3
      return cell
    }
    confetti.beginTime = CACurrentMediaTime()
    // (a burst, then it eases off)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.confetti.birthRate = 0.35 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.confetti.birthRate = 0 }
  }
  private static func piece(_ c: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 10, height: 5)).image { _ in c.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 10, height: 5), cornerRadius: 1.5).fill() }
  }
}

/* ---------- 4 · the birthday / city card: a small glass card just above the tab bar; goes by itself after 20 s, or as
   soon as another page or a task is opened ---------- */
final class ProfileAskCard: UIView {
  static weak var current: ProfileAskCard?
  private let glass = UIVisualEffectView(effect: nil), stack = UIStackView()
  var onProfile: (() -> Void)?
  private var timer: Timer?
  init(dark: Bool, missing: String) {
    super.init(frame: .zero)
    overrideUserInterfaceStyle = dark ? .dark : .light
    if #available(iOS 26.0, *) { glass.effect = UIGlassEffect(style: .regular) } else { glass.effect = UIBlurEffect(style: .systemThickMaterial) }
    glass.layer.cornerRadius = 26; glass.layer.cornerCurve = .continuous; glass.clipsToBounds = true
    addSubview(glass)
    layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = dark ? 0 : 0.1; layer.shadowRadius = 18; layer.shadowOffset = CGSize(width: 0, height: 6)
    let tile = Pop.tile(36, bg: .systemPink, sym: "gift.fill", radius: 9)
    let t = missing == "both" ? "Add your birthday and city?" : missing == "city" ? "Add your city?" : "Add your birthday?"
    let why = missing == "both" ? "The team gets a reminder to wish you on your birthday, and people see your city on your card. Both are optional."
      : missing == "city" ? "People see your city on your card. It’s optional." : "The team gets a reminder to wish you on your birthday. It’s optional."
    let btns = Pop.row([Pop.capsule("Go to My profile", filled: true, small: true) { [weak self] in let go = self?.onProfile; self?.go(); go?() },
                        Pop.capsule("Not now", filled: false, small: true) { [weak self] in self?.go() }, UIView()], spacing: 8)
    let text = Pop.col([Pop.label(t, 17, .semibold), Pop.label(why, 14, .regular, .secondaryLabel), btns], spacing: 4)
    text.setCustomSpacing(12, after: text.arrangedSubviews[1])
    stack.axis = .horizontal; stack.alignment = .top; stack.spacing = 12
    stack.addArrangedSubview(tile); stack.addArrangedSubview(text)
    glass.contentView.addSubview(stack)
  }
  required init?(coder: NSCoder) { fatalError() }
  func show(in host: UIView, bottom: CGFloat) {
    ProfileAskCard.current?.go()
    let W = host.bounds.width - 24
    stack.frame = CGRect(x: 16, y: 16, width: W - 32, height: 0)
    let h = stack.systemLayoutSizeFitting(CGSize(width: W - 32, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    frame = CGRect(x: 12, y: bottom - 10 - (h + 32), width: W, height: h + 32)
    glass.frame = bounds; stack.frame = CGRect(x: 16, y: 16, width: W - 32, height: h)
    host.addSubview(self)
    ProfileAskCard.current = self
    alpha = 0; transform = CGAffineTransform(translationX: 0, y: 24)
    UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.alpha = 1; self.transform = .identity }
    timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.go() }
  }
  // (slips away)
  func go() {
    timer?.invalidate(); timer = nil
    if ProfileAskCard.current === self { ProfileAskCard.current = nil }
    UIView.animate(withDuration: 0.3, animations: { self.alpha = 0; self.transform = CGAffineTransform(translationX: 0, y: 20) }) { _ in self.removeFromSuperview() }
  }
}
