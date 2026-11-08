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
  var onHold: ((String) -> Void)?   // (touch and hold: its sheet — Admins change it, everyone else sees it)
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { (rows + offRows).forEach { $0.paintAms(people) } } } }
  // the active clients in one rounded group; under it "Inactive clients · N" with a chevron — tapped, the inactive ones
  // open in a rounded group of their own, the chevron turning (Haris 2026-11-03: closed whenever the list is made, the
  // heading as it was)
  private let box = UIView(), offBox = UIView(), more = UIButton(type: .system), chev = UIImageView()
  private var rows: [ClientRow] = [], offRows: [ClientRow] = [], lines: [UIView] = [], offLines: [UIView] = []
  private var showInactive = false
  private var data: ([[String: Any]], [[String: Any]]) = ([], [])
  private var L = HomeLook(nil)
  private var made: [String: ClientRow] = [:]
  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "clients"
    for b in [box, offBox] { b.layer.cornerRadius = 26; b.layer.cornerCurve = .continuous; b.clipsToBounds = true; addSubview(b) }
    more.contentHorizontalAlignment = .leading
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    chev.tintColor = .secondaryLabel; chev.contentMode = .center; chev.isUserInteractionEnabled = false
    more.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.showInactive.toggle()
      let opening = self.showInactive
      self.set(self.data.0, self.data.1, look: self.L)
      if opening { self.offRows.forEach { $0.alpha = 0 } }
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        self.chev.transform = opening ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
      }
      // (its screen — over it on the page, or a cell of Apple's list in between: AppleClients.swift)
      var up = self.superview; while let u = up, !(u is HomeView) { up = u.superview }; (up as? HomeView)?.relayout()
      UIView.animate(withDuration: 0.25, delay: opening ? 0.1 : 0, options: [.curveEaseOut, .allowUserInteraction]) {
        self.offRows.forEach { $0.alpha = opening ? 0.75 : 0 }
      }
    }, for: .touchUpInside)
    addSubview(more); addSubview(chev)
  }
  required init?(coder: NSCoder) { fatalError() }
  // (closed again — the Clients tab coming back: it always starts closed)
  func closeInactive() { guard showInactive else { return }; showInactive = false; chev.transform = .identity; set(data.0, data.1, look: L) }
  // (each row kept by its client while it's there — only what changed is drawn again)
  // (Haris 2026-11-03: opening Inactive clients, the whole list flew in a second time — every row was made anew, as the
  // rows kept were looked for in the emptied list, and the new ones grew from the corner inside the list's slide. Now
  // the rows there stay as they are; a new one is made and put in its place with no animation, then only it fades.)
  private var fresh: [ClientRow] = []
  private func row(_ r: [String: Any], inactive: Bool, into b: UIView, from kept: [String: ClientRow]) -> ClientRow {
    let id = r["id"] as? String ?? ""
    let v = kept[id] ?? { let x = ClientRow(); x.id = id; x.onTap = { [weak self] in self?.onOpen?(id) }; x.onHold = { [weak self] in self?.onHold?(id) }; _ = PressShrink.add(to: x); self.fresh.append(x); return x }()
    v.set(r, look: L, inactive: inactive)
    if v.superview !== b { if v.superview != nil { fresh.append(v) }; b.addSubview(v) }
    v.paintAms(people)   // (in its group already: the faces' rims take its colour)
    return v
  }
  private func makeLines(_ n: Int, _ old: [UIView], in b: UIView) -> [UIView] {
    old.dropFirst(n).forEach { $0.removeFromSuperview() }
    var ls = Array(old.prefix(n))
    while ls.count < n { let l = UIView(); l.backgroundColor = .separator; b.addSubview(l); ls.append(l); lineFresh.append(l) }
    return ls
  }
  private var lineFresh: [UIView] = []
  func set(_ active: [[String: Any]], _ inactive: [[String: Any]], look: HomeLook) {
    data = (active, inactive); L = look
    box.backgroundColor = L.card; offBox.backgroundColor = L.card
    let kept = made
    var gone = made; made = [:]
    fresh = []; lineFresh = []
    UIView.performWithoutAnimation {
      rows = active.map { r in let v = row(r, inactive: false, into: box, from: kept); made[v.id] = v; gone[v.id] = nil; return v }
      // (the inactive ones are made while open; closing, they stay in their group as it shrinks away)
      offRows = (showInactive ? inactive : []).map { r in let v = row(r, inactive: true, into: offBox, from: kept); made[v.id] = v; gone[v.id] = nil; return v }
      if !showInactive { for v in gone.values where v.superview === offBox { made[v.id] = v; gone[v.id] = nil } }
      gone.values.forEach { $0.removeFromSuperview() }
      lines = makeLines(max(0, rows.count - 1), lines, in: box)
      offLines = makeLines(max(0, offRows.count - 1), offLines, in: offBox)
      // (what's new stands in its place at once, laid out — never grown from the corner)
      if !fresh.isEmpty || !lineFresh.isEmpty { placeAll(); fresh.forEach { $0.layoutIfNeeded() } }
    }
    more.isHidden = inactive.isEmpty; chev.isHidden = inactive.isEmpty
    more.setAttributedTitle(NSAttributedString(string: "Inactive clients · \(inactive.count)", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel]), for: .normal)
    more.accessibilityLabel = "Inactive clients, \(inactive.count), \(showInactive ? "open" : "closed")"
    setNeedsLayout()
  }
  private var offH: CGFloat { showInactive ? CGFloat(offRows.count) * ClientRow.H + 6 : 0 }
  func blockHeight(_ W: CGFloat) -> CGFloat { CGFloat(rows.count) * ClientRow.H + (more.isHidden ? 0 : 50 + offH) }
  // (the rows and lines inside each group, at the group's width)
  private func placeAll() {
    let px = 1 / max(1, traitCollection.displayScale)
    let w = max(0, bounds.width - 32)
    for (rs, ls) in [(rows, lines), (offRows, offLines)] {
      // (size and place without touching its shrink: a frame set on a shrunk row moved its insides)
      for (i, r) in rs.enumerated() { r.bounds = CGRect(x: 0, y: 0, width: w, height: ClientRow.H); r.center = CGPoint(x: w / 2, y: (CGFloat(i) + 0.5) * ClientRow.H) }
      for (i, l) in ls.enumerated() { l.frame = CGRect(x: 69, y: CGFloat(i + 1) * ClientRow.H - px / 2, width: w - 69, height: px) }
    }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width
    box.frame = CGRect(x: 16, y: 0, width: W - 32, height: CGFloat(rows.count) * ClientRow.H)
    box.isHidden = rows.isEmpty
    placeAll()
    more.frame = CGRect(x: 36, y: box.frame.maxY + 6, width: W - 72, height: 44)
    let tw = ceil(more.attributedTitle(for: .normal)?.size().width ?? 0)
    chev.bounds = CGRect(x: 0, y: 0, width: 16, height: 16); chev.center = CGPoint(x: more.frame.minX + tw + 12, y: more.frame.midY)
    offBox.frame = CGRect(x: 16, y: more.frame.maxY, width: W - 32, height: max(0, offH - 6))
  }
}

