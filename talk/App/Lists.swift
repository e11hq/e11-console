import UIKit

/* The lists (the approved mockups, design/e11-chat/e11talk-main-*.png — Haris 2026-11-05 "loveeee!!"):
   Groups — your pinned groups (up to 5) on top, then one row per client (its logo, its newest message, the total
   unread of its groups), newest activity first (Haris 2026-11-06: "like WhatsApp"); a client → its groups, newest
   first, each with its own unread count. Holding a group: Pin · Mute · Mark as read · Group info · Leave.
   Each row is kept by its id and only redrawn when what it shows changes (iPhone's diffable lists). */
enum Row: Hashable { case group(String), client(String) }

final class ChatRowCell: UITableViewCell {
  static let id = "row"
  let avatar = Avatar()
  private let title = UILabel(), sub = UILabel(), time = UILabel(), badge = PaddedBadge(), icons = UIStackView()
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    title.font = .systemFont(ofSize: 17, weight: .semibold)
    sub.font = .systemFont(ofSize: 15); sub.textColor = .secondaryLabel
    time.font = .systemFont(ofSize: 13); time.textAlignment = .right
    icons.axis = .horizontal; icons.spacing = 4; icons.alignment = .center
    [avatar, title, sub, time, badge, icons].forEach { contentView.addSubview($0) }
    separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = contentView.bounds.width, H = contentView.bounds.height
    avatar.frame = CGRect(x: 16, y: (H - 52) / 2, width: 52, height: 52)
    let tw = time.sizeThatFits(CGSize(width: 120, height: 20)).width
    time.frame = CGRect(x: W - 16 - tw, y: 13, width: tw, height: 18)
    title.frame = CGRect(x: 80, y: 11, width: W - 80 - tw - 24, height: 22)
    var right = W - 16
    if !badge.isHidden { let bw = max(20, badge.sizeThatFits(.zero).width); badge.frame = CGRect(x: right - bw, y: 38, width: bw, height: 20); right -= bw + 6 }
    let iw = icons.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
    icons.frame = CGRect(x: right - iw, y: 38, width: iw, height: 20); right -= iw + (iw > 0 ? 6 : 0)
    sub.frame = CGRect(x: 80, y: 37, width: right - 80, height: 21)
  }
  private func icon(_ n: String) -> UIImageView {
    let v = UIImageView(image: UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
    v.tintColor = .tertiaryLabel; return v
  }
  func show(title t: String, sub s: String, time tm: String, unread: Int, pinned: Bool, muted: Bool, chip: String? = nil) {
    title.text = t; sub.text = s; time.text = tm
    time.textColor = unread > 0 ? Look.accent : .secondaryLabel
    badge.isHidden = unread == 0; badge.text = unread > 99 ? "99+" : "\(unread)"
    badge.backgroundColor = muted ? .systemGray3 : Look.accent
    icons.arrangedSubviews.forEach { $0.removeFromSuperview() }
    if muted { icons.addArrangedSubview(icon("bell.slash.fill")) }
    if pinned { icons.addArrangedSubview(icon("pin.fill")) }
    setNeedsLayout()
  }
}
final class PaddedBadge: UILabel {
  override init(frame: CGRect) { super.init(frame: frame); font = .systemFont(ofSize: 13, weight: .semibold); textColor = .white; textAlignment = .center; layer.cornerRadius = 10; layer.masksToBounds = true }
  required init?(coder: NSCoder) { fatalError() }
  override func sizeThatFits(_ size: CGSize) -> CGSize { let s = super.sizeThatFits(size); return CGSize(width: s.width + 12, height: 20) }
}

