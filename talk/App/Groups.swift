import UIKit
import PhotosUI

/* New group (the mockup): its name, its client (the picture is the client's logo from Client Assets — it can be
   changed later), the people. Anyone on the staff makes groups (not freelancers); only the group's admins add people.
   Group info: its picture and name, its people (admins marked), Mute, Pin; for its admins Add people, Rename, Change
   picture, Remove someone, and — the creator — pick one second admin; Super Admins and Office Admins "Make me admin"
   and can take anyone's admin away (the creator's too). Leave group; Delete group (admins). (Haris 2026-11-05 / 06) */
final class NewGroupVC: UITableViewController, UITextFieldDelegate, UISearchBarDelegate {
  private var client: String?
  private var picked = Set<String>()
  private let name = UITextField()
  private let pic = Avatar(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
  private var q = ""
  private let find = UISearchBar()
  private let forClient: Bool
  init(client: String?, forClient: Bool = false) { self.client = client; self.forClient = forClient; super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "New group"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Create", primaryAction: UIAction { [weak self] _ in self?.create() })
    navigationItem.rightBarButtonItem?.style = .done
    name.placeholder = "Group name — a campaign, a shoot, an event…"; name.font = .systemFont(ofSize: 17); name.clearButtonMode = .whileEditing
    name.delegate = self; name.returnKeyType = .done
    name.addAction(UIAction { [weak self] _ in self?.check() }, for: .editingChanged)
    find.placeholder = "Search the team"; find.searchBarStyle = .minimal; find.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    tableView.keyboardDismissMode = .onDrag
    if client == nil, Talk.shared.clientOrder.count == 1 { client = Talk.shared.clientOrder.first }
    check()
  }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); name.becomeFirstResponder() }
  private func check() { navigationItem.rightBarButtonItem?.isEnabled = client != nil && !(name.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
  func textFieldShouldReturn(_ t: UITextField) -> Bool { t.resignFirstResponder(); return true }
  func searchBar(_ s: UISearchBar, textDidChange t: String) { q = t.lowercased(); tableView.reloadSections([2], with: .none) }

  // the team, and — for Super / Office Admins — the picked client's contacts first (adding one makes it a client group)
  private var people: [Person] {
    let T = Talk.shared, me = T.me?.id
    let match: (String, String) -> Bool = { [q] n, r in q.isEmpty || n.lowercased().contains(q) || r.lowercased().contains(q) }
    let team = T.people.values.filter { $0.id != me && !$0.gone && !$0.contact && match($0.name, $0.role) }.sorted { $0.name < $1.name }
    guard T.boss, let c = client else { return team }
    let cname = T.clients[c]?.name ?? "Client"
    let ks = T.contacts.filter { $0.client == c && match($0.name, cname) }.map { Person(id: $0.id, name: $0.name, role: "\(cname) · client", photo: nil, color: nil, gone: false, contact: true, client: c) }
    return ks + team
  }
  override func numberOfSections(in tv: UITableView) -> Int { 3 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? 1 : s == 1 ? 1 : people.count + 1 }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { s == 1 ? "Client" : s == 2 ? "People · \(picked.count)" : nil }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == 0 ? "The picture is the client’s logo from Client Assets — you can change it later."
      : s == 2 ? (Talk.shared.boss ? "Adding a client contact makes it a client group — the client can see it. Only Super Admins and Office Admins can." : "Only the group’s admins add people. Nobody joins by themselves; anyone can leave.") : nil
  }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { ip.section == 0 ? 76 : ip.section == 2 && ip.row > 0 ? 58 : 50 }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    switch ip.section {
    case 0:
      c.selectionStyle = .none
      if let cl = client.flatMap({ Talk.shared.clients[$0] }) { pic.set(client: cl) } else { pic.set(name: "?", color: .systemGray3, picture: nil) }
      pic.frame = CGRect(x: 16, y: 10, width: 56, height: 56); c.contentView.addSubview(pic)
      name.frame = CGRect(x: 84, y: 18, width: tv.bounds.width - 84 - 48, height: 40); c.contentView.addSubview(name)
    case 1:
      var cfg = c.defaultContentConfiguration()
      if let cl = client.flatMap({ Talk.shared.clients[$0] }) { cfg.text = cl.name } else { cfg.text = "Pick a client"; cfg.textProperties.color = .secondaryLabel }
      c.contentConfiguration = cfg; c.accessoryType = .disclosureIndicator
    default:
      if ip.row == 0 { c.selectionStyle = .none; find.frame = c.contentView.bounds.insetBy(dx: 4, dy: 0); find.autoresizingMask = [.flexibleWidth, .flexibleHeight]; c.contentView.addSubview(find); return c }
      let p = people[ip.row - 1]
      var cfg = c.defaultContentConfiguration()
      cfg.text = p.name; cfg.secondaryText = p.role; cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
      c.contentConfiguration = cfg
      let a = Avatar(frame: CGRect(x: 16, y: 9, width: 40, height: 40)); a.set(person: p); c.contentView.addSubview(a)
      let on = picked.contains(p.id)
      let tick = UIImageView(image: UIImage(systemName: on ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)))
      tick.tintColor = on ? Look.accent : .tertiaryLabel; c.accessoryView = tick
    }
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    if ip.section == 1 {
      let pick = ClientPickVC(selected: client) { [weak self] id in
        guard let self = self else { return }
        self.client = id
        self.picked = self.picked.filter { pid in !pid.hasPrefix("k-") || Talk.shared.contacts.first(where: { $0.id == pid })?.client == id }   // (another client's contacts leave the list)
        self.check(); self.tableView.reloadData()
      }
      navigationController?.pushViewController(pick, animated: true)
    } else if ip.section == 2, ip.row > 0 {
      let p = people[ip.row - 1]
      if picked.contains(p.id) { picked.remove(p.id) } else { picked.insert(p.id) }
      UISelectionFeedbackGenerator().selectionChanged()
      tv.reloadRows(at: [ip], with: .none)
      tv.headerView(forSection: 2)?.textLabel?.text = "PEOPLE · \(picked.count)"
    }
  }
  private func create() {
    guard let c = client else { return }
    let n = (name.text ?? "").trimmingCharacters(in: .whitespaces)
    navigationItem.rightBarButtonItem?.isEnabled = false
    Net.shared.act(["act": "newGroup", "client": c, "name": n, "members": Array(picked)]) { [weak self] j in
      guard let self = self else { return }
      guard (j?["ok"] as? Bool) == true, let g = (j?["group"] as? [String: Any])?["id"] as? String else {
        toast(j?["error"] as? String ?? "Couldn’t make the group — try again"); self.check(); return
      }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      let host = self.presentingViewController
      Talk.shared.refresh {
        Talk.shared.sync()
        self.dismiss(animated: true) {
          let nav = (host as? UITabBarController)?.selectedViewController as? UINavigationController ?? host as? UINavigationController
          nav?.pushViewController(ChatVC(group: g), animated: true)
        }
      }
    }
  }
}

