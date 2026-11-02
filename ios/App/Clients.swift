import UIKit

/* The Clients tab, the app's own (shell 31, Part B — Haris 2026-11-02, from the approved mockup): Home's screen
   (HomeView) with its big title and the shared top buttons —
   · the list of clients: one inset group, each row its logo (or colour square with initials), name, "12 open ·
     3 overdue", its Account Managers' pictures, ›; "Inactive clients · N" opens the rest under it;
   · a client's page (‹ back): its Client Assets folders on top in a row that scrolls sideways (the folders open in the
     website's Client Assets), "Tasks · N open" with Show / Hide completed, then its tasks by status as Home's own cards
     (Haris: "the task cards will be consistent").
   Drawn from the app's own copy of the data (web/rules.js clientsList / clientPage). */

// a block of Home's list that isn't a card or a heading: its own height, the whole width
protocol HomeBlock: UIView { func blockHeight(_ W: CGFloat) -> CGFloat }

// the list of clients: one rounded group, a row each (as iPhone's Settings), "Inactive clients · N" under it
final class ClientsGroup: UIView, HomeBlock {
  var onOpen: ((String) -> Void)?
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { rows.forEach { $0.paintAms(people) } } } }
  private let box = UIView(), more = UIButton(type: .system)
  private var rows: [ClientRow] = [], lines: [UIView] = []
  private var showInactive = false
  private var data: ([[String: Any]], [[String: Any]]) = ([], [])
  private var L = HomeLook(nil)
  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "clients"
    box.layer.cornerRadius = 26; box.layer.cornerCurve = .continuous; box.clipsToBounds = true
    addSubview(box)
    more.contentHorizontalAlignment = .leading
    more.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.showInactive.toggle(); self.set(self.data.0, self.data.1, look: self.L)
      (self.superview?.superview as? HomeView)?.relayout()
    }, for: .touchUpInside)
    addSubview(more)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ active: [[String: Any]], _ inactive: [[String: Any]], look: HomeLook) {
    data = (active, inactive); L = look
    box.backgroundColor = L.card
    let list = active + (showInactive ? inactive : [])
    // (rows kept by client: a change redraws only what changed)
    var keep: [String: ClientRow] = [:]; rows.forEach { keep[$0.id] = $0 }
    rows = list.map { r in
      let id = r["id"] as? String ?? ""
      let v = keep.removeValue(forKey: id) ?? { let x = ClientRow(); x.id = id; x.onTap = { [weak self] in self?.onOpen?(id) }; _ = PressShrink.add(to: x); return x }()
      v.set(r, look: L, inactive: !active.contains { ($0["id"] as? String) == id }); v.paintAms(people)
      if v.superview !== box { box.addSubview(v) }
      return v
    }
    keep.values.forEach { $0.removeFromSuperview() }
    lines.forEach { $0.removeFromSuperview() }
    lines = rows.dropFirst().map { _ in let l = UIView(); l.backgroundColor = .separator; box.addSubview(l); return l }
    more.isHidden = inactive.isEmpty
    let t = (showInactive ? "Hide inactive clients" : "Inactive clients · \(inactive.count)")
    more.setAttributedTitle(NSAttributedString(string: t, attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel]), for: .normal)
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { CGFloat(rows.count) * ClientRow.H + (more.isHidden ? 0 : 50) }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    box.frame = CGRect(x: 16, y: 0, width: W - 32, height: CGFloat(rows.count) * ClientRow.H)
    box.isHidden = rows.isEmpty
    for (i, r) in rows.enumerated() { r.frame = CGRect(x: 0, y: CGFloat(i) * ClientRow.H, width: box.bounds.width, height: ClientRow.H) }
    let px = 1 / max(1, traitCollection.displayScale)
    for (i, l) in lines.enumerated() { l.frame = CGRect(x: 69, y: CGFloat(i + 1) * ClientRow.H - px / 2, width: box.bounds.width - 69, height: px) }
    more.frame = CGRect(x: 36, y: box.frame.maxY + 6, width: W - 72, height: 44)
  }
}

