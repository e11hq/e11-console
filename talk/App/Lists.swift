import UIKit

/* The lists (the approved mockups, design/e11-chat/e11talk-main-*.png — Haris 2026-11-05 "loveeee!!"):
   Groups — your pinned groups (up to 5) on top, then one row per client (its logo, its newest message, the total
   unread of its groups), newest activity first (Haris 2026-11-06: "like WhatsApp"); a client → its groups, newest
   first, each with its own unread count. Holding a group: Pin · Mute · Mark as read · Group info · Leave.
   Each row is kept by its id and only redrawn when what it shows changes (iPhone's diffable lists). */
enum Row: Hashable { case group(String), client(String), found(String, String), hit(String) }   // (found: a message — its group, its id)
// (hit: a client found by search — its own row, never the list's: a client's row from search handed back to the list kept
//  search's marked words after the search was closed, as Console's Home once did — Haris 2026-11-13)

final class ChatRowCell: UITableViewCell {
  static let id = "row"
  let avatar = Avatar()
  private let title = UILabel(), sub = UILabel(), time = UILabel(), badge = PaddedBadge(), icons = UIStackView(), chipL = PaddedLabel()
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    title.font = .systemFont(ofSize: 17, weight: .semibold)
    sub.font = .systemFont(ofSize: 15); sub.textColor = .secondaryLabel
    time.font = .systemFont(ofSize: 13); time.textAlignment = .right
    icons.axis = .horizontal; icons.spacing = 4; icons.alignment = .center
    chipL.font = .systemFont(ofSize: 11, weight: .semibold); chipL.textColor = .systemOrange; chipL.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.14)
    chipL.layer.cornerRadius = 7; chipL.layer.masksToBounds = true; chipL.isHidden = true
    [avatar, title, sub, time, badge, icons, chipL].forEach { contentView.addSubview($0) }
    separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = contentView.bounds.width, H = contentView.bounds.height
    avatar.frame = CGRect(x: 16, y: (H - 52) / 2, width: 52, height: 52)
    let tw = time.sizeThatFits(CGSize(width: 120, height: 20)).width
    time.frame = CGRect(x: W - 16 - tw, y: 13, width: tw, height: 18)
    let cw = chipL.isHidden ? 0 : chipL.sizeThatFits(CGSize(width: 140, height: 18)).width
    let tmax = W - 80 - tw - 24 - (cw > 0 ? cw + 6 : 0)
    let tfit = min(tmax, title.sizeThatFits(CGSize(width: tmax, height: 22)).width)
    title.frame = CGRect(x: 80, y: 11, width: chipL.isHidden ? W - 80 - tw - 24 : tfit, height: 22)
    if !chipL.isHidden { chipL.frame = CGRect(x: 80 + tfit + 6, y: 13, width: cw, height: 18) }
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
  func show(title t: String, sub s: String, time tm: String, unread: Int, pinned: Bool, muted: Bool, chip: String? = nil, typing: Bool = false) {
    title.text = t; time.text = tm
    // (someone typing: the last line becomes "Omar is typing…" in our blue, crossfading — the design's board 33)
    let ink: UIColor = typing ? Look.accent : .secondaryLabel
    // (crossfaded only when typing starts or stops on a row in view — a fade on every redraw left the line blank)
    let typingNow = sub.textColor == Look.accent
    if typing != typingNow && window != nil && sub.text != nil {
      UIView.transition(with: sub, duration: 0.2, options: [.transitionCrossDissolve, .beginFromCurrentState]) { self.sub.text = s; self.sub.textColor = ink }
    } else { sub.layer.removeAllAnimations(); sub.text = s; sub.textColor = ink }
    chipL.text = chip; chipL.isHidden = chip == nil
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
  var clientsTab = false                  // (the Clients tab: groups with a client contact in them)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    table.frame = view.bounds; table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    table.rowHeight = 72; table.delegate = self
    table.register(ChatRowCell.self, forCellReuseIdentifier: ChatRowCell.id)
    table.sectionHeaderTopPadding = 6
    view.addSubview(table)
    table.register(AgencyCell.self, forCellReuseIdentifier: AgencyCell.id)
    data = UITableViewDiffableDataSource<String, Row>(tableView: table) { [weak self] tv, ip, row in
      guard let self = self else { return UITableViewCell() }
      return self.cell(tv, ip, row)
    }
    data.defaultRowAnimation = .fade
    search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
    navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(typingChanged(_:)), name: .talkTyping, object: nil)
  }
  // (a search left open closes once the page is out of sight — a client opened from it, another tab: back here, the page
  //  is itself again, its search bar in its place under the title — Haris 2026-11-13)
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if search.isActive { UIView.performWithoutAnimation { search.searchBar.text = ""; search.isActive = false } }
  }
  // a row's cell: the group rows as before (a client's groups — step 2b); a client's row Apple's own cell (2a)
  func cell(_ tv: UITableView, _ ip: IndexPath, _ row: Row) -> UITableViewCell {
    if case .client(let id) = row {
      let c = tv.dequeueReusableCell(withIdentifier: AgencyCell.id, for: ip) as! AgencyCell
      c.show(clientRow(id)); return c
    }
    if case .hit(let id) = row {
      let c = tv.dequeueReusableCell(withIdentifier: AgencyCell.id, for: ip) as! AgencyCell
      c.show(clientRow(id)); return c
    }
    let c = tv.dequeueReusableCell(withIdentifier: ChatRowCell.id, for: ip) as! ChatRowCell
    fill(c, row); return c
  }
  // what a client's row shows (board 1): its logo, name, the newest "Group · Name: message", the time, unread, pinned
  var hits: [String: (String, Msg)] = [:]   // (searching: a client's message found, by client)
  func clientRow(_ id: String) -> AgencyCell.Model {
    let T = Talk.shared
    let gs = T.groups(of: id, withClient: clientsTab)
    var line = "\(gs.count) group\(gs.count == 1 ? "" : "s")"
    var blue = false
    func said(_ g: Group, _ m: Msg) -> String {
      let who = m.kind == "sys" ? "" : (m.by == T.me?.id ? "You" : String(T.name(m.by).split(separator: " ").first ?? "")) + ": "
      return "\(g.name) · \(who)\(Talk.preview(m))"
    }
    if let (gid, m) = hits[id], let g = T.groups[gid] { line = said(g, m) }
    else if let g = gs.first(where: { T.typingLine($0.id) != nil }), let t = T.typingLine(g.id) { line = "\(g.name) · \(t)"; blue = true }
    else if let g = gs.first, let m = T.last(g.id) { line = said(g, m) }
    let un = T.clientUnread(id, withClient: clientsTab)
    return AgencyCell.Model(id: id, client: T.clients[id], name: T.clients[id]?.name ?? "", line: line, typing: blue,
                            time: Look.time(T.clientActivity(id, withClient: clientsTab)), unread: un,
                            pinned: !clientsTab && T.pinnedClients.contains(id), find: query, twoLines: hits[id] != nil)
  }
  // (typing: only that group's row and its client's row drawn again)
  @objc func typingChanged(_ n: Notification) {
    guard let gid = n.object as? String else { return }
    let cid = Talk.shared.groups[gid]?.client
    var snap = data.snapshot()
    let rows = snap.itemIdentifiers.filter { r in
      switch r { case .group(let id): return id == gid; case .client(let id), .hit(let id): return id == cid; default: return false }
    }
    guard !rows.isEmpty else { return }
    snap.reconfigureItems(rows); data.applySteady(snap, in: table, animated: view.window != nil)
  }
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); reload(animated: false) }
  @objc func changed() { reload(animated: view.window != nil) }
  func updateSearchResults(for s: UISearchController) { reload(animated: false) }
  func build() -> [(String, String, [Row])] { [] }
  // (the redraw rule: a row is set again only when what it shows changed, crossfading in place; rows coming, going or
  //  moving to the top glide — Haris 2026-11-13)
  var sigs: [Row: Int] = [:]
  func sig(_ r: Row) -> Int {
    let T = Talk.shared; var h = Hasher()
    switch r {
    case .client(let id), .hit(let id): h.combine(clientRow(id).sig)
    case .group(let id):
      guard let g = T.groups[id] else { return 0 }
      h.combine(g.name); h.combine(g.pic); h.combine(g.muted); h.combine(g.withClient); h.combine(T.unread(id)); h.combine(T.activity(g))
      h.combine(T.last(id)?.id); h.combine(T.last(id)?.text); h.combine(T.typingLine(id)); h.combine(T.pinnedGroups.contains(id)); h.combine(T.pinnedClientGroups.contains(id))
      h.combine(T.clients[g.client]?.logo)
    case .found(let g, let m): h.combine(g); h.combine(m); h.combine(query)
    }
    return h.finalize()
  }
  func reload(animated: Bool) {
    var snap = NSDiffableDataSourceSnapshot<String, Row>()
    sections = [:]
    for (key, head, rows) in build() where !rows.isEmpty { snap.appendSections([key]); snap.appendItems(rows, toSection: key); sections[key] = head }
    let old = data.snapshot()
    var newSigs: [Row: Int] = [:]
    for r in snap.itemIdentifiers { newSigs[r] = sig(r) }
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != newSigs[$0] })
    sigs = newSigs
    data.applySteady(snap, in: table, animated: animated)
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
      let typing = T.typingLine(id)
      let line = typing ?? m.map { ($0.kind == "sys" ? "" : "\(T.name($0.by)): ") + Talk.preview($0) } ?? "No messages yet"
      let pinned = (g.withClient ? T.pinnedClientGroups : T.pinnedGroups).contains(id)
      c.show(title: g.name, sub: line, time: Look.time(T.activity(g)), unread: T.unread(id), pinned: pinned, muted: g.muted, chip: g.withClient && !T.isContact ? "With Client" : nil, typing: typing != nil)
    case .found(let gid, let mid):
      guard let g = T.groups[gid], let m = T.log(gid).msgs.first(where: { $0.id == mid }) else { return }
      c.avatar.set(group: g)
      c.show(title: g.name, sub: "\(T.name(m.by)): " + Talk.preview(m), time: Look.time(m.at), unread: 0, pinned: false, muted: false)
    case .client(let id), .hit(let id):
      guard let cl = T.clients[id] else { return }
      c.avatar.set(client: cl)
      let gs = T.groups(of: id, withClient: clientsTab)
      let newest = gs.first.flatMap { g in T.last(g.id).map { (g, $0) } }
      // (someone typing in one of its groups: that, on the client's line too)
      let typing = gs.lazy.compactMap { T.typingLine($0.id) }.first
      let line = typing ?? newest.map { (_, m) in (m.kind == "sys" ? "" : "\(T.name(m.by)): ") + Talk.preview(m) } ?? "\(gs.count) group\(gs.count == 1 ? "" : "s")"
      c.show(title: cl.name, sub: typing == nil && clientsTab && newest == nil ? "\(gs.count) group\(gs.count == 1 ? "" : "s") with the client" : line, time: Look.time(T.clientActivity(id, withClient: clientsTab)),
             unread: T.clientUnread(id, withClient: clientsTab), pinned: !clientsTab && T.pinnedClients.contains(id), muted: false, typing: typing != nil)
    }
  }
  func tableView(_ tv: UITableView, heightForHeaderInSection s: Int) -> CGFloat {
    let key = data.snapshot().sectionIdentifiers[s]; return (sections[key] ?? "").isEmpty ? 0 : 30
  }
  // (Apple's own plain header — PINNED, CLIENTS, as board 1: 13 semibold, spaced, grey)
  func tableView(_ tv: UITableView, viewForHeaderInSection s: Int) -> UIView? {
    let key = data.snapshot().sectionIdentifiers[s], head = sections[key] ?? ""
    guard !head.isEmpty else { return nil }
    let v = tv.dequeueReusableHeaderFooterView(withIdentifier: "head") ?? UITableViewHeaderFooterView(reuseIdentifier: "head")
    var c = UIListContentConfiguration.plainHeader()
    c.attributedText = NSAttributedString(string: head, attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .kern: 0.4, .foregroundColor: UIColor.secondaryLabel])
    c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 20, bottom: 4, trailing: 20)
    v.contentConfiguration = c
    var bg = UIBackgroundConfiguration.clear(); bg.backgroundColor = view.backgroundColor; v.backgroundConfiguration = bg
    return v
  }
  func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard let row = data.itemIdentifier(for: ip) else { return }
    switch row {
    case .group(let id): navigationController?.pushViewController(ChatVC(group: id), animated: true)
    case .client(let id), .hit(let id): navigationController?.pushViewController(ClientGroupsVC(client: id, clientsTab: clientsTab), animated: true)
    case .found(let gid, let mid): navigationController?.pushViewController(ChatVC(group: gid, focus: mid), animated: true)
    }
  }
  // holding a group (the design's board 27): Apple's lift with the chat itself as the preview — reading it there marks
  // nothing read — and Mark as Read · Pin · Mute · Group Info; a tap on the preview opens the chat. A client: Pin
  func tableView(_ tv: UITableView, contextMenuConfigurationForRowAt ip: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    guard let row = data.itemIdentifier(for: ip) else { return nil }
    var peek: UIContextMenuContentPreviewProvider?
    if case .group(let id) = row { peek = { let c = ChatVC(group: id); c.peek = true; return c } }
    let gid: String? = { if case .group(let id) = row { return id }; return nil }()
    return UIContextMenuConfiguration(identifier: gid as NSString?, previewProvider: peek) { [weak self] _ in
      guard let self = self else { return nil }
      switch row {
      case .group(let id), .found(let id, _): return self.groupMenu(id)
      case .client(let id), .hit(let id):
        let on = Talk.shared.pinnedClients.contains(id)
        return UIMenu(children: [UIAction(title: on ? "Unpin" : "Pin", image: UIImage(systemName: on ? "pin.slash" : "pin")) { _ in self.pin(client: id, !on) }])
      }
    }
  }
  func tableView(_ tv: UITableView, previewForHighlightingContextMenuWithConfiguration c: UIContextMenuConfiguration) -> UITargetedPreview? { nil }
  func tableView(_ tv: UITableView, willPerformPreviewActionForMenuWith c: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
    guard let id = c.identifier as? String else { return }
    animator.addCompletion { [weak self] in self?.navigationController?.pushViewController(ChatVC(group: id), animated: true) }
  }
  // swiping a group (the design's board 58): Delete, for its admins — asked first (board 59)
  func tableView(_ tv: UITableView, trailingSwipeActionsConfigurationForRowAt ip: IndexPath) -> UISwipeActionsConfiguration? {
    guard case .group(let id) = data.itemIdentifier(for: ip), let g = Talk.shared.groups[id], Talk.shared.canManage(g) else { return nil }
    let del = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
      GroupActions.askDelete(g, from: self); done(false)
    }
    del.image = UIImage(systemName: "trash")
    return UISwipeActionsConfiguration(actions: [del])
  }

  func groupMenu(_ id: String) -> UIMenu? {
    let T = Talk.shared
    guard let g = T.groups[id] else { return nil }
    let pinned = (g.withClient ? T.pinnedClientGroups : T.pinnedGroups).contains(id)
    let mute: UIMenuElement = g.muted
      ? UIAction(title: "Unmute", image: UIImage(systemName: "bell")) { _ in GroupActions.mute(id, nil) }
      : UIMenu(title: "Mute", image: UIImage(systemName: "bell.slash"), children: [
          UIAction(title: "8 Hours") { _ in GroupActions.mute(id, 8 * 3600) },
          UIAction(title: "1 Week") { _ in GroupActions.mute(id, 7 * 86400) },
          UIAction(title: "Always") { _ in GroupActions.mute(id, -1) }])
    // (board 27's order; Leave stays in Group Info)
    return UIMenu(children: [
      UIAction(title: "Mark as Read", image: UIImage(systemName: "envelope.open")) { _ in T.markRead(id) },
      UIAction(title: pinned ? "Unpin" : "Pin", image: UIImage(systemName: pinned ? "pin.slash" : "pin")) { [weak self] _ in self?.pin(group: id, !pinned) },
      mute,
      UIAction(title: "Group Info", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.navigationController?.pushViewController(GroupInfoVC(group: id), animated: true) },
    ])
  }
  // up to 5: a 6th asks which one to unpin (Haris 2026-11-05)
  func pin(group id: String, _ on: Bool) { pinThing("pin", id, on, name: Talk.shared.groups[id]?.name ?? "", tab: Talk.shared.groups[id]?.withClient == true ? "clients" : "groups") }
  func pin(client id: String, _ on: Bool) { pinThing("pinClient", id, on, name: Talk.shared.clients[id]?.name ?? "") }
  private func pinThing(_ act: String, _ id: String, _ on: Bool, name: String, tab: String = "groups") {
    Net.shared.act(["act": act, "id": id, "on": on, "tab": tab]) { [weak self] j in
      if (j?["full"] as? Bool) == true, let pins = j?["pins"] as? [String] {
        // (board 38's words)
        let a = UIAlertController(title: "Pinned is full", message: "Unpin one to pin \(name). Up to 5 pinned.", preferredStyle: .actionSheet)
        for p in pins {
          let n = act == "pin" ? Talk.shared.groups[p]?.name : Talk.shared.clients[p]?.name
          a.addAction(UIAlertAction(title: "Unpin \(n ?? "…")", style: .default) { _ in
            Net.shared.act(["act": act, "id": p, "on": false, "tab": tab]) { _ in Net.shared.act(["act": act, "id": id, "on": true, "tab": tab]) { _ in Talk.shared.refresh() } }
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

// ---------- E11 Agency (the first tab) and the Clients tab: pinned clients, then clients — the design's boards 1, 19, 56,
// L1 (step 2a, Haris 2026-11-13). A client contact: their groups straight away (board 14 — step 2d). ----------
final class GroupsVC: ListVC {
  private var filter = 0   // All · Unread · Mentions — clients with unread / with a mention (Haris 2026-11-13: A, clients)
  private let pillsRow = UIStackView()
  private var pills: [UIButton] = []
  // (the Clients tab: the same screen with the groups that have a client contact in them — Haris 2026-11-05)
  init(clientsTab: Bool = false) { super.init(nibName: nil, bundle: nil); self.clientsTab = clientsTab }
  required init?(coder: NSCoder) { fatalError() }
  static let pageBg = Look.dyn(0x0C0D0F, 0xFFFFFF)
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = GroupsVC.pageBg; table.backgroundColor = GroupsVC.pageBg
    table.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
    table.separatorColor = Look.dyn(0x2A2B2E, 0xDCDCE0)
    table.keyboardDismissMode = .interactive   // (the keyboard rule: the list scrolls while searching, a drag takes it down)
    title = clientsTab ? "Clients" : "E11 Agency"
    navigationItem.largeTitleDisplayMode = .always
    search.searchBar.placeholder = clientsTab ? "Search clients" : "Search clients"
    // (the search bar always under the big title, as Console's Home — Haris 2026-11-13; was hidden until pulled down)
    search.delegate = self
    // All · Unread · Mentions — Apple's own buttons set to the board's look (ours, said plainly: there's no Apple part for
    // this row; Haris 2026-11-13: B, as Console's Inbox)
    for (i, t) in ["All", "Unread", "Mentions"].enumerated() {
      let b = UIButton(type: .system); b.tag = i
      b.addAction(UIAction { [weak self] _ in self?.pick(i) }, for: .touchUpInside)
      b.heightAnchor.constraint(equalToConstant: 32).isActive = true
      pills.append(b); pillsRow.addArrangedSubview(b)
      b.accessibilityLabel = t
    }
    pillsRow.axis = .horizontal; pillsRow.spacing = 8; pillsRow.alignment = .center
    let head = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 46))
    pillsRow.frame = CGRect(x: 16, y: 4, width: view.bounds.width - 32, height: 32); pillsRow.distribution = .fill
    let spacer = UIView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal); pillsRow.addArrangedSubview(spacer)
    head.addSubview(pillsRow); table.tableHeaderView = head
    paintPills(animated: false)
    setMe()
    NotificationCenter.default.addObserver(self, selector: #selector(setMe), name: .talkChanged, object: nil)
  }
  // a pill: Apple's filled capsule button — the chosen one in the page's ink, the others on a faint fill (board 1, L1)
  private func paintPills(animated: Bool) {
    let T = Talk.shared
    let un = T.myClients(withClient: clientsTab).reduce(0) { $0 + T.clientUnread($1, withClient: clientsTab) }
    let titles = ["All", un > 0 ? "Unread \(un)" : "Unread", "Mentions"]
    let change = {
      for (i, b) in self.pills.enumerated() {
        var c = UIButton.Configuration.filled(); c.cornerStyle = .capsule
        c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        let on = i == self.filter
        c.baseBackgroundColor = on ? Look.dyn(0xF5F5F7, 0x000000) : Look.dyn(0x262628, 0xE3E3E8)
        c.baseForegroundColor = on ? Look.dyn(0x000000, 0xFFFFFF) : .label
        c.attributedTitle = AttributedString(titles[i], attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: on ? .semibold : .regular)]))
        b.configuration = c
      }
    }
    if animated, view.window != nil { UIView.transition(with: pillsRow, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction], animations: change) } else { change() }
  }
  private var pillsSig = ""
  private func pick(_ i: Int) {
    guard i != filter else { return }
    filter = i; UISelectionFeedbackGenerator().selectionChanged()
    paintPills(animated: true); reload(animated: true)
  }
  @objc private func setMe() {
    let T = Talk.shared
    // (a client contact: a plain list of their groups — no filters; their page is step 2d)
    title = T.isContact ? "Chats" : clientsTab ? "Clients" : "E11 Agency"
    table.tableHeaderView?.isHidden = T.isContact
    if T.isContact, table.tableHeaderView?.frame.height != 0 { table.tableHeaderView?.frame.size.height = 0; table.tableHeaderView = table.tableHeaderView }
    // + only on the Clients tab (E11 Agency's groups are made from a client's page — board 25)
    if clientsTab, T.canMake, T.boss, !T.isContact {
      if navigationItem.leftBarButtonItem == nil { navigationItem.leftBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.newGroup() }, menu: nil) }
    } else { navigationItem.leftBarButtonItem = nil }
    // your E11 Console photo, top right in Apple's glass button (board 1) — made once, set again only when it changes
    if navigationItem.rightBarButtonItem == nil {
      meFace.translatesAutoresizingMaskIntoConstraints = false
      meFace.widthAnchor.constraint(equalToConstant: 38).isActive = true; meFace.heightAnchor.constraint(equalToConstant: 38).isActive = true
      meFace.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toSettings)))
      meFace.accessibilityLabel = "You — Settings"; meFace.isAccessibilityElement = true
      navigationItem.rightBarButtonItem = UIBarButtonItem(customView: meFace)
    }
    let key = [T.me?.id, T.me?.name, T.me?.color, T.me?.picture].map { $0 ?? "" }.joined(separator: "|")
    if key != meKey { meKey = key; meFace.set(person: T.me) }
    let ps = [T.myClients(withClient: clientsTab).reduce(0) { $0 + T.clientUnread($1, withClient: clientsTab) }].map(String.init).joined()
    if ps != pillsSig { pillsSig = ps; paintPills(animated: true) }
  }
  private let meFace = Avatar(frame: CGRect(x: 0, y: 0, width: 38, height: 38))
  private var meKey = ""
  @objc private func toSettings() {
    if Talk.shared.isContact { navigationController?.pushViewController(SettingsVC(), animated: true); return }
    tabBarController?.selectedIndex = (tabBarController?.viewControllers?.count ?? 2) - 1
  }
  private func newGroup() {
    let nav = UINavigationController(rootViewController: NewGroupVC(client: nil, forClient: clientsTab))
    present(nav, animated: true)
  }
  // the line under the title: "8 clients · 5 unread" (board 1), crossfading when it changes
  private func setLine() {
    let T = Talk.shared
    guard !T.isContact else { return }
    let cs = T.myClients(withClient: clientsTab), un = cs.reduce(0) { $0 + T.clientUnread($1, withClient: clientsTab) }
    let line = "\(cs.count) client\(cs.count == 1 ? "" : "s")" + (un > 0 ? " · \(un) unread" : "")
    if #available(iOS 26.0, *), navigationItem.subtitle != line {
      if view.window != nil, let bar = navigationController?.navigationBar { UIView.transition(with: bar, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction], animations: nil) }
      navigationItem.subtitle = line
    }
  }
  override func reload(animated: Bool) {
    super.reload(animated: animated)
    setLine()
  }
  // searching: the filters go, their room with them, so the results start right under the search bar (board 19; as
  // Console's My Tasks All / Done — Haris 2026-11-13) — faded and closed alongside Apple's own search transition, back
  // the same way when it closes
  private func pillsShown(_ on: Bool, _ s: UISearchController) {
    guard let h = table.tableHeaderView, !Talk.shared.isContact else { return }
    h.isUserInteractionEnabled = on; h.clipsToBounds = true
    let change = { [weak self] in
      guard let self = self else { return }
      h.alpha = on ? 1 : 0; h.frame.size.height = on ? 46 : 0; self.table.tableHeaderView = h; self.table.layoutIfNeeded()
    }
    if let tc = s.transitionCoordinator ?? transitionCoordinator { tc.animate(alongsideTransition: { _ in change() }) }
    else { UIView.animate(withDuration: Crossfade.time, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: change) }
  }
  override func build() -> [(String, String, [Row])] {
    let T = Talk.shared
    hits = [:]
    // a client contact: their groups, newest first (step 2d)
    if T.isContact {
      let gs = T.groups.values.filter { query.isEmpty || $0.name.lowercased().contains(query) }.sorted { T.activity($0) > T.activity($1) }
      return [("found", "", gs.map { .group($0.id) })]
    }
    let mine = T.myClients(withClient: clientsTab)
    if !query.isEmpty {
      // searching (board 19): the clients, by name or by a message in their groups — the words found marked
      for (gid, m) in T.search(query) {
        guard let g = T.groups[gid], g.withClient == clientsTab, hits[g.client] == nil else { continue }
        hits[g.client] = (gid, m)
      }
      let found = mine.filter { (T.clients[$0]?.name.lowercased().contains(query) ?? false) || hits[$0] != nil }
      return [("found", "", found.map { .hit($0) })]
    }
    // (A: the filters keep this tab a list of clients — the ones with unread, or with a mention of you)
    let keep: (String) -> Bool = { [filter, clientsTab] c in
      filter == 0 || (filter == 1 && T.clientUnread(c, withClient: clientsTab) > 0) || (filter == 2 && T.groups(of: c, withClient: clientsTab).contains { T.mentionsMe($0.id) })
    }
    let pinnedC = clientsTab ? [] : T.pinnedClients.filter { mine.contains($0) && keep($0) }
    let rest = mine.filter { !pinnedC.contains($0) && keep($0) }
    return [("pins", "PINNED", pinnedC.map { .client($0) }), ("clients", pinnedC.isEmpty ? "" : "CLIENTS", rest.map { .client($0) })]
  }
  // nothing to show: Apple's own empty view (board 56) — and Apple's "No Results" for a search; faded in and out
  override func emptyNote() {
    let none = data.snapshot().numberOfItems == 0
    let T = Talk.shared
    if #available(iOS 17.0, *) {
      var e: UIContentUnavailableConfiguration
      if !query.isEmpty { e = .search() }
      else {
        e = .empty()
        e.image = UIImage(systemName: filter == 2 ? "at" : "bubble.left.and.bubble.right")
        (e.text, e.secondaryText) = filter == 1 ? ("No Unread Messages", "Clients with something new show here.")
          : filter == 2 ? ("No Mentions", "Clients where someone @mentions you show here.")
          : T.isContact ? ("No Chats Yet", "You’ll see one here when E11 adds you to it.")
          : clientsTab ? ("No Client Groups Yet", "Groups with a client contact in them show here.")
          : ("No Groups Yet", "When someone adds you to a group, its client shows here.")
      }
      let v = (table.backgroundView as? UIContentUnavailableView) ?? { let v = UIContentUnavailableView(configuration: e); v.alpha = 0; table.backgroundView = v; return v }()
      v.configuration = e
      let a: CGFloat = none ? 1 : 0
      if v.alpha != a { UIView.animate(withDuration: Crossfade.time) { v.alpha = a } }
    } else {
      let l = (table.backgroundView as? UILabel) ?? { let l = UILabel(); l.textAlignment = .center; l.textColor = .secondaryLabel; l.numberOfLines = 0; l.alpha = 0; table.backgroundView = l; return l }()
      l.text = !query.isEmpty ? "No Results" : filter == 1 ? "No Unread Messages" : filter == 2 ? "No Mentions" : "No Groups Yet"
      let a: CGFloat = none ? 1 : 0
      if l.alpha != a { UIView.animate(withDuration: Crossfade.time) { l.alpha = a } }
    }
  }
}
extension GroupsVC: UISearchControllerDelegate {
  func willPresentSearchController(_ s: UISearchController) { pillsShown(false, s) }
  func willDismissSearchController(_ s: UISearchController) { pillsShown(true, s) }
}