final class ClientPickVC: UITableViewController, UISearchResultsUpdating {
  private let selected: String?, done: (String) -> Void
  private let search = UISearchController(searchResultsController: nil)
  init(selected: String?, done: @escaping (String) -> Void) { self.selected = selected; self.done = done; super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var list: [Client] {
    let q = (search.searchBar.text ?? "").lowercased()
    return Talk.shared.clientOrder.compactMap { Talk.shared.clients[$0] }.filter { q.isEmpty || $0.name.lowercased().contains(q) }
  }
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Client"
    search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; search.searchBar.placeholder = "Search clients"
    navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
  }
  func updateSearchResults(for s: UISearchController) { tableView.reloadData() }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { list.count }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { 54 }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .default, reuseIdentifier: nil), cl = list[ip.row]
    var cfg = c.defaultContentConfiguration(); cfg.text = cl.name
    cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 34, height: 34)
    c.contentConfiguration = cfg
    let a = Avatar(frame: CGRect(x: 16, y: 10, width: 34, height: 34)); a.set(client: cl); c.contentView.addSubview(a)
    c.accessoryType = cl.id == selected ? .checkmark : .none
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) { done(list[ip.row].id); navigationController?.popViewController(animated: true) }
}

// ---------- group info ----------
final class GroupInfoVC: UITableViewController, PHPickerViewControllerDelegate {
  /* Group Info — the approved design's boards 23 and 24 (Haris 2026-11-12: "Start Group Info"). Apple's inset list:
     the picture, name and "client · N members" with Search · Mute · Edit; Photos, Files and Links with the latest four;
     the members (Admin chip, a client in orange, You), + Add Members; Mute and Make Me Admin; Second Admin with what it
     means; Leave and Delete, then who made it and when. Rows kept by what they show — only a row that changed is drawn again. */
  let group: String
  init(group: String) { self.group = group; super.init(style: .insetGrouped); hidesBottomBarWhenPushed = true }
  required init?(coder: NSCoder) { fatalError() }
  private var g: Group? { Talk.shared.groups[group] }
  enum Row: Hashable { case media, member(String), addMembers, mute, makeMeAdmin, second, leave, delete }
  private var data: UITableViewDiffableDataSource<Int, Row>!
  private var sigs: [Row: Int] = [:]
  private let head = UIView(), pic = Avatar(frame: CGRect(x: 0, y: 0, width: 116, height: 116)), nameL = UILabel(), subL = UILabel()
  private let acts = UIStackView()
  private var members: [String] {
    guard let g = g else { return [] }
    let me = Talk.shared.me?.id
    return g.members.sorted { a, b in
      let aa = g.admins.contains(a), ba = g.admins.contains(b)
      if aa != ba { return aa }
      if (a == me) != (b == me) { return b == me }   // (You last)
      return Talk.shared.name(a) < Talk.shared.name(b)
    }
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Group Info"; navigationItem.largeTitleDisplayMode = .never
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    tableView.sectionHeaderTopPadding = 8
    data = UITableViewDiffableDataSource(tableView: tableView) { [weak self] tv, ip, row in
      let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip); self?.fill(c, row); return c
    }
    data.defaultRowAnimation = .fade
    buildHead()
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(gone(_:)), name: .talkGone, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkGroup, object: group)
    reload(animated: false)
  }
  @objc private func changed() { if g == nil { navigationController?.popToRootViewController(animated: true); return }; reload(animated: view.window != nil) }
  @objc private func gone(_ n: Notification) { if (n.object as? String) == group { navigationController?.popToRootViewController(animated: true) } }

  // the top: the picture, the name, "client · N members", and Search · Mute · Edit as three cards
  private func buildHead() {
    pic.translatesAutoresizingMaskIntoConstraints = false
    nameL.font = .systemFont(ofSize: 26, weight: .bold); nameL.textAlignment = .center; nameL.numberOfLines = 2
    subL.font = .systemFont(ofSize: 15); subL.textColor = .secondaryLabel; subL.textAlignment = .center
    acts.axis = .horizontal; acts.distribution = .fillEqually; acts.spacing = 10
    let col = UIStackView(arrangedSubviews: [pic, nameL, subL, acts]); col.axis = .vertical; col.alignment = .center; col.spacing = 4
    col.setCustomSpacing(12, after: pic); col.setCustomSpacing(16, after: subL)
    col.translatesAutoresizingMaskIntoConstraints = false; head.addSubview(col)
    NSLayoutConstraint.activate([pic.widthAnchor.constraint(equalToConstant: 116), pic.heightAnchor.constraint(equalToConstant: 116),
      col.topAnchor.constraint(equalTo: head.topAnchor, constant: 4), col.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 20),
      col.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -20), col.bottomAnchor.constraint(equalTo: head.bottomAnchor, constant: -4),
      acts.widthAnchor.constraint(equalTo: col.widthAnchor), acts.heightAnchor.constraint(equalToConstant: 62)])
    tableView.tableHeaderView = head
  }
  private var headSig = 0
  // (a new picture: on show at once, dimmed with Apple's spinner until it's in — Haris 2026-11-13)
  private var picBusy = false
  private lazy var picSpin: UIActivityIndicatorView = {
    let s = UIActivityIndicatorView(style: .medium); s.color = .white; s.hidesWhenStopped = true
    s.backgroundColor = UIColor.black.withAlphaComponent(0.35); s.layer.cornerRadius = 58; s.clipsToBounds = true
    s.translatesAutoresizingMaskIntoConstraints = false; pic.addSubview(s)
    NSLayoutConstraint.activate([s.leadingAnchor.constraint(equalTo: pic.leadingAnchor), s.trailingAnchor.constraint(equalTo: pic.trailingAnchor), s.topAnchor.constraint(equalTo: pic.topAnchor), s.bottomAnchor.constraint(equalTo: pic.bottomAnchor)])
    return s
  }()
  private func picUploading(_ on: Bool, _ img: UIImage? = nil) {
    picBusy = on
    if on { if let i = img { pic.show(i) }; picSpin.startAnimating() } else { picSpin.stopAnimating(); headSig = 0; if let g = g { fillHead(g) } }
  }
  private func fillHead(_ g: Group) {
    let T = Talk.shared, can = T.canManage(g)
    var h = Hasher(); h.combine(g.name); h.combine(g.pic); h.combine(g.members.count); h.combine(can); h.combine(g.muted); h.combine(T.clients[g.client]?.name); h.combine(T.clients[g.client]?.logo)
    let sig = h.finalize(); guard sig != headSig else { return }; headSig = sig
    if !picBusy { pic.set(group: g) }; nameL.text = g.name
    subL.text = [T.clients[g.client]?.name, "\(g.members.count) member\(g.members.count == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · ")
    acts.arrangedSubviews.forEach { $0.removeFromSuperview() }
    acts.addArrangedSubview(card("magnifyingglass", "Search") { [weak self] in self?.search() })
    acts.addArrangedSubview(card(g.muted ? "bell.slash" : "bell", g.muted ? "Muted" : "Mute") { [weak self] in if let g = self?.g { self?.muteSheet(g) } })
    if can { acts.addArrangedSubview(card("pencil", "Edit") { [weak self] in if let g = self?.g { self?.edit(g) } }) }
    let w = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
    let size = head.systemLayoutSizeFitting(CGSize(width: w, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    head.frame = CGRect(x: 0, y: 0, width: w, height: size.height); tableView.tableHeaderView = head
  }
  // one of the three: its symbol in our blue over its name, on the rows' own colour
  private func card(_ sym: String, _ title: String, _ act: @escaping () -> Void) -> UIButton {
    var c = UIButton.Configuration.filled()
    c.baseBackgroundColor = .secondarySystemGroupedBackground; c.baseForegroundColor = .label
    c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)); c.imagePlacement = .top; c.imagePadding = 6
    c.imageColorTransformer = UIConfigurationColorTransformer { _ in Look.accent }
    c.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14)]))
    c.background.cornerRadius = 14; c.cornerStyle = .fixed
    return UIButton(configuration: c, primaryAction: UIAction { _ in act() })
  }

  private func reload(animated: Bool) {
    guard let g = g else { return }
    let T = Talk.shared, me = T.me?.id ?? "", can = T.canManage(g)
    fillHead(g)
    var snap = NSDiffableDataSourceSnapshot<Int, Row>()
    var newSigs: [Row: Int] = [:]
    func add(_ sec: Int, _ rows: [Row]) { snap.appendSections([sec]); snap.appendItems(rows, toSection: sec) }
    add(0, [.media])
    add(1, members.map { Row.member($0) } + (can ? [.addMembers] : []))
    add(2, [.mute] + (T.boss && !T.isAdmin(g) ? [.makeMeAdmin] : []))
    if (g.creator == me && g.creatorAdmin) || T.boss { add(3, [.second]) }
    add(4, [.leave] + (can ? [.delete] : []))
    for r in snap.itemIdentifiers {
      var h = Hasher()
      switch r {
      case .media: h.combine(mediaCount()); h.combine(latestPics().map { $0.id })
      case .member(let id): h.combine(T.name(id)); h.combine(T.people[id]?.role); h.combine(g.admins.contains(id)); h.combine(T.people[id]?.picture); h.combine(T.people[id]?.contact)
      case .mute: h.combine(g.muted); h.combine(g.mutedUntil)
      case .second: h.combine(g.second)
      default: h.combine(0)
      }
      newSigs[r] = h.finalize()
    }
    let old = data.snapshot()
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != newSigs[$0] })
    sigs = newSigs
    data.apply(snap, animatingDifferences: animated)
  }

  // what the chat holds: photos and videos, files, and messages with links — from this phone's own copy
  private func mediaCount() -> Int {
    Talk.shared.log(group).msgs.filter { !$0.deleted && ($0.file != nil || $0.link != nil) }.count
  }
  private func latestPics() -> [Msg] {
    Array(Talk.shared.log(group).msgs.filter { !$0.deleted && ($0.kind == "photo" || $0.kind == "video") && $0.file != nil }.suffix(4).reversed())
  }

  private func fill(_ c: UITableViewCell, _ row: Row) {
    guard let g = g else { return }
    let T = Talk.shared, me = T.me?.id ?? ""
    c.contentView.subviews.filter { $0.tag == 77 }.forEach { $0.removeFromSuperview() }
    c.accessoryView = nil; c.accessoryType = .none; c.selectionStyle = .default
    var cfg = UIListContentConfiguration.valueCell()
    switch row {
    case .media:
      cfg = UIListContentConfiguration.valueCell(); cfg.text = "Photos, Files and Links"; cfg.secondaryText = "\(mediaCount())"
      cfg.directionalLayoutMargins.bottom = 96
      c.accessoryType = .disclosureIndicator
      let strip = UIStackView(); strip.tag = 77; strip.axis = .horizontal; strip.spacing = 8; strip.distribution = .fillEqually
      for m in latestPics() {
        let iv = UIImageView(); iv.contentMode = .scaleAspectFill; iv.clipsToBounds = true; iv.layer.cornerRadius = 8; iv.layer.cornerCurve = .continuous
        iv.backgroundColor = .tertiarySystemFill
        if let f = m.file { if let i = BubbleCell.cached(f.id) ?? ZoomPage.small(m, f) { iv.image = i } else { ZoomPage.thumb(m, f) { iv.image = $0 } } }
        strip.addArrangedSubview(iv)
      }
      while strip.arrangedSubviews.count < 4 { let v = UIView(); strip.addArrangedSubview(v) }
      strip.translatesAutoresizingMaskIntoConstraints = false; c.contentView.addSubview(strip)
      NSLayoutConstraint.activate([strip.leadingAnchor.constraint(equalTo: c.contentView.leadingAnchor, constant: 16), strip.trailingAnchor.constraint(equalTo: c.contentView.trailingAnchor, constant: -16),
                                   strip.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor, constant: -12), strip.heightAnchor.constraint(equalToConstant: 76)])
      strip.isHidden = latestPics().isEmpty
      if latestPics().isEmpty { cfg.directionalLayoutMargins.bottom = 11 }
    case .member(let id):
      let p = T.people[id]
      cfg = UIListContentConfiguration.subtitleCell()
      cfg.text = id == me ? "You" : T.name(id)
      cfg.secondaryText = p?.contact == true ? "Client" : p?.role
      cfg.secondaryTextProperties.color = p?.contact == true ? Look.clientInk : .secondaryLabel
      cfg.secondaryTextProperties.font = p?.contact == true ? .systemFont(ofSize: 14, weight: .semibold) : .systemFont(ofSize: 14)
      cfg.textProperties.font = .systemFont(ofSize: 17)
      cfg.image = UIImage(); cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40); cfg.imageToTextPadding = 14
      cfg.directionalLayoutMargins.top = 9; cfg.directionalLayoutMargins.bottom = 9
      let a = Avatar(frame: CGRect(x: 16, y: 9, width: 40, height: 40)); a.tag = 77; a.isUserInteractionEnabled = false; a.set(person: p); c.contentView.addSubview(a)
      if g.admins.contains(id) {
        let chip = ChipLabel(); chip.text = "Admin"; chip.font = .systemFont(ofSize: 13, weight: .semibold); chip.textColor = .systemGreen
        chip.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.16); chip.layer.cornerRadius = 7; chip.layer.masksToBounds = true
        chip.sizeToFit(); c.accessoryView = chip
      }
      c.selectionStyle = id == me ? .none : .default
    case .addMembers:
      cfg = UIListContentConfiguration.cell(); cfg.text = "Add Members"; cfg.textProperties.color = Look.accent
      cfg.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
      cfg.imageProperties.tintColor = Look.accent; cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40); cfg.imageToTextPadding = 14
      let ring = UIView(frame: CGRect(x: 16, y: 0, width: 40, height: 40)); ring.tag = 77; ring.isUserInteractionEnabled = false
      ring.backgroundColor = Look.accent.withAlphaComponent(0.16); ring.layer.cornerRadius = 20
      c.contentView.insertSubview(ring, at: 0)
      ring.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([ring.leadingAnchor.constraint(equalTo: c.contentView.leadingAnchor, constant: 16), ring.centerYAnchor.constraint(equalTo: c.contentView.centerYAnchor),
                                   ring.widthAnchor.constraint(equalToConstant: 40), ring.heightAnchor.constraint(equalToConstant: 40)])
    case .mute:
      cfg.text = "Mute"; cfg.secondaryText = !g.muted ? "Off" : (g.mutedUntil ?? 0) > 8e15 ? "Always" : "Until " + Look.time(g.mutedUntil ?? 0, short: true)
      c.accessoryType = .disclosureIndicator
    case .makeMeAdmin:
      cfg = UIListContentConfiguration.cell(); cfg.text = "Make Me Admin"; cfg.textProperties.color = Look.accent
    case .second:
      cfg.text = "Second Admin"; cfg.secondaryText = g.second.map { T.name($0) } ?? "None"
      c.accessoryType = .disclosureIndicator
    case .leave:
      cfg = UIListContentConfiguration.cell(); cfg.text = "Leave Group"; cfg.textProperties.color = .systemRed
    case .delete:
      cfg = UIListContentConfiguration.cell(); cfg.text = "Delete Group"; cfg.textProperties.color = .systemRed
    }
    c.contentConfiguration = cfg
    // (on a cell's first use Apple's content view is made only now, over the pictures and the strip put in before — they
    //  showed only once the row was scrolled away and back: Haris 2026-11-13. The ring stays under Add Members' +.)
    c.contentView.subviews.filter { $0.tag == 77 && $0.bounds.width != 40 }.forEach { c.contentView.bringSubviewToFront($0) }
    c.contentView.subviews.filter { $0 is Avatar && $0.tag == 77 }.forEach { c.contentView.bringSubviewToFront($0) }
  }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? {
    guard data.snapshot().sectionIdentifiers.indices.contains(s) else { return nil }
    return data.snapshot().sectionIdentifiers[s] == 1 ? "\(g?.members.count ?? 0) Members" : nil
  }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    guard let g = g, data.snapshot().sectionIdentifiers.indices.contains(s) else { return nil }
    switch data.snapshot().sectionIdentifiers[s] {
    case 3: return "The creator picks one second admin. Admins change the picture and name, add and remove people, and can delete the group."
    case 4:
      let f = DateFormatter(); f.dateStyle = .short
      return "Created by \(Talk.shared.name(g.creator)), \(f.string(from: Date(timeIntervalSince1970: g.createdAt / 1000))). Messages delete themselves after 90 days."
    default: return nil
    }
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard let g = g, let row = data.itemIdentifier(for: ip) else { return }
    switch row {
    case .media: navigationController?.pushViewController(MediaVC(group: group), animated: true)   // (step 1b — mock-up approved 2026-11-13)
    case .member(let id): personSheet(id, g, at: tv.cellForRow(at: ip))
    case .addMembers: navigationController?.pushViewController(AddPeopleVC(group: group), animated: true)
    case .mute: muteSheet(g)
    case .makeMeAdmin: simple(["act": "makeMeAdmin", "group": group], done: "You’re an admin of this group")
    case .second: secondSheet(g, at: tv.cellForRow(at: ip))
    case .leave: GroupActions.leave(group, from: self)
    case .delete:
      let a = UIAlertController(title: "Delete “\(g.name)”?", message: "The group and its messages go for everyone in it.", preferredStyle: .alert)
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in self?.simple(["act": "deleteGroup", "group": self?.group ?? ""], done: "Group deleted") })
      present(a, animated: true)
    }
  }
  // Search: back to the chat, its own search open
  private func search() {
    guard let nav = navigationController, let chat = nav.viewControllers.last(where: { ($0 as? ChatVC)?.group == group }) as? ChatVC else { return }
    nav.popToViewController(chat, animated: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { chat.startFind() }
  }
  // Edit (for now the picture and the name — its own sheet is step 1e)
  private func edit(_ g: Group) {
    let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    a.addAction(UIAlertAction(title: "Change Picture", style: .default) { [weak self] _ in self?.changePicture() })
    a.addAction(UIAlertAction(title: "Rename Group", style: .default) { [weak self] _ in self?.rename(g) })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(a, animated: true)
  }
  // the second admin: any of the team in the group (not a client), or none
  private func secondSheet(_ g: Group, at cell: UITableViewCell?) {
    let T = Talk.shared
    let a = UIAlertController(title: "Second Admin", message: nil, preferredStyle: .actionSheet)
    for id in members where id != g.creator && T.people[id]?.contact != true {
      a.addAction(UIAlertAction(title: T.name(id) + (g.second == id ? " ✓" : ""), style: .default) { [weak self] _ in self?.simple(["act": "setSecond", "group": g.id, "id": id]) })
    }
    if g.second != nil { a.addAction(UIAlertAction(title: "None", style: .destructive) { [weak self] _ in self?.simple(["act": "setSecond", "group": g.id, "id": NSNull()]) }) }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.popoverPresentationController?.sourceView = cell
    present(a, animated: true)
  }
  private func simple(_ b: [String: Any], done: String? = nil) {
    Net.shared.act(b) { j in
      if (j?["ok"] as? Bool) == true { if let d = done { toast(d) }; Talk.shared.refresh(); Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t do that — try again") }
    }
  }
  private func rename(_ g: Group) {
    let a = UIAlertController(title: "Rename group", message: nil, preferredStyle: .alert)
    a.addTextField { t in t.text = g.name; t.clearButtonMode = .whileEditing; t.autocapitalizationType = .sentences }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
      let n = (a.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
      if !n.isEmpty, n != g.name { self?.simple(["act": "rename", "group": g.id, "name": n]) }
    })
    present(a, animated: true)
  }
  private func muteSheet(_ g: Group) {
    let a = UIAlertController(title: g.muted ? "Muted" : "Mute “\(g.name)”", message: "An @mention still notifies you.", preferredStyle: .actionSheet)
    if g.muted { a.addAction(UIAlertAction(title: "Unmute", style: .default) { _ in GroupActions.mute(g.id, nil) }) }
    else {
      a.addAction(UIAlertAction(title: "8 hours", style: .default) { _ in GroupActions.mute(g.id, 8 * 3600) })
      a.addAction(UIAlertAction(title: "1 week", style: .default) { _ in GroupActions.mute(g.id, 7 * 86400) })
      a.addAction(UIAlertAction(title: "Always", style: .default) { _ in GroupActions.mute(g.id, -1) })
    }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(a, animated: true)
  }
  // a person in the group: admin / remove (for those who may)
  private func personSheet(_ id: String, _ g: Group, at cell: UITableViewCell?) {
    let T = Talk.shared, me = T.me?.id ?? ""
    guard id != me else { return }
    let a = UIAlertController(title: T.name(id), message: T.people[id]?.role, preferredStyle: .actionSheet)
    let creatorAdmin = g.creator == me && g.creatorAdmin
    if (creatorAdmin || T.boss) && id != g.creator {
      if g.second == id { a.addAction(UIAlertAction(title: "Remove as admin", style: .default) { [weak self] _ in self?.simple(["act": "setSecond", "group": g.id, "id": NSNull()]) }) }
      else if !g.admins.contains(id) { a.addAction(UIAlertAction(title: g.second == nil ? "Make second admin" : "Make second admin (instead of \(T.name(g.second!)))", style: .default) { [weak self] _ in self?.simple(["act": "setSecond", "group": g.id, "id": id]) }) }
    }
    if T.boss && g.admins.contains(id) && g.second != id {
      a.addAction(UIAlertAction(title: id == g.creator ? "Take away the creator’s admin" : "Remove as admin", style: .destructive) { [weak self] _ in self?.simple(["act": "dropAdmin", "group": g.id, "id": id]) })
    }
    if T.canManage(g) && (id != g.creator || T.boss) {
      a.addAction(UIAlertAction(title: "Remove from group", style: .destructive) { [weak self] _ in self?.simple(["act": "removePerson", "group": g.id, "id": id], done: "\(T.name(id)) removed") })
    }
    if a.actions.isEmpty { return }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.popoverPresentationController?.sourceView = cell
    present(a, animated: true)
  }
  private func changePicture() {
    var c = PHPickerConfiguration(); c.filter = .images; c.selectionLimit = 1
    let p = PHPickerViewController(configuration: c); p.delegate = self; present(p, animated: true)
  }
  func picker(_ p: PHPickerViewController, didFinishPicking r: [PHPickerResult]) {
    p.dismiss(animated: true)
    guard let ip = r.first?.itemProvider, ip.canLoadObject(ofClass: UIImage.self) else { return }
    ip.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
      guard let img = obj as? UIImage, let self = self else { return }
      let side: CGFloat = 640, s = side / min(img.size.width, img.size.height)
      let sq = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in img.draw(in: CGRect(x: (side - img.size.width * s) / 2, y: (side - img.size.height * s) / 2, width: img.size.width * s, height: img.size.height * s)) }
      guard let d = sq.jpegData(compressionQuality: 0.85) else { return }
      DispatchQueue.main.async {
        self.picUploading(true, sq)
        Net.shared.upload(d, name: "group.jpg", progress: { _ in }) { fid in
          guard let fid = fid else { self.picUploading(false); toast("The picture didn’t upload — try again"); return }
          try? d.write(to: Net.local(fid))
          Net.shared.act(["act": "setPic", "group": self.group, "file": fid]) { j in
            if (j?["ok"] as? Bool) == true { Talk.shared.refresh(); Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t do that — try again") }
            self.picUploading(false)
          }
        }
      }
    }
  }
}

