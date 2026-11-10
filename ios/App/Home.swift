import UIKit
import CoreImage

// (who's in the pictures and who has a photo: redrawn when that changes — a photo arriving later too)
func picsKey(_ p: [String: [String: Any]]) -> String { p.keys.sorted().map { $0 + (p[$0]?["photo"] != nil ? "+" : "") }.joined(separator: ",") }

/* ================= Home (E11 Day / My Day), drawn by the app itself (23+, Haris 2026-10-31) =================
   The same page as the website's phone Home (phone.js myDay / card, phone.css .ph-head / .ph-stats / .ph-gh / .pc),
   only scrolled and tapped by iPhone itself. The page stays the engine: it sends what to show — the header, the three
   boxes, the groups and their task cards, and the colours of its own Home drawn under this one (light / dark) — with
   the "home" command whenever something changes (NativeHome in phone.js), and the taps go back to it
   (window.__e11Home: open a task, Search, Me, New task). */
final class HomeView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UITextFieldDelegate {
  var onEvent: (([String: Any]) -> Void)?
  var present: ((UIViewController) -> Void)?
  private var canDelete = false
  private var toastView: UIView?
  /* The header (Haris, 2026-10-31, as Mail): at the top the big title with the date over it; as the list scrolls it
     shrinks as it rises into a small bar — the small title with the date under it — and the cards pass under it
     through a soft blur. Search is a Liquid Glass circle that stretches into a glass search bar; your photo then
     turns into a glass ✕ that closes it. */
  private let blur = UIVisualEffectView(effect: nil), hairline = UIView(), blurMask = CAGradientLayer()
  // the bar's own row (the small title on it): on iOS 26+ iPhone's own scroll edge effect frosts the list under it, as in Mail
  private let topBar = HomePassThrough(), topLine = UIView()
  private var edgeHook: AnyObject?
  private let frostReach = FrostReach()   // (the soft frost's area reaching a little below the bar, as Mail's)
  private var reachK: CGFloat = 0
  // THE FROST BAR — LOCKED (Haris 2026-11-03): two kinds of page.
  //  • the soft one (iPhone's soft frost as strong as Mail's — FrostReach — and no line): a page with its name in the middle
  //    of the bar and nothing stuck under it (a client's page, Client Assets, My profile, About…);
  //  • the Inbox's (iPhone's firm frost, even down to the line, and the line): every other page — big titles (Home, My Tasks,
  //    Inbox, Clients, Me) and pages with search / filters stuck under the bar (Trash, Team members, the task page).
  //  Both: nothing at the top of a page; they come in once something is under the bar (the firm one fades in where iPhone
  //  lets it).
  var softFrost: Bool { pageBar && pinHead == nil }
  // (never while the page is at its top or bouncing above it — Haris 2026-11-03: the frost flashed on the bounce)
  private var underBar: Bool { pinned || scroll.contentOffset.y > -scroll.contentInset.top + 0.5 && (dLine > 0.001 || pageBar) }
  private func applyFrost() {
    guard #available(iOS 26.0, *) else { return }
    let style: UIScrollEdgeEffect.Style = softFrost ? .soft : .hard
    if scroll.topEdgeEffect.style != style { scroll.topEdgeEffect.style = style }
    if softFrost { if scroll.topEdgeEffect.isHidden { scroll.topEdgeEffect.isHidden = false } } else { Frost.show(scroll, underBar || searching) }
    // (the line under the bar is iPhone's own, the firm frost's — ours is gone: two lines, ours moving into iPhone's —
    //  Haris 2026-11-03)
    topLine.alpha = 0
    reachK = softFrost ? (underBar ? 1 : 0) : 0
    placeReach()
  }
  // (it reaches below the bar only as the line comes in — at the top of a page the big title stays clear; not while My
  //  Tasks' filters are stuck: that firm frost ends at the line)
  private func placeReach() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    frostReach.frame = CGRect(x: 0, y: 0, width: bounds.width, height: topBar.frame.height + (!softFrost || searching ? 0 : FrostReach.extra * reachK))
    CATransaction.commit()
  }
  /* Mail's own measures (Haris, 2026-10-31, from his Mail screenshots): the bar's buttons 44 pt, 16 from the right
     edge, 12 apart, their middle 22 under the status bar; the bar 54 under it; the small title 17 semibold with the
     line under it 12 regular; the big title 34 bold, 16 from the left, the line under it 15 regular; system colours */
  private let R: CGFloat = 16, BTN: CGFloat = 44
  private let sub = UILabel(), title = UILabel(), smallTitle = UILabel(), smallSub = UILabel()
  private let searchCircle = HomeGlass(), me = UIButton(type: .custom), closeCircle = HomeGlass()
  private let searchBar = HomeGlass(), field = UITextField(), lens = UIImageView()
  private let results = UIScrollView(), hint = UILabel()
  private var resultViews: [UIView] = [], resultCards: [String: HomeCard] = [:], resultFiles: [String: FileListRow] = [:]
  private(set) var searching = false
  private(set) var closingSearch = false        // (✕ tapped: the bar shrinking back into 🔍 — your photo is already coming back)
  private(set) var searchClosedAt: Date?
  /* The corner button (shell 30, Haris 2026-11-01): Search here, Mark all read / unread on the Inbox and ••• on a
     task page are one glass button of the app's (CornerButton, Main): this screen's own ones then stay invisible and
     only say where the button goes and what it is. */
  var cornerShared = false { didSet { searchCircle.alpha = cornerShared || searching ? 0 : 1; markAll.alpha = cornerShared ? 0 : 1; me.isHidden = cornerShared; if cornerShared { closeCircle.isHidden = true } } }
  // (the shared top buttons: your photo — where, what, and its tap)
  // (its place at full size — while searching it's shrunk away, and the ✕ that takes its place came out shrunk too)
  var meFrame: CGRect { CGRect(x: me.center.x - me.bounds.width / 2, y: me.center.y - me.bounds.height / 2, width: me.bounds.width, height: me.bounds.height) }
  var meImage: UIImage? { me.image(for: .normal) }
  func meTap() { send(["ev": "me"]) }
  var onCorner: (() -> Void)?
  // (shown or hidden — a tab changed: the corner button goes to this screen's, or away)
  override var isHidden: Bool { didSet { if oldValue != isHidden { onCorner?(); onAppleCorner?(); if !isHidden { onShown?() } } } }
  var onShown: (() -> Void)?   // (shown again: what changed while it was hidden is drawn — Main's Home)
  // what the corner is here: "search", "read", "unread" or "none", and where (its right edge left of your photo)
  func corner() -> (kind: String, text: String, frame: CGRect) {
    let f = searchCircle.frame
    if searching || closingSearch || isHidden { return ("none", "", f) }
    guard isInbox else { return ("search", "", f) }
    if !markAll.isHidden { return ("read", "Mark all read", f) }
    let rows = content.compactMap { $0 as? InboxRow }
    return rows.isEmpty ? ("none", "", f) : ("unread", "Mark all unread", f)
  }
  // the corner button tapped
  func cornerTap(_ kind: String) {
    switch kind {
    case "search": UIImpactFeedbackGenerator(style: .light).impactOccurred(); openSearch()
    case "read": UIImpactFeedbackGenerator(style: .light).impactOccurred(); send(["ev": "readAll"])
    case "unread":
      // only the ones in the list on screen — and asked first (Haris, 2026-11-01)
      let ids = content.compactMap { ($0 as? InboxRow)?.id }
      guard !ids.isEmpty else { return }
      let a = UIAlertController(title: "Mark all unread?", message: "The \(ids.count) update\(ids.count == 1 ? "" : "s") in this list will show as unread again.", preferredStyle: .alert)
      a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      a.addAction(UIAlertAction(title: "Mark unread", style: .default) { [weak self] _ in self?.send(["ev": "unreadList", "ids": ids]) })
      present?(a)
    default: break
    }
  }
  private var findTimer: Timer?, keyboardH: CGFloat = 0
  private let scroll = UIScrollView()
  /* Home in iPhone's own navigation (AppleHome.swift, Haris 2026-11-07): Apple's bar has the big title, the date, 🔍 and
     your photo, and Apple's search bar; this screen's own header, buttons and search bar stay out of it. The list,
     cards and boxes are as they were. */
  private(set) var appleTop = false
  var onAppleTitle: ((String, String) -> Void)?
  var onAppleMe: ((UIImage?) -> Void)?
  var onAppleResign: (() -> Void)?
  var onAppleFilters: (([String: Any]) -> Void)?
  var onAppleCorner: (() -> Void)?   // (the Inbox: Mark all read / unread changed — its own screen's bar button follows)   // (My Tasks: its tab, filter buttons and chips — its own screen's bar shows them)
  private let catsWrap = UIView()   // (the Inbox under Apple's bar: Mail's buttons as the first row of Apple's list)
  func menuEvent(_ e: [String: Any]) { send(e) }
  var appleScroll: UIScrollView { listOn ? sv : searching ? results : sv }
  // Home's list as Apple's own list (Haris 2026-11-07: "I like Apple's list"): the same cards, headings and boxes, each
  // in a cell of iPhone's list — Apple's swipe actions (Done · Due, Copy link · Delete) and Apple's animation when cards
  // come, go or move
  private var list: UICollectionView?
  private var listDS: UICollectionViewDiffableDataSource<Int, String>?
  private var listViews: [String: UIView] = [:]
  private var blockWraps: [ObjectIdentifier: BlockWrap] = [:]
  // (Me's pages in Apple's list — AppleMe.swift: their rows, sections, switches, held rows and pictures)
  fileprivate var meItems: [String: SetItem] = [:]
  fileprivate var meSecs: [Int: MeSec] = [:]
  fileprivate var meSwitches: [String: UISwitch] = [:]
  fileprivate var meHolds: [String: MeHold] = [:]
  fileprivate var mePics: [String: UIImage] = [:]
  fileprivate var mePicAsked = Set<String>()
  fileprivate var meDrawn: [String: String] = [:]
  private var listDrawn: [String: String] = [:]
  // (the groups' headings and "nothing due" lines kept by their group in Apple's list — made new on every draw before)
  private var heads: [String: UILabel] = [:], empties: [String: UILabel] = [:]
  private var listOn: Bool { list != nil }
  private var sv: UIScrollView { list ?? scroll }
  private let statsRow = UIView()
  func useAppleTop() {
    guard !appleTop else { return }
    appleTop = true
    scroll.contentInsetAdjustmentBehavior = .automatic
    scroll.automaticallyAdjustsScrollIndicatorInsets = true
    scroll.contentInset.top = 6
    results.contentInsetAdjustmentBehavior = .automatic
    results.automaticallyAdjustsScrollIndicatorInsets = true
    if #available(iOS 26.0, *) {
      scroll.topEdgeEffect.style = .automatic; results.topEdgeEffect.style = .automatic
      if let i = edgeHook as? UIScrollEdgeElementContainerInteraction { topBar.removeInteraction(i) }
      edgeHook = nil
    }
    frostReach.isHidden = true
    [topBar, blur, title, sub, smallTitle, smallSub, searchCircle, me, searchBar, closeCircle].forEach { $0.isHidden = true }
    onAppleTitle?(title.attributedText?.string ?? "", sub.text ?? "")
    onAppleMe?(me.image(for: .normal))
    if assets == nil || assets == "client" || assets == "folder" || assets == "all" || isMeList { makeAppleList() }   // (Me and its pages too — AppleMe.swift)   // (the Clients tab's pages and Client Assets' too — AppleClients.swift)
    // (My Tasks: its filter rows and chips are in Apple's bar's menu now — taken out; All / Done goes into the list)
    // (My Tasks: its filters are in Apple's bar's menu, All / Done in Apple's search bar's scope bar — the rows taken out)
    if isList && !isInbox { listHead.removeFromSuperview(); if let f = lastFilters { onAppleFilters?(f) } }
    // (the Inbox: Mail's buttons go into the list, Mark all read into Apple's bar — HomeView's own taken out)
    if isInbox { listHead.removeFromSuperview(); markAll.removeFromSuperview(); catsWrap.addSubview(catsView); if !content.isEmpty { applyList(animated: false) }; onAppleCorner?() }
    // (the Clients tab's pages and Client Assets': what's drawn already goes into Apple's list)
    if (isClients || isClient || assets != nil || !cards.isEmpty), listOn, !content.isEmpty { applyList(animated: false) }
    setNeedsLayout()
  }
  private func makeAppleList() {
    var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
    cfg.showsSeparators = false
    cfg.backgroundColor = .clear
    cfg.trailingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipeActions(ip, leading: false) }
    cfg.leadingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipeActions(ip, leading: true) }
    let layout = UICollectionViewCompositionalLayout { [weak self] i, env in
      // (Me and its pages: iPhone Settings' own grouped sections — AppleMe.swift)
      if let self = self, self.isMeList, let g = self.meSection(i), g.grouped { return self.meGrouped(g, env) }
      // (a group of tasks — or of clients found — is one of Apple's inset groups, its heading Apple's header: Haris
      //  2026-11-09, Home fully Apple)
      // (folders and files as the Files app's grid — Apple's own sections: a sideways-scrolling row on a client's page,
      //  three across in Client Assets; Haris 2026-11-10)
      if let self = self, i < self.listSecs.count, self.listSecs[i].tiles != .none { return self.tileSection(self.listSecs[i], env) }
      if let self = self, !self.isMeList || self.searching, i < self.listSecs.count, self.listSecs[i].rows {
        var gc = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        gc.backgroundColor = .clear
        gc.separatorConfiguration.color = HomeLook.line   // (Apple's line, a little softer — every Apple page)
        gc.headerMode = self.listSecs[i].head != nil ? .supplementary : .none
        gc.trailingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipeActions(ip, leading: false) }
        gc.leadingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipeActions(ip, leading: true) }
        return NSCollectionLayoutSection.list(using: gc, layoutEnvironment: env)
      }
      // (the Inbox's rows: Apple's plain list, edge to edge as Mail's, Apple's line between them — none under Mail's
      //  buttons or the last row; the Inbox's lines stay Apple's own colour: Haris 2026-11-10)
      let inbox = self?.isInbox == true
      var ic = cfg
      if inbox {
        ic.showsSeparators = true
        ic.itemSeparatorHandler = { [weak self] ip, sc in
          var c = sc
          guard let self = self, let ds = self.listDS, let key = ds.itemIdentifier(for: ip) else { return c }
          let items = ds.snapshot().itemIdentifiers(inSection: ds.snapshot().sectionIdentifiers[ip.section])
          if !(self.listViews[key] is InboxRow) || key == items.last { c.bottomSeparatorVisibility = .hidden }
          c.topSeparatorVisibility = .hidden
          return c
        }
      }
      let sec = NSCollectionLayoutSection.list(using: inbox ? ic : cfg, layoutEnvironment: env)
      sec.interGroupSpacing = inbox ? 0 : 10
      // (a pushed page — a client's, Client Assets, a folder, Me's pages: its first thing clear of Apple's bar and its frost,
      //  as the task page — 4 pt put it under the frost's reach, so the frost and its line showed at rest: Haris 2026-11-08)
      let top: CGFloat = (i == 0 && self?.pushedList == true) ? 18 : 4
      sec.contentInsets = inbox ? NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0) : NSDirectionalEdgeInsets(top: top, leading: 16, bottom: 0, trailing: 16)
      return sec
    }
    let cv = UICollectionView(frame: bounds, collectionViewLayout: layout)
    cv.backgroundColor = .clear
    cv.alwaysBounceVertical = true
    cv.contentInsetAdjustmentBehavior = .automatic
    cv.allowsSelection = true   // (a task's or a client's row: Apple's selection opens it; nothing else highlights)
    cv.delegate = self
    if #available(iOS 26.0, *) { cv.topEdgeEffect.style = .automatic }
    let reg = UICollectionView.CellRegistration<HostCell, String> { [weak self] cell, _, key in
      guard let self = self, let v = self.listViews[key] else { cell.host(nil, height: 1); return }
      cell.host(v, height: self.itemHeight(key, v))
    }
    // (Me's rows: Apple's own list cells, set by Apple's configurations — iPhone Settings')
    let setReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in self?.paintMe(cell, key) }
    // (a task or a client found: Apple's own cell — HomeCard / HomeClientRow give its content; a group's "nothing due" line:
    //  Apple's cell with its words)
    let rowReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
      guard let self = self, let r = self.listViews[key] as? AppleRow else { return }
      self.paintRow(cell, r)
    }
    // (search's rows — a task or a client found — their own cells, never handed to a list's row: a cell that had shown a
    //  task found, its title washed where the words matched, kept that wash when given to Home's row of the same task —
    //  the same words, only the wash different: Haris 2026-11-09, closing search with the x inside the bar)
    let foundReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
      guard let self = self, let r = self.listViews[key] as? AppleRow else { return }
      self.paintRow(cell, r)
    }
    // (a folder or a file: its tile in a cell of Apple's grid)
    let tileReg = UICollectionView.CellRegistration<TileCell, String> { [weak self] cell, _, key in
      guard let t = self?.listViews[key] as? FileTile else { return }
      cell.show(t)
    }
    // (an Inbox row: Apple's own cell — InboxRow gives its content, its dot and its time)
    let inboxReg = UICollectionView.CellRegistration<InboxCell, String> { [weak self] cell, _, key in
      guard let r = self?.listViews[key] as? InboxRow else { return }
      cell.show(r)
    }
    // (Apple's own empty state — AppleEmpty)
    let unavailReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
      (self?.listViews[key] as? AppleEmpty)?.paint(cell)
    }
    let emptyReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
      guard let self = self else { return }
      var c = UIListContentConfiguration.cell()
      c.text = (self.listViews[key] as? UILabel)?.text
      c.textProperties.font = .systemFont(ofSize: 14); c.textProperties.color = self.L.empty
      cell.contentConfiguration = c
      cell.accessories = []
      var bg = UIBackgroundConfiguration.listGroupedCell(); bg.backgroundColor = self.L.card; cell.backgroundConfiguration = bg
    }
    let isMe = isMeList
    listDS = UICollectionViewDiffableDataSource<Int, String>(collectionView: cv) { [weak self] cv, ip, key in
      if isMe && (key.hasPrefix("s:") || key == "me:card") { return cv.dequeueConfiguredReusableCell(using: setReg, for: ip, item: key) }
      if let v = self?.listViews[key] {
        if v is AppleRow { return cv.dequeueConfiguredReusableCell(using: key.hasPrefix("f:") || v is HomeClientRow ? foundReg : rowReg, for: ip, item: key) }
        if v is InboxRow { return cv.dequeueConfiguredReusableCell(using: inboxReg, for: ip, item: key) }
        if v is FileTile { return cv.dequeueConfiguredReusableCell(using: tileReg, for: ip, item: key) }
        if v is AppleEmpty { return cv.dequeueConfiguredReusableCell(using: unavailReg, for: ip, item: key) }
        if key.hasPrefix("e:") && v.tag == 8 { return cv.dequeueConfiguredReusableCell(using: emptyReg, for: ip, item: key) }
      }
      return cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: key)
    }
    if !isMe {
      // (a group's heading: Apple's header over its inset group — our words, its client's dot)
      let head = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] v, _, ip in
        var c = UIListContentConfiguration.groupedHeader()
        if let self = self, ip.section < self.listSecs.count { c.attributedText = self.listSecs[ip.section].head }
        v.contentConfiguration = c
        // (a client's folders: See All at the header's right — Apple's button, as the App Store's rows)
        // (and a folder's files: Select / Cancel)
        if let self = self, ip.section < self.listSecs.count, let all = self.listSecs[ip.section].seeAll {
          let b = UIButton(type: .system); b.setTitle(all.0, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 15)
          // ("See all ›" as the mock-up: Apple's small chevron after the words)
          if all.0 == "See all" { b.setImage(UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)), for: .normal); b.semanticContentAttribute = .forceRightToLeft; b.imageEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4) }
          let key = all.2
          b.addAction(UIAction { [weak self] _ in UISelectionFeedbackGenerator().selectionChanged(); self?.tileSeeAll[key]?.1() }, for: .touchUpInside); b.sizeToFit()
          v.accessories = [.customView(configuration: .init(customView: b, placement: .trailing(), reservedLayoutWidth: .actual))]
        } else if !v.accessories.isEmpty { v.accessories = [] }   // (only taken off a header that had one)
      }
      listDS?.supplementaryViewProvider = { cv, _, ip in cv.dequeueConfiguredReusableSupplementary(using: head, for: ip) }
    }
    if isMe {
      let head = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] v, _, ip in
        var c = UIListContentConfiguration.groupedHeader(); c.text = self?.meSection(ip.section)?.head; c.textProperties.font = .systemFont(ofSize: 13); c.textProperties.color = .secondaryLabel; v.contentConfiguration = c   // (Apple's header at the size Me had: 13 grey — Haris 2026-11-08)
      }
      let foot = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] v, _, ip in
        var c = UIListContentConfiguration.groupedFooter()
        if let f = self?.meSection(ip.section)?.foot { c.attributedText = f; c.textProperties.alignment = (self?.meSection(ip.section)?.footCentred ?? false) ? .center : .natural }
        v.contentConfiguration = c
      }
      listDS?.supplementaryViewProvider = { cv, kind, ip in
        kind == UICollectionView.elementKindSectionHeader ? cv.dequeueConfiguredReusableSupplementary(using: head, for: ip) : cv.dequeueConfiguredReusableSupplementary(using: foot, for: ip)
      }
    }
    stats.forEach { statsRow.addSubview($0) }
    insertSubview(cv, aboveSubview: scroll)
    scroll.isHidden = true
    list = cv
  }
  // each thing's height in the list (as the list had them)
  private func itemHeight(_ key: String, _ v: UIView) -> CGFloat {
    let w = bounds.width - 32
    if let b = v as? BlockWrap { return b.block.blockHeight(bounds.width) }
    if key == "stats" { return 80 }
    if key == "cats" { return MailCats.H + 10 }
    if v === hint { return (hint.sizeThatFits(CGSize(width: w, height: 400)).height) + 28 }
    if let n = v as? SearchFixedNote { return n.height(for: w) }
    if v.tag == 8 { return 28 + ((v as? UILabel)?.sizeThatFits(CGSize(width: w - 8, height: 400)).height ?? 17) }
    return 27
  }
  // the list as it is now: the boxes, then each group's heading, cards and "nothing due" line
  private func applyList(animated: Bool) {
    guard let ds = listDS else { return }
    if isMeList && !searching { applyMeList(animated: animated); return }   // (Me's pages: iPhone Settings' own sections)
    var views: [String: UIView] = [:], keys: [String] = []
    if searching {
      // (searching: the results are the list's rows — the hint, the groups' headings, clients, task cards)
      if let t = hint.text, !t.isEmpty { keys.append("e:hint"); views["e:hint"] = hint }
      for v in resultViews {
        // (a task found is its own row, not Home's row of the same task: one identity for both, Apple kept the found
        //  row's cell — the search's wash on its title — when search closed: Haris 2026-11-09)
        let k: String
        if let c = v as? HomeCard { k = "f:" + c.id }
        else if let f = v as? FileListRow { k = f.key }
        else if let e = v as? AppleEmpty { k = "u:" + (e.accessibilityIdentifier ?? "") }
        else { k = "r:\(ObjectIdentifier(v).hashValue)" }
        if views[k] != nil { continue }
        // (Client Assets' found files — a block: the whole width, as the list's — AppleClients.swift)
        if let b = v as? HomeBlock { let w = blockWraps[ObjectIdentifier(b)] ?? BlockWrap(b); blockWraps[ObjectIdentifier(b)] = w; keys.append(k); views[k] = w; continue }
        keys.append(k); views[k] = v
      }
    } else {
    if !noStats { keys.append("stats"); views["stats"] = statsRow }
    if isInbox && catsView.superview === catsWrap { keys.append("cats"); views["cats"] = catsWrap }
    for v in content {
      if let r = v as? InboxRow { let k = "r:" + r.id; keys.append(k); views[k] = r; continue }
      if let c = v as? HomeCard { let k = "c:" + c.id; keys.append(k); views[k] = c; continue }
      if let c = v as? ClientListRow { let k = "k:" + c.id; keys.append(k); views[k] = c; continue }
      if v is ClientsMoreRow { keys.append("k:inactive"); views["k:inactive"] = v; continue }
      // (a file's row: Recently added's, or one search found — its own identity, so a wash never stays: Haris 2026-11-10)
      if let r = v as? FileListRow { let k = r.key; if views[k] != nil { continue }; keys.append(k); views[k] = r; continue }
      if let e = v as? AppleEmpty { let k = "u:" + (e.accessibilityIdentifier ?? "\(ObjectIdentifier(e).hashValue)"); if views[k] != nil { continue }; keys.append(k); views[k] = e; continue }
      if let t = v as? FileTile { let k = t.key; if views[k] != nil { continue }; keys.append(k); views[k] = t; continue }
      // (the Clients tab's and Client Assets' blocks — the clients' group, folders, files: each a cell, the whole width)
      if let b = v as? HomeBlock {
        let k = "b:" + (b.accessibilityIdentifier ?? "\(ObjectIdentifier(b).hashValue)")
        if views[k] != nil { continue }
        let w = blockWraps[ObjectIdentifier(b)] ?? BlockWrap(b); blockWraps[ObjectIdentifier(b)] = w
        keys.append(k); views[k] = w; continue
      }
      if v.tag == 7 && v.isHidden { continue }   // (Today's mark: no heading on screen)
      let k = (v.tag == 8 ? "e:" : "h:") + (v.accessibilityIdentifier ?? "\(ObjectIdentifier(v).hashValue)")
      if views[k] != nil { continue }
      keys.append(k); views[k] = v
    }
    }
    listViews = views
    list?.backgroundView?.isHidden = searching
    blockWraps = blockWraps.filter { e in views.values.contains { $0 === e.value } }
    // (the groups, Apple's way — Haris 2026-11-09: a heading over tasks, or over clients found, and its rows are one of
    //  Apple's inset groups, the heading its header; Today's own run has no heading. Everything else — the boxes, a client's
    //  folders, the Inbox's rows, Client Assets' blocks — in plain sections as before)
    func isRow(_ k: String) -> Bool { let v = views[k]; return v is AppleRow || (k.hasPrefix("e:") && v?.tag == 8) }
    // (tiles: a client's folders in a sideways row, Client Assets' three across — their heading the section's header)
    let tileKind: ListSec.Tiles = isClient ? .strip : .grid
    func tiles(_ k: String) -> Bool { views[k] is FileTile }
    // (All Client Assets' clients: two across — mock-up 0 B)
    func kindOf(_ k: String) -> ListSec.Tiles { (views[k] as? FileTile)?.isClient == true ? .clients : tileKind }
    var secs: [[String]] = [], meta: [ListSec] = []
    for (n, k) in keys.enumerated() {
      if k.hasPrefix("h:"), let nx = keys[(n + 1)...].first(where: { !$0.hasPrefix("h:") }), isRow(nx) || tiles(nx) {
        let t = tiles(nx)
        secs.append([]); meta.append(ListSec(rows: !t, head: (views[k] as? UILabel)?.attributedText, tiles: t ? kindOf(nx) : .none, seeAll: t ? tileSeeAll[k].map { ($0.0, $0.1, k) } : nil, folders: (views[nx] as? FileTile)?.isFolder == true)); continue
      }
      let r = isRow(k), t = tiles(k)
      // (whether the group before holds tiles — read on the group itself: `meta.last?.tiles != .none` compared the optional
      //  with nil, so every row started a group of its own and each heading stood apart from its rows: Haris 2026-11-10 13:56)
      let lastTiles = meta.last.map { $0.tiles != ListSec.Tiles.none } ?? false
      if meta.last?.rows != r || lastTiles != t { secs.append([]); meta.append(ListSec(rows: r, head: nil, tiles: t ? kindOf(k) : .none, folders: (views[k] as? FileTile)?.isFolder == true)) }
      secs[secs.count - 1].append(k)
    }
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    for (i, x) in secs.enumerated() { snap.appendSections([i]); snap.appendItems(x, toSection: i) }
    // (a cell set again only when what it shows or its height changed — every cell set afresh on each draw broke the rule
    //  "only what changed changes": Haris 2026-11-08)
    let had = Set(ds.snapshot().itemIdentifiers)
    var sigs: [String: String] = [:]
    for k in secs.joined() {
      guard let v = views[k] else { continue }
      if let r = v as? AppleRow { sigs[k] = r.rowSig }
      else if let t = v as? FileTile { sigs[k] = t.sig }
      else if let e = v as? AppleEmpty { sigs[k] = e.sig }
      else if let r = v as? InboxRow { sigs[k] = r.rowSig }
      else if k.hasPrefix("e:") && v.tag == 8 { sigs[k] = ((v as? UILabel)?.text ?? "") + "|" + L.key }
      else { sigs[k] = "\(ObjectIdentifier(v).hashValue)|\(itemHeight(k, v))" }
    }
    let changed = secs.joined().filter { had.contains($0) && listDrawn[$0] != sigs[$0] }
    listDrawn = sigs
    if !changed.isEmpty { snap.reconfigureItems(changed); rowsSet += changed.count }
    // (a section that became a group, or stopped being one: its layout asked again)
    let kindsChanged = listSecs.map { "\($0.rows)\($0.tiles)\($0.folders)" } != meta.map { "\($0.rows)\($0.tiles)\($0.folders)" }
    listSecs = meta
    if kindsChanged { list?.collectionViewLayout.invalidateLayout() }
    // (the list's length changed: the motto asked again — an empty list switched to a full one left it over the rows:
    //  Haris 2026-11-10)
    ds.apply(snap, animatingDifferences: animated) { [weak self] in
      self?.refreshHeads(); self?.showMotto()
      if let self = self, let k = self.stripStart, let ip = ds.indexPath(for: k) { self.stripStart = nil; self.list?.scrollToItem(at: ip, at: .left, animated: false) }
    }
  }
  // (a row's picture came after it was drawn: the list set again — only that row changes, by its signature)
  func listAgain() { if listOn { applyList(animated: false) } }
  // a group: rows (Apple's inset group) or not, and its heading (Apple's header)
  struct ListSec {
    enum Tiles { case none, strip, grid, clients }
    let rows: Bool; let head: NSAttributedString?
    var tiles: Tiles = .none
    var seeAll: (String, () -> Void, String)? = nil   // (its words, what it does, its heading's key)
    var folders = false   // (tiles of folders — their own height: the folder's shape)
  }
  // a heading's button — See All (a client's folders: Client Assets), Select / Cancel (a folder's files) — by the heading's key
  var tileSeeAll: [String: (String, () -> Void)] = [:]
  // Apple's section for tiles: a sideways-scrolling row, or three across
  func tileSection(_ s: ListSec, _ env: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
    let sec: NSCollectionLayoutSection
    if s.tiles == .strip {
      let w = FileTile.stripW, h = FileTile.height(width: w, lines: 1, folder: s.folders)
      let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(w), heightDimension: .absolute(h)))
      let g = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(w), heightDimension: .absolute(h)), subitems: [item])
      sec = NSCollectionLayoutSection(group: g)
      sec.orthogonalScrollingBehavior = .continuous
      sec.interGroupSpacing = 6
      sec.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16)
    } else {
      let cl = s.tiles == .clients
      let cols: CGFloat = cl ? 2 : 3, gap: CGFloat = cl ? 14 : 10
      let w = floor((env.container.effectiveContentSize.width - 32 - gap * (cols - 1)) / cols), h = cl ? FileTile.clientHeight(width: w) : FileTile.height(width: w, lines: 2, folder: s.folders)
      let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(w), heightDimension: .absolute(h)))
      let g = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(h)), subitems: [item])
      g.interItemSpacing = .fixed(gap)
      sec = NSCollectionLayoutSection(group: g)
      sec.interGroupSpacing = cl ? 22 : 18
      sec.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16)
    }
    if s.head != nil {
      let hd = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(38)), elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
      sec.boundarySupplementaryItems = [hd]
    }
    return sec
  }
  private var listSecs: [ListSec] = []
  private static func headButton(_ v: UIView) -> UIButton? { (v as? UIButton) ?? v.subviews.lazy.compactMap { headButton($0) }.first }
  // the headers on screen with new words (a count changed) set again — only those
  private func refreshHeads() {
    guard let cv = list, !isMeList || searching else { return }
    let kind = UICollectionView.elementKindSectionHeader
    for ip in cv.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
      guard ip.section < listSecs.count, let v = cv.supplementaryView(forElementKind: kind, at: ip) as? UICollectionViewListCell,
            var c = v.contentConfiguration as? UIListContentConfiguration else { continue }
      // (its button's words — Select ↔ Cancel — crossfading in place)
      if let b = Self.headButton(v), let w = listSecs[ip.section].seeAll?.0, b.title(for: .normal) != w {
        UIView.transition(with: b, duration: 0.2, options: .transitionCrossDissolve) { b.setTitle(w, for: .normal); b.sizeToFit() }
      }
      let want = listSecs[ip.section].head
      if (c.attributedText == nil && want == nil) || (want != nil && c.attributedText?.isEqual(to: want!) == true) { continue }
      c.attributedText = want; v.contentConfiguration = c
    }
  }
  // a task's or a client's row: Apple's cell set by its content, our tag and faces at its right, Apple's ›; the cell in
  // the card's colour, Apple's highlight when it's tapped
  private func paintRow(_ cell: UICollectionViewListCell, _ r: AppleRow) {
    cell.contentConfiguration = r.rowContent
    var acc: [UICellAccessory] = []
    if r.rowHasAccessory { acc.append(.customView(configuration: .init(customView: r, placement: .trailing(), reservedLayoutWidth: .actual, maintainsFixedSize: true))) }
    if r.rowChevron { acc.append(.disclosureIndicator()) }
    cell.accessories = acc
    let card = HomeCard.rowColor(L.card, late: r.rowLate)
    cell.configurationUpdateHandler = { c, state in
      var bg = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
      if !state.isHighlighted && !state.isSelected { bg.backgroundColor = card }
      c.backgroundConfiguration = bg
    }
  }
  // Apple's swipe actions: right — Done · Due; left — Copy link · Delete (as our round buttons did)
  private func swipeActions(_ ip: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
    if let key = listDS?.itemIdentifier(for: ip), let row = listViews[key] as? InboxRow {
      guard leading else { return nil }
      let a = UIContextualAction(style: .normal, title: row.read ? "Unread" : "Read") { [weak row] _, _, finish in
        UIImpactFeedbackGenerator(style: .light).impactOccurred(); row?.onToggle?(); finish(true)
      }
      a.image = UIImage(systemName: row.read ? "envelope.fill" : "envelope.open.fill")
      a.backgroundColor = .systemBlue
      let cfg = UISwipeActionsConfiguration(actions: [a]); cfg.performsFirstActionWithFullSwipe = true
      return cfg
    }
    // (My Tasks' Done tab: completed tasks are read only — no swipes, as no hold)
    guard let key = listDS?.itemIdentifier(for: ip), let card = listViews[key] as? HomeCard, !(isList && listTab == "done") else { return nil }
    let d = card.info
    var acts: [UIContextualAction] = []
    if leading {
      if (d["canDone"] as? Bool) == true {
        let done = (d["done"] as? Bool) == true, hold = (d["cdHold"] as? Bool) == true
        let a = UIContextualAction(style: .normal, title: hold ? "Review" : done ? "Not Done" : "Done") { [weak self, weak card] _, _, finish in
          guard let self = self, let card = card else { return finish(false) }
          let wasDone = (card.info["done"] as? Bool) == true, ready = (card.info["doneReady"] as? Bool) == true
          if !wasDone && ready { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
          self.send(["ev": "done", "id": card.id, "done": !wasDone, "card": card.info]); self.findAgain()
          finish(true)
        }
        a.image = UIImage(systemName: hold ? "person.badge.clock" : done ? "arrow.uturn.backward" : "checkmark")
        a.backgroundColor = hold ? TaskSwipe.orange.withAlphaComponent(0.5) : done ? TaskSwipe.grey : TaskSwipe.green
        acts.append(a)
      }
      if (d["canDue"] as? Bool) == true {
        let a = UIContextualAction(style: .normal, title: "Due") { [weak self, weak card] _, _, finish in
          guard let self = self, let card = card else { return finish(false) }
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          self.send(["ev": "due", "id": card.id, "card": card.info]); self.findAgain()
          finish(true)
        }
        a.image = UIImage(systemName: "calendar")
        a.backgroundColor = TaskSwipe.purple
        acts.append(a)
      }
    } else {
      if canDelete {
        let a = UIContextualAction(style: .destructive, title: "Trash") { [weak self, weak card] _, _, finish in
          guard let self = self, let card = card else { return finish(false) }
          self.askTrash(card, finish: finish)
        }
        a.image = UIImage(systemName: "trash")
        acts.append(a)
      }
      let c = UIContextualAction(style: .normal, title: "Copy link") { [weak self, weak card] _, _, finish in
        guard let self = self, let card = card else { return finish(false) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.send(["ev": "copy", "id": card.id])
        finish(true)
      }
      c.image = UIImage(systemName: "link")
      c.backgroundColor = TaskSwipe.grey
      acts.append(c)
    }
    if acts.isEmpty { return nil }
    let cfg = UISwipeActionsConfiguration(actions: acts)
    cfg.performsFirstActionWithFullSwipe = !leading || (d["cdHold"] as? Bool) != true
    return cfg
  }
  // (asked first: the task goes to the Trash — from its swipe)
  private func askTrash(_ card: HomeCard, finish: ((Bool) -> Void)?) {
    let al = UIAlertController(title: "Move this task to the Trash?", message: card.taskTitle.isEmpty ? nil : card.taskTitle, preferredStyle: .actionSheet)
    al.addAction(UIAlertAction(title: "Trash Task", style: .destructive) { [weak self] _ in self?.send(["ev": "delete", "id": card.id, "card": card.info]); self?.findAgain(); finish?(true) })
    al.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in finish?(false) })
    present?(al)
  }
  // (the list's top and bottom as iPhone has them — under Apple's bar — or as this screen sets them)
  private var inTop: CGFloat { appleTop ? sv.adjustedContentInset.top : scroll.contentInset.top }
  private var inBottom: CGFloat { appleTop ? sv.adjustedContentInset.bottom : scroll.contentInset.bottom }
  private func resignSearch() { field.resignFirstResponder(); onAppleResign?() }
  // Apple's search bar: it opened, its words changed, it closed — the results in Home's own list, on Home's own page (as
  // E11 Talk's lists: one list, Apple's bar following it; a second results page kept the big title's room above them)
  func appleSearchBegin() {
    guard appleTop, !searching else { return }
    searching = true
    showMotto()
    field.text = ""; showResults(nil)
  }
  func appleSearchText(_ q: String) {
    guard appleTop, searching, q != (field.text ?? "") else { return }
    field.text = q; typed()
  }
  func appleSearchEnd() {
    guard appleTop, searching else { return }
    findTimer?.invalidate()
    searching = false
    showMotto()
    field.text = ""; showResults(nil)
  }
  private let fab = UIButton(type: .system)
  // (a second, round button left of it — Client Assets' Delete while files are selected: Haris 2026-11-04)
  private let fab2 = UIButton(type: .system)
  private var fab2Run: (() -> Void)?
  // at the end of the list, beside "+ New task": "NOT JUST ANY AGENCY" (Haris, 2026-10-31) — it fades in (0.2 s — Haris) once
  // the list has reached its end, and out again on scrolling back (Haris, 2026-10-31)
  private let motto = UILabel()
  private var mottoOn = false
  private var stats: [UIView] = []
  private var content: [UIView] = []
  private var cards: [String: HomeCard] = [:]
  private var m: [String: Any] = [:]
  private var L = HomeLook(nil)
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { cards.values.forEach { $0.people = people }; meChanged(); if isInbox && !m.isEmpty { drawInbox(m) }; if isClients && !m.isEmpty { drawClients(m) } } } }
  private var meId = ""
  var bottomRoom: CGFloat = 120 { didSet { if oldValue != bottomRoom { setNeedsLayout() } } }
  // the top of the app's tab bar: the + sits 14 above it, 18 from the right (phone.css .ph-fab), so it's in place from
  // the first frame — not where the page had it a moment before the tab bar came (it jumped up, Haris 2026-10-31)
  // (the room under the list's last card: the list ends as far above "+ New task" as the button sits above the tab bar —
  //  it ended about 39 above it, the button about 19 above the tab bar: Haris 2026-11-09 18:46, the same gap)
  private var endRoom: CGFloat { tabTop.map { bounds.height - ($0 - 14 - BTN) - 8 } ?? bottomRoom }
  var tabTop: CGFloat? { didSet { if oldValue != tabTop { setNeedsLayout() } } }

  override init(frame: CGRect) {
    super.init(frame: frame)
    scroll.alwaysBounceVertical = true
    scroll.contentInsetAdjustmentBehavior = .never
    // (the scroll bar: from the bar's line down to just above the tab bar, from the very first moment — the standard,
    //  Haris 2026-11-03; iPhone's own adding of the safe area would start it up by the status bar)
    scroll.automaticallyAdjustsScrollIndicatorInsets = false; scroll.verticalScrollIndicatorInsets.top = 98
    scroll.delegate = self
    addSubview(scroll)
    // the search results (in place of the list while searching)
    results.alwaysBounceVertical = true; results.contentInsetAdjustmentBehavior = .never; results.automaticallyAdjustsScrollIndicatorInsets = false; results.keyboardDismissMode = .onDrag
    results.alpha = 0; results.isHidden = true
    hint.font = .systemFont(ofSize: 15); hint.numberOfLines = 0; hint.textAlignment = .center; results.addSubview(hint)
    addSubview(results)
    blur.isUserInteractionEnabled = false
    // (the bar once scrolled: frosted glass with a soft line under it, as Mail's)
    blur.contentView.addSubview(hairline)
    blur.alpha = 0
    blurMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    blur.layer.mask = blurMask
    addSubview(blur)
    addSubview(topBar)
    topLine.alpha = 0; topBar.addSubview(topLine)   // (the soft line under the bar, as Mail's)
    if #available(iOS 26.0, *) {
      blur.isHidden = true
      let i = UIScrollEdgeElementContainerInteraction()
      i.scrollView = scroll; i.edge = .top
      // (the bar's own row tells iPhone how far down the frost goes — FrostReach alone left it only as tall as the status
      //  bar: Haris 2026-11-03, build 1361)
      topBar.addInteraction(i)
      edgeHook = i
      frostReach.attach(scroll, in: self, below: topBar)
      // (iPhone's soft frost — Haris 2026-11-03: back to it, and locked)
      scroll.topEdgeEffect.style = .soft
      results.topEdgeEffect.style = .soft
    }
    sub.font = .systemFont(ofSize: 15)
    title.font = .systemFont(ofSize: 34, weight: .bold)
    title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.6
    smallTitle.font = .systemFont(ofSize: 17, weight: .semibold); smallSub.font = .systemFont(ofSize: 12)
    smallTitle.alpha = 0; smallSub.alpha = 0
    // (the big title scrolls with the list and goes under the frosted bar; the small title is on the bar)
    // (the big date and title are the list's own first lines: they scroll with it, under the frosted edge)
    scroll.addSubview(sub); scroll.addSubview(title)
    [smallTitle, smallSub].forEach { topBar.addSubview($0) }
    searchCircle.setIcon("magnifyingglass", 18)
    searchCircle.accessibilityLabel = "Search"
    searchCircle.onTap = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.openSearch() }
    me.clipsToBounds = true
    me.accessibilityLabel = "Me"
    me.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "me"]) }, for: .touchUpInside)
    closeCircle.setIcon("xmark", 17)
    closeCircle.accessibilityLabel = "Close search"
    closeCircle.onTap = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.closeSearch() }
    closeCircle.alpha = 0; closeCircle.isHidden = true
    // the search bar: a glass capsule with the lens and the text field
    lens.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
    lens.contentMode = .center
    field.font = .systemFont(ofSize: 17)
    field.delegate = self
    field.returnKeyType = .search; field.autocorrectionType = .no; field.clearButtonMode = .whileEditing
    field.addAction(UIAction { [weak self] _ in self?.typed() }, for: .editingChanged)
    field.addAction(UIAction { [weak self] _ in self?.field.resignFirstResponder() }, for: .editingDidEndOnExit)
    searchBar.content.addSubview(lens); searchBar.content.addSubview(field)
    searchBar.isHidden = true
    [searchCircle, me, searchBar, closeCircle].forEach { addSubview($0) }
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
      guard let self = self, let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
      let r = self.convert(end, from: nil)
      self.keyboardH = max(0, self.bounds.maxY - r.minY); self.setNeedsLayout()
    }
    nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in self?.keyboardH = 0; self?.setNeedsLayout() }
    // "+ New task": a Liquid Glass capsule the size of Mail's "Select" (iOS 26's own glass button; before: a grey capsule)
    // (a plain capsule, light and dark — no glass, the same as the toast it stretches into: Haris 2026-11-03)
    // (glass again — iPhone's own Liquid Glass, and the toast it stretches into is glass too: Haris 2026-11-03, "1")
    var fc: UIButton.Configuration
    if #available(iOS 26.0, *) { fc = .glass() } else { fc = .filled(); fc.cornerStyle = .capsule }
    fc.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    fc.imagePadding = 6
    fc.attributedTitle = AttributedString("New task", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    fc.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 18)
    fc.baseForegroundColor = .label
    fab.configuration = fc
    fab.accessibilityLabel = "New task"
    // (not greyed by iPhone behind an open sheet — its words greyed while the "+" didn't, and came back with a snap as
    //  the sheet left: Apple's own setting for it, Haris 2026-11-08)
    fab.tintAdjustmentMode = .normal
    fab.isHidden = true   // (until the screen's model says this person may add — it showed for a freelancer, who can't: the walk-through)
    fab.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); if let a = self?.fabRun { a() } else { self?.send(["ev": "add"]) } }, for: .touchUpInside)
    addSubview(fab)
    var f2: UIButton.Configuration
    if #available(iOS 26.0, *) { f2 = .glass() } else { f2 = .filled(); f2.cornerStyle = .capsule }
    f2.image = UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
    f2.baseForegroundColor = .systemRed; f2.contentInsets = .zero
    fab2.configuration = f2; fab2.isHidden = true
    fab2.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.fab2Run?() }, for: .touchUpInside)
    addSubview(fab2)
    for i in 0..<3 {
      let v = UIView(); v.layer.cornerRadius = 18; v.layer.cornerCurve = .continuous; let n = UILabel(), l = UILabel(); n.tag = 1; l.tag = 2; v.addSubview(n); v.addSubview(l); scroll.addSubview(v); stats.append(v)
      // (tapped: Overdue brings its group up to where the big title is; In review opens My Tasks waiting for the CD's
      //  review — Haris, 2026-10-31. Due today isn't tapped: its tasks are already first, right under it — Haris
      //  2026-11-07)
      v.tag = 100 + i; v.isAccessibilityElement = true
      if i == 0 { v.accessibilityTraits = .staticText; continue }
      let tap = UITapGestureRecognizer(target: self, action: #selector(statTap(_:))); v.addGestureRecognizer(tap)
      v.accessibilityTraits = .button
    }
  }
  required init?(coder: NSCoder) { fatalError() }

  private func send(_ ev: [String: Any]) {
    var e = ev; e["y"] = Int((sv.contentOffset.y + inTop).rounded())
    onEvent?(e)
  }

  // a screen's model, from the server or the copy: for the same person as what's in it, the screen's own change
  // animation; for someone else (View as…), the old rows and cards simply go and theirs are there at once — the Inbox
  // faded the other person's rows into these, Haris 2026-11-05
  func drawFor(_ model: [String: Any]) {
    let was = m["me"] as? String, now = model["me"] as? String
    if let was = was, let now = now, was != now { UIView.performWithoutAnimation { update(model); setNeedsLayout(); layoutIfNeeded() }; layer.removeAllAnimations(); subviews.forEach { $0.layer.removeAllAnimations() } }
    else { update(model) }
  }
  // ---------- what the page sent ----------
  func update(_ model: [String: Any]) {
    m = model
    L = HomeLook(model["look"] as? [String: Any])
    backgroundColor = L.bg
    // (the system's own text colours, as Mail: label for the titles, secondary label for the lines under them; the look
    //  is the phone's — nothing forced, every colour switches itself: Look.swift)
    HomeView.fadeText(sub, model["date"] as? String); sub.textColor = .secondaryLabel
    title.attributedText = NSAttributedString(string: model["title"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.label])
    if appleTop { onAppleTitle?(model["title"] as? String ?? "", model["date"] as? String ?? "") }
    smallTitle.text = model["title"] as? String; smallTitle.textColor = .label
    HomeView.fadeText(smallSub, model["date"] as? String); smallSub.textColor = .secondaryLabel
    if blur.effect == nil { blur.effect = UIBlurEffect(style: .systemUltraThinMaterial) }
    hairline.backgroundColor = Look.c(UIColor.white.withAlphaComponent(0.08), UIColor.black.withAlphaComponent(0.08))
    topLine.backgroundColor = Look.c(UIColor.white.withAlphaComponent(0.12), UIColor.black.withAlphaComponent(0.12))
    [searchCircle, closeCircle, searchBar].forEach { $0.setLook(tint: L.roundIc) }
    lens.tintColor = L.sub; field.textColor = L.h1; field.tintColor = L.tag
    field.attributedPlaceholder = NSAttributedString(string: assets == "plansTab" || assets == "plansPage" || assets == "me.plan" ? "Search plans — a client or a post" : assets == "reviewsTab" ? "Search requests" : assets == "claimsTab" ? "Search claims" : assets == "expensesTab" ? "Search expenses" : assets != nil ? "Search every client’s files" : "Search tasks, clients, people", attributes: [.foregroundColor: L.sub])
    hint.textColor = L.empty
    meId = model["me"] as? String ?? ""; watchMe(); meChanged()
    if var fc = fab.configuration {
      if #available(iOS 26.0, *) { fab.layer.shadowOpacity = 0 } else {
        fc.background.backgroundColor = ToastCapsule.fill; fc.background.strokeColor = ToastCapsule.line; fc.background.strokeWidth = 1
        fab.layer.shadowColor = UIColor.black.cgColor; fab.layer.shadowRadius = 10; fab.layer.shadowOffset = CGSize(width: 0, height: 3)
        fab.followLook("shadow") { [weak fab] tc in fab?.layer.shadowOpacity = tc.userInterfaceStyle == .light ? 0.08 : 0 }
      }
      fc.baseForegroundColor = Look.ink; fab.configuration = fc
    }
    if var f2 = fab2.configuration {
      if #available(iOS 26.0, *) {} else {
        f2.background.backgroundColor = ToastCapsule.fill; f2.background.strokeColor = ToastCapsule.line; f2.background.strokeWidth = 1
      }
      fab2.configuration = f2
    }
    stats.forEach { $0.isHidden = noStats }
    let st = model["stats"] as? [Int] ?? [0, 0, 0]
    let names = ["Due today", "Overdue", "In review"], cols = [L.statG, L.statR, L.statA]
    for (i, v) in stats.enumerated() {
      v.backgroundColor = L.card   // (the task cards' own colour, light and dark, no border — Haris 2026-11-09)
      v.layer.shadowOpacity = 0   // (no drop shadows on boxes or cards — Haris, 2026-10-31)
      let n = v.viewWithTag(1) as? UILabel, l = v.viewWithTag(2) as? UILabel
      n?.text = "\(st.indices.contains(i) ? st[i] : 0)"; n?.font = .systemFont(ofSize: 34, weight: .bold); n?.textColor = cols[i]   // (as Mail's big title)
      l?.text = names[i]; l?.font = .systemFont(ofSize: 12); l?.textColor = L.statLabel
    }
    if isInbox { drawInbox(model); setNeedsLayout(); layoutIfNeeded(); return }
    if isClients { drawClients(model); setNeedsLayout(); layoutIfNeeded(); return }
    if assets != nil { drawAssets(model); setNeedsLayout(); layoutIfNeeded(); return }
    // the groups: their headers, cards (kept by task, so a change doesn't redraw the rest) and "nothing due" lines
    // A change on the same list (done, due, deleted, undone — by you or by anyone else) moves as the Inbox does (Haris,
    // 2026-11-02): what goes fades out where it is while the gap closes; what comes — a task moving from Overdue to
    // Today, one completed elsewhere arriving on Done — gets its gap opened, then fades in. Nothing jumps.
    let key = "\(isList)|\(listTab)|\(filtersKey)|\(model["id"] as? String ?? "")"   // (another client's page: drawn afresh)
    // (Apple's list moves what came, went or moved itself — the cards' own move animation is gone with the cards: Haris
    //  2026-11-09, Home fully Apple)
    let animate = window != nil && !isHidden && key == drawnKey && !content.isEmpty && !searching
    drawnKey = key
    if !listOn { content.forEach { if !($0 is HomeBlock) && !($0 is HomeCard) { $0.removeFromSuperview() } } }
    var headsUsed = Set<String>()
    content = []
    if isClient {
      drawBarTitle(model)
      // (Haris 2026-11-10, the approved mock-up: "Client Assets · See All" with its folders as the Files app's grid in
      //  Apple's sideways row, then Apple's switch Open · Done, then its tasks — each kept, not made again)
      if let a = model["assets"] as? [String: Any], let cid = a["id"] as? String {
        let folders = (a["folders"] as? [[String: Any]]) ?? []
        if !folders.isEmpty {
          let h = clientAssetsHead
          let t = HomeView.groupHeading("Client Assets")
          if h.attributedText?.isEqual(to: t) != true { h.attributedText = t }
          tileSeeAll["h:client-assets"] = ("See all", { [weak self] in self?.send(["ev": "assets", "client": cid]) })
          content.append(h)
          var keep = Set<String>()
          for f in folders {
            let fid = f["id"] as? String ?? ""; keep.insert(fid)
            let v = stripTiles[fid] ?? { let x = FileTile(); stripTiles[fid] = x; return x }()
            v.folder(f, lines: 1)
            v.onTap = { [weak self] in self?.send(["ev": "folder", "client": cid, "folder": fid]) }
            // (held: Apple's menu with its lift — Open, and Copy link: a folder's link is copied by holding it, Haris 2026-11-10)
            v.menu = { [weak self] in
              var a: [UIMenuElement] = [UIAction(title: "Open", image: UIImage(systemName: "folder")) { _ in self?.send(["ev": "folder", "client": cid, "folder": fid]) }]
              if (f["canLink"] as? Bool) != false {
                a.append(UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in Main.shared.copyFolderLink(client: cid, folder: fid) { t in self?.assetsToast(t) } })
              }
              return UIMenu(children: a)
            }
            content.append(v)
          }
          for k in stripTiles.keys where !keep.contains(k) { stripTiles[k] = nil }
          // (another client's page: its folders' row starts at its first folder, not where the last client's was left —
          //  the same page is used for each client; Apple's own scroll to its first item once the list has it, Haris 2026-11-10)
          if stripClient != cid { stripClient = cid; stripStart = (folders.first?["id"] as? String).map { "fd:" + $0 } }
        }
      }
      let done = (model["showDone"] as? Bool) == true, open = model["open"] as? Int ?? 0
      doneSwitch.set("Open · \(open)", "Done", done ? 1 : 0)
      content.append(doneSwitch)
    }
    var seen = Set<String>()
    var runs: [String: Int] = [:]
    // (My Tasks or Home with nothing to show — a filter with no tasks, an empty Done, a Home with no tasks at all: Apple's own
    //  unavailable view behind the list, not our grey line — Haris 2026-11-09, the fully-Apple My Tasks: "Make the same
    //  empty for home page when there are no tasks". A client's page keeps its line.)
    var mtGroups = model["groups"] as? [[String: Any]] ?? []
    // (a client's page: its tasks in one list, by due date — today, then overdue (the nearest first), then tomorrow and on;
    //  none at the end; each keeping its status for its line — Haris 2026-11-10 15:05)
    if isClient {
      let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
      let today = f.string(from: Date())
      let all = mtGroups.flatMap { g in ((g["cards"] as? [[String: Any]]) ?? []).map { c -> [String: Any] in var x = c; x["_status"] = g["name"] ?? ""; return x } }
      func rank(_ c: [String: Any]) -> Int {
        let d = c["due"] as? String ?? ""
        return d.isEmpty ? 3 : d == today ? 0 : d < today ? 1 : 2
      }
      let sorted = all.enumerated().sorted { a, b in
        let ra = rank(a.element), rb = rank(b.element)
        if ra != rb { return ra < rb }
        let da = a.element["due"] as? String ?? "", db = b.element["due"] as? String ?? ""
        if da != db { return ra == 1 ? da > db : da < db }   // (overdue: the nearest first; to come: the soonest first)
        return a.offset < b.offset
      }.map { $0.element }
      let empty = mtGroups.compactMap { $0["empty"] as? String }.first { !$0.isEmpty }
      mtGroups = [["name": "", "cards": sorted, "empty": all.isEmpty ? (empty ?? "") : ""]]
    }
    let mtEmpty: String? = (isList || !isClient) && listOn && (model["plain"] as? Bool) != true && mtGroups.allSatisfy({ (($0["cards"] as? [Any]) ?? []).isEmpty })
      ? (mtGroups.compactMap { $0["empty"] as? String }.first { !$0.isEmpty } ?? "No open tasks here.") : nil
    var unavailable = false
    if #available(iOS 17.0, *) { unavailable = mtEmpty != nil }
    for g in mtGroups {
      let gname = g["name"] as? String ?? ""
      runs[gname, default: 0] += 1
      let gkey = gname + "#" + String(runs[gname]!)
      let h: UILabel = listOn ? (heads[gkey] ?? { let x = UILabel(); heads[gkey] = x; return x }()) : UILabel()
      headsUsed.insert(gkey)
      let name = (g["name"] as? String ?? "").uppercased()
      let s = NSMutableAttributedString()
      // (a client's run under Today: its colour dot first, as on the cards)
      // (Apple's circle in the client's colour — Haris 2026-11-09)
      if let dot = NativeSheetVC.color(g["dot"]), let img = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8))?.withTintColor(dot, renderingMode: .alwaysOriginal) {
        let a = NSTextAttachment(); a.image = img; a.bounds = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
        s.append(NSAttributedString(attachment: a)); s.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 12), .kern: 2]))
      }
      s.append(NSAttributedString(string: name, attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .kern: 0.72, .foregroundColor: L.gh]))
      if let n = g["n"] as? Int, n > 0 {
        s.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 12), .kern: 3.6]))
        s.append(NSAttributedString(string: "\(n)", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: L.gh.withAlphaComponent(0.8)]))
      }
      if h.attributedText?.isEqual(to: s) != true { h.attributedText = s }
      h.tag = 7; h.accessibilityIdentifier = gkey
      // (Today: no heading on screen — only the mark the Due today box scrolls to)
      let anchor = (g["anchor"] as? Bool) == true
      if h.isHidden != anchor { h.isHidden = anchor }
      if !listOn { scroll.addSubview(h) }   // (Apple's list: its words are its group's header, or a cell's)
      // (a client's page with nothing to show: Apple's own empty state under Open · Done — no heading over it; Haris 2026-11-10)
      // (Open shows only the open ones, Done only the done ones — Haris 2026-11-10 14:08)
      let showDone = (model["showDone"] as? Bool) == true
      let gcards = ((g["cards"] as? [[String: Any]]) ?? []).filter { !isClient || ((($0["done"] as? Bool) == true) == showDone) }
      let clientEmpty = isClient && listOn && gcards.isEmpty && !(mtGroups.contains { (($0["cards"] as? [[String: Any]]) ?? []).contains { (($0["done"] as? Bool) == true) == showDone } })
      if clientEmpty {
        if !content.contains(where: { $0 === clientEmptyView }) {
          if showDone { clientEmptyView.set("checkmark.circle", "No Done Tasks", "Tasks show here once they're done.") } else { clientEmptyView.set("checkmark.circle", "No Open Tasks", "Done tasks are under Done.") }
          content.append(clientEmptyView)
        }
        continue
      }
      // (a client's page: its tasks one Apple group, no status headings — the approved mock-up's board 2; each task's status on
      //  its line instead of the client's own name)
      if !isClient { content.append(h) }
      for c in gcards {
        guard let id = c["id"] as? String else { continue }
        seen.insert(id)
        // (the task: Apple's cell in the list, this its content and accessory — tapped: Apple's selection; held: Apple's menu;
        //  swiped: Apple's swipe actions — HomeView's list)
        let v: HomeCard
        if let old = cards[id] { v = old } else {
          v = HomeCard(); v.id = id
          v.onTap = { [weak self] in self?.send(["ev": "open", "id": id]) }
          cards[id] = v
        }
        v.people = people
        if isClient {
          var x = c
          var ml = (c["meta"] as? [[String: Any]]) ?? []
          if let i = ml.firstIndex(where: { $0["dot"] != nil || ($0["t"] as? String) == (model["title"] as? String) }) { ml.remove(at: i) }
          ml.insert(["t": c["_status"] as? String ?? gname], at: 0)
          x["meta"] = ml
          v.set(x, look: L)
        } else { v.set(c, look: L) }
        content.append(v)
      }
      if let e = g["empty"] as? String, !e.isEmpty, !unavailable {
        let l: UILabel = listOn ? (empties[gkey] ?? { let x = UILabel(); empties[gkey] = x; return x }()) : UILabel()
        if l.text != e { l.text = e }
        l.font = .systemFont(ofSize: 14); if l.textColor != L.empty { l.textColor = L.empty }; l.tag = 8; l.numberOfLines = 0; l.accessibilityIdentifier = "empty|" + gkey
        if !listOn { scroll.addSubview(l) }   // (Apple's list: its words in an Apple cell of the group)
        content.append(l)
      }
    }
    // (headings and lines of groups no longer there: gone)
    if listOn {
      for (k, v) in heads where !headsUsed.contains(k) { v.removeFromSuperview(); heads[k] = nil }
      for (k, v) in empties where !headsUsed.contains(k) || !content.contains(where: { $0 === v }) { v.removeFromSuperview(); empties[k] = nil }
    }
    for id in cards.keys where !seen.contains(id) { cards[id] = nil }
    canDelete = (model["canDelete"] as? Bool) == true
    if let t = model["toast"] as? [String: Any] { toast(t) }
    fab.isHidden = (model["add"] as? Bool) != true
    // (the filter buttons again in this light / dark, if it changed)
    if isList, let f = lastFilters { setFilters(f) }

    setNeedsLayout(); layoutIfNeeded()
    // (Apple's list: Apple's own animation for what came, went or moved)
    if listOn { applyList(animated: animate) }
    if isList || !isClient { showUnavailable(unavailable ? mtEmpty : nil) }
  }
  // Apple's unavailable view behind My Tasks' or Home's list (iOS 17+): a symbol, "No Tasks", why — and Clear Filters while a filter is
  // on. Set again only when what it says changes.
  private var unavailableShown: String?
  private func showUnavailable(_ why: String?, title: String = "No Tasks", symbol: String = "checkmark.circle") {
    guard #available(iOS 17.0, *), let cv = list else { return }
    let filtered = !isInbox && ((lastFilters?["chips"] as? [Any]) ?? []).isEmpty == false
    let key = why.map { $0 + "|\(filtered)|" + title + "|" + symbol }
    if key == unavailableShown { return }
    unavailableShown = key
    guard let why = why else { cv.backgroundView = nil; return }
    var c = UIContentUnavailableConfiguration.empty()
    c.image = UIImage(systemName: symbol)
    c.text = title
    c.secondaryText = why.isEmpty ? nil : why
    if filtered {
      var b = UIButton.Configuration.gray(); b.title = "Clear Filters"; b.cornerStyle = .capsule
      c.button = b
      c.buttonProperties.primaryAction = UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "reset"]) }
    }
    // (in the room between Apple's bar and "+ New task")
    c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: cv.adjustedContentInset.top, leading: 30, bottom: cv.adjustedContentInset.bottom + 70, trailing: 30)
    let v = UIContentUnavailableView(configuration: c)
    v.isHidden = searching
    cv.backgroundView = v
  }
  private var drawnKey = ""
  // (your photo only made again when it really changed — a new picture each drawing made the top button's photo blink a
  //  moment after it settled, and on coming back to the app: Haris 2026-11-02. A photo that's there isn't swapped for
  //  your initials while it's being fetched again.)
  private var meKey = ""
  // your photo in the corner: MePhoto (the same one as the Me tab); the one Home's people have is offered to it
  private func meChanged() {
    let p = people[meId]
    if let own = NativeSheetVC.photo(p) { MePhoto.shared.offer(own, for: meId) }
    MePhoto.shared.who(p?["initials"] as? String, NativeSheetVC.color(p?["color"]))
    let pic = MePhoto.shared.image
    let key = "\(meId)|\(pic.map { "\(ObjectIdentifier($0).hashValue)" } ?? "-")|\(MePhoto.shared.initials ?? "")"
    if key == meKey, me.image(for: .normal) != nil { return }
    meKey = key
    guard let img = MePhoto.shared.picture(44) else { return }
    me.setImage(img, for: .normal)
    onAppleMe?(img)
    onCorner?()
  }
  private var meWatching = false
  func watchMe() { guard !meWatching else { return }; meWatching = true; MePhoto.shared.watch { [weak self] in self?.meChanged() } }

  // ---------- My Tasks (26+): the same screen as a list — All / Done, the filter buttons and the filters that are on ----------
  // (the page says which buttons this person has and what's on: setFilters; taps go back as tab / filter / chip / reset)
  var isList = false { didSet { if isList && seg.superview == nil { makeList() } } }
  private let seg = UISegmentedControl(items: ["All", "Done"])
  private let filterRow = UIScrollView(), chipRow = UIScrollView()
  private let listHead = HomePassThrough()
  private var listHeadH: CGFloat = 0
  private var pinned = false   // (the tabs and filters stuck under the bar)
  // a page's own search and filters (the Trash's): at the top of its list, stuck under the bar once they reach it, as
  // My Tasks' — the standard (Haris 2026-11-03)
  var pinHead: UIView? { didSet {
    if oldValue !== pinHead { oldValue?.removeFromSuperview(); if let p = pinHead { insertSubview(p, belowSubview: topBar) }; pinned = false; setNeedsLayout() }
  } }
  private var pinHeadY: CGFloat = 0, pinHeadH: CGFloat = 0
  private var filterBtns: [UIButton] = [], chipBtns: [UIButton] = []
  private(set) var listTab = "all"
  private var filtersKey = ""
  private func makeList() {
    if isInbox { makeInbox(); return }
    seg.selectedSegmentIndex = 0
    seg.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.listTab = self.seg.selectedSegmentIndex == 1 ? "done" : "all"
      self.send(["ev": "tab", "tab": self.listTab])
    }, for: .valueChanged)
    [filterRow, chipRow].forEach { $0.showsHorizontalScrollIndicator = false; $0.alwaysBounceHorizontal = true; $0.clipsToBounds = false; $0.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16) }
    [filterRow, chipRow].forEach { $0.contentOffset.x = -16 }   // (the first button 16 in, as the cards)
    // (together, over the list: they move with it until they reach the frost bar, then stay under it — Haris, 2026-11-01)
    [seg, filterRow, chipRow].forEach { listHead.addSubview($0) }
    insertSubview(listHead, belowSubview: topBar)
  }
  private func capsule(_ t: String, sym: String?, on: Bool, small: Bool) -> UIButton {
    var c: UIButton.Configuration
    if #available(iOS 26.0, *) { c = on ? .prominentGlass() : .glass() } else { c = on ? .filled() : .gray(); c.cornerStyle = .capsule }
    // (a filter that's on: filled — black with white in light, white with black in dark, as Mail's "All Mail"; fixed
    //  colours, not the system's: the glass worked its own text colour out and it came out white on white in dark — Haris,
    //  2026-11-01)
    let ink: UIColor = on ? Look.inkInverse : Look.ink
    if on { c.baseBackgroundColor = Look.ink }
    c.baseForegroundColor = ink
    let f = UIFont.systemFont(ofSize: small ? 13 : 15, weight: on ? .semibold : .regular)
    c.attributedTitle = AttributedString(t, attributes: AttributeContainer([.font: f, .foregroundColor: ink]))
    if let sym = sym { c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: small ? 10 : 12, weight: .semibold))?.withTintColor(ink, renderingMode: .alwaysOriginal); c.imagePadding = small ? 5 : 6 }
    c.imagePlacement = small ? .trailing : .leading
    c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: small ? 12 : 14, bottom: 0, trailing: small ? 10 : 14)
    let b = UIButton(type: .system); b.configuration = c
    return b
  }
  private var lastFilters: [String: Any]?
  func setFilters(_ a: [String: Any]) {
    if !isList { isList = true }
    lastFilters = a
    if appleTop { onAppleFilters?(a) }
    let tab = (a["tab"] as? String) == "done" ? "done" : "all"
    if tab != listTab { listTab = tab }
    seg.selectedSegmentIndex = listTab == "done" ? 1 : 0
    let key = String(describing: a["buttons"] ?? "") + "|" + String(describing: a["chips"] ?? "") 
    if key == filtersKey { return }
    filtersKey = key
    filterBtns.forEach { $0.removeFromSuperview() }; chipBtns.forEach { $0.removeFromSuperview() }
    let syms = ["due": "calendar", "people": "person.2", "ams": "person.crop.circle", "assigned": "person.fill.checkmark"]
    filterBtns = (a["buttons"] as? [[String: Any]] ?? []).map { d -> UIButton in
      let k = d["k"] as? String ?? ""
      let b = capsule((d["t"] as? String ?? ""), sym: syms[k] ?? "line.3.horizontal.decrease", on: (d["on"] as? Bool) == true, small: false)
      b.accessibilityIdentifier = "filter-" + k
      b.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "filter", "k": k]) }, for: .touchUpInside)
      filterRow.addSubview(b); return b
    }
    var chips = (a["chips"] as? [[String: Any]] ?? []).map { d -> UIButton in
      let b = capsule(d["t"] as? String ?? "", sym: "xmark", on: false, small: true)
      b.accessibilityLabel = "Remove " + (d["t"] as? String ?? "")
      var ev: [String: Any] = ["ev": "chip", "act": d["act"] as? String ?? ""]; if let id = d["id"] as? String { ev["id"] = id }
      b.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(ev) }, for: .touchUpInside)
      return b
    }
    if chips.count > 1 {
      let b = UIButton(type: .system)
      b.setAttributedTitle(NSAttributedString(string: "Clear all", attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.secondaryLabel]), for: .normal)
      b.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "reset"]) }, for: .touchUpInside)
      chips.append(b)
    }
    chips.forEach { chipRow.addSubview($0) }
    chipBtns = chips
    setNeedsLayout()
  }
  // (where the boxes are on Home: All / Done 32 tall, the filter buttons 36, what's on 30 under them; returns where the list starts)
  private func layoutList(_ W: CGFloat) -> CGFloat {
    if isInbox { return layoutCats(W) }
    var y: CGFloat = 0
    seg.frame = CGRect(x: 16, y: y, width: W - 32, height: 32); y += 32 + 10
    func row(_ r: UIScrollView, _ bs: [UIButton], _ h: CGFloat) {
      var x: CGFloat = 0
      for (i, b) in bs.enumerated() {
        let w = ceil(b.sizeThatFits(CGSize(width: 400, height: h)).width)
        if i > 0 { x += 8 }
        b.frame = CGRect(x: x, y: 0, width: w, height: h); x += w
      }
      r.frame = CGRect(x: 0, y: y, width: W, height: h)
      r.contentSize = CGSize(width: x, height: h)
    }
    filterRow.isHidden = filterBtns.isEmpty
    if !filterBtns.isEmpty { row(filterRow, filterBtns, 36); y += 36 + 10 }
    chipRow.isHidden = chipBtns.isEmpty
    if !chipBtns.isEmpty { row(chipRow, chipBtns, 30); y += 30 + 10 }
    return y - 10
  }
  func selfTab(_ t: String) { seg.selectedSegmentIndex = t == "done" ? 1 : 0; seg.sendActions(for: .valueChanged) }
  func listGeo() -> [String: Any] {
    ["tab": listTab, "pinned": pinned, "apple": appleTop, "listOn": listOn, "headTop": listHead.frame.minY, "barBottom": smallHead, "filters": filterBtns.map { $0.accessibilityIdentifier ?? "" }, "chips": chipBtns.count, "cards": cards.count,
     "groups": content.compactMap { ($0 as? UILabel)?.tag == 7 ? $0.accessibilityIdentifier : nil }]
  }

  // ---------- the Inbox (28+): Home's screen with Mail's rows — All / Unread / Mentions as Mail's categories (MailCats),
  // Mark all read in Search's place, rows swiped right: Read / Unread. The server sends all of them; Unread and Mentions
  // are picked here, so switching is instant: the rows that don't belong fade out where they are and the others close
  // up — and back the other way (Haris, 2026-11-01, from Mail) ----------
  var isInbox = false { didSet { if isInbox && !isList { isList = true } } }
  // the Clients tab (shell 31): the list of clients, or a client's page (‹ back: the shared top buttons' left one)
  var isClients = false, isClient = false
  // Client Assets, the app's own (shell 32): "all", "client" or "folder" (Assets.swift)
  var assets: String?
  var assetsBack = false   // (pushed over another screen: ‹ goes back to it)
  var fabRun: (() -> Void)?
  // (the task page's bar — ‹ · logo and name · ••• — instead of the big title: a client's page, a client's assets, a folder)
  var pageBar: Bool { isClient || assets == "client" || assets == "folder" || isMeSub }
  // the app's own Me (shell 33, Me.swift): "me" — the tab's first page, Home's big title, no 🔍 or photo; "me.<page>" —
  // a page under it (Appearance, About, Shortcuts, Team members, a member): the task page's bar, ‹ and its name
  var isMe: Bool { assets == "me" || isMeSub }
  var isMeSub: Bool { assets?.hasPrefix("me.") == true }
  // (where 🔍 is on this page: left of your photo — or, on a page opened from somewhere (no photo), in the photo's own
  //  place; search grows out of it and shrinks back into it there — a second 🔍 showed on closing: Haris 2026-11-04)
  var searchInPhotoSpot: Bool { assets == "plansPage" || assets == "me.plan" || (backable && !pageBar) }
  var searchHome: CGRect { searchInPhotoSpot ? meFrame : searchCircle.frame }
  // where the list starts and the room above "+ New task", on screen with the list at its top (a box that fills the
  // page — About's What's new — ends there)
  var listTop: CGFloat { bigHead + 10 }
  var listBottom: CGFloat { (tabTop ?? bounds.height - 100) - 14 - BTN - 10 }
  private var noStats: Bool { isList || isClients || isClient || assets != nil || (m["plain"] as? Bool) == true }   // (plain: Finance only's "on the computer")
  // the assets screen's own pieces (Assets.swift), kept here so a change redraws only what changed
  var assetsParts: [String: UIView] = [:]
  func setFab(_ title: String, _ sym: String, _ run: (() -> Void)?) {
    fabRun = run
    guard var c = fab.configuration else { return }
    // (another label on a button that's showing — a tab switched: Add subscription ↔ Add office expense — it squashes
    //  and stretches into its new width, the words crossfading: the standard for every such button, Haris 2026-11-05.
    //  Judged by what showed when this redraw began: a page clears the button first (setFab("", …, nil)) and then sets
    //  its own, and judged by that cleared one it never morphed — it snapped: Haris 2026-11-05)
    noteFab()
    let shown = fabBefore?.label, was = fabBefore?.frame ?? fab.frame
    let morph = run != nil && !title.isEmpty && shown != nil && shown != "" && shown != title
    fabSym = sym
    c.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    c.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    if morph { let t = CATransition(); t.type = .fade; t.duration = 0.22; fab.layer.add(t, forKey: "label") }
    fab.configuration = c; fab.accessibilityLabel = title
    fab.isHidden = run == nil
    setNeedsLayout()
    if morph { DispatchQueue.main.async { [weak self] in self?.squashFab(from: was) } }
  }
  // ---- the shared + (SharedFab.swift): the + as it shows now, and its drawing veiled while the shared one moves ----
  // (a screen just hidden by a tab change still says what it showed — that's where the shared + comes from)
  var fabNow: (shown: Bool, frame: CGRect, config: UIButton.Configuration?, label: String) {
    let a = CGFloat(fab.layer.presentation()?.opacity ?? fab.layer.opacity)
    return (!fab.isHidden && fab.superview != nil && a > 0.01 && fab.bounds.width > 0, fab.frame, fab.configuration, fab.accessibilityLabel ?? "")
  }
  var fabVeiled = false { didSet { if fabVeiled != oldValue { fab.layer.mask = fabVeiled ? CALayer() : nil } } }   // (taps still reach it)
  private var fabBefore: (label: String?, frame: CGRect)?
  // what the button showed as this redraw began — before anything in it hides it (drawAssets hides it first: Me's pages,
  // Client Assets — the + still snapped, Haris 2026-11-05)
  private func noteFab() {
    guard fabBefore == nil else { return }
    fabBefore = (!fab.isHidden && fab.window != nil && fab.bounds.width > 0 ? fab.accessibilityLabel : nil, fab.frame)
    DispatchQueue.main.async { [weak self] in self?.fabBefore = nil }
  }
  // the button from its old size to its new one with a little squash and stretch (iPhone's own spring, as its own
  // buttons do when they change)
  private func squashFab(from was: CGRect) {
    layoutIfNeeded()
    let to = fab.frame
    guard to.width > 0, abs(to.width - was.width) > 0.5 || to.minY != was.minY else { return }
    UIView.performWithoutAnimation { fab.frame = was }
    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.4, options: [.allowUserInteraction, .beginFromCurrentState]) { self.fab.frame = to }
    let k = CAKeyframeAnimation(keyPath: "transform.scale.y")
    k.values = [1, 0.9, 1.05, 0.98, 1]; k.keyTimes = [0, 0.25, 0.55, 0.8, 1]; k.duration = 0.45
    k.timingFunction = CAMediaTimingFunction(name: .easeOut)
    fab.layer.add(k, forKey: "squash")
  }
  // ---- a tab changed: the button the last tab showed in this corner squashes and stretches into this one's, the words
  //      crossfading — + New task ↔ + Add client (Haris 2026-11-08: "then do it"; our button only, Apple's tab switch untouched)
  var fabInWindow: (frame: CGRect, config: UIButton.Configuration?, label: String)? {
    let n = fabNow
    guard n.shown, window != nil, let w = fab.superview else { return nil }
    return (w.convert(fab.frame, to: nil), n.config, n.label)
  }
  func fabArrive(from old: (frame: CGRect, config: UIButton.Configuration?, label: String)) {
    layoutIfNeeded()
    let n = fabNow
    guard n.shown, n.label != old.label, let w = fab.superview, let newCfg = fab.configuration else { return }
    let was = w.convert(old.frame, from: nil)
    // (the same corner only — a button elsewhere isn't the same button)
    guard abs(was.maxX - n.frame.maxX) < 2, abs(was.maxY - n.frame.maxY) < 2 else { return }
    UIView.performWithoutAnimation { fab.configuration = old.config; fab.layoutIfNeeded() }
    let t = CATransition(); t.type = .fade; t.duration = 0.22; fab.layer.add(t, forKey: "label")
    fab.configuration = newCfg
    squashFab(from: was)
  }
  // a line's words changing while it shows (the grey line under a title — Subscriptions ↔ Office expenses): a short
  // crossfade, not a jump; first shown or emptied: at once (the standard, Haris 2026-11-05)
  static func fadeText(_ l: UILabel, _ text: String?) {
    let old = l.text ?? "", new = text ?? ""
    if old != new, !old.isEmpty, !new.isEmpty, l.window != nil, !l.isHidden {
      let t = CATransition(); t.type = .fade; t.duration = 0.22; t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      l.layer.add(t, forKey: "text")
    }
    l.text = text
  }
  func setFab2(_ label: String, _ run: (() -> Void)?) {
    fab2Run = run; fab2.accessibilityLabel = label
    fab2.isHidden = run == nil
    setNeedsLayout()
  }
  func setContent(_ views: [UIView]) {
    // (Apple's list: its cells hold them)
    if listOn { content = views; applyList(animated: window != nil && !isHidden); return }
    for v in content where !views.contains(where: { $0 === v }) { v.removeFromSuperview() }
    for v in views where v.superview !== scroll { scroll.addSubview(v) }
    content = views
  }
  var look: HomeLook { L }
  var model: [String: Any] { m }
  func assetsToast(_ t: String) { toast(["t": t]) }
  // (a Client Assets folder download: the toast's round button an ✕ in the +'s place, cancelling it — Haris 2026-11-08)
  var onToastAct: (() -> Void)?
  func assetsToast(_ t: String, cancel: (() -> Void)?) { onToastAct = cancel; toast(cancel == nil ? ["t": t] : ["t": t, "x": true, "ms": 60000.0]) }
  var assetsMenu: (() -> [CornerMenuItem])?
  // the Clients list (fully Apple — Clients.swift): each client its own Apple row, kept by its id; "Inactive Clients" and the
  // inactive ones under it once it's tapped; a heading with no words parts the two groups
  private var clientRows: [String: ClientListRow] = [:]
  private lazy var clientsMore: ClientsMoreRow = {
    let r = ClientsMoreRow()
    r.onTap = { [weak self] in guard let self = self else { return }; self.clientsMore.open.toggle(); if !self.m.isEmpty { self.drawClients(self.m) } }
    return r
  }()
  private lazy var clientsGap: UILabel = { let l = UILabel(); l.accessibilityIdentifier = "clients-gap"; return l }()
  // a client's page (fully Apple, Haris 2026-11-10): its folders' tiles (kept by folder), their heading, Open · Done
  private var stripTiles: [String: FileTile] = [:]
  private var stripClient: String?, stripStart: String?
  private lazy var searchEmpty: AppleEmpty = { let e = AppleEmpty(); e.accessibilityIdentifier = "search-empty"; return e }()
  // a group's heading on the Clients pages, as the mock-up: capitals, 13 grey, a little spacing (Apple's grouped header)
  static func groupHeading(_ t: String) -> NSAttributedString {
    NSAttributedString(string: t.uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.secondaryLabel, .kern: 0.4])
  }
  private lazy var clientEmptyView: AppleEmpty = { let e = AppleEmpty(); e.accessibilityIdentifier = "client-empty"; return e }()
  private lazy var clientAssetsHead: UILabel = { let l = UILabel(); l.accessibilityIdentifier = "client-assets"; return l }()
  // (Apple's switch: "showDone" — its own name: "done" is a card's tick, which the app does itself)
  private lazy var doneSwitch: SegBlock = {
    let b = SegBlock(); b.accessibilityIdentifier = "client-open-done"
    b.onPick = { [weak self] i in guard let self = self else { return }; if (i == 1) != ((self.m["showDone"] as? Bool) == true) { self.send(["ev": "showDone"]) } }
    return b
  }()
  // ‹ on a client's page: where it is (the shared top buttons' row, at the page's left edge) and its tap
  var backable: Bool { isClient || (assets != nil && assetsBack) || (isClients && backFromMe) }
  var backFromMe = false   // (the Clients list opened from Me › Work — the CD's: ‹ back to Me, Haris 2026-11-05)
  // a client's page has the task page's header (Haris 2026-11-02, "b"): ‹ · its logo and name in the middle · •••
  private lazy var barTitle: UIStackView = {
    // (name, and a line under it on Client Assets: "6 folders · 48 files", a folder's client)
    let words = UIStackView(arrangedSubviews: [barName, barSub]); words.axis = .vertical; words.alignment = .center; words.spacing = 0
    barSub.font = .systemFont(ofSize: 12); barSub.textColor = .secondaryLabel; barSub.isHidden = true; barSub.lineBreakMode = .byTruncatingTail
    let s = UIStackView(arrangedSubviews: [barLogo, words]); s.spacing = 8; s.alignment = .center
    barLogo.layer.cornerRadius = 7; barLogo.layer.cornerCurve = .continuous; barLogo.clipsToBounds = true; barLogo.contentMode = .scaleAspectFill
    barLogo.widthAnchor.constraint(equalToConstant: 26).isActive = true; barLogo.heightAnchor.constraint(equalToConstant: 26).isActive = true
    barIni.font = .systemFont(ofSize: 10, weight: .bold); barIni.textColor = .white; barIni.textAlignment = .center; barLogo.addSubview(barIni)
    barName.font = .systemFont(ofSize: 17, weight: .semibold); barName.lineBreakMode = .byTruncatingTail
    s.isUserInteractionEnabled = false
    topBar.addSubview(s)
    return s
  }()
  private let barLogo = UIImageView(), barIni = UILabel(), barName = UILabel(), barSub = UILabel()
  // Client Assets' bar: its name (and logo, for a client) with the line under it
  func drawAssetsBar(name: String, sub: String, logo: String?, rgb: Any?, ini: String?, showLogo: Bool) {
    drawBarTitle(["title": name, "logo": logo as Any, "rgb": rgb as Any, "ini": ini as Any])
    barLogo.isHidden = !showLogo
    HomeView.fadeText(barSub, sub); barSub.isHidden = sub.isEmpty; barSub.textColor = .secondaryLabel
    barName.font = .systemFont(ofSize: sub.isEmpty ? 17 : 16, weight: .semibold)
    setNeedsLayout()
    tellApplePage()
  }
  // (a page pushed on the Clients tab — AppleClients.swift: its name, the line under it and its colour or logo, for
  //  Apple's bar)
  var onApplePage: ((String, String, UIColor, String?, String?, Bool) -> Void)?
  func tellApplePage() {
    onApplePage?(barName.text ?? "", barSub.isHidden ? "" : (barSub.text ?? ""), NativeSheetVC.color(m["rgb"]) ?? barLogo.backgroundColor ?? .systemGray, barLogoPath, barIni.text, !barLogo.isHidden)
  }
  private var barLogoPath: String?
  private func drawBarTitle(_ model: [String: Any]) {
    _ = barTitle
    barName.text = model["title"] as? String; barName.textColor = .label
    barIni.text = model["ini"] as? String
    let rgb = NativeSheetVC.color(model["rgb"]) ?? .systemGray
    let lp = model["logo"] as? String
    if lp != barLogoPath {
      barLogoPath = lp; barLogo.image = nil; barLogo.backgroundColor = rgb; barLogo.contentMode = .scaleAspectFill; barIni.isHidden = false
      if let p = lp { FeedLoader.shared.image(p) { [weak self] img in guard let self = self, self.barLogoPath == p, let img = img else { return }; LogoLook.put(img, key: p, in: self.barLogo); self.barIni.isHidden = true } }
    } else if barLogo.image == nil { barLogo.backgroundColor = rgb }
    [title, sub, smallTitle, smallSub].forEach { $0.isHidden = true }
    if isClient { tellApplePage() }
  }
  // its ••• (the shared corner button's menu): Client Assets, New task
  var menuItems: [CornerMenuItem] {
    if assets != nil { return assetsMenu?() ?? [] }
    guard isClient, !m.isEmpty else { return [] }
    var out: [CornerMenuItem] = []
    if let cid = (m["assets"] as? [String: Any])?["id"] as? String { out.append(CornerMenuItem(title: "Client Assets", symbol: "folder", run: { [weak self] in self?.send(["ev": "assets", "client": cid]) })) }
    // (Open · Done is Apple's switch on the page itself now — Haris 2026-11-10)
    if (m["add"] as? Bool) == true { out.append(CornerMenuItem(title: "New task", symbol: "plus", run: { [weak self] in self?.send(["ev": "add"]) })) }
    return out
  }
  var backFrame: CGRect { CGRect(x: 16, y: safeAreaInsets.top + 22 - BTN / 2, width: BTN, height: BTN) }
  func backTap() { send(["ev": "back"]) }
  func relayout() { if listOn { applyList(animated: true); return }; UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.setNeedsLayout(); self.layoutIfNeeded() } }
  // (the Clients tab coming back: Inactive Clients closed again)
  func clientsFresh() { if clientsMore.open { clientsMore.open = false; if !m.isEmpty { drawClients(m) } } }
  private func drawClients(_ model: [String: Any]) {
    content.forEach { if !($0 is ClientListRow) && $0 !== clientsMore && $0 !== clientsGap { $0.removeFromSuperview() } }
    let active = (model["rows"] as? [[String: Any]]) ?? [], inactive = (model["inactive"] as? [[String: Any]]) ?? []
    var seen = Set<String>()
    let row = { (r: [String: Any], off: Bool) -> ClientListRow in
      let id = r["id"] as? String ?? ""
      seen.insert(id)
      let v = self.clientRows[id] ?? {
        let x = ClientListRow(); x.id = id
        x.onTap = { [weak self] in self?.send(["ev": "client", "id": id]) }
        x.onLook = { [weak self] in self?.applyList(animated: false) }
        self.clientRows[id] = x; return x }()
      v.set(r, inactive: off, look: self.L, people: self.people)
      return v
    }
    var list: [UIView] = active.map { row($0, false) }
    if !inactive.isEmpty {
      clientsMore.count = inactive.count
      list += [clientsGap, clientsMore]
      if clientsMore.open { list += inactive.map { row($0, true) } }
    } else { clientsMore.open = false }
    for id in clientRows.keys where !seen.contains(id) { clientRows[id] = nil }
    content = list
    // (+ Add client for Admins — Haris 2026-11-03; the app's own New client sheet)
    if (model["canEdit"] as? Bool) == true { setFab("Add client", "plus") { [weak self] in self?.send(["ev": "addClient"]) } } else { fab.isHidden = true }
    if listOn { applyList(animated: window != nil && !isHidden) }
  }
  private let catsView = MailCats(items: [
    .init(key: "all", sym: "tray", name: "All", fill: MailCats.neutral),
    .init(key: "unread", sym: "envelope", name: "Unread", fill: MailCats.blue),
    .init(key: "mentions", sym: "at", name: "Mentions", fill: MailCats.purple)])
  private let markAll = UIButton(type: .system)
  // (the Inbox opens on Unread — Haris 2026-11-08: "Make the inbox open on unread"; All and Mentions a tap away)
  private(set) var inboxTab = "unread"
  private var keepSet = false
  private var inboxRows: [String: InboxRow] = [:]
  private var keep = Set<String>()     // (rows that were in the list when it was picked stay until it's left — read or not)
  private func makeInbox() {
    var c: UIButton.Configuration
    if #available(iOS 26.0, *) { c = .glass() } else { c = .gray(); c.cornerStyle = .capsule }
    c.attributedTitle = AttributedString("Mark all read", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]))
    c.baseForegroundColor = .label
    c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    markAll.configuration = c
    markAll.accessibilityIdentifier = "mark-all-read"
    markAll.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.send(["ev": "readAll"]) }, for: .touchUpInside)
    addSubview(markAll)
    catsView.onPick = { [weak self] i in guard let self = self else { return }; self.pickTab(["all", "unread", "mentions"][i]) }
    catsView.choose(1, animated: false)
    listHead.addSubview(catsView)
    insertSubview(listHead, belowSubview: topBar)
  }
  private func layoutCats(_ W: CGFloat) -> CGFloat {
    catsView.frame = CGRect(x: 0, y: 0, width: W, height: MailCats.H)
    return MailCats.H
  }
  private func fits(_ r: [String: Any]) -> Bool {
    let id = r["id"] as? String ?? ""
    switch inboxTab {
    case "unread": return (r["read"] as? Bool) != true || keep.contains(id)
    case "mentions": return (r["mention"] as? Bool) == true
    default: return true
    }
  }
  private func pickTab(_ k: String) {
    guard k != inboxTab else { scrollToTop(); return }
    UISelectionFeedbackGenerator().selectionChanged()
    inboxTab = k
    catsView.choose(["all", "unread", "mentions"].firstIndex(of: k) ?? 0, animated: true)
    keep = Set((m["rows"] as? [[String: Any]] ?? []).filter { ($0["read"] as? Bool) != true }.compactMap { $0["id"] as? String }); keepSet = true
    drawInbox(m)
    if #available(iOS 26.0, *), !appleTop { DispatchQueue.main.async { [weak self] in guard let self = self else { return }; Frost.nudge(self.scroll); self.applyFrost() } }
    send(["ev": "tab", "tab": k])
  }
  private func drawInbox(_ model: [String: Any]) {
    fab.isHidden = (model["add"] as? Bool) != true   // (+ New task, as on Home — for those who may)
    markAll.isHidden = ((model["unread"] as? Int) ?? 0) == 0
    markAll.alpha = cornerShared ? 0 : 1
    defer { onCorner?() }
    // (opened on Unread: the unread ones at the start stay in it until another list is picked — read or not, as Mail)
    // (nothing unread when it first opens: it opens on All instead — Haris 2026-11-10)
    if !keepSet, (model["rows"] as? [[String: Any]]) != nil, inboxTab == "unread", ((model["unread"] as? Int) ?? 0) == 0 {
      inboxTab = "all"; catsView.choose(0, animated: false)
    }
    if !keepSet, (model["rows"] as? [[String: Any]]) != nil {
      keep = Set((model["rows"] as? [[String: Any]] ?? []).filter { ($0["read"] as? Bool) != true }.compactMap { $0["id"] as? String }); keepSet = true
    }
    content.forEach { if !($0 is InboxRow) { $0.removeFromSuperview() } }
    content = []
    var seen = Set<String>()
    for r in (model["rows"] as? [[String: Any]] ?? []) where fits(r) {
      guard let id = r["id"] as? String else { continue }
      seen.insert(id)
      let v: InboxRow
      if let old = inboxRows[id] { v = old } else {
        v = InboxRow(); v.id = id
        v.onTap = { [weak self] in self?.send(["ev": "open", "id": id]) }
        v.onToggle = { [weak self, weak v] in guard let v = v else { return }; self?.send(["ev": v.read ? "unread" : "read", "id": id]) }
        inboxRows[id] = v
      }
      let p = people[r["from"] as? String ?? ""]
      let sig = drawSig(r) + "|\((p?["photo"] as? String)?.hashValue ?? 0)|\(p?["initials"] as? String ?? "")|\(String(describing: p?["color"]))|\(InboxRow.label(r["at"] as? String ?? ""))"
      if v.rowSig != sig { v.rowSig = sig; v.set(r, photo: roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 44)) }
      content.append(v)
    }
    for id in inboxRows.keys where !seen.contains(id) { inboxRows[id] = nil }
    // (nothing in the list: Apple's own unavailable view behind it — iOS 16, a line of words)
    let e = (model["empty"] as? String) ?? (inboxTab == "unread" ? "Inbox zero 🎉" : inboxTab == "mentions" ? "No mentions yet" : "Nothing here yet")
    let none = content.isEmpty
    if #available(iOS 17.0, *) {
      showUnavailable(none ? "" : nil, title: e, symbol: inboxTab == "unread" ? "checkmark.circle" : inboxTab == "mentions" ? "at" : "tray")
    } else if none {
      let l = UILabel(); l.text = e; l.font = .systemFont(ofSize: 15); l.textColor = .secondaryLabel; l.tag = 8; l.numberOfLines = 0; l.textAlignment = .center
      l.accessibilityIdentifier = "inbox-empty-" + inboxTab
      content.append(l)
    }
    // (Apple's list: it moves, brings in and takes away the rows itself — only what changed set again)
    if listOn { applyList(animated: window != nil && !isHidden); onAppleCorner?() }
  }
  func selfInboxTab(_ k: String) { pickTab(k) }
  func selfSwipeRow() {
    // (Apple's list: the first row offers Apple's own Read / Unread swipe)
    if let r = content.first as? InboxRow, let ip = listDS?.indexPath(for: "r:" + r.id) { appleSwipeOK = swipeActions(ip, leading: true) != nil }
    // (the rows Apple's own cells; holding one: Apple's menu, and the peek of a task's update — drawn from the copy)
    inboxCells = list?.visibleCells.filter { $0 is InboxCell }.count ?? 0
    if let r = content.first(where: { ($0 as? InboxRow).map { InboxPeekVC.make($0.id) != nil } == true }) as? InboxRow {
      let p = InboxPeekVC.make(r.id); p?.loadViewIfNeeded()
      peekSeen = ["h": Int(p?.preferredContentSize.height ?? 0), "comment": p?.commentText != nil, "menu": inboxMenuItems(r, p).count]
    }
  }
  private var appleSwipeOK = false
  private var inboxCells = 0
  private var peekSeen: [String: Any] = [:]
  func inboxGeo() -> [String: Any] {
    ["tab": inboxTab, "unread": (m["unread"] as? Int) ?? 0, "rows": content.filter { $0 is InboxRow }.count, "unreadRows": content.compactMap { $0 as? InboxRow }.filter { !$0.read }.count,
     "cats": catsView.widths, "markAll": !markAll.isHidden, "open": appleSwipeOK, "cells": inboxCells, "peek": peekSeen, "pinned": pinned, "apple": appleTop, "listOn": listOn]
  }

  // ---------- where things go ----------
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    let bigH = bigHead
    // the list runs the full height, under the header; it starts below the big header
    if scroll.frame != bounds { scroll.frame = bounds }
    if !appleTop, scroll.contentInset.top != bigH { let s0 = scroll.contentOffset.y + scroll.contentInset.top; scroll.contentInset.top = bigH; scroll.contentOffset.y = s0 - bigH }
    layoutHeader()
    if appleTop {
      // (under Apple's bar and its search bar: iPhone keeps the results clear of them, and of the keyboard)
      if results.frame != bounds { results.frame = bounds }
      results.contentInset.top = 12; results.contentInset.bottom = max(0, keyboardH - safeAreaInsets.bottom, bottomRoom - 60 - safeAreaInsets.bottom)
    } else {
    results.frame = CGRect(x: 0, y: searchBar.frame.maxY + 8, width: W, height: H - searchBar.frame.maxY - 8)
    results.contentInset.bottom = max(keyboardH, bottomRoom - 60)
    results.contentInset.top = 12   // (clear of the blur under the search bar)
    }
    if !listOn { layoutResults() }   // (Apple's list: the results are in it — applyList)
    if let cv = list {
      // (Apple's list: its cells place the boxes, headings and cards; the room under the last card kept as before)
      if cv.frame != bounds { cv.frame = bounds }
      let bottom = max(0, endRoom - safeAreaInsets.bottom)
      if cv.contentInset.bottom != bottom { cv.contentInset.bottom = bottom }
      if catsView.superview === catsWrap { catsView.frame = CGRect(x: 0, y: 0, width: W, height: MailCats.H) }
      let bw = (W - 32 - 16) / 3, bh: CGFloat = 1 + 10 + 41 + 15 + 12 + 1
      for (i, v) in stats.enumerated() {
        v.frame = CGRect(x: CGFloat(i) * (bw + 8), y: 0, width: bw, height: bh)
        v.viewWithTag(1)?.frame = CGRect(x: 13, y: 11, width: bw - 26, height: 41)
        v.viewWithTag(2)?.frame = CGRect(x: 13, y: 11 + 41, width: bw - 26, height: 15)
      }
    } else {
    // the three boxes (.ph-stats: 4 above, 6 below, 8 apart) — My Tasks: All / Done, the filters and what's on instead
    var y: CGFloat = 4
    let bw = (W - 32 - 16) / 3, bh: CGFloat = 1 + 10 + 41 + 15 + 12 + 1
    if isList { listHeadH = layoutList(W); y = 4 + listHeadH - bh; layoutHeader() }
    if isClients || isClient || assets != nil { y = 4 - bh }
    for (i, v) in stats.enumerated() where !noStats {
      v.frame = CGRect(x: 16 + CGFloat(i) * (bw + 8), y: y, width: bw, height: bh)
      v.viewWithTag(1)?.frame = CGRect(x: 13, y: 11, width: bw - 26, height: 41)
      v.viewWithTag(2)?.frame = CGRect(x: 13, y: 11 + 41, width: bw - 26, height: 15)
    }
    y += bh + 6
    if let p = pinHead, !isList { pinHeadY = y; pinHeadH = (p as? HomeBlock)?.blockHeight(W) ?? 0; y += pinHeadH }
    // the list (.ph-list: 16 from the sides, 10 between things; a group's title 12 lower than that)
    let lw = W - 32
    for (i, v) in content.enumerated() {
      if let b = v as? HomeBlock {
        // (the Clients tab's own blocks: the whole width, their own height)
        let h = b.blockHeight(W)
        b.bounds = CGRect(x: 0, y: 0, width: W, height: h); b.center = CGPoint(x: W / 2, y: y + h / 2)
        y += h
        continue
      }
      if v is InboxRow { continue }   // (the Inbox's rows: only in Apple's list)
      if i > 0 { y += 10 }
      if v.tag == 7 && v.isHidden {
        // (Today's mark: no room taken — the first client's heading starts where Today's used to)
        if i > 0 { y -= 10 }
        v.frame = CGRect(x: 20, y: y, width: lw - 8, height: 0)
      } else if v.tag == 7 {
        y += 12
        v.frame = CGRect(x: 20, y: y, width: lw - 8, height: 15)
        y += 15
      } else if v.tag == 8 {
        let h = (v as? UILabel)?.sizeThatFits(CGSize(width: lw - 8, height: 400)).height ?? 17
        v.frame = CGRect(x: 20, y: y + 14, width: lw - 8, height: h)
        y += 14 + h + 14
      }
    }
    // (the list ends with its last card 12 above "+ New task", so nothing is hidden behind it and no empty third of the
    //  screen is left under it — Haris, 2026-10-31; while scrolling the cards still pass under the + and the tab bar)
    scroll.contentSize = CGSize(width: W, height: y + endRoom)
    // (a list that got shorter — a task deleted — never leaves the view scrolled past its end, showing nothing)
    let maxY = max(-inTop, scroll.contentSize.height + inBottom - scroll.bounds.height)
    if !scroll.isDragging && !scroll.isDecelerating && scroll.contentOffset.y > maxY + 1 { scroll.setContentOffset(CGPoint(x: 0, y: maxY), animated: true) }
    }
    // the + button where the page has it
    // "+ New task": 44 tall like Mail's buttons, 16 from the right, 14 above the tab bar
    let fw = ceil(fab.sizeThatFits(CGSize(width: 300, height: BTN)).width)
    fab.frame = CGRect(x: W - R - fw, y: (tabTop ?? H - 100) - 14 - BTN, width: fw, height: BTN)
    fab2.frame = CGRect(x: fab.frame.minX - 10 - BTN, y: fab.frame.minY, width: BTN, height: BTN)
    let leftEdge = fab2.isHidden || fab.isHidden ? fab.frame.minX : fab2.frame.minX
    // (from the page's left edge, its middle level with the +'s)
    if motto.superview == nil {
      // (Haris, 2026-10-31: in capitals, 9 pt medium, letter spacing 2.4, the frost bar date's grey)
      motto.attributedText = NSAttributedString(string: "NOT JUST ANY AGENCY", attributes: [.font: UIFont.systemFont(ofSize: 9, weight: .medium), .kern: 2.4, .foregroundColor: UIColor.secondaryLabel])
      motto.textAlignment = .left   // (left, on the page's own edge — as the cards and the tab bar: Haris, 2026-11-01)
      motto.adjustsFontSizeToFitWidth = true; motto.minimumScaleFactor = 0.7
      motto.alpha = 0; motto.isUserInteractionEnabled = false
      insertSubview(motto, belowSubview: fab)
    }
    // (starting where the "O" of NOT was — the N's width and its letter spacing in from the page's edge; Haris, 2026-11-01)
    let nW = ceil(("N" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .medium), .kern: 2.4]).width)
    if fab.isHidden {
      // (no "+ New task" for this person: the motto in the middle of the page, at the same height — Haris, 2026-11-01)
      motto.textAlignment = .center
      motto.frame = CGRect(x: 16, y: fab.frame.midY - 16, width: W - 32, height: 32)
    } else {
      motto.textAlignment = .left
      motto.frame = CGRect(x: 16 + nW, y: fab.frame.midY - 16, width: max(0, leftEdge - 12 - 16 - nW), height: 32)
    }
    showMotto()
  }
  func scrollToTop() { sv.setContentOffset(CGPoint(x: 0, y: -(appleTop ? max(appleOpenTop, inTop) : inTop)), animated: true); userScrolled = false }
  // (under Apple's bar: the list's top with the big title open — the room above the list is measured from the bar as it is
  //  now, so scrolled with the small title showing, "the top" stopped where the small title forms and Apple's bar never
  //  opened the big title again: Haris 2026-11-08. Remembered while the big title is open: the most room it has given.)
  private var appleOpenTop: CGFloat = 0
  // a block's row brought to about 40% down the screen (an Inbox update opening the Reviews on its request)
  func scrollToShow(_ v: UIView, animated: Bool = true) {
    layoutIfNeeded()
    userScrolled = true
    let r = v.convert(v.bounds, to: sv)
    let y = max(-inTop, min(r.midY - sv.bounds.height * 0.4, sv.contentSize.height + inBottom - sv.bounds.height))
    sv.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if scrollView === scroll || scrollView === list { layoutHeader(); showMotto() }
    if appleTop, !searching, scrollView === sv, sv.adjustedContentInset.top > appleOpenTop { appleOpenTop = sv.adjustedContentInset.top }
  }
  // (Apple's bar coming in — after the startup screen, or back from another tab — or its big title growing: a list that
  //  was at its top stays at its top, the big title showing; it opened scrolled under the small title — Haris 2026-11-07)
  // (until you scroll it yourself, Home's list stays at its very top with the big title — whatever room the bars, the
  //  tab bar or the startup screen give it; it opened scrolled under the small title, twice: Haris 2026-11-07)
  // (Home's list is placed by Apple — its big title, its top: nothing of ours moves it; HomeVC in AppleHome.swift)
  private var userScrolled = false
  var appleBarHeight: (() -> CGFloat)?
  // the list at its end (or too short to scroll), Home not searching, no toast beside the + — the motto shows
  private func showMotto() {
    let end = max(-inTop, sv.contentSize.height + inBottom - sv.bounds.height)
    // (a list that fits on the screen — half a page, nothing to scroll for: it shows at once, not only after a
    //  scroll; Haris 2026-11-03)
    let fits = sv.contentSize.height + inTop + (listOn ? inBottom : 0) <= sv.bounds.height + 1
    let want = !searching && toastView == nil && (fits || sv.contentOffset.y >= end - 2)
    guard want != mottoOn else { return }
    mottoOn = want
    UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.motto.alpha = want ? 1 : 0 }
  }

  // ---------- the header (as Mail): the big title scrolls with the list, under a frosted bar that comes as it goes ----------
  // (where the list's boxes start: under the big title and its line, 18 below them — as Mail's filters)
  private var bigHead: CGFloat { pageBar ? smallHead + 8 : safeAreaInsets.top + 66 + 41 + 1 + 19 + 18 - 4 }   // (a client's page: no big title — the task page's bar)
  // (the bar's row: its middle 28 under the status bar, 14 of room under the 46 pt buttons — Haris: they sat on its edge)
  private var smallHead: CGFloat { safeAreaInsets.top + 54 }
  private func ease(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { let x = min(1, max(0, (t - a) / (b - a))); return x * x * (3 - 2 * x) }
  // (how far the list has scrolled)
  private var scrolled: CGFloat { scroll.contentOffset.y + scroll.contentInset.top }
  // ---------- the bar switching over, as Mail (measured frame by frame from Haris's recordings, 2026-11-01) ----------
  // Mail's is tied to the scroll, not a timed animation: as the big title reaches the top (its middle just under the
  // status bar) it blurs and fades where it is, over ~8 pt of scroll; the small title comes in over the next ~14 pt
  // (rising ~6 pt, sharpening), the line under it ~8 pt later. Scroll slowly and it follows your finger; flick and it's
  // over in a few frames. Let go part way and it finishes by itself (~0.35 s, easing out) — the way it was going.
  // Going back, the same in reverse. Everything here follows one number, u: the scroll, or the finish once let go.
  private let bigFrom: CGFloat = 82     // (scrolled: the big title starts to go)
  private var u: CGFloat = 0            // where the switch-over is (in scroll points)
  private var latch: Bool? = nil        // finished by itself: held on / off until the scroll passes that end
  private var snapFrom: CGFloat = 0, snapTo: CGFloat = 0, snapT0: CFTimeInterval = 0, snapping = false
  private var lastS: CGFloat = 0, goingUp = true
  // shown (eased toward u's values each frame, so nothing jumps)
  private var dBig: CGFloat = 0, dT: CGFloat = 0, dS: CGFloat = 0, dLine: CGFloat = 0
  private var barLink: CADisplayLink?, barLast: CFTimeInterval = 0
  private var uEnd: CGFloat { bigFrom + 8 + 14 }   // (all in)
  private var barIn: Bool { u >= bigFrom + 7 }      // (more than half way: what the rest of the screen goes by)
  private var shrink: CGFloat { barIn ? 1 : 0 }
  private var pastBig: Bool { barIn }
  private func clamp01(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
  private var tBig: CGFloat { clamp01((u - bigFrom) / 8) }
  private var tT: CGFloat { clamp01((u - bigFrom) / 14) }   // (starting the moment the big title starts to fade — Haris, 2026-11-01)
  private var tS: CGFloat { clamp01((u - bigFrom - 8) / 14) }
  private var fades: [ObjectIdentifier: HomeBlurFade] = [:]
  private func fade(_ l: UILabel) -> HomeBlurFade {
    if let f = fades[ObjectIdentifier(l)] { return f }
    let f = HomeBlurFade(l); fades[ObjectIdentifier(l)] = f; return f
  }
  private func easeOut(_ x: CGFloat) -> CGFloat { let t = min(1, max(0, x)); return 1 - pow(1 - t, 3) }
  // the scroll moved (or was set): u follows it, unless finishing by itself
  private func followScroll() {
    let s = scrolled
    if abs(s - lastS) > 0.01 { goingUp = s > lastS; lastS = s }
    let dragging = scroll.isTracking || scroll.isDragging || scroll.isDecelerating
    if dragging { snapping = false }
    if let l = latch {
      // (held at its end until the scroll itself passes that end — or turns back past the start)
      if l && (s >= uEnd || s < bigFrom) || !l && (s <= bigFrom || s > uEnd) { latch = nil }
    }
    if !snapping {
      if let l = latch { u = l ? max(s, uEnd) : min(s, bigFrom) } else { u = s }
    }
    startBarLink()
  }
  // let go part way: finish the way it was going
  private func settle() {
    guard latch == nil, u > bigFrom, u < uEnd, !scroll.isDecelerating else { return }
    let on = goingUp ? tBig > 0.05 : tT > 0.95
    snapFrom = u; snapTo = on ? uEnd : bigFrom; snapT0 = CACurrentMediaTime(); snapping = true; latch = on
    startBarLink()
  }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if scrollView === scroll && !decelerate { settle() } }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { if scrollView === scroll { settle() } }
  private func startBarLink() {
    if barLink != nil { return }
    barLast = CACurrentMediaTime()
    let l = CADisplayLink(target: self, selector: #selector(barTick))
    if #available(iOS 15.0, *) { l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120) }
    l.add(to: .main, forMode: .common); barLink = l
  }
  @objc private func barTick() {
    let now = CACurrentMediaTime(), dt = CGFloat(min(now - barLast, 1.0 / 30)); barLast = now
    if snapping {
      let k = CGFloat(min(1, (now - snapT0) / 0.35))
      u = snapFrom + (snapTo - snapFrom) * easeOut(k)
      if k >= 1 { snapping = false }
    }
    // (shown values close in on u's quickly — ~30 ms — so a flick takes a few frames, as Mail's, and nothing jumps)
    // (Mail never goes quicker than its own pace, however fast the flick — measured from Haris's flick recordings: in, the
    //  big title gone in ~0.07 s, the small title over ~0.09 s once the big one is mostly gone, its line over ~0.09 s
    //  from the small title's 60 %; out, the line in ~0.07 s, the small title in ~0.15 s, the big title back once the
    //  small one has gone. Each piece moves at most at that pace, and waits for the one before it.)
    let a = 1 - exp(-dt / 0.03)
    func near(_ d: inout CGFloat, _ to: CGFloat, upIn: Double, downIn: Double) {
      var n = d + (to - d) * a
      let up = dt / CGFloat(upIn), down = dt / CGFloat(downIn)
      n = min(n, d + up); n = max(n, d - down)
      d = abs(to - n) < 0.002 ? to : n
    }
    // (the big title and the small one cross: one starts as the other starts; the line follows the small title)
    let gT = tT, gS = min(tS, clamp01((dT - 0.6) / 0.4))
    let bT = max(gT, dS - 0.25), bBig = tBig
    near(&dBig, bBig, upIn: 0.1, downIn: 0.1)
    near(&dT, bT, upIn: 0.09, downIn: 0.15)
    near(&dS, gS, upIn: 0.09, downIn: 0.07)
    // (the line: in with the title; going back, gone at once)
    if goingUp || snapping && snapTo > snapFrom { near(&dLine, dT, upIn: 0.09, downIn: 0.01) } else { dLine = tT >= 1 ? dLine : 0 }
    applyBar()
    if !snapping && dBig == bBig && dT == bT && dS == gS && dBig == tBig && dT == tT && dS == tS && !scroll.isTracking && !scroll.isDecelerating { barLink?.invalidate(); barLink = nil }
  }
  private func applyBar() {
    let tr = traitCollection
    if searching {
      fades.values.forEach { $0.clear() }
      smallTitle.alpha = 0; smallSub.alpha = 0; title.alpha = 1; sub.alpha = 1
      return
    }
    // the small title and its line: rising ~6 pt and sharpening as they come; blurring and sinking as they go
    // (each starts half its own height low — its top where its middle will be — and comes up into place: the fade and
    //  sharpening eased out, the rise eased in; going back, the same way down — Haris, 2026-11-01)
    func show(_ l: UILabel, _ p: CGFloat) {
      let rise = l.bounds.height / 2
      fade(l).set(blur: 8 * (1 - easeOut(p)), alpha: easeOut(min(1, p / 0.7)), dy: rise * (1 - p * p), trait: tr)
    }
    // (a page with its name in the middle of the bar — a client's, Client Assets, Me's pages: only that name; Home's small
    //  title never comes in over it — Haris 2026-11-03)
    if pageBar { fade(smallTitle).set(blur: 0, alpha: 0, dy: 0, trait: tr); fade(smallSub).set(blur: 0, alpha: 0, dy: 0, trait: tr) }
    else { show(smallTitle, dT); show(smallSub, dS) }
    // the big title: blurs and fades where it is; the big line under it with it
    // (as Mail's: no blur of its own — it just fades away behind the frost; Haris, 2026-11-01)
    fade(title).set(blur: 0, alpha: 1 - ease(0, 1, dBig), dy: 0, trait: tr)
    fade(sub).set(blur: 0, alpha: 1 - ease(0, 0.8, dBig), dy: 0, trait: tr)
    if #available(iOS 26.0, *) {
      // (no line under the bar on a page with its name in the middle — the standard, Haris 2026-11-03)
      applyFrost()
    } else { blur.alpha = dT }
  }
  // (Search's end, a self-test, a new layout: everything where the scroll says, at once)
  private func setBar(_ on: Bool, now: Bool = false) {
    latch = nil; snapping = false; u = scrolled; lastS = u
    if now { dBig = tBig; dT = tT; dS = tS; dLine = tT; applyBar() } else { startBarLink() }
  }
  private func layoutHeader() {
    if appleTop { return }   // (Apple's bar: its own title, buttons and frost)
    let W = bounds.width
    let bigH = bigHead, smallH = smallHead, top = safeAreaInsets.top
    let titleY = top + 66   // (the big title's top, as Mail's)
    // the bar's frost: iPhone's own scroll edge effect under the bar's row (iOS 26+), there once the list moves under it;
    // before iOS 26 a thin see-through blur that softens out at its lower edge
    // My Tasks: All / Done and the filters where the list has them (4 under its top) — once they reach the bar, stuck
    // 8 under it, the frost reaching down under them (so the cards go under them too)
    var barH = smallH
    if isList && listHead.superview != nil {
      let atY = 4 - scroll.contentOffset.y, pinY = smallH + 8
      let pin = !searching && atY < pinY
      listHead.frame = CGRect(x: 0, y: max(atY, pin ? pinY : atY), width: W, height: listHeadH)
      if pin != pinned {
        pinned = pin
        // (in the bar while stuck — iPhone's frost goes under what's in it; otherwise over the list)
        if pin { topBar.addSubview(listHead) } else { insertSubview(listHead, belowSubview: topBar) }
      }
      listHead.isHidden = searching
      if pin { barH = pinY + listHeadH + 8 }
    } else if let p = pinHead, !isList {
      let atY = pinHeadY - scroll.contentOffset.y, pinY = smallH + 4
      let pin = !searching && atY < pinY
      if pin != pinned {
        pinned = pin
        if pin { topBar.addSubview(p) } else { insertSubview(p, belowSubview: topBar) }
      }
      p.bounds = CGRect(x: 0, y: 0, width: W, height: pinHeadH); p.center = CGPoint(x: W / 2, y: max(atY, pin ? pinY : atY) + pinHeadH / 2)
      if pin { barH = pinY + pinHeadH + 4 }
    }
    topBar.frame = CGRect(x: 0, y: 0, width: W, height: barH)
    // (it comes the moment the big title has gone under the bar, as Mail's — Haris, 2026-10-31)
    if !searching { followScroll() }
    if #available(iOS 26.0, *) {
      if let i = edgeHook as? UIScrollEdgeElementContainerInteraction { let want: UIScrollView = searching ? results : scroll; if i.scrollView !== want { i.scrollView = want }; frostReach.follow(want) }
      applyFrost()
      // (one pixel, as Mail's)
      let px = 1 / max(1, traitCollection.displayScale)
      topLine.frame = CGRect(x: 0, y: barH - px, width: W, height: px)
    } else {
      blur.frame = CGRect(x: 0, y: 0, width: W, height: barH + 14)
      CATransaction.begin(); CATransaction.setDisableActions(true)
      blurMask.frame = blur.bounds; blurMask.locations = [0, NSNumber(value: Double(barH / (barH + 14))), 1]
      CATransaction.commit()
      hairline.frame = CGRect(x: 0, y: barH - 0.5, width: W, height: 0.5)
      if searching { blur.alpha = 1 }
    }
    // (the scroll bar on the right runs from the bar's lower edge down, never up beside it — as Mail's; set here, not by iPhone)
    if scroll.automaticallyAdjustsScrollIndicatorInsets { scroll.automaticallyAdjustsScrollIndicatorInsets = false }
    // (… down to just above the tab bar, as Mail's)
    // (… and from under the stuck search / filters from the very first moment, so it never jumps as they stick —
    //  Haris 2026-11-03)
    var barTop = smallH
    if searching {} else if isList && listHead.superview != nil { barTop = smallH + 8 + listHeadH + 8 } else if pinHead != nil, !isList { barTop = smallH + 4 + pinHeadH + 4 }
    scroll.verticalScrollIndicatorInsets = UIEdgeInsets(top: barTop, left: 0, bottom: tabTop.map { bounds.height - $0 + 8 } ?? bottomRoom - 20, right: 0)
    // the big date and title: the list's own first lines (above its top, in the room it keeps for them)
    let tw = W - 16 - R
    // (bounds and centre, not frame: the blur fade moves them with a transform)
    func place(_ l: UILabel, _ r: CGRect) { l.bounds = CGRect(origin: .zero, size: r.size); l.center = CGPoint(x: r.midX, y: r.midY) }
    place(title, CGRect(x: 16, y: titleY - bigH, width: tw, height: 41))
    place(sub, CGRect(x: 16, y: titleY + 41 + 1 - bigH, width: tw, height: 19))
    // the small title and date on the bar: there once the big ones have gone under it (gone while searching, under its bar)
    let smallCY = top + 22
    let stw = W - 16 - R - BTN - 12 - BTN - 12
    if pageBar {
      // (in the middle of the bar, between ‹ and •••)
      let sz = barTitle.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
      let maxW = W - 2 * (16 + BTN + 12)
      let w = min(sz.width, maxW)
      let bh: CGFloat = barSub.isHidden ? 30 : 38
      barTitle.frame = CGRect(x: (W - w) / 2, y: top + 22 - bh / 2, width: w, height: bh)
    }
    let sx: CGFloat = backable ? 16 + BTN + 12 : 16   // (a client's page: right of ‹)
    place(smallTitle, CGRect(x: sx, y: top + 1, width: stw - (sx - 16), height: 21)); place(smallSub, CGRect(x: sx, y: top + 25, width: stw - (sx - 16), height: 15))
    applyBar()
    // Search and your photo: with the title until they reach the bar, then they stay on it
    // (Search and your photo stay on the bar's row from the start — they don't move with the list — Haris, 2026-10-31)
    let cy = smallCY
    if !searching {
      me.bounds = CGRect(x: 0, y: 0, width: BTN, height: BTN); me.center = CGPoint(x: W - R - BTN / 2, y: cy); me.layer.cornerRadius = BTN / 2
      searchCircle.frame = CGRect(x: W - R - BTN - 12 - BTN, y: cy - BTN / 2, width: BTN, height: BTN)
      if isInbox {
        searchCircle.isHidden = true
        let mw = ceil(markAll.sizeThatFits(CGSize(width: 300, height: BTN)).width)
        markAll.frame = CGRect(x: W - R - BTN - 12 - mw, y: cy - BTN / 2, width: mw, height: BTN)
      }
    } else {
      // (the bar in the row the buttons are in; the ✕ where your photo was)
      searchBar.frame = CGRect(x: 16, y: cy - BTN / 2, width: W - 16 - BTN - 12 - R, height: BTN)
      closeCircle.frame = CGRect(x: W - R - BTN, y: cy - BTN / 2, width: BTN, height: BTN)
    }
    lens.frame = CGRect(x: 12, y: 0, width: 22, height: searchBar.bounds.height)
    field.frame = CGRect(x: 40, y: 0, width: max(0, searchBar.bounds.width - 40 - 10), height: searchBar.bounds.height)
  }
  // the field's own ✕: clears what's typed (and the results)
  func textFieldShouldClear(_ textField: UITextField) -> Bool { DispatchQueue.main.async { self.typed() }; return true }

  // ---------- search: the glass circle stretches into a search bar, your photo becomes a glass ✕ ----------
  func openSearch() {
    if searching { field.becomeFirstResponder(); return }
    let start = searchHome, meF = me.frame
    searching = true
    onCorner?()
    showMotto()
    searchBar.frame = start; searchBar.isHidden = false; searchBar.alpha = 1
    searchBar.layer.cornerRadius = start.height / 2
    // (its glass starts as the circle too — it was laid out at full width at once, so the bar seemed to come in from
    //  the right; now the glass and the field stretch out of 🔍 together, inside the spring)
    lens.frame = CGRect(x: 12, y: 0, width: 22, height: start.height); field.frame = CGRect(x: 40, y: 0, width: 0, height: start.height)
    searchBar.layoutIfNeeded()
    closeCircle.frame = meF; closeCircle.isHidden = cornerShared; closeCircle.alpha = 0
    closeCircle.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
    searchCircle.alpha = 0
    results.isHidden = false
    field.text = ""; if assets != nil { onEvent?(["ev": "find", "q": ""]) } else { showResults(nil) }
    UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
      self.layoutHeader()
      self.searchBar.layer.cornerRadius = self.BTN / 2
      self.searchBar.layoutIfNeeded()
      self.me.alpha = 0; self.me.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
      self.barTitle.alpha = 0   // (a page's name in the middle goes while you search — Haris 2026-11-04: it showed through)
      self.closeCircle.alpha = 1; self.closeCircle.transform = .identity
      self.scroll.alpha = 0; self.results.alpha = 1; self.fab.alpha = 0
      self.results.frame.origin.y = self.searchBar.frame.maxY + 8
    }
    field.becomeFirstResponder()
  }
  func closeSearch() {
    guard searching else { return }
    field.resignFirstResponder()
    findTimer?.invalidate()
    searching = false
    // (your photo comes back at once, as the bar starts shrinking — it used to wait for the bar: Haris, 2026-11-02)
    closingSearch = true
    onCorner?()
    showMotto()
    setNeedsLayout(); layoutIfNeeded()
    let back = searchHome
    if searchBar.transform != .identity { searchBar.transform = .identity }   // (closed while still settling)
    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3, options: [.allowUserInteraction]) {
      self.searchBar.frame = back; self.searchBar.layer.cornerRadius = back.height / 2
      self.lens.frame = CGRect(x: 12, y: 0, width: 22, height: back.height)
      self.field.alpha = 0
      self.closeCircle.alpha = 0; self.closeCircle.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
      self.me.alpha = 1; self.me.transform = .identity
      self.barTitle.alpha = 1
      self.scroll.alpha = 1; self.results.alpha = 0; self.fab.alpha = 1
      self.layoutHeader()
      self.searchBar.frame = back; self.searchBar.layoutIfNeeded()   // (its glass shrinks back into 🔍 with it)
    } completion: { _ in
      self.closingSearch = false
      if self.searching { return }
      self.searchClosedAt = Date()
      self.searchBar.isHidden = true; self.closeCircle.isHidden = true; self.field.alpha = 1
      self.searchCircle.alpha = self.cornerShared ? 0 : 1; self.results.isHidden = true
      self.onCorner?()
      self.field.text = ""; self.showResults(nil)
    }
  }
  // (a search result changed — done, due, deleted: the results again, a moment later, as they are now)
  private func findAgain() {
    guard searching else { return }
    for t in [0.8, 2.5] { DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in if self?.searching == true { self?.typed() } } }
  }
  private func typed() {
    findTimer?.invalidate()
    let q = field.text ?? ""
    // (All Client Assets: its own files, found on the phone — Assets.swift)
    if assets != nil { onEvent?(["ev": "find", "q": q]); return }
    if q.trimmingCharacters(in: .whitespaces).isEmpty { showResults(nil); return }
    findTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in self?.onEvent?(["ev": "find", "q": q]) }
  }
  // what the page found for the bar (the search command): clients, then tasks — in the cards of Home
  func searchResults(_ r: [String: Any]) {
    guard searching, (r["q"] as? String) == field.text else { return }
    showResults(r)
  }
  private func showResults(_ r: [String: Any]?) {
    // (Apple's list: the results live in its cells — never taken out of them here; a card still found stays in its cell.
    //  Taken out, a card that didn't change wasn't put back (its cell isn't set again), and the tasks found went blank:
    //  Haris 2026-11-08)
    if !listOn { resultViews.forEach { $0.removeFromSuperview() } }
    resultViews = []
    var seen = Set<String>(), seenFiles = Set<String>()
    let q = (field.text ?? "").trimmingCharacters(in: .whitespaces)
    if let r = r {
      let marks = (r["marks"] as? [String]) ?? []
      let clients = (r["clients"] as? [[String: Any]] ?? []).map { var x = $0; x["marks"] = marks; return x }, tasks = (r["tasks"] as? [[String: Any]] ?? []).map { var x = $0; x["marks"] = marks; return x }
      walkFirst = (tasks.first?["id"] as? String, clients.first?["id"] as? String)
      // (a word that only matched as a typo: "Showing results for ford (you typed “frod”)" — app.js searchFixedNote)
      if let fx = r["fixed"] as? [[String: Any]], !fx.isEmpty { let n = SearchFixedNote(); n.set(fx); if !listOn { results.addSubview(n) }; resultViews.append(n) }
      if !clients.isEmpty {
        resultViews.append(groupHead("Clients", clients.count))
        for c in clients {
          let row = HomeClientRow(); row.set(c, look: L)
          let id = c["id"] as? String ?? ""
          row.onTap = { [weak self] in self?.resignSearch(); self?.send(["ev": "client", "id": id]) }
          resultViews.append(row)
        }
      }
      if !tasks.isEmpty {
        resultViews.append(groupHead("Tasks", (r["total"] as? Int) ?? tasks.count))
        for c in tasks {
          guard let id = c["id"] as? String else { continue }
          seen.insert(id)
          // (a task is the same row wherever it shows — Apple's cell, its swipes and hold — in the search results too)
          let v: HomeCard
          if let old = resultCards[id] { v = old } else {
            v = HomeCard(); v.id = id
            v.onTap = { [weak self] in self?.resignSearch(); self?.send(["ev": "open", "id": id]) }
            resultCards[id] = v
          }
          v.people = people; v.set(c, look: L)
          resultViews.append(v)
        }
      }
      // (a client's page: its folders found — Apple's rows, ›, opening the folder — Haris 2026-11-10 14:08: "its tasks and assets")
      let dirs = (r["folders"] as? [[String: Any]]) ?? []
      if !dirs.isEmpty {
        let cid = (m["assets"] as? [String: Any])?["id"] as? String ?? ""
        resultViews.append(groupHead("Folders", dirs.count))
        for x in dirs {
          let id = x["id"] as? String ?? ""
          seenFiles.insert("d:" + id)
          let v = resultFiles["d:" + id] ?? { let y = FileListRow(); y.found = true; resultFiles["d:" + id] = y; return y }()
          let n = x["total"] as? Int ?? x["files"] as? Int ?? 0
          v.setFolder(x, line: [x["path"] as? String ?? "", "\(n) file\(n == 1 ? "" : "s")"].filter { !$0.isEmpty }.joined(separator: " · "), marks: (r["folderMarks"] as? [String]) ?? [], look: L)
          v.onTap = { [weak self] in self?.resignSearch(); self?.send(["ev": "folder", "client": cid, "folder": id]) }
          v.menu = nil
          resultViews.append(v)
        }
      }
      // (a client's page: its files found too — Apple's rows, each with its own identity, the words washed: Haris 2026-11-10)
      let files = (r["files"] as? [[String: Any]]) ?? []
      if !files.isEmpty {
        let fm = (r["fileMarks"] as? [String]) ?? marks
        let cid = (m["assets"] as? [String: Any])?["id"] as? String ?? ""
        let cname = (m["assets"] as? [String: Any])?["name"] as? String ?? ""
        resultViews.append(groupHead("Files", files.count))
        for (i, f) in files.enumerated() {
          let id = f["id"] as? String ?? ""
          seenFiles.insert(id)
          let v = resultFiles[id] ?? { let x = FileListRow(); x.found = true; resultFiles[id] = x; return x }()
          var at = f["where"] as? String ?? ""
          if !cname.isEmpty, at.hasPrefix(cname + " › ") { at = String(at.dropFirst(cname.count + 3)) }
          v.set(f, line: FileListRow.line(f, at: at), marks: fm, look: L)
          v.onTap = { Main.shared.quickLook(files, at: i) }
          v.menu = { [weak self] in self.map { Main.shared.assetsCtl.fileMenu($0, f, client: cid) } }
          v.onLook = { [weak self] in self?.applyList(animated: false) }
          resultViews.append(v)
        }
      }
      let none = clients.isEmpty && tasks.isEmpty && files.isEmpty && dirs.isEmpty
      // (a client's page: Apple's own "No Results" — Haris 2026-11-10; Home's keeps its line, locked)
      if none && isClient && listOn { searchEmpty.set("magnifyingglass", "No Results", "Check the spelling or try a new search."); resultViews.append(searchEmpty); hint.text = nil }
      else { hint.text = none ? (r["empty"] as? String ?? "No tasks found. Try a client or person’s name.") : nil }
    } else { hint.text = q.isEmpty ? (isClient ? "Search this client’s tasks and files." : "Search tasks, clients or people.") : nil }
    for id in resultCards.keys where !seen.contains(id) { resultCards[id] = nil }
    for id in resultFiles.keys where !seenFiles.contains(id) { resultFiles[id] = nil }
    setNeedsLayout()
    if listOn { applyList(animated: false) }   // (Apple's list: the results are its rows while searching)
  }
  // what Client Assets found (its rows, as blocks), or what to say
  func showFound(_ views: [UIView], hint t: String?) {
    if !listOn { resultViews.forEach { $0.removeFromSuperview() } }   // (Apple's list: they live in its cells — as showResults)
    resultViews = views
    hint.text = t; hint.textColor = L.empty
    if listOn { applyList(animated: false); return }   // (Apple's list: the results are its rows — Client Assets' search)
    views.forEach { results.addSubview($0) }
    setNeedsLayout()
  }
  var findText: String { field.text ?? "" }
  var onAssetsDraw: ((HomeView, [String: Any]) -> Void)?
  // (Client Assets' and Me's screens — drawn again by their own controllers, never through update)
  var isAssetsScreen: Bool { onAssetsDraw != nil }
  private func drawAssets(_ model: [String: Any]) { noteFab(); fab.isHidden = true; onAssetsDraw?(self, model) }
  private func groupHead(_ name: String, _ n: Int) -> UILabel {
    let h = UILabel(); h.tag = 7
    let s = NSMutableAttributedString(string: name.uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .kern: 0.72, .foregroundColor: L.gh])
    s.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 12), .kern: 3.6]))
    s.append(NSAttributedString(string: "\(n)", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: L.gh.withAlphaComponent(0.8)]))
    h.attributedText = s
    if !listOn { results.addSubview(h) }   // (Apple's list: its words are the group's header)
    return h
  }
  private func layoutResults() {
    let W = bounds.width, lw = W - 32
    var y: CGFloat = 0
    // (the hint: just under the search bar, in the middle of the page)
    if let t = hint.text, !t.isEmpty { let h = hint.sizeThatFits(CGSize(width: lw, height: 400)).height; hint.frame = CGRect(x: 16, y: 0, width: lw, height: h); y = h + 14 } else { hint.frame = .zero }
    for (i, v) in resultViews.enumerated() {
      if i > 0 { y += 10 }
      if v.tag == 7 { y += i > 0 ? 12 : 4; v.frame = CGRect(x: 20, y: y, width: lw - 8, height: 15); y += 15 }
      else if let b = v as? HomeBlock { let h = b.blockHeight(W); b.frame = CGRect(x: 0, y: y, width: W, height: h); y += h }
      else if let n = v as? SearchFixedNote { let h = n.height(for: lw); n.frame = CGRect(x: 16, y: y, width: lw, height: h); y += h }
      else { v.frame = CGRect(x: 16, y: y, width: lw, height: 70); y += 70 }
    }
    results.contentSize = CGSize(width: W, height: y + 20)
  }
  @objc private func statTap(_ g: UITapGestureRecognizer) {
    guard let v = g.view, !searching else { return }
    UIView.animate(withDuration: 0.08, animations: { v.transform = CGAffineTransform(scaleX: 0.96, y: 0.96) }) { _ in UIView.animate(withDuration: 0.15) { v.transform = .identity } }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let i = v.tag - 100
    if i == 2 { send(["ev": "review"]); return }
    showGroup("Overdue")
  }
  // a group's heading brought up to where the big title is (as far as the list goes)
  func showGroup(_ name: String) {
    // (a heading's key is its name and its run — "Today#1": the box found nothing to go to — Haris 2026-11-07)
    guard let h = content.first(where: { $0.tag == 7 && ($0.accessibilityIdentifier == name || ($0.accessibilityIdentifier ?? "").hasPrefix(name + "#")) }) else { return }
    if let cv = list, let ds = listDS {
      // (Apple's list: that group's heading — Today's first card, its heading being only a mark — to the top)
      guard let i = content.firstIndex(where: { $0 === h }) else { return }
      // (the group's first row — its heading is Apple's header over it, since Home is fully Apple: Haris 2026-11-09)
      let after = content[(i + 1)...].first { v in v is HomeCard || v.tag == 8 }
      let key = after.map { v -> String in (v as? HomeCard).map { "c:" + $0.id } ?? ("e:" + (v.accessibilityIdentifier ?? "")) }
      guard let k = key, let ip = ds.indexPath(for: k), let row = cv.layoutAttributesForItem(at: ip) else { return }
      // (its header, when it has one, comes into sight with it)
      let head = cv.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: ip.section))
      let goal = head.map { $0.frame.height > 0 ? $0.frame.union(row.frame) : row.frame } ?? row.frame
      // (already on screen — Today's, just under the boxes: nothing to scroll to. Scrolled "to the top" it only went part of the
      //  way into the big title's room, and Apple's bar snaps back to its big title from there — the jump: Haris 2026-11-07)
      let top = cv.contentOffset.y + cv.adjustedContentInset.top, bottom = cv.contentOffset.y + cv.bounds.height - cv.adjustedContentInset.bottom
      if goal.minY >= top, row.frame.maxY <= bottom { return }
      let maxY = max(-cv.adjustedContentInset.top, cv.contentSize.height + cv.adjustedContentInset.bottom - cv.bounds.height)
      userScrolled = true
      cv.setContentOffset(CGPoint(x: 0, y: min(maxY, goal.minY - cv.adjustedContentInset.top)), animated: true)
      return
    }
    let want = appleTop ? h.frame.minY - 12 - (safeAreaInsets.top) : h.frame.minY - (safeAreaInsets.top + 66)
    let maxY = max(-inTop, scroll.contentSize.height + inBottom - scroll.bounds.height)
    scroll.setContentOffset(CGPoint(x: 0, y: min(maxY, max(-inTop, want))), animated: true)
  }
  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { if scrollView === scroll { layoutHeader() } }
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { if scrollView === list { userScrolled = true } }

  // ---------- a toast over Home (the page's own would be under it): "Link copied", "2 files added to …", Undo ----------
  // a toast (Haris 2026-11-03, option C): "+ New task" stretches into it — "New task" fades, the capsule stretches to
  // the left with the + at its right end as a small round button, the tick, the words and Undo fade in; about 3 s later
  // (longer while a finger is on it) it shrinks back into "+ New task". A plain capsule, light and dark — no glass. A new
  // message while it's out (an upload's progress): only the words change.
  func toast(_ t: [String: Any]) {
    let text = t["t"] as? String ?? "", act = t["a"] as? String ?? ""
    let ms = (t["ms"] as? Double) ?? 3000
    let x = t["x"] as? Bool ?? false
    if let c = toastCap, c.out { c.say(text, act); c.cross(x); c.hold(ms); return }
    toastCap?.removeFromSuperview(); toastCap = nil
    layoutIfNeeded()
    let W = bounds.width
    let withFab = !fab.isHidden && fab.frame.width > 0
    let bottom = withFab ? fab.frame.maxY : (tabTop ?? bounds.height - 40) - 12
    let from = withFab ? fab.frame : CGRect(x: W - R - BTN, y: bottom - BTN, width: BTN, height: BTN)
    let to = CGRect(x: 16, y: from.minY, width: from.maxX - 16, height: from.height)
    let c = ToastCapsule(title: withFab ? (fab.accessibilityLabel ?? "New task") : nil, sym: withFab ? fabSym : nil, plus: withFab)
    c.say(text, act); c.cross(x)
    c.onUndo = { [weak self, weak c] in c?.close(); self?.onEvent?(["ev": "toast"]) }
    c.onPlus = { [weak self, weak c] in
      if c?.crossed == true { UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onToastAct?(); return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred(); if let a = self?.fabRun { a() } else { self?.send(["ev": "add"]) }
    }
    c.onGone = { [weak self, weak c] in
      guard let self = self, let c = c else { return }
      c.removeFromSuperview(); if self.toastCap === c { self.toastCap = nil; self.toastView = nil }
      self.fab.alpha = 1; self.showMotto()
    }
    c.from = from; c.to = to; c.frame = from
    addSubview(c); toastCap = c; toastView = c
    fab.alpha = 0
    showMotto()
    c.open(); c.hold(ms)
  }
  private var toastCap: ToastCapsule?
  private var fabSym = "plus"
  // (for the self-test: the first task's row — Apple's swipe actions on each side, Apple's hold menu)
  private var firstCardIP: IndexPath? { content.compactMap { $0 as? HomeCard }.first.flatMap { listDS?.indexPath(for: "c:" + $0.id) } }
  private var selfRow: [String: Any] = [:]
  func selfSwipe() { selfRow["trailing"] = firstCardIP.flatMap { swipeActions($0, leading: false) }?.actions.map { $0.title ?? "" } ?? [] }
  func selfSwipeRight() { selfRow["leading"] = firstCardIP.flatMap { swipeActions($0, leading: true) }?.actions.map { $0.title ?? "" } ?? [] }
  func selfPress() {
    guard let cv = list, let ip = firstCardIP, let m = collectionView(cv, contextMenuConfigurationForItemsAt: [ip], point: .zero) else { selfRow["menu"] = false; return }
    selfRow["menu"] = String(describing: m.identifier)
    selfRow["cell"] = (cv.cellForItem(at: ip) as? UICollectionViewListCell)?.contentConfiguration is UIListContentConfiguration
  }
  func selfClose() {}
  func selfScroll(_ y: CGFloat) { userScrolled = y > 0; sv.setContentOffset(CGPoint(x: 0, y: y - inTop), animated: false); layoutHeader(); if !appleTop { setBar(barIn, now: true) } }
  // (Apple's search on Home's own screen — HomeVC: the self-test types into it as a finger would)
  var onAppleFind: ((String?) -> Void)?
  func selfFind(_ q: String) { if appleTop, let f = onAppleFind { f(q); return }; openSearch(); field.text = q; typed() }
  // (the self-test: the first task's first word, to search for; and whether its title on screen carries search's wash)
  var selfUnavailable: Bool { if let v = list?.backgroundView { return !v.isHidden } else { return false } }
  func selfFirstWord() -> String { ((content.compactMap { $0 as? HomeCard }.first?.taskTitle ?? "").split(separator: " ").first).map(String.init) ?? "" }
  func selfWash() -> [String: Any] {
    guard let cv = list, let card = content.compactMap({ $0 as? HomeCard }).first, let ip = listDS?.indexPath(for: "c:" + card.id) else { return ["row": false] }
    cv.layoutIfNeeded()
    guard let cell = cv.cellForItem(at: ip) else { return ["row": true, "cell": false] }
    func labels(_ v: UIView) -> [UILabel] { (v as? UILabel).map { [$0] } ?? v.subviews.flatMap(labels) }
    guard let l = labels(cell.contentView).first(where: { $0.attributedText?.string == card.taskTitle }), let a = l.attributedText else { return ["row": true, "cell": true, "title": false] }
    var washed = false
    a.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: a.length)) { v, _, _ in if v != nil { washed = true } }
    return ["row": true, "cell": true, "title": true, "washed": washed]
  }
  // (the self-test, the Clients pages fully Apple — Haris 2026-11-10: what each list holds, as Apple's cells)
  func selfClientsGeo() -> [String: Any] {
    let ks = Array(listViews.keys)
    var g: [String: Any] = ["rows": ks.filter { $0.hasPrefix("k:") }.count, "folders": ks.filter { $0.hasPrefix("fd:") }.count, "cards": ks.filter { $0.hasPrefix("c:") }.count,
                            "openDone": ks.contains("b:client-open-done"), "strip": listSecs.contains { $0.tiles == .strip }, "seeAll": listSecs.contains { $0.seeAll != nil }]
    if let cv = list, let ds = listDS, let k = ks.first(where: { $0.hasPrefix("k:") || $0.hasPrefix("c:") }), let ip = ds.indexPath(for: k) {
      cv.layoutIfNeeded()
      g["appleCell"] = (cv.cellForItem(at: ip) as? UICollectionViewListCell)?.contentConfiguration is UIListContentConfiguration
    }
    return g
  }
  func selfOpenFirstClient() -> String {
    guard let r = content.first(where: { $0 is ClientListRow }) as? ClientListRow else { return "no client" }
    r.rowTapped(); return r.id
  }
  func selfDoneSwitch(_ i: Int) { doneSwitch.seg.selectedSegmentIndex = i; doneSwitch.onPick?(i) }
  // (every task's title on screen: none struck through — Done, then Open again)
  func selfStrike() -> [String: Any] {
    guard let cv = list else { return ["list": false] }
    cv.layoutIfNeeded()
    var titles = 0, struck = 0, done = 0
    for case let cell as UICollectionViewListCell in cv.visibleCells {
      guard let ip = cv.indexPath(for: cell), let k = listDS?.itemIdentifier(for: ip), let card = listViews[k] as? HomeCard else { continue }
      titles += 1
      if (card.info["done"] as? Bool) == true { done += 1 }
      if let a = (cell.contentConfiguration as? UIListContentConfiguration)?.attributedText, a.length > 0 {
        var hit = false
        a.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: a.length)) { v, _, _ in if (v as? Int ?? 0) != 0 { hit = true } }
        if hit && (card.info["done"] as? Bool) != true { struck += 1 }
      }
    }
    return ["titles": titles, "struckOpen": struck, "done": done]
  }
  func selfFindGeo() -> [String: Any] { ["searching": searching, "results": resultViews.count, "tasks": resultCards.count, "files": resultFiles.count, "hint": hint.text ?? "",
                                          "clients": resultViews.filter { $0 is HomeClientRow }.count] }
  // (the self-test — the Clients pages as the task page and Me, Haris 2026-11-10: each row's height arrived / scrolled / back
  //  at the top, and how many rows were set again — none for going away and coming back)
  private(set) var rowsSet = 0
  func selfHeights() -> [String: Double] {
    guard let cv = list, let ds = listDS else { return [:] }
    cv.layoutIfNeeded()
    var out: [String: Double] = [:]
    for c in cv.visibleCells { if let ip = cv.indexPath(for: c), let k = ds.itemIdentifier(for: ip) { out[k] = Double(c.bounds.height) } }
    for ip in cv.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
      if let v = cv.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: ip) { out["head:\(ip.section)"] = Double(v.bounds.height) }
    }
    return out
  }
  func selfScroll(_ y: CGFloat?) {
    guard let cv = list else { return }
    let top = -cv.adjustedContentInset.top
    if let y = y { cv.setContentOffset(CGPoint(x: 0, y: max(top, min(top + y, cv.contentSize.height + cv.adjustedContentInset.bottom - cv.bounds.height))), animated: false) }
    else { cv.setContentOffset(CGPoint(x: 0, y: top), animated: true) }
  }
  func selfFindDone() { if appleTop, let f = onAppleFind { f(nil); return }; closeSearch() }
  // (the walk-through: the first task and client in the results, and a tap on one — as a finger would)
  var walkFirst: (task: String?, client: String?) = (nil, nil)
  func selfTapResult(client: Bool) -> String {
    if client, let c = walkFirst.client { field.resignFirstResponder(); send(["ev": "client", "id": c]); return "client " + c }
    if let t = walkFirst.task { field.resignFirstResponder(); send(["ev": "open", "id": t]); return "task " + t }
    return "no result"
  }
  // (the walk-through: the floating button tapped, when there is one)
  func selfFab() -> Bool { guard !fab.isHidden else { return false }; if let a = fabRun { a() } else { send(["ev": "add"]) }; return true }
  func geo() -> [String: Any] {
    ["row": selfRow, "sections": listSecs.count, "groupsApple": listSecs.filter { $0.rows }.count, "unavailable": selfUnavailable,
     "title": title.text ?? "", "date": sub.text ?? "", "stats": stats.map { ($0.viewWithTag(1) as? UILabel)?.text ?? "" },
     "groups": content.filter { $0.tag == 7 }.map { ($0 as? UILabel)?.text ?? "" }, "cards": cards.count, "fab": !fab.isHidden,
     "headH": blur.frame.height, "shrink": shrink, "bar": blur.alpha, "smallTitle": smallTitle.alpha, "searching": searching,
     "searchBarW": searchBar.isHidden ? 0 : searchBar.frame.width, "results": resultViews.count,
     "apple": appleTop, "appleList": listOn, "appleBarH": appleBarHeight?() ?? 0, "listCells": list?.visibleCells.count ?? 0, "scrolledY": sv.contentOffset.y + inTop,
     "headGap": headGap()]
  }
  // (the room between a group's heading and its first row — Apple's header sits just over its group: Haris 2026-11-10 13:56)
  func headGap() -> CGFloat {
    guard let cv = list else { return -1 }
    cv.layoutIfNeeded()
    for i in 0..<listSecs.count where listSecs[i].head != nil && listSecs[i].rows && cv.numberOfItems(inSection: i) > 0 {
      guard let h = cv.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: i)),
            let r = cv.layoutAttributesForItem(at: IndexPath(item: 0, section: i)) else { continue }
      return r.frame.minY - h.frame.maxY
    }
    return -1
  }
}

