import UIKit
import PhotosUI

/* New group (the mockup): its name, its client (the picture is the client's logo from Client Assets — it can be
   changed later), the people. Anyone on the staff makes groups (not freelancers); only the group's admins add people.
   Group info: its picture and name, its people (admins marked), Mute, Pin; for its admins Add people, Rename, Change
   picture, Remove someone, and — the creator — pick one second admin; Super Admins and Office Admins "Make me admin"
   and can take anyone's admin away (the creator's too). Leave group; Delete group (admins). (Haris 2026-11-05 / 06) */
// ---------- New Group (step 1g — the design's board 25): Apple's sheet; ✕ · New Group · Create; the picture (the client's
// logo until another is chosen — Take Photo · Choose Photo, Apple's menu) beside "Group name"; Client ›; Apple's search;
// the team as "N People Added" and the client's contacts, Apple's round selection marks; the footers as drawn ----------
final class NewGroupVC: UITableViewController, UITextFieldDelegate, UISearchBarDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  private var client: String?
  private var picked = Set<String>()
  private let name = UITextField()
  private let pic = Avatar(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
  private var chosen: UIImage?        // (a picture picked here: set on the group once it's made)
  private var q = ""
  private let find = UISearchBar()
  private let forClient: Bool
  // (fixed: made from a client's page — a group of that client only, its Client row set and not changed — Haris 2026-11-13)
  private let fixed: Bool
  init(client: String?, forClient: Bool = false, fixed: Bool = false) { self.client = client; self.forClient = forClient; self.fixed = fixed && client != nil; super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "New Group"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let make = UIBarButtonItem(title: "Create", primaryAction: UIAction { [weak self] _ in self?.create() })
    if #available(iOS 26.0, *) { make.style = .prominent } else { make.style = .done }
    navigationItem.rightBarButtonItem = make
    name.placeholder = "A campaign, a shoot, an event…"; name.font = .systemFont(ofSize: 19); name.clearButtonMode = .whileEditing
    name.delegate = self; name.returnKeyType = .done
    name.addAction(UIAction { [weak self] _ in self?.check() }, for: .editingChanged)
    find.placeholder = "Search people"; find.searchBarStyle = .minimal; find.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    // (the keyboard follows a drag down; a tap on a person picks them, as Apple's own pickers — Haris 2026-11-13: yes)
    tableView.keyboardDismissMode = .interactive
    // (Apple's round selection marks — the list's own multiple selection)
    tableView.allowsMultipleSelectionDuringEditing = true; tableView.isEditing = true
    if client == nil, Talk.shared.clientOrder.count == 1 { client = Talk.shared.clientOrder.first }
    setUpList()
    check()
  }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); if (name.text ?? "").isEmpty { name.becomeFirstResponder() } }
  private func check() { navigationItem.rightBarButtonItem?.isEnabled = client != nil && !(name.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
  func textFieldShouldReturn(_ t: UITextField) -> Bool { t.resignFirstResponder(); return true }
  func searchBar(_ s: UISearchBar, textDidChange t: String) { q = t.lowercased(); reload(animated: true) }

  private func match(_ n: String, _ r: String) -> Bool { q.isEmpty || n.lowercased().contains(q) || r.lowercased().contains(q) }
  private var team: [Person] {
    let T = Talk.shared, me = T.me?.id
    return T.people.values.filter { $0.id != me && !$0.gone && !$0.contact && match($0.name, $0.role) }.sorted { $0.name < $1.name }
  }
  private var contacts: [Person] {
    let T = Talk.shared
    guard T.boss, let c = client else { return [] }
    let cname = T.clients[c]?.name ?? "Client"
    return T.contacts.filter { $0.client == c && match($0.name, cname) }.map { Person(id: $0.id, name: $0.name, role: "Client · \(cname)", photo: nil, color: nil, gone: false, contact: true, client: c) }
  }
  // sections: 0 the picture and name · 1 Client · 2 the team, its search on top (Haris 2026-11-13: part of the list) ·
  // 3 the client's contacts (when there are any) —
  // Apple's change-only list: a search, a client picked or a change from elsewhere only adds and takes away the rows that
  // differ (the whole list was reloaded on every letter — Haris 2026-11-13)
  private var data: TitledSource<Int, String>!
  private var byId: [String: Person] = [:], sigs: [String: Int] = [:]
  private func setUpList() {
    data = TitledSource(tableView: tableView) { [weak self] tv, ip, id in
      let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip); self?.fill(c, id); return c
    }
    data.defaultRowAnimation = .fade
    data.head = { [weak self] s in self?.headTitle(s) }
    data.foot = { [weak self] s in self?.footTitle(s) }
    data.canEdit = { [weak self] ip in ip.section >= 2 && !["none", "find"].contains(self?.data.itemIdentifier(for: ip) ?? "none") }
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    reload(animated: false)
  }
  @objc private func changed() { reload(animated: view.window != nil) }
  private func reload(animated: Bool) {
    let T = Talk.shared
    // (a person who left the team, or another client's contact, is no longer picked)
    let can = Set(T.people.values.filter { !$0.gone && !$0.contact }.map { $0.id } + T.contacts.filter { $0.client == client }.map { $0.id })
    picked = picked.filter { can.contains($0) }
    let t = team, k = contacts
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    snap.appendSections([0, 1, 2]); snap.appendItems(["pic"], toSection: 0); snap.appendItems(["client"], toSection: 1)
    snap.appendItems(["find"] + (t.isEmpty && k.isEmpty && !q.isEmpty ? ["none"] : t.map { $0.id }), toSection: 2)
    if !k.isEmpty { snap.appendSections([3]); snap.appendItems(k.map { $0.id }, toSection: 3) }
    var newSigs: [String: Int] = [:]
    byId = [:]
    for p in t + k { byId[p.id] = p; var h = Hasher(); h.combine(p.name); h.combine(p.role); h.combine(p.picture); newSigs[p.id] = h.finalize() }
    var h = Hasher(); h.combine(client.flatMap { T.clients[$0]?.name }); newSigs["client"] = h.finalize()
    let old = data.snapshot()
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != nil && sigs[$0] != newSigs[$0] })
    sigs = newSigs
    data.applySteady(snap, in: tableView, animated: animated) { [weak self] in self?.reselect(); self?.counted() }
  }
  private func reselect() {
    for id in picked { if let ip = data.indexPath(for: id) { tableView.selectRow(at: ip, animated: false, scrollPosition: .none) } }
  }
  private func headTitle(_ s: Int) -> String? {
    s == 2 ? (picked.isEmpty ? "Team" : "\(picked.count) \(picked.count == 1 ? "Person" : "People") Added") : s == 3 ? "Client Contacts" : nil
  }
  private func footTitle(_ s: Int) -> String? {
    if s == 1 { return "The picture is the client’s logo from Client Assets until you choose another." }
    if s == data.snapshot().numberOfSections - 1, Talk.shared.boss { return "Add a client contact and the group moves to the Clients tab, marked “Client can see this group”." }
    return nil
  }
  // the group's picture: the one chosen here, else the client's logo — set straight on it, nothing else drawn again
  private func showPic() {
    if let i = chosen { pic.show(i) } else if let cl = client.flatMap({ Talk.shared.clients[$0] }) { pic.set(client: cl) } else { pic.set(name: "?", color: .systemGray3, picture: nil) }
  }
  private func fill(_ c: UITableViewCell, _ id: String) {
    // (Apple's content view first, ours into it — Group Info's lesson)
    if c.contentConfiguration == nil { c.contentConfiguration = UIListContentConfiguration.cell() }
    c.contentView.subviews.filter { $0.tag == 77 }.forEach { $0.removeFromSuperview() }
    c.accessoryType = .none; c.selectionStyle = .default; c.backgroundConfiguration = nil
    switch id {
    case "pic":
      // the picture with its camera badge (Apple's menu), and "Group name" over the field
      c.selectionStyle = .none
      var cfg = UIListContentConfiguration.cell(); cfg.text = " "; cfg.directionalLayoutMargins.top = 14; cfg.directionalLayoutMargins.bottom = 14
      cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 60, height: 60)
      c.contentConfiguration = cfg
      showPic()
      let pb = UIButton(type: .custom); pb.tag = 77; pb.frame = CGRect(x: 16, y: 14, width: 60, height: 60)
      pic.frame = pb.bounds; pic.isUserInteractionEnabled = false; pb.addSubview(pic)
      let badge = UIImageView(image: UIImage(systemName: "camera.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)))
      badge.tintColor = .label; badge.backgroundColor = .systemBackground; badge.layer.cornerRadius = 11; badge.clipsToBounds = true
      badge.frame = CGRect(x: 41, y: 41, width: 22, height: 22); pb.addSubview(badge)
      // (the menu asked for as it opens: Use Client Logo only once a picture is chosen)
      pb.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.picMenu() ?? []) }]); pb.showsMenuAsPrimaryAction = true
      pb.accessibilityLabel = "Change the picture"
      c.contentView.addSubview(pb)
      let cap = UILabel(); cap.tag = 77; cap.text = "Group name"; cap.font = .systemFont(ofSize: 13); cap.textColor = .secondaryLabel
      cap.frame = CGRect(x: 90, y: 18, width: 200, height: 18); c.contentView.addSubview(cap)
      name.tag = 77; name.frame = CGRect(x: 90, y: 38, width: max(120, tableView.bounds.width - 90 - 52), height: 30); c.contentView.addSubview(name)
    case "client":
      var cfg = UIListContentConfiguration.valueCell(); cfg.text = "Client"
      cfg.secondaryText = client.flatMap { Talk.shared.clients[$0]?.name } ?? "Pick a client"
      c.contentConfiguration = cfg; c.accessoryType = fixed ? .none : .disclosureIndicator; c.selectionStyle = fixed ? .none : .default
    case "find":
      // (Apple's search bar as the first row of the team's list, on the list's own card — Haris 2026-11-13)
      c.selectionStyle = .none
      c.contentConfiguration = UIListContentConfiguration.cell()
      find.tag = 77; find.frame = c.contentView.bounds; find.autoresizingMask = [.flexibleWidth, .flexibleHeight]; c.contentView.addSubview(find)
    case "none": PickRows.noResults(c)
    default: if let p = byId[id] { PickRows.person(c, p, size: 36) }
    }
  }
  override func tableView(_ tv: UITableView, willSelectRowAt ip: IndexPath) -> IndexPath? {
    let id = data.itemIdentifier(for: ip); return id == "pic" || id == "find" || id == "none" || (id == "client" && fixed) ? nil : ip
  }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    guard let id = data.itemIdentifier(for: ip) else { return }
    if id == "client" {
      tv.deselectRow(at: ip, animated: true)
      let pick = ClientPickVC(selected: client) { [weak self] cid in
        guard let self = self else { return }
        self.client = cid
        self.check(); self.showPic(); self.reload(animated: true)
      }
      navigationController?.pushViewController(pick, animated: true)
    } else if byId[id] != nil {
      picked.insert(id); UISelectionFeedbackGenerator().selectionChanged(); counted()
    }
  }
  override func tableView(_ tv: UITableView, didDeselectRowAt ip: IndexPath) {
    guard let id = data.itemIdentifier(for: ip), byId[id] != nil else { return }
    picked.remove(id); UISelectionFeedbackGenerator().selectionChanged(); counted()
  }
  // ("N People Added" over the team, crossfading to its new words)
  private func counted() {
    guard let h = tableView.headerView(forSection: 2), let t = headTitle(2), h.textLabel?.text != t else { return }
    UIView.transition(with: h, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction]) { h.textLabel?.text = t; h.setNeedsLayout(); h.layoutIfNeeded() }
  }
  // ---------- the picture ----------
  private func picMenu() -> [UIMenuElement] {
    var xs: [UIMenuElement] = []
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      xs.append(UIAction(title: "Take Photo", image: UIImage(systemName: "camera")) { [weak self] _ in
        let p = UIImagePickerController(); p.sourceType = .camera; p.delegate = self; self?.present(p, animated: true)
      })
    }
    xs.append(UIAction(title: "Choose Photo", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
      var c = PHPickerConfiguration(); c.filter = .images; c.selectionLimit = 1
      let p = PHPickerViewController(configuration: c); p.delegate = self; self?.present(p, animated: true)
    })
    if chosen != nil { xs.append(UIAction(title: "Use Client Logo", image: UIImage(systemName: "building.2")) { [weak self] _ in self?.chosen = nil; self?.showPic() }) }
    return xs
  }
  func picker(_ p: PHPickerViewController, didFinishPicking r: [PHPickerResult]) {
    p.dismiss(animated: true)
    guard let ip = r.first?.itemProvider, ip.canLoadObject(ofClass: UIImage.self) else { return }
    ip.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
      guard let img = obj as? UIImage else { return }
      DispatchQueue.main.async { self?.chosen = NewGroupVC.square(img); self?.showPic() }
    }
  }
  func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    p.dismiss(animated: true)
    if let img = info[.originalImage] as? UIImage { chosen = NewGroupVC.square(img); showPic() }
  }
  func imagePickerControllerDidCancel(_ p: UIImagePickerController) { p.dismiss(animated: true) }
  static func square(_ img: UIImage) -> UIImage {
    let side: CGFloat = 640, s = side / min(img.size.width, img.size.height)
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in img.draw(in: CGRect(x: (side - img.size.width * s) / 2, y: (side - img.size.height * s) / 2, width: img.size.width * s, height: img.size.height * s)) }
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
      // (a picture chosen here goes on the group now it's made)
      if let i = self.chosen, let d = i.jpegData(compressionQuality: 0.85) {
        Net.shared.upload(d, name: "group.jpg", progress: { _ in }) { fid in
          guard let fid = fid else { toast("The picture didn’t upload — change it in Group Info"); return }
          try? d.write(to: Net.local(fid))
          Net.shared.act(["act": "setPic", "group": g, "file": fid]) { _ in Talk.shared.refresh(); Talk.shared.sync() }
        }
      }
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
  private var data: UITableViewDiffableDataSource<Int, String>!
  private var sigs: [String: Int] = [:]
  init(selected: String?, done: @escaping (String) -> Void) { self.selected = selected; self.done = done; super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var list: [Client] {
    let q = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    return Talk.shared.clientOrder.compactMap { Talk.shared.clients[$0] }.filter { q.isEmpty || $0.name.lowercased().contains(q) }
  }
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Client"
    search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; search.searchBar.placeholder = "Search clients"
    navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
    tableView.keyboardDismissMode = .interactive
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    // (Apple's change-only list: a search only adds and takes away the clients that differ)
    data = UITableViewDiffableDataSource(tableView: tableView) { [weak self] tv, ip, id in
      let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip)
      if id == "none" { PickRows.noResults(c); return c }
      guard let self = self, let cl = Talk.shared.clients[id] else { return c }
      c.contentView.subviews.filter { $0.tag == 77 }.forEach { $0.removeFromSuperview() }
      var cfg = UIListContentConfiguration.cell(); cfg.text = cl.name
      cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 34, height: 34)
      cfg.directionalLayoutMargins.top = 10; cfg.directionalLayoutMargins.bottom = 10
      c.contentConfiguration = cfg
      let a = Avatar(frame: CGRect(x: 16, y: 10, width: 34, height: 34)); a.tag = 77; a.isUserInteractionEnabled = false; a.set(client: cl); c.contentView.addSubview(a)
      c.accessoryType = cl.id == self.selected ? .checkmark : .none
      return c
    }
    data.defaultRowAnimation = .fade
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    reload(animated: false)
  }
  @objc private func changed() { reload(animated: view.window != nil) }
  func updateSearchResults(for s: UISearchController) { reload(animated: true) }
  private func reload(animated: Bool) {
    let l = list, typed = !(search.searchBar.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    var snap = NSDiffableDataSourceSnapshot<Int, String>(); snap.appendSections([0])
    snap.appendItems(l.isEmpty && typed ? ["none"] : l.map { $0.id })
    var newSigs: [String: Int] = [:]
    for cl in l { var h = Hasher(); h.combine(cl.name); h.combine(cl.logo); h.combine(cl.color); newSigs[cl.id] = h.finalize() }
    let old = data.snapshot()
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != nil && sigs[$0] != newSigs[$0] })
    sigs = newSigs
    data.applySteady(snap, in: tableView, animated: animated)
  }
  override func tableView(_ tv: UITableView, willSelectRowAt ip: IndexPath) -> IndexPath? { data.itemIdentifier(for: ip) == "none" ? nil : ip }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    guard let id = data.itemIdentifier(for: ip), id != "none" else { return }
    done(id); navigationController?.popViewController(animated: true)
  }
}