final class AddPeopleVC: UITableViewController {
  let group: String
  private var picked = Set<String>()
  init(group: String) { self.group = group; super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var list: [Person] {
    let T = Talk.shared, inIt = Set(T.groups[group]?.members ?? [])
    let team = T.people.values.filter { !inIt.contains($0.id) && !$0.gone && !$0.contact }.sorted { $0.name < $1.name }
    guard T.boss, let g = T.groups[group] else { return team }
    let cname = T.clients[g.client]?.name ?? "Client"
    return T.contacts.filter { $0.client == g.client && !inIt.contains($0.id) }.map { Person(id: $0.id, name: $0.name, role: "\(cname) · client", photo: nil, color: nil, gone: false, contact: true, client: g.client) } + team
  }
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Add people"
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Add", primaryAction: UIAction { [weak self] _ in self?.add() })
    navigationItem.rightBarButtonItem?.style = .done; navigationItem.rightBarButtonItem?.isEnabled = false
  }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { list.count }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { 58 }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? { "They’ll see the messages from now on — not what was said before." }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil), p = list[ip.row]
    var cfg = c.defaultContentConfiguration(); cfg.text = p.name; cfg.secondaryText = p.role; cfg.secondaryTextProperties.color = .secondaryLabel
    cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
    c.contentConfiguration = cfg
    let a = Avatar(frame: CGRect(x: 16, y: 9, width: 40, height: 40)); a.set(person: p); c.contentView.addSubview(a)
    let on = picked.contains(p.id)
    let tick = UIImageView(image: UIImage(systemName: on ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)))
    tick.tintColor = on ? Look.accent : .tertiaryLabel; c.accessoryView = tick
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    let id = list[ip.row].id
    if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    UISelectionFeedbackGenerator().selectionChanged()
    tv.reloadRows(at: [ip], with: .none)
    navigationItem.rightBarButtonItem?.isEnabled = !picked.isEmpty
  }
  private func add() {
    Net.shared.act(["act": "addPeople", "group": group, "ids": Array(picked)]) { [weak self] j in
      if (j?["ok"] as? Bool) == true { Talk.shared.refresh(); Talk.shared.sync(); self?.navigationController?.popViewController(animated: true) }
      else { toast(j?["error"] as? String ?? "Couldn’t add them — try again") }
    }
  }
}

