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
  private weak var openCard: HomeCard?
  private var actions: HomeActions?
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
  private var resultViews: [UIView] = [], resultCards: [String: HomeCard] = [:]
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
  override var isHidden: Bool { didSet { if oldValue != isHidden { onCorner?() } } }
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
  var onAppleScroll: (() -> Void)?
  var appleScroll: UIScrollView { searching ? results : sv }
  // Home's list as Apple's own list (Haris 2026-11-07: "I like Apple's list"): the same cards, headings and boxes, each
  // in a cell of iPhone's list — Apple's swipe actions (Done · Due, Copy link · Delete) and Apple's animation when cards
  // come, go or move
  private var list: UICollectionView?
  private var listDS: UICollectionViewDiffableDataSource<Int, String>?
  private var listViews: [String: UIView] = [:]
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
    if !isList && !isInbox && !isClients && !isClient && assets == nil { makeAppleList() }
    setNeedsLayout()
  }
  private func makeAppleList() {
    var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
    cfg.showsSeparators = false
    cfg.backgroundColor = .clear
    cfg.trailingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipeActions(ip, leading: false) }
    cfg.leadingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipeActions(ip, leading: true) }
    let layout = UICollectionViewCompositionalLayout { _, env in
      let sec = NSCollectionLayoutSection.list(using: cfg, layoutEnvironment: env)
      sec.interGroupSpacing = 10
      sec.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16)
      return sec
    }
    let cv = UICollectionView(frame: bounds, collectionViewLayout: layout)
    cv.backgroundColor = .clear
    cv.alwaysBounceVertical = true
    cv.contentInsetAdjustmentBehavior = .automatic
    cv.allowsSelection = false
    cv.delegate = self
    if #available(iOS 26.0, *) { cv.topEdgeEffect.style = .automatic }
    let reg = UICollectionView.CellRegistration<HostCell, String> { [weak self] cell, _, key in
      guard let self = self, let v = self.listViews[key] else { cell.host(nil, height: 1); return }
      cell.host(v, height: self.itemHeight(key, v))
    }
    listDS = UICollectionViewDiffableDataSource<Int, String>(collectionView: cv) { cv, ip, key in cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: key) }
    stats.forEach { statsRow.addSubview($0) }
    insertSubview(cv, aboveSubview: scroll)
    scroll.isHidden = true
    list = cv
  }
  // each thing's height in the list (as the list had them)
  private func itemHeight(_ key: String, _ v: UIView) -> CGFloat {
    let w = bounds.width - 32
    if key == "stats" { return 80 }
    if let c = v as? HomeCard { return c.height(for: w) }
    if v.tag == 8 { return 28 + ((v as? UILabel)?.sizeThatFits(CGSize(width: w - 8, height: 400)).height ?? 17) }
    return 27
  }
  // the list as it is now: the boxes, then each group's heading, cards and "nothing due" line
  private func applyList(animated: Bool) {
    guard let ds = listDS else { return }
    var views: [String: UIView] = [:], keys: [String] = []
    if !noStats { keys.append("stats"); views["stats"] = statsRow }
    for v in content {
      if let c = v as? HomeCard { let k = "c:" + c.id; keys.append(k); views[k] = c; continue }
      if v.tag == 7 && v.isHidden { continue }   // (Today's mark: no heading on screen)
      let k = (v.tag == 8 ? "e:" : "h:") + (v.accessibilityIdentifier ?? "\(ObjectIdentifier(v).hashValue)")
      if views[k] != nil { continue }
      keys.append(k); views[k] = v
    }
    listViews = views
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    snap.appendSections([0]); snap.appendItems(keys, toSection: 0)
    let had = Set(ds.snapshot().itemIdentifiers)
    snap.reconfigureItems(keys.filter { had.contains($0) })
    ds.apply(snap, animatingDifferences: animated)
  }
  // Apple's swipe actions: right — Done · Due; left — Copy link · Delete (as our round buttons did)
  private func swipeActions(_ ip: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
    guard let key = listDS?.itemIdentifier(for: ip), let card = listViews[key] as? HomeCard else { return nil }
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
        a.backgroundColor = hold ? HomeActions.orange.withAlphaComponent(0.5) : done ? HomeActions.grey : HomeActions.green
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
        a.backgroundColor = HomeActions.purple
        acts.append(a)
      }
    } else {
      if canDelete {
        let a = UIContextualAction(style: .destructive, title: "Delete") { [weak self, weak card] _, _, finish in
          guard let self = self, let card = card else { return finish(false) }
          // (asked first: the task goes to the Trash)
          let al = UIAlertController(title: "Delete this task?", message: card.taskTitle.isEmpty ? nil : card.taskTitle, preferredStyle: .actionSheet)
          al.addAction(UIAlertAction(title: "Delete Task", style: .destructive) { _ in self.send(["ev": "delete", "id": card.id, "card": card.info]); self.findAgain(); finish(true) })
          al.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in finish(false) })
          self.present?(al)
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
      c.backgroundColor = HomeActions.grey
      acts.append(c)
    }
    if acts.isEmpty { return nil }
    let cfg = UISwipeActionsConfiguration(actions: acts)
    cfg.performsFirstActionWithFullSwipe = !leading || (d["cdHold"] as? Bool) != true
    return cfg
  }
  // (the list's top and bottom as iPhone has them — under Apple's bar — or as this screen sets them)
  private var inTop: CGFloat { appleTop ? sv.adjustedContentInset.top : scroll.contentInset.top }
  private var inBottom: CGFloat { appleTop ? sv.adjustedContentInset.bottom : scroll.contentInset.bottom }
  private func resignSearch() { field.resignFirstResponder(); onAppleResign?() }
  // Apple's search bar: it opened, its words changed, it closed
  func appleSearchBegin() {
    guard appleTop, !searching else { return }
    if let o = openCard { setOpen(o, false) }
    searching = true
    showMotto()
    results.isHidden = false
    field.text = ""; showResults(nil)
    setNeedsLayout(); layoutIfNeeded()
    UIView.animate(withDuration: 0.25) { self.sv.alpha = 0; self.results.alpha = 1; self.fab.alpha = 0 }
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
    UIView.animate(withDuration: 0.25) { self.sv.alpha = 1; self.results.alpha = 0; self.fab.alpha = 1 } completion: { _ in
      if self.searching { return }
      self.results.isHidden = true
      self.field.text = ""; self.showResults(nil)
    }
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
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { cards.values.forEach { $0.people = people }; meChanged(); if isInbox && !m.isEmpty { drawInbox(m) }; if isClients { clientsGroup.people = people } } } }
  private var meId = ""
  var bottomRoom: CGFloat = 120 { didSet { if oldValue != bottomRoom { setNeedsLayout() } } }
  // the top of the app's tab bar: the + sits 14 above it, 18 from the right (phone.css .ph-fab), so it's in place from
  // the first frame — not where the page had it a moment before the tab bar came (it jumped up, Haris 2026-10-31)
  // (the room under the list's last card: up to 12 above "+ New task", which sits 14 above the tab bar)
  private var endRoom: CGFloat { tabTop.map { bounds.height - ($0 - 14 - BTN) + 12 } ?? bottomRoom }
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
      let v = UIView(); v.layer.cornerRadius = 18; v.layer.borderWidth = 1; let n = UILabel(), l = UILabel(); n.tag = 1; l.tag = 2; v.addSubview(n); v.addSubview(l); scroll.addSubview(v); stats.append(v)
      // (tapped: Due today / Overdue bring their group up to where the big title is; In review opens My Tasks waiting
      //  for the CD's review — Haris, 2026-10-31)
      let tap = UITapGestureRecognizer(target: self, action: #selector(statTap(_:))); v.tag = 100 + i; v.addGestureRecognizer(tap)
      v.isAccessibilityElement = true; v.accessibilityTraits = .button
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
    // (the system's own text colours, as Mail: label for the titles, secondary label for the lines under them)
    overrideUserInterfaceStyle = L.light ? .light : .dark
    HomeView.fadeText(sub, model["date"] as? String); sub.textColor = .secondaryLabel
    title.attributedText = NSAttributedString(string: model["title"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.label])
    if appleTop { onAppleTitle?(model["title"] as? String ?? "", model["date"] as? String ?? "") }
    smallTitle.text = model["title"] as? String; smallTitle.textColor = .label
    HomeView.fadeText(smallSub, model["date"] as? String); smallSub.textColor = .secondaryLabel
    blur.effect = UIBlurEffect(style: L.light ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark)
    hairline.backgroundColor = L.light ? UIColor.black.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.08)
    topLine.backgroundColor = L.light ? UIColor.black.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.12)
    [searchCircle, closeCircle, searchBar].forEach { $0.setLook(light: L.light, tint: L.roundIc) }
    lens.tintColor = L.sub; field.textColor = L.h1; field.tintColor = L.tag
    field.attributedPlaceholder = NSAttributedString(string: assets == "plansTab" || assets == "plansPage" || assets == "me.plan" ? "Search plans — a client or a post" : assets == "reviewsTab" ? "Search requests" : assets == "claimsTab" ? "Search claims" : assets == "expensesTab" ? "Search expenses" : assets != nil ? "Search every client’s files" : "Search tasks, clients, people", attributes: [.foregroundColor: L.sub])
    field.keyboardAppearance = L.light ? .light : .dark
    hint.textColor = L.empty
    meId = model["me"] as? String ?? ""; watchMe(); meChanged()
    if var fc = fab.configuration {
      if #available(iOS 26.0, *) { fab.overrideUserInterfaceStyle = L.light ? .light : .dark; fab.layer.shadowOpacity = 0 } else {
        fc.background.backgroundColor = ToastCapsule.fill(L.light); fc.background.strokeColor = ToastCapsule.line(L.light); fc.background.strokeWidth = 1
        fab.layer.shadowColor = UIColor.black.cgColor; fab.layer.shadowOpacity = L.light ? 0.08 : 0; fab.layer.shadowRadius = 10; fab.layer.shadowOffset = CGSize(width: 0, height: 3)
      }
      fc.baseForegroundColor = L.light ? .black : .white; fab.configuration = fc
    }
    if var f2 = fab2.configuration {
      if #available(iOS 26.0, *) { fab2.overrideUserInterfaceStyle = L.light ? .light : .dark } else {
        f2.background.backgroundColor = ToastCapsule.fill(L.light); f2.background.strokeColor = ToastCapsule.line(L.light); f2.background.strokeWidth = 1
      }
      fab2.configuration = f2
    }
    stats.forEach { $0.isHidden = noStats }
    let st = model["stats"] as? [Int] ?? [0, 0, 0]
    let names = ["Due today", "Overdue", "In review"], cols = [L.statG, L.statR, L.statA]
    for (i, v) in stats.enumerated() {
      v.backgroundColor = L.statBg; v.layer.borderColor = L.statLine.cgColor
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
    let animate = window != nil && !isHidden && key == drawnKey && !content.isEmpty && !searching
    drawnKey = key
    var oldCenter: [String: CGPoint] = [:]
    let oldGroup = groupOf
    var oldHeads: [String: UIView] = [:]
    if animate {
      for (id, v) in cards { oldCenter[id] = v.center }
      for v in content where !(v is HomeCard) { if let k = v.accessibilityIdentifier { oldHeads[k] = v } }
    }
    let leavingHeads = content.filter { !($0 is HomeCard) }
    if !animate { leavingHeads.forEach { if !($0 is HomeBlock) { $0.removeFromSuperview() } } }
    content = []
    groupOf = [:]
    if isClient {
      drawBarTitle(model)
      // (its Client Assets folders on top, then "Tasks · N open" with Show completed — kept, not made again)
      if let a = model["assets"] as? [String: Any] {
        assetsStrip.set((a["folders"] as? [[String: Any]]) ?? [], look: L)
        let cid = model["id"] as? String ?? ""
        if cid != stripClient || isHidden { stripClient = cid; assetsStrip.toStart() }
        if assetsStrip.superview !== scroll { scroll.addSubview(assetsStrip) }
        content.append(assetsStrip)
      } else { assetsStrip.removeFromSuperview() }
      tasksHead.set(open: model["open"] as? Int ?? 0, showDone: (model["showDone"] as? Bool) == true)
      if tasksHead.superview !== scroll { scroll.addSubview(tasksHead) }
      content.append(tasksHead)
    }
    var seen = Set<String>()
    var runs: [String: Int] = [:]
    for g in model["groups"] as? [[String: Any]] ?? [] {
      let gname = g["name"] as? String ?? ""
      runs[gname, default: 0] += 1
      let gkey = gname + "#" + String(runs[gname]!)
      let h = UILabel()
      let name = (g["name"] as? String ?? "").uppercased()
      let s = NSMutableAttributedString()
      // (a client's run under Today: its colour dot first, as on the cards)
      if let dot = NativeSheetVC.color(g["dot"]) {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in dot.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 8, height: 8), cornerRadius: 2).fill() }
        let a = NSTextAttachment(); a.image = img; a.bounds = CGRect(x: 0, y: 0.5, width: 8, height: 8)
        s.append(NSAttributedString(attachment: a)); s.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 12), .kern: 2]))
      }
      s.append(NSAttributedString(string: name, attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .kern: 0.72, .foregroundColor: L.gh]))
      if let n = g["n"] as? Int, n > 0 {
        s.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 12), .kern: 3.6]))
        s.append(NSAttributedString(string: "\(n)", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: L.gh.withAlphaComponent(0.8)]))
      }
      h.attributedText = s; h.tag = 7; h.accessibilityIdentifier = gkey
      // (Today: no heading on screen — only the mark the Due today box scrolls to)
      if (g["anchor"] as? Bool) == true { h.isHidden = true }
      scroll.addSubview(h); content.append(h)
      for c in g["cards"] as? [[String: Any]] ?? [] {
        guard let id = c["id"] as? String else { continue }
        seen.insert(id)
        let v: HomeCard
        if let old = cards[id] { v = old } else {
          v = HomeCard(); v.id = id
          v.onTap = { [weak self, weak v] in
            guard let self = self else { return }
            // (a card swiped open: a tap closes it, as in Mail)
            if let o = self.openCard { self.setOpen(o, false); if o === v { return } }
            self.send(["ev": "open", "id": id])
          }
          let pan = UIPanGestureRecognizer(target: self, action: #selector(self.swipe(_:))); pan.delegate = self; v.addGestureRecognizer(pan)
          if APPLE_NAV {
            // (iPhone's own touch and hold, as E11 Talk: the card shrinks as it's held, lifts, and Apple's menu comes
            //  beside it — the same choices the sheet had: Haris 2026-11-07)
            v.addInteraction(UIContextMenuInteraction(delegate: self))
          } else {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(self.press(_:))); lp.minimumPressDuration = 0.45; v.addGestureRecognizer(lp)
            _ = PressShrink.add(to: v)   // (touch and hold, app-wide: it shrinks from the moment the finger is down)
          }
          self.scroll.addSubview(v); self.cards[id] = v
        }
        v.people = people
        v.set(c, look: L)
        content.append(v)
        groupOf[id] = gkey
      }
      if let e = g["empty"] as? String, !e.isEmpty {
        let l = UILabel(); l.text = e; l.font = .systemFont(ofSize: 14); l.textColor = L.empty; l.tag = 8; l.numberOfLines = 0; l.accessibilityIdentifier = "empty|" + gkey
        scroll.addSubview(l); content.append(l)
      }
    }
    var gone: [UIView] = []
    for (id, v) in cards where !seen.contains(id) {
      if v === openCard { actions?.removeFromSuperview(); actions = nil; openCard = nil }
      if animate { gone.append(v) } else { v.removeFromSuperview() }
      cards[id] = nil
    }
    canDelete = (model["canDelete"] as? Bool) == true
    if let t = model["toast"] as? [String: Any] { toast(t) }
    fab.isHidden = (model["add"] as? Bool) != true
    // (the filter buttons again in this light / dark, if it changed)
    if isList, let f = lastFilters { setFilters(f) }

    setNeedsLayout(); layoutIfNeeded()
    // (Apple's list: Apple's own animation for what came, went or moved)
    if listOn { applyList(animated: animate); return }
    if animate { moveList(oldCenter: oldCenter, oldGroup: oldGroup, oldHeads: oldHeads, leavingHeads: leavingHeads, gone: gone) }
  }
  private var drawnKey = ""
  private var groupOf: [String: String] = [:]
  // the list from how it was to how it is now: going — fades out where it is; staying — slides to its place (the gap
  // closing or opening, Mail's spring); coming (or moved to another group) — fades in once its gap has opened
  private func moveList(oldCenter: [String: CGPoint], oldGroup: [String: String], oldHeads: [String: UIView], leavingHeads: [UIView], gone: [UIView]) {
    let fadeOut = 0.2, settle = 0.44
    func fade(_ v: UIView) {
      scroll.bringSubviewToFront(v)
      UIView.animate(withDuration: fadeOut, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { v.alpha = 0 } completion: { _ in v.removeFromSuperview() }
    }
    // going: the removed cards, and the old headings that aren't there any more (the rest are swapped for the new ones)
    gone.forEach(fade)
    var arrivals: [UIView] = [], moves: [(UIView, CGPoint)] = []
    for v in content {
      if let c = v as? HomeCard {
        guard let was = oldCenter[c.id] else { arrivals.append(c); continue }
        if oldGroup[c.id] != groupOf[c.id] {
          // (moved to another group — Overdue → Today: a copy fades out where it was, the card fades in at its new place)
          if let ghost = c.snapshotView(afterScreenUpdates: false) { ghost.center = was; scroll.addSubview(ghost); fade(ghost) }
          arrivals.append(c)
        } else if abs(was.y - c.center.y) > 0.5 { moves.append((c, c.center)); c.center = was }
      } else if let k = v.accessibilityIdentifier, let old = oldHeads[k] {
        let now = v.center
        if abs(old.center.y - now.y) > 0.5 { v.center = old.center; moves.append((v, now)) }
      } else { arrivals.append(v) }
    }
    for h in leavingHeads {
      if content.contains(where: { $0 === h }) { continue }   // (the client page's folders and tasks line: kept, not swapped)
      if let k = h.accessibilityIdentifier, content.contains(where: { $0.accessibilityIdentifier == k }) { h.removeFromSuperview() } else { fade(h) }
    }
    arrivals.forEach { $0.alpha = 0 }
    // the gaps close and open together (Mail's spring: about 0.44 s, no bounce), a moment after the fading starts
    let run = { for (v, to) in moves { v.center = to } }
    if #available(iOS 17.0, *) { UIView.animate(springDuration: settle, bounce: 0, initialSpringVelocity: 0, delay: 0.06, options: [.allowUserInteraction, .beginFromCurrentState], animations: run) }
    else { UIView.animate(withDuration: settle, delay: 0.06, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: run) }
    // coming: once its gap is there
    UIView.animate(withDuration: 0.22, delay: 0.26, options: [.curveEaseOut, .allowUserInteraction]) { arrivals.forEach { $0.alpha = 1 } }
  }
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
      if let o = self.openCard { self.setOpen(o, false) }
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
    let ink: UIColor = on ? (L.light ? .white : .black) : (L.light ? .black : .white)
    if on { c.baseBackgroundColor = L.light ? .black : .white }
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
    let tab = (a["tab"] as? String) == "done" ? "done" : "all"
    if tab != listTab { listTab = tab; if let o = openCard { setOpen(o, false) } }
    seg.selectedSegmentIndex = listTab == "done" ? 1 : 0
    let key = String(describing: a["buttons"] ?? "") + "|" + String(describing: a["chips"] ?? "") + "|" + (L.light ? "l" : "d")
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
    ["tab": listTab, "pinned": pinned, "headTop": listHead.frame.minY, "barBottom": smallHead, "filters": filterBtns.map { $0.accessibilityIdentifier ?? "" }, "chips": chipBtns.count, "cards": cards.count,
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
  var fabNow: (shown: Bool, frame: CGRect, config: UIButton.Configuration?, light: Bool, label: String) {
    let a = CGFloat(fab.layer.presentation()?.opacity ?? fab.layer.opacity)
    return (!fab.isHidden && fab.superview != nil && a > 0.01 && fab.bounds.width > 0, fab.frame, fab.configuration, L.light, fab.accessibilityLabel ?? "")
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
    for v in content where !views.contains(where: { $0 === v }) { v.removeFromSuperview() }
    for v in views where v.superview !== scroll { scroll.addSubview(v) }
    content = views
  }
  var look: HomeLook { L }
  var model: [String: Any] { m }
  func assetsToast(_ t: String) { toast(["t": t]) }
  var assetsMenu: (() -> [CornerMenuItem])?
  private lazy var clientsGroup: ClientsGroup = {
    let g = ClientsGroup(); g.onOpen = { [weak self] id in self?.send(["ev": "client", "id": id]) }
    g.onHold = { [weak self] id in self?.send(["ev": "clientHold", "id": id]) }; return g
  }()
  private var stripClient = ""
  private lazy var assetsStrip: AssetsStrip = {
    let a = AssetsStrip()
    a.onFolder = { [weak self] f in guard let self = self, let c = (self.m["assets"] as? [String: Any])?["id"] as? String else { return }; self.send(["ev": "folder", "client": c, "folder": f]) }
    a.onAll = { [weak self] in guard let self = self, let c = (self.m["assets"] as? [String: Any])?["id"] as? String else { return }; self.send(["ev": "assets", "client": c]) }
    return a
  }()
  // (its own name: "done" is a card's tick, which the app does itself — the toggle went nowhere, Haris 2026-11-02)
  private lazy var tasksHead: TasksHead = { let t = TasksHead(); t.onToggle = { [weak self] in self?.send(["ev": "showDone"]) }; return t }()
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
  }
  private var barLogoPath: String?
  private func drawBarTitle(_ model: [String: Any]) {
    _ = barTitle
    barName.text = model["title"] as? String; barName.textColor = .label
    barIni.text = model["ini"] as? String
    let rgb = NativeSheetVC.color(model["rgb"]) ?? .systemGray
    let lp = model["logo"] as? String
    if lp != barLogoPath {
      barLogoPath = lp; barLogo.image = nil; barLogo.backgroundColor = rgb; barIni.isHidden = false
      if let p = lp { FeedLoader.shared.image(p) { [weak self] img in guard let self = self, self.barLogoPath == p, let img = img else { return }; self.barLogo.image = img; self.barLogo.backgroundColor = .white; self.barIni.isHidden = true } }
    } else if barLogo.image == nil { barLogo.backgroundColor = rgb }
    [title, sub, smallTitle, smallSub].forEach { $0.isHidden = true }
  }
  // its ••• (the shared corner button's menu): Client Assets, Show / Hide completed, New task
  var menuItems: [CornerMenuItem] {
    if assets != nil { return assetsMenu?() ?? [] }
    guard isClient, !m.isEmpty else { return [] }
    var out: [CornerMenuItem] = []
    if m["assets"] is [String: Any] { out.append(CornerMenuItem(title: "Client Assets", symbol: "folder", run: { [weak self] in self?.assetsStrip.onAll?() })) }
    let done = (m["showDone"] as? Bool) == true
    out.append(CornerMenuItem(title: done ? "Hide completed" : "Show completed", symbol: done ? "checkmark.circle.badge.xmark" : "checkmark.circle", run: { [weak self] in self?.send(["ev": "showDone"]) }))
    if (m["add"] as? Bool) == true { out.append(CornerMenuItem(title: "New task", symbol: "plus", run: { [weak self] in self?.send(["ev": "add"]) })) }
    return out
  }
  var backFrame: CGRect { CGRect(x: 16, y: safeAreaInsets.top + 22 - BTN / 2, width: BTN, height: BTN) }
  func backTap() { send(["ev": "back"]) }
  func relayout() { UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.setNeedsLayout(); self.layoutIfNeeded() } }
  func clientsFresh() { clientsGroup.closeInactive(); setNeedsLayout() }
  private func drawClients(_ model: [String: Any]) {
    content.filter { $0 !== clientsGroup }.forEach { $0.removeFromSuperview() }
    clientsGroup.people = people
    clientsGroup.set((model["rows"] as? [[String: Any]]) ?? [], (model["inactive"] as? [[String: Any]]) ?? [], look: L)
    if clientsGroup.superview !== scroll { scroll.addSubview(clientsGroup) }
    content = [clientsGroup]
    // (+ Add client for Admins — Haris 2026-11-03; the app's own New client sheet)
    if (model["canEdit"] as? Bool) == true { setFab("Add client", "plus") { [weak self] in self?.send(["ev": "addClient"]) } } else { fab.isHidden = true }
  }
  private let catsView = MailCats(items: [
    .init(key: "all", sym: "tray", name: "All", fill: MailCats.neutral),
    .init(key: "unread", sym: "envelope", name: "Unread", fill: MailCats.blue),
    .init(key: "mentions", sym: "at", name: "Mentions", fill: MailCats.purple)])
  private let markAll = UIButton(type: .system)
  private(set) var inboxTab = "all"
  private var inboxRows: [String: InboxRow] = [:]
  private var openRow: InboxRow?
  private var keep = Set<String>()     // (rows that were in the list when it was picked stay until it's left — read or not)
  private var switching = false
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
    openRow?.close(animated: false); openRow = nil
    catsView.choose(["all", "unread", "mentions"].firstIndex(of: k) ?? 0, animated: true)
    keep = Set((m["rows"] as? [[String: Any]] ?? []).filter { ($0["read"] as? Bool) != true }.compactMap { $0["id"] as? String })
    switching = true
    drawInbox(m)
    switching = false
    if #available(iOS 26.0, *) { DispatchQueue.main.async { [weak self] in guard let self = self else { return }; Frost.nudge(self.scroll); self.applyFrost() } }
    send(["ev": "tab", "tab": k])
  }
  private func drawInbox(_ model: [String: Any]) {
    fab.isHidden = (model["add"] as? Bool) != true   // (+ New task, as on Home — for those who may)
    markAll.isHidden = ((model["unread"] as? Int) ?? 0) == 0
    markAll.alpha = cornerShared ? 0 : 1
    defer { onCorner?() }
    catsView.light = L.light
    // where each row is now (to move it from there), and which go
    var was: [String: CGPoint] = [:]
    for v in content { if let r = v as? InboxRow { was[r.id] = r.center } }
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
        v.onOpen = { [weak self] row in if let o = self?.openRow, o !== row { o.close() }; self?.openRow = row }
        scroll.addSubview(v); inboxRows[id] = v
      }
      let p = people[r["from"] as? String ?? ""]
      v.set(r, photo: roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 44))
      content.append(v)
    }
    let rowsNow = content.compactMap { $0 as? InboxRow }
    rowsNow.forEach { $0.last = $0 === rowsNow.last }
    // the rows that don't belong any more: faded out where they are, then gone
    for (id, v) in inboxRows where !seen.contains(id) {
      if v === openRow { openRow = nil }
      inboxRows[id] = nil
      UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) { v.alpha = 0 } completion: { _ in v.removeFromSuperview() }
    }
    if content.isEmpty {
      let e = inboxTab == "unread" ? "Inbox zero 🎉" : inboxTab == "mentions" ? "No mentions yet" : "Nothing here yet"
      let l = UILabel(); l.text = e; l.font = .systemFont(ofSize: 15); l.textColor = .secondaryLabel; l.tag = 8; l.numberOfLines = 0; l.textAlignment = .center
      scroll.addSubview(l); content.append(l)
    }
    // the others close up (or open up for the ones coming back, which fade in where they belong) — smoothly, no bounce
    setNeedsLayout(); layoutIfNeeded()
    let moved = content.compactMap { $0 as? InboxRow }
    for r in moved {
      if let from = was[r.id] { r.center = from; r.alpha = 1 } else { r.alpha = switching ? 0 : 1 }
    }
    UIView.animate(withDuration: switching ? 0.35 : 0, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
      self.setNeedsLayout(); self.layoutIfNeeded()
      moved.forEach { $0.alpha = 1 }
    }
  }
  func selfInboxTab(_ k: String) { pickTab(k) }
  func selfSwipeRow() { if let r = content.first as? InboxRow { r.selfOpen(); openRow = r } }
  func inboxGeo() -> [String: Any] {
    ["tab": inboxTab, "rows": content.filter { $0 is InboxRow }.count, "unreadRows": content.compactMap { $0 as? InboxRow }.filter { !$0.read }.count,
     "cats": catsView.widths, "markAll": !markAll.isHidden, "open": openRow?.isOpen ?? false, "pinned": pinned]
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
    layoutResults()
    if let cv = list {
      // (Apple's list: its cells place the boxes, headings and cards; the room under the last card kept as before)
      if cv.frame != bounds { cv.frame = bounds }
      let bottom = max(0, endRoom - safeAreaInsets.bottom)
      if cv.contentInset.bottom != bottom { cv.contentInset.bottom = bottom }
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
      if let r = v as? InboxRow {
        // (Inbox rows: edge to edge, one under the other, as Mail's)
        r.bounds = CGRect(x: 0, y: 0, width: W, height: InboxRow.H); r.center = CGPoint(x: W / 2, y: y + InboxRow.H / 2)
        y += InboxRow.H
        continue
      }
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
      } else if let c = v as? HomeCard {
        let h = c.height(for: lw)
        // (bounds and centre: a card swiped open keeps its sideways shift)
        c.bounds = CGRect(x: 0, y: 0, width: lw, height: h); c.center = CGPoint(x: 16 + lw / 2, y: y + h / 2)
        if c === openCard, let a = actions { a.frame = CGRect(x: a.leading ? 16 : 16 + lw - a.frame.width, y: y, width: a.frame.width, height: h) }
        y += h
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
  func scrollToTop() { sv.setContentOffset(CGPoint(x: 0, y: -inTop), animated: true) }
  // a block's row brought to about 40% down the screen (an Inbox update opening the Reviews on its request)
  func scrollToShow(_ v: UIView, animated: Bool = true) {
    layoutIfNeeded()
    let r = v.convert(v.bounds, to: sv)
    let y = max(-inTop, min(r.midY - sv.bounds.height * 0.4, sv.contentSize.height + inBottom - sv.bounds.height))
    sv.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) { if scrollView === scroll || scrollView === list { layoutHeader(); showMotto(); if appleTop { onAppleScroll?() } } }
  // (Apple's bar coming in — after the startup screen, or back from another tab — or its big title growing: a list that
  //  was at its top stays at its top, the big title showing; it opened scrolled under the small title — Haris 2026-11-07)
  private var lastTopIn: CGFloat = 0
  func scrollViewDidChangeAdjustedContentInset(_ sv: UIScrollView) {
    guard appleTop, sv === list || sv === results else { lastTopIn = sv.adjustedContentInset.top; return }
    let was = lastTopIn, now = sv.adjustedContentInset.top
    lastTopIn = now
    if !sv.isDragging && !sv.isDecelerating && sv.contentOffset.y <= -was + 1 && abs(now - was) > 0.5 { sv.contentOffset.y = -now }
  }
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
    if let o = openCard { setOpen(o, false) }
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
    resultViews.forEach { $0.removeFromSuperview() }
    resultViews = []
    var seen = Set<String>()
    let q = (field.text ?? "").trimmingCharacters(in: .whitespaces)
    if let r = r {
      let marks = (r["marks"] as? [String]) ?? []
      let clients = (r["clients"] as? [[String: Any]] ?? []).map { var x = $0; x["marks"] = marks; return x }, tasks = (r["tasks"] as? [[String: Any]] ?? []).map { var x = $0; x["marks"] = marks; return x }
      walkFirst = (tasks.first?["id"] as? String, clients.first?["id"] as? String)
      // (a word that only matched as a typo: "Showing results for ford (you typed “frod”)" — app.js searchFixedNote)
      if let fx = r["fixed"] as? [[String: Any]], !fx.isEmpty { let n = SearchFixedNote(); n.set(fx, light: L.light); results.addSubview(n); resultViews.append(n) }
      if !clients.isEmpty {
        resultViews.append(groupHead("Clients", clients.count))
        for c in clients {
          let row = HomeClientRow(); row.set(c, look: L); _ = PressShrink.add(to: row)
          let id = c["id"] as? String ?? ""
          row.addAction(UIAction { [weak self] _ in self?.resignSearch(); self?.send(["ev": "client", "id": id]) }, for: .touchUpInside)
          results.addSubview(row); resultViews.append(row)
        }
      }
      if !tasks.isEmpty {
        resultViews.append(groupHead("Tasks", (r["total"] as? Int) ?? tasks.count))
        for c in tasks {
          guard let id = c["id"] as? String else { continue }
          seen.insert(id)
          let v: HomeCard
          if let old = resultCards[id] { v = old } else {
            v = HomeCard(); v.id = id
            v.onTap = { [weak self, weak v] in
              guard let self = self else { return }
              if let o = self.openCard { self.setOpen(o, false); if o === v { return } }
              self.resignSearch(); self.send(["ev": "open", "id": id])
            }
            // (a task card is the same card wherever it shows — Haris, 2026-11-02: swipe right Done · Due, left Copy link ·
            //  Delete, touch and hold Attach Files — in the search results too)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(self.swipe(_:))); pan.delegate = self; v.addGestureRecognizer(pan)
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(self.press(_:))); lp.minimumPressDuration = 0.45; v.addGestureRecognizer(lp)
            _ = PressShrink.add(to: v)
            resultCards[id] = v
          }
          v.people = people; v.set(c, look: L)
          results.addSubview(v); resultViews.append(v)
        }
      }
      hint.text = clients.isEmpty && tasks.isEmpty ? "No tasks found. Try a client or person’s name." : nil
    } else { hint.text = q.isEmpty ? "Search tasks, clients or people." : nil }
    for (id, v) in resultCards where !seen.contains(id) { v.removeFromSuperview(); resultCards[id] = nil }
    setNeedsLayout()
  }
  // what Client Assets found (its rows, as blocks), or what to say
  func showFound(_ views: [UIView], hint t: String?) {
    resultViews.forEach { $0.removeFromSuperview() }
    resultViews = views
    views.forEach { results.addSubview($0) }
    hint.text = t; hint.textColor = L.empty
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
    results.addSubview(h)
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
      else if let c = v as? HomeCard { let h = c.height(for: lw); c.bounds = CGRect(x: 0, y: 0, width: lw, height: h); c.center = CGPoint(x: 16 + lw / 2, y: y + h / 2); y += h }
      else if let b = v as? HomeBlock { let h = b.blockHeight(W); b.frame = CGRect(x: 0, y: y, width: W, height: h); y += h }
      else if let n = v as? SearchFixedNote { let h = n.height(for: lw); n.frame = CGRect(x: 16, y: y, width: lw, height: h); y += h }
      else { v.frame = CGRect(x: 16, y: y, width: lw, height: 70); y += 70 }
    }
    results.contentSize = CGSize(width: W, height: y + 20)
  }
  @objc private func statTap(_ g: UITapGestureRecognizer) {
    guard let v = g.view, !searching else { return }
    if let o = openCard { setOpen(o, false) }
    UIView.animate(withDuration: 0.08, animations: { v.transform = CGAffineTransform(scaleX: 0.96, y: 0.96) }) { _ in UIView.animate(withDuration: 0.15) { v.transform = .identity } }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let i = v.tag - 100
    if i == 2 { send(["ev": "review"]); return }
    showGroup(i == 0 ? "Today" : "Overdue")
  }
  // a group's heading brought up to where the big title is (as far as the list goes)
  func showGroup(_ name: String) {
    guard let h = content.first(where: { $0.tag == 7 && $0.accessibilityIdentifier == name }) else { return }
    if let cv = list, let ds = listDS {
      // (Apple's list: that group's heading — Today's first card, its heading being only a mark — to the top)
      guard let i = content.firstIndex(where: { $0 === h }) else { return }
      let after = content[i...].first { v in v is HomeCard || !(v.tag == 7 && v.isHidden) }
      let key = after.map { v -> String in (v as? HomeCard).map { "c:" + $0.id } ?? ((v.tag == 8 ? "e:" : "h:") + (v.accessibilityIdentifier ?? "")) }
      if let k = key, let ip = ds.indexPath(for: k) { cv.scrollToItem(at: ip, at: .top, animated: true) }
      return
    }
    let want = appleTop ? h.frame.minY - 12 - (safeAreaInsets.top) : h.frame.minY - (safeAreaInsets.top + 66)
    let maxY = max(-inTop, scroll.contentSize.height + inBottom - scroll.bounds.height)
    scroll.setContentOffset(CGPoint(x: 0, y: min(maxY, max(-inTop, want))), animated: true)
  }
  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { if scrollView === scroll { layoutHeader() } }
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { if let o = openCard { setOpen(o, false) } }

  // ---------- swipe left on a card: Copy link · Delete; swipe right: Done · Due (as in Mail: round buttons with their names
  // under them) ----------
  private func leadOK(_ card: HomeCard) -> Bool { (card.info["canDone"] as? Bool) == true || (card.info["canDue"] as? Bool) == true }
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    // (My Tasks' Done tab: completed tasks are read only — no swipes, no Attach Files)
    if isList && listTab == "done" && g.view is HomeCard && (g is UIPanGestureRecognizer || g is UILongPressGestureRecognizer) { return false }
    guard let p = g as? UIPanGestureRecognizer, let card = p.view as? HomeCard else { return true }
    if listOn && card.superview !== results { return false }   // (Apple's list: Apple's swipe actions)
    let v = p.velocity(in: self)
    return abs(v.x) > abs(v.y) * 1.2 && (v.x < 0 || card.swipeX != 0 || leadOK(card))
  }
  private func reveal(_ leading: Bool) -> CGFloat {
    let n = leading ? max(1, actions?.leading == true ? actions!.count : 2) : (canDelete ? 2 : 1)
    return 20 + CGFloat(n) * 64
  }
  // (+1: the card slid right, Done · Due on its left; -1: slid left, Copy link · Delete on its right)
  private var openSide: CGFloat { (openCard?.swipeX ?? 0) > 0 ? 1 : -1 }
  private func actionsFor(_ card: HomeCard, leading: Bool) -> HomeActions {
    if let a = actions, openCard === card, a.leading == leading { return a }
    actions?.removeFromSuperview()
    let a: HomeActions
    if leading {
      let d = card.info
      a = HomeActions(done: (d["done"] as? Bool) == true, showDone: (d["canDone"] as? Bool) == true, due: d["due"] as? String, showDue: (d["canDue"] as? Bool) == true, cdHold: (d["cdHold"] as? Bool) == true)
    } else { a = HomeActions(delete: canDelete, light: L.light) }
    let w = 20 + CGFloat(a.count) * 64
    a.frame = CGRect(x: leading ? card.center.x - card.bounds.width / 2 : card.center.x + card.bounds.width / 2 - w, y: card.center.y - card.bounds.height / 2, width: w, height: card.bounds.height)
    a.onCopy = { [weak self, weak card] in
      guard let self = self, let card = card else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      self.send(["ev": "copy", "id": card.id]); self.setOpen(card, false)
    }
    a.onDelete = { [weak self, weak card] in
      guard let self = self, let card = card else { return }
      // (asked first: the task goes to the Trash)
      let al = UIAlertController(title: "Delete this task?", message: card.taskTitle.isEmpty ? nil : card.taskTitle, preferredStyle: .actionSheet)
      al.addAction(UIAlertAction(title: "Delete Task", style: .destructive) { _ in self.send(["ev": "delete", "id": card.id, "card": card.info]); self.setOpen(card, false); self.findAgain() })
      al.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in self.setOpen(card, false) })
      al.overrideUserInterfaceStyle = self.L.light ? .light : .dark
      self.present?(al)
    }
    // Done: green at once (grey again when a done task is reopened), then the card closes and the page does the rest — as
    // its own tick: a task not ready to complete only shows why (the circle stays grey), Undo on the toast
    a.onDone = { [weak self, weak card, weak a] in
      guard let self = self, let card = card else { return }
      let wasDone = (card.info["done"] as? Bool) == true, ready = (card.info["doneReady"] as? Bool) == true
      if wasDone || ready {
        a?.markDone(!wasDone)
        if !wasDone { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + (wasDone || ready ? 0.35 : 0)) {
        self.send(["ev": "done", "id": card.id, "done": !wasDone, "card": card.info]); self.setOpen(card, false); self.findAgain()
      }
    }
    // Due: the card closes and the page opens the date sheet the task page uses
    a.onDue = { [weak self, weak card] in
      guard let self = self, let card = card else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      self.send(["ev": "due", "id": card.id, "card": card.info]); self.setOpen(card, false); self.findAgain()
    }
    (card.superview as? UIScrollView ?? scroll).insertSubview(a, belowSubview: card)   // (Home's list, or the search results)
    actions = a; openCard = card
    return a
  }
  private var swipeLead = false
  private var lastSwipeV: CGFloat = 0   // (the finger's speed as it let go: the spring carries it on)
  @objc private func swipe(_ g: UIPanGestureRecognizer) {
    guard let card = g.view as? HomeCard else { return }
    switch g.state {
    case .began:
      if let o = openCard, o !== card { setOpen(o, false) }
      card.swipeStart = card.swipeX
      swipeLead = card.swipeX != 0 ? card.swipeX > 0 : g.velocity(in: self).x > 0
      if swipeLead && !leadOK(card) { swipeLead = false }
      _ = actionsFor(card, leading: swipeLead)
    case .changed:
      var x = card.swipeStart + g.translation(in: self).x
      let r = reveal(swipeLead)
      if swipeLead {
        if x < 0 { x = 0 }
        if x > r { x = r + (x - r) / 3 }   // (past the buttons: held back)
      } else {
        if x > 0 { x = 0 }
        if x < -r { x = -r + (x + r) / 3 }
      }
      card.swipeX = x
      actions?.progress = min(1, abs(x) / r)
    case .ended, .cancelled, .failed:
      let v = g.velocity(in: self).x, r = reveal(swipeLead)
      lastSwipeV = v
      if swipeLead { setOpen(card, v > 350 || (card.swipeX > r / 2 && v > -300), leading: true) }
      else { setOpen(card, v < -350 || (card.swipeX < -r / 2 && v < 300), leading: false) }
    default: break
    }
  }
  func setOpen(_ card: HomeCard, _ open: Bool, leading: Bool? = nil) {
    let lead = leading ?? (openCard === card ? openSide > 0 : false)
    if open { _ = actionsFor(card, leading: lead) }
    let a = actions, r = reveal(lead)
    let fingerV = lastSwipeV; lastSwipeV = 0
    SwipeSpring.run(from: card.swipeX, to: open ? (lead ? r : -r) : 0, velocity: fingerV) {
      card.swipeX = open ? (lead ? r : -r) : 0
      a?.progress = open ? 1 : 0
    } completion: {
      if !open && card.swipeX == 0 && self.openCard === card { a?.removeFromSuperview(); if self.actions === a { self.actions = nil }; self.openCard = nil }
    }
  }

  // ---------- long press a card: Attach Files (Camera · Photos · Files), the card lifted over the dimmed screen ----------
  @objc private func press(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began, let card = g.view as? HomeCard, !(isList && listTab == "done") else { return }   // (Done tab: read only)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    attach(card)
  }
  private func attach(_ card: HomeCard) {
    if let o = openCard { setOpen(o, false) }
    card.isHighlighted = false
    let id = card.id
    let sheet = AttachSheetVC(light: L.light, title: "Attach Files") { [weak self] src in self?.send(["ev": "attach", "id": id, "source": src]) }
    // (the lifted picture is the card at its full size, and the card itself is hidden under it while the sheet is up —
    //  the shrunk card showed its border round the picture: a double border, Haris 2026-11-02)
    (card.gestureRecognizers?.first { $0 is PressShrink } as? PressShrink)?.release()
    card.layer.removeAllAnimations(); card.transform = CGAffineTransform(translationX: card.swipeX, y: 0)
    if let snap = card.snapshotView(afterScreenUpdates: true) {
      sheet.lifted = snap; sheet.liftedFrame = card.convert(card.bounds, to: nil)
      card.alpha = 0
      sheet.onLiftedGone = { [weak card] in card?.alpha = 1 }
    }
    present?(sheet)
    // (never left hidden if the sheet didn't come up)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak card, weak sheet] in if sheet?.view.window == nil { card?.alpha = 1 } }
  }

  // ---------- a toast over Home (the page's own would be under it): "Link copied", "2 files added to …", Undo ----------
  // a toast (Haris 2026-11-03, option C): "+ New task" stretches into it — "New task" fades, the capsule stretches to
  // the left with the + at its right end as a small round button, the tick, the words and Undo fade in; about 3 s later
  // (longer while a finger is on it) it shrinks back into "+ New task". A plain capsule, light and dark — no glass. A new
  // message while it's out (an upload's progress): only the words change.
  func toast(_ t: [String: Any]) {
    let text = t["t"] as? String ?? "", act = t["a"] as? String ?? ""
    let ms = (t["ms"] as? Double) ?? 3000
    if let c = toastCap, c.out { c.say(text, act); c.hold(ms); return }
    toastCap?.removeFromSuperview(); toastCap = nil
    layoutIfNeeded()
    let W = bounds.width
    let withFab = !fab.isHidden && fab.frame.width > 0
    let bottom = withFab ? fab.frame.maxY : (tabTop ?? bounds.height - 40) - 12
    let from = withFab ? fab.frame : CGRect(x: W - R - BTN, y: bottom - BTN, width: BTN, height: BTN)
    let to = CGRect(x: 16, y: from.minY, width: from.maxX - 16, height: from.height)
    let c = ToastCapsule(light: L.light, title: withFab ? (fab.accessibilityLabel ?? "New task") : nil, sym: withFab ? fabSym : nil, plus: withFab)
    c.say(text, act)
    c.onUndo = { [weak self, weak c] in c?.close(); self?.onEvent?(["ev": "toast"]) }
    c.onPlus = { [weak self] in UIImpactFeedbackGenerator(style: .light).impactOccurred(); if let a = self?.fabRun { a() } else { self?.send(["ev": "add"]) } }
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
  // (for the self-test: the first card swiped open, held, closed)
  private var firstCard: HomeCard? { content.compactMap { $0 as? HomeCard }.first }
  func selfSwipe() { if let c = firstCard { setOpen(c, true) } }
  func selfPress() { if let c = firstCard { attach(c) } }
  func selfSwipeRight() { if let c = firstCard { setOpen(c, true, leading: true) } }
  func selfClose() { if let o = openCard { setOpen(o, false) } }
  func selfScroll(_ y: CGFloat) { sv.setContentOffset(CGPoint(x: 0, y: y - inTop), animated: false); layoutHeader(); if !appleTop { setBar(barIn, now: true) } }
  func selfFind(_ q: String) { openSearch(); field.text = q; typed() }
  func selfFindDone() { closeSearch() }
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
    ["open": openCard != nil, "openShift": openCard?.swipeX ?? 0, "actions": actions?.subviews.count ?? 0, "lead": actions?.leading ?? false,
     "title": title.text ?? "", "date": sub.text ?? "", "stats": stats.map { ($0.viewWithTag(1) as? UILabel)?.text ?? "" },
     "groups": content.filter { $0.tag == 7 }.map { ($0 as? UILabel)?.text ?? "" }, "cards": cards.count, "fab": !fab.isHidden,
     "headH": blur.frame.height, "shrink": shrink, "bar": blur.alpha, "smallTitle": smallTitle.alpha, "searching": searching,
     "searchBarW": searchBar.isHidden ? 0 : searchBar.frame.width, "results": resultViews.count, "light": L.light,
     "apple": appleTop, "appleList": listOn, "listCells": list?.visibleCells.count ?? 0, "scrolledY": sv.contentOffset.y + inTop]
  }
}