// the colours the page's own Home uses (phone.css), read from it; dark / light defaults when a piece isn't on it
struct HomeLook {
  // the line between rows in Apple's lists, every Apple page (Haris 2026-11-10: Apple's own, "softer"): Apple's separator,
  // a little fainter — light and dark, as Apple switches it; worked out once per look
  private static var lineMade: [Int: UIColor] = [:]
  static let line: UIColor = UIColor { t in
    let k = t.userInterfaceStyle.rawValue
    if let c = HomeLook.lineMade[k] { return c }
    let s = UIColor.separator.resolvedColor(with: t)
    var a: CGFloat = 0; s.getWhite(nil, alpha: &a)
    let c = s.withAlphaComponent(a * 0.7)
    HomeLook.lineMade[k] = c
    return c
  }
  // every colour holds both looks (Look.c): the website's measured colours for each look when it has sent them (Main
  // keeps the last of each — Main.lookBoth), else the app's own — so iPhone switches them itself
  let bg, headBg, sub, h1, round, roundIc, statLabel, statG, statR, statA, gh, empty: UIColor
  let card, title, meta, sep, late, today, doneTitle, tag, tagBg, urgent, urgentBg, more, moreBg, fabBg, fabLine: UIColor
  let headH: CGFloat?, fabRect: CGRect?
  // (which colours these are — the same for the same website colours: a drawing's signature, never the colour objects,
  //  which are new each time)
  let key: String
  // d: { dark: {…}?, light: {…}? } — or one look's colours as the website sends them ({ light: Bool, bg: […], … })
  init(_ d: [String: Any]?) {
    var dk = d?["dark"] as? [String: Any], lt = d?["light"] as? [String: Any]
    if dk == nil, lt == nil, let one = d, one["light"] is Bool { if (one["light"] as? Bool) == true { lt = one } else { dk = one } }
    key = drawSig(dk ?? [:]) + "§" + drawSig(lt ?? [:])
    func rgb(_ x: [String: Any]?, _ k: String) -> UIColor? {
      guard let a = x?[k] as? [NSNumber], a.count >= 3 else { return nil }
      return UIColor(red: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: a.count > 3 ? CGFloat(a[3].doubleValue) : 1)
    }
    func c(_ k: String, _ dark: UIColor, _ light: UIColor) -> UIColor { Look.c(rgb(dk, k) ?? dark, rgb(lt, k) ?? light) }
    let w = UIColor.white, k = UIColor.black
    let bgD = SplashView.hex(0x0c0d0f), bgL = SplashView.hex(0xf4f4f7)
    bg = c("bg", bgD, bgL); headBg = Look.c(rgb(dk, "headBg") ?? rgb(dk, "bg") ?? bgD, rgb(lt, "headBg") ?? rgb(lt, "bg") ?? bgL)
    // (every grey on the app's own screens is the date's grey: iPhone's secondary label — Haris, 2026-10-31)
    let grey = UIColor.secondaryLabel
    let h1D = SplashView.hex(0xe9eaee), h1L = SplashView.hex(0x17181b)
    sub = grey; h1 = c("h1", h1D, h1L)
    round = c("round", w.withAlphaComponent(0.08), k.withAlphaComponent(0.05))
    roundIc = Look.c(rgb(dk, "roundIc") ?? rgb(dk, "h1") ?? h1D, rgb(lt, "roundIc") ?? rgb(lt, "h1") ?? h1L)
    statLabel = grey
    statG = c("statG", SplashView.hex(0x3ddc97), SplashView.hex(0x1a9e63)); statR = c("statR", SplashView.hex(0xff7a7a), SplashView.hex(0xd9363e)); statA = c("statA", SplashView.hex(0xf9be33), SplashView.hex(0xb57d00))
    gh = grey; empty = grey
    card = c("card", SplashView.hex(0x121317), w)
    title = c("title", SplashView.hex(0xe9eaee), SplashView.hex(0x17181b)); meta = grey
    sep = grey; late = c("late", SplashView.hex(0xff8a8a), SplashView.hex(0xd9363e)); today = c("today", SplashView.hex(0x8fbcff), SplashView.hex(0x2f6fd6))
    doneTitle = grey
    tag = c("tag", SplashView.hex(0xc9c0ff), SplashView.hex(0x5b4bd6)); tagBg = c("tagBg", UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.18), UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.14))
    urgent = c("urgent", SplashView.hex(0xff9494), SplashView.hex(0xd9363e)); urgentBg = c("urgentBg", UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.16), UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.12))
    more = grey; moreBg = c("moreBg", w.withAlphaComponent(0.08), k.withAlphaComponent(0.06))
    let fd = dk?["fab"] as? [String: Any], fl = lt?["fab"] as? [String: Any]
    fabBg = Look.c(rgb(fd, "bg") ?? SplashView.hex(0x5b4bd6), rgb(fl, "bg") ?? SplashView.hex(0x5b4bd6)); fabLine = Look.c(rgb(fd, "line") ?? .clear, rgb(fl, "line") ?? .clear)
    let f = fd ?? fl
    if let r = f?["rect"] as? [NSNumber], r.count == 4, r[2].doubleValue > 0 { fabRect = CGRect(x: r[0].doubleValue, y: r[1].doubleValue, width: r[2].doubleValue, height: r[3].doubleValue) } else { fabRect = nil }
    headH = ((dk ?? lt)?["headH"] as? NSNumber).map { CGFloat($0.doubleValue) }
  }
}