class ListVC: UIViewController, UITableViewDelegate, UISearchResultsUpdating {
  let table = UITableView(frame: .zero, style: .plain)
  var data: UITableViewDiffableDataSource<String, Row>!
  let search = UISearchController(searchResultsController: nil)
  var query: String { (search.searchBar.text ?? "").trimmingCharacters(in: .whitespaces).lowercased() }
  var sections: [String: String] = [:]   // section key → its heading

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    table.frame = view.bounds; table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    table.rowHeight = 72; table.delegate = self
    table.register(ChatRowCell.self, forCellReuseIdentifier: ChatRowCell.id)
    table.sectionHeaderTopPadding = 6
    view.addSubview(table)
    data = UITableViewDiffableDataSource<String, Row>(tableView: table) { [weak self] tv, ip, row in
      let c = tv.dequeueReusableCell(withIdentifier: ChatRowCell.id, for: ip) as! ChatRowCell
      self?.fill(c, row)
      return c
    }
    data.defaultRowAnimation = .fade
    search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
    navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
  }
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); reload(animated: false) }
  @objc func changed() { reload(animated: view.window != nil) }
  func updateSearchResults(for s: UISearchController) { reload(animated: false) }
  func build() -> [(String, String, [Row])] { [] }
  func reload(animated: Bool) {
    var snap = NSDiffableDataSourceSnapshot<String, Row>()
    sections = [:]
    for (key, head, rows) in build() where !rows.isEmpty { snap.appendSections([key]); snap.appendItems(rows, toSection: key); sections[key] = head }
    // (rows that stay: drawn again in place — only what they show changes)
    snap.reconfigureItems(snap.itemIdentifiers.filter { data.snapshot().indexOfItem($0) != nil })
    data.apply(snap, animatingDifferences: animated)
    emptyNote()
  }
  func emptyNote() {}
  func fill(_ c: ChatRowCell, _ row: Row) {
    let T = Talk.shared
    switch row {
    case .group(let id):
      guard let g = T.groups[id] else { return }
      c.avatar.set(group: g)
      let m = T.last(id)
      let line = m.map { ($0.kind == "sys" ? "" : "\(T.name($0.by)): ") + Talk.preview($0) } ?? "No messages yet"
      c.show(title: g.name, sub: line, time: Look.time(T.activity(g)), unread: T.unread(id), pinned: T.pinnedGroups.contains(id), muted: g.muted)
    case .client(let id):
      guard let cl = T.clients[id] else { return }
      c.avatar.set(client: cl)
      let gs = T.groups(of: id)
      let newest = gs.first.flatMap { g in T.last(g.id).map { (g, $0) } }
      let line = newest.map { (_, m) in (m.kind == "sys" ? "" : "\(T.name(m.by)): ") + Talk.preview(m) } ?? "\(gs.count) group\(gs.count == 1 ? "" : "s")"
      c.show(title: cl.name, sub: line, time: Look.time(T.clientActivity(id)), unread: T.clientUnread(id), pinned: T.pinnedClients.contains(id), muted: false)
    }
  }
  func tableView(_ tv: UITableView, heightForHeaderInSection s: Int) -> CGFloat {
    let key = data.snapshot().sectionIdentifiers[s]; return (sections[key] ?? "").isEmpty ? 0 : 32
  }
  func tableView(_ tv: UITableView, viewForHeaderInSection s: Int) -> UIView? {
    let key = data.snapshot().sectionIdentifiers[s], head = sections[key] ?? ""
    guard !head.isEmpty else { return nil }
    let v = UIView(), l = UILabel()
    let a = NSMutableAttributedString()
    if key == "pins" { a.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))!.withTintColor(.secondaryLabel)))); a.append(NSAttributedString(string: " ")) }
    a.append(NSAttributedString(string: head, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.secondaryLabel]))
    l.attributedText = a; l.frame = CGRect(x: 18, y: 8, width: 300, height: 22); v.addSubview(l)
    return v
  }
  func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard let row = data.itemIdentifier(for: ip) else { return }
    switch row {
    case .group(let id): navigationController?.pushViewController(ChatVC(group: id), animated: true)
    case .client(let id): navigationController?.pushViewController(ClientGroupsVC(client: id), animated: true)
    }
  }
  // holding a group: Pin · Mute · Mark as read · Group info · Leave group; a client: Pin
  func tableView(_ tv: UITableView, contextMenuConfigurationForRowAt ip: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    guard let row = data.itemIdentifier(for: ip) else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      guard let self = self else { return nil }
      switch row {
      case .group(let id): return self.groupMenu(id)
      case .client(let id):
        let on = Talk.shared.pinnedClients.contains(id)
        return UIMenu(children: [UIAction(title: on ? "Unpin" : "Pin", image: UIImage(systemName: on ? "pin.slash" : "pin")) { _ in self.pin(client: id, !on) }])
      }
    }
  }
  func tableView(_ tv: UITableView, previewForHighlightingContextMenuWithConfiguration c: UIContextMenuConfiguration) -> UITargetedPreview? { nil }

  func groupMenu(_ id: String) -> UIMenu? {
    let T = Talk.shared
    guard let g = T.groups[id] else { return nil }
    let pinned = T.pinnedGroups.contains(id)
    let mute: UIMenuElement = g.muted
      ? UIAction(title: "Unmute", image: UIImage(systemName: "bell")) { _ in GroupActions.mute(id, nil) }
      : UIMenu(title: "Mute", image: UIImage(systemName: "bell.slash"), children: [
          UIAction(title: "8 hours") { _ in GroupActions.mute(id, 8 * 3600) },
          UIAction(title: "1 week") { _ in GroupActions.mute(id, 7 * 86400) },
          UIAction(title: "Always") { _ in GroupActions.mute(id, -1) }])
    return UIMenu(title: g.name, children: [
      UIAction(title: pinned ? "Unpin" : "Pin", image: UIImage(systemName: pinned ? "pin.slash" : "pin")) { [weak self] _ in self?.pin(group: id, !pinned) },
      mute,
      UIAction(title: "Mark as read", image: UIImage(systemName: "checkmark.circle")) { _ in T.markRead(id) },
      UIAction(title: "Group info", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.navigationController?.pushViewController(GroupInfoVC(group: id), animated: true) },
      UIMenu(options: .displayInline, children: [UIAction(title: "Leave group", image: UIImage(systemName: "rectangle.portrait.and.arrow.right"), attributes: .destructive) { [weak self] _ in GroupActions.leave(id, from: self) }]),
    ])
  }
  // up to 5: a 6th asks which one to unpin (Haris 2026-11-05)
  func pin(group id: String, _ on: Bool) { pinThing("pin", id, on, name: Talk.shared.groups[id]?.name ?? "") }
  func pin(client id: String, _ on: Bool) { pinThing("pinClient", id, on, name: Talk.shared.clients[id]?.name ?? "") }
  private func pinThing(_ act: String, _ id: String, _ on: Bool, name: String) {
    Net.shared.act(["act": act, "id": id, "on": on]) { [weak self] j in
      if (j?["full"] as? Bool) == true, let pins = j?["pins"] as? [String] {
        let a = UIAlertController(title: "Pinned is full", message: "Up to 5. Unpin one to pin “\(name)”. Your pins are yours — nobody else sees them.", preferredStyle: .actionSheet)
        for p in pins {
          let n = act == "pin" ? Talk.shared.groups[p]?.name : Talk.shared.clients[p]?.name
          a.addAction(UIAlertAction(title: "Unpin “\(n ?? "…")”", style: .default) { _ in
            Net.shared.act(["act": act, "id": p, "on": false]) { _ in Net.shared.act(["act": act, "id": id, "on": true]) { _ in Talk.shared.refresh() } }
          })
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self?.present(a, animated: true)
        return
      }
      Talk.shared.refresh()
    }
  }
}

