import UIKit

/* Who reacted (mock-up "Talk — Reactions sheet", Haris 2026-11-13 18:35 "Yes"): a tap on the reactions under a bubble —
   Apple's sheet, half height (pulled up for more); at the top the Inbox's buttons: All with how many, then each reaction
   with how many (the most first); each person Apple's cell — picture, name, role (a client's in the client colour), their
   reaction on the right; yours first, "You", "Tap to remove". Live: a reaction coming or going fades in or out in place;
   the last one taken off closes the sheet. */
final class ReactionsVC: UIViewController, UITableViewDelegate {
  private let group: String, msgId: String
  private let onRemove: () -> Void
  init(group: String, msg: String, onRemove: @escaping () -> Void) { self.group = group; self.msgId = msg; self.onRemove = onRemove; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private let pillsRow = UIStackView()
  private var pills: [UIButton] = []
  private var tabKeys: [String] = []          // "" = All, else the emoji
  private var picked = ""
  private var data: UITableViewDiffableDataSource<Int, String>!
  private var sigs: [String: String] = [:]
  private var reactions: [String: String] { Talk.shared.log(group).msgs.first(where: { $0.id == msgId })?.reactions ?? [:] }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    pillsRow.axis = .horizontal; pillsRow.spacing = 8; pillsRow.alignment = .center
    pillsRow.translatesAutoresizingMaskIntoConstraints = false
    table.translatesAutoresizingMaskIntoConstraints = false; table.backgroundColor = .clear
    table.delegate = self; table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 60
    table.contentInset.top = 0; table.sectionHeaderTopPadding = 0
    table.register(UITableViewCell.self, forCellReuseIdentifier: "p")
    view.addSubview(pillsRow); view.addSubview(table)
    NSLayoutConstraint.activate([
      pillsRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 26), pillsRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      pillsRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16), pillsRow.heightAnchor.constraint(equalToConstant: 32),
      table.topAnchor.constraint(equalTo: pillsRow.bottomAnchor, constant: 0), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    data = UITableViewDiffableDataSource(tableView: table) { [weak self] tv, ip, id in
      let c = tv.dequeueReusableCell(withIdentifier: "p", for: ip); self?.fill(c, id); return c
    }
    data.defaultRowAnimation = .fade
    NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .talkGroup, object: nil)
    reload(animated: false)
  }
  @objc private func changed(_ n: Notification) {
    guard (n.object as? String) == group else { return }
    if reactions.isEmpty { dismiss(animated: true); return }
    reload(animated: view.window != nil)
  }
  // the reactions, the most first; you first in the list, then the rest by name
  private func order() -> (tabs: [(String, Int)], people: [String]) {
    let r = reactions, me = Talk.shared.me?.id ?? ""
    let counts = Dictionary(grouping: r.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    let ids = r.keys.filter { picked.isEmpty || r[$0] == picked }
      .sorted { a, b in a == me ? true : b == me ? false : Talk.shared.name(a) < Talk.shared.name(b) }
    return ([("", r.count)] + counts, ids)
  }
  private func reload(animated: Bool) {
    if !picked.isEmpty && !reactions.values.contains(picked) { picked = "" }   // (that reaction gone: back to All)
    let o = order()
    paintPills(o.tabs, animated: animated)
    var snap = NSDiffableDataSourceSnapshot<Int, String>(); snap.appendSections([0]); snap.appendItems(o.people)
    var new: [String: String] = [:]
    for id in o.people { new[id] = (reactions[id] ?? "") + "|" + Talk.shared.name(id) }
    let old = data.snapshot()
    snap.reconfigureItems(o.people.filter { old.indexOfItem($0) != nil && sigs[$0] != new[$0] })
    sigs = new
    data.applySteady(snap, in: table, animated: animated)
  }
  // the Inbox's buttons (Talk's own pills): the chosen one in the page's ink, the others on a soft fill
  private func paintPills(_ tabs: [(String, Int)], animated: Bool) {
    let keys = tabs.map { $0.0 }
    let rebuild = keys != tabKeys
    let put = {
      if rebuild {
        self.pills.forEach { $0.removeFromSuperview() }; self.pills = []
        for (k, _) in tabs {
          let b = UIButton(type: .system)
          b.addAction(UIAction { [weak self] _ in self?.pick(k) }, for: .touchUpInside)
          self.pills.append(b); self.pillsRow.addArrangedSubview(b)
        }
        self.tabKeys = keys
      }
      for (i, (k, n)) in tabs.enumerated() {
        var c = UIButton.Configuration.filled(); c.cornerStyle = .capsule
        c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        let on = k == self.picked
        c.baseBackgroundColor = on ? Look.dyn(0xF5F5F7, 0x000000) : Look.dyn(0x2C2C2E, 0xE3E3E8)
        c.baseForegroundColor = on ? Look.dyn(0x000000, 0xFFFFFF) : .label
        c.attributedTitle = AttributedString((k.isEmpty ? "All" : k) + " \(n)", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: on ? .semibold : .regular)]))
        self.pills[i].configuration = c
        self.pills[i].accessibilityLabel = (k.isEmpty ? "All" : k) + ", \(n)"
      }
    }
    if animated { UIView.transition(with: pillsRow, duration: Crossfade.time, options: [.transitionCrossDissolve, .allowUserInteraction]) { UIView.performWithoutAnimation(put) } } else { put() }
  }
  private func pick(_ k: String) {
    guard k != picked else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    picked = k; reload(animated: true)
  }
  private func fill(_ c: UITableViewCell, _ id: String) {
    let T = Talk.shared, me = id == T.me?.id
    guard let p = me ? T.me : T.people[id] else { return }
    PickRows.person(c, p, size: 40)
    if var cfg = c.contentConfiguration as? UIListContentConfiguration {
      if me { cfg.text = "You"; cfg.secondaryText = "Tap to remove"; cfg.secondaryTextProperties.color = .secondaryLabel; cfg.secondaryTextProperties.font = .systemFont(ofSize: 13) }
      else if p.contact { cfg.secondaryText = "Client" + (p.client.flatMap { T.clients[$0]?.name }.map { " · \($0)" } ?? ""); cfg.secondaryTextProperties.color = Look.clientInk }
      c.contentConfiguration = cfg
    }
    let e = UILabel(); e.text = reactions[id]; e.font = .systemFont(ofSize: 24); e.sizeToFit(); c.accessoryView = e
    c.selectionStyle = me ? .default : .none
  }
  func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
    tv.deselectRow(at: ip, animated: true)
    guard data.itemIdentifier(for: ip) == Talk.shared.me?.id else { return }
    onRemove()
  }
}