// A task in a list — Home, My Tasks, a client's page, search (Haris 2026-11-09, Home fully Apple: mock-up "E11 Day — fully
// Apple"). Apple's own list cell shows it, set by Apple's content configuration (`content`): the status symbol in the
// status colour, the title, the line under it — the client, status, due date, comments, with our CD chip in it (room
// above it when it wraps: Haris 11:26) — and, in search, where it was found as one more line (Haris 11:35: Apple's third
// line, no box). This view is only what Apple has no part for, the cell's accessory at its right: our Urgent / P1 tag and
// the faces (a green ring for one whose part is done, "+N" for more). The cell's tap, hold (Apple's menu with its own lift)
// and swipes are the list's own (HomeView).
protocol AppleRow: UIView {
  var rowContent: UIListContentConfiguration { get }
  var rowChevron: Bool { get }   // (Apple's › at its right — all but a row that opens in place, as Inactive Clients)
  var rowSig: String { get }
  var rowHasAccessory: Bool { get }
  var rowLeading: Bool { get }
  var rowLate: Bool { get }
  func rowTapped()
}
extension AppleRow { var rowChevron: Bool { true } }
final class HomeCard: UIView, AppleRow {
  var onTap: (() -> Void)?
  var id = ""
  var taskTitle: String { c["title"] as? String ?? "" }
  var info: [String: Any] { c }
  private var inline = false   // (a Today card: one line, comments and the CD chip on it)
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { drawPeople() } } }
  private let badge = UILabel(), avs = UIView()
  private var c: [String: Any] = [:]
  private var L = HomeLook(nil)
  private var stackW: CGFloat = 0
  private(set) var rowContent = UIListContentConfiguration.subtitleCell()
  private var drawnSig = "", peopleSig = 0
  var rowSig: String { drawnSig + "|\(peopleSig)" }
  var rowHasAccessory: Bool { stackW > 0 || !badge.isHidden }
  var rowLeading: Bool { false }
  // (overdue: a faint red tint on its row — Haris 2026-11-09 12:35, approved on the mock-up)
  var rowLate: Bool { (c["late"] as? Bool) == true }
  func rowTapped() { onTap?() }
  // the row's colour: the card's, with a faint red blended in when it's overdue (both looks: 10% in dark, 6% in light)
  static func rowColor(_ card: UIColor, late: Bool) -> UIColor {
    guard late else { return card }
    return UIColor { tc in
      let dark = tc.userInterfaceStyle != .light, a: CGFloat = dark ? 0.10 : 0.06
      var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
      card.resolvedColor(with: tc).getRed(&r, green: &g, blue: &b, alpha: &al)
      return UIColor(red: r * (1 - a) + 229 / 255 * a, green: g * (1 - a) + 72 / 255 * a, blue: b * (1 - a) + 77 / 255 * a, alpha: 1)
    }
  }
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false   // (a tap anywhere on the row is the cell's own)
    badge.layer.cornerRadius = 6; badge.clipsToBounds = true; badge.textAlignment = .center; badge.isHidden = true
    [badge, avs].forEach { addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }

  func set(_ d: [String: Any], look: HomeLook) {
    // (the same as it shows: left as it is — its faces, words and icon not made again: Haris 2026-11-08)
    let sig = drawSig(d) + "|" + look.key
    c = d; L = look
    if sig == drawnSig { return }
    drawnSig = sig
    let done = (d["done"] as? Bool) == true
    var cfg = UIListContentConfiguration.subtitleCell()
    // the status symbol (Apple's, in the status colour)
    cfg.image = HomeCard.statusIcon(d["icon"] as? [String: Any])
    cfg.imageProperties.reservedLayoutSize = CGSize(width: 22, height: 22)
    cfg.imageToTextPadding = 12
    // the title (the words searched for washed yellow)
    let t = d["title"] as? String ?? ""
    let ps = NSMutableParagraphStyle(); ps.minimumLineHeight = 20.15; ps.maximumLineHeight = 20.15
    var ta: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15.5, weight: t.isEmpty ? .medium : .semibold), .foregroundColor: done || t.isEmpty ? L.doneTitle : L.title, .paragraphStyle: ps, .baselineOffset: 1.5]
    if t.isEmpty { ta[.font] = UIFont.italicSystemFont(ofSize: 15.5) }
    // (said either way, never left out: Apple's label reused from a done task kept its line through the words when the
    //  next title simply had none — My Tasks' Done then All struck every title, Haris 2026-11-09)
    ta[.strikethroughStyle] = done ? NSUnderlineStyle.single.rawValue : 0
    let marks = (d["marks"] as? [String]) ?? []
    cfg.attributedText = t.isEmpty || marks.isEmpty ? NSAttributedString(string: t.isEmpty ? "Untitled task" : t, attributes: ta)
      : HomeCard.marked(t, marks, base: ta, mark: [.backgroundColor: Find.wash])
    cfg.textProperties.numberOfLines = 0
    // the line under it, with the CD chip (CD Review / ✓ CD Approved) at its end — after the comments, on its last line
    // when it fits (Haris, 2026-10-31: "1 comment" and the chip together)
    inline = (d["inline"] as? Bool) == true
    let ml = NSMutableAttributedString(attributedString: meta(d["meta"] as? [[String: Any]] ?? []))
    if let cd = d["cd"] as? [String: Any] {
      let img = HomeCard.cdChip(cd["t"] as? String ?? "", check: (cd["check"] as? Bool) == true, color: NativeSheetVC.color(cd["rgb"]) ?? .systemYellow)
      let a = NSTextAttachment(); a.image = img
      let f = UIFont.systemFont(ofSize: 12.5)
      a.bounds = CGRect(x: 0, y: ((f.capHeight - img.size.height) / 2).rounded(), width: img.size.width, height: img.size.height)
      let hasCm = inline || (d["meta"] as? [[String: Any]] ?? []).contains(where: HomeCard.isComments)
      if ml.length > 0 { ml.append(NSAttributedString(string: hasCm ? " " : "\n", attributes: hasCm ? [.font: f, .kern: 4.9] : [.font: f])) }
      ml.append(NSAttributedString(attachment: a))
    }
    // (search: where it was found, when not by its title — one more line, the words in blue: Haris 11:35)
    if let fd = d["found"] as? [String: Any] {
      if ml.length > 0 { ml.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: 12.5)])) }
      ml.append(NSAttributedString(string: (fd["label"] as? String ?? "") + ": ", attributes: [.font: UIFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: L.title]))
      ml.append(HomeCard.marked(fd["text"] as? String ?? "", marks, base: [.font: UIFont.systemFont(ofSize: 12.5), .foregroundColor: L.meta], mark: [.foregroundColor: UIColor.systemBlue, .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold)]))
    }
    // (the chip room above it when the line wraps — it touched the words over it: Haris 11:26)
    let lp = NSMutableParagraphStyle(); lp.lineSpacing = 5
    ml.addAttribute(.paragraphStyle, value: lp, range: NSRange(location: 0, length: ml.length))
    cfg.secondaryAttributedText = ml.length > 0 ? ml : nil
    cfg.secondaryTextProperties.numberOfLines = 0
    cfg.textToSecondaryTextVerticalPadding = 5
    rowContent = cfg
    // Urgent, or the priority number: our tag, over the faces
    if let b = d["badge"] as? [String: Any] {
      let u = (b["urgent"] as? Bool) == true
      badge.isHidden = false
      badge.attributedText = NSAttributedString(string: b["t"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: u ? L.urgent : L.tag])
      badge.backgroundColor = u ? L.urgentBg : L.tagBg
    } else { badge.isHidden = true }
    drawPeople()
  }
  // the words searched for, marked wherever they start a word (accents and case don't matter)
  static func marked(_ text: String, _ words: [String], base: [NSAttributedString.Key: Any], mark: [NSAttributedString.Key: Any]) -> NSAttributedString {
    let s = NSMutableAttributedString(string: text, attributes: base)
    let ns = text as NSString
    for w in words { for r in Find.ranges(w, ns) { s.addAttributes(mark, range: r) } }
    return s
  }
  static func isComments(_ it: [String: Any]) -> Bool {
    if (it["cm"] as? Bool) == true { return true }
    let t = (it["t"] as? String ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
    return t.hasSuffix(" comment") || t.hasSuffix(" comments")
  }
  // the line under the title: client (with its colour), status, due date, comments — "·" between
  private func meta(_ items: [[String: Any]]) -> NSAttributedString {
    let f = UIFont.systemFont(ofSize: 12.5)
    let s = NSMutableAttributedString()
    // (as the page wraps it: whole pieces only — "3 comments" never split — and a "·" stays at the end of its line)
    let gap = { (breaks: Bool) in NSAttributedString(string: breaks ? " " : "\u{00A0}", attributes: [.font: f, .kern: 2.9]) }
    // (the comments always start the second line, the CD chip after them — the same on every card, Haris 2026-10-31)
    for (i, it) in items.enumerated() {
      let cm = HomeCard.isComments(it) && !inline
      // (My Tasks' Done tab: "Completed Oct 30 — read only" on a line of its own, after a lock)
      let own = (it["line"] as? Bool) == true
      if i > 0 && (cm || own) { s.append(NSAttributedString(string: "\n", attributes: [.font: f])) }
      else if i > 0 { s.append(gap(false)); s.append(NSAttributedString(string: "·", attributes: [.font: f, .foregroundColor: L.sep])); s.append(gap(true)) }
      // (the client's colour: Apple's circle — Haris 2026-11-09)
      if let dot = NativeSheetVC.color(it["dot"]), let img = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 7))?.withTintColor(dot, renderingMode: .alwaysOriginal) {
        let a = NSTextAttachment(); a.image = img; a.bounds = CGRect(x: 0, y: 0.5, width: img.size.width, height: img.size.height)
        s.append(NSAttributedString(attachment: a)); s.append(gap(false))
      }
      let b = it["b"] as? String
      let col = b == "late" ? L.late : b == "today" ? L.today : L.meta
      if (it["lock"] as? Bool) == true, let lk = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))?.withTintColor(col, renderingMode: .alwaysOriginal) {
        let a = NSTextAttachment(); a.image = lk; a.bounds = CGRect(x: 0, y: -0.5, width: lk.size.width, height: lk.size.height)
        s.append(NSAttributedString(attachment: a)); s.append(gap(false))
      }
      s.append(NSAttributedString(string: (it["t"] as? String ?? "").replacingOccurrences(of: " ", with: "\u{00A0}"), attributes: [.font: b != nil ? UIFont.systemFont(ofSize: 12.5, weight: .semibold) : f, .foregroundColor: col]))
    }
    return s
  }
  // the assignees' pictures (two, overlapping; a green ring when their part is done — Haris 11:30) and "+N"
  private func drawPeople() {
    avs.subviews.forEach { $0.removeFromSuperview() }
    let list = c["av"] as? [[String: Any]] ?? []
    var x: CGFloat = 0
    func ringed(_ img: UIImage, done: Bool) -> UIView {
      let r = UIView(frame: CGRect(x: x - 2, y: -2, width: 26, height: 26)); r.backgroundColor = done ? SplashView.green : HomeCard.rowColor(L.card, late: rowLate); r.layer.cornerRadius = 13
      let iv = UIImageView(image: img); iv.frame = CGRect(x: 2, y: 2, width: 22, height: 22); r.addSubview(iv)
      return r
    }
    for a in list {
      let id = a["id"] as? String ?? ""
      let p = people[id]
      avs.addSubview(ringed(roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 22), done: (a["done"] as? Bool) == true))
      x += 16
    }
    if let n = c["more"] as? Int, n > 0 {
      let r = UIView(frame: CGRect(x: x - 2, y: -2, width: 26, height: 26)); r.backgroundColor = HomeCard.rowColor(L.card, late: rowLate); r.layer.cornerRadius = 13
      let l = UILabel(frame: CGRect(x: 2, y: 2, width: 22, height: 22)); l.text = "+\(n)"; l.font = .systemFont(ofSize: 9.5, weight: .semibold); l.textColor = L.more
      l.backgroundColor = L.moreBg; l.layer.cornerRadius = 11; l.clipsToBounds = true; l.textAlignment = .center
      r.addSubview(l); avs.addSubview(r); x += 16
    }
    // (22 for the first, 16 more for each next one: they overlap by 6)
    stackW = x > 0 ? x + 6 : 0
    peopleSig += 1
    let s = sideSize()
    frame.size = s
    invalidateIntrinsicContentSize(); setNeedsLayout()
  }
  // (the tag over the faces, at the cell's right)
  private func sideSize() -> CGSize {
    var w: CGFloat = 0, h: CGFloat = 0
    if !badge.isHidden { let s = badge.attributedText?.size() ?? .zero; w = ceil(s.width) + 14; h = ceil(s.height) + 6 }
    if stackW > 0 { w = max(w, stackW); h += (h > 0 ? 6 : 0) + 22 }
    return CGSize(width: w, height: h)
  }
  override var intrinsicContentSize: CGSize { sideSize() }
  override func sizeThatFits(_ size: CGSize) -> CGSize { sideSize() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width
    var y: CGFloat = 0
    if !badge.isHidden { let s = badge.attributedText?.size() ?? .zero; badge.frame = CGRect(x: w - ceil(s.width) - 14, y: y, width: ceil(s.width) + 14, height: ceil(s.height) + 6); y = badge.frame.maxY + 6 }
    if stackW > 0 { avs.frame = CGRect(x: w - stackW, y: y, width: stackW, height: 22) }
  }
  // the CD chip (app.css .cd-chip): 10.5 bold in the CD colour on a 16% wash, 4 round, a tick before "CD Approved" —
  // the tick and the words on one centre line
  static func cdChip(_ text: String, check: Bool, color: UIColor) -> UIImage {
    let f = UIFont.systemFont(ofSize: 10.5, weight: .bold)
    let ts = (text as NSString).size(withAttributes: [.font: f])
    let tick: CGFloat = check ? 10 + 3 : 0
    let size = CGSize(width: ceil(6 + tick + ts.width + 6), height: 16)
    return UIGraphicsImageRenderer(size: size).image { _ in
      color.withAlphaComponent(0.16).setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4).fill()
      if check, let ck = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))?.withTintColor(color, renderingMode: .alwaysOriginal) {
        ck.draw(in: CGRect(x: 6 + (10 - ck.size.width) / 2, y: (16 - ck.size.height) / 2, width: ck.size.width, height: ck.size.height))
      }
      (text as NSString).draw(at: CGPoint(x: 6 + tick, y: (16 - ts.height) / 2), withAttributes: [.font: f, .foregroundColor: color])
    }
  }
  // the status icon, in SF Symbols (Haris, 2026-10-31): to do — a dashed circle; under way — a half-filled circle; nearly
  // there (the later statuses) — a filled circle in a ring; done — a filled circle with a tick. In the status's colour.
  static func statusIcon(_ d: [String: Any]?) -> UIImage {
    let col = NativeSheetVC.color(d?["rgb"]) ?? .systemGray
    let kind = d?["kind"] as? String ?? "todo"
    let frac = CGFloat((d?["frac"] as? NSNumber)?.doubleValue ?? 0.5)
    let name = kind == "done" ? "checkmark.circle.fill" : kind == "todo" ? "circle.dashed" : frac < 0.6 ? "circle.lefthalf.filled" : "circle.inset.filled"
    let cfg = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
    let sym = UIImage(systemName: name, withConfiguration: cfg)?.withTintColor(col, renderingMode: .alwaysOriginal) ?? UIImage()
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
      sym.draw(in: CGRect(x: (22 - sym.size.width) / 2, y: (22 - sym.size.height) / 2, width: sym.size.width, height: sym.size.height))
    }.withRenderingMode(.alwaysOriginal)
  }
}

