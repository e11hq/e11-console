import UIKit

/* The lists (the approved mockups, design/e11-chat/e11talk-main-*.png — Haris 2026-11-05 "loveeee!!"):
   Groups — your pinned groups (up to 5) on top, then one row per client (its logo, its newest message, the total
   unread of its groups), newest activity first (Haris 2026-11-06: "like WhatsApp"); a client → its groups, newest
   first, each with its own unread count. Holding a group: Pin · Mute · Mark as read · Group info · Leave.
   Each row is kept by its id and only redrawn when what it shows changes (iPhone's diffable lists). */
enum Row: Hashable { case group(String), client(String), found(String, String), hit(String), ghit(String) }   // (found: a message — its group, its id)
// (hit: a client found by search — its own row, never the list's: a client's row from search handed back to the list kept
//  search's marked words after the search was closed, as Console's Home once did — Haris 2026-11-13; ghit: a group found
//  on a client's page, the same way — 2b)

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

class ListVC: UIViewController, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate {
  let table = UITableView(frame: .zero, style: .plain)
  var data: UITableViewDiffableDataSource<String, Row>!
  let search = UISearchController(searchResultsController: nil)
  var query: String { (search.searchBar.text ?? "").trimmingCharacters(in: .whitespaces).lowercased() }
  var sections: [String: String] = [:]   // section key → its heading
  var clientsTab = false                  // (the Clients tab: groups with a client contact in them)
  // All · Unread · Mentions (boards 1 and 2) — shared by E11 Agency and a client's page: the same buttons, the same ways
  var filter = 0
  let pillsRow = UIStackView()
  var pills: [UIButton] = []
  private var headH: CGFloat = 46
  func pillsUnread() -> Int { 0 }   // ("Unread 3" — each page says how many)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    table.frame = view.bounds; table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    table.rowHeight = 72; table.delegate = self
    table.register(ChatRowCell.self, forCellReuseIdentifier: ChatRowCell.id)
    table.sectionHeaderTopPadding = 6
    view.addSubview(table)
    table.register(AgencyCell.self, forCellReuseIdentifier: AgencyCell.id)
    table.register(GroupCell.self, forCellReuseIdentifier: GroupCell.id)
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
  // the head of the list: what's above the filters (a client's logo — board 2), then All · Unread · Mentions — Apple's own
  // buttons set to the board's look (ours, said plainly: there's no Apple part for this row; Haris 2026-11-13: B, as
  // Console's Inbox)
  func makePills(above top: UIView? = nil) {
    for (i, t) in ["All", "Unread", "Mentions"].enumerated() {
      let b = UIButton(type: .system); b.tag = i
      b.addAction(UIAction { [weak self] _ in self?.pick(i) }, for: .touchUpInside)
      b.heightAnchor.constraint(equalToConstant: 32).isActive = true
      pills.append(b); pillsRow.addArrangedSubview(b)
      b.accessibilityLabel = t
    }
    pillsRow.axis = .horizontal; pillsRow.spacing = 8; pillsRow.alignment = .center
    let topH = top?.frame.height ?? 0
    headH = topH + 46
    let head = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: headH))
    if let top = top { top.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: topH); top.autoresizingMask = [.flexibleWidth]; head.addSubview(top) }
    pillsRow.frame = CGRect(x: 16, y: topH + 4, width: view.bounds.width - 32, height: 32); pillsRow.distribution = .fill
    let spacer = UIView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal); pillsRow.addArrangedSubview(spacer)
    head.addSubview(pillsRow); table.tableHeaderView = head
    paintPills(animated: false)
  }
  // a pill: Apple's filled capsule button — the chosen one in the page's ink, the others on a faint fill (board 1, L1)
  func paintPills(animated: Bool) {
    let un = pillsUnread()
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
  private var pillsSig = -1
  // ("Unread 3" brought up to date — crossfading, only when the number changed)
  func repaintPillsIfNeeded() { let n = pillsUnread(); if n != pillsSig { let first = pillsSig < 0; pillsSig = n; paintPills(animated: !first) } }
  private func pick(_ i: Int) {
    guard i != filter else { return }
    filter = i; UISelectionFeedbackGenerator().selectionChanged()
    paintPills(animated: true); reload(animated: true)
  }
  // searching: the head goes, its room with it, so the results start right under the search bar (boards 19, 2; as
  // Console's My Tasks All / Done — Haris 2026-11-13) — faded and closed alongside Apple's own search transition, back
  // the same way when it closes
  func pillsShown(_ on: Bool, _ s: UISearchController) {
    guard let h = table.tableHeaderView, !Talk.shared.isContact, !pills.isEmpty else { return }
    h.isUserInteractionEnabled = on; h.clipsToBounds = true
    let full = headH
    let change = { [weak self] in
      guard let self = self else { return }
      h.alpha = on ? 1 : 0; h.frame.size.height = on ? full : 0; self.table.tableHeaderView = h; self.table.layoutIfNeeded()
    }
    if let tc = s.transitionCoordinator ?? transitionCoordinator { tc.animate(alongsideTransition: { _ in change() }) }
    else { UIView.animate(withDuration: Crossfade.time, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: change) }
  }
  func willPresentSearchController(_ s: UISearchController) { pillsShown(false, s) }
  func willDismissSearchController(_ s: UISearchController) { pillsShown(true, s) }
  // (the page out of sight — another page opened, another tab — a search left open closes — Haris 2026-11-13)
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    UIView.performWithoutAnimation { if search.isActive { search.searchBar.text = ""; search.isActive = false } }
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
    // (a page drawing its groups as Apple's own cells — a client's page, a client contact's — 2b, 2d)
    switch row {
    case .group(let id), .ghit(let id):
      if let m = groupModel(id) {
        let c = tv.dequeueReusableCell(withIdentifier: GroupCell.id, for: ip) as! GroupCell
        UIView.performWithoutAnimation { c.show(m); c.layoutIfNeeded() }
        return c
      }
    default: break
    }
    let c = tv.dequeueReusableCell(withIdentifier: ChatRowCell.id, for: ip) as! ChatRowCell
    fill(c, row); return c
  }
  // what a client's row shows (board 1): its logo, name, the newest "Group · Name: message", the time, unread, pinned
  var hits: [String: (String, Msg)] = [:]   // (searching: a client's message found, by client)
  var hitsG: [String: Msg] = [:]            // (searching a client's page: a group's message found, by group)
  func groupModel(_ id: String) -> GroupCell.Model? { nil }   // (a page drawing its groups as GroupCell — 2b)
  func groupRow(_ id: String) -> GroupCell.Model { groupModel(id) ?? GroupCell.Model.blank(id) }
  // what a group's row shows (board 2): its picture, name, the newest message (two lines), the time, ✓✓ on yours, unread,
  // muted, pinned — "With Client" on the Clients tab (board 20)
  func makeGroupModel(_ id: String) -> GroupCell.Model? {
    let T = Talk.shared
    guard let g = T.groups[id] else { return nil }
    let l = T.log(id), me = T.me?.id
    let hit = query.isEmpty ? nil : hitsG[id]
    let m = hit ?? l.msgs.last
    let typing = hit == nil ? T.typingLine(id) : nil
    var line = "No messages yet", ticks = 0
    if let t = typing { line = t }
    else if let m = m {
      if m.kind == "sys" || m.by == me { line = Talk.preview(m) }
      else {
        let p = T.people[m.by], first = String(T.name(m.by).split(separator: " ").first ?? "")
        let who = p?.contact == true ? "\(first) (\(p?.client.flatMap { T.clients[$0]?.name } ?? "Client"))" : first
        line = "\(who): " + Talk.preview(m)
      }
      if m.by == me, m.kind != "sys", !m.deleted, hit == nil {
        let others = g.members.filter { $0 != me }
        let idx = l.msgs.firstIndex { $0.id == m.id } ?? 0
        let seen = !T.isContact && !others.isEmpty && others.allSatisfy { p in l.readBy[p].flatMap { r in l.msgs.firstIndex { $0.id == r } }.map { $0 >= idx } ?? false }
        let got = !others.isEmpty && others.allSatisfy { p in l.read(p, m.id) || l.time(l.gotAt, p, m.id) != nil }
        ticks = m.pending ? 0 : seen ? 3 : got ? 2 : 1
      }
    }
    let pinned = (g.withClient ? T.pinnedClientGroups : T.pinnedGroups).contains(id)
    return GroupCell.Model(id: id, group: g, name: g.name, line: line, typing: typing != nil, ticks: ticks,
                           time: Look.time(hit?.at ?? T.activity(g)), unread: T.unread(id), pinned: pinned, muted: g.muted,
                           chip: clientsTab && g.withClient && !T.isContact, find: hit != nil || g.name.lowercased().contains(query) ? query : "")
  }

  func clientRow(_ id: String) -> AgencyCell.Model {
    let T = Talk.shared
    let gs = T.groups(of: id, withClient: clientsTab)
    var line = "\(gs.count) group\(gs.count == 1 ? "" : "s")"
    var blue = false
    func said(_ g: Group, _ m: Msg) -> String {
      // (a client contact's words: "Rania (Client)" — board 19)
      let first = String(T.name(m.by).split(separator: " ").first ?? "")
      let who = m.kind == "sys" ? "" : (m.by == T.me?.id ? "You" : T.people[m.by]?.contact == true ? "\(first) (Client)" : first) + ": "
      return "\(g.name) · \(who)\(Talk.preview(m))"
    }
    if let (gid, m) = hits[id], let g = T.groups[gid] { line = said(g, m) }
    else if let g = gs.first(where: { T.typingLine($0.id) != nil }), let t = T.typingLine(g.id) { line = "\(g.name) · \(t)"; blue = true }
    else if let g = gs.first, let m = T.last(g.id) { line = said(g, m) }
    let un = T.clientUnread(id, withClient: clientsTab)
    return AgencyCell.Model(id: id, client: T.clients[id], name: T.clients[id]?.name ?? "", line: line, typing: blue,
                            time: Look.time(T.clientActivity(id, withClient: clientsTab)), unread: un,
                            pinned: T.pinnedClients.contains(id), find: query, twoLines: hits[id] != nil)
  }
  // (typing: only that group's row and its client's row drawn again)
  @objc func typingChanged(_ n: Notification) {
    guard let gid = n.object as? String else { return }
    let cid = Talk.shared.groups[gid]?.client
    var snap = data.snapshot()
    let rows = snap.itemIdentifiers.filter { r in
      switch r { case .group(let id), .ghit(let id): return id == gid; case .client(let id), .hit(let id): return id == cid; default: return false }
    }
    guard !rows.isEmpty else { return }
    snap.reconfigureItems(rows); data.applySteady(snap, in: table, animated: view.window != nil)
  }
  // (coming back to the page: what changed while away set, but the list not laid out here — laid out before Apple's bar
  //  had put its big title back, it kept the small bar's room and the title stayed small: the check's note, Clients,
  //  "page coming back", room 116 of 189 — Haris 2026-11-13. Apple lays it out with its bar, as the page shows.)
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); appearing = true; reload(animated: false); appearing = false }
  private var appearing = false
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
    case .ghit(let id): h.combine(groupRow(id).sig)
    case .group(let id):
      if let m = groupModel(id) { return m.sig }
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
    data.applySteady(snap, in: table, animated: animated, layout: !appearing)
    emptyNote()
  }
  func emptyNote() {}
  func fill(_ c: ChatRowCell, _ row: Row) {
    let T = Talk.shared
    switch row {
    case .group(let id), .ghit(let id):
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
  // (a group drawn as Apple's own cell takes its own height — two lines of its message; the rest keep the list's)
  func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat {
    switch data.itemIdentifier(for: ip) {
    case .group(let id)?, .ghit(let id)?: return groupModel(id) != nil ? UITableView.automaticDimension : tv.rowHeight
    default: return tv.rowHeight
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
    case .ghit(let id): navigationController?.pushViewController(ChatVC(group: id, focus: hitsG[id]?.id), animated: true)
    case .client(let id), .hit(let id): navigationController?.pushViewController(ClientGroupsVC(client: id, clientsTab: clientsTab), animated: true)
    case .found(let gid, let mid): navigationController?.pushViewController(ChatVC(group: gid, focus: mid), animated: true)
    }
  }
  // holding a group (the design's board 27): Apple's lift with the chat itself as the preview — reading it there marks
  // nothing read — and Mark as Read · Pin · Mute · Group Info; a tap on the preview opens the chat. A client: Pin
  func tableView(_ tv: UITableView, contextMenuConfigurationForRowAt ip: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    guard let row = data.itemIdentifier(for: ip) else { return nil }
    var peek: UIContextMenuContentPreviewProvider?
    let gid: String? = { switch row { case .group(let id), .ghit(let id): return id; default: return nil } }()
    if let id = gid { peek = { let c = ChatVC(group: id); c.peek = true; return c } }
    return UIContextMenuConfiguration(identifier: gid as NSString?, previewProvider: peek) { [weak self] _ in
      guard let self = self else { return nil }
      switch row {
      case .group(let id), .ghit(let id), .found(let id, _): return self.groupMenu(id)
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
    let gid: String? = { switch data.itemIdentifier(for: ip) { case .group(let id)?, .ghit(let id)?: return id; default: return nil } }()
    guard let id = gid, let g = Talk.shared.groups[id], Talk.shared.canManage(g) else { return nil }
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
  // (All · Unread · Mentions — clients with unread / with a mention: Haris 2026-11-13, A, clients)
  // (the Clients tab: the same screen with the groups that have a client contact in them — Haris 2026-11-05)
  init(clientsTab: Bool = false) { super.init(nibName: nil, bundle: nil); self.clientsTab = clientsTab }
  required init?(coder: NSCoder) { fatalError() }
  static let pageBg = Look.dyn(0x0C0D0F, 0xFFFFFF)
  // ---------- a TEMPORARY check (Haris 2026-11-13: "1") — what makes the big title small while the list is at its top.
  // Nothing on the page changes: each moment it goes small at the top is noted with what was happening, and Settings
  // shows the notes under the version. Taken out once the cause is found. ----------
  // (measured by the room above the list — the bar's own height doesn't change on iOS 26 — and looked at on every
  //  layout, scroll, coming back to the page and the app coming back)
  private var bigTop: CGFloat = 0, smallAtTop = false, lastEvent = "—"
  private func note(_ e: String) { lastEvent = e + " " + DiagTitle.clock() }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); look() }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); look() }
  func scrollViewDidScroll(_ s: UIScrollView) { look() }
  private func look() {
    guard !Talk.shared.isContact, navigationController != nil else { return }
    let top = table.adjustedContentInset.top
    // (as the page first shows: big title, search bar away — a search bar pulled out later isn't counted)
    if bigTop == 0, view.window != nil, !search.isActive, table.contentOffset.y <= -top + 1 { bigTop = top }
    guard bigTop > 0 else { return }
    let small = top < bigTop - 20 && table.contentOffset.y <= -top + 1 && !search.isActive && !table.isTracking
    if small && !smallAtTop {
      let app = UIApplication.shared.applicationState == .background ? "in the background" : UIApplication.shared.applicationState == .inactive ? "leaving or coming back" : "open"
      DiagTitle.add("\(clientsTab ? "Clients" : "E11 Agency") went small at the top — app \(app), page \(view.window == nil ? "off screen" : "on screen"), room \(Int(top)) of \(Int(bigTop)), last: \(lastEvent)")
    }
    smallAtTop = small
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) {
    super.traitCollectionDidChange(p)
    if UIApplication.shared.applicationState == .background { note("look redrawn in the background (app switcher picture)") }
  }
  override func viewDidDisappear(_ a: Bool) { if search.isActive { note("search closed while away") } else { note("page left") }; super.viewDidDisappear(a) }
  override func viewWillAppear(_ a: Bool) { note("page coming back"); super.viewWillAppear(a) }
  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.note("app to the background") }
    NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.note("app coming back") }
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.look() }
    view.backgroundColor = GroupsVC.pageBg; table.backgroundColor = GroupsVC.pageBg
    table.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
    table.separatorColor = Look.dyn(0x2A2B2E, 0xDCDCE0)
    table.keyboardDismissMode = .interactive   // (the keyboard rule: the list scrolls while searching, a drag takes it down)
    title = clientsTab ? "Clients" : "E11 Agency"
    navigationItem.largeTitleDisplayMode = .always
    search.searchBar.placeholder = clientsTab ? "Search clients" : "Search clients"
    // (search hidden until the list is pulled down — board 1; Apple's own)
    navigationItem.hidesSearchBarWhenScrolling = true
    search.delegate = self
    makePills()
    setMe()
    NotificationCenter.default.addObserver(self, selector: #selector(setMe), name: .talkChanged, object: nil)
  }
  override func groupModel(_ id: String) -> GroupCell.Model? { Talk.shared.isContact ? makeGroupModel(id) : nil }
  override func pillsUnread() -> Int {
    let T = Talk.shared
    if T.isContact { return T.groups.keys.reduce(0) { $0 + T.unread($1) } }
    return T.myClients(withClient: clientsTab).reduce(0) { $0 + T.clientUnread($1, withClient: clientsTab) }
  }
  @objc private func setMe() {
    let T = Talk.shared
    // (a client contact: "E11 Agency" — their groups straight away, with All · Unread · Mentions: board 14, step 2d)
    title = clientsTab ? "Clients" : "E11 Agency"
    // + top right (Haris 2026-11-13 — E11 Agency gets one too: a group for any client you can see in E11 Console, the
    // client showing in the list once its first group is made; the Clients tab's for Super / Office Admins, as before)
    if T.canMake, !T.isContact, !clientsTab || T.boss {
      if navigationItem.rightBarButtonItem == nil { navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.newGroup() }, menu: nil) }
    } else { navigationItem.rightBarButtonItem = nil }
    // your E11 Console photo, top left in Apple's glass button (Haris 2026-11-13; was top right, board 1) — made once,
    // set again only when it changes
    if navigationItem.leftBarButtonItem == nil {
      meFace.translatesAutoresizingMaskIntoConstraints = false
      meFace.widthAnchor.constraint(equalToConstant: 38).isActive = true; meFace.heightAnchor.constraint(equalToConstant: 38).isActive = true
      meFace.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toSettings)))
      meFace.accessibilityLabel = "You — Settings"; meFace.isAccessibilityElement = true
      navigationItem.leftBarButtonItem = UIBarButtonItem(customView: meFace)
    }
    let key = [T.me?.id, T.me?.name, T.me?.color, T.me?.picture].map { $0 ?? "" }.joined(separator: "|")
    if key != meKey { meKey = key; meFace.set(person: T.me) }
    repaintPillsIfNeeded()
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
    var line: String
    if T.isContact {
      // ("3 groups · 2 unread" — board 14)
      let n = T.groups.count, un = T.groups.keys.reduce(0) { $0 + T.unread($1) }
      line = n == 0 ? "No groups yet" : "\(n) group\(n == 1 ? "" : "s")" + (un > 0 ? " · \(un) unread" : "")
    } else {
      let cs = T.myClients(withClient: clientsTab), un = cs.reduce(0) { $0 + T.clientUnread($1, withClient: clientsTab) }
      // ("No groups yet" with none — board 56)
      line = cs.isEmpty ? "No groups yet" : "\(cs.count) client\(cs.count == 1 ? "" : "s")" + (un > 0 ? " · \(un) unread" : "")
    }
    if #available(iOS 26.0, *), navigationItem.subtitle != line {
      if view.window != nil, let bar = navigationController?.navigationBar { UIView.transition(with: bar, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction], animations: nil) }
      navigationItem.subtitle = line
    }
  }
  override func reload(animated: Bool) {
    super.reload(animated: animated)
    setLine()
  }
  override func build() -> [(String, String, [Row])] {
    let T = Talk.shared
    hits = [:]
    // a client contact: their groups — pinned first, then newest; the filters; search by name or a message, its own rows
    // with the words marked (step 2d, as a client's page)
    if T.isContact {
      hitsG = [:]
      let gs = T.groups.values.sorted { T.activity($0) > T.activity($1) }
      if !query.isEmpty {
        for (gid, m) in T.search(query) where hitsG[gid] == nil { hitsG[gid] = m }
        return [("found", "", gs.filter { $0.name.lowercased().contains(query) || hitsG[$0.id] != nil }.map { .ghit($0.id) })]
      }
      let shown = gs.filter { [filter] g in filter == 0 || (filter == 1 && T.unread(g.id) > 0) || (filter == 2 && T.mentionsMe(g.id)) }
      let pins = T.pinnedGroups
      return [("groups", "", (shown.filter { pins.contains($0.id) } + shown.filter { !pins.contains($0.id) }).map { .group($0.id) })]
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
    // (pinned clients on both tabs — board 19)
    let pinnedC = T.pinnedClients.filter { mine.contains($0) && keep($0) }
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
          : T.isContact ? ("No Groups Yet", "You’ll see one here when E11 adds you to it.")
          : clientsTab ? ("No Client Groups Yet", "Groups with a client contact in them show here.")
          : ("No Groups Yet", "When someone adds you to a group, its client shows here.")
      }
      let v = (table.backgroundView as? UIContentUnavailableView) ?? { let v = UIContentUnavailableView(configuration: e); v.alpha = 0; table.backgroundView = v; return v }()
      // (the words set only while it shows — going away, it keeps what it said as it fades: switching back to All flashed
      //  "No Groups" / "No Mentions" — Haris 2026-11-13; one empty to another crossfades)
      if none, let was = v.configuration as? UIContentUnavailableConfiguration, was.text != e.text || was.secondaryText != e.secondaryText || (was.text == nil && was.image != e.image) {
        if v.alpha > 0, view.window != nil { UIView.transition(with: v, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction]) { v.configuration = e } } else { v.configuration = e }
      }
      let a: CGFloat = none ? 1 : 0
      if v.alpha != a { UIView.animate(withDuration: Crossfade.time) { v.alpha = a } }
    } else {
      let l = (table.backgroundView as? UILabel) ?? { let l = UILabel(); l.textAlignment = .center; l.textColor = .secondaryLabel; l.numberOfLines = 0; l.alpha = 0; table.backgroundView = l; return l }()
      if none { l.text = !query.isEmpty ? "No Results" : filter == 1 ? "No Unread Messages" : filter == 2 ? "No Mentions" : "No Groups Yet" }
      let a: CGFloat = none ? 1 : 0
      if l.alpha != a { UIView.animate(withDuration: Crossfade.time) { l.alpha = a } }
    }
  }
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