// A client's row on E11 Agency (board 1): Apple's own list cell — the logo (a rounded square), the name, the newest
// "Group · Name: message" — with ours inside it, said plainly: the time on the first line, the unread count and the pin or ›
final class AgencyCell: UITableViewCell {
  static let id = "agency"
  struct Model {
    let id: String, client: Client?, name: String, line: String, typing: Bool, time: String, unread: Int, pinned: Bool, find: String, twoLines: Bool
    var sig: Int { var h = Hasher(); [id, name, line, time, find, client?.logo ?? "", client?.color ?? ""].forEach { h.combine($0) }; h.combine(typing); h.combine(unread); h.combine(pinned); h.combine(twoLines); return h.finalize() }
  }
  private let logo = Avatar(frame: CGRect(x: 0, y: 0, width: 52, height: 52)), time = UILabel(), badge = PaddedBadge(), mark = UIImageView()
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    logo.square = true; logo.isUserInteractionEnabled = false
    time.font = .systemFont(ofSize: 14); time.textAlignment = .right
    badge.font = .systemFont(ofSize: 13, weight: .bold); badge.layer.cornerRadius = 11
    mark.contentMode = .center
    insetsLayoutMarginsFromSafeArea = false; contentView.insetsLayoutMarginsFromSafeArea = false   // (steady heights — the rule)
    contentConfiguration = UIListContentConfiguration.subtitleCell()   // (Apple's content view first, ours into it)
    [logo, time, badge, mark].forEach { contentView.addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateConfiguration(using state: UICellConfigurationState) {
    var bg = UIBackgroundConfiguration.listPlainCell().updated(for: state)
    if !state.isHighlighted && !state.isSelected { bg.backgroundColor = .clear }
    backgroundConfiguration = bg
  }
  // the words found: dark as the board (its brown, white words); light — the board draws none — a soft yellow behind the
  // row's own ink, as iPhone marks words found (the brown was too strong on white — Haris 2026-11-13)
  static let findBg = UIColor { $0.userInterfaceStyle == .dark ? Look.rgb(0x7A5626) : UIColor.systemYellow.withAlphaComponent(0.32) }
  static let findInk = UIColor { $0.userInterfaceStyle == .dark ? .white : .label }
  private static func marked(_ t: String, _ q: String, font: UIFont, ink: UIColor) -> NSAttributedString {
    let a = NSMutableAttributedString(string: t, attributes: [.font: font, .foregroundColor: ink])
    guard !q.isEmpty else { return a }
    var from = t.startIndex
    while let r = t.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: from..<t.endIndex) {
      a.addAttributes([.backgroundColor: AgencyCell.findBg, .foregroundColor: AgencyCell.findInk], range: NSRange(r, in: t)); from = r.upperBound
    }
    return a
  }
  private var rightW: CGFloat = 0
  func show(_ m: Model) {
    time.text = m.time; time.textColor = m.unread > 0 ? Look.dyn(0x5AA9FF, 0x2F7BFF) : .secondaryLabel
    badge.isHidden = m.unread == 0; badge.text = m.unread > 99 ? "99+" : "\(m.unread)"; badge.backgroundColor = Look.dyn(0x2F7BFF, 0x2F7BFF)
    mark.image = UIImage(systemName: m.pinned ? "pin.fill" : "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: m.pinned ? 12 : 13, weight: .semibold))
    mark.tintColor = m.pinned ? .secondaryLabel : .tertiaryLabel
    let tw = ceil(time.sizeThatFits(CGSize(width: 140, height: 20)).width)
    let bw = badge.isHidden ? 0 : max(22, ceil(badge.sizeThatFits(.zero).width) + 2)
    rightW = max(tw, bw + (bw > 0 ? 8 : 0) + 14)
    var cfg = UIListContentConfiguration.subtitleCell()
    cfg.attributedText = AgencyCell.marked(m.name, m.find, font: .systemFont(ofSize: 17, weight: .semibold), ink: .label)
    cfg.secondaryAttributedText = AgencyCell.marked(m.line, m.find, font: .systemFont(ofSize: 15), ink: m.typing ? Look.accent : .secondaryLabel)
    cfg.textProperties.numberOfLines = 1; cfg.secondaryTextProperties.numberOfLines = m.twoLines ? 2 : 1
    cfg.textToSecondaryTextVerticalPadding = 3
    cfg.image = UIImage(systemName: "square.fill"); cfg.imageProperties.tintColor = .clear
    cfg.imageProperties.reservedLayoutSize = CGSize(width: 52, height: 52); cfg.imageProperties.maximumSize = CGSize(width: 52, height: 52)
    cfg.imageToTextPadding = 12
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16 + rightW + 8)
    contentConfiguration = cfg
    [logo, time, badge, mark].forEach { contentView.bringSubviewToFront($0) }
    if let c = m.client { logo.set(client: c) } else { logo.set(name: m.name, color: Look.color(for: m.id), picture: nil) }
    accessibilityLabel = [m.name, m.line, m.time, m.unread > 0 ? "\(m.unread) unread" : nil, m.pinned ? "Pinned" : nil].compactMap { $0 }.joined(separator: ", ")
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = contentView.bounds.width, H = contentView.bounds.height
    logo.frame = CGRect(x: 16, y: (H - 52) / 2, width: 52, height: 52)
    let tw = ceil(time.sizeThatFits(CGSize(width: 140, height: 20)).width)
    time.frame = CGRect(x: W - 16 - tw, y: H / 2 - 22, width: tw, height: 18)
    var x = W - 16
    mark.frame = CGRect(x: x - 14, y: H / 2 + 2, width: 14, height: 20); x -= 14 + 8
    if !badge.isHidden { let bw = max(22, ceil(badge.sizeThatFits(.zero).width) + 2); badge.frame = CGRect(x: x - bw, y: H / 2 + 1, width: bw, height: 22) }
  }
}

