import UIKit

/* The morning round-up as iPhone's own sheet (app shell 29+; Haris, 2026-11-01). The page works the sections out (Daily
   in daily.js — the same as the website's card) and sends them: dailySheet { title, sub, foot, light, open, sections:
   [{ k, l, sym, rgb, n, rows: [{ id, t, m, d, late }], more: { t } }] }. Not growable: the sheet is as tall as what's in
   it — the six headings and the open section (one always open; at most 7 lines in it, "See all N in My Tasks" counted)
   — and changes height with the section in one movement, as iPhone's own sheets do. Never taller than 85 % of the
   screen (small phones: the inside scrolls). Taps back: open (a task), all (a section's "See … in My Tasks"). */
final class DailySheetVC: UIViewController, UISheetPresentationControllerDelegate {
  private var d: [String: Any]
  private let answer: ([String: Any]) -> Void
  private var openK: String
  private let scroll = UIScrollView(), stack = UIStackView()
  private let head = UIView(), sun = UIView(), sunIcon = UIImageView(), titleL = UILabel(), subL = UILabel(), close = UIButton(type: .system)
  private let group = UIStackView(), foot = UILabel()
  private var fitHeight: CGFloat = 520
  private var sections: [[String: Any]] { d["sections"] as? [[String: Any]] ?? [] }

