import UIKit

/* Me and its pages in Apple's navigation (Haris 2026-11-08: "start the me page … me page and its inner pages"):
   · Me is its tab's first screen, as Home: its own Apple navigation in Apple's tab bar, Apple's big title "Me" with its
     line; no bar buttons and no search (Haris: "Nothing", "No search");
   · its pages — My profile, Appearance, About, Shortcuts, Team members and a member, Trash, Content plans and a plan,
     Client Assets — are pushed on it, as the task page: Apple's push and swipe back, Apple's bar (‹ · the name), Apple's
     firm frost with its line, the tab bar staying (as the Clients tab's pages);
   · the rows are iPhone Settings' own: Apple's grouped list, Apple's cells set by Apple's configurations, Apple's
     headers and footers, Apple's ›, value text and switches, Apple's highlight (HomeView.applyMeList). Ours, shown by
     Apple's cells: the coloured icons and the pictures; and the few blocks of our own design (Appearance's phones,
     About's cards, a member's header, a plan's posts) in a cell of Apple's list.
   MeCtl keeps the pages' contents and actions, as before; only where they live and who draws them changed. */
let APPLE_ME = APPLE_NAV
// A role's own tab in its own Apple navigation, as Home (MeTabVC): Social's Plans (Haris 2026-11-10 18:13, the mock-up
// "Content plans — fully Apple"), an Office Admin's Team (19:58, the mock-up "Team members — fully Apple"), the CD's Reviews
// (21:20, the mock-up "Review Requests — fully Apple")
let APPLE_ROLE_TABS: [String] = APPLE_NAV ? ["plans", "team", "reviews"] : []

extension Main {
  // (Me in its own Apple navigation — for everyone with a Me tab)
  var meApple: Bool { APPLE_ME && tabKeys.contains("me") }
  // (a role's tab its own Apple screen — Social's Plans, an Office Admin's Team)
  func roleApple(_ key: String) -> Bool { APPLE_ROLE_TABS.contains(key) && tabKeys.contains(key) }
  // Me's navigation has settled (a push, a pop, the tab tapped again popping everything): the pages no longer in it are
  // gone for the app too — Me's, Client Assets', the Clients list opened from Me
  func meNavShown(_ n: UINavigationController) {
    guard (meApple && n === AppleTabs.shared?.meNav) || (AppleTabs.shared?.roleNavs.values.contains { $0 === n } == true) else { return }
    let vcs = n.viewControllers
    meCtl.reconcile(vcs)
    if assetsCtl.appleNav === n { assetsCtl.reconcile(vcs) }   // (Client Assets opened over Me)
    if ClientVC.pushed, clientsNavNow === n, !vcs.contains(where: { $0 is ClientVC }) { clientPageGone() }
  }
}

// Me: its tab's first screen
final class MeVC: UIViewController, TabRoot {
  static weak var shared: MeVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); MeVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = HomeLook(Main.shared.lookBoth).bg; view = v }
  private(set) weak var h: HomeView?
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = "Settings"   // (the page says Settings — Haris 2026-11-08; the tab stays "Me")
    BigLine.prime(self, "me")
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let h = h, h.superview === view { h.tabTop = Main.shared.homeTabTop }
  }
  // (its screen in it before it first shows — never an empty tab: Haris 2026-11-08)
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    Main.shared.drawBeforeShow("me")   // (its rows from the phone's copy before it first shows)
    if APPLE_ROLE_TABS.contains(where: Main.shared.tabKeys.contains) { Main.shared.meCtl.willShowTab("me") } else if h == nil { Main.shared.meCtl.prepareRoot() }   // (a role's own tab given back — Social's Plans, an Office Admin's Team)
  }
  func adopt(_ v: HomeView) {
    loadViewIfNeeded()
    if let old = h, old !== v, old.superview === view { old.removeFromSuperview() }
    h = v
    if v.superview !== view {
      v.removeFromSuperview()
      v.frame = view.bounds; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(v, at: 0)
    }
    v.isHidden = false; v.transform = .identity
    view.backgroundColor = v.backgroundColor ?? view.backgroundColor
    v.onAppleTitle = { [weak self] t, d in self?.setLine(t, d) }
    v.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    v.useAppleTop()
    setContentScrollView(v.appleScroll, for: .top)
  }
  private var shownLine: String?
  private func setLine(_ t: String, _ d: String) {
    if !t.isEmpty, navigationItem.title != t { navigationItem.title = t }
    guard d != shownLine else { return }
    shownLine = d
    BigLine.set(self, d, "me")
  }
}