final class ClientRow: UIControl {
  static let H: CGFloat = 64
  var id = ""
  var onTap: (() -> Void)?
  private let logo = UIImageView(), ini = UILabel(), name = UILabel(), meta = UILabel(), ams = UIStackView(), chev = UIImageView()
  private var amIds: [String] = [], logoPath: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    logo.layer.cornerRadius = 11; logo.layer.cornerCurve = .continuous; logo.clipsToBounds = true; logo.contentMode = .scaleAspectFill
    ini.font = .systemFont(ofSize: 14, weight: .bold); ini.textColor = .white; ini.textAlignment = .center
    logo.addSubview(ini)
    name.font = .systemFont(ofSize: 17); meta.font = .systemFont(ofSize: 13)
    ams.spacing = -6; ams.alignment = .center
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)); chev.tintColor = .tertiaryLabel; chev.contentMode = .center
    [logo, name, meta, ams, chev].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
    addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onTap?() }, for: .touchUpInside)
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ r: [String: Any], look L: HomeLook, inactive: Bool) {
    let rgb = NativeSheetVC.color(r["rgb"]) ?? .systemGray
    name.text = r["name"] as? String; name.textColor = inactive ? .secondaryLabel : L.title
    ini.text = r["ini"] as? String
    let open = r["open"] as? Int ?? 0, late = r["late"] as? Int ?? 0
    let m = NSMutableAttributedString(string: "\(open) open", attributes: [.foregroundColor: UIColor.secondaryLabel])
    if late > 0 { m.append(NSAttributedString(string: " · ", attributes: [.foregroundColor: UIColor.secondaryLabel])); m.append(NSAttributedString(string: "\(late) overdue", attributes: [.foregroundColor: L.late, .font: UIFont.systemFont(ofSize: 13, weight: .medium)])) }
    meta.attributedText = m
    accessibilityLabel = "\(name.text ?? ""), \(open) open\(late > 0 ? ", \(late) overdue" : "")"
    amIds = (r["ams"] as? [String]) ?? []
    // (its logo where it has one — fetched with the app's sign-in, kept on the phone — else its colour and initials)
    let lp = r["logo"] as? String
    if lp != logoPath {
      logoPath = lp; logo.image = nil; logo.backgroundColor = rgb; ini.isHidden = false
      if let p = lp { FeedLoader.shared.image(p) { [weak self] img in guard let self = self, self.logoPath == p, let img = img else { return }; self.logo.image = img; self.logo.backgroundColor = .white; self.ini.isHidden = true } }
    } else if logo.image == nil { logo.backgroundColor = rgb }
    alpha = inactive ? 0.75 : 1
    setNeedsLayout()
  }
  func paintAms(_ people: [String: [String: Any]]) {
    ams.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for id in amIds {
      let p = people[id]
      let v = UIImageView(image: roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 24))
      v.layer.cornerRadius = 12; v.layer.borderWidth = 2; v.layer.borderColor = (superview?.backgroundColor ?? .systemBackground).cgColor; v.clipsToBounds = true
      v.widthAnchor.constraint(equalToConstant: 24).isActive = true; v.heightAnchor.constraint(equalToConstant: 24).isActive = true
      ams.addArrangedSubview(v)
    }
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    logo.frame = CGRect(x: 16, y: (H - 40) / 2, width: 40, height: 40); ini.frame = logo.bounds
    chev.frame = CGRect(x: W - 16 - 14, y: 0, width: 14, height: H)
    let aw = ams.arrangedSubviews.isEmpty ? 0 : CGFloat(ams.arrangedSubviews.count) * 18 + 6
    ams.frame = CGRect(x: chev.frame.minX - 8 - aw, y: (H - 24) / 2, width: aw, height: 24)
    let tx: CGFloat = 69, tw = max(0, ams.frame.minX - 8 - tx)
    name.frame = CGRect(x: tx, y: H / 2 - 21, width: tw, height: 22)
    meta.frame = CGRect(x: tx, y: H / 2 + 2, width: tw, height: 18)
  }
  override var isHighlighted: Bool { didSet { backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.06) : .clear } }
}

