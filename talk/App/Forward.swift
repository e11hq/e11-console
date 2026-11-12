import UIKit

/* Forward a message (the approved design, board "Forward sheet"; Haris 2026-11-12): Apple's sheet — ✕, "Forward To" and
   how many are picked, Apple's search (the list filtered as you type), then RECENT and ALL GROUPS in Apple's inset groups:
   Apple's tick circle, the group's picture, its name, its client under it. Only the groups you're in. A group the client can
   see (the Clients tab's) carries the "With Client" chip and a small orange circle with a person on its picture. Pick one
   or more; the bar at the bottom names them, with the blue send. Each gets a copy marked "Forwarded". */
final class ForwardVC: UIViewController, UICollectionViewDelegate, UISearchResultsUpdating {
  private let msgs: [Msg], from: String
  private var msg: Msg { msgs[0] }
  private var cv: UICollectionView!
  private var data: UICollectionViewDiffableDataSource<String, String>!
  private var picked: [String] = []            // group ids, in the order picked
  private var query = ""
  private let search = UISearchController(searchResultsController: nil)
  private let sendBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  private let names = UILabel(), sendB = UIButton(type: .custom)
  private let titleL = UILabel(), countL = UILabel()

  // (one message, or an album's photos together — Haris 2026-11-12: holding an album acts on the whole album)
  init(msgs: [Msg], from: String) { self.msgs = msgs; self.from = from; super.init(nibName: nil, bundle: nil) }
  convenience init(msg: Msg, from: String) { self.init(msgs: [msg], from: from) }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    // the title: "Forward To" and, under it, how many are picked
    titleL.text = "Forward To"; titleL.font = .systemFont(ofSize: 17, weight: .semibold); titleL.textAlignment = .center
    countL.font = .systemFont(ofSize: 13); countL.textColor = .secondaryLabel; countL.textAlignment = .center
    let tv = UIStackView(arrangedSubviews: [titleL, countL]); tv.axis = .vertical; tv.alignment = .center
    navigationItem.titleView = tv
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; search.hidesNavigationBarDuringPresentation = false
    search.searchBar.placeholder = "Search"
    navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
    navigationItem.preferredSearchBarPlacement = .stacked