// the colours of Apple's swipe actions on a task (Done green, Due purple, Copy link grey; Review orange)
enum TaskSwipe {
  static let grey = SplashView.hex(0x8a8d96), green = SplashView.hex(0x30d158), purple = SplashView.hex(0x7a6ff0), orange = SplashView.hex(0xff9f0a)
}

// a label going or coming through a blur that builds up / clears frame by frame (Mail's bar titles): its copies at a few
// blur strengths, the nearest two shown over each other; sharp (the label itself) when there's no blur
final class HomeBlurFade {
  static let radii: [CGFloat] = [0, 1.5, 3, 4.5, 6, 8, 11]
  static let ci = CIContext()
  weak var label: UILabel?
  private let a = UIImageView(), b = UIImageView()
  private var imgs: [UIImage] = [], key = ""
  private let pad: CGFloat = 22
  init(_ l: UILabel) { label = l; [a, b].forEach { $0.isUserInteractionEnabled = false; $0.isHidden = true } }
  private func ready(_ trait: UITraitCollection) -> Bool {
    guard let l = label, let text = l.text, !text.isEmpty, let font = l.font, l.bounds.width > 0, l.bounds.height > 0 else { return false }
    let colour = (l.textColor ?? .label).resolvedColor(with: trait)
    let k = "\(text)|\(l.bounds.size)|\(colour)|\(font.pointSize)|\(font.fontName)"
    if k == key { return !imgs.isEmpty }
    key = k; imgs = []
    let fmt = UIGraphicsImageRendererFormat.preferred(); let sc = fmt.scale, bs = l.bounds.size, p = pad
    let size = CGSize(width: bs.width + p * 2, height: bs.height + p * 2)
    // (as the label draws it: shrunk to fit if it does, middle of its height)
    let fit = l.adjustsFontSizeToFitWidth ? min(1, max(l.minimumScaleFactor, bs.width / max(1, (text as NSString).size(withAttributes: [.font: font]).width))) : 1
    let f2 = fit < 1 ? font.withSize(font.pointSize * fit) : font
    let sharp = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
      NSAttributedString(string: text, attributes: [.font: f2, .foregroundColor: colour])
        .draw(with: CGRect(x: p, y: p + (bs.height - f2.lineHeight) / 2, width: bs.width, height: f2.lineHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
    guard let src = CIImage(image: sharp) else { return false }
    for r in HomeBlurFade.radii {
      if r == 0 { imgs.append(sharp); continue }
      guard let f = CIFilter(name: "CIGaussianBlur") else { imgs = []; return false }
      f.setValue(src, forKey: kCIInputImageKey); f.setValue(r * sc, forKey: kCIInputRadiusKey)
      guard let o = f.outputImage?.cropped(to: src.extent), let cg = Self.ci.createCGImage(o, from: src.extent) else { imgs = []; return false }
      imgs.append(UIImage(cgImage: cg, scale: sc, orientation: .up))
    }
    return true
  }
  // blur (points; 0 = sharp), how see-through, how far below its place
  func set(blur r: CGFloat, alpha: CGFloat, dy: CGFloat, trait: UITraitCollection) {
    guard let l = label else { return }
    let t = CGAffineTransform(translationX: 0, y: dy)
    if l.transform != t { l.transform = t }
    if alpha < 0.01 { l.alpha = 0; a.isHidden = true; b.isHidden = true; return }
    if r < 0.2 || !ready(trait) { l.alpha = alpha; a.isHidden = true; b.isHidden = true; return }
    if a.superview !== l.superview { l.superview?.insertSubview(a, aboveSubview: l); l.superview?.insertSubview(b, aboveSubview: a) }
    let R = HomeBlurFade.radii
    var i = 0; while i < R.count - 2 && r > R[i + 1] { i += 1 }
    let f = min(1, max(0, (r - R[i]) / (R[i + 1] - R[i])))
    l.alpha = 0
    for v in [a, b] { v.bounds = CGRect(origin: .zero, size: imgs[0].size); v.center = l.center; v.transform = t; v.isHidden = false }
    a.image = imgs[i]; b.image = imgs[i + 1]
    a.alpha = alpha; b.alpha = alpha * f
  }
  func clear() { a.isHidden = true; b.isHidden = true; label?.transform = .identity }
}

// a Liquid Glass circle or capsule (iOS 26+: iPhone's own glass; before: a thin blur with a light edge)
final class HomeGlass: UIView {
  var onTap: (() -> Void)?
  let content = UIView()
  private let fx = UIVisualEffectView(effect: nil), icon = UIImageView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    fx.isUserInteractionEnabled = true   // (the search bar's field, inside it, gets its taps — its ✕ too)
    addSubview(fx)
    content.isUserInteractionEnabled = true
    fx.contentView.addSubview(content)
    icon.contentMode = .center; addSubview(icon)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    isAccessibilityElement = true; accessibilityTraits = .button
    fx.clipsToBounds = true
    if #available(iOS 26.0, *) {
      let g = UIGlassEffect(style: .regular); g.isInteractive = true
      fx.effect = g
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func tap() { onTap?() }
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { g is UITapGestureRecognizer ? onTap != nil : true }
  func setIcon(_ sym: String, _ size: CGFloat) { icon.image = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium)) }
  func setLook(tint: UIColor) {
    icon.tintColor = tint
    if #available(iOS 26.0, *) { return }
    fx.effect = UIBlurEffect(style: .systemUltraThinMaterial)
    fx.layer.borderWidth = 1; fx.followLook("border") { [weak fx] tc in fx?.layer.setBorder(Look.c(UIColor.white.withAlphaComponent(0.18), UIColor.white.withAlphaComponent(0.6)), tc) }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    fx.frame = bounds; content.frame = fx.contentView.bounds; icon.frame = bounds
    fx.layer.cornerRadius = min(bounds.height, bounds.width) / 2
  }
  // (the search bar's field gets the taps inside it; the glass itself only when there's no field)
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let v = super.hitTest(point, with: event)
    if let v = v, v !== self, v.isDescendant(of: content), v !== content { return v }
    return v == nil ? nil : self
  }
}