// ---------- group info ----------
final class GroupInfoVC: UITableViewController {
  /* Group Info — the approved design's boards 23 and 24 (Haris 2026-11-12: "Start Group Info"). Apple's inset list:
     the picture, name and "client · N members" with Search · Mute · Edit; Photos, Files and Links with the latest four;
     the members (Admin chip, a client in orange, You), + Add Members; Mute and Make Me Admin; Second Admin with what it
     means; Leave and Delete, then who made it and when. Rows kept by what they show — only a row that changed is drawn again. */
  let group: String
  init(group: String) { self.group = group; super.init(style: .insetGrouped); hidesBottomBarWhenPushed = true }
  required init?(coder: NSCoder) { fatalError() }
  private var g: Group? { Talk.shared.groups[group] }
  enum Row: Hashable { case media, starred, member(String), addMembers, mute, makeMeAdmin, second, leave, delete }
  private var data: TitledSource<Int, Row>!
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
    tableView.sectionHeaderTopPadding = 0
    data = TitledSource(tableView: tableView) { [weak self] tv, ip, row in
      let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip); self?.fill(c, row); return c
    }
    // (the list's own titles — "18 MEMBERS" over the people, as board 23, and the notes under the last boxes: a diffable
    //  list asks its data source for them, never the page, so they never showed and left an empty gap — Haris 2026-11-13)
    data.head = { [weak self] s in self?.headTitle(s) }
    data.foot = { [weak self] s in self?.footTitle(s) }
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
    // (the cards' edges on the list's own margins, where Apple's inset boxes below start and end; room under them as
    //  between the boxes — they sat on the Photos box: Haris 2026-11-13)
    head.preservesSuperviewLayoutMargins = true
    NSLayoutConstraint.activate([pic.widthAnchor.constraint(equalToConstant: 116), pic.heightAnchor.constraint(equalToConstant: 116),
      col.topAnchor.constraint(equalTo: head.topAnchor, constant: 4), col.leadingAnchor.constraint(equalTo: head.layoutMarginsGuide.leadingAnchor),
      col.trailingAnchor.constraint(equalTo: head.layoutMarginsGuide.trailingAnchor), col.bottomAnchor.constraint(equalTo: head.bottomAnchor, constant: -24),
      acts.widthAnchor.constraint(equalTo: col.widthAnchor), acts.heightAnchor.constraint(equalToConstant: 62)])
    tableView.tableHeaderView = head
  }
  private var headSig = 0
  private func fillHead(_ g: Group) {
    let T = Talk.shared, can = T.canManage(g)
    var h = Hasher(); h.combine(g.name); h.combine(g.pic); h.combine(g.members.count); h.combine(can); h.combine(g.muted); h.combine(T.clients[g.client]?.name); h.combine(T.clients[g.client]?.logo)
    let sig = h.finalize(); guard sig != headSig else { return }
    // (a change after the page is up — the name, the picture, Mute ↔ Muted — crossfades in place, nothing snapping)
    if headSig != 0, view.window != nil { UIView.transition(with: head, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction], animations: nil) }
    headSig = sig
    pic.set(group: g); nameL.text = g.name
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
    add(0, [.media, .starred])   // (Starred Messages of this group — Haris 2026-11-13)
    add(1, members.map { Row.member($0) } + (can ? [.addMembers] : []))
    add(2, [.mute] + (T.boss && !T.isAdmin(g) ? [.makeMeAdmin] : []))
    if (g.creator == me && g.creatorAdmin) || T.boss { add(3, [.second]) }
    add(4, [.leave] + (can ? [.delete] : []))
    for r in snap.itemIdentifiers {
      var h = Hasher()
      switch r {
      case .media: h.combine(mediaCount()); h.combine(latestPics().map { $0.id })
      case .starred: h.combine(Talk.shared.starred.filter { $0.group == group }.count)
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
    data.applySteady(snap, in: tableView, animated: animated)
    // (someone added or gone: the title over the people says the new count, in place — the rest left as it is)
    if let i = snap.indexOfSection(1), let h = tableView.headerView(forSection: i), let t = headTitle(i), h.textLabel?.text != t {
      UIView.transition(with: h, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) { h.textLabel?.text = t; h.setNeedsLayout(); h.layoutIfNeeded() }   // (laid out again for the new words — they were cut to "16 MEMBE…")
    }
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
    // (a row's first configuration puts Apple's own content view in place of the old one — the pictures and the photo
    //  strip added before it went with the old one, and showed only once the row came back from reuse: Haris 2026-11-13.
    //  So the row has Apple's content view first, and ours go into it.)
    if c.contentConfiguration == nil { c.contentConfiguration = UIListContentConfiguration.valueCell() }
    c.contentView.subviews.filter { $0.tag == 77 }.forEach { $0.removeFromSuperview() }
    c.accessoryView = nil; c.accessoryType = .none; c.selectionStyle = .default
    var cfg = UIListContentConfiguration.valueCell()
    switch row {
    case .media:
      cfg = UIListContentConfiguration.valueCell(); cfg.text = "Photos, Files and Links"
      // (the count and Apple's chevron together on the title line — the › stood beside the photos: Haris 2026-11-13)
      let n = NSMutableAttributedString(string: "\(mediaCount())  ", attributes: [.foregroundColor: UIColor.secondaryLabel, .font: UIFont.preferredFont(forTextStyle: .body)])
      let chev = UIImage(systemName: "chevron.forward", withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 14, weight: .semibold)))!.withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal)
      n.append(NSAttributedString(attachment: NSTextAttachment(image: chev)))
      cfg.secondaryAttributedText = n
      cfg.directionalLayoutMargins.bottom = 96
      let strip = UIStackView(); strip.tag = 77; strip.axis = .horizontal; strip.spacing = 8; strip.distribution = .fillEqually
      for m in latestPics() {
        let iv = UIImageView(); iv.contentMode = .scaleAspectFill; iv.clipsToBounds = true; iv.layer.cornerRadius = 8; iv.layer.cornerCurve = .continuous
        iv.backgroundColor = .tertiarySystemFill
        if let f = m.file { if let i = BubbleCell.cached(f.id) ?? ZoomPage.small(m, f) { iv.image = i } else { ZoomPage.thumb(m, f) { iv.land($0) } } }
        strip.addArrangedSubview(iv)
      }
      while strip.arrangedSubviews.count < 4 { let v = UIView(); strip.addArrangedSubview(v) }
      strip.translatesAutoresizingMaskIntoConstraints = false; c.contentView.addSubview(strip)
      NSLayoutConstraint.activate([strip.leadingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.leadingAnchor), strip.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor),
                                   strip.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor, constant: -12), strip.heightAnchor.constraint(equalToConstant: 76)])
      strip.isHidden = latestPics().isEmpty
      if latestPics().isEmpty { cfg.directionalLayoutMargins.bottom = 11 }
    case .starred:
      // (this group's starred messages — the count and ›, as the row above)
      let n = T.starred.filter { $0.group == group }.count
      cfg.text = "Starred Messages"; cfg.secondaryText = n == 0 ? "None" : "\(n)"
      c.accessoryType = .disclosureIndicator
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
        // (room round the word, a capsule — sizeToFit gave it none, the chip hugged the word: Haris 2026-11-13)
        chip.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.16); chip.textAlignment = .center; chip.layer.masksToBounds = true
        let tw = ceil(("Admin" as NSString).size(withAttributes: [.font: chip.font!]).width)
        chip.frame = CGRect(x: 0, y: 0, width: tw + 20, height: 24); chip.layer.cornerRadius = 12; c.accessoryView = chip
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
  }
  // (the gap between boxes 24, as under the three cards — Apple's were wider: Haris 2026-11-13)
  override func tableView(_ tv: UITableView, heightForHeaderInSection s: Int) -> CGFloat { headTitle(s) == nil ? 0.01 : UITableView.automaticDimension }
  override func tableView(_ tv: UITableView, heightForFooterInSection s: Int) -> CGFloat { footTitle(s) == nil ? 24 : UITableView.automaticDimension }
  private func headTitle(_ s: Int) -> String? {
    guard data.snapshot().sectionIdentifiers.indices.contains(s) else { return nil }
    return data.snapshot().sectionIdentifiers[s] == 1 ? "\(g?.members.count ?? 0) MEMBERS" : nil
  }
  private func footTitle(_ s: Int) -> String? {
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
    case .starred: navigationController?.pushViewController(StarredVC(group: group), animated: true)
    case .media: navigationController?.pushViewController(MediaVC(group: group), animated: true)   // (step 1b — mock-up approved 2026-11-13)
    case .member(let id): personSheet(id, g, at: tv.cellForRow(at: ip))
    case .addMembers:
      // (step 1f: its own sheet — the design's board 41)
      let n = UINavigationController(rootViewController: AddPeopleVC(group: group))
      if let sh = n.sheetPresentationController { sh.detents = [.large()]; sh.prefersGrabberVisible = true }
      present(n, animated: true)
    case .mute: muteSheet(g)
    case .makeMeAdmin: simple(["act": "makeMeAdmin", "group": group], done: "You’re an admin of this group")
    case .second: secondSheet(g, at: tv.cellForRow(at: ip))
    case .leave: GroupActions.leave(group, from: self)
    case .delete: GroupActions.askDelete(g, from: self)
    }
  }
  // Search: back to the chat, its own search open
  private func search() {
    guard let nav = navigationController, let chat = nav.viewControllers.last(where: { ($0 as? ChatVC)?.group == group }) as? ChatVC else { return }
    // (the chat is already searching as it slides back in — Apple's bar brings the search field in with the slide, and the
    //  keyboard comes up once it's there; set after the slide, the title went and the field popped in: Haris 2026-11-13)
    chat.startFind(focus: false, animated: false)
    nav.popToViewController(chat, animated: true)
    if let tc = nav.transitionCoordinator { tc.animate(alongsideTransition: nil) { c in if !c.isCancelled { chat.focusFind() } } } else { chat.focusFind() }
  }
  // Edit (for now the picture and the name — its own sheet is step 1e)
  // (step 1e: Edit Group as its own sheet — the design's board 40)
  private func edit(_ g: Group) {
    let n = UINavigationController(rootViewController: EditGroupVC(group: g.id))
    if let s = n.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
    present(n, animated: true)
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
  private func muteSheet(_ g: Group) {
    // (the design's board 39, word for word — Haris 2026-11-13)
    let a = UIAlertController(title: g.muted ? "Muted" : "Mute \(g.name)", message: "You still get a notification when someone @mentions you.", preferredStyle: .actionSheet)
    if g.muted { a.addAction(UIAlertAction(title: "Unmute", style: .default) { _ in GroupActions.mute(g.id, nil) }) }
    else {
      a.addAction(UIAlertAction(title: "8 Hours", style: .default) { _ in GroupActions.mute(g.id, 8 * 3600) })
      a.addAction(UIAlertAction(title: "1 Week", style: .default) { _ in GroupActions.mute(g.id, 7 * 86400) })
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
}

// ---------- Add Members (step 1f — the design's board 41): Apple's sheet; ✕ · Add Members · Add in Apple's bar, "N selected"
// under the title; Apple's search; the team, then the client's contacts (Super / Office Admins); Apple's own round
// selection marks (the list's multiple selection); the footer as drawn ----------
final class AddPeopleVC: UITableViewController, UISearchResultsUpdating {
  let group: String
  private var picked = Set<String>()
  private var q = ""
  private var data: TitledSource<String, String>!
  private var byId: [String: Person] = [:], sigs: [String: Int] = [:]
  init(group: String) { self.group = group; super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var cname: String { Talk.shared.clients[Talk.shared.groups[group]?.client ?? ""]?.name ?? "Client" }
  // who can be added: the team, and (for Super / Office Admins) the client's contacts — not already in the group
  private func people(_ query: String) -> (team: [Person], contacts: [Person]) {
    let T = Talk.shared, inIt = Set(T.groups[group]?.members ?? [])
    let hit = { (p: Person) in query.isEmpty || p.name.localizedCaseInsensitiveContains(query) }
    let team = T.people.values.filter { !inIt.contains($0.id) && !$0.gone && !$0.contact && hit($0) }.sorted { $0.name < $1.name }
    var cs: [Person] = []
    if T.boss, let g = T.groups[group] {
      cs = T.contacts.filter { $0.client == g.client && !inIt.contains($0.id) }
        .map { Person(id: $0.id, name: $0.name, role: "Client", photo: nil, color: nil, gone: false, contact: true, client: g.client) }.filter(hit)
    }
    return (team, cs)
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Add Members"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let add = UIBarButtonItem(title: "Add", primaryAction: UIAction { [weak self] _ in self?.add() })
    if #available(iOS 26.0, *) { add.style = .prominent } else { add.style = .done }
    add.isEnabled = false; navigationItem.rightBarButtonItem = add
    let sc = UISearchController(searchResultsController: nil); sc.searchResultsUpdater = self; sc.obscuresBackgroundDuringPresentation = false
    sc.searchBar.placeholder = "Search people"
    navigationItem.searchController = sc; navigationItem.hidesSearchBarWhenScrolling = false
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    // (the keyboard follows a drag down; a tap on a person picks them, as Apple's own pickers — Haris 2026-11-13: yes)
    tableView.keyboardDismissMode = .interactive
    // (Apple's round selection marks on the left — the list's own multiple selection)
    tableView.allowsMultipleSelectionDuringEditing = true; tableView.isEditing = true
    // (Apple's change-only list: a search, or someone added elsewhere, only adds and takes away the rows that differ —
    //  the whole list was reloaded on every letter, Haris 2026-11-13)
    data = TitledSource(tableView: tableView) { [weak self] tv, ip, id in
      let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip)
      if id == "none" { PickRows.noResults(c) } else if let p = self?.byId[id] { PickRows.person(c, p, size: 40) }
      return c
    }
    data.defaultRowAnimation = .fade
    data.head = { [weak self] s in
      guard let self = self, let sec = self.data.snapshot().sectionIdentifiers[safe: s] else { return nil }
      return sec == "team" ? "Team" : sec == "contacts" ? "\(self.cname) Contacts" : nil
    }
    data.foot = { [weak self] s in
      guard let self = self, s == self.data.snapshot().numberOfSections - 1 else { return nil }
      return Talk.shared.boss ? "Adding a client contact moves the group to the Clients tab and marks it “Client can see this group”. People already in the group aren’t listed." : "People already in the group aren’t listed."
    }
    data.canEdit = { [weak self] ip in self?.data.itemIdentifier(for: ip) != "none" }
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkGroup, object: group)
    reload(animated: false)
    counted()
  }
  @objc private func changed() { reload(animated: view.window != nil) }
  private func counted() {
    navigationItem.rightBarButtonItem?.isEnabled = !picked.isEmpty
    if #available(iOS 26.0, *) { navigationItem.subtitle = picked.isEmpty ? nil : "\(picked.count) selected" }
  }
  func updateSearchResults(for sc: UISearchController) {
    let n = (sc.searchBar.text ?? "").trimmingCharacters(in: .whitespaces); guard n != q else { return }
    q = n; reload(animated: true)
  }
  private func reload(animated: Bool) {
    // (someone added elsewhere, or gone from the team, is no longer picked)
    let all = people(""); let can = Set((all.team + all.contacts).map { $0.id })
    let before = picked.count; picked = picked.filter { can.contains($0) }; if picked.count != before { counted() }
    let (team, cs) = people(q)
    var snap = NSDiffableDataSourceSnapshot<String, String>()
    if !team.isEmpty { snap.appendSections(["team"]); snap.appendItems(team.map { $0.id }, toSection: "team") }
    if !cs.isEmpty { snap.appendSections(["contacts"]); snap.appendItems(cs.map { $0.id }, toSection: "contacts") }
    if team.isEmpty && cs.isEmpty { snap.appendSections(["none"]); if !q.isEmpty { snap.appendItems(["none"], toSection: "none") } }
    var newSigs: [String: Int] = [:]
    byId = [:]
    for p in team + cs { byId[p.id] = p; var h = Hasher(); h.combine(p.name); h.combine(p.role); h.combine(p.picture); newSigs[p.id] = h.finalize() }
    let old = data.snapshot()
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != nil && sigs[$0] != newSigs[$0] })
    sigs = newSigs
    data.applySteady(snap, in: tableView, animated: animated) { [weak self] in self?.reselect() }
  }
  private func reselect() {
    for id in picked { if let ip = data.indexPath(for: id) { tableView.selectRow(at: ip, animated: false, scrollPosition: .none) } }
  }
  override func tableView(_ tv: UITableView, willSelectRowAt ip: IndexPath) -> IndexPath? { data.itemIdentifier(for: ip) == "none" ? nil : ip }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    guard let id = data.itemIdentifier(for: ip), byId[id] != nil else { return }
    picked.insert(id); UISelectionFeedbackGenerator().selectionChanged(); counted()
  }
  override func tableView(_ tv: UITableView, didDeselectRowAt ip: IndexPath) {
    guard let id = data.itemIdentifier(for: ip), byId[id] != nil else { return }
    picked.remove(id); UISelectionFeedbackGenerator().selectionChanged(); counted()
  }
  private func add() {
    navigationItem.rightBarButtonItem?.isEnabled = false
    Net.shared.act(["act": "addPeople", "group": group, "ids": Array(picked)]) { [weak self] j in
      if (j?["ok"] as? Bool) == true { Talk.shared.refresh(); Talk.shared.sync(); self?.dismiss(animated: true) }
      else { toast(j?["error"] as? String ?? "Couldn’t add them — try again"); self?.counted() }
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
    title = "Client Contacts"   // (the board's words, Title Case as Apple's)
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
      self?.present(UINavigationController(rootViewController: NewContactVC()), animated: true)
    }, menu: nil)
    NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .talkChanged, object: nil)
    Talk.shared.refresh()
  }
  override func numberOfSections(in tv: UITableView) -> Int { max(1, byClient.count) }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { byClient.isEmpty ? 0 : byClient[s].1.count }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { byClient.isEmpty ? nil : byClient[s].0.name }   // (the client's name, as the board)
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == max(1, byClient.count) - 1 ? (byClient.isEmpty ? "No client contacts yet. Tap + to add one. " : "") + "Client contacts only see the groups they’re added to. Super Admins and Office Admins add and remove them." : nil
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
    title = "New Client Contact"
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