// a client's Client Assets: "Client Assets · See all ›", then its folders in a row that scrolls sideways
final class AssetsStrip: UIView, HomeBlock {
  var onFolder: ((String) -> Void)?, onAll: (() -> Void)?
  private let head = UILabel(), all = UIButton(type: .system), scroll = UIScrollView(), fade = CAGradientLayer()
  // (the fade on a frame that doesn't scroll: on the row itself it moved away with it and hid every folder after the
  //  third, Haris 2026-11-02)
  private let clip = UIView()
  private var tiles: [UIControl] = []
  private var key = ""
  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "assets"
    head.text = "Client Assets"; head.font = .systemFont(ofSize: 16); head.textColor = .secondaryLabel
    var c = UIButton.Configuration.plain()
    c.attributedTitle = AttributedString("See all", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15)]))
    c.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)); c.imagePlacement = .trailing; c.imagePadding = 3
    c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0)
    all.configuration = c
    all.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onAll?() }, for: .touchUpInside)
    scroll.showsHorizontalScrollIndicator = false; scroll.alwaysBounceHorizontal = true; scroll.clipsToBounds = false
    fade.startPoint = CGPoint(x: 0, y: 0.5); fade.endPoint = CGPoint(x: 1, y: 0.5)
    clip.addSubview(scroll)
    [head, all, clip].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ folders: [[String: Any]], look L: HomeLook) {
    let k = folders.map { "\($0["id"] ?? "")|\($0["name"] ?? "")|\($0["files"] ?? 0)" }.joined(separator: ",") + "|\(L.light)"
    if k == key { return }
    key = k
    tiles.forEach { $0.removeFromSuperview() }
    tiles = folders.map { f in
      let t = UIControl(); t.backgroundColor = L.card; t.layer.cornerRadius = 20; t.layer.cornerCurve = .continuous
      let col = NativeSheetVC.color(f["rgb"]) ?? .systemBlue
      let ic = UIImageView(image: UIImage(systemName: "folder.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular))); ic.tintColor = col; ic.contentMode = .left
      let n = UILabel(); n.text = f["name"] as? String; n.font = .systemFont(ofSize: 14, weight: .semibold); n.textColor = L.title; n.lineBreakMode = .byTruncatingTail
      let c = f["files"] as? Int ?? 0
      let s = UILabel(); s.text = "\(c) file\(c == 1 ? "" : "s")"; s.font = .systemFont(ofSize: 12); s.textColor = .secondaryLabel
      [ic, n, s].forEach { $0.isUserInteractionEnabled = false; t.addSubview($0) }
      ic.frame = CGRect(x: 12, y: 12, width: 40, height: 30); n.frame = CGRect(x: 12, y: 50, width: 88, height: 18); s.frame = CGRect(x: 12, y: 69, width: 88, height: 15)
      let id = f["id"] as? String ?? ""
      t.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onFolder?(id) }, for: .touchUpInside)
      _ = PressShrink.add(to: t)
      t.isAccessibilityElement = true; t.accessibilityLabel = "\(f["name"] as? String ?? "Folder"), \(c) files"; t.accessibilityTraits = .button
      scroll.addSubview(t)
      return t
    }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { tiles.isEmpty ? 40 : 40 + 96 + 4 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    head.frame = CGRect(x: 20, y: 6, width: W - 140, height: 28)
    let aw = ceil(all.sizeThatFits(CGSize(width: 200, height: 28)).width)
    all.frame = CGRect(x: W - 20 - aw, y: 6, width: aw, height: 28)
    clip.frame = CGRect(x: 0, y: 40, width: W, height: 96)
    scroll.frame = clip.bounds
    var x: CGFloat = 20
    for t in tiles { t.frame = CGRect(x: x, y: 0, width: 112, height: 96); x += 112 + 10 }
    scroll.contentSize = CGSize(width: x - 10 + 20, height: 96)
    scroll.isHidden = tiles.isEmpty
    // (a soft fade at the right edge when there's more to see, as the file rows)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    if scroll.contentSize.width > W + 1 {
      fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]; fade.locations = [0, 0.86, 1]
      fade.frame = CGRect(x: 0, y: 0, width: W, height: 96); clip.layer.mask = fade
    } else { clip.layer.mask = nil }
    CATransaction.commit()
  }
}

// "Tasks · N open" — Show completed / Hide completed
final class TasksHead: UIView, HomeBlock {
  var onToggle: (() -> Void)?
  private let l = UILabel(), b = UIButton(type: .system)
  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "taskshead"
    l.font = .systemFont(ofSize: 16); l.textColor = .secondaryLabel
    b.titleLabel?.font = .systemFont(ofSize: 15)
    b.addAction(UIAction { [weak self] _ in UISelectionFeedbackGenerator().selectionChanged(); self?.onToggle?() }, for: .touchUpInside)
    addSubview(l); addSubview(b)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(open: Int, showDone: Bool) {
    l.text = "Tasks · \(open) open"
    UIView.performWithoutAnimation { b.setTitle(showDone ? "Hide completed" : "Show completed", for: .normal); b.layoutIfNeeded() }
    setNeedsLayout()
  }
  func blockHeight(_ W: CGFloat) -> CGFloat { 36 }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    let bw = ceil(b.sizeThatFits(CGSize(width: 220, height: 30)).width)
    b.frame = CGRect(x: W - 20 - bw, y: 6, width: bw, height: 30)
    l.frame = CGRect(x: 20, y: 6, width: b.frame.minX - 28, height: 30)
  }
}