final class ClientRow: UIControl {
  static let H: CGFloat = 64
  var id = ""
  var onTap: (() -> Void)?
  var onHold: (() -> Void)? { didSet { if hold == nil { let g = UILongPressGestureRecognizer(target: self, action: #selector(held(_:))); g.minimumPressDuration = 0.45; addGestureRecognizer(g); hold = g } } }
  private var hold: UILongPressGestureRecognizer?
  @objc private func held(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    cancelTracking(with: nil)   // (no tap after the hold)
    onHold?()
    // (springs back as its sheet comes, as the comment cards — Haris 2026-11-03)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in (self?.gestureRecognizers?.first { $0 is PressShrink } as? PressShrink)?.release() }
  }
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
  private var amsSig = ""
  func paintAms(_ people: [String: [String: Any]]) {
    // (the same faces: left as they are — made again, they flew in from the corner inside the list's slide)
    let sig = amIds.map { id in id + (people[id]?["photo"] != nil ? "+" : "") + ((people[id]?["initials"] as? String) ?? "") }.joined(separator: ",") + "|\(traitCollection.userInterfaceStyle.rawValue)|" + ((superview?.backgroundColor).map { "\($0.cgColor.components ?? [])" } ?? "")
    guard sig != amsSig else { return }
    amsSig = sig
    UIView.performWithoutAnimation { paintFaces(people); layoutIfNeeded() }
  }
  private func paintFaces(_ people: [String: [String: Any]]) {
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
  // (no grey while touched: it shrinks as one, as the comment cards — Haris 2026-11-03)
}

// a client's Client Assets: "Client Assets · See all ›", then its folders in a row that scrolls sideways
final class AssetsStrip: UIView, HomeBlock {
  var onFolder: ((String) -> Void)?, onAll: (() -> Void)?
  private let head = UILabel(), all = UIButton(type: .system), scroll = UIScrollView(), fade = CAGradientLayer()
  // (the fade on a frame that doesn't scroll: on the row itself it moved away with it and hid every folder after the
  //  third, Haris 2026-11-02)
  private let clip = UIView()
  private var tiles: [UIControl] = [], made: [String: (UIControl, String)] = [:]
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
  // (each folder kept while it shows the same — only a changed one is made again: the rule for every screen of the app's)
  func set(_ folders: [[String: Any]], look L: HomeLook) {
    var keep = made; made = [:]
    tiles = folders.map { f in
      let fid = f["id"] as? String ?? ""
      let sig = "\(f["name"] ?? "")|\(f["files"] ?? 0)|\(f["rgb"] ?? "")|\(L.light)"
      if let k = keep.removeValue(forKey: fid) {
        if k.1 == sig { made[fid] = k; return k.0 }
        k.0.removeFromSuperview()
      }
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
      made[fid] = (t, sig)
      return t
    }
    keep.values.forEach { $0.0.removeFromSuperview() }
    setNeedsLayout()
  }
  // (another client's page, or one opened again: its folders from the first — Haris 2026-11-06)
  func toStart() { scroll.setContentOffset(CGPoint(x: -scroll.adjustedContentInset.left, y: 0), animated: false) }
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
    for t in tiles { t.bounds = CGRect(x: 0, y: 0, width: 112, height: 96); t.center = CGPoint(x: x + 56, y: 48); x += 112 + 10 }
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

/* ---------- a client, held in the list (Haris 2026-11-02): iPhone's own sheet — Admins change its name, colour,
   Account Managers (on leave) and Social Executives (red − to take off, green + to add, as iPhone's own lists);
   everyone else sees it, read only. ---------- */
final class ClientSheetVC: UITableViewController, UITextFieldDelegate {
  private let row: [String: Any], canEdit: Bool, people: [String: [String: Any]], names: [String: String]
  private let amPool: [String], sePool: [String], smIds: Set<String>
  private var name: String, color: String
  private var ams: [(id: String, onLeave: Bool)], socials: [String]
  // (a new client from the list's + Add client — Haris 2026-11-03; and Active / inactive, as the website's switch)
  private let isNew: Bool
  private var active: Bool
  var onSave: (([String: Any], @escaping (String?) -> Void) -> Void)?
  private static let COLORS = ["#0a84ff", "#30b0c7", "#34c759", "#ff9f0a", "#ff375f", "#af52de", "#5e5ce6", "#8e8e93"]
  init(row: [String: Any], list: [String: Any], people: [String: [String: Any]], dark: Bool, isNew: Bool = false, active: Bool = true) {
    self.row = row
    self.isNew = isNew; self.active = active
    canEdit = (list["canEdit"] as? Bool) == true
    self.people = people
    names = (list["names"] as? [String: String]) ?? [:]
    amPool = (list["amPool"] as? [String]) ?? []; sePool = (list["sePool"] as? [String]) ?? []
    smIds = Set((list["smIds"] as? [String]) ?? [])
    name = row["name"] as? String ?? ""; color = row["color"] as? String ?? ""
    ams = ((row["amsAll"] as? [[String: Any]]) ?? []).compactMap { a in (a["id"] as? String).map { ($0, (a["onLeave"] as? Bool) == true) } }
    socials = (row["socials"] as? [String]) ?? []
    // (a new one: the first colour no client has yet)
    if isNew {
      let used = Set((((list["rows"] as? [[String: Any]]) ?? []) + ((list["inactive"] as? [[String: Any]]) ?? [])).compactMap { ($0["color"] as? String)?.lowercased() })
      color = ClientSheetVC.COLORS.first { !used.contains($0.lowercased()) } ?? ClientSheetVC.COLORS[0]
    }
    super.init(style: .insetGrouped)
    overrideUserInterfaceStyle = dark ? .dark : .light
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = isNew ? "New client" : canEdit ? "Edit client" : "Client"
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    if canEdit {
      navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
      let done = UIBarButtonItem(title: isNew ? "Add" : "Done", primaryAction: UIAction { [weak self] _ in self?.save() })
      done.style = .done
      done.isEnabled = !isNew || !name.trimmingCharacters(in: .whitespaces).isEmpty
      if #available(iOS 26.0, *) { done.tintColor = .systemBlue }
      navigationItem.rightBarButtonItem = done
      tableView.isEditing = true
      tableView.allowsSelectionDuringEditing = true
    } else {
      navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
      tableView.tableHeaderView = hero()
      let f = UILabel(); f.text = "Only Admins change clients."; f.font = .systemFont(ofSize: 13); f.textColor = .secondaryLabel; f.textAlignment = .center
      f.frame = CGRect(x: 0, y: 0, width: 300, height: 50); tableView.tableFooterView = f
    }
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); if navigationController?.topViewController === self, navigationController?.transitionCoordinator == nil { (navigationController as? FitNav)?.fitTo(tableView) } }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); (navigationController as? FitNav)?.fitTo(tableView) }   // (back from a list: someone added — its size now)
  private func rgb() -> UIColor { UIColor(hex: color) ?? NativeSheetVC.color(row["rgb"]) ?? .systemGray }
  private func logoView(_ size: CGFloat) -> UIView {
    let v = UIImageView(); v.backgroundColor = rgb(); v.layer.cornerRadius = size * 0.27; v.layer.cornerCurve = .continuous; v.clipsToBounds = true; v.contentMode = .scaleAspectFill
    let l = UILabel(); l.text = row["ini"] as? String; l.font = .systemFont(ofSize: size * 0.34, weight: .heavy); l.textColor = .white; l.textAlignment = .center
    l.frame = CGRect(x: 0, y: 0, width: size, height: size); v.addSubview(l)
    if let p = row["logo"] as? String { FeedLoader.shared.image(p) { img in if let img = img { v.image = img; v.backgroundColor = .white; l.isHidden = true } } }
    v.frame = CGRect(x: 0, y: 0, width: size, height: size)
    return v
  }
  private func hero() -> UIView {
    let h = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 150))
    let lg = logoView(64); lg.frame.origin = CGPoint(x: 0, y: 8); lg.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
    let n = UILabel(); n.text = name; n.font = .systemFont(ofSize: 20, weight: .semibold); n.textAlignment = .center
    let open = row["open"] as? Int ?? 0, late = row["late"] as? Int ?? 0
    let s = UILabel(); s.text = "\(open) open" + (late > 0 ? " · \(late) overdue" : ""); s.font = .systemFont(ofSize: 13); s.textColor = .secondaryLabel; s.textAlignment = .center
    [lg, n, s].forEach { h.addSubview($0) }
    n.frame = CGRect(x: 0, y: 84, width: 320, height: 26); s.frame = CGRect(x: 0, y: 110, width: 320, height: 18)
    [n, s].forEach { $0.autoresizingMask = [.flexibleWidth] }
    lg.center.x = h.bounds.midX
    return h
  }
  // sections: (edit) 0 name · 1 colour · 2 Account Managers · 3 Social Executives · 4 Active — (read only) 0 AMs · 1 SEs
  private func kind(_ s: Int) -> String { canEdit ? ["name", "color", "ams", "ses", "active"][s] : ["ams", "ses"][s] }
  override func numberOfSections(in tv: UITableView) -> Int { canEdit ? 5 : 2 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int {
    switch kind(s) {
    case "ams": return ams.count + (canEdit ? 1 : 0) + (!canEdit && ams.isEmpty ? 1 : 0)
    case "ses": return socials.count + (canEdit ? 1 : 0) + (!canEdit && socials.isEmpty ? 1 : 0)
    default: return 1
    }
  }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? {
    ["name": nil, "color": "Colour", "ams": "Account Managers", "ses": "Social Executives"][kind(s)] ?? nil
  }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    if kind(s) == "active" { return active ? "Shows in the client lists." : "Hidden from everyone with its tasks, Client Assets and Finance history until switched back on. Nothing is deleted." }
    guard kind(s) == "ams", !canEdit else { return nil }
    let away = ams.filter { $0.onLeave }.map { first($0.id) }, here = ams.filter { !$0.onLeave }.map { first($0.id) }
    guard let a = away.first, let c = here.first else { return nil }
    return "\(a) is on leave — \(c) covers."
  }
  private func first(_ id: String) -> String { (names[id] ?? "Someone").split(separator: " ").first.map(String.init) ?? "Someone" }
  private func avatar(_ id: String) -> UIImage? {
    let p = people[id]
    return roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 34)
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    c.selectionStyle = .none
    switch kind(ip.section) {
    case "name":
      let lg = logoView(34)
      let f = UITextField(); f.text = name; f.font = .systemFont(ofSize: 17); f.clearButtonMode = .whileEditing; f.returnKeyType = .done; f.delegate = self
      f.addAction(UIAction { [weak self, weak f] _ in
        guard let self = self else { return }
        self.name = f?.text ?? ""
        if self.isNew { self.navigationItem.rightBarButtonItem?.isEnabled = !self.name.trimmingCharacters(in: .whitespaces).isEmpty }
      }, for: .editingChanged)
      f.placeholder = "Client name"
      if isNew { DispatchQueue.main.async { [weak f] in f?.becomeFirstResponder() } }
      let s = UIStackView(arrangedSubviews: [lg, f]); s.spacing = 12; s.alignment = .center
      lg.widthAnchor.constraint(equalToConstant: 34).isActive = true; lg.heightAnchor.constraint(equalToConstant: 34).isActive = true
      s.translatesAutoresizingMaskIntoConstraints = false; c.contentView.addSubview(s)
      NSLayoutConstraint.activate([s.leadingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.leadingAnchor), s.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor), s.topAnchor.constraint(equalTo: c.contentView.topAnchor, constant: 8), s.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor, constant: -8)])
    case "color":
      let s = UIStackView(); s.spacing = 12; s.alignment = .center
      for hx in ClientSheetVC.COLORS {
        let b = UIButton(type: .custom); b.backgroundColor = UIColor(hex: hx); b.layer.cornerRadius = 15
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true; b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        if hx.lowercased() == color.lowercased() { b.layer.borderWidth = 3; b.layer.borderColor = UIColor.label.cgColor }
        b.accessibilityLabel = "Colour"
        b.addAction(UIAction { [weak self] _ in UISelectionFeedbackGenerator().selectionChanged(); self?.color = hx; self?.tableView.reloadSections(IndexSet([0, 1]), with: .none) }, for: .touchUpInside)
        s.addArrangedSubview(b)
      }
      s.translatesAutoresizingMaskIntoConstraints = false; c.contentView.addSubview(s)
      NSLayoutConstraint.activate([s.leadingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.leadingAnchor), s.topAnchor.constraint(equalTo: c.contentView.topAnchor, constant: 10), s.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor, constant: -10)])
    case "active":
      c.textLabel?.text = "Active client"
      let sw = UISwitch(); sw.isOn = active
      sw.addAction(UIAction { [weak self, weak sw] _ in
        guard let self = self, let sw = sw else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        self.active = sw.isOn
        UIView.performWithoutAnimation { self.tableView.reloadSections(IndexSet([ip.section]), with: .none) }   // (its line under)
        (self.navigationController as? FitNav)?.fitTo(self.tableView)
      }, for: .valueChanged)
      c.editingAccessoryView = sw
    case "ams", "ses":
      let isAm = kind(ip.section) == "ams"
      let n = isAm ? ams.count : socials.count
      if ip.row >= n {
        if canEdit { c.textLabel?.text = isAm ? "Add Account Manager" : "Add Social Executive"; c.textLabel?.textColor = .systemBlue; c.selectionStyle = .default }
        else { c.textLabel?.text = isAm ? "None yet" : "No Social Executive yet"; c.textLabel?.textColor = .secondaryLabel }
        return c
      }
      let id = isAm ? ams[ip.row].id : socials[ip.row]
      c.imageView?.image = avatar(id)
      c.textLabel?.text = names[id] ?? "Former member"
      c.detailTextLabel?.textColor = .secondaryLabel
      if isAm {
        if ip.row == 0 { c.detailTextLabel?.text = "Main" }
        let away = ams[ip.row].onLeave
        if canEdit {
          let sw = UISwitch(); sw.isOn = away; sw.onTintColor = .systemOrange
          sw.addAction(UIAction { [weak self, weak sw] _ in guard let self = self, let sw = sw, ip.row < self.ams.count else { return }; self.ams[ip.row].onLeave = sw.isOn }, for: .valueChanged)
          let l = UILabel(); l.text = "On leave"; l.font = .systemFont(ofSize: 13); l.textColor = .secondaryLabel
          let s = UIStackView(arrangedSubviews: [l, sw]); s.spacing = 8; s.alignment = .center
          s.frame = CGRect(origin: .zero, size: s.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
          c.editingAccessoryView = s
        } else if away {
          let t = UILabel(); t.text = " On leave "; t.font = .systemFont(ofSize: 12, weight: .bold); t.textColor = .systemOrange
          t.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15); t.layer.cornerRadius = 7; t.clipsToBounds = true; t.sizeToFit(); t.frame.size.height = 22
          c.accessoryView = t
        }
      } else if smIds.contains(id) { c.detailTextLabel?.text = "Social Manager" }
    default: break
    }
    return c
  }
  override func tableView(_ tv: UITableView, editingStyleForRowAt ip: IndexPath) -> UITableViewCell.EditingStyle {
    guard canEdit else { return .none }
    let k = kind(ip.section)
    guard k == "ams" || k == "ses" else { return .none }
    return ip.row >= (k == "ams" ? ams.count : socials.count) ? .insert : .delete
  }
  override func tableView(_ tv: UITableView, shouldIndentWhileEditingRowAt ip: IndexPath) -> Bool { ["ams", "ses"].contains(kind(ip.section)) }
  override func tableView(_ tv: UITableView, commit style: UITableViewCell.EditingStyle, forRowAt ip: IndexPath) {
    let isAm = kind(ip.section) == "ams"
    if style == .delete {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      if isAm { ams.remove(at: ip.row) } else { socials.remove(at: ip.row) }
      tv.deleteRows(at: [ip], with: .automatic)
      if isAm { tv.reloadSections(IndexSet([ip.section]), with: .none) }   // ("Main": the first one)
    } else if style == .insert { pick(isAm) }
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    let k = kind(ip.section)
    guard canEdit, k == "ams" || k == "ses", ip.row >= (k == "ams" ? ams.count : socials.count) else { return }
    pick(k == "ams")
  }
  // the people to add: pushed in this sheet, those not on it yet
  private func pick(_ isAm: Bool) {
    let have = Set(isAm ? ams.map { $0.id } : socials)
    let pool = (isAm ? amPool : sePool).filter { !have.contains($0) }
    let vc = PeoplePickVC(ids: pool, names: names, sub: isAm ? [:] : Dictionary(uniqueKeysWithValues: smIds.map { ($0, "Social Manager") }), avatar: { [weak self] in self?.avatar($0) }) { [weak self] id in
      guard let self = self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      if isAm { self.ams.append((id, false)) } else { self.socials.append(id) }
      self.tableView.reloadData()
      self.navigationController?.popViewController(animated: true)
    }
    vc.title = isAm ? "Add Account Manager" : "Add Social Executive"
    vc.overrideUserInterfaceStyle = overrideUserInterfaceStyle
    navigationController?.pushViewController(vc, animated: true)
  }
  func textFieldShouldReturn(_ f: UITextField) -> Bool { f.resignFirstResponder(); return true }
  private func save() {
    view.endEditing(true)
    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !n.isEmpty else { alert("A client needs a name"); return }
    navigationItem.rightBarButtonItem?.isEnabled = false
    let body: [String: Any] = ["name": n, "color": color, "ams": ams.map { $0.onLeave ? ["id": $0.id, "onLeave": true] : ["id": $0.id] }, "socials": socials, "active": active]
    onSave?(body) { [weak self] err in
      guard let self = self else { return }
      if let e = err { self.navigationItem.rightBarButtonItem?.isEnabled = true; UINotificationFeedbackGenerator().notificationOccurred(.error); self.alert(e); return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      self.dismiss(animated: true)
    }
  }
  private func alert(_ t: String) { let a = UIAlertController(title: t, message: nil, preferredStyle: .alert); a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true) }
}

