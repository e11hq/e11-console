import UIKit
import QuickLook

/* Group Info › Photos, Files and Links (step 1b — the mock-up "Talk — Photos, Files and Links", approved by Haris
   2026-11-13 00:22 as drawn: Media by month, links mixed in by date, the hold menu Show in Chat · Forward · Save · Share ·
   Delete). Apple's own parts: the segmented control under the bar, a collection view (a grid for Media, inset-grouped list
   rows for Files and Links) with Apple's headers, Apple's lift and menu on hold, Quick Look, Apple's empty state. Ours, said
   plainly: the kind badge on a file and the E11 marks on our own links. From the phone's copy — live, offline. */
final class MediaVC: UIViewController, UICollectionViewDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  let group: String
  init(group: String) { self.group = group; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }

  private enum Tab: Int { case media, files, links }
  private var shown: Tab = .media
  private let seg = UISegmentedControl(items: ["Media", "Files", "Links"])
  private var cv: UICollectionView!
  private var data: UICollectionViewDiffableDataSource<String, String>!
  private var byId: [String: Msg] = [:]
  private var sigs: [String: Int] = [:]
  private var previewURL: URL?
  private weak var openFrom: UIView?

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Photos, Files and Links"; navigationItem.largeTitleDisplayMode = .never
    view.backgroundColor = .systemGroupedBackground
    seg.selectedSegmentIndex = 0
    seg.addAction(UIAction { [weak self] _ in guard let self = self else { return }; self.shown = Tab(rawValue: self.seg.selectedSegmentIndex) ?? .media; self.reload(animated: false, layout: true) }, for: .valueChanged)
    cv = UICollectionView(frame: view.bounds, collectionViewLayout: layout())
    cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cv.backgroundColor = .clear; cv.delegate = self
    view.addSubview(cv)
    // (Media · Files · Links in Apple's bar, where the title was — B, Haris 2026-11-13: under the bar, the frost behind them
    //  went each time they were pressed; in the bar, Apple's bar, its frost and the press are all one. The title stays the
    //  page's name for ‹ and VoiceOver.)
    // (its width and height given, and its frame from the start — E11 Console's task page lesson (Haris 2026-11-09): with
    //  only a width, Apple's bar sized it from the room it had while the page slid in, its top cut until the page landed,
    //  and it sat off to one side; 44 high, as ‹ beside it)
    seg.translatesAutoresizingMaskIntoConstraints = false
    seg.widthAnchor.constraint(equalToConstant: 236).isActive = true
    seg.heightAnchor.constraint(equalToConstant: 44).isActive = true
    seg.frame = CGRect(x: 0, y: 0, width: 236, height: 44)
    seg.apportionsSegmentWidthsByContent = false
    navigationItem.titleView = seg

    let grid = UICollectionView.CellRegistration<PicCell, String> { [weak self] c, _, id in if let m = self?.byId[id] { c.set(m) } }
    let row = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] c, _, id in if let m = self?.byId[id] { self?.fillRow(c, m) } }
    let empty = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] c, _, _ in
      guard let self = self else { return }
      let what = self.shown == .media ? "Photos and videos" : self.shown == .files ? "Files" : "Links"
      let title = self.shown == .media ? "No Media" : self.shown == .files ? "No Files" : "No Links"
      if #available(iOS 17.0, *) {
        var e = UIContentUnavailableConfiguration.empty()
        e.image = UIImage(systemName: self.shown == .media ? "photo.on.rectangle" : self.shown == .files ? "doc" : "link")
        e.text = title; e.secondaryText = "\(what) sent in this group show here."
        c.contentConfiguration = e
      } else {
        // (iOS 16: the line alone, as every Apple page's empty state there)
        var e = UIListContentConfiguration.cell(); e.text = title; e.textProperties.alignment = .center; e.textProperties.color = .secondaryLabel
        c.contentConfiguration = e
      }
    }
    data = UICollectionViewDiffableDataSource(collectionView: cv) { [weak self] cv, ip, id in
      if id == "empty" { return cv.dequeueConfiguredReusableCell(using: empty, for: ip, item: id) }
      return self?.shown == .media ? cv.dequeueConfiguredReusableCell(using: grid, for: ip, item: id) : cv.dequeueConfiguredReusableCell(using: row, for: ip, item: id)
    }
    let head = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] h, _, ip in
      guard let self = self, let s = self.data.sectionIdentifier(for: ip.section) else { return }
      var c = UIListContentConfiguration.groupedHeader(); c.text = s == "empty" ? nil : s; h.contentConfiguration = c
    }
    data.supplementaryViewProvider = { cv, _, ip in cv.dequeueConfiguredReusableSupplementary(using: head, for: ip) }
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkGroup, object: group)
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .talkChanged, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(gone(_:)), name: .talkGone, object: nil)
    reload(animated: false, layout: false)
  }
  @objc private func changed() { reload(animated: view.window != nil, layout: false) }
  @objc private func gone(_ n: Notification) { if (n.object as? String) == group { navigationController?.popToRootViewController(animated: true) } }

  // ---------- what it shows ----------
  private func items(_ t: Tab) -> [Msg] {
    Talk.shared.log(group).msgs.filter { m in
      guard !m.deleted, !m.pending else { return false }
      switch t {
      case .media: return (m.kind == "photo" || m.kind == "video") && m.file != nil
      case .files: return m.file != nil && m.kind != "photo" && m.kind != "video" && m.kind != "voice"
      case .links: return m.link != nil
      }
    }.reversed()
  }
  private static let monthF: DateFormatter = { let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f }()
  private func month(_ ms: Double) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current
    if cal.isDate(d, equalTo: Date(), toGranularity: .month) { return "This Month" }
    if cal.isDate(d, equalTo: Date(), toGranularity: .year) { let f = DateFormatter(); f.dateFormat = "LLLL"; return f.string(from: d) }
    return MediaVC.monthF.string(from: d)
  }
  private func sig(_ m: Msg) -> Int { var h = Hasher(); h.combine(m.file?.id); h.combine(m.link); h.combine(m.text); return h.finalize() }
  private func reload(animated: Bool, layout: Bool) {
    let list = items(shown)
    byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var snap = NSDiffableDataSourceSnapshot<String, String>()
    if list.isEmpty { snap.appendSections(["empty"]); snap.appendItems(["empty"], toSection: "empty") }
    for m in list {
      let s = month(m.at)
      if !snap.sectionIdentifiers.contains(s) { snap.appendSections([s]) }
      snap.appendItems([m.id], toSection: s)
    }
    // (only what changed is set again)
    let new = Dictionary(list.map { ($0.id, sig($0)) }, uniquingKeysWith: { a, _ in a })
    let old = data.snapshot()
    snap.reconfigureItems(snap.itemIdentifiers.filter { old.indexOfItem($0) != nil && sigs[$0] != nil && sigs[$0] != new[$0] })
    sigs = new
    if layout {
      // (another tab: its own items and layout, no animation between them)
      UIView.performWithoutAnimation {
        cv.setCollectionViewLayout(self.layout(), animated: false)
        data.applySnapshotUsingReloadData(snap)
      }
      cv.setContentOffset(CGPoint(x: 0, y: -cv.adjustedContentInset.top), animated: false)
    } else { data.applySteady(snap, in: cv, animated: animated) }
  }
  private func layout() -> UICollectionViewLayout {
    UICollectionViewCompositionalLayout { [weak self] s, env in
      let empty = self?.data?.sectionIdentifier(for: s) == "empty"
      if self?.shown == .media && !empty {
        let w = NSCollectionLayoutDimension.fractionalWidth(0.25)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: w, heightDimension: .fractionalWidth(0.25)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        let g = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.25)), subitems: [item])
        let sec = NSCollectionLayoutSection(group: g)
        let h = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(36)), elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        sec.boundarySupplementaryItems = [h]
        return sec
      }
      var c = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
      c.backgroundColor = .clear; c.headerMode = empty ? .none : .supplementary
      if empty { c.showsSeparators = false }
      let sec = NSCollectionLayoutSection.list(using: c, layoutEnvironment: env)
      if empty { sec.contentInsets.top = 140 }
      return sec
    }
  }
  private func fillRow(_ c: UICollectionViewListCell, _ m: Msg) {
    var cfg = UIListContentConfiguration.subtitleCell()
    cfg.textProperties.font = .systemFont(ofSize: 16); cfg.secondaryTextProperties.color = .secondaryLabel; cfg.secondaryTextProperties.font = .systemFont(ofSize: 13)
    cfg.imageToTextPadding = 12
    let who = Talk.shared.name(m.by), when = Look.time(m.at)
    if let f = m.file {
      let ext = (f.name as NSString).pathExtension
      cfg.text = f.name
      cfg.secondaryText = [ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file), who, when].joined(separator: " · ")
      cfg.image = BubbleCell.docIcon(ext.isEmpty ? "file" : ext); cfg.imageProperties.reservedLayoutSize = CGSize(width: 38, height: 46); cfg.imageProperties.maximumSize = CGSize(width: 32, height: 42)
    } else if let l = m.link {
      cfg.text = l.title.flatMap { $0.isEmpty ? nil : $0 } ?? l.url
      let site = l.e11 == "folder" ? "E11 Console · Folder" : l.e11 == "file" ? "E11 Console · File" : l.site ?? URL(string: l.url)?.host ?? ""
      cfg.secondaryText = [site, who].joined(separator: " · ")
      cfg.imageProperties.reservedLayoutSize = CGSize(width: 52, height: 52); cfg.imageProperties.maximumSize = CGSize(width: 52, height: 52)
      cfg.imageProperties.cornerRadius = 8
      cfg.image = linkPic(m, l) ?? UIImage(systemName: l.e11 == "folder" ? "folder" : l.e11 == "file" ? "doc" : m.task != nil ? "checkmark.square" : "link")
      if cfg.image?.isSymbolImage == true { cfg.imageProperties.tintColor = .label; cfg.imageProperties.maximumSize = CGSize(width: 26, height: 26) }
    }
    c.contentConfiguration = cfg
    var b = UIBackgroundConfiguration.listGroupedCell(); b.backgroundColor = .secondarySystemGroupedBackground; c.backgroundConfiguration = b
  }
  // (a link's picture: its preview's, or an E11 link's page picture — fetched once, then the row set again)
  private var linkPics: [String: UIImage] = [:]
  private func linkPic(_ m: Msg, _ l: Msg.LinkPrev) -> UIImage? {
    if let id = l.img { return UIImage(contentsOfFile: Net.local(id).path) }
    guard let p = l.pic else { return nil }
    if let i = linkPics[p] { return i }
    Net.shared.picture(p, max: p.hasSuffix("/view") ? 300 : 160) { [weak self] i in
      guard let self = self, let i = i, self.linkPics[p] == nil else { return }
      self.linkPics[p] = i
      // (the next turn, never inside the list's own update: a picture already kept answers at once, while the row is being
      //  drawn — setting the list again from there stopped the app on the Links tab, Haris 2026-11-13)
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        var s = self.data.snapshot(); if s.indexOfItem(m.id) != nil { s.reconfigureItems([m.id]); self.data.applySteady(s, in: self.cv, animated: false) }
      }
    }
    return nil
  }

  // ---------- tapping ----------
  func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
    cv.deselectItem(at: ip, animated: true)
    guard let id = data.itemIdentifier(for: ip), let m = byId[id] else { return }
    switch shown {
    case .media: openMedia(m)
    case .files: openFile(m, from: cv.cellForItem(at: ip))
    case .links: if let s = m.link?.url, let u = URL(string: s) { UIApplication.shared.open(u) }
    }
  }
  private var chat: ChatVC? { navigationController?.viewControllers.last(where: { ($0 as? ChatVC)?.group == group }) as? ChatVC }
  private func showInChat(_ m: Msg) {
    guard let nav = navigationController, let c = chat else { return }
    nav.popToViewController(c, animated: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { c.jump(to: m.id) }
  }
  private func openMedia(_ m: Msg) {
    let all = items(.media).reversed() as [Msg]
    guard let i = all.firstIndex(where: { $0.id == m.id }) else { return }
    let v = PhotoViewerVC(items: all, at: i)
    v.source = { [weak self] x in
      guard let self = self, let ip = self.data.indexPath(for: x.id), let c = self.cv.cellForItem(at: ip) as? PicCell, c.window != nil else { return nil }
      return (c.img, c.img.bounds)
    }
    v.onShow = { [weak self] x in self?.showInChat(x) }
    v.onReply = { [weak self] x in guard let self = self, let c = self.chat else { return }; self.navigationController?.popToViewController(c, animated: true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { c.startReply(x) } }
    v.onForward = { [weak self] x in self?.forward(x) }
    v.onDelete = { [weak self] x in guard let self = self else { return }; self.chat?.askDelete([x], from: self) }
    v.onReact = { [weak self, weak v] x in
      let s = EmojiSheet(mine: x.reactions[Talk.shared.me?.id ?? ""]) { e in self?.chat?.react(x, e) }
      let n = UINavigationController(rootViewController: s)
      if let sh = n.sheetPresentationController { sh.detents = [.medium(), .large()]; sh.prefersGrabberVisible = true }
      v?.present(n, animated: true)
    }
    present(v, animated: false)
  }
  private func openFile(_ m: Msg, from cell: UIView?) {
    guard let f = m.file else { return }
    Net.shared.file(f.id) { [weak self] url in
      guard let self = self, let url = url else { toast("That file isn’t on the server any more"); return }
      // (Quick Look wants the name's extension)
      let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
      try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
      self.previewURL = named; self.openFrom = cell
      let q = QLPreviewController(); q.dataSource = self; q.delegate = self
      self.present(q, animated: true)
    }
  }
  func numberOfPreviewItems(in c: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
  func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { previewURL! as NSURL }
  func previewController(_ c: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? { openFrom }
  private func forward(_ m: Msg) {
    let n = UINavigationController(rootViewController: ForwardVC(msgs: [m], from: group))
    if let s = n.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
    present(n, animated: true)
  }
  private func share(_ m: Msg, from v: UIView?) {
    if let l = m.link, let u = URL(string: l.url) { presentShare([u], v); return }
    guard let f = m.file else { return }
    Net.shared.file(f.id) { [weak self] url in
      guard let self = self, let url = url else { toast("That file isn’t on the server any more"); return }
      let named = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
      try? FileManager.default.removeItem(at: named); try? FileManager.default.copyItem(at: url, to: named)
      self.presentShare([named], v)
    }
  }
  private func presentShare(_ xs: [Any], _ v: UIView?) {
    let a = UIActivityViewController(activityItems: xs, applicationActivities: nil)
    a.popoverPresentationController?.sourceView = v ?? view
    present(a, animated: true)
  }

  // ---------- holding: Apple's lift and menu ----------
  func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemsAt ips: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
    guard let ip = ips.first, let id = data.itemIdentifier(for: ip), let m = byId[id] else { return nil }
    let cell = cv.cellForItem(at: ip)
    return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
      guard let self = self else { return nil }
      var acts: [UIMenuElement] = [
        UIAction(title: "Show in Chat", image: UIImage(systemName: "bubble.left")) { [weak self] _ in self?.showInChat(m) },
        UIAction(title: "Forward", image: UIImage(systemName: "arrowshape.turn.up.right")) { [weak self] _ in self?.forward(m) },
      ]
      if m.kind == "photo" || m.kind == "video" { acts.append(UIAction(title: "Save to Photos", image: UIImage(systemName: "square.and.arrow.down")) { _ in ChatVC.saveAll([m]) }) }
      acts.append(UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share(m, from: cell) })
      var kids: [UIMenuElement] = [UIMenu(options: .displayInline, children: acts)]
      if m.by == Talk.shared.me?.id {
        kids.append(UIMenu(options: .displayInline, children: [UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
          guard let self = self else { return }; self.chat?.askDelete([m], from: self)
        }]))
      }
      return UIMenu(children: kids)
    }
  }
}