// a client in the search results (phone.js search(): the coloured square with its initials, the name, its open tasks)
// a client found by search: Apple's own list cell (Haris 2026-11-09: "yes") — its coloured square in the cell's image spot,
// the name (the words searched for washed yellow) and "Client · N open tasks", Apple's ›. Not drawn itself: its cell is.
final class HomeClientRow: UIView, AppleRow {
  var onTap: (() -> Void)?
  private(set) var rowContent = UIListContentConfiguration.subtitleCell()
  private(set) var rowSig = ""
  var rowHasAccessory: Bool { false }
  var rowLeading: Bool { false }
  var rowLate: Bool { false }
  func rowTapped() { onTap?() }
  func set(_ c: [String: Any], look L: HomeLook) {
    let sig = drawSig(c) + "|" + L.key
    if sig == rowSig { return }
    rowSig = sig
    var cfg = UIListContentConfiguration.subtitleCell()
    let ini = c["ini"] as? String ?? "", col = NativeSheetVC.color(c["rgb"]) ?? .systemIndigo
    cfg.image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { _ in
      col.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 11).fill()
      let f = UIFont.systemFont(ofSize: 14, weight: .heavy), s = (ini as NSString).size(withAttributes: [.font: f])
      (ini as NSString).draw(at: CGPoint(x: (40 - s.width) / 2, y: (40 - s.height) / 2), withAttributes: [.font: f, .foregroundColor: UIColor.white])
    }.withRenderingMode(.alwaysOriginal)
    cfg.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
    cfg.imageToTextPadding = 12
    let name = c["name"] as? String ?? ""
    let base: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15.5, weight: .semibold), .foregroundColor: L.title]
    let mk = (c["marks"] as? [String]) ?? []
    cfg.attributedText = mk.isEmpty ? NSAttributedString(string: name, attributes: base) : HomeCard.marked(name, mk, base: base, mark: [.backgroundColor: Find.wash])
    let n = c["open"] as? Int ?? 0
    cfg.secondaryAttributedText = NSAttributedString(string: "Client · \(n) open task\(n == 1 ? "" : "s")", attributes: [.font: UIFont.systemFont(ofSize: 12.5), .foregroundColor: L.meta])
    cfg.textToSecondaryTextVerticalPadding = 3
    rowContent = cfg
    accessibilityLabel = name
  }
}