// ---------- Groups: pins, then clients ----------
final class GroupsVC: ListVC {
  private var filter = 0   // All · Unread · @ Mentions
  private let pills = UISegmentedControl(items: ["All", "Unread", "@ Mentions"])
  private let empty = UILabel()
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Groups"
    navigationItem.largeTitleDisplayMode = .always
    search.searchBar.placeholder = "Search"
    pills.selectedSegmentIndex = 0
    pills.addAction(UIAction { [weak self] _ in guard let self = self else { return }; self.filter = self.pills.selectedSegmentIndex; UISelectionFeedbackGenerator().selectionChanged(); self.reload(animated: true) }, for: .valueChanged)
    let head = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 46))
    pills.frame = CGRect(x: 16, y: 6, width: min(300, view.bounds.width - 32), height: 32)
    head.addSubview(pills); table.tableHeaderView = head
    empty.numberOfLines = 0; empty.textAlignment = .center; empty.textColor = .secondaryLabel; empty.font = .systemFont(ofSize: 15)
    table.backgroundView = empty
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.newGroup() }, menu: nil)
    setMe()
    NotificationCenter.default.addObserver(self, selector: #selector(setMe), name: .talkChanged, object: nil)
  }
  @objc private func setMe() {
    navigationItem.rightBarButtonItem?.isHidden = !Talk.shared.canMake
    let a = Avatar(frame: CGRect(x: 0, y: 0, width: 32, height: 32)); a.set(person: Talk.shared.me)
    a.widthAnchor.constraint(equalToConstant: 32).isActive = true; a.heightAnchor.constraint(equalToConstant: 32).isActive = true
    a.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toSettings)))
    navigationItem.leftBarButtonItem = UIBarButtonItem(customView: a)
  }
  @objc private func toSettings() { tabBarController?.selectedIndex = 1 }
  private func newGroup() {
    let nav = UINavigationController(rootViewController: NewGroupVC(client: nil))
    present(nav, animated: true)
  }
  override func build() -> [(String, String, [Row])] {
    let T = Talk.shared
    let keep: (String) -> Bool = { [filter] id in filter == 0 || (filter == 1 && T.unread(id) > 0) || (filter == 2 && T.mentionsMe(id)) }
    if !query.isEmpty {
      // searching: the groups themselves (and clients by name)
      let gs = T.groups.values.filter { $0.name.lowercased().contains(query) || (T.clients[$0.client]?.name.lowercased().contains(query) ?? false) }.filter { keep($0.id) }
        .sorted { T.activity($0) > T.activity($1) }
      return [("found", gs.isEmpty ? "" : "Groups", gs.map { .group($0.id) })]
    }
    let pins = T.pinnedGroups.filter { T.groups[$0] != nil && keep($0) }
    if filter != 0 {
      let gs = T.groups.values.filter { keep($0.id) }.sorted { T.activity($0) > T.activity($1) }
      return [("found", "", gs.map { .group($0.id) })]
    }
    let pinnedC = T.pinnedClients.filter { T.myClients.contains($0) }
    let cs = pinnedC + T.myClients.filter { !pinnedC.contains($0) }
    return [("pins", "Pinned", pins.map { .group($0) }), ("clients", "Clients", cs.map { .client($0) })]
  }
  override func emptyNote() {
    let none = data.snapshot().numberOfItems == 0
    empty.isHidden = !none
    empty.text = !query.isEmpty ? "Nothing found" : filter == 1 ? "No unread messages" : filter == 2 ? "No mentions" : Talk.shared.canMake ? "No groups yet.\nTap + to make one under a client." : "No groups yet.\nYou’ll see a group here when you’re added to one."
  }
}