// ---------- client contacts (Super Admins and Office Admins — Haris 2026-11-05): name, email and their client; several
// per client. A contact signs in to E11 Talk only with that email's code; removing one takes them out of every group and
// signs them out at once. ----------
final class ContactsVC: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var byClient: [(Client, [Contact])] {
    let T = Talk.shared
    return T.clientOrder.compactMap { id in
      guard let c = T.clients[id] else { return nil }
      let ks = T.contacts.filter { $0.client == id }
      return ks.isEmpty ? nil : (c, ks)
    }
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Client contacts"
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
      self?.present(UINavigationController(rootViewController: NewContactVC()), animated: true)
    }, menu: nil)
    NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .talkChanged, object: nil)
    Talk.shared.refresh()
  }
  override func numberOfSections(in tv: UITableView) -> Int { max(1, byClient.count) }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { byClient.isEmpty ? 0 : byClient[s].1.count }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { byClient.isEmpty ? nil : "\(byClient[s].0.name)’s contacts · \(byClient[s].1.count)" }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == max(1, byClient.count) - 1 ? (byClient.isEmpty ? "No client contacts yet. Tap + to add one — " : "") + "A contact signs in to E11 Talk with a one-time code sent to their email — E11 Talk only, never E11 Console. They see only the groups you add them to." : nil
  }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { 58 }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let k = byClient[ip.section].1[ip.row]
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    var cfg = c.defaultContentConfiguration()
    cfg.text = k.name; cfg.secondaryText = k.email; cfg.secondaryTextProperties.color = .secondaryLabel
    cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
    c.contentConfiguration = cfg
    let a = Avatar(frame: CGRect(x: 16, y: 9, width: 40, height: 40)); a.set(name: k.name, color: Look.color(for: k.id), picture: Talk.shared.clients[k.client]?.logo, logo: true); c.contentView.addSubview(a)   // (their client's logo when it has one, else initials)
    let n = UILabel(); n.text = "\(k.groups) group\(k.groups == 1 ? "" : "s")"; n.font = .systemFont(ofSize: 14); n.textColor = .secondaryLabel; n.sizeToFit(); c.accessoryView = n
    c.selectionStyle = .none
    return c
  }
  override func tableView(_ tv: UITableView, trailingSwipeActionsConfigurationForRowAt ip: IndexPath) -> UISwipeActionsConfiguration? {
    let k = byClient[ip.section].1[ip.row]
    let a = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
      let al = UIAlertController(title: "Remove \(k.name)?", message: "They leave every group and can’t sign in to E11 Talk any more.", preferredStyle: .alert)
      al.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
      al.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
        Net.shared.act(["act": "removeContact", "id": k.id]) { j in
          if (j?["ok"] as? Bool) == true { toast("\(k.name) removed"); Talk.shared.refresh(); Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t remove them") }
          done(true)
        }
      })
      self?.present(al, animated: true)
    }
    return UISwipeActionsConfiguration(actions: [a])
  }
}

