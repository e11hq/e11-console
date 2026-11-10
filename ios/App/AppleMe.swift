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

extension Main {
  // (Me in its own Apple navigation — for everyone with a Me tab)
  var meApple: Bool { APPLE_ME && tabKeys.contains("me") }
  // Me's navigation has settled (a push, a pop, the tab tapped again popping everything): the pages no longer in it are
  // gone for the app too — Me's, Client Assets', the Clients list opened from Me
  func meNavShown(_ n: UINavigationController) {
    guard meApple, n === AppleTabs.shared?.meNav else { return }
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
    if h == nil { Main.shared.meCtl.prepareRoot() }
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
      navigationItem.searchController = s
      navigationItem.hidesSearchBarWhenScrolling = false
      if #available(iOS 16.0, *) { navigationItem.preferredSearchBarPlacement = .stacked }
    }
    // (each only when it changes — set again on every redraw, Apple's bar laid itself out again)
    guard let b = search?.searchBar else { return }
    if b.placeholder != placeholder { b.placeholder = placeholder }
    if !scopes.isEmpty, (b.scopeButtonTitles ?? []) != scopes { b.scopeButtonTitles = scopes }
    if !scopes.isEmpty, b.selectedScopeButtonIndex != selected { b.selectedScopeButtonIndex = selected }
  }
  func updateSearchResults(for s: UISearchController) { onSearch?(s.searchBar.text ?? "") }
  func searchBar(_ b: UISearchBar, selectedScopeButtonIndexDidChange i: Int) { UISelectionFeedbackGenerator().selectionChanged(); onScope?(i) }
  private(set) var appeared = false
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); appeared = true }
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
    // (Me's pages have no ••• of their own: none in the bar)
    if menuItems().isEmpty { navigationItem.rightBarButtonItem = nil }
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