// ---------- a client: its groups ----------
final class ClientGroupsVC: ListVC {
  let client: String
  init(client: String) { self.client = client; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .always
    search.searchBar.placeholder = "Search \(Talk.shared.clients[client]?.name ?? "")’s groups"
    if Talk.shared.canMake {
      navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
        guard let self = self else { return }
        self.present(UINavigationController(rootViewController: NewGroupVC(client: self.client)), animated: true)
      }, menu: nil)
    }
  }
  override func reload(animated: Bool) {
    let T = Talk.shared
    let gs = T.groups(of: client), un = gs.filter { T.unread($0.id) > 0 }.count
    title = T.clients[client]?.name
    navigationItem.backButtonDisplayMode = .minimal
    // (under the name: "7 groups · 3 unread")
    let sub = "\(gs.count) group\(gs.count == 1 ? "" : "s")" + (un > 0 ? " · \(un) unread" : "")
    if table.tableHeaderView == nil {
      let v = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 28)), l = UILabel(frame: CGRect(x: 20, y: 2, width: view.bounds.width - 40, height: 20))
      l.font = .systemFont(ofSize: 14); l.textColor = .secondaryLabel; l.tag = 5; l.autoresizingMask = [.flexibleWidth]; v.addSubview(l); table.tableHeaderView = v
    }
    (table.tableHeaderView?.viewWithTag(5) as? UILabel)?.text = sub
    super.reload(animated: animated)
    // (the client gone, or no groups of it left for me: back to the list)
    if gs.isEmpty, view.window != nil, navigationController?.topViewController === self { navigationController?.popViewController(animated: true) }
  }
  override func build() -> [(String, String, [Row])] {
    let gs = Talk.shared.groups(of: client).filter { query.isEmpty || $0.name.lowercased().contains(query) }
    return [("groups", "", gs.map { .group($0.id) })]
  }
}

// ---------- what a group's menu does ----------
enum GroupActions {
  static func mute(_ id: String, _ secs: Double?) {
    let until: Any = secs == nil ? 0 : secs! < 0 ? "always" : (Date().timeIntervalSince1970 + secs!) * 1000
    Net.shared.act(["act": "mute", "group": id, "until": until]) { _ in Talk.shared.refresh() }
  }
  static func leave(_ id: String, from vc: UIViewController?) {
    let name = Talk.shared.groups[id]?.name ?? "this group"
    let a = UIAlertController(title: "Leave “\(name)”?", message: "You won’t get its messages any more. An admin can add you back.", preferredStyle: .actionSheet)
    a.addAction(UIAlertAction(title: "Leave group", style: .destructive) { _ in
      Net.shared.act(["act": "leave", "group": id]) { j in
        if (j?["ok"] as? Bool) == true { Talk.shared.refresh(); toast("You left “\(name)”") } else { toast(j?["error"] as? String ?? "Couldn’t leave — try again") }
      }
    })
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    vc?.present(a, animated: true)
  }
}