  init(_ d: [String: Any], answer: @escaping ([String: Any]) -> Void) {
    self.d = d; self.answer = answer
    openK = d["open"] as? String ?? ""
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = (d["light"] as? Bool) == false ? .dark : .light
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController {
      sh.detents = [.custom(identifier: .init("daily")) { [weak self] ctx in min(ctx.maximumDetentValue * 0.85, self?.fitHeight ?? 520) }]
      sh.prefersGrabberVisible = true
      sh.preferredCornerRadius = 38
      sh.delegate = self
    }
  }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    // (a solid back: a sheet not at full height is see-through glass on iOS 26 — the Inbox showed through the sections)
    let back = UIView(); back.backgroundColor = .systemGroupedBackground; back.frame = view.bounds; back.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(back)
    scroll.alwaysBounceVertical = false; scroll.showsVerticalScrollIndicator = false
    view.addSubview(scroll)
    stack.axis = .vertical; stack.spacing = 16; scroll.addSubview(stack)
    // the top: the sun, Good morning, the date and whose tasks, ✕
    sun.backgroundColor = .systemOrange; sun.layer.cornerRadius = 22
    sunIcon.image = UIImage(systemName: "sun.max.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)); sunIcon.tintColor = .white; sunIcon.contentMode = .center
    sun.addSubview(sunIcon)
    titleL.font = .systemFont(ofSize: 20, weight: .bold); titleL.text = d["title"] as? String
    subL.font = .systemFont(ofSize: 14); subL.textColor = .secondaryLabel; subL.numberOfLines = 2; subL.text = d["sub"] as? String
    var c: UIButton.Configuration
    if #available(iOS 26.0, *) { c = .glass() } else { c = .gray(); c.cornerStyle = .capsule }
    // (the same ✕ as the Attach Files sheet: 44 pt glass, 15 pt semibold, the label colour — Haris, 2026-11-01)
    c.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)); c.baseForegroundColor = .label
    c.cornerStyle = .capsule
    close.configuration = c; close.accessibilityLabel = "Close"
    close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    [sun, titleL, subL, close].forEach { head.addSubview($0) }
    stack.addArrangedSubview(head)
    group.axis = .vertical; group.backgroundColor = .secondarySystemGroupedBackground; group.layer.cornerRadius = 22; group.layer.cornerCurve = .continuous; group.clipsToBounds = true
    stack.addArrangedSubview(group)
    foot.font = .systemFont(ofSize: 13); foot.textColor = .secondaryLabel; foot.textAlignment = .center; foot.text = d["foot"] as? String
    stack.addArrangedSubview(foot)
    build()
  }

  // ---------- the sections ----------
  private var sectionViews: [String: (row: UIControl, chev: UIImageView, list: UIStackView)] = [:]
  private func build() {
    group.arrangedSubviews.forEach { $0.removeFromSuperview() }
    sectionViews = [:]
    let any = sections.contains { ($0["n"] as? Int ?? 0) > 0 }
    if !any {
      // all clear: the tick, a short sheet
      let v = UIView()
      let tick = UIView(); tick.backgroundColor = .systemGreen; tick.layer.cornerRadius = 26
      let ti = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold))); ti.tintColor = .white; ti.contentMode = .center
      tick.addSubview(ti)
      let b = UILabel(); b.text = "All clear today"; b.font = .systemFont(ofSize: 17, weight: .semibold); b.textAlignment = .center
      let s = UILabel(); s.text = "Nothing overdue, due today or waiting on anyone."; s.font = .systemFont(ofSize: 14); s.textColor = .secondaryLabel; s.textAlignment = .center; s.numberOfLines = 0
      [tick, b, s].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; v.addSubview($0) }
      ti.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        tick.topAnchor.constraint(equalTo: v.topAnchor, constant: 26), tick.centerXAnchor.constraint(equalTo: v.centerXAnchor), tick.widthAnchor.constraint(equalToConstant: 52), tick.heightAnchor.constraint(equalToConstant: 52),
        ti.centerXAnchor.constraint(equalTo: tick.centerXAnchor), ti.centerYAnchor.constraint(equalTo: tick.centerYAnchor),
        b.topAnchor.constraint(equalTo: tick.bottomAnchor, constant: 10), b.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12), b.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
        s.topAnchor.constraint(equalTo: b.bottomAnchor, constant: 3), s.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12), s.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
        s.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
      ])
      group.addArrangedSubview(v)
      return
    }
    for (i, sec) in sections.enumerated() {
      let k = sec["k"] as? String ?? "", n = sec["n"] as? Int ?? 0
      let row = UIControl()
      row.heightAnchor.constraint(equalToConstant: 48).isActive = true
      let ic = UIView(); ic.backgroundColor = DailySheetVC.color(sec["rgb"]); ic.layer.cornerRadius = 8; ic.layer.cornerCurve = .continuous; ic.alpha = n > 0 ? 1 : 0.4
      let icI = UIImageView(image: UIImage(systemName: sec["sym"] as? String ?? "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))); icI.tintColor = .white; icI.contentMode = .center
      ic.addSubview(icI)
      let l = UILabel(); l.text = sec["l"] as? String; l.font = .systemFont(ofSize: 16, weight: .medium); l.textColor = n > 0 ? .label : .tertiaryLabel
      let c = UILabel(); c.text = "\(n)"; c.font = .systemFont(ofSize: 16, weight: .medium); c.textColor = n > 0 ? .secondaryLabel : .tertiaryLabel
      let chev = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))); chev.tintColor = .tertiaryLabel; chev.isHidden = n == 0
      [ic, l, c, chev].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; $0.isUserInteractionEnabled = false; row.addSubview($0) }
      icI.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
      NSLayoutConstraint.activate([
        ic.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), ic.centerYAnchor.constraint(equalTo: row.centerYAnchor), ic.widthAnchor.constraint(equalToConstant: 28), ic.heightAnchor.constraint(equalToConstant: 28),
        l.leadingAnchor.constraint(equalTo: ic.trailingAnchor, constant: 11), l.centerYAnchor.constraint(equalTo: row.centerYAnchor), l.trailingAnchor.constraint(lessThanOrEqualTo: c.leadingAnchor, constant: -8),
        chev.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14), chev.centerYAnchor.constraint(equalTo: row.centerYAnchor), chev.widthAnchor.constraint(equalToConstant: 12),
        c.trailingAnchor.constraint(equalTo: chev.leadingAnchor, constant: -8), c.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      ])
      row.isEnabled = n > 0
      row.accessibilityLabel = "\(sec["l"] as? String ?? ""), \(n)"; row.isAccessibilityElement = true; row.accessibilityTraits = .button
      row.addAction(UIAction { [weak self] _ in self?.pick(k) }, for: .touchUpInside)
      let list = UIStackView(); list.axis = .vertical
      for r in sec["rows"] as? [[String: Any]] ?? [] { list.addArrangedSubview(taskRow(r)) }
      if let more = sec["more"] as? [String: Any], let t = more["t"] as? String {
        let b = UIButton(type: .system)
        b.setAttributedTitle(NSAttributedString(string: t, attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor.systemBlue]), for: .normal)
        b.contentHorizontalAlignment = .leading
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        b.addAction(UIAction { [weak self] _ in self?.done(["ev": "all", "k": k]) }, for: .touchUpInside)
        list.addArrangedSubview(lined(b))
      }
      let wrap = UIStackView(arrangedSubviews: [row, list]); wrap.axis = .vertical
      list.isHidden = k != openK; list.alpha = k == openK ? 1 : 0
      chev.transform = k == openK ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
      group.addArrangedSubview(wrap)
      if i < sections.count - 1 { group.addArrangedSubview(sep(inset: 0)) }
      sectionViews[k] = (row, chev, list)
    }
  }
  private func sep(inset: CGFloat) -> UIView {
    let v = UIView(); v.heightAnchor.constraint(equalToConstant: 1 / max(1, UIScreen.main.scale)).isActive = true
    let line = UIView(); line.backgroundColor = .separator; line.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(line)
    NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: inset), line.trailingAnchor.constraint(equalTo: v.trailingAnchor), line.topAnchor.constraint(equalTo: v.topAnchor), line.bottomAnchor.constraint(equalTo: v.bottomAnchor)])
    return v
  }
  // (a line inside an open section: from the names' edge, with the separator above it)
  private func lined(_ content: UIView) -> UIView {
    let v = UIView()
    let s = sep(inset: 0); s.translatesAutoresizingMaskIntoConstraints = false; content.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(s); v.addSubview(content)
    NSLayoutConstraint.activate([
      s.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 53), s.trailingAnchor.constraint(equalTo: v.trailingAnchor), s.topAnchor.constraint(equalTo: v.topAnchor),
      content.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 53), content.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: s.bottomAnchor), content.bottomAnchor.constraint(equalTo: v.bottomAnchor),
    ])
    return v
  }
  private func taskRow(_ r: [String: Any]) -> UIView {
    let b = UIControl()
    let t = UILabel(); t.text = r["t"] as? String; t.font = .systemFont(ofSize: 15); t.lineBreakMode = .byTruncatingTail
    let m = UILabel(); m.font = .systemFont(ofSize: 13)
    let s = NSMutableAttributedString(string: r["m"] as? String ?? "", attributes: [.foregroundColor: UIColor.secondaryLabel])
    if let dd = r["d"] as? String, !dd.isEmpty {
      if s.length > 0 { s.append(NSAttributedString(string: " · ", attributes: [.foregroundColor: UIColor.secondaryLabel])) }
      s.append(NSAttributedString(string: dd, attributes: [.foregroundColor: (r["late"] as? Bool) == true ? UIColor.systemRed : UIColor.secondaryLabel]))
    }
    m.attributedText = s
    [t, m].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; $0.isUserInteractionEnabled = false; b.addSubview($0) }
    NSLayoutConstraint.activate([
      t.topAnchor.constraint(equalTo: b.topAnchor, constant: 8), t.leadingAnchor.constraint(equalTo: b.leadingAnchor), t.trailingAnchor.constraint(equalTo: b.trailingAnchor),
      m.topAnchor.constraint(equalTo: t.bottomAnchor, constant: 1), m.leadingAnchor.constraint(equalTo: b.leadingAnchor), m.trailingAnchor.constraint(equalTo: b.trailingAnchor),
      m.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -8),
    ])
    let id = r["id"] as? String ?? ""
    b.addAction(UIAction { [weak self] _ in self?.done(["ev": "open", "id": id]) }, for: .touchUpInside)
    return lined(b)
  }

  // ---------- one section open at a time: the old one closes, the new one opens, the sheet fits — one movement ----------
  private func pick(_ k: String) {
    guard k != openK, let new = sectionViews[k] else { return }   // (the open one stays open)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let old = sectionViews[openK]
    openK = k
    view.layoutIfNeeded()
    let move = {
      old?.list.isHidden = true; old?.list.alpha = 0; old?.chev.transform = .identity
      new.list.isHidden = false; new.list.alpha = 1; new.chev.transform = CGAffineTransform(rotationAngle: .pi / 2)
      self.view.layoutIfNeeded()
      self.measure()
    }
    if let sh = sheetPresentationController {
      sh.animateChanges { move(); sh.invalidateDetents() }
    } else { UIView.animate(withDuration: 0.35, animations: move) }
  }
  private func done(_ ev: [String: Any]) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let a = answer
    dismiss(animated: true) { a(ev) }
  }

  // ---------- where things go; the sheet as tall as what's in it ----------
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let W = view.bounds.width
    scroll.frame = view.bounds
    let pad: CGFloat = 16
    // (the top: placed by hand — the sun, the two lines, the ✕)
    let textW = W - pad * 2 - 44 - 12 - 12 - 44
    let subH = ceil(subL.sizeThatFits(CGSize(width: textW, height: 100)).height)
    let headH = max(44, 25 + 2 + subH)
    head.frame.size = CGSize(width: W - pad * 2, height: headH)
    sun.frame = CGRect(x: 4, y: (headH - 44) / 2, width: 44, height: 44); sunIcon.frame = sun.bounds
    titleL.frame = CGRect(x: 4 + 44 + 12, y: 0, width: textW, height: 25)
    subL.frame = CGRect(x: 4 + 44 + 12, y: 27, width: textW, height: subH)
    close.frame = CGRect(x: W - pad * 2 - 44, y: (headH - 44) / 2, width: 44, height: 44)
    head.heightAnchorConstraint(headH)
    stack.frame = CGRect(x: pad, y: 34, width: W - pad * 2, height: stack.systemLayoutSizeFitting(CGSize(width: W - pad * 2, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    scroll.contentSize = CGSize(width: W, height: stack.frame.maxY + 22)
    measure()
  }
  private var measured = false
  private func measure() {
    let floating: Bool; if #available(iOS 26, *) { floating = true } else { floating = false }
    let h = stack.frame.maxY + 22 + (floating ? 0 : view.safeAreaInsets.bottom)
    guard abs(h - fitHeight) > 0.5 else { return }
    fitHeight = h
    // (first time: sized once it's laid out, outside the layout pass — iOS 27 went round in circles sizing a sheet inside it)
    if !measured { measured = true; DispatchQueue.main.async { [weak self] in self?.sheetPresentationController?.invalidateDetents() } }
  }
  static func color(_ v: Any?) -> UIColor {
    if let a = v as? [Double], a.count >= 3 { return UIColor(red: a[0] / 255, green: a[1] / 255, blue: a[2] / 255, alpha: 1) }
    if let a = v as? [Int], a.count >= 3 { return UIColor(red: CGFloat(a[0]) / 255, green: CGFloat(a[1]) / 255, blue: CGFloat(a[2]) / 255, alpha: 1) }
    return .systemBlue
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { answer(["ev": "closed"]) }
}

private extension UIView {
  // (the top's height for the stack, kept as one constraint)
  func heightAnchorConstraint(_ h: CGFloat) {
    if let c = constraints.first(where: { $0.firstAttribute == .height && $0.firstItem === self }) { c.constant = h }
    else { let c = heightAnchor.constraint(equalToConstant: h); c.isActive = true }
  }
}
