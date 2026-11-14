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

// ---------- the Clients list, fully Apple (Haris 2026-11-10, mock-up "Clients — with the rules", approved 12:33) ----------
// Each client is Apple's own list cell in Apple's inset group: its logo whole on its own background (LogoLook) or its colour
// with initials, its name, "9 open · 1 overdue", Apple's ›. Ours, inside Apple's cell (said plainly): its Account Managers'
// faces at the right. Held: Apple's menu with its lift (Open · Client Assets · Client Details). The inactive ones: an Apple
// row "Inactive Clients" with their number, tapped they come in under it with Apple's own list animation.
final class ClientListRow: UIView, AppleRow {
  var id = ""
  var onTap: (() -> Void)?
  var onLook: (() -> Void)?   // (its logo came after it was drawn: its cell set again)
  private(set) var rowContent = UIListContentConfiguration.subtitleCell()
  private(set) var rowSig = ""
  var rowHasAccessory: Bool { !amIds.isEmpty }
  var rowLeading: Bool { false }
  var rowLate: Bool { false }
  func rowTapped() { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap?() }
  private var r: [String: Any] = [:], inactive = false, L = HomeLook(nil)
  private var amIds: [String] = [], logoPath: String?, logo: UIImage?
  private let faces = UIStackView()
  var name: String { r["name"] as? String ?? "" }
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    faces.spacing = -6; faces.alignment = .center
    addSubview(faces)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ r: [String: Any], inactive: Bool, look: HomeLook, people: [String: [String: Any]]) {
    let probeT = Probe.now(); defer { Probe.sum("a client row set (Clients.swift)", probeT) }   // (TEMPORARY speed report)
    self.r = r; self.inactive = inactive; L = look
    // its logo: from the phone at once when it's kept there, else fetched once and the cell set again
    let lp = r["logo"] as? String
    if lp != logoPath {
      logoPath = lp; logo = nil
      if let p = lp {
        var now = true
        FeedLoader.shared.image(p) { [weak self] img in
          guard let self = self, self.logoPath == p, let img = img else { return }
          self.logo = LogoLook.tile(img, key: p, side: 40, radius: 11)
          if !now { self.paint(people); self.onLook?() }
        }
        now = false
      }
    }
    amIds = (r["ams"] as? [String]) ?? []
    paint(people)
  }
  private var facesSig = ""
  private func paint(_ people: [String: [String: Any]]) {
    let fs = amIds.map { id in id + (people[id]?["photo"] != nil ? "+" : "") + ((people[id]?["initials"] as? String) ?? "") }.joined(separator: ",")
    let sig = drawSig(r) + "|\(inactive)|\(L.key)|\(logo != nil)|" + fs
    guard sig != rowSig else { return }
    rowSig = sig
    var cfg = UIListContentConfiguration.subtitleCell()
    cfg.image = logo ?? ClientListRow.initialsTile(r["ini"] as? String ?? "", NativeSheetVC.color(r["rgb"]) ?? .systemGray)
    cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
    cfg.imageProperties.maximumSize = CGSize(width: 40, height: 40)
    cfg.imageToTextPadding = 13
    cfg.text = name
    cfg.textProperties.font = .systemFont(ofSize: 17, weight: .medium)
    cfg.textProperties.color = inactive ? .secondaryLabel : L.title
    cfg.textProperties.numberOfLines = 1
    let open = r["open"] as? Int ?? 0, late = r["late"] as? Int ?? 0
    let m = NSMutableAttributedString(string: "\(open) open", attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel])
    if late > 0 {
      m.append(NSAttributedString(string: " · ", attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel]))
      m.append(NSAttributedString(string: "\(late) overdue", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: L.late]))
    }
    cfg.secondaryAttributedText = m
    cfg.textToSecondaryTextVerticalPadding = 2
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 8)
    rowContent = cfg
    accessibilityLabel = "\(name), \(open) open\(late > 0 ? ", \(late) overdue" : "")"
    if fs != facesSig {
      facesSig = fs
      UIView.performWithoutAnimation {
        faces.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for id in amIds {
          let p = people[id]
          let v = UIImageView(image: roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 24))
          v.layer.cornerRadius = 12; v.clipsToBounds = true; v.layer.borderWidth = 2
          let ring = L.card
          v.followLook("ring") { [weak v] tc in v?.layer.setBorder(ring, tc) }
          v.widthAnchor.constraint(equalToConstant: 24).isActive = true; v.heightAnchor.constraint(equalToConstant: 24).isActive = true
          faces.addArrangedSubview(v)
        }
        let w = amIds.isEmpty ? 0 : CGFloat(amIds.count) * 18 + 6
        frame = CGRect(x: 0, y: 0, width: w, height: 24); faces.frame = bounds
      }
    }
  }
  // a client with no logo: its colour with its initials (as search's client rows)
  static func initialsTile(_ ini: String, _ col: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { _ in
      col.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 11).fill()
      let f = UIFont.systemFont(ofSize: 14, weight: .bold), s = (ini as NSString).size(withAttributes: [.font: f])
      (ini as NSString).draw(at: CGPoint(x: (40 - s.width) / 2, y: (40 - s.height) / 2), withAttributes: [.font: f, .foregroundColor: UIColor.white])
    }.withRenderingMode(.alwaysOriginal)
  }
}