// ---------- a client: its groups ----------
final class ClientGroupsVC: ListVC {
  let client: String
  init(client: String, clientsTab: Bool = false) { self.client = client; super.init(nibName: nil, bundle: nil); self.clientsTab = clientsTab }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .always
    search.searchBar.placeholder = "Search \(Talk.shared.clients[client]?.name ?? "")’s groups"
    if Talk.shared.canMake && (!clientsTab || Talk.shared.boss) {
      navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
        guard let self = self else { return }
        self.present(UINavigationController(rootViewController: NewGroupVC(client: self.client, forClient: self.clientsTab)), animated: true)
      }, menu: nil)
    }
  }
  override func reload(animated: Bool) {
    let T = Talk.shared
    let gs = T.groups(of: client, withClient: clientsTab), un = gs.filter { T.unread($0.id) > 0 }.count
    title = T.clients[client]?.name
    navigationItem.backButtonDisplayMode = .minimal
    // (under the name: "7 groups · 3 unread" — Apple's subtitle under the big title, as board 2 and E11 Agency's: the same
    //  bar on both pages, so the big title no longer jumps as a swipe back starts — Haris 2026-11-13)
    let sub = "\(gs.count) group\(gs.count == 1 ? "" : "s")" + (un > 0 ? " · \(un) unread" : "")
    if #available(iOS 26.0, *) {
      if navigationItem.subtitle != sub {
        if view.window != nil, let bar = navigationController?.navigationBar { UIView.transition(with: bar, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction], animations: nil) }
        navigationItem.subtitle = sub
      }
    } else if table.tableHeaderView == nil {
      let v = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 28)), l = UILabel(frame: CGRect(x: 20, y: 2, width: view.bounds.width - 40, height: 20))
      l.font = .systemFont(ofSize: 14); l.textColor = .secondaryLabel; l.tag = 5; l.autoresizingMask = [.flexibleWidth]; v.addSubview(l); table.tableHeaderView = v
    }
    if #unavailable(iOS 26.0) { (table.tableHeaderView?.viewWithTag(5) as? UILabel)?.text = sub }
    super.reload(animated: animated)
    // (the client gone, or no groups of it left for me: back to the list)
    if gs.isEmpty, view.window != nil, navigationController?.topViewController === self { navigationController?.popViewController(animated: true) }
  }
  override func build() -> [(String, String, [Row])] {
    let gs = Talk.shared.groups(of: client, withClient: clientsTab).filter { query.isEmpty || $0.name.lowercased().contains(query) }
    return [("groups", "", gs.map { .group($0.id) })]
  }
}

// ---------- what a group's menu does ----------
enum GroupActions {
  static func mute(_ id: String, _ secs: Double?) {
    let until: Any = secs == nil ? 0 : secs! < 0 ? "always" : (Date().timeIntervalSince1970 + secs!) * 1000
    Net.shared.act(["act": "mute", "group": id, "until": until]) { _ in Talk.shared.refresh() }
  }
  // deleting a group (board 59): asked first, then gone for everyone
  static func askDelete(_ g: Group, from vc: UIViewController?) {
    let a = UIAlertController(title: "Delete “\(g.name)”?", message: "The group and its messages go for everyone in it. This can’t be undone.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    a.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
      Net.shared.act(["act": "deleteGroup", "group": g.id]) { j in
        if (j?["ok"] as? Bool) == true { toast("Group deleted"); Talk.shared.refresh(); Talk.shared.sync() } else { toast(j?["error"] as? String ?? "Couldn’t do that — try again") }
      }
    })
    vc?.present(a, animated: true)
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
