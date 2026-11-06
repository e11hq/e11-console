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
  init(client: String?) { self.client = client; super.init(style: .insetGrouped) }
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

  private var people: [Person] {
    let me = Talk.shared.me?.id
    return Talk.shared.people.values.filter { $0.id != me && !$0.gone && (q.isEmpty || $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q)) }.sorted { $0.name < $1.name }
  }
  override func numberOfSections(in tv: UITableView) -> Int { 3 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? 1 : s == 1 ? 1 : people.count + 1 }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { s == 1 ? "Client" : s == 2 ? "People · \(picked.count)" : nil }
  override func tableView(_ tv: UITableView, titleForFooterInSection s: Int) -> String? {
    s == 0 ? "The picture is the client’s logo from Client Assets — you can change it later." : s == 2 ? "Only the group’s admins add people. Nobody joins by themselves; anyone can leave." : nil
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
      let pick = ClientPickVC(selected: client) { [weak self] id in self?.client = id; self?.check(); self?.tableView.reloadSections([0, 1], with: .none) }
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
  let group: String
  init(group: String) { self.group = group; super.init(style: .insetGrouped); hidesBottomBarWhenPushed = true }
  required init?(coder: NSCoder) { fatalError() }
  private var g: Group? { Talk.shared.groups[group] }
  private enum Act { case addPeople, rename, picture, mute, pin, makeMeAdmin, leave, delete }
  private var actions: [Act] {
    guard let g = g else { return [] }
    let T = Talk.shared
    var a: [Act] = [.mute, .pin]
    if T.canManage(g) { a = [.addPeople, .rename, .picture] + a }
    if T.boss && !T.isAdmin(g) { a.append(.makeMeAdmin) }
    return a
  }
  private var members: [String] {
    guard let g = g else { return [] }
    return g.members.sorted { a, b in
      let aa = g.admins.contains(a), ba = g.admins.contains(b)
      if aa != ba { return aa }
      return Talk.shared.name(a) < Talk.shared.name(b)
    }
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Group info"
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(gone(_:)), name: .talkGone, object: nil)
  }
  @objc private func changed() { if g == nil { navigationController?.popToRootViewController(animated: true); return }; tableView.reloadData() }
  @objc private func gone(_ n: Notification) { if (n.object as? String) == group { navigationController?.popToRootViewController(animated: true) } }

  override func numberOfSections(in tv: UITableView) -> Int { 4 }
  override func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int {
    guard g != nil else { return 0 }
    return [1, actions.count, members.count, Talk.shared.canManage(g!) ? 2 : 1][s]
  }
  override func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? { s == 2 ? "\(members.count) people" : nil }
  override func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { ip.section == 0 ? 190 : ip.section == 2 ? 58 : 48 }
  override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    guard let g = g else { return c }
    let T = Talk.shared
    switch ip.section {
    case 0:
      c.selectionStyle = .none; c.backgroundColor = .clear
      let a = Avatar(frame: CGRect(x: (tv.bounds.width - 32 - 96) / 2, y: 6, width: 96, height: 96)); a.set(group: g); c.contentView.addSubview(a)
      let n = UILabel(frame: CGRect(x: 10, y: 110, width: tv.bounds.width - 52, height: 30)); n.text = g.name; n.font = .systemFont(ofSize: 22, weight: .bold); n.textAlignment = .center
      let s = UILabel(frame: CGRect(x: 10, y: 142, width: tv.bounds.width - 52, height: 40)); s.numberOfLines = 2; s.textAlignment = .center; s.font = .systemFont(ofSize: 14); s.textColor = .secondaryLabel
      s.text = "\(T.clients[g.client]?.name ?? "") · made by \(T.name(g.creator)) · \(Look.day(g.createdAt))"
      [n, s].forEach { c.contentView.addSubview($0) }
    case 1:
      var cfg = c.defaultContentConfiguration()
      switch actions[ip.row] {
      case .addPeople: cfg.text = "Add people"; cfg.image = UIImage(systemName: "person.badge.plus")
      case .rename: cfg.text = "Rename group"; cfg.image = UIImage(systemName: "pencil")
      case .picture: cfg.text = g.pic == nil ? "Change picture" : "Change picture"; cfg.image = UIImage(systemName: "photo")
      case .mute:
        cfg.text = g.muted ? "Muted" : "Mute"; cfg.image = UIImage(systemName: g.muted ? "bell.slash.fill" : "bell.slash")
        cfg.secondaryText = g.muted ? ((g.mutedUntil ?? 0) > 8e15 ? "Always — an @mention still notifies you" : "Until " + Look.time(g.mutedUntil ?? 0, short: true)) : nil
        c.accessoryView = muteButton(g)
      case .pin:
        let on = T.pinnedGroups.contains(group)
        cfg.text = on ? "Unpin" : "Pin"; cfg.image = UIImage(systemName: on ? "pin.slash" : "pin"); cfg.secondaryText = "Pinned groups stay above your clients — up to 5"
      case .makeMeAdmin: cfg.text = "Make me admin"; cfg.image = UIImage(systemName: "star"); cfg.secondaryText = "As a Super Admin / Office Admin"
      default: break
      }
      cfg.imageProperties.tintColor = Look.accent; cfg.textProperties.color = Look.accent; cfg.secondaryTextProperties.color = .secondaryLabel
      c.contentConfiguration = cfg
    case 2:
      let id = members[ip.row], p = T.people[id]
      var cfg = c.defaultContentConfiguration()
      cfg.text = T.name(id); cfg.secondaryText = p?.role; cfg.secondaryTextProperties.color = .secondaryLabel
      cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear; cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
      c.contentConfiguration = cfg
      let a = Avatar(frame: CGRect(x: 16, y: 9, width: 40, height: 40)); a.set(person: p); c.contentView.addSubview(a)
      if g.admins.contains(id) {
        let chip = PaddedLabel(); chip.text = id == g.creator ? "Creator · Admin" : "Admin"; chip.font = .systemFont(ofSize: 12, weight: .semibold); chip.textColor = Look.accent
        chip.backgroundColor = Look.accent.withAlphaComponent(0.12); chip.layer.cornerRadius = 9; chip.layer.masksToBounds = true
        chip.sizeToFit(); chip.frame.size = CGSize(width: chip.frame.width, height: 22); c.accessoryView = chip
      }
    default:
      var cfg = c.defaultContentConfiguration()
      cfg.text = ip.row == 0 ? "Leave group" : "Delete group"; cfg.textProperties.color = .systemRed
      cfg.image = UIImage(systemName: ip.row == 0 ? "rectangle.portrait.and.arrow.right" : "trash"); cfg.imageProperties.tintColor = .systemRed
      c.contentConfiguration = cfg
    }
    return c
  }
  private func muteButton(_ g: Group) -> UIView? { nil }
  override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard let g = g else { return }
    switch ip.section {
    case 1:
      switch actions[ip.row] {
      case .addPeople: navigationController?.pushViewController(AddPeopleVC(group: group), animated: true)
      case .rename: rename(g)
      case .picture: changePicture()
      case .mute: muteSheet(g)
      case .pin:
        let on = Talk.shared.pinnedGroups.contains(group)
        Net.shared.act(["act": "pin", "id": group, "on": !on]) { j in
          if (j?["full"] as? Bool) == true { toast("Pinned is full — unpin one from the Groups list first") } else { Talk.shared.refresh() }
        }
      case .makeMeAdmin: simple(["act": "makeMeAdmin", "group": group], done: "You’re an admin of this group")
      default: break
      }
    case 2: personSheet(members[ip.row], g, at: tv.cellForRow(at: ip))
    case 3:
      if ip.row == 0 { GroupActions.leave(group, from: self) }
      else {
        let a = UIAlertController(title: "Delete “\(g.name)”?", message: "It goes for everyone in it. Messages already on their phones stay there until they’re cleared.", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Delete group", style: .destructive) { [weak self] _ in self?.simple(["act": "deleteGroup", "group": self?.group ?? ""], done: "Group deleted") })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(a, animated: true)
      }
    default: break
    }
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
        toast("Changing the picture…")
        Net.shared.upload(d, name: "group.jpg", progress: { _ in }) { fid in
          guard let fid = fid else { toast("The picture didn’t upload — try again"); return }
          try? d.write(to: Net.local(fid))
          self.simple(["act": "setPic", "group": self.group, "file": fid], done: "Picture changed")
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
    let inIt = Set(Talk.shared.groups[group]?.members ?? [])
    return Talk.shared.people.values.filter { !inIt.contains($0.id) && !$0.gone }.sorted { $0.name < $1.name }
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