final class NewContactVC: UITableViewController, UITextFieldDelegate {
  private let name = UITextField(), email = UITextField()
  private var client: String?
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "New client contact"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Add", primaryAction: UIAction { [weak self] _ in self?.add() })
    navigationItem.rightBarButtonItem?.style = .done
    name.placeholder = "Ahmed Karim"; name.autocapitalizationType = .words; name.returnKeyType = .next; name.delegate = self
    email.placeholder = "ahmed@company.com"; email.keyboardType = .emailAddress; email.autocapitalizationType = .none; email.autocorrectionType = .no; email.returnKeyType = .done; email.delegate = self
    [name, email].forEach { $0.addAction(UIAction { [weak self] _ in self?.check() }, for: .editingChanged); $0.clearButtonMode = .whileEditing }
    check()
  }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); name.becomeFirstResponder() }
  func textFieldShouldReturn(_ t: UITextField) -> Bool { if t === name { email.becomeFirstResponder() } else { t.resignFirstResponder() }; return true }
  private func check() {
    let e = (email.text ?? "").trimmingCharacters(in: .whitespaces)
    navigationItem.rightBarButtonItem?.isEnabled = !(name.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty && e.contains("@") && e.contains(".") && client != nil
  }
  override func numberOfSections(in tv: UITableView) -> Int { 2 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? 2 : 1 }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { s == 0 ? "Contact" : "Client (from E11 Console)" }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == 1 ? "They sign in to E11 Talk with a one-time code sent to this email — E11 Talk only, never E11 Console. Only Super Admins and Office Admins add client contacts and put them in groups." : nil
  }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .value1, reuseIdentifier: nil)
    if ip.section == 0 {
      c.selectionStyle = .none
      let l = UILabel(frame: CGRect(x: 20, y: 0, width: 70, height: 44)); l.text = ip.row == 0 ? "Name" : "Email"; l.textColor = .secondaryLabel
      let f = ip.row == 0 ? name : email
      f.frame = CGRect(x: 96, y: 0, width: tv.bounds.width - 96 - 52, height: 44)
      c.contentView.addSubview(l); c.contentView.addSubview(f)
    } else {
      var cfg = c.defaultContentConfiguration()
      if let cl = client.flatMap({ Talk.shared.clients[$0] }) { cfg.text = cl.name } else { cfg.text = "Pick their client"; cfg.textProperties.color = .secondaryLabel }
      c.contentConfiguration = cfg; c.accessoryType = .disclosureIndicator
    }
    return c
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard ip.section == 1 else { return }
    navigationController?.pushViewController(ClientPickVC(selected: client) { [weak self] id in self?.client = id; self?.check(); self?.tableView.reloadSections([1], with: .none) }, animated: true)
  }
  private func add() {
    guard let c = client else { return }
    navigationItem.rightBarButtonItem?.isEnabled = false
    let n = (name.text ?? "").trimmingCharacters(in: .whitespaces), e = (email.text ?? "").trimmingCharacters(in: .whitespaces)
    Net.shared.act(["act": "addContact", "name": n, "email": e, "client": c]) { [weak self] j in
      if (j?["ok"] as? Bool) == true {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Talk.shared.refresh()
        self?.dismiss(animated: true) { toast("\(n) added — put them in a group to start") }
      } else { toast(j?["error"] as? String ?? "Couldn’t add them — try again"); self?.check() }
    }
  }
}