// ---------- Edit Group (step 1e — the design's board 40): Apple's sheet; ✕ · Edit Group · Done in Apple's bar; the picture
// with Edit (Take Photo · Choose Photo · Use Client Logo, Apple's menu); the name; the members with Apple's red remove;
// who may do what as the footer. A picture or a removal goes at once (as everywhere); the name on Done. ----------
final class EditGroupVC: UITableViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate {
  let group: String
  init(group: String) { self.group = group; super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  private var g: Group? { Talk.shared.groups[group] }
  private let pic = Avatar(frame: CGRect(x: 0, y: 0, width: 88, height: 88))
  private let field = UITextField()
  private var gone = Set<String>()   // (removed here: off the list at once)
  private lazy var spin: UIActivityIndicatorView = {
    let s = UIActivityIndicatorView(style: .medium); s.color = .white; s.hidesWhenStopped = true
    s.backgroundColor = UIColor.black.withAlphaComponent(0.35); s.layer.cornerRadius = 44; s.clipsToBounds = true
    s.frame = pic.bounds; pic.addSubview(s); return s
  }()
  private var people: [String] {
    guard let g = g else { return [] }
    let me = Talk.shared.me?.id
    return g.members.filter { !gone.contains($0) }.sorted { a, b in
      let aa = g.admins.contains(a), ba = g.admins.contains(b)
      if aa != ba { return aa }
      if (a == me) != (b == me) { return b == me }
      return Talk.shared.name(a) < Talk.shared.name(b)
    }
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Edit Group"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    let done = UIBarButtonItem(title: "Done", primaryAction: UIAction { [weak self] _ in self?.save() })
    if #available(iOS 26.0, *) { done.style = .prominent } else { done.style = .done }
    navigationItem.rightBarButtonItem = done
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    tableView.isEditing = true; tableView.allowsSelectionDuringEditing = true
    tableView.keyboardDismissMode = .interactive
    field.text = g?.name; field.font = .systemFont(ofSize: 17); field.clearButtonMode = .whileEditing
    field.autocapitalizationType = .sentences; field.returnKeyType = .done; field.delegate = self
    field.placeholder = "Group name"
    // the top: the picture and Edit under it, Apple's menu
    let head = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 136))
    pic.translatesAutoresizingMaskIntoConstraints = false; head.addSubview(pic)
    if let g = g { pic.set(group: g) }
    let edit = UIButton(type: .system); edit.setTitle("Edit", for: .normal); edit.titleLabel?.font = .systemFont(ofSize: 17)
    edit.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.picMenu() ?? []) }]); edit.showsMenuAsPrimaryAction = true
    edit.translatesAutoresizingMaskIntoConstraints = false; head.addSubview(edit)
    NSLayoutConstraint.activate([pic.topAnchor.constraint(equalTo: head.topAnchor, constant: 4), pic.centerXAnchor.constraint(equalTo: head.centerXAnchor),
                                 pic.widthAnchor.constraint(equalToConstant: 88), pic.heightAnchor.constraint(equalToConstant: 88),
                                 edit.topAnchor.constraint(equalTo: pic.bottomAnchor, constant: 4), edit.centerXAnchor.constraint(equalTo: head.centerXAnchor)])
    tableView.tableHeaderView = head
    setUpList()
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
  }
  private func picMenu() -> [UIMenuElement] {
    var xs: [UIMenuElement] = []
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      xs.append(UIAction(title: "Take Photo", image: UIImage(systemName: "camera")) { [weak self] _ in
        let p = UIImagePickerController(); p.sourceType = .camera; p.delegate = self; self?.present(p, animated: true)
      })
    }
    xs.append(UIAction(title: "Choose Photo", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
      var c = PHPickerConfiguration(); c.filter = .images; c.selectionLimit = 1
      let p = PHPickerViewController(configuration: c); p.delegate = self; self?.present(p, animated: true)
    })
    if let g = g, g.pic != nil, Talk.shared.clients[g.client]?.logo != nil {
      xs.append(UIAction(title: "Use Client Logo", image: UIImage(systemName: "building.2")) { [weak self] _ in self?.setPic(nil, nil) })
    }
    return xs
  }
  @objc private func changed() {
    guard let g = g else { dismiss(animated: true); return }
    if !spin.isAnimating { pic.set(group: g) }
    reload(animated: view.window != nil)
  }
  private func save() {
    let n = (field.text ?? "").trimmingCharacters(in: .whitespaces)
    if let g = g, !n.isEmpty, n != g.name {
      Net.shared.act(["act": "rename", "group": group, "name": n]) { j in
        if (j?["ok"] as? Bool) == true { Talk.shared.refresh(); Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t do that — try again") }
      }
    }
    dismiss(animated: true)
  }
  func textFieldShouldReturn(_ t: UITextField) -> Bool { t.resignFirstResponder(); return true }

  // ---------- the list ----------
  // (Apple's change-only list — the redraw rule: a member's row is set again only when what it shows changed, at once with
  //  nothing moving; one removed fades out and the rest slide up — Haris 2026-11-13. It reloaded the whole members part
  //  on every change.)
  private var data: TitledSource<Int, String>!
  private var sigs: [String: Int] = [:]
  private func setUpList() {
    data = TitledSource(tableView: tableView) { [weak self] tv, ip, id in
      let c = tv.dequeueReusableCell(withIdentifier: "c", for: ip); self?.fill(c, id); return c
    }
    data.defaultRowAnimation = .fade
    data.head = { s in s == 0 ? "Group Name" : "Members" }
    data.foot = { s in
      s == 0 ? "Edit the picture: Take Photo · Choose Photo · Use Client Logo."
        : "The creator, Super Admins and Office Admins can change the picture and name and remove people. The creator stays unless a Super or Office Admin removes them."
    }
    data.canEdit = { ip in ip.section == 1 }
    data.onDelete = { [weak self] ip in self?.remove(ip) }
    reload(animated: false)
  }
  private func reload(animated: Bool) {
    guard let g = g else { return }
    let T = Talk.shared, ps = people
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    snap.appendSections([0, 1]); snap.appendItems(["field"], toSection: 0); snap.appendItems(ps, toSection: 1)
    var newSigs: [String: Int] = [:]
    for id in ps {
      var h = Hasher(); h.combine(T.name(id)); h.combine(T.people[id]?.role); h.combine(T.people[id]?.picture); h.combine(T.people[id]?.contact)
      h.combine(g.creator == id); h.combine(g.second == id); h.combine(g.admins.contains(id)); h.combine(canRemove(id))
      newSigs[id] = h.finalize()
    }
    let old = data.snapshot()
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != nil && sigs[$0] != newSigs[$0] })
    sigs = newSigs
    data.applySteady(snap, in: tableView, animated: animated)
  }
  private func fill(_ c: UITableViewCell, _ id: String) {
    // (Apple's content view first, ours into it — Group Info's lesson)
    if c.contentConfiguration == nil { c.contentConfiguration = UIListContentConfiguration.cell() }
    c.contentView.subviews.filter { $0.tag == 77 }.forEach { $0.removeFromSuperview() }
    c.selectionStyle = .none
    if id == "field" {
      var cfg = UIListContentConfiguration.cell(); cfg.text = " "; c.contentConfiguration = cfg
      field.tag = 77; field.translatesAutoresizingMaskIntoConstraints = false; c.contentView.addSubview(field)
      NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.leadingAnchor), field.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor),
                                   field.topAnchor.constraint(equalTo: c.contentView.topAnchor), field.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor)])
      return
    }
    let T = Talk.shared, p = T.people[id]
    var cfg = UIListContentConfiguration.subtitleCell()
    cfg.text = id == T.me?.id ? "You" : T.name(id)
    let tag = g?.creator == id ? "Admin" : g?.second == id ? "Second Admin" : g?.admins.contains(id) == true ? "Admin" : nil
    let role = p?.contact == true ? "Client" : p?.role
    cfg.secondaryText = [role, tag].compactMap { $0 }.joined(separator: " · ")
    cfg.secondaryTextProperties.color = p?.contact == true ? .systemOrange : .secondaryLabel
    cfg.secondaryTextProperties.font = p?.contact == true ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
    cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear
    cfg.imageProperties.reservedLayoutSize = CGSize(width: 38, height: 38); cfg.imageProperties.maximumSize = CGSize(width: 38, height: 38)
    cfg.directionalLayoutMargins.top = 9; cfg.directionalLayoutMargins.bottom = 9
    c.contentConfiguration = cfg
    let a = Avatar(frame: CGRect(x: 16, y: 10, width: 38, height: 38)); a.tag = 77; a.isUserInteractionEnabled = false; a.set(person: p)
    c.contentView.addSubview(a)
  }
  private func canRemove(_ id: String) -> Bool {
    guard let g = g else { return false }
    let T = Talk.shared
    return id != T.me?.id && T.canManage(g) && (id != g.creator || T.boss)
  }
  override func tableView(_ tv: UITableView, editingStyleForRowAt ip: IndexPath) -> UITableViewCell.EditingStyle {
    guard ip.section == 1, let id = data.itemIdentifier(for: ip) else { return .none }
    return canRemove(id) ? .delete : .none
  }
  override func tableView(_ tv: UITableView, shouldIndentWhileEditingRowAt ip: IndexPath) -> Bool { ip.section == 1 }
  override func tableView(_ tv: UITableView, titleForDeleteConfirmationButtonForRowAt ip: IndexPath) -> String? { "Remove" }
  private func remove(_ ip: IndexPath) {
    guard ip.section == 1, let id = data.itemIdentifier(for: ip), id != "field" else { return }
    let name = Talk.shared.name(id)
    // (gone from the list at once — Apple's own row animation; the server's answer then draws it as it is)
    gone.insert(id); reload(animated: true)
    Net.shared.act(["act": "removePerson", "group": group, "id": id]) { [weak self] j in
      if (j?["ok"] as? Bool) == true { toast("\(name) removed"); Talk.shared.refresh(); Talk.shared.sync() }
      else { toast(j?["error"] as? String ?? "Couldn’t do that — try again"); self?.gone.remove(id); self?.reload(animated: true) }
    }
  }

  // ---------- the picture ----------
  func picker(_ p: PHPickerViewController, didFinishPicking r: [PHPickerResult]) {
    p.dismiss(animated: true)
    guard let ip = r.first?.itemProvider, ip.canLoadObject(ofClass: UIImage.self) else { return }
    ip.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
      guard let img = obj as? UIImage else { return }
      DispatchQueue.main.async { self?.upload(img) }
    }
  }
  func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    p.dismiss(animated: true)
    if let img = info[.originalImage] as? UIImage { upload(img) }
  }
  func imagePickerControllerDidCancel(_ p: UIImagePickerController) { p.dismiss(animated: true) }
  private func upload(_ img: UIImage) {
    let side: CGFloat = 640, s = side / min(img.size.width, img.size.height)
    let sq = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in img.draw(in: CGRect(x: (side - img.size.width * s) / 2, y: (side - img.size.height * s) / 2, width: img.size.width * s, height: img.size.height * s)) }
    guard let d = sq.jpegData(compressionQuality: 0.85) else { return }
    pic.show(sq); spin.startAnimating()
    Net.shared.upload(d, name: "group.jpg", progress: { _ in }) { [weak self] fid in
      guard let fid = fid else { self?.spin.stopAnimating(); if let g = self?.g { self?.pic.set(group: g) }; toast("The picture didn’t upload — try again"); return }
      try? d.write(to: Net.local(fid))
      self?.setPic(fid, sq)
    }
  }
  private func setPic(_ fid: String?, _ shown: UIImage?) {
    if shown == nil { spin.startAnimating() }
    Net.shared.act(["act": "setPic", "group": group, "file": fid.map { $0 as Any } ?? NSNull()]) { [weak self] j in
      if (j?["ok"] as? Bool) == true { Talk.shared.refresh(); Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t do that — try again") }
      self?.spin.stopAnimating(); if let g = self?.g { self?.pic.set(group: g) }
      if let self = self { (self.tableView.tableHeaderView?.subviews.compactMap { $0 as? UIButton }.first)?.menu = UIMenu(children: self.picMenu()) }
    }
  }
}