// the colours the page's own Home uses (phone.css), read from it; dark / light defaults when a piece isn't on it
struct HomeLook {
  let light: Bool
  let bg, headBg, sub, h1, round, roundIc, statBg, statLine, statLabel, statG, statR, statA, gh, empty: UIColor
  let card, cardLine, lateLine, title, meta, sep, late, today, doneTitle, tag, tagBg, urgent, urgentBg, more, moreBg, fabBg, fabLine: UIColor
  let headH: CGFloat?, fabRect: CGRect?
  init(_ d: [String: Any]?) {
    let lt = (d?["light"] as? Bool) ?? false
    light = lt
    func c(_ k: String, _ dark: UIColor, _ lightC: UIColor) -> UIColor {
      guard let a = d?[k] as? [NSNumber], a.count >= 3 else { return lt ? lightC : dark }
      return UIColor(red: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: a.count > 3 ? CGFloat(a[3].doubleValue) : 1)
    }
    let w = UIColor.white, k = UIColor.black
    bg = c("bg", SplashView.hex(0x0c0d0f), SplashView.hex(0xf4f4f7)); headBg = c("headBg", bg, bg)
    // (every grey on the app's own screens is the date's grey: iPhone's secondary label — Haris, 2026-10-31)
    let grey = UIColor.secondaryLabel
    sub = grey; h1 = c("h1", SplashView.hex(0xe9eaee), SplashView.hex(0x17181b))
    round = c("round", w.withAlphaComponent(0.08), k.withAlphaComponent(0.05)); roundIc = c("roundIc", h1, h1)
    statBg = c("statBg", w.withAlphaComponent(0.06), w.withAlphaComponent(0.7)); statLine = c("statLine", w.withAlphaComponent(0.12), w)
    statLabel = grey
    statG = c("statG", SplashView.hex(0x3ddc97), SplashView.hex(0x1a9e63)); statR = c("statR", SplashView.hex(0xff7a7a), SplashView.hex(0xd9363e)); statA = c("statA", SplashView.hex(0xf9be33), SplashView.hex(0xb57d00))
    gh = grey; empty = grey
    card = c("card", SplashView.hex(0x121317), w); cardLine = c("cardLine", SplashView.hex(0x1d1f24), .clear)
    lateLine = c("lateLine", UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.45), UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.45))
    title = c("title", SplashView.hex(0xe9eaee), SplashView.hex(0x17181b)); meta = grey
    sep = grey; late = c("late", SplashView.hex(0xff8a8a), SplashView.hex(0xd9363e)); today = c("today", SplashView.hex(0x8fbcff), SplashView.hex(0x2f6fd6))
    doneTitle = grey
    tag = c("tag", SplashView.hex(0xc9c0ff), SplashView.hex(0x5b4bd6)); tagBg = c("tagBg", UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.18), UIColor(red: 123 / 255, green: 104 / 255, blue: 238 / 255, alpha: 0.14))
    urgent = c("urgent", SplashView.hex(0xff9494), SplashView.hex(0xd9363e)); urgentBg = c("urgentBg", UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.16), UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.12))
    more = grey; moreBg = c("moreBg", w.withAlphaComponent(0.08), k.withAlphaComponent(0.06))
    let f = d?["fab"] as? [String: Any]
    func fc(_ k: String, _ dflt: UIColor) -> UIColor {
      guard let a = f?[k] as? [NSNumber], a.count >= 3 else { return dflt }
      return UIColor(red: CGFloat(a[0].doubleValue) / 255, green: CGFloat(a[1].doubleValue) / 255, blue: CGFloat(a[2].doubleValue) / 255, alpha: a.count > 3 ? CGFloat(a[3].doubleValue) : 1)
    }
    fabBg = fc("bg", SplashView.hex(0x5b4bd6)); fabLine = fc("line", .clear)
    if let r = f?["rect"] as? [NSNumber], r.count == 4, r[2].doubleValue > 0 { fabRect = CGRect(x: r[0].doubleValue, y: r[1].doubleValue, width: r[2].doubleValue, height: r[3].doubleValue) } else { fabRect = nil }
    headH = (d?["headH"] as? NSNumber).map { CGFloat($0.doubleValue) }
  }
}