    var c = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
    c.headerMode = .supplementary
    c.separatorConfiguration.bottomSeparatorInsets.leading = 104
    cv = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: c))
    cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cv.allowsMultipleSelection = true; cv.delegate = self
    cv.keyboardDismissMode = .interactive
    view.addSubview(cv)

    let rowReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
      guard let self = self, let g = Talk.shared.groups[String(key.dropFirst(2))] else { return }
      let T = Talk.shared
      var cf = UIListContentConfiguration.subtitleCell()
      let chip = g.withClient && !T.isContact
      let name = NSMutableAttributedString(string: g.name, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label])
      if chip {
        let a = NSTextAttachment(image: ForwardVC.chip); a.bounds = CGRect(x: 0, y: -3, width: ForwardVC.chip.size.width, height: ForwardVC.chip.size.height)
        name.append(NSAttributedString(string: "  ")); name.append(NSAttributedString(attachment: a))
      }
      cf.attributedText = name
      cf.secondaryText = T.clients[g.client]?.name ?? ""
      cf.secondaryTextProperties.font = .systemFont(ofSize: 13); cf.secondaryTextProperties.color = .secondaryLabel
      cf.image = GroupFace.image(g, badge: chip) { [weak self] in self?.redraw(key) }
      cf.imageProperties.maximumSize = CGSize(width: 40, height: 40); cf.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
      cf.imageToTextPadding = 12; cf.textToSecondaryTextVerticalPadding = 1
      cf.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 16)
      cell.contentConfiguration = cf
      cell.accessories = [.multiselect(displayed: .always)]
      // (picked: Apple's filled tick only — no grey over the row)
      cell.configurationUpdateHandler = { c, _ in var b = UIBackgroundConfiguration.listGroupedCell(); b.backgroundColor = .secondarySystemGroupedBackground; c.backgroundConfiguration = b }
    }
    let headReg = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, ip in
      var h = UIListContentConfiguration.groupedHeader()
      h.text = self?.data.snapshot().sectionIdentifiers[safe: ip.section] == "recent" ? "RECENT" : "ALL GROUPS"
      cell.contentConfiguration = h
    }
    data = UICollectionViewDiffableDataSource<String, String>(collectionView: cv) { cv, ip, key in cv.dequeueConfiguredReusableCell(using: rowReg, for: ip, item: key) }
    data.supplementaryViewProvider = { cv, _, ip in cv.dequeueConfiguredReusableSupplementary(using: headReg, for: ip) }

    // the bar at the bottom: the picked groups' names and the blue send — in once something is picked
    names.font = .systemFont(ofSize: 15); names.textColor = .secondaryLabel; names.lineBreakMode = .byTruncatingTail
    var sc = UIButton.Configuration.filled()
    sc.image = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
    sc.baseBackgroundColor = Look.rgb(0x2F7BFF); sc.baseForegroundColor = .white; sc.cornerStyle = .capsule; sc.contentInsets = .zero
    sendB.configuration = sc; sendB.accessibilityLabel = "Send"
    sendB.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
    [names, sendB].forEach { sendBar.contentView.addSubview($0) }
    sendBar.alpha = 0
    view.addSubview(sendBar)
    reload()
    showPicked(animated: false)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let W = view.bounds.width, h: CGFloat = 64 + view.safeAreaInsets.bottom
    sendBar.frame = CGRect(x: 0, y: view.bounds.height - h, width: W, height: h)
    names.frame = CGRect(x: 20, y: 10, width: W - 96, height: 44)
    sendB.frame = CGRect(x: W - 64, y: 10, width: 44, height: 44)
    cv.contentInset.bottom = picked.isEmpty ? 0 : 64
  }

  // RECENT: the five chats most lately busy; ALL GROUPS: every group by name — searching: the matching ones, one list
  private func reload() {
    // (a task card can't go where a client can see it — those groups aren't offered, Haris 2026-11-12)
    let T = Talk.shared, all = Array(T.groups.values).filter { msg.task == nil || !$0.withClient }
    var s = NSDiffableDataSourceSnapshot<String, String>()
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    if !q.isEmpty {
      let hits = all.filter { $0.name.lowercased().contains(q) || (T.clients[$0.client]?.name.lowercased().contains(q) ?? false) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      s.appendSections(["all"]); s.appendItems(hits.map { "a:" + $0.id }, toSection: "all")
    } else {
      let recent = all.sorted { T.activity($0) > T.activity($1) }.prefix(5)
      s.appendSections(["recent", "all"])
      s.appendItems(recent.map { "r:" + $0.id }, toSection: "recent")
      s.appendItems(all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map { "a:" + $0.id }, toSection: "all")
    }
    data.apply(s, animatingDifferences: false)
    for k in s.itemIdentifiers where picked.contains(String(k.dropFirst(2))) { cv.selectItem(at: data.indexPath(for: k), animated: false, scrollPosition: []) }
  }
  private func redraw(_ key: String) {
    var s = data.snapshot(); guard s.indexOfItem(key) != nil else { return }
    s.reconfigureItems([key]); data.apply(s, animatingDifferences: false)
  }
  func updateSearchResults(for c: UISearchController) {
    let q = c.searchBar.text ?? ""
    guard q != query else { return }
    query = q; reload()
  }

  // a group picked in one list is picked in the other too
  func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) { toggle(ip, on: true) }
  func collectionView(_ cv: UICollectionView, didDeselectItemAt ip: IndexPath) { toggle(ip, on: false) }
  private func toggle(_ ip: IndexPath, on: Bool) {
    guard let key = data.itemIdentifier(for: ip) else { return }
    let id = String(key.dropFirst(2))
    UISelectionFeedbackGenerator().selectionChanged()
    if on { if !picked.contains(id) { picked.append(id) } } else { picked.removeAll { $0 == id } }
    for twin in ["r:" + id, "a:" + id] where twin != key {
      if let tip = data.indexPath(for: twin) { if on { cv.selectItem(at: tip, animated: false, scrollPosition: []) } else { cv.deselectItem(at: tip, animated: false) } }
    }
    showPicked(animated: true)
  }
  private func showPicked(animated: Bool) {
    countL.text = picked.isEmpty ? "Pick groups" : "\(picked.count) selected"
    names.text = picked.compactMap { Talk.shared.groups[$0]?.name }.joined(separator: ", ")
    view.setNeedsLayout()
    let go = { self.sendBar.alpha = self.picked.isEmpty ? 0 : 1 }
    if animated { UIView.animate(withDuration: 0.25, animations: go) } else { go() }
  }

  // each picked group gets its own copy, marked Forwarded — a file sent again from this phone's copy
  private func send() {
    guard !picked.isEmpty else { return }
    let all = msgs, targets = picked
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let done = { [weak self] in
      toast(targets.count == 1 ? "Forwarded" : "Forwarded to \(targets.count) groups")
      self?.dismiss(animated: true)
    }
    // (an album goes on as an album — one id per group for its photos, so it arrives as one)
    let albumIds = Dictionary(uniqueKeysWithValues: targets.map { ($0, all.count >= 4 ? UUID().uuidString : nil) })
    sendB.isEnabled = false
    var left = all.count, failed = false
    func next(_ i: Int) {
      guard i < all.count else { if !failed { done() } else { sendB.isEnabled = true }; return }
      let m = all[i]
      guard let f = m.file else {
        for g in targets { Talk.shared.send(g, text: m.text, fwd: true, task: m.task) }
        left -= 1; next(i + 1); return
      }
      Net.shared.file(f.id) { url in
        guard let url = url, let d = try? Data(contentsOf: url) else { failed = true; toast("That file isn’t on this phone any more"); next(all.count); return }
        for g in targets {
          let tmp = "local-" + UUID().uuidString
          let copy = Msg.FileRef(id: tmp, name: f.name, size: d.count, kind: f.kind, w: f.w, h: f.h, secs: f.secs, wave: f.wave)
          Talk.shared.send(g, text: m.text, file: copy, localFile: url, upload: d, fwd: true, album: albumIds[g] ?? nil)
        }
        left -= 1; next(i + 1)
      }
    }
    next(0)
  }

  // the chip beside a group the client can see — the Clients tab's own (orange words on a faint orange)
  static let chip: UIImage = {
    let t = NSAttributedString(string: "With Client", attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.systemOrange])
    let ts = t.size(), size = CGSize(width: ceil(ts.width) + 12, height: 18)
    return UIGraphicsImageRenderer(size: size).image { _ in
      UIColor.systemOrange.withAlphaComponent(0.14).setFill(); UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7).fill()
      t.draw(at: CGPoint(x: 6, y: (size.height - ts.height) / 2))
    }
  }()
}