// ---------- a client: its groups — the design's boards 2, L2 and 20 (step 2b, Haris 2026-11-13: "same behaviour as the
// E11 Agency page") ----------
// Apple's bar with the client's name and its line in the middle (‹ · name · +); under it the client's logo, then All ·
// Unread · Mentions; the groups as Apple's own cells (GroupCell). The same ways as E11 Agency: search hidden until the list
// is pulled down, the head going while searching, found groups their own rows with the words marked, each row set again
// only when what it shows changed (crossfading), rows coming, going or moving gliding, Apple's empty views.
final class ClientGroupsVC: ListVC {
  let client: String
  init(client: String, clientsTab: Bool = false) { self.client = client; super.init(nibName: nil, bundle: nil); self.clientsTab = clientsTab }
  required init?(coder: NSCoder) { fatalError() }
  private let logo = Avatar(frame: CGRect(x: 0, y: 0, width: 76, height: 76))
  private var logoKey = ""
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = GroupsVC.pageBg; table.backgroundColor = GroupsVC.pageBg
    table.separatorInset = UIEdgeInsets(top: 0, left: 82, bottom: 0, right: 0)
    table.separatorColor = Look.dyn(0x2A2B2E, 0xDCDCE0)
    table.keyboardDismissMode = .interactive   // (the keyboard rule)
    table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 86
    navigationItem.largeTitleDisplayMode = .never   // (board 2: the name and its line in the middle of the bar)
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.hidesSearchBarWhenScrolling = true   // (as E11 Agency: out only as the list is pulled down)
    search.delegate = self
    search.searchBar.placeholder = "Search \(Talk.shared.clients[client]?.name ?? "")’s groups"
    if Talk.shared.canMake && (!clientsTab || Talk.shared.boss) {
      navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
        guard let self = self else { return }
        self.present(UINavigationController(rootViewController: NewGroupVC(client: self.client, forClient: self.clientsTab, fixed: true)), animated: true)
      }, menu: nil)
      navigationItem.rightBarButtonItem?.accessibilityLabel = "New group for \(Talk.shared.clients[client]?.name ?? "this client")"
    }
    // the client's logo (Client Assets), centred under the bar (board 2)
    let top = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 18 + 76 + 14))
    logo.square = true; logo.isUserInteractionEnabled = false
    logo.frame = CGRect(x: (top.bounds.width - 76) / 2, y: 18, width: 76, height: 76); logo.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
    top.addSubview(logo)
    makePills(above: top)
    setLogo()
  }
  private func setLogo() {
    guard let c = Talk.shared.clients[client] else { return }
    let k = [c.name, c.color ?? "", c.logo ?? ""].joined(separator: "|")
    if k != logoKey { logoKey = k; logo.set(client: c) }
  }
  private var mine: [Group] { Talk.shared.groups(of: client, withClient: clientsTab) }
  override func pillsUnread() -> Int { mine.reduce(0) { $0 + Talk.shared.unread($1.id) } }
  override func reload(animated: Bool) {
    let T = Talk.shared
    let gs = mine, un = gs.reduce(0) { $0 + T.unread($1.id) }
    if title != T.clients[client]?.name { title = T.clients[client]?.name }
    // (under the name: "7 groups · 3 unread" — "with the client" on the Clients tab, board 20 — crossfading when it changes)
    let n = "\(gs.count) group\(gs.count == 1 ? "" : "s")" + (clientsTab ? " with the client" : "")
    let sub = n + (un > 0 ? " · \(un) unread" : "")
    if #available(iOS 26.0, *), navigationItem.subtitle != sub {
      if view.window != nil, let bar = navigationController?.navigationBar { UIView.transition(with: bar, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction], animations: nil) }
      navigationItem.subtitle = sub
    }
    setLogo(); repaintPillsIfNeeded()
    super.reload(animated: animated)
    // (the client gone, or no groups of it left for me: back to the list)
    if gs.isEmpty, view.window != nil, navigationController?.topViewController === self { navigationController?.popViewController(animated: true) }
  }
  override func build() -> [(String, String, [Row])] {
    let T = Talk.shared
    hitsG = [:]
    let gs = mine
    if !query.isEmpty {
      // searching (as board 19): the groups, by name or by a message in them — the words found marked
      let ids = Set(gs.map { $0.id })
      for (gid, m) in T.search(query) where ids.contains(gid) && hitsG[gid] == nil { hitsG[gid] = m }
      return [("found", "", gs.filter { $0.name.lowercased().contains(query) || hitsG[$0.id] != nil }.map { .ghit($0.id) })]
    }
    let keep: (Group) -> Bool = { [filter] g in filter == 0 || (filter == 1 && T.unread(g.id) > 0) || (filter == 2 && T.mentionsMe(g.id)) }
    // (pinned first, then newest — board 2)
    let pins = clientsTab ? T.pinnedClientGroups : T.pinnedGroups
    let shown = gs.filter(keep)
    let ordered = shown.filter { pins.contains($0.id) } + shown.filter { !pins.contains($0.id) }
    return [("groups", "", ordered.map { .group($0.id) })]
  }
  override func groupModel(_ id: String) -> GroupCell.Model? { makeGroupModel(id) }
  // nothing to show: Apple's own empty views, faded in and out (as E11 Agency's)
  override func emptyNote() {
    let none = data.snapshot().numberOfItems == 0 && !mine.isEmpty
    if #available(iOS 17.0, *) {
      var e: UIContentUnavailableConfiguration
      if !query.isEmpty { e = .search() }
      else {
        e = .empty()
        e.image = UIImage(systemName: filter == 2 ? "at" : "bubble.left.and.bubble.right")
        (e.text, e.secondaryText) = filter == 1 ? ("No Unread Messages", "Groups with something new show here.")
          : ("No Mentions", "Groups where someone @mentions you show here.")
      }
      let v = (table.backgroundView as? UIContentUnavailableView) ?? { let v = UIContentUnavailableView(configuration: e); v.alpha = 0; table.backgroundView = v; return v }()
      // (the words set only while it shows — going away, it keeps what it said as it fades: switching back to All flashed
      //  "No Groups" / "No Mentions" — Haris 2026-11-13; one empty to another crossfades)
      if none, let was = v.configuration as? UIContentUnavailableConfiguration, was.text != e.text || was.secondaryText != e.secondaryText || (was.text == nil && was.image != e.image) {
        if v.alpha > 0, view.window != nil { UIView.transition(with: v, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction]) { v.configuration = e } } else { v.configuration = e }
      }
      let a: CGFloat = none ? 1 : 0
      if v.alpha != a { UIView.animate(withDuration: Crossfade.time) { v.alpha = a } }
    } else {
      let l = (table.backgroundView as? UILabel) ?? { let l = UILabel(); l.textAlignment = .center; l.textColor = .secondaryLabel; l.numberOfLines = 0; l.alpha = 0; table.backgroundView = l; return l }()
      if none { l.text = !query.isEmpty ? "No Results" : filter == 1 ? "No Unread Messages" : "No Mentions" }
      let a: CGFloat = none ? 1 : 0
      if l.alpha != a { UIView.animate(withDuration: Crossfade.time) { l.alpha = a } }
    }
  }
}