// a sheet of lists that's as tall as what's on it (as the morning round-up), up to nearly the whole screen; a list
// pushed onto it (Add Account Manager…) grows or shrinks it to fit too, with the sheet's own animation (Haris 2026-11-02)
final class FitNav: UINavigationController {
  private var fit: CGFloat = 360, measured = false
  override func viewDidLoad() {
    super.viewDidLoad()
    sheetPresentationController?.detents = [.custom(identifier: .init("fitList")) { [weak self] ctx in min(ctx.maximumDetentValue, self?.fit ?? 360) }]
  }
  // measured before it comes up — it came up at a guess and then grew to its size, half first and then full (Haris
  // 2026-11-03 07:38): its list laid out at the screen's width, its bar's height on top
  func prepare(width: CGFloat, bottom: CGFloat) {
    guard let t = (viewControllers.first as? UITableViewController)?.tableView else { return }
    loadViewIfNeeded(); _ = viewControllers.first?.view
    t.frame = CGRect(x: 0, y: 0, width: width, height: 3000)
    t.reloadData(); t.layoutIfNeeded()
    let floating: Bool; if #available(iOS 26, *) { floating = true } else { floating = false }
    // (a little room to spare: measured again once it's up, a few points more made it grow a little after coming —
    //  Haris 2026-11-03 08:10; now it only changes size for a real change, such as a row added)
    fit = ceil(64 + t.contentSize.height + 16 + (floating ? 0 : bottom))
    measured = true; settled = false
  }
  private var settled = true
  func fitTo(_ table: UITableView) {
    table.layoutIfNeeded()
    let floating: Bool; if #available(iOS 26, *) { floating = true } else { floating = false }
    let h = ceil(navigationBar.frame.maxY + table.contentSize.height + table.adjustedContentInset.bottom - view.safeAreaInsets.bottom + 8 + (floating ? 0 : view.safeAreaInsets.bottom))
    guard abs(h - fit) > 0.5 else { return }
    // (its first measure once up: only if it's really off — no growing or shrinking by a few points as it settles)
    if !settled { settled = true; if h <= fit && fit - h < 48 { table.isScrollEnabled = false; return } }
    fit = h
    table.isScrollEnabled = h > view.window.map { $0.bounds.height * 0.9 } ?? 700
    let first = !measured; measured = true
    // (outside the layout pass; the first time with no animation — the sheet comes up already its size)
    DispatchQueue.main.async { [weak self] in
      guard let sh = self?.sheetPresentationController else { return }
      if first { sh.invalidateDetents() } else { sh.animateChanges { sh.invalidateDetents() } }
    }
  }
}