// A diffable list with section titles: Apple asks the data source for them (the page's own title methods are never asked
// once a diffable data source is set)
final class TitledSource<S: Hashable, I: Hashable>: UITableViewDiffableDataSource<S, I> {
  var head: ((Int) -> String?)?, foot: ((Int) -> String?)?, canEdit: ((IndexPath) -> Bool)?, onDelete: ((IndexPath) -> Void)?
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { head?(s) }
  override func tableView(_ tv: UITableView, canEditRowAt ip: IndexPath) -> Bool { canEdit?(ip) ?? false }
  override func tableView(_ tv: UITableView, commit s: UITableViewCell.EditingStyle, forRowAt ip: IndexPath) { if s == .delete { onDelete?(ip) } }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? { foot?(s) }
}

// The rows of the people pickers (New Group, Add Members) and the client picker's nothing-found row
enum PickRows {
  // a person: their picture, name, and role (a client contact's in orange) — Apple's subtitle cell with our picture in it
  static func person(_ c: UITableViewCell, _ p: Person, size: CGFloat) {
    // (Apple's content view first, ours into it — Group Info's lesson)
    if c.contentConfiguration == nil { c.contentConfiguration = UIListContentConfiguration.subtitleCell() }
    c.contentView.subviews.filter { $0.tag == 77 }.forEach { $0.removeFromSuperview() }
    c.accessoryType = .none; c.selectionStyle = .default; c.backgroundConfiguration = nil
    var cfg = UIListContentConfiguration.subtitleCell()
    cfg.text = p.name; cfg.secondaryText = p.role
    cfg.secondaryTextProperties.color = p.contact ? .systemOrange : .secondaryLabel
    cfg.secondaryTextProperties.font = p.contact ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
    cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear
    cfg.imageProperties.reservedLayoutSize = CGSize(width: size, height: size); cfg.imageProperties.maximumSize = CGSize(width: size, height: size)
    // (room above and below — the grey line under the name was cut off at the old fixed height)
    cfg.directionalLayoutMargins.top = 10; cfg.directionalLayoutMargins.bottom = 10
    c.contentConfiguration = cfg
    let a = Avatar(frame: CGRect(x: 16, y: 10, width: size, height: size)); a.tag = 77; a.isUserInteractionEnabled = false; a.set(person: p)
    c.contentView.addSubview(a)
  }
  // a search with nothing found: Apple's own "No Results" (iOS 16: the line alone)
  static func noResults(_ c: UITableViewCell) {
    c.contentView.subviews.filter { $0.tag == 77 }.forEach { $0.removeFromSuperview() }
    c.accessoryType = .none; c.selectionStyle = .none
    var bg = UIBackgroundConfiguration.clear(); bg.backgroundColor = .clear; c.backgroundConfiguration = bg
    if #available(iOS 17.0, *) { c.contentConfiguration = UIContentUnavailableConfiguration.search() }
    else { var e = UIListContentConfiguration.cell(); e.text = "No Results"; e.textProperties.alignment = .center; e.textProperties.color = .secondaryLabel; c.contentConfiguration = e }
  }
}