// A role's own tab: its first screen, as Home — Apple's big title and its line, Apple's search (with Apple's scope bar for
// Team's Active · Past), your photo as Apple's bar button (Team's "+ Add member" as Home's + New task — Haris 20:07); MeCtl's page in Apple's list
// (HomeView.applyMeList); a page pushed on it (MePageVC), the tab bar going once it has arrived, as a task.
//  · Social's Plans (Haris 2026-11-10, the mock-up "Content plans — fully Apple"): "Content plans", clients and posts
//  · an Office Admin's Team (Haris 2026-11-10, the mock-up "Team members — fully Apple"): "Team members", people
//  · the CD's Reviews (Haris 2026-11-10, the mock-up "Review Requests — fully Apple"): "Reviews", requests and skeletons
final class MeTabVC: UIViewController, TabRoot, UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {
  static var byKey: [String: MeTabVC] = [:]
  let key: String
  init(_ key: String) { self.key = key; super.init(nibName: nil, bundle: nil); MeTabVC.byKey[key] = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = HomeLook(Main.shared.lookBoth).bg; view = v }
  private(set) weak var h: HomeView?
  private var search: UISearchController?
  private var meItem: UIBarButtonItem?
  private var mePhoto: UIImage?
  var onSearch: ((String) -> Void)?, onScope: ((Int) -> Void)?
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = ["team": "Team members", "reviews": "Reviews"][key] ?? "Content plans"
    let me = UIBarButtonItem(image: BarImage.me(nil, traitCollection), primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.selectTab("me") })
    me.accessibilityLabel = "Me"
    BarImage.bare(me)
    meItem = me
    navigationItem.rightBarButtonItems = [me]
    if #available(iOS 17.0, *) { registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: MeTabVC, _: UITraitCollection) in vc.paintMe() } }
    let s = UISearchController(searchResultsController: nil)
    s.obscuresBackgroundDuringPresentation = false
    s.searchResultsUpdater = self; s.delegate = self
    s.searchBar.placeholder = ["team": "Search people", "reviews": "Search tasks, clients or people"][key] ?? "Search clients and posts"
    s.searchBar.autocorrectionType = .no
    search = s
    navigationItem.hidesSearchBarWhenScrolling = false
    navigationItem.searchController = s
    BigLine.prime(self, key)
  }
  func paintMe() { meItem?.image = BarImage.me(mePhoto ?? MePhoto.shared.image, traitCollection) }
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    paintMe()
    Main.shared.meCtl.willShowTab(key)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let h = h, h.superview === view { h.tabTop = Main.shared.homeTabTop }
  }
  func adopt(_ v: HomeView) {
    loadViewIfNeeded()
    if let old = h, old !== v, old.superview === view { old.removeFromSuperview() }
    h = v
    if v.superview !== view {
      v.removeFromSuperview()
      v.frame = view.bounds; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(v, at: 0)
    }
    v.isHidden = false; v.transform = .identity
    view.backgroundColor = v.backgroundColor ?? view.backgroundColor
    v.onAppleTitle = { [weak self] _, d in self?.setLine(d) }
    v.onAppleResign = { [weak self] in self?.search?.searchBar.resignFirstResponder() }
    v.onAppleFind = { [weak self] q in
      guard let self = self, let s = self.search else { return }
      if let q = q { s.isActive = true; s.searchBar.text = q; self.h?.appleSearchText(q) } else { s.isActive = false }
    }
    v.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    v.useAppleTop()
    setContentScrollView(v.appleScroll, for: .top)
  }
  // (Team's Active · Past: Apple's scope bar under the search, always showing — as My Tasks' All / Done; the page's own
  //  search answers in its list, not Home's results)
  func useScopes(_ scopes: [String], selected: Int) {
    guard let b = search?.searchBar else { return }
    if (b.scopeButtonTitles ?? []) != scopes {
      b.scopeButtonTitles = scopes; b.delegate = self
      if !b.showsScopeBar { b.showsScopeBar = true; if #available(iOS 16.0, *) { search?.scopeBarActivation = .manual } }
    }
    if b.selectedScopeButtonIndex != selected { b.selectedScopeButtonIndex = selected }
  }
  func searchBar(_ b: UISearchBar, selectedScopeButtonIndexDidChange i: Int) { UISelectionFeedbackGenerator().selectionChanged(); onScope?(i) }
  private var shownLine: String?
  private func setLine(_ d: String) {
    guard d != shownLine else { return }
    shownLine = d
    BigLine.set(self, d, key)
  }
  func updateSearchResults(for s: UISearchController) {
    if let f = onSearch { f(s.searchBar.text ?? ""); return }
    h?.appleSearchText(s.searchBar.text ?? "")
  }
  func willPresentSearchController(_ s: UISearchController) { if onSearch == nil { h?.appleSearchBegin() } }
  func didPresentSearchController(_ s: UISearchController) { DispatchQueue.main.async { s.searchBar.becomeFirstResponder() } }
  func willDismissSearchController(_ s: UISearchController) { if onSearch == nil { h?.appleSearchEnd() } }
}