// "Inactive Clients · N" — Apple's row; tapped, the inactive ones come in under it (its chevron turns down) and go again
final class ClientsMoreRow: UIView, AppleRow {
  var onTap: (() -> Void)?
  var open = false { didSet { if open != oldValue { UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) { self.chev.transform = self.open ? CGAffineTransform(rotationAngle: .pi / 2) : .identity }; rowSig = "" ; paint() } } }
  var count = 0 { didSet { if count != oldValue { paint() } } }
  private(set) var rowContent = UIListContentConfiguration.valueCell()
  private(set) var rowSig = ""
  var rowHasAccessory: Bool { true }
  var rowChevron: Bool { false }
  var rowLeading: Bool { false }
  var rowLate: Bool { false }
  func rowTapped() { UISelectionFeedbackGenerator().selectionChanged(); onTap?() }
  private let chev = UIImageView()
  override init(frame: CGRect) {
    super.init(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
    isUserInteractionEnabled = false
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    chev.tintColor = .tertiaryLabel; chev.contentMode = .center; chev.frame = bounds
    addSubview(chev)
    accessibilityIdentifier = "clients-inactive"
    paint()
  }
  required init?(coder: NSCoder) { fatalError() }
  private func paint() {
    var c = UIListContentConfiguration.valueCell()
    c.text = "Inactive Clients"; c.textProperties.color = .secondaryLabel
    c.secondaryText = "\(count)"
    rowContent = c
    rowSig = "\(count)|\(open)"
    accessibilityLabel = "Inactive clients, \(count), \(open ? "open" : "closed")"
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
  init(row: [String: Any], list: [String: Any], people: [String: [String: Any]], isNew: Bool = false, active: Bool = true) {
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
    if let p = row["logo"] as? String { FeedLoader.shared.image(p) { img in if let img = img { LogoLook.put(img, key: p, in: v); l.isHidden = true } } }
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
        if hx.lowercased() == color.lowercased() { b.layer.borderWidth = 3; b.followLook("ring") { [weak b] tc in b?.layer.setBorder(.label, tc) } }
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
  private var fit: CGFloat = 360, measured = false, appeared = false
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); appeared = true }
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
    measured = true
    // (still coming up — its real size found as it lays out in the sheet: told at once, so the slide goes straight to it.
    //  Told a moment later and animated, the sheet slid up to its guess and then grew — "jumps before settling down": Haris
    //  2026-11-10 15:01. Once up, a real change — a row added — animates as Apple's own.)
    guard let sh = sheetPresentationController else { return }
    if !appeared { sh.invalidateDetents(); return }
    DispatchQueue.main.async { sh.animateChanges { sh.invalidateDetents() } }
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