// The redraw rule (Haris 2026-11-13: "nothing slides while anything changes"): rows that only change in place are set at
// once, laid out without animation, nothing on the page moving; rows coming or going fade, the rest sliding to make room.
// …and nothing snaps (Haris 2026-11-13: "things still appear in a snap"): a row changed in place crossfades to its new look
// in its place — the old picture of it fading out over the new one fading in — with nothing around it moving.
enum Crossfade {
  static let time: TimeInterval = 0.22
  // pictures of the rows about to change, laid over them where they are — inside the row itself, so the picture goes
  // wherever the row goes: laid on the list, a row moving under it (a message growing as the list keeps its end in place)
  // left the picture behind, the old look sliding away from the new — the card "flying down" (Haris 2026-11-13)
  static func cover(_ cells: [UIView], in host: UIView) -> [UIView] {
    cells.compactMap { c in
      let into = (c as? UITableViewCell)?.contentView ?? (c as? UICollectionViewCell)?.contentView ?? c
      // (a still picture — a snapshot view can go on showing the row as it changes)
      guard into.bounds.width > 0, into.bounds.height > 0 else { return nil }
      let img = UIGraphicsImageRenderer(bounds: into.bounds).image { _ in into.drawHierarchy(in: into.bounds, afterScreenUpdates: false) }
      let s = UIImageView(image: img); s.frame = into.bounds; s.isUserInteractionEnabled = false; into.addSubview(s); return s
    }
  }
  // the old picture fading away over the new look, already there under it — the new one isn't faded in too: both half
  // see-through at once let the page show through, a flash (Haris 2026-11-13)
  static func run(_ shots: [UIView], new cells: [UIView]) {
    guard !shots.isEmpty else { return }
    UIView.animate(withDuration: time, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
      shots.forEach { $0.alpha = 0 }
    } completion: { _ in shots.forEach { $0.removeFromSuperview() } }
  }
}
extension UITableViewDiffableDataSource {
  func applySteady(_ snap: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, in tv: UITableView, animated: Bool, layout: Bool = true, done: (() -> Void)? = nil) {
    let old = snapshot()
    if !animated || (old.sectionIdentifiers == snap.sectionIdentifiers && old.itemIdentifiers == snap.itemIdentifiers) {
      let ids = animated ? snap.reconfiguredItemIdentifiers : []
      let shots = Crossfade.cover(ids.compactMap { indexPath(for: $0).flatMap { tv.cellForRow(at: $0) } }, in: tv)
      UIView.performWithoutAnimation { apply(snap, animatingDifferences: false); if layout { tv.layoutIfNeeded() } }
      Crossfade.run(shots, new: ids.compactMap { indexPath(for: $0).flatMap { tv.cellForRow(at: $0)?.contentView } })
      done?()
    } else {
      // (rows coming, going or moving glide — but a row both moving and changed isn't reloaded in that glide: Apple
      //  reloads a moving row by fading it out and in, a flash on a row that never went (ALAIN as a client above it was
      //  pinned — Haris 2026-11-13). The rows glide as they are, then the changed ones crossfade in place.)
      let changed = snap.reconfiguredItemIdentifiers
      var plain = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()
      plain.appendSections(snap.sectionIdentifiers)
      for sec in snap.sectionIdentifiers { plain.appendItems(snap.itemIdentifiers(inSection: sec), toSection: sec) }
      apply(plain, animatingDifferences: true) { [weak self, weak tv] in
        guard let self = self, let tv = tv, !changed.isEmpty else { done?(); return }
        var again = self.snapshot(); let here = changed.filter { again.indexOfItem($0) != nil }
        guard !here.isEmpty else { done?(); return }
        again.reconfigureItems(here); self.applySteady(again, in: tv, animated: true, done: done)
      }
    }
  }
}
extension UICollectionViewDiffableDataSource {
  func applySteady(_ snap: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, in cv: UICollectionView, animated: Bool, done: (() -> Void)? = nil) {
    let old = snapshot()
    if !animated || (old.sectionIdentifiers == snap.sectionIdentifiers && old.itemIdentifiers == snap.itemIdentifiers) {
      let ids = animated ? snap.reconfiguredItemIdentifiers : []
      let shots = Crossfade.cover(ids.compactMap { indexPath(for: $0).flatMap { cv.cellForItem(at: $0) } }, in: cv)
      UIView.performWithoutAnimation { apply(snap, animatingDifferences: false); cv.layoutIfNeeded() }
      Crossfade.run(shots, new: ids.compactMap { indexPath(for: $0).flatMap { cv.cellForItem(at: $0)?.contentView } })
      done?()
    } else {
      // (rows coming, going or moving glide — but a row both moving and changed isn't reloaded in that glide: Apple
      //  reloads a moving row by fading it out and in, a flash on a row that never went (ALAIN as a client above it was
      //  pinned — Haris 2026-11-13). The rows glide as they are, then the changed ones crossfade in place.)
      let changed = snap.reconfiguredItemIdentifiers
      var plain = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()
      plain.appendSections(snap.sectionIdentifiers)
      for sec in snap.sectionIdentifiers { plain.appendItems(snap.itemIdentifiers(inSection: sec), toSection: sec) }
      apply(plain, animatingDifferences: true) { [weak self, weak cv] in
        guard let self = self, let cv = cv, !changed.isEmpty else { done?(); return }
        var again = self.snapshot(); let here = changed.filter { again.indexOfItem($0) != nil }
        guard !here.isEmpty else { done?(); return }
        again.reconfigureItems(here); self.applySteady(again, in: cv, animated: true, done: done)
      }
    }
  }
}