// a view that only takes touches on what's in it (the bar's row: the list under its empty parts still scrolls)
final class HomePassThrough: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { let v = super.hitTest(point, with: event); return v === self ? nil : v }
}

// ---------- the Inbox: a notification as Apple's own list cell (Haris 2026-11-09/10, mock-up "Inbox — with the rules", B) ----------
// Apple's cell, set by Apple's configuration: the person's picture, who did what (bold while unread), the task and one line
// of what. Apple's highlight, Apple's swipe (Read / Unread), Apple's hold with its peek, Apple's line between rows. Ours,
// inside Apple's cell (said plainly, approved 2026-11-10 09:09): the unread dot, and the time on the first line as Mail's —
// Apple's cell has neither. This view is that: it lies over the cell, takes no touches, and holds the row's data.
final class InboxRow: UIView {
  var onTap: (() -> Void)?, onToggle: (() -> Void)?
  var id = ""
  private(set) var read = false
  private(set) var info: [String: Any] = [:]
  private(set) var photo: UIImage?
  var rowSig = ""   // (what the cell shows — set again only when it changed)
  private let dot = UIView(), when = UILabel(), chev = UIImageView()
  // Mail's measures (from Haris's screenshots, 2026-11-01): the picture 44 at 34, the words from 88, 18 from the right
  static let headFont = UIFont.systemFont(ofSize: 16.5, weight: .semibold), headFontRead = UIFont.systemFont(ofSize: 16.5)
  static let lineFont = UIFont.systemFont(ofSize: 14)
  static let top: CGFloat = 11, lead: CGFloat = 34, trail: CGFloat = 18, pic: CGFloat = 44, gap: CGFloat = 10
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    dot.backgroundColor = .systemBlue; dot.layer.cornerRadius = 3.9
    when.font = InboxRow.lineFont; when.textColor = .secondaryLabel; when.textAlignment = .right
    // (Mail's › beside the time on the first line, as the Inbox had it — Haris 2026-11-10: "› on the rows will be there")
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    chev.tintColor = .tertiaryLabel; chev.contentMode = .bottom
    addSubview(dot); addSubview(when); addSubview(chev)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ r: [String: Any], photo: UIImage?) {
    info = r
    id = r["id"] as? String ?? ""
    read = (r["read"] as? Bool) == true
    self.photo = photo
    dot.isHidden = read
    when.text = InboxRow.label(r["at"] as? String ?? "")
    setNeedsLayout()
  }
  var head: String { info["head"] as? String ?? "" }
  // Apple's content: the first line kept clear of the time (it's cut with … before it, as Mail's)
  func content(width W: CGFloat) -> UIListContentConfiguration {
    var c = UIListContentConfiguration.subtitleCell()
    c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: InboxRow.top, leading: InboxRow.lead, bottom: InboxRow.top, trailing: InboxRow.trail)
    c.image = photo
    c.imageProperties.maximumSize = CGSize(width: InboxRow.pic, height: InboxRow.pic)
    c.imageProperties.reservedLayoutSize = CGSize(width: InboxRow.pic, height: InboxRow.pic)
    c.imageProperties.cornerRadius = InboxRow.pic / 2
    c.imageToTextPadding = InboxRow.gap
    c.textToSecondaryTextVerticalPadding = 3
    let font = read ? InboxRow.headFontRead : InboxRow.headFont
    c.text = InboxRow.fit(head, font: font, width: W - InboxRow.lead - InboxRow.pic - InboxRow.gap - InboxRow.trail - whenWidth - 9 - 7 - 8)
    c.textProperties.font = font; c.textProperties.color = .label; c.textProperties.numberOfLines = 1
    // the task, then one line of what — each its own line, cut with … (Apple's second text, two lines)
    let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
    let task = (info["title"] as? String) ?? "", what = (info["desc"] as? String) ?? ""
    let t = NSMutableAttributedString(string: task.isEmpty ? " " : task, attributes: [.font: InboxRow.lineFont, .foregroundColor: UIColor.label, .paragraphStyle: ps])
    t.append(NSAttributedString(string: "\n" + (what.isEmpty ? " " : what), attributes: [.font: InboxRow.lineFont, .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: ps]))
    c.secondaryAttributedText = t
    c.secondaryTextProperties.numberOfLines = 2
    return c
  }
  var whenWidth: CGFloat { ceil(when.sizeThatFits(CGSize(width: 200, height: 22)).width) }
  // the words cut to the room, with … (only when they don't fit)
  static func fit(_ s: String, font: UIFont, width: CGFloat) -> String {
    let w = { (x: String) in ceil((x as NSString).size(withAttributes: [.font: font]).width) }
    guard width > 20, w(s) > width else { return s }
    var lo = 0, hi = s.count
    while lo < hi { let mid = (lo + hi + 1) / 2; if w(String(s.prefix(mid)).trimmingCharacters(in: .whitespaces) + "…") <= width { lo = mid } else { hi = mid - 1 } }
    return String(s.prefix(lo)).trimmingCharacters(in: .whitespaces) + "…"
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    // the dot centred on the picture, at 20.7 from the edge; the time on the first line's baseline, 18 from the right
    dot.frame = CGRect(x: 20.7 - 3.9, y: H / 2 - 3.9, width: 7.8, height: 7.8)
    let ww = whenWidth
    let base = InboxRow.top + InboxRow.headFont.ascender
    chev.frame = CGRect(x: W - InboxRow.trail - 9, y: base - 11, width: 9, height: 13)
    when.frame = CGRect(x: chev.frame.minX - 7 - ww, y: base - when.font.ascender, width: ww, height: ceil(when.font.lineHeight))
  }
  var accessibilityText: String {
    [read ? nil : "Unread", head, info["title"] as? String, info["desc"] as? String, when.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
  }
  // when, as Mail: 12:30 PM · Yesterday · Friday · Oct 29 · Oct 29, 2025
  static func label(_ iso: String) -> String {
    let p = ISO8601DateFormatter(); p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = p.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let cal = Calendar.current, f = DateFormatter(); f.locale = Locale(identifier: "en_US")
    if cal.isDateInToday(d) { f.dateFormat = "h:mm a"; return f.string(from: d) }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 99
    if days < 7 { f.dateFormat = "EEEE"; return f.string(from: d) }
    f.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: Date()) ? "MMM d" : "MMM d, yyyy"
    return f.string(from: d)
  }
}
// Apple's list cell for an Inbox row: Apple's content, Apple's highlight on the page's own background, the row's dot and time
// over it; the first line set again only if the cell's width changed what fits
final class InboxCell: UICollectionViewListCell {
  private(set) weak var row: InboxRow?
  private var fitW: CGFloat = 0
  private var shownSig = ""
  func show(_ r: InboxRow) {
    // (the same row with something new — read, unread, a new line: it crossfades in place, never snaps — the smoothness rule)
    let fade = row === r && shownSig != r.rowSig && window != nil
    if row !== r { if let old = row, old.superview === contentView { old.removeFromSuperview() }; row = r }
    shownSig = r.rowSig
    fitW = bounds.width
    let w = fitW > 0 ? fitW : (window?.bounds.width ?? UIScreen.main.bounds.width)
    if fade { UIView.transition(with: contentView, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: { self.contentConfiguration = r.content(width: w) }) }
    else { contentConfiguration = r.content(width: w) }
    // (inside the cell's content: Apple's swipe moves it with the words)
    if r.superview !== contentView { contentView.addSubview(r) }
    isAccessibilityElement = true; accessibilityLabel = r.accessibilityText; accessibilityTraits = .button
    accessibilityIdentifier = "inbox-row"
    setNeedsLayout()
  }
  override func updateConfiguration(using state: UICellConfigurationState) {
    var bg = UIBackgroundConfiguration.listPlainCell().updated(for: state)
    if !state.isHighlighted && !state.isSelected { bg.backgroundColor = .clear }
    backgroundConfiguration = bg
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.width > 0 && abs(bounds.width - fitW) > 0.5, let r = row { fitW = bounds.width; contentConfiguration = r.content(width: fitW) }
    if let r = row {
      if r.superview !== contentView { contentView.addSubview(r) }   // (the content set again: the row kept on top of it)
      r.frame = contentView.bounds; contentView.bringSubviewToFront(r)
    }
  }
}