final class PeoplePickVC: UITableViewController {
  private let ids: [String], names: [String: String], sub: [String: String], avatar: (String) -> UIImage?, picked: (String) -> Void
  init(ids: [String], names: [String: String], sub: [String: String], avatar: @escaping (String) -> UIImage?, picked: @escaping (String) -> Void) {
    self.ids = ids; self.names = names; self.sub = sub; self.avatar = avatar; self.picked = picked
    super.init(style: .insetGrouped)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { max(1, ids.count) }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    guard !ids.isEmpty else { c.textLabel?.text = "Everyone is on it already"; c.textLabel?.textColor = .secondaryLabel; c.selectionStyle = .none; return c }
    let id = ids[ip.row]
    c.imageView?.image = avatar(id); c.textLabel?.text = names[id] ?? ""; c.detailTextLabel?.text = sub[id]; c.detailTextLabel?.textColor = .secondaryLabel
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) { tv.deselectRow(at: ip, animated: true); if !ids.isEmpty { picked(ids[ip.row]) } }
  // (no resizing of the sheet for it: the sheet changing height while the pages slid cut the client's list off —
  //  Haris 2026-11-02 23:00; it scrolls in the room the sheet has)
}

extension UIColor {
  convenience init?(hex: String) {
    var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    self.init(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
  }
}