// a square of the grid: the photo or the video's first frame, ▶ and its length on a video
final class PicCell: UICollectionViewCell {
  let img = UIImageView(); private let play = UILabel()
  private var want: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    img.contentMode = .scaleAspectFill; img.clipsToBounds = true; img.backgroundColor = .tertiarySystemFill
    img.frame = contentView.bounds; img.autoresizingMask = [.flexibleWidth, .flexibleHeight]; contentView.addSubview(img)
    play.font = .systemFont(ofSize: 11, weight: .semibold); play.textColor = .white
    play.layer.shadowColor = UIColor.black.cgColor; play.layer.shadowOpacity = 0.6; play.layer.shadowRadius = 2; play.layer.shadowOffset = .zero
    play.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(play)
    NSLayoutConstraint.activate([play.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6), play.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)])
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ m: Msg) {
    guard let f = m.file else { return }
    want = f.id
    if m.kind == "video" { let s = Int(f.secs ?? 0); play.text = "▶ \(s / 60):" + String(format: "%02d", s % 60); play.isHidden = false } else { play.isHidden = true }
    if let i = BubbleCell.cached(f.id) ?? ZoomPage.small(m, f) { img.image = i; return }
    img.image = nil
    ZoomPage.thumb(m, f) { [weak self] i in guard let self = self, self.want == f.id else { return }; self.img.image = i }
  }
}