// a page of Me pushed on its tab: as the Clients tab's pages (tab bar staying, Apple's firm frost, Apple's bar)
final class MePageVC: ClientsPushedVC, UISearchResultsUpdating, UISearchBarDelegate {
  var onGone: (() -> Void)?
  // (a page with a search — Team members: Apple's own search bar in Apple's bar, its lists as Apple's scope bar under it)
  private var search: UISearchController?
  var onSearch: ((String) -> Void)?, onScope: ((Int) -> Void)?
  func useSearch(_ placeholder: String, scopes: [String], selected: Int) {
    if search == nil {
      let s = UISearchController(searchResultsController: nil)
      s.obscuresBackgroundDuringPresentation = false
      s.searchResultsUpdater = self
      s.searchBar.autocorrectionType = .no
      s.searchBar.delegate = self
      if !scopes.isEmpty { s.searchBar.scopeButtonTitles = scopes; s.searchBar.showsScopeBar = true; if #available(iOS 16.0, *) { s.scopeBarActivation = .manual } }
      search = s
      navigationItem.hidesSearchBarWhenScrolling = false
      if #available(iOS 16.0, *) { navigationItem.preferredSearchBarPlacement = .stacked }
      navigationItem.searchController = s   // (given once where it goes is told — ClientVC)
    }
    // (each only when it changes — set again on every redraw, Apple's bar laid itself out again)
    guard let b = search?.searchBar else { return }
    if b.placeholder != placeholder { b.placeholder = placeholder }
    if !scopes.isEmpty, (b.scopeButtonTitles ?? []) != scopes { b.scopeButtonTitles = scopes }
    if !scopes.isEmpty, b.selectedScopeButtonIndex != selected { b.selectedScopeButtonIndex = selected }
  }
  func updateSearchResults(for s: UISearchController) { onSearch?(s.searchBar.text ?? "") }
  func searchBar(_ b: UISearchBar, selectedScopeButtonIndexDidChange i: Int) { UISelectionFeedbackGenerator().selectionChanged(); onScope?(i) }
  // (+ Add member: Apple's + in the bar's right corner — the mock-up's C2; none for those who can't add)
  private var plusOn = false
  func usePlus(_ run: (() -> Void)?) {
    guard (run != nil) != plusOn || run != nil else { return }
    if let run = run {
      guard !plusOn else { return }
      plusOn = true
      let p = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); run() })
      p.accessibilityLabel = "Add member"; navigationItem.rightBarButtonItem = p
    } else { plusOn = false; navigationItem.rightBarButtonItem = nil }
  }
  private(set) var appeared = false
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); appeared = true }
  // (a page with its own buttons on Apple's toolbar — a skeleton waiting for you: Send Back · Approve. Made again only when
  //  what they do changes; Apple's toolbar shown with the page and gone with it)
  private var toolsKey = ""
  func setTools(_ key: String, _ make: (() -> [UIBarButtonItem])?) {
    guard key != toolsKey else { return }
    toolsKey = key
    let items = make?() ?? []
    setToolbarItems(items.isEmpty ? nil : items, animated: appeared)
    if navigationController?.topViewController === self { navigationController?.setToolbarHidden(items.isEmpty, animated: appeared) }
  }
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    navigationController?.setToolbarHidden(toolbarItems?.isEmpty ?? true, animated: a)
  }
  override func viewWillDisappear(_ a: Bool) {
    super.viewWillDisappear(a)
    if isMovingFromParent, toolbarItems?.isEmpty == false { navigationController?.setToolbarHidden(true, animated: a) }
  }
  override init(_ h: HomeView) {
    super.init(h)
    // (a page whose name is its big title on the old page — Content plans opened from Me: its name and line in the bar)
    h.onAppleTitle = { [weak self] t, d in
      guard let self = self, !t.isEmpty else { return }
      if self.navigationItem.title != t { self.navigationItem.title = t }   // (only when it changes — Apple's bar not laid out again mid-slide)
      if #available(iOS 26.0, *) { let sub: String? = d.isEmpty ? nil : d; if self.navigationItem.subtitle != sub { self.navigationItem.subtitle = sub } }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    // (Me's pages have no ••• of their own: none in the bar — a skeleton's comes once it knows it has one)
    moreItem = navigationItem.rightBarButtonItem
    if menuItems().isEmpty { navigationItem.rightBarButtonItem = nil }
  }
  private var moreItem: UIBarButtonItem?
  func menuChanged() {
    guard isViewLoaded else { return }
    let want = menuItems().isEmpty ? nil : moreItem
    if navigationItem.rightBarButtonItem !== want { navigationItem.rightBarButtonItem = want }
  }
  override func viewDidDisappear(_ a: Bool) {
    super.viewDidDisappear(a)
    if isMovingFromParent || navigationController == nil { onGone?(); onGone = nil }
  }
  // (a page without a name of its own in the bar — Content plans: its big title's name instead, never an empty name with
  //  a grey square)
  override func setBar(_ t: String, _ sub: String, _ col: UIColor, _ logo: String?, _ ini: String?, _ showLogo: Bool) {
    if t.isEmpty { return }
    super.setBar(t, sub, col, logo, ini, false)
  }
}