// one task card (phone.js card(), phone.css .pc)
final class HomeCard: UIControl {
  var onTap: (() -> Void)?
  var id = ""
  var taskTitle: String { c["title"] as? String ?? "" }
  var info: [String: Any] { c }
  private var inline = false   // (a Today card: one line, comments and the CD chip on it)
  var swipeStart: CGFloat = 0
  // (sideways when swiped open. Pressed: only the shared PressShrink shrinks it — its own small press-in as well made
  //  the card shrink twice, Haris 2026-11-02)
  var swipeX: CGFloat = 0 { didSet { applyTransform() } }
  private func applyTransform() {
    let s = sqrt(transform.a * transform.a + transform.c * transform.c)   // (keeps a press-shrink in progress)
    transform = CGAffineTransform(translationX: swipeX, y: 0).scaledBy(x: s, y: s)
  }
  var people: [String: [String: Any]] = [:] { didSet { if picsKey(oldValue) != picsKey(people) { drawPeople() } } }
  private let icon = UIImageView(), titleL = UILabel(), metaL = UILabel(), chip = UIView(), chipL = UILabel(), badge = UILabel(), avs = UIView()
  // (a search result found by something other than its title: where, with the words in blue — app.js searchWhy, Haris
  //  2026-11-06)
  private let foundBox = UIView(), foundL = UILabel()
  private var c: [String: Any] = [:]
  private var L = HomeLook(nil)
  private var stackW: CGFloat = 0
  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 20; layer.borderWidth = 1
    titleL.numberOfLines = 0; metaL.numberOfLines = 0
    chip.layer.cornerRadius = 4; chip.addSubview(chipL)
    badge.layer.cornerRadius = 6; badge.clipsToBounds = true; badge.textAlignment = .center
    [icon, titleL, metaL, chip, badge, avs].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
    foundL.numberOfLines = 3; foundBox.layer.cornerRadius = 12; foundBox.layer.cornerCurve = .continuous; foundBox.isUserInteractionEnabled = false
    foundBox.addSubview(foundL); foundBox.isHidden = true; addSubview(foundBox)
    addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
  }
  required init?(coder: NSCoder) { fatalError() }
  // (.pc:active: pressed in a little)

  func set(_ d: [String: Any], look: HomeLook) {
    c = d; L = look
    let late = (d["late"] as? Bool) == true, done = (d["done"] as? Bool) == true
    backgroundColor = L.card
    layer.borderColor = (late ? L.lateLine : L.cardLine).cgColor
    layer.shadowOpacity = 0
    let t = d["title"] as? String ?? ""
    let ps = NSMutableParagraphStyle(); ps.minimumLineHeight = 20.15; ps.maximumLineHeight = 20.15
    var ta: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15.5, weight: t.isEmpty ? .medium : .semibold), .foregroundColor: done || t.isEmpty ? L.doneTitle : L.title, .paragraphStyle: ps, .baselineOffset: 1.5]
    if t.isEmpty { ta[.font] = UIFont.italicSystemFont(ofSize: 15.5) }
    if done { ta[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    let marks = (d["marks"] as? [String]) ?? []
    titleL.attributedText = t.isEmpty || marks.isEmpty ? NSAttributedString(string: t.isEmpty ? "Untitled task" : t, attributes: ta)
      : HomeCard.marked(t, marks, base: ta, mark: [.backgroundColor: UIColor.systemBlue.withAlphaComponent(L.light ? 0.16 : 0.3)])
    if let f = d["found"] as? [String: Any] {
      foundBox.isHidden = false
      foundBox.backgroundColor = L.light ? UIColor(white: 0.965, alpha: 1) : UIColor(white: 0.14, alpha: 1)
      let base: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: L.meta]
      let s = NSMutableAttributedString(string: (f["label"] as? String ?? "") + ": ", attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: L.title])
      s.append(HomeCard.marked(f["text"] as? String ?? "", marks, base: base, mark: [.foregroundColor: UIColor.systemBlue, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)]))
      foundL.attributedText = s
    } else { foundBox.isHidden = true; foundL.attributedText = nil }
    // the CD chip (CD Review / ✓ CD Approved) at the end of the line under the title, on its last line when it fits
    // (Haris, 2026-10-31: "1 comment" and the chip together)
    inline = (d["inline"] as? Bool) == true
    let ml = NSMutableAttributedString(attributedString: meta(d["meta"] as? [[String: Any]] ?? []))
    if let cd = d["cd"] as? [String: Any] {
      let img = HomeCard.cdChip(cd["t"] as? String ?? "", check: (cd["check"] as? Bool) == true, color: NativeSheetVC.color(cd["rgb"]) ?? .systemYellow)
      let a = NSTextAttachment(); a.image = img
      let f = UIFont.systemFont(ofSize: 12.5)
      a.bounds = CGRect(x: 0, y: ((f.capHeight - img.size.height) / 2).rounded(), width: img.size.width, height: img.size.height)
      // (after the comments on the second line; with no comments, the second line is the chip's own)
      // (a Today card is one line: status · comments · CD chip)
      let hasCm = (d["inline"] as? Bool) == true || (d["meta"] as? [[String: Any]] ?? []).contains(where: HomeCard.isComments)
      if ml.length > 0 { ml.append(NSAttributedString(string: hasCm ? " " : "\n", attributes: hasCm ? [.font: f, .kern: 4.9] : [.font: f])) }
      ml.append(NSAttributedString(attachment: a))
    }
    metaL.attributedText = ml
    icon.image = HomeCard.statusIcon(d["icon"] as? [String: Any])
    chip.isHidden = true
    // Urgent, or the priority number
    if let b = d["badge"] as? [String: Any] {
      let u = (b["urgent"] as? Bool) == true
      badge.isHidden = false
      badge.attributedText = NSAttributedString(string: b["t"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: u ? L.urgent : L.tag])
      badge.backgroundColor = u ? L.urgentBg : L.tagBg
    } else { badge.isHidden = true }
    drawPeople()
    setNeedsLayout()
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
  // the line under the title: client (with its colour), status, due date, comments — 6 apart, "·" between
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
      if let dot = NativeSheetVC.color(it["dot"]) {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in dot.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 8, height: 8), cornerRadius: 2).fill() }
        let a = NSTextAttachment(); a.image = img; a.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
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
    let ps = NSMutableParagraphStyle(); ps.lineSpacing = 1
    s.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: s.length))
    return s
  }
  // the assignees' pictures (two, overlapping, ringed in the card's colour; a green tick when their part is done) and "+N"
  private func drawPeople() {
    avs.subviews.forEach { $0.removeFromSuperview() }
    let list = c["av"] as? [[String: Any]] ?? []
    var x: CGFloat = 0
    func ringed(_ img: UIImage) -> UIView {
      let r = UIView(frame: CGRect(x: x - 2, y: -2, width: 26, height: 26)); r.backgroundColor = L.card; r.layer.cornerRadius = 13
      let iv = UIImageView(image: img); iv.frame = CGRect(x: 2, y: 2, width: 22, height: 22); r.addSubview(iv)
      return r
    }
    for a in list {
      let id = a["id"] as? String ?? ""
      let p = people[id]
      let v = ringed(roundPic(NativeSheetVC.photo(p), initials: p?["initials"] as? String, color: NativeSheetVC.color(p?["color"]), size: 22))
      if (a["done"] as? Bool) == true {
        let t = UIView(frame: CGRect(x: 13, y: 13, width: 16, height: 16))
        t.backgroundColor = L.card; t.layer.cornerRadius = 8
        let g = UIView(frame: CGRect(x: 2, y: 2, width: 12, height: 12)); g.backgroundColor = SplashView.green; g.layer.cornerRadius = 6
        let ck = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .black)))
        ck.tintColor = SplashView.hex(0x0b1d14); ck.frame = CGRect(x: 2, y: 2, width: 8, height: 8); ck.contentMode = .center
        g.addSubview(ck); t.addSubview(g); v.addSubview(t)
      }
      avs.addSubview(v)
      x += 16
    }
    if let n = c["more"] as? Int, n > 0 {
      let r = UIView(frame: CGRect(x: x - 2, y: -2, width: 26, height: 26)); r.backgroundColor = L.card; r.layer.cornerRadius = 13
      let l = UILabel(frame: CGRect(x: 2, y: 2, width: 22, height: 22)); l.text = "+\(n)"; l.font = .systemFont(ofSize: 9.5, weight: .semibold); l.textColor = L.more
      l.backgroundColor = L.moreBg; l.layer.cornerRadius = 11; l.clipsToBounds = true; l.textAlignment = .center
      r.addSubview(l); avs.addSubview(r); x += 16
    }
    // (22 for the first, 16 more for each next one: they overlap by 6)
    stackW = x > 0 ? x + 6 : 0
    avs.frame.size = CGSize(width: stackW, height: 22)
    setNeedsLayout()
  }
  // (.pc: 14 inside, the icon 22 on the left, 12 to the text, the badge and pictures on the right)
  private func sideSize() -> CGSize {
    var w: CGFloat = 0, h: CGFloat = 0
    if !badge.isHidden { let s = badge.attributedText?.size() ?? .zero; w = ceil(s.width) + 14; h = ceil(s.height) + 6 }
    if stackW > 0 { w = max(w, stackW); h += (h > 0 ? 6 : 0) + 22 }
    return CGSize(width: w, height: h)
  }
  private func bodyHeight(_ bw: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    let th = ceil(titleL.sizeThatFits(CGSize(width: bw, height: 1000)).height)
    let mh = ceil(metaL.sizeThatFits(CGSize(width: bw, height: 1000)).height)
    return (th, mh, 0)
  }
  func height(for w: CGFloat) -> CGFloat {
    let side = sideSize()
    let bw = w - 1 - 14 - 22 - 12 - (side.width > 0 ? side.width + 12 : 0) - 14 - 1
    let (th, mh, ch) = bodyHeight(bw)
    let body = th + 5 + mh + (ch > 0 ? 5 + ch : 0)
    return 1 + 14 + max(23, body, side.height) + foundH(w) + 14 + 1
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width
    icon.frame = CGRect(x: 15, y: 16, width: 22, height: 22)
    let side = sideSize()
    let bx: CGFloat = 15 + 22 + 12
    let bw = w - bx - (side.width > 0 ? side.width + 12 : 0) - 15
    let (th, mh, ch) = bodyHeight(bw)
    titleL.frame = CGRect(x: bx, y: 15, width: bw, height: th)
    metaL.frame = CGRect(x: bx, y: 15 + th + 5, width: bw, height: mh)
    if ch > 0 {
      let cs = chipL.attributedText?.size() ?? .zero
      chip.frame = CGRect(x: bx + 8, y: metaL.frame.maxY + 5, width: ceil(cs.width) + 12, height: ch)
      chipL.frame = CGRect(x: 6, y: 0, width: ceil(cs.width) + 2, height: ch)
    }
    var y: CGFloat = 15
    if !badge.isHidden { let s = badge.attributedText?.size() ?? .zero; badge.frame = CGRect(x: w - 15 - ceil(s.width) - 14, y: y, width: ceil(s.width) + 14, height: ceil(s.height) + 6); y = badge.frame.maxY + 6 }
    if stackW > 0 { avs.frame = CGRect(x: w - 15 - stackW, y: y, width: stackW, height: 22) }
    if !foundBox.isHidden {
      let top = 15 + max(23, th + 5 + mh, side.height) + 10
      let fw = w - bx - 15
      foundBox.frame = CGRect(x: bx, y: top, width: fw, height: foundH(w) - 10)
      foundL.frame = foundBox.bounds.insetBy(dx: 11, dy: 9)
    }
  }
  // (the found box's room: its words at the body's width, 9 above and below, 10 above it)
  private func foundH(_ w: CGFloat) -> CGFloat {
    guard !foundBox.isHidden else { return 0 }
    let fw = w - (15 + 22 + 12) - 15 - 22
    return 10 + ceil(foundL.sizeThatFits(CGSize(width: fw, height: 200)).height) + 18
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
    }
  }
}