// A group's row on a client's page (board 2): Apple's own list cell — the picture (round), the name, the newest message on
// two lines — with ours inside it, said plainly: the time on the first line, ✓✓ on yours, the unread count, muted and
// pinned, and "With Client" (board 20)
final class GroupCell: UITableViewCell {
  static let id = "group"
  struct Model {
    let id: String, group: Group?, name: String, line: String, typing: Bool, ticks: Int, time: String, unread: Int, pinned: Bool, muted: Bool, chip: Bool, find: String
    static func blank(_ id: String) -> Model { Model(id: id, group: nil, name: "", line: "", typing: false, ticks: 0, time: "", unread: 0, pinned: false, muted: false, chip: false, find: "") }
    var sig: Int {
      var h = Hasher(); [id, name, line, time, find, group?.pic ?? "", group?.client ?? ""].forEach { h.combine($0) }
      h.combine(typing); h.combine(ticks); h.combine(unread); h.combine(pinned); h.combine(muted); h.combine(chip)
      if let c = group.flatMap({ Talk.shared.clients[$0.client] }) { h.combine(c.logo); h.combine(c.color) }
      return h.finalize()
    }
  }
  private let pic = Avatar(frame: CGRect(x: 0, y: 0, width: 54, height: 54)), time = UILabel(), badge = PaddedBadge(), marks = UIStackView()
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    pic.isUserInteractionEnabled = false
    time.font = .systemFont(ofSize: 14); time.textAlignment = .right
    badge.font = .systemFont(ofSize: 13, weight: .bold); badge.layer.cornerRadius = 11
    marks.axis = .horizontal; marks.spacing = 6; marks.alignment = .center
    badgeW = badge.widthAnchor.constraint(equalToConstant: 22); badgeW.isActive = true
    badge.heightAnchor.constraint(equalToConstant: 22).isActive = true
    insetsLayoutMarginsFromSafeArea = false; contentView.insetsLayoutMarginsFromSafeArea = false   // (steady heights — the rule)
    contentConfiguration = UIListContentConfiguration.subtitleCell()   // (Apple's content view first, ours into it)
    [pic, time, marks].forEach { contentView.addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateConfiguration(using state: UICellConfigurationState) {
    var bg = UIBackgroundConfiguration.listPlainCell().updated(for: state)
    if !state.isHighlighted && !state.isSelected { bg.backgroundColor = .clear }
    backgroundConfiguration = bg
  }
  private static func marked(_ t: String, _ q: String, font: UIFont, ink: UIColor) -> NSMutableAttributedString {
    let a = NSMutableAttributedString(string: t, attributes: [.font: font, .foregroundColor: ink])
    guard !q.isEmpty else { return a }
    var from = t.startIndex
    while let r = t.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: from..<t.endIndex) {
      a.addAttributes([.backgroundColor: AgencyCell.findBg, .foregroundColor: AgencyCell.findInk], range: NSRange(r, in: t)); from = r.upperBound
    }
    return a
  }
  // "With Client" (board 20): orange words on a faint orange, a picture for each look so iPhone switches it itself
  private static let chipFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
  // (its size in points, known here — the picture from the look's set came back in pixels and was stretched, Haris 2026-11-13)
  private static let chipW: CGFloat = ceil(("With Client" as NSString).size(withAttributes: [.font: chipFont]).width) + 16
  private static let chip: UIImage = {
    func draw(_ dark: Bool) -> UIImage {
      let f = chipFont, t = "With Client" as NSString
      let ink = dark ? Look.rgb(0xFFB340) : Look.rgb(0xC26A00), fill = dark ? Look.rgb(0xFF9F0A, 0.16) : Look.rgb(0xFF9F0A, 0.16)
      let w = chipW
      let fmt = UIGraphicsImageRendererFormat.preferred(); fmt.scale = UIScreen.main.scale
      return UIGraphicsImageRenderer(size: CGSize(width: w, height: 18), format: fmt).image { _ in
        fill.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: 18), cornerRadius: 8).fill()
        t.draw(at: CGPoint(x: 8, y: 1.5), withAttributes: [.font: f, .foregroundColor: ink])
      }
    }
    let asset = UIImageAsset()
    let scale = UITraitCollection(displayScale: UIScreen.main.scale)
    asset.register(draw(false), with: UITraitCollection(traitsFrom: [scale, UITraitCollection(userInterfaceStyle: .light)]))
    asset.register(draw(true), with: UITraitCollection(traitsFrom: [scale, UITraitCollection(userInterfaceStyle: .dark)]))
    return asset.image(with: UITraitCollection(traitsFrom: [scale, UITraitCollection.current]))
  }()
  private var rightW: CGFloat = 0
  private var badgeW: NSLayoutConstraint!
  func show(_ m: Model) {
    time.text = m.time; time.textColor = m.unread > 0 ? Look.dyn(0x5AA9FF, 0x2F7BFF) : .secondaryLabel
    badge.text = m.unread > 99 ? "99+" : "\(m.unread)"; badge.backgroundColor = m.muted ? .systemGray3 : Look.dyn(0x2F7BFF, 0x2F7BFF)
    // (under the time: muted · unread · pinned — board 2's order)
    marks.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let sym = { (n: String) -> UIImageView in
      let v = UIImageView(image: UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))); v.tintColor = .secondaryLabel; return v
    }
    if m.muted { marks.addArrangedSubview(sym("speaker.slash.fill")) }
    if m.unread > 0 { badgeW.constant = max(22, ceil(badge.sizeThatFits(.zero).width) + 2); marks.addArrangedSubview(badge) }
    if m.pinned { marks.addArrangedSubview(sym("pin.fill")) }
    let tw = ceil(time.sizeThatFits(CGSize(width: 140, height: 20)).width)
    let mw = ceil(marks.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
    rightW = max(tw, mw)
    var cfg = UIListContentConfiguration.subtitleCell()
    let title = GroupCell.marked(m.name, m.find, font: .systemFont(ofSize: 17, weight: .semibold), ink: .label)
    if m.chip {
      let a = NSTextAttachment(image: GroupCell.chip); a.bounds = CGRect(x: 0, y: -3, width: GroupCell.chipW, height: 18)
      title.append(NSAttributedString(string: "\n")); title.append(NSAttributedString(attachment: a))
    }
    cfg.attributedText = title
    let line = NSMutableAttributedString()
    if m.ticks > 0 {
      let c: UIColor = m.ticks == 3 ? Look.dyn(0x5AA9FF, 0x2F7BFF) : .secondaryLabel
      // (a template picture in the line's own colour — light and dark switch it with nothing drawn again)
      let t = NSTextAttachment(image: Ticks.image(.black, double: m.ticks > 1).withRenderingMode(.alwaysTemplate)); t.bounds = CGRect(x: 0, y: 0, width: 16, height: 10)
      let tick = NSMutableAttributedString(attachment: t); tick.addAttribute(.foregroundColor, value: c, range: NSRange(location: 0, length: tick.length))
      line.append(tick); line.append(NSAttributedString(string: " "))
    }
    line.append(GroupCell.marked(m.line, m.find, font: .systemFont(ofSize: 15), ink: m.typing ? Look.accent : .secondaryLabel))
    cfg.secondaryAttributedText = line
    cfg.textProperties.numberOfLines = m.chip ? 2 : 1; cfg.secondaryTextProperties.numberOfLines = 2
    cfg.textToSecondaryTextVerticalPadding = 2
    cfg.image = UIImage(systemName: "circle.fill"); cfg.imageProperties.tintColor = .clear
    cfg.imageProperties.reservedLayoutSize = CGSize(width: 54, height: 54); cfg.imageProperties.maximumSize = CGSize(width: 54, height: 54)
    cfg.imageToTextPadding = 12
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16 + rightW + 8)
    contentConfiguration = cfg
    [pic, time, marks].forEach { contentView.bringSubviewToFront($0) }
    if Talk.shared.isContact { pic.setE11() } else if let g = m.group { pic.set(group: g) }
    accessibilityLabel = [m.name, m.chip ? "With Client" : nil, m.line, m.time, m.unread > 0 ? "\(m.unread) unread" : nil, m.muted ? "Muted" : nil, m.pinned ? "Pinned" : nil].compactMap { $0 }.joined(separator: ", ")
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = contentView.bounds.width
    pic.frame = CGRect(x: 16, y: 10, width: 54, height: 54)
    let tw = ceil(time.sizeThatFits(CGSize(width: 140, height: 20)).width)
    time.frame = CGRect(x: W - 16 - tw, y: 14, width: tw, height: 18)
    let ms = marks.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    marks.frame = CGRect(x: W - 16 - ms.width, y: 38, width: ms.width, height: 22)
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

// the TEMPORARY check's notes (the big title going small at the top) — the newest 12, kept on the phone, shown in Settings
enum DiagTitle {
  static func clock() -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date()) }
  static var notes: [String] { UserDefaults.standard.stringArray(forKey: "diag-title") ?? [] }
  static func add(_ s: String) { UserDefaults.standard.set(Array(([clock() + " " + s] + notes).prefix(12)), forKey: "diag-title") }
}