// ---------- Mail's category buttons (28+): the same everywhere in the app (Haris, 2026-11-01) ----------
// Solid (not glass), 38 tall, 9 apart, from 16 in. Not chosen: 49 wide, icon only — light #EAEAEC with a #868689 icon,
// dark #272729 with a #9D9CA4 icon. The chosen one widens smoothly (no bounce) to its icon and name in white on its colour.
// A swipe across them goes to the next / the one before (not past the ends) — the row doesn't scroll.
final class MailCats: UIView {
  struct Item { let key: String; let sym: String; let name: String; let fill: (Bool) -> UIColor }
  static let H: CGFloat = 38
  static let neutral: (Bool) -> UIColor = { $0 ? UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1) : UIColor(red: 229 / 255, green: 229 / 255, blue: 234 / 255, alpha: 1) }
  static let blue: (Bool) -> UIColor = { $0 ? UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1) : UIColor(red: 89 / 255, green: 151 / 255, blue: 224 / 255, alpha: 1) }
  static let purple: (Bool) -> UIColor = { $0 ? UIColor(red: 175 / 255, green: 82 / 255, blue: 222 / 255, alpha: 1) : UIColor(red: 160 / 255, green: 120 / 255, blue: 214 / 255, alpha: 1) }
  let items: [Item]
  private(set) var selected = 0
  var onPick: ((Int) -> Void)?
  private var pills: [(bg: UIView, icon: UIImageView, label: UILabel)] = []
  var widths: [CGFloat] { pills.map { $0.bg.frame.width } }
  init(items: [Item]) {
    self.items = items
    super.init(frame: .zero)
    for (i, it) in items.enumerated() {
      let bg = UIView(); bg.layer.cornerRadius = MailCats.H / 2; bg.layer.cornerCurve = .continuous; bg.clipsToBounds = true
      let icon = UIImageView(image: UIImage(systemName: it.sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)))
      icon.contentMode = .center
      let label = UILabel(); label.text = it.name; label.font = .systemFont(ofSize: 17, weight: .semibold)
      bg.addSubview(icon); bg.addSubview(label); addSubview(bg)
      bg.isAccessibilityElement = true; bg.accessibilityLabel = it.name; bg.accessibilityIdentifier = "cat-" + it.key
      let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:))); bg.tag = i; bg.addGestureRecognizer(tap)
      pills.append((bg, icon, label))
    }
    for d in [UISwipeGestureRecognizer.Direction.left, .right] {
      let sw = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:))); sw.direction = d; addGestureRecognizer(sw)
    }
    paint()
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func tapped(_ g: UITapGestureRecognizer) { if let i = g.view?.tag { pick(i) } }
  // (left: the next one; right: the one before — nothing past the ends)
  @objc private func swiped(_ g: UISwipeGestureRecognizer) { pick(g.direction == .left ? selected + 1 : selected - 1) }
  private func pick(_ i: Int) {
    guard i >= 0, i < items.count else { return }
    onPick?(i)
  }
  func choose(_ i: Int, animated: Bool) {
    guard i != selected, i >= 0, i < items.count else { return }
    selected = i
    UIView.animate(withDuration: animated ? 0.3 : 0, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
      self.paint(); self.place()
    }
  }
  private func paint() {
    let idle = Look.c(UIColor(red: 39 / 255, green: 39 / 255, blue: 41 / 255, alpha: 1), UIColor(red: 234 / 255, green: 234 / 255, blue: 236 / 255, alpha: 1))
    let idleInk = Look.c(UIColor(red: 157 / 255, green: 156 / 255, blue: 164 / 255, alpha: 1), UIColor(red: 134 / 255, green: 134 / 255, blue: 137 / 255, alpha: 1))
    for (i, p) in pills.enumerated() {
      let on = i == selected
      // (the neutral one in dark: light grey with black, as the others' white on colour)
      let ink: UIColor = on ? (items[i].key == "all" ? Look.c(.black, .white) : .white) : idleInk
      p.bg.backgroundColor = on ? Look.c(items[i].fill(false), items[i].fill(true)) : idle
      p.icon.tintColor = ink; p.label.textColor = ink
      p.label.alpha = on ? 1 : 0
      p.bg.accessibilityTraits = on ? [.button, .selected] : .button
    }
  }
  private func onWidth(_ i: Int) -> CGFloat { ceil(13 + 22 + 6 + pills[i].label.intrinsicContentSize.width + 16) }
  private func place() {
    var x: CGFloat = 16
    for (i, p) in pills.enumerated() {
      let on = i == selected, w: CGFloat = on ? onWidth(i) : 49
      p.bg.frame = CGRect(x: x, y: 0, width: w, height: MailCats.H)
      p.icon.frame = on ? CGRect(x: 13, y: 0, width: 22, height: MailCats.H) : CGRect(x: (49 - 22) / 2, y: 0, width: 22, height: MailCats.H)
      p.label.frame = CGRect(x: 13 + 22 + 6, y: 0, width: pills[i].label.intrinsicContentSize.width + 2, height: MailCats.H)
      x += w + 9
    }
  }
  override func layoutSubviews() { super.layoutSubviews(); place() }
}

// ---------- how every swiped row settles, opening or closing (Haris, 2026-11-01: "wherever there's a swipe list") ----------
// Mail's, measured frame by frame from Haris's recording: a critically damped spring (no bounce) of ~0.44 s — from rest it
// starts slowly and eases in to its place over ~0.5 s; let go mid-swipe, it carries the finger's speed on.
enum SwipeSpring {
  static func run(from: CGFloat, to: CGFloat, velocity: CGFloat, _ change: @escaping () -> Void, completion: (() -> Void)? = nil) {
    let dist = to - from
    let v = abs(dist) > 0.5 ? max(-30, min(30, velocity / dist)) : 0
    // (response 0.44 s: ω = 2π / 0.44; critically damped — damping 2ω, no bounce)
    let w: CGFloat = 2 * .pi / 0.44
    let spring = UISpringTimingParameters(mass: 1, stiffness: w * w, damping: 2 * w, initialVelocity: CGVector(dx: v, dy: 0))
    let a = UIViewPropertyAnimator(duration: 0.5, timingParameters: spring)
    a.isUserInteractionEnabled = true
    a.addAnimations(change)
    if let c = completion { a.addCompletion { _ in c() } }
    a.startAnimation()
  }
}


// the toast capsule "+ New task" stretches into (HomeView.toast)
final class ToastCapsule: UIView {
  static let fill = Look.c(SplashView.hex(0x2b2c31), .white)
  static let line = Look.c(UIColor.white.withAlphaComponent(0.1), UIColor.black.withAlphaComponent(0.08))
  var onUndo: (() -> Void)?, onPlus: (() -> Void)?, onGone: (() -> Void)?
  var from = CGRect.zero, to = CGRect.zero
  private(set) var out = false
  private let start = UIButton(type: .custom), tick = UIImageView(), msg = UILabel(), undo = UIButton(type: .system), plusB = UIButton(type: .system)
  private let hasPlus: Bool
  // (✕ in the +'s place while a Client Assets download runs — tapping it cancels; Haris 2026-11-08)
  private(set) var crossed = false
  private var roundOn: Bool { hasPlus || crossed }
  func cross(_ on: Bool) {
    guard on != crossed else { return }
    crossed = on
    UIView.performWithoutAnimation {
      plusB.setImage(UIImage(systemName: on ? "xmark" : "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
      plusB.accessibilityLabel = on ? "Cancel download" : nil
      plusB.isHidden = !roundOn
    }
    setNeedsLayout()
  }
  private var timer: Timer?, touching = false, closing = false
  // (iOS 26: iPhone's own glass in a glass container — the button's glass and the toast's are one liquid piece, so the
  //  toast squashes and stretches out of "+ New task" and back into it, as the top buttons do; Haris 2026-11-03)
  private let bed = UIVisualEffectView(effect: nil), body = UIVisualEffectView(effect: nil), nub = UIVisualEffectView(effect: nil)
  private var glassy: Bool { if #available(iOS 26.0, *) { return true }; return false }
  // (as the pill forms into the toast: its glass tinted 60 % — light on light, dark on dark; back to clear glass as it goes:
  //  Haris 2026-11-03)
  // (its corners: always a full pill, as the button — Haris 2026-11-03)
  private func shape(_ toast: Bool) {
    let H = body.bounds.height > 0 ? body.bounds.height : bounds.height
    body.layer.cornerRadius = H / 2
  }
  private func glass(tinted: Bool) -> UIVisualEffect? {
    guard #available(iOS 26.0, *) else { return nil }
    let g = UIGlassEffect(style: .regular)
    if tinted { g.tintColor = Look.c(UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 0.6), UIColor.white.withAlphaComponent(0.6)) }
    return g
  }
  init(title: String?, sym: String?, plus: Bool) {
    hasPlus = plus
    super.init(frame: .zero)
    let ink: UIColor = Look.ink   // (its words: black on light, white on dark — Haris 2026-11-03)
    if #available(iOS 26.0, *) {
      // (iPhone's own Liquid Glass, as "+ New task" it stretches out of)
      let ce = UIGlassContainerEffect(); ce.spacing = 24; bed.effect = ce
      body.effect = UIGlassEffect(style: .regular); nub.effect = UIGlassEffect(style: .regular)
      [body, nub].forEach { $0.clipsToBounds = true; $0.layer.cornerCurve = .continuous; bed.contentView.addSubview($0) }
      bed.isUserInteractionEnabled = false; addSubview(bed)
    } else {
      backgroundColor = ToastCapsule.fill
      layer.borderWidth = 1; layer.shadowColor = UIColor.black.cgColor; layer.shadowRadius = 10; layer.shadowOffset = CGSize(width: 0, height: 3)
      followLook("layer") { [weak self] tc in self?.layer.setBorder(ToastCapsule.line, tc); self?.layer.shadowOpacity = tc.userInterfaceStyle == .light ? 0.08 : 0 }
    }
    // ("+ New task" as the button has it — fading away as it stretches, back as it shrinks; drawn by Apple's button with
    //  the button's own settings, so its + is the same size — drawn as text it was smaller and snapped to the button's
    //  size as the toast went: Haris 2026-11-08)
    var sc = UIButton.Configuration.plain()
    if let s = sym { sc.image = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)) }
    sc.imagePadding = 6
    if let t = title { sc.attributedTitle = AttributedString(t, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)])) }
    sc.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 18)
    sc.baseForegroundColor = ink
    start.configuration = sc
    tick.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
    tick.tintColor = .systemGreen; tick.contentMode = .center
    msg.font = .systemFont(ofSize: 15); msg.textColor = ink; msg.lineBreakMode = .byTruncatingTail; msg.adjustsFontSizeToFitWidth = true; msg.minimumScaleFactor = 0.82   // (a message a little too long shrinks a touch rather than being cut)
    undo.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    undo.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.onUndo?() }, for: .touchUpInside)
    plusB.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
    plusB.tintColor = ink; plusB.backgroundColor = ink.withAlphaComponent(0.07)
    plusB.addAction(UIAction { [weak self] _ in self?.onPlus?() }, for: .touchUpInside)
    plusB.isHidden = !plus
    [tick, msg, undo, plusB].forEach { $0.alpha = 0; addSubview($0) }
    start.isUserInteractionEnabled = false; addSubview(start)
  }
  required init?(coder: NSCoder) { fatalError() }
  func say(_ text: String, _ act: String) {
    msg.text = text
    UIView.performWithoutAnimation { undo.setTitle(act.isEmpty ? nil : act, for: .normal); undo.layoutIfNeeded() }
    undo.isHidden = act.isEmpty
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    layer.cornerRadius = H / 2
    if glassy {
      bed.frame = bounds
      // (the button's own place, at the right end; the toast's glass grows out of it)
      let n = CGRect(x: W - from.width, y: 0, width: from.width, height: H)
      if !moving { nub.frame = n; body.frame = out ? bounds : n }
      nub.layer.cornerRadius = H / 2; if !moving { shape(out) }
    }
    // (laid out for its stretched size; the start words over the right end, where the button was)
    start.frame = CGRect(x: W - from.width, y: 0, width: from.width, height: H)
    let p: CGFloat = roundOn ? 34 : 0
    plusB.frame = CGRect(x: W - 5 - p, y: (H - 34) / 2, width: p, height: 34); plusB.layer.cornerRadius = 17
    tick.frame = CGRect(x: 10, y: 0, width: 26, height: H)
    let uw = undo.isHidden ? 0 : ceil(undo.sizeThatFits(CGSize(width: 120, height: H)).width) + 12
    let right = (roundOn ? plusB.frame.minX : W - 8) - 4
    undo.frame = CGRect(x: right - uw, y: 0, width: uw, height: H)
    msg.frame = CGRect(x: 42, y: 0, width: max(0, undo.frame.minX - 42 - 4), height: H)
  }
  private var moving = false
  func open() {
    out = true
    UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) { self.start.alpha = 0 }
    if glassy {
      // (the toast at its full size at once, its glass still the button's; then the glass stretches out — Mail's spring,
      //  a little bounce so it squashes and settles, iPhone's own liquid glass doing the rest)
      moving = true
      UIView.performWithoutAnimation {
        frame = to; layoutIfNeeded()
        let n = CGRect(x: bounds.width - from.width, y: 0, width: from.width, height: bounds.height)
        bed.frame = bounds; nub.frame = n; body.frame = n
        // (a full pill from its first frame — made at no size, its corners were 0 and the spring rounded them as it
        //  stretched: square corners for a moment, Haris 2026-11-09)
        shape(true); nub.layer.cornerRadius = bounds.height / 2
      }
      UIView.animate(withDuration: 0.5, delay: 0.03, usingSpringWithDamping: 0.78, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        self.body.frame = self.bounds; self.plusB.alpha = 1
        self.shape(true); self.body.effect = self.glass(tinted: true)
      } completion: { _ in self.moving = false }
    } else {
      UIView.animate(withDuration: 0.4, delay: 0.05, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        self.frame = self.to; self.layoutIfNeeded(); self.plusB.alpha = 1
      }
    }
    UIView.animate(withDuration: 0.22, delay: 0.3, options: [.curveEaseOut, .allowUserInteraction]) { [self.tick, self.msg, self.undo].forEach { $0.alpha = 1 } }
  }
  // how long it stays out (a finger on it keeps it)
  func hold(_ ms: Double) {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: ms / 1000, repeats: false) { [weak self] _ in guard let self = self, !self.touching else { return }; self.close() }
  }
  override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { touching = true; super.touchesBegan(t, with: e) }
  override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { touching = false; hold(1500); super.touchesEnded(t, with: e) }
  override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { touching = false; hold(1500); super.touchesCancelled(t, with: e) }
  func close() {
    guard !closing else { return }
    closing = true; out = false; timer?.invalidate()
    UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) { [self.tick, self.msg, self.undo].forEach { $0.alpha = 0 } }
    if glassy {
      // (the glass squashes back into the button's place)
      moving = true
      let n = CGRect(x: bounds.width - from.width, y: 0, width: from.width, height: bounds.height)
      UIView.animate(withDuration: 0.45, delay: 0.1, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        self.body.frame = n; self.plusB.alpha = 0
        self.shape(false); self.body.effect = self.glass(tinted: false)
      } completion: { _ in self.moving = false; UIView.performWithoutAnimation { self.frame = self.from; self.layoutIfNeeded() }; self.onGone?() }
    } else {
      UIView.animate(withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        self.frame = self.from; self.layoutIfNeeded(); self.plusB.alpha = 0
      } completion: { _ in self.onGone?() }
    }
    UIView.animate(withDuration: 0.2, delay: 0.32, options: [.curveEaseOut]) { self.start.alpha = self.hasPlus ? 1 : 0; if !self.hasPlus { self.alpha = 0 } }
  }
}