// the buttons a swiped card shows: Copy link (grey) and Delete (red, for those who may), round with their names under
final class HomeActions: UIView {
  var onCopy: (() -> Void)?, onDelete: (() -> Void)?, onDone: (() -> Void)?, onDue: (() -> Void)?
  let leading: Bool
  private var items: [UIView] = []
  private(set) var doneBtn: UIButton?
  var progress: CGFloat = 0 { didSet { items.forEach { $0.alpha = progress; $0.transform = CGAffineTransform(scaleX: 0.6 + 0.4 * progress, y: 0.6 + 0.4 * progress) } } }
  static let grey = SplashView.hex(0x8a8d96), green = SplashView.hex(0x30d158), purple = SplashView.hex(0x7a6ff0), orange = SplashView.hex(0xff9f0a)
  private func item(_ name: String, _ col: UIColor, sym: String? = nil, inner: UIView? = nil, _ act: @escaping () -> Void) -> (UIView, UIButton) {
    let v = UIView()
    let b = UIButton(type: .custom)
    b.backgroundColor = col; b.layer.cornerRadius = 26; b.tintColor = .white
    if let sym = sym { b.setImage(UIImage(systemName: sym, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal) }
    b.frame = CGRect(x: 0, y: 0, width: 52, height: 52)
    if let inner = inner { inner.isUserInteractionEnabled = false; inner.frame = b.bounds; b.addSubview(inner) }
    b.addAction(UIAction { _ in act() }, for: .touchUpInside)
    b.accessibilityLabel = name
    let l = UILabel(); l.text = name; l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabel; l.textAlignment = .center
    l.frame = CGRect(x: -14, y: 58, width: 80, height: 15)
    v.addSubview(b); v.addSubview(l)
    v.bounds = CGRect(x: 0, y: 0, width: 52, height: 73)
    return (v, b)
  }
  // swiped left (trailing): Copy link · Delete
  init(delete: Bool, light: Bool) {
    leading = false
    super.init(frame: .zero)
    items.append(item("Copy link", HomeActions.grey, sym: "link", { [weak self] in self?.onCopy?() }).0)
    if delete { items.append(item("Delete", SplashView.hex(0xe5484d), sym: "trash", { [weak self] in self?.onDelete?() }).0) }
    items.forEach { addSubview($0) }
    progress = 0
  }
  // swiped right (leading), as Mail's Unread · Remind Me: Done (grey, green once done) · Due (the day big, the month under
  // it; SET with a calendar when there's none) — Haris, 2026-10-31
  init(done: Bool, showDone: Bool, due: String?, showDue: Bool, cdHold: Bool = false) {
    leading = true
    super.init(frame: .zero)
    if showDone && cdHold {
      // held by the CD's review: a faded orange "CD" · Review — a tap says why (Haris, 2026-10-31)
      let cd = UILabel(); cd.text = "CD"; cd.font = .systemFont(ofSize: 16, weight: .bold); cd.textColor = .white; cd.textAlignment = .center
      let (v, b) = item("Review", HomeActions.orange, inner: cd, { [weak self] in self?.onDone?() })
      b.alpha = 0.42
      (v.subviews.compactMap { $0 as? UILabel }.first)?.textColor = .tertiaryLabel
      items.append(v)
    } else if showDone {
      let (v, b) = item("Done", done ? HomeActions.green : HomeActions.grey, sym: "checkmark", { [weak self] in self?.onDone?() })
      doneBtn = b; items.append(v)
    }
    if showDue {
      let inner = UIView()
      let top = UILabel(), bot = UILabel()
      top.textColor = .white; bot.textColor = .white; top.textAlignment = .center; bot.textAlignment = .center
      if let d = due, d.count >= 10, let day = Int(d.dropFirst(8).prefix(2)), let mon = Int(d.dropFirst(5).prefix(2)), (1...12).contains(mon) {
        top.text = "\(day)"; top.font = .systemFont(ofSize: 21, weight: .bold)
        bot.text = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][mon - 1]; bot.font = .systemFont(ofSize: 10, weight: .semibold)
        top.frame = CGRect(x: 0, y: 8, width: 52, height: 24); bot.frame = CGRect(x: 0, y: 31, width: 52, height: 12)
        inner.addSubview(top)
      } else {
        let cal = UIImageView(image: UIImage(systemName: "calendar", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
        cal.tintColor = .white; cal.contentMode = .center; cal.frame = CGRect(x: 0, y: 9, width: 52, height: 22)
        bot.text = "SET"; bot.font = .systemFont(ofSize: 10, weight: .semibold); bot.frame = CGRect(x: 0, y: 31, width: 52, height: 12)
        inner.addSubview(cal)
      }
      inner.addSubview(bot)
      items.append(item("Due", HomeActions.purple, inner: inner, { [weak self] in self?.onDue?() }).0)
    }
    items.forEach { addSubview($0) }
    progress = 0
  }
  var count: Int { items.count }
  // (Done tapped: the circle turns green — or grey again, reopened — with a little pop)
  func markDone(_ on: Bool) {
    guard let b = doneBtn else { return }
    UIView.animate(withDuration: 0.12, animations: { b.transform = CGAffineTransform(scaleX: 1.12, y: 1.12); b.backgroundColor = on ? HomeActions.green : HomeActions.grey }) { _ in
      UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) { b.transform = .identity }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    // (16 in from the side they're on, 12 between)
    if leading { var x: CGFloat = 16; for v in items { v.center = CGPoint(x: x + 26, y: bounds.height / 2); x += 52 + 12 } }
    else { var x = bounds.width - 16; for v in items.reversed() { v.center = CGPoint(x: x - 26, y: bounds.height / 2); x -= 52 + 12 } }
  }
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
  func setLook(light: Bool, tint: UIColor) {
    icon.tintColor = tint
    overrideUserInterfaceStyle = light ? .light : .dark
    if #available(iOS 26.0, *) { return }
    fx.effect = UIBlurEffect(style: light ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark)
    fx.layer.borderWidth = 1; fx.layer.borderColor = UIColor.white.withAlphaComponent(light ? 0.6 : 0.18).cgColor
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
final class HomeClientRow: UIControl {
  private let sq = UILabel(), name = UILabel(), meta = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 20; layer.borderWidth = 1
    sq.layer.cornerRadius = 11; sq.clipsToBounds = true; sq.textAlignment = .center; sq.font = .systemFont(ofSize: 14, weight: .heavy); sq.textColor = .white
    name.font = .systemFont(ofSize: 15.5, weight: .semibold); meta.font = .systemFont(ofSize: 12.5)
    [sq, name, meta].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  // (pressed: the shared PressShrink, as every card — added where it's made)
  func set(_ c: [String: Any], look L: HomeLook) {
    backgroundColor = L.card; layer.borderColor = L.cardLine.cgColor
    sq.text = c["ini"] as? String; sq.backgroundColor = NativeSheetVC.color(c["rgb"]) ?? .systemIndigo
    name.text = c["name"] as? String; name.textColor = L.title
    if let mk = c["marks"] as? [String], !mk.isEmpty { name.attributedText = HomeCard.marked(name.text ?? "", mk, base: [.font: name.font!, .foregroundColor: L.title], mark: [.backgroundColor: UIColor.systemBlue.withAlphaComponent(L.light ? 0.16 : 0.3)]) }
    let n = c["open"] as? Int ?? 0
    meta.text = "Client · \(n) open task\(n == 1 ? "" : "s")"; meta.textColor = L.meta
    accessibilityLabel = name.text
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    sq.frame = CGRect(x: 15, y: (bounds.height - 40) / 2, width: 40, height: 40)
    name.frame = CGRect(x: 67, y: bounds.height / 2 - 20, width: bounds.width - 82, height: 21)
    meta.frame = CGRect(x: 67, y: bounds.height / 2 + 3, width: bounds.width - 82, height: 17)
  }
}

// a view that only takes touches on what's in it (the bar's row: the list under its empty parts still scrolls)
final class HomePassThrough: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { let v = super.hitTest(point, with: event); return v === self ? nil : v }
}

// ---------- the Inbox (28+): a notification as Mail's message row ----------
// blue dot (unread) · picture · who did what (bold) and when · the task · one line of what — swiped right: the row goes
// grey and a round blue envelope (Read / Unread) shows on its left (Haris, 2026-11-01)
final class InboxRow: UIControl, UIGestureRecognizerDelegate {
  var onTap: (() -> Void)?, onToggle: (() -> Void)?, onOpen: ((InboxRow) -> Void)?
  var id = ""
  private(set) var read = false
  var last = false { didSet { sep.isHidden = last } }   // (the list's last row: no separator under it — Haris, 2026-11-01)
  static let H: CGFloat = 82.8   // (Mail's)
  private let body = UIView(), dot = UIView(), av = UIImageView(), head = UILabel(), when = UILabel(), chev = UIImageView(), titleL = UILabel(), descL = UILabel(), sep = UIView()
  private let act = UIView(), actCircle = UIView(), actIcon = UIImageView(), actLabel = UILabel()
  // (the button grows from / shrinks to its own middle, as on the task cards; the grey row rounds its corners as it slides,
  //  as Mail's — Haris, 2026-11-01)
  private var shift: CGFloat = 0 { didSet {
    body.transform = CGAffineTransform(translationX: shift, y: 0)
    let k = min(1, shift / 86)
    act.alpha = k; act.transform = CGAffineTransform(scaleX: 0.6 + 0.4 * k, y: 0.6 + 0.4 * k)
    body.backgroundColor = shift > 0.5 ? UIColor.systemGray5 : .clear
    body.layer.cornerRadius = 18 * k
  } }
  var isOpen: Bool { shift > 1 }
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    act.alpha = 0
    actCircle.backgroundColor = .systemBlue; actCircle.layer.cornerRadius = 27
    actIcon.tintColor = .white; actIcon.contentMode = .center
    actLabel.font = .systemFont(ofSize: 12, weight: .medium); actLabel.textColor = .secondaryLabel; actLabel.textAlignment = .center
    actCircle.addSubview(actIcon); act.addSubview(actCircle); act.addSubview(actLabel); addSubview(act)
    act.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
    dot.backgroundColor = .systemBlue; dot.layer.cornerRadius = 5
    av.clipsToBounds = true; av.layer.cornerRadius = 20
    // (Mail's sizes, from the height of the capitals in Haris's screenshots side by side, 2026-11-01: ours at 17 / 15 / 15
    //  read bigger — Mail's are ~16.5 / 14 / 14)
    head.font = .systemFont(ofSize: 16.5, weight: .semibold); head.textColor = .label
    when.font = .systemFont(ofSize: 14); when.textColor = .secondaryLabel; when.textAlignment = .right
    chev.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)); chev.tintColor = .tertiaryLabel; chev.contentMode = .bottom
    titleL.font = .systemFont(ofSize: 14); titleL.textColor = .label
    descL.font = .systemFont(ofSize: 14); descL.textColor = .secondaryLabel
    [head, titleL, descL].forEach { $0.lineBreakMode = .byTruncatingTail; $0.numberOfLines = 1 }
    sep.backgroundColor = .separator
    [dot, av, head, when, chev, titleL, descL, sep].forEach { body.addSubview($0) }
    body.isUserInteractionEnabled = false
    body.layer.cornerCurve = .continuous
    addSubview(body)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:))); pan.delegate = self; addGestureRecognizer(pan)
    addAction(UIAction { [weak self] _ in guard let self = self else { return }; if self.isOpen { self.close() } else { self.onTap?() } }, for: .touchUpInside)
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isHighlighted: Bool { didSet { if !isOpen { body.backgroundColor = isHighlighted ? .systemGray5 : .clear } } }
  func set(_ r: [String: Any], photo: UIImage?) {
    id = r["id"] as? String ?? ""
    read = (r["read"] as? Bool) == true
    dot.isHidden = read
    head.text = r["head"] as? String
    titleL.text = r["title"] as? String
    let d = (r["desc"] as? String ?? "")
    descL.text = d.isEmpty ? " " : d
    when.text = InboxRow.label(r["at"] as? String ?? "")
    av.image = photo
    actIcon.image = UIImage(systemName: read ? "envelope.fill" : "envelope.open.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold))
    actLabel.text = read ? "Unread" : "Read"
    accessibilityLabel = [read ? nil : "Unread", head.text, titleL.text, d, when.text].compactMap { $0 }.joined(separator: ", ")
    setNeedsLayout()
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
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    // (bounds and centre, not frame: the row slid right keeps its shift through a new layout)
    body.bounds = CGRect(origin: .zero, size: bounds.size); body.center = CGPoint(x: W / 2, y: H / 2)
    // Mail's row, measured from Haris's screenshot (2026-11-01): 82.8 tall; the dot 7.8 at 20.7 from the edge and the
    // picture 43.5 at 34.3, both centred 36.3 down; text from 88; the three lines' capitals' tops 15.9 / 37.3 / 56.3
    // down; the time on the first line's baseline with the › 18 from the right; the separator from 86 to 17 short of the edge
    let midY: CGFloat = 36.3
    dot.frame = CGRect(x: 20.7 - 3.9, y: midY - 3.9, width: 7.8, height: 7.8); dot.layer.cornerRadius = 3.9
    av.frame = CGRect(x: 34.3, y: midY - 21.75, width: 43.5, height: 43.5); av.layer.cornerRadius = 21.75
    let x: CGFloat = 88, R: CGFloat = 18
    func top(_ l: UILabel, capTop: CGFloat) -> CGFloat { capTop - (l.font.ascender - l.font.capHeight) }
    let base1 = 15.9 + head.font.capHeight
    chev.frame = CGRect(x: W - R - 9, y: base1 - 11, width: 9, height: 13)
    let ww = ceil(when.sizeThatFits(CGSize(width: 200, height: 22)).width)
    when.frame = CGRect(x: chev.frame.minX - 7 - ww, y: base1 - when.font.ascender, width: ww, height: ceil(when.font.lineHeight))
    head.frame = CGRect(x: x, y: top(head, capTop: 15.9), width: max(0, when.frame.minX - 8 - x), height: ceil(head.font.lineHeight))
    titleL.frame = CGRect(x: x, y: top(titleL, capTop: 37.3), width: W - R - x, height: ceil(titleL.font.lineHeight))
    descL.frame = CGRect(x: x, y: top(descL, capTop: 56.3), width: W - R - x, height: ceil(descL.font.lineHeight))
    let px = 1 / max(1, traitCollection.displayScale)
    sep.frame = CGRect(x: 86, y: H - px, width: W - 86 - 17, height: px)
    // (the button and its name as one, placed by bounds and centre so its shrinking stays on its own middle)
    act.bounds = CGRect(x: 0, y: 0, width: 70, height: 54 + 3 + 15); act.center = CGPoint(x: 16 + 29, y: H / 2)
    actCircle.frame = CGRect(x: 8, y: 0, width: 54, height: 54)
    actIcon.frame = actCircle.bounds
    actLabel.frame = CGRect(x: 0, y: 57, width: 70, height: 15)
  }
  // swiped right only (as Mail's leading swipe); left does nothing
  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    // (only the row's own swipe: iOS asks this for the list's scrolling too — answering no to that stopped the Inbox
    //  from scrolling, Haris 2026-11-01)
    guard g.view === self, let p = g as? UIPanGestureRecognizer else { return true }
    let v = p.velocity(in: self)
    return abs(v.x) > abs(v.y) * 1.2 && (v.x > 0 || isOpen)
  }
  private var start: CGFloat = 0
  @objc private func pan(_ g: UIPanGestureRecognizer) {
    switch g.state {
    case .began: start = shift; onOpen?(self)
    case .changed:
      let x = start + g.translation(in: self).x
      shift = x < 0 ? 0 : x > 86 ? 86 + (x - 86) * 0.25 : x
    default:
      let open = shift > 44 || g.velocity(in: self).x > 400
      if open && shift < 44 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      let to: CGFloat = open && g.velocity(in: self).x > -300 ? 86 : 0
      SwipeSpring.run(from: shift, to: to, velocity: g.velocity(in: self).x) { self.shift = to }
    }
  }
  func close(animated: Bool = true) { if animated { SwipeSpring.run(from: shift, to: 0, velocity: 0) { self.shift = 0 } } else { shift = 0 } }
  func selfOpen() { shift = 86 }
  @objc private func toggle() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    onToggle?()
    close()
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
  var light = true { didSet { if oldValue != light { paint() } } }
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
    let idle = light ? UIColor(red: 234 / 255, green: 234 / 255, blue: 236 / 255, alpha: 1) : UIColor(red: 39 / 255, green: 39 / 255, blue: 41 / 255, alpha: 1)
    let idleInk = light ? UIColor(red: 134 / 255, green: 134 / 255, blue: 137 / 255, alpha: 1) : UIColor(red: 157 / 255, green: 156 / 255, blue: 164 / 255, alpha: 1)
    for (i, p) in pills.enumerated() {
      let on = i == selected
      // (the neutral one in dark: light grey with black, as the others' white on colour)
      let ink: UIColor = on ? (items[i].key == "all" && !light ? .black : .white) : idleInk
      p.bg.backgroundColor = on ? items[i].fill(light) : idle
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
  static func fill(_ light: Bool) -> UIColor { light ? .white : SplashView.hex(0x2b2c31) }
  static func line(_ light: Bool) -> UIColor { light ? UIColor.black.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.1) }
  var onUndo: (() -> Void)?, onPlus: (() -> Void)?, onGone: (() -> Void)?
  var from = CGRect.zero, to = CGRect.zero
  private(set) var out = false
  private let start = UILabel(), tick = UIImageView(), msg = UILabel(), undo = UIButton(type: .system), plusB = UIButton(type: .system)
  private let hasPlus: Bool
  private var timer: Timer?, touching = false, closing = false
  // (iOS 26: iPhone's own glass in a glass container — the button's glass and the toast's are one liquid piece, so the
  //  toast squashes and stretches out of "+ New task" and back into it, as the top buttons do; Haris 2026-11-03)
  private let bed = UIVisualEffectView(effect: nil), body = UIVisualEffectView(effect: nil), nub = UIVisualEffectView(effect: nil)
  private var glassy: Bool { if #available(iOS 26.0, *) { return true }; return false }
  // (as the pill forms into the toast: its glass tinted 60 % — light on light, dark on dark; back to clear glass as it goes:
  //  Haris 2026-11-03)
  private var isLight = true
  // (its corners: always a full pill, as the button — Haris 2026-11-03)
  private func shape(_ toast: Bool) {
    let H = body.bounds.height > 0 ? body.bounds.height : bounds.height
    body.layer.cornerRadius = H / 2
  }
  private func glass(tinted: Bool) -> UIVisualEffect? {
    guard #available(iOS 26.0, *) else { return nil }
    let g = UIGlassEffect(style: .regular)
    if tinted { g.tintColor = isLight ? UIColor.white.withAlphaComponent(0.6) : UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 0.6) }
    return g
  }
  init(light: Bool, title: String?, sym: String?, plus: Bool) {
    hasPlus = plus
    super.init(frame: .zero)
    overrideUserInterfaceStyle = light ? .light : .dark
    isLight = light
    let ink: UIColor = light ? .black : .white   // (its words: black on light, white on dark — Haris 2026-11-03)
    if #available(iOS 26.0, *) {
      // (iPhone's own Liquid Glass, as "+ New task" it stretches out of)
      let ce = UIGlassContainerEffect(); ce.spacing = 24; bed.effect = ce
      body.effect = UIGlassEffect(style: .regular); nub.effect = UIGlassEffect(style: .regular)
      [body, nub].forEach { $0.clipsToBounds = true; $0.layer.cornerCurve = .continuous; bed.contentView.addSubview($0) }
      shape(false)
      bed.isUserInteractionEnabled = false; addSubview(bed)
    } else {
      backgroundColor = ToastCapsule.fill(light)
      layer.borderWidth = 1; layer.borderColor = ToastCapsule.line(light).cgColor
      layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = light ? 0.08 : 0; layer.shadowRadius = 10; layer.shadowOffset = CGSize(width: 0, height: 3)
    }
    // ("+ New task" as the button has it — fading away as it stretches, back as it shrinks)
    let a = NSMutableAttributedString()
    if let s = sym, let img = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))?.withTintColor(ink, renderingMode: .alwaysOriginal) {
      let at = NSTextAttachment(); at.image = img; at.bounds = CGRect(x: 0, y: -2, width: img.size.width, height: img.size.height)
      a.append(NSAttributedString(attachment: at)); a.append(NSAttributedString(string: "  "))
    }
    if let t = title { a.append(NSAttributedString(string: t, attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: ink])) }
    start.attributedText = a; start.textAlignment = .center
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
    let p: CGFloat = hasPlus ? 34 : 0
    plusB.frame = CGRect(x: W - 5 - p, y: (H - 34) / 2, width: p, height: 34); plusB.layer.cornerRadius = 17
    tick.frame = CGRect(x: 10, y: 0, width: 26, height: H)
    let uw = undo.isHidden ? 0 : ceil(undo.sizeThatFits(CGSize(width: 120, height: H)).width) + 12
    let right = (hasPlus ? plusB.frame.minX : W - 8) - 4
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
  func set(_ fx: [[String: Any]], light: Bool) {
    backgroundColor = light ? UIColor(red: 0.91, green: 0.93, blue: 0.98, alpha: 1) : UIColor(red: 0.09, green: 0.14, blue: 0.23, alpha: 1)
    let ink = light ? UIColor(red: 0.17, green: 0.29, blue: 0.54, alpha: 1) : UIColor(red: 0.66, green: 0.76, blue: 1, alpha: 1)
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


// ---------- iPhone's own touch and hold on a task card (AppleNav.swift — Haris 2026-11-07: as in E11 Talk) ----------
extension HomeView: UIContextMenuInteractionDelegate {
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation p: CGPoint) -> UIContextMenuConfiguration? {
    guard let card = i.view as? HomeCard, !(isList && listTab == "done") else { return nil }   // (Done tab: read only)
    let id = card.id
    if let o = openCard { setOpen(o, false) }
    return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
      // (the picker is asked for once the menu has closed — while it's still closing, iPhone shows no other screen)
      let src = { (s: String, t: String, img: String) in UIAction(title: t, image: UIImage(systemName: img)) { _ in HomeView.afterMenu = { self?.send(["ev": "attach", "id": id, "source": s]) } } }
      return UIMenu(title: "Attach Files", children: [src("camera", "Camera", "camera"), src("photos", "Photos", "photo"), src("files", "Files", "doc.badge.arrow.up")])
    }
  }
  private static var afterMenu: (() -> Void)?
  func contextMenuInteraction(_ i: UIContextMenuInteraction, willEndFor c: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
    let run = { let f = HomeView.afterMenu; HomeView.afterMenu = nil; f?() }
    if let a = animator { a.addCompletion(run) } else { DispatchQueue.main.async(execute: run) }
  }
  // (the card itself lifts, with its own rounded corners)
  func contextMenuInteraction(_ i: UIContextMenuInteraction, configuration c: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier id: NSCopying) -> UITargetedPreview? {
    guard let v = i.view else { return nil }
    let pp = UIPreviewParameters()
    pp.visiblePath = UIBezierPath(roundedRect: v.bounds, cornerRadius: v.layer.cornerRadius > 0 ? v.layer.cornerRadius : 18)
    pp.backgroundColor = .clear
    return UITargetedPreview(view: v, parameters: pp)
  }
}

extension HomeView: UICollectionViewDelegate {}

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
    // (a card: its own rounded corners; Apple's swipe buttons kept within them)
    if let c = v as? HomeCard { layer.cornerRadius = c.layer.cornerRadius > 0 ? c.layer.cornerRadius : 18; layer.cornerCurve = .continuous; clipsToBounds = true } else { layer.cornerRadius = 0; clipsToBounds = false }
    setNeedsLayout()
    invalidateIntrinsicContentSize()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let v = hosted, v.superview === contentView else { return }
    let b = contentView.bounds
    if v is HomeCard { v.bounds = CGRect(origin: .zero, size: b.size); v.center = CGPoint(x: b.midX, y: b.midY) }
    else if v.tag == 7 { v.frame = CGRect(x: 4, y: b.height - 15, width: b.width - 8, height: 15) }
    else if v.tag == 8 { v.frame = CGRect(x: 4, y: 14, width: b.width - 8, height: b.height - 28) }
    else { v.frame = b }
  }
  override func preferredLayoutAttributesFitting(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    let r = super.preferredLayoutAttributesFitting(a)
    r.size.height = h
    return r
  }
}