// a group's picture as an image for Apple's cells — its own picture, else its client's logo, else its letter on the
// client's colour; with the client's badge (orange circle, a person) at the bottom right when the client can see it
enum GroupFace {
  private static var cache: [String: UIImage] = [:]
  static func image(_ g: Group, badge: Bool, loaded: @escaping () -> Void) -> UIImage {
    let key = "\(g.id)|\(g.pic ?? "")|\(badge)"
    if let i = cache[key] { return i }
    let c = Talk.shared.clients[g.client]
    let ink = Look.hex(c?.color) ?? Look.accent
    let draw = { (pic: UIImage?) -> UIImage in
      let S: CGFloat = 80
      return UIGraphicsImageRenderer(size: CGSize(width: S, height: S)).image { ctx in
        let r = CGRect(x: 0, y: 0, width: S, height: S)
        ctx.cgContext.saveGState(); UIBezierPath(ovalIn: r).addClip()
        if let p = pic { p.draw(in: r) } else {
          ink.setFill(); UIRectFill(r)
          let t = NSAttributedString(string: String(g.name.prefix(1)).uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 32, weight: .semibold), .foregroundColor: UIColor.white])
          let ts = t.size(); t.draw(at: CGPoint(x: (S - ts.width) / 2, y: (S - ts.height) / 2))
        }
        ctx.cgContext.restoreGState()
        if badge {
          let b = CGRect(x: S - 32, y: S - 32, width: 32, height: 32)
          UIColor.systemBackground.setFill(); UIBezierPath(ovalIn: b).fill()
          UIColor.systemOrange.setFill(); UIBezierPath(ovalIn: b.insetBy(dx: 3, dy: 3)).fill()
          if let p = UIImage(systemName: "person.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            p.draw(at: CGPoint(x: b.midX - p.size.width / 2, y: b.midY - p.size.height / 2))
          }
        }
      }
    }
    let plain = draw(nil)
    let took = { (i: UIImage?) in
      guard let i = i else { return }
      let first = cache[key] == nil
      cache[key] = draw(i)
      if first { DispatchQueue.main.async { loaded() } }
    }
    if let p = g.pic { Net.shared.file(p) { url in took(url.flatMap { UIImage(contentsOfFile: $0.path) }) } }
    else if let l = c?.logo { Net.shared.picture(l) { took($0) } }
    else { cache[key] = plain }
    return cache[key] ?? plain
  }
}