// The soft frost as strong as Mail's (Haris 2026-11-03, measured against his Mail screenshot): iPhone's own soft frost
// covers the area of the views that join it, strongest at the top and fading out over it. Over the bar alone it fades
// too early (what's under the big title showed through ~5× more than in Mail), so an invisible view a little taller than
// the bar joins it too: the strong part covers the whole bar, and it fades out mostly near and just below the line.
final class FrostReach: UIView {
  static let extra: CGFloat = 20
  private var hook: AnyObject?
  func attach(_ scroll: UIScrollView, in parent: UIView, below: UIView) {
    isUserInteractionEnabled = false; backgroundColor = .clear
    parent.insertSubview(self, belowSubview: below)
    if #available(iOS 26.0, *) {
      let i = UIScrollEdgeElementContainerInteraction(); i.scrollView = scroll; i.edge = .top
      addInteraction(i); hook = i
    }
  }
  func follow(_ scroll: UIScrollView) {
    if #available(iOS 26.0, *), let i = hook as? UIScrollEdgeElementContainerInteraction, i.scrollView !== scroll { i.scrollView = scroll }
  }
}

// The firm frost (the Inbox's) only once something is under the bar — at the top of a page, nothing; fading in and out
// where iPhone lets it (Haris 2026-11-03)
enum Frost {
  @available(iOS 26.0, *)
  static func show(_ s: UIScrollView, _ on: Bool) {
    if s.topEdgeEffect.isHidden == !on { return }
    UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) { s.topEdgeEffect.isHidden = !on }
  }
  // (a list placed again without scrolling — a category switched back — the frost asked again at once)
  @available(iOS 26.0, *)
  static func nudge(_ s: UIScrollView) { let o = s.contentOffset; s.contentOffset = CGPoint(x: o.x, y: o.y + 0.5); s.contentOffset = o }
}
// (for a page whose bar has no big title: the frost the moment the page has scrolled under its bar)
final class FrostWatch: NSObject {
  private var kv: [NSKeyValueObservation] = []
  init(_ scroll: UIScrollView) {
    super.init()
    guard #available(iOS 26.0, *) else { return }
    let f: (UIScrollView) -> Void = { s in Frost.show(s, s.contentOffset.y > -s.adjustedContentInset.top + 0.5) }
    kv = [scroll.observe(\.contentOffset, options: [.initial, .new]) { s, _ in f(s) },
          scroll.observe(\.contentInset, options: [.new]) { s, _ in f(s) }]
  }
}

// the note on top of search results when a word was read as another (a typo): "Showing results for ford (you typed
// “frod”)" — app.js searchFixedNote (Haris 2026-11-06)
final class SearchFixedNote: UIView {
  private let l = UILabel()
  override init(frame: CGRect) { super.init(frame: frame); layer.cornerRadius = 14; layer.cornerCurve = .continuous; l.numberOfLines = 0; addSubview(l) }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ fx: [[String: Any]]) {
    backgroundColor = Look.c(UIColor(red: 0.09, green: 0.14, blue: 0.23, alpha: 1), UIColor(red: 0.91, green: 0.93, blue: 0.98, alpha: 1))
    let ink = Look.c(UIColor(red: 0.66, green: 0.76, blue: 1, alpha: 1), UIColor(red: 0.17, green: 0.29, blue: 0.54, alpha: 1))
    let s = NSMutableAttributedString()
    if let img = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))?.withTintColor(ink, renderingMode: .alwaysOriginal) {
      let a = NSTextAttachment(); a.image = img; a.bounds = CGRect(x: 0, y: -1, width: img.size.width, height: img.size.height); s.append(NSAttributedString(attachment: a)); s.append(NSAttributedString(string: "  "))
    }
    let f = UIFont.systemFont(ofSize: 14)
    s.append(NSAttributedString(string: "Showing results for ", attributes: [.font: f, .foregroundColor: ink]))
    s.append(NSAttributedString(string: fx.map { $0["to"] as? String ?? "" }.joined(separator: ", "), attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: ink]))
    s.append(NSAttributedString(string: " (you typed " + fx.map { "“" + ($0["from"] as? String ?? "") + "”" }.joined(separator: ", ") + ")", attributes: [.font: f, .foregroundColor: ink.withAlphaComponent(0.75)]))
    l.attributedText = s
    setNeedsLayout()
  }
  func height(for w: CGFloat) -> CGFloat { ceil(l.sizeThatFits(CGSize(width: w - 28, height: 400)).height) + 22 }
  override func layoutSubviews() { super.layoutSubviews(); l.frame = bounds.insetBy(dx: 14, dy: 11) }
}


// what a model shows, as words — to tell whether it changed (keys in order; anything that can't be written: always new)
func drawSig(_ d: Any) -> String {
  guard JSONSerialization.isValidJSONObject(d), let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) else { return UUID().uuidString }
  return String(decoding: data, as: UTF8.self)
}

extension HomeView: UICollectionViewDelegate {
  // (a task's or a client's row: Apple's highlight and selection open it; Me's rows as iPhone Settings'; nothing else)
  func collectionView(_ cv: UICollectionView, shouldHighlightItemAt ip: IndexPath) -> Bool {
    guard let key = listDS?.itemIdentifier(for: ip) else { return false }
    if listViews[key] is AppleRow || listViews[key] is InboxRow || listViews[key] is FileTile { return true }
    guard isMeList else { return false }
    if key == "me:card" { return true }
    guard let it = meItems[key] else { return false }
    return it.tap != nil && it.toggle == nil
  }
  func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
    cv.deselectItem(at: ip, animated: true)
    guard let key = listDS?.itemIdentifier(for: ip) else { return }
    // (a file's tile or row: Quick Look grows out of it and goes back into it — FilesLook)
    if listViews[key] is FileTile || listViews[key] is FileListRow { FilesLook.source = (listViews[key] as? FileTile) ?? cv.cellForItem(at: ip) }
    if let r = listViews[key] as? AppleRow { r.rowTapped(); return }
    if let r = listViews[key] as? InboxRow { r.onTap?(); return }
    if let t = listViews[key] as? FileTile { t.onTap?(); return }
    guard isMeList else { return }
    if key == "me:card" { (listViews[key] as? MeCardBlock)?.onTap?(); return }
    meItems[key]?.tap?()
  }
  // touch and hold a task: Apple's own lift of its cell and Apple's menu — Attach Files (Camera · Photos · Files); Copy link
  // and Trash are on its swipe (Haris 2026-11-09 12:36: "no need for them to be in the menu"). My Tasks' Done tab: read only
  // (a folder's or file's tile held: Apple's lift on its picture alone, on nothing — as the Files app; every other row: Apple's own)
  private func tileLift(_ ip: IndexPath) -> UITargetedPreview? {
    guard let key = listDS?.itemIdentifier(for: ip), let t = listViews[key] as? FileTile, t.window != nil else { return nil }
    let v = t.liftView
    let p = UIPreviewParameters(); p.backgroundColor = .clear
    // (the whole picture shown — the folder's own outline cut its tab's slope off: Haris 2026-11-10 17:54; its shadow the
    //  folder's shape, so no box shows around it)
    p.visiblePath = UIBezierPath(roundedRect: v.bounds, cornerRadius: t.liftRadius); p.shadowPath = t.liftPath
    return UITargetedPreview(view: v, parameters: p)
  }
  func collectionView(_ cv: UICollectionView, contextMenuConfiguration c: UIContextMenuConfiguration, highlightPreviewForItemAt ip: IndexPath) -> UITargetedPreview? { tileLift(ip) }
  func collectionView(_ cv: UICollectionView, contextMenuConfiguration c: UIContextMenuConfiguration, dismissalPreviewForItemAt ip: IndexPath) -> UITargetedPreview? { tileLift(ip) }
  func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemsAt ips: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
    if ips.count == 1, let key = listDS?.itemIdentifier(for: ips[0]), let row = listViews[key] as? InboxRow { return inboxMenu(row, key) }
    // (a folder or a file held: Apple's menu with its lift — Assets.swift's menus)
    if ips.count == 1, let key = listDS?.itemIdentifier(for: ips[0]), let t = listViews[key] as? FileTile, let menu = t.menu {
      return UIContextMenuConfiguration(identifier: key as NSString, previewProvider: nil) { _ in menu() }
    }
    if ips.count == 1, let key = listDS?.itemIdentifier(for: ips[0]), let r = listViews[key] as? FileListRow, let menu = r.menu {
      return UIContextMenuConfiguration(identifier: key as NSString, previewProvider: nil) { _ in menu() }
    }
    // (a client held: Apple's menu with its lift — Open · Client Details; its sheet once the menu has closed)
    if ips.count == 1, let key = listDS?.itemIdentifier(for: ips[0]), let row = listViews[key] as? ClientListRow {
      let id = row.id
      return UIContextMenuConfiguration(identifier: key as NSString, previewProvider: nil) { [weak self, weak row] _ in
        UIMenu(children: [
          UIAction(title: "Open", image: UIImage(systemName: "arrow.up.right.square")) { _ in HomeView.afterMenu = { row?.rowTapped() } },
          UIAction(title: "Client Details", image: UIImage(systemName: "info.circle")) { _ in HomeView.afterMenu = { self?.send(["ev": "clientHold", "id": id]) } },
        ])
      }
    }
    guard ips.count == 1, let key = listDS?.itemIdentifier(for: ips[0]), let card = listViews[key] as? HomeCard, !(isList && listTab == "done") else { return nil }
    let id = card.id
    return UIContextMenuConfiguration(identifier: key as NSString, previewProvider: nil) { [weak self] _ in
      // (the picker is asked for once the menu has closed — while it's still closing, iPhone shows no other screen)
      let src = { (s: String, t: String, img: String) in UIAction(title: t, image: UIImage(systemName: img)) { _ in HomeView.afterMenu = { self?.send(["ev": "attach", "id": id, "source": s]) } } }
      return UIMenu(title: "Attach Files", children: [src("camera", "Camera", "camera"), src("photos", "Photos", "photo"), src("files", "Files", "doc.badge.arrow.up")])
    }
  }
  // hold an Inbox row: Apple's peek of it (InboxPeekVC — the task, the comment in full or the task's facts, from the phone's
  // copy) with Apple's menu: Open Task · Mark as Read / Unread · Copy Text (a comment) or Copy Link. Peeking doesn't open it
  // or mark it read; the preview tapped opens it, as the row's tap (Haris 2026-11-09, mock-up "Inbox — with the rules")
  private func inboxMenu(_ row: InboxRow, _ key: String) -> UIContextMenuConfiguration {
    let peek = InboxPeekVC.make(row.id)
    let preview: UIContextMenuContentPreviewProvider? = peek.map { p in { () -> UIViewController? in p } }
    return UIContextMenuConfiguration(identifier: key as NSString, previewProvider: preview) { [weak self, weak row] _ in
      guard let self = self, let row = row else { return nil }
      return UIMenu(children: self.inboxMenuItems(row, peek))
    }
  }
  func inboxMenuItems(_ row: InboxRow, _ peek: InboxPeekVC?) -> [UIMenuElement] {
    var acts: [UIMenuElement] = [
      UIAction(title: peek != nil ? "Open Task" : "Open", image: UIImage(systemName: "arrow.up.right.square")) { [weak row] _ in HomeView.afterMenu = { row?.onTap?() } },
      UIAction(title: row.read ? "Mark as Unread" : "Mark as Read", image: UIImage(systemName: row.read ? "envelope.badge" : "envelope.open")) { [weak row] _ in row?.onToggle?() },
    ]
    if let p = peek {
      if let t = p.commentText, !t.isEmpty { acts.append(UIAction(title: "Copy Text", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = t }) }
      else { let id = p.taskId; acts.append(UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in Main.shared.copyTaskLink(id) }) }
    }
    return acts
  }
  // the peek tapped: the task opens, as the row's tap — once Apple's preview has gone into it
  func collectionView(_ cv: UICollectionView, willPerformPreviewActionForMenuWith c: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
    guard let key = c.identifier as? String, let row = listViews[key] as? InboxRow else { return }
    animator.preferredCommitStyle = .pop
    animator.addCompletion { [weak row] in row?.onTap?() }
  }
  private static var afterMenu: (() -> Void)?
  func collectionView(_ cv: UICollectionView, willEndContextMenuInteraction c: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
    let run = { let f = HomeView.afterMenu; HomeView.afterMenu = nil; f?() }
    if let a = animator { a.addCompletion(run) } else { DispatchQueue.main.async(execute: run) }
  }
}

// ---------- Me and its pages as iPhone's Settings (Haris 2026-11-08: "start the me page … me page and its inner pages") ----------
// Each group of rows is one of Apple's grouped sections, its title Apple's header and the words under it Apple's footer;
// each row Apple's list cell, set by Apple's own configurations — the text, the line under it, Apple's ›, the value at the
// right, Apple's switch, Apple's highlight. Ours: the coloured icons and pictures the cells show, and the page's own
// blocks (Appearance's phones, About's cards…), each in a cell of Apple's list as before.
struct MeSec { var grouped = false; var head = ""; var foot: NSAttributedString? = nil; var footCentred = false }
final class MeHold: NSObject, UIContextMenuInteractionDelegate {
  var run: (() -> Void)?
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation p: CGPoint) -> UIContextMenuConfiguration? {
    guard let r = run else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
      UIMenu(children: [UIAction(title: "Role, rights and access", image: UIImage(systemName: "slider.horizontal.3")) { _ in r() }])
    }
  }
}
extension HomeView {
  var isMeList: Bool { isMe || assets == "plansPage" }
  // (a page pushed on a tab, not a tab's first screen)
  var pushedList: Bool { pageBar || (assets == "all" && assetsBack) || assets == "plansPage" }
  func meSection(_ i: Int) -> MeSec? {
    guard let ds = listDS else { return nil }
    let ids = ds.snapshot().sectionIdentifiers
    guard i >= 0, i < ids.count else { return nil }
    return meSecs[ids[i]]
  }
  func meGrouped(_ g: MeSec, _ env: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
    var c = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
    c.backgroundColor = .clear
    c.separatorConfiguration.color = HomeLook.line   // (Apple's line, a little softer — every Apple page)
    c.headerMode = g.head.isEmpty ? .none : .supplementary
    c.footerMode = g.foot == nil ? .none : .supplementary
    let sec = NSCollectionLayoutSection.list(using: c, layoutEnvironment: env)
    // (the page's sides, as its other blocks: 16 pt)
    sec.contentInsetsReference = .none
    var ins = sec.contentInsets; ins.leading = 16; ins.trailing = 16; sec.contentInsets = ins
    return sec
  }
  // the page as Apple's sections: a title and the group under it — one section; the words under a group — its footer;
  // anything else of the page's — in its own section, as before
  func applyMeList(animated: Bool) {
    guard let ds = listDS else { return }
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    var views: [String: UIView] = [:], items: [String: SetItem] = [:], secs: [Int: MeSec] = [:]
    var n = 0, cur: [String] = [], info = MeSec()
    func close() {
      if !cur.isEmpty { snap.appendSections([n]); snap.appendItems(cur, toSection: n); secs[n] = info; n += 1 }
      cur = []; info = MeSec()
    }
    let vs = content
    var i = 0
    while i < vs.count {
      let v = vs[i]
      var head: String? = nil
      var g = v as? SetGroup
      if let hd = v as? SetHead, i + 1 < vs.count, let gg = vs[i + 1] as? SetGroup { head = hd.label.text ?? ""; g = gg; i += 1 }
      if let g = g {
        i += 1
        guard !g.isEmpty else { continue }
        close()
        info = MeSec(grouped: true, head: head ?? "")
        let gid = ObjectIdentifier(g).hashValue
        var seen = Set<String>()
        for it in g.items {
          var k = "s:\(gid):\(it.key)"; var j = 1
          while seen.contains(k) { k = "s:\(gid):\(it.key)#\(j)"; j += 1 }
          seen.insert(k); cur.append(k); items[k] = it
        }
        if i < vs.count, let f = vs[i] as? SetFoot, !(f.label.text ?? "").isEmpty {
          info.foot = f.label.attributedText ?? NSAttributedString(string: f.label.text ?? ""); info.footCentred = f.center_; i += 1
        }
        close()
        continue
      }
      // your card: Apple's cell, as Settings' account row
      if let c = v as? MeCardBlock {
        close(); info = MeSec(grouped: true); cur = ["me:card"]; views["me:card"] = c
        c.onPhoto = { [weak self] in guard let self = self, self.meDrawn["me:card"] != self.meSig("me:card") else { return }; self.meDrawn["me:card"] = self.meSig("me:card"); self.reconfigureMe("me:card") }
        close(); i += 1; continue
      }
      // anything else: as before, the whole width in a cell of Apple's list
      if info.grouped { close() }
      if let b = v as? HomeBlock {
        let k = "b:" + (b.accessibilityIdentifier ?? "\(ObjectIdentifier(b).hashValue)")
        if views[k] == nil {
          let w = blockWraps[ObjectIdentifier(b)] ?? BlockWrap(b); blockWraps[ObjectIdentifier(b)] = w
          cur.append(k); views[k] = w
        }
      } else {
        let k = "e:\(ObjectIdentifier(v).hashValue)"
        if views[k] == nil { cur.append(k); views[k] = v }
      }
      i += 1
    }
    close()
    listViews = views; meItems = items; meSecs = secs
    blockWraps = blockWraps.filter { e in views.values.contains { $0 === e.value } }
    // (only what changed is drawn again — a row showing the same is left as it is: the standard, Haris 2026-11-03; Me drawn
    //  again on every open set every row afresh — Haris 2026-11-08 "Is the me page drawing on every open?")
    let had = Set(ds.snapshot().itemIdentifiers)
    var sigs: [String: String] = [:]
    for k in snap.itemIdentifiers { sigs[k] = meSig(k) }
    let changed = snap.itemIdentifiers.filter { had.contains($0) && meDrawn[$0] != sigs[$0] }
    meDrawn = sigs
    if !changed.isEmpty { snap.reconfigureItems(changed); Main.meRows += changed.count }
    // (nothing came, went or changed: nothing applied at all)
    if changed.isEmpty, snap.sectionIdentifiers == ds.snapshot().sectionIdentifiers, snap.itemIdentifiers == ds.snapshot().itemIdentifiers { return }
    ds.apply(snap, animatingDifferences: animated)
  }
  // what a row shows, to tell whether it changed: a settings row by its item, your card by its words and photo, a block of
  // the page's own always (it draws itself, keeping what's the same)
  func meSig(_ key: String) -> String {
    if key == "me:card", let c = listViews[key] as? MeCardBlock { let x = c.info; return "\(x.name)|\(x.role)|\(x.email)|\(MePhoto.shared.image.map { "\(ObjectIdentifier($0).hashValue)" } ?? "-")\(MePhoto.shared.initials ?? "")|\(look.key)" }
    if let e = listViews[key] as? AppleEmpty { return "u|" + e.sig + "|\(look.key)" }   // (Apple's empty state: by its words)
    if let it = meItems[key] { return it.sig + "|\(it.toggle.map { $0 ? "1" : "0" } ?? "")|\(look.key)" }
    if let v = listViews[key] { return "b|\(itemHeight(key, v))" }   // (a block's own height changed — its cell sized again)
    return "b"
  }
  func reconfigureMe(_ key: String) {
    guard let ds = listDS else { return }
    var s = ds.snapshot()
    guard s.indexOfItem(key) != nil else { return }
    s.reconfigureItems([key]); ds.apply(s, animatingDifferences: false)
  }
  // one row, iPhone Settings' own cell
  func paintMe(_ cell: UICollectionViewListCell, _ key: String) {
    let L = look
    let card = L.card
    cell.configurationUpdateHandler = { cell, state in
      var b = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
      if !(state.isHighlighted || state.isSelected) { b.backgroundColor = card }
      cell.backgroundConfiguration = b
    }
    cell.interactions.filter { $0 is UIContextMenuInteraction }.forEach { cell.removeInteraction($0) }
    if key == "me:card", let c = listViews[key] as? MeCardBlock {
      let x = c.info
      var cf = UIListContentConfiguration.subtitleCell()
      cf.text = x.name; cf.textProperties.font = .systemFont(ofSize: 21, weight: .semibold); cf.textProperties.color = L.title
      cf.secondaryText = [x.role, x.email].filter { !$0.isEmpty }.joined(separator: "\n")
      cf.secondaryTextProperties.font = .systemFont(ofSize: 14); cf.secondaryTextProperties.color = .secondaryLabel; cf.secondaryTextProperties.numberOfLines = 2
      cf.textToSecondaryTextVerticalPadding = 3
      cf.image = c.photo.map { roundPic($0, initials: nil, color: nil, size: 62) }
      cf.imageProperties.maximumSize = CGSize(width: 62, height: 62); cf.imageProperties.reservedLayoutSize = CGSize(width: 62, height: 0); cf.imageProperties.cornerRadius = 31
      cf.imageToTextPadding = 14
      cf.directionalLayoutMargins.top = 14; cf.directionalLayoutMargins.bottom = 14
      cell.contentConfiguration = cf
      cell.accessories = [.disclosureIndicator()]
      cell.accessibilityLabel = "\(x.name), \(x.role), My profile"
      return
    }
    guard let it = meItems[key] else { return }
    var cf = (it.sub.isEmpty && it.pills.isEmpty) ? UIListContentConfiguration.cell() : UIListContentConfiguration.subtitleCell()
    cf.text = it.title
    cf.textProperties.font = .systemFont(ofSize: 17, weight: it.bold ? .semibold : .regular); cf.textProperties.color = it.danger ? .systemRed : L.title
    if !it.sub.isEmpty || !it.pills.isEmpty {
      let a = NSMutableAttributedString(string: it.sub, attributes: [.foregroundColor: it.warn ? UIColor.systemOrange : UIColor.secondaryLabel])
      for (j, p) in it.pills.enumerated() { a.append(NSAttributedString(string: (j == 0 && it.sub.isEmpty ? "" : "  ") + p.0, attributes: [.foregroundColor: p.1, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)])) }
      cf.secondaryAttributedText = a
      cf.secondaryTextProperties.font = .systemFont(ofSize: 13); cf.secondaryTextProperties.numberOfLines = it.bold ? 0 : 2
      cf.textToSecondaryTextVerticalPadding = 2
    }
    if let p = it.person {
      cf.image = mePic(p.photo, p.ini, p.rgb, key)
      cf.imageProperties.maximumSize = CGSize(width: 36, height: 36); cf.imageProperties.reservedLayoutSize = CGSize(width: 36, height: 0); cf.imageProperties.cornerRadius = 18
      cf.imageToTextPadding = 12
    } else if let s = it.sym {
      cf.image = HomeView.settingsIcon(s, it.col ?? .systemGray)
      cf.imageProperties.maximumSize = CGSize(width: 30, height: 30); cf.imageProperties.reservedLayoutSize = CGSize(width: 30, height: 0)
      cf.imageToTextPadding = 12
    }
    cell.contentConfiguration = cf
    var acc: [UICellAccessory] = []
    if let b = it.badge { acc.append(.customView(configuration: .init(customView: HomeView.meBadge(b, .systemBlue), placement: .trailing()))) }
    if it.count > 0 { acc.append(.customView(configuration: .init(customView: HomeView.meBadge(it.count > 99 ? "99+" : "\(it.count)", .systemRed), placement: .trailing()))) }
    if let p = it.pill { acc.append(.label(text: p, options: .init(font: .monospacedSystemFont(ofSize: 13, weight: .semibold)))) }
    if !it.value.isEmpty { acc.append(.label(text: it.value)) }
    if let on = it.toggle {
      let sw = meSwitch(key)
      if sw.isOn != on { sw.setOn(on, animated: cell.window != nil) }
      acc.append(.customView(configuration: .init(customView: sw, placement: .trailing())))
    } else if it.chevron && it.tap != nil { acc.append(.disclosureIndicator()) }
    cell.accessories = acc
    cell.contentView.alpha = it.dim ? 0.6 : 1
    // (touch and hold — a team member: Apple's own lift and its menu)
    if let hold = it.hold {
      let d = MeHold(); d.run = hold; meHolds[key] = d
      cell.addInteraction(UIContextMenuInteraction(delegate: d))
    }
    cell.accessibilityLabel = [it.title, it.sub, it.value].filter { !$0.isEmpty }.joined(separator: ", ")
  }
  // (a switch kept for its row — the same one each time, so it moves as Apple's do)
  private func meSwitch(_ key: String) -> UISwitch {
    if let s = meSwitches[key] { return s }
    let s = UISwitch()
    s.addAction(UIAction { [weak self, weak s] _ in
      guard let self = self, let s = s else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.meItems[key]?.flip?(s.isOn)
    }, for: .valueChanged)
    meSwitches[key] = s
    return s
  }
  // a person's picture: their photo once it's in (the row drawn again then), else their initials
  private func mePic(_ path: String?, _ ini: String, _ rgb: UIColor, _ key: String) -> UIImage {
    if let p = path, let img = mePics[p] { return img }
    if let p = path, !mePicAsked.contains(p) {
      mePicAsked.insert(p)
      FeedLoader.shared.image(p) { [weak self] img in
        guard let self = self, let img = img else { return }
        DispatchQueue.main.async { self.mePics[p] = roundPic(img, initials: nil, color: nil, size: 36); self.reconfigureMe(key) }
      }
    }
    return roundPic(nil, initials: ini, color: rgb, size: 36)
  }
  // the coloured rounded square with its white symbol, as iPhone's Settings has them (shown by Apple's cell)
  private static var icons: [String: UIImage] = [:]
  static func settingsIcon(_ sym: String, _ col: UIColor) -> UIImage {
    let k = sym + "|" + col.description
    if let i = icons[k] { return i }
    let side: CGFloat = 30
    let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
      let r = CGRect(x: 0, y: 0, width: side, height: side)
      col.setFill(); UIBezierPath(roundedRect: r, cornerRadius: side * 0.27).fill()
      if let s = UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))?.withTintColor(.white, renderingMode: .alwaysOriginal) {
        s.draw(in: CGRect(x: (side - s.size.width) / 2, y: (side - s.size.height) / 2, width: s.size.width, height: s.size.height))
      }
    }
    icons[k] = img
    return img
  }
  // a small round pill — "New", a count waiting for you
  static func meBadge(_ t: String, _ c: UIColor) -> UIView {
    let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: c == .systemRed ? 15 : 11, weight: c == .systemRed ? .regular : .bold); l.textColor = .white; l.textAlignment = .center
    l.backgroundColor = c; l.clipsToBounds = true
    let h: CGFloat = c == .systemRed ? 24 : 18
    let w = max(h, ceil(l.sizeThatFits(CGSize(width: 80, height: h)).width) + (c == .systemRed ? 14 : 12))
    l.frame = CGRect(x: 0, y: 0, width: w, height: h); l.layer.cornerRadius = h / 2
    l.widthAnchor.constraint(equalToConstant: w).isActive = true; l.heightAnchor.constraint(equalToConstant: h).isActive = true
    return l
  }
}

// a cell of Home's Apple list holding one of Home's own views (a card, a heading, the boxes) as it is
final class HostCell: UICollectionViewListCell {
  private weak var hosted: UIView?
  private var h: CGFloat = 1
  func host(_ v: UIView?, height: CGFloat) {
    h = height
    if hosted !== v { if let old = hosted, old.superview === contentView { old.removeFromSuperview() } }
    hosted = v
    backgroundConfiguration = .clear()
    if let v = v, v.superview !== contentView { v.transform = .identity; v.alpha = 1; contentView.addSubview(v) }
    setNeedsLayout()
    invalidateIntrinsicContentSize()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let v = hosted, v.superview === contentView else { return }
    let b = contentView.bounds
    if v.tag == 7 { v.frame = CGRect(x: 4, y: b.height - 15, width: b.width - 8, height: 15) }
    else if v.tag == 8 { v.frame = CGRect(x: 4, y: 14, width: b.width - 8, height: b.height - 28) }
    else { v.frame = b }
  }
  override func preferredLayoutAttributesFitting(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    let r = super.preferredLayoutAttributesFitting(a)
    r.size.height = h
    return r
  }
}