// the Clients list opened from Me (Me › Work › Clients — the CD's, who has no Clients tab): pushed on Me, as Me's pages
final class ClientsFromMeVC: ClientsPushedVC {
  var onGone: (() -> Void)?
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Clients"
    navigationItem.rightBarButtonItem = nil
  }
  override func setBar(_ t: String, _ sub: String, _ col: UIColor, _ logo: String?, _ ini: String?, _ showLogo: Bool) {}   // ("Clients" only)
  override func viewDidDisappear(_ a: Bool) {
    super.viewDidDisappear(a)
    if isMovingFromParent || navigationController == nil { onGone?(); onGone = nil }
  }
}

// The line under a tab's big title, set the way Home sets its date (AppleHome.swift: "the title and the date there before
// Home first shows — Apple sizes its bar for the big title from the start"): there from the first layout — the last one
// shown, kept on the phone — and never taken away, only its words changed; given late (its list's numbers came after the
// page first showed), Apple's bar grew under a list already placed and the big title was cut — every tab but Home, which
// already does this (Haris 2026-11-08: "not the home page but every other page")
enum BigLine {
  static func prime(_ vc: UIViewController, _ key: String) {
    set(vc, UserDefaults.standard.string(forKey: "e11_line_" + key) ?? "", key, save: false)
  }
  static func set(_ vc: UIViewController, _ d: String, _ key: String, save: Bool = true) {
    guard #available(iOS 26.0, *) else { return }
    if save, !d.isEmpty { UserDefaults.standard.set(d, forKey: "e11_line_" + key) }
    let words = d.isEmpty ? " " : d   // (never removed: its room stays, as Apple measured it)
    // (set only when its words change — Haris 2026-11-10: the rule "only what changed changes")
    guard vc.navigationItem.subtitle != words || vc.navigationItem.largeAttributedSubtitle == nil else { return }
    var a = AttributedString(words); a.uiKit.font = .systemFont(ofSize: 15); a.uiKit.foregroundColor = .secondaryLabel
    let put = { vc.navigationItem.subtitle = words; vc.navigationItem.largeAttributedSubtitle = a }
    // (on screen, its words crossfade to the new ones — the standard "words that change on a showing screen", Haris
    //  2026-11-05 / 2026-11-10 — with Apple's own crossfade on Apple's bar; not while the page is coming or going (Apple's
    //  slide carries the bar), nor while typing in its search)
    let searchOn = vc.navigationItem.searchController?.isActive == true
    if let bar = vc.navigationController?.navigationBar, vc.viewIfLoaded?.window != nil, vc.transitionCoordinator == nil,
       vc.navigationController?.topViewController === vc, !searchOn, vc.navigationItem.subtitle != nil {
      UIView.transition(with: bar, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState], animations: put)
    } else { put() }
    // (the self-test: each line set — which tab, its words, on screen or not, in the middle of a change — Haris 2026-11-09:
    //  the big title gone on the second visit to My Tasks and the Inbox, never on Clients' or Home's)
    if !SELFTEST.isEmpty { sets.append(["key": key, "words": words, "t": CACurrentMediaTime(), "shown": vc.viewIfLoaded?.window != nil, "moving": vc.transitionCoordinator != nil]); if sets.count > 60 { sets.removeFirst() } }
  }
  static var sets: [[String: Any]] = []
}


// (the self-test, Haris 2026-11-10: the search box's glass coming in late as a client's page slides in — every touch of
//  ours on Apple's top bar during the slide, with its time, beside the frames; off outside the measurement)
enum BarLog {
  static var on = false, t0: CFTimeInterval = 0
  static var notes: [String] = []
  static func start() { notes = []; t0 = CACurrentMediaTime(); on = true }
  static func note(_ w: String) { guard on else { return }; notes.append("\(Int((CACurrentMediaTime() - t0) * 1000))ms \(w)") }
}
