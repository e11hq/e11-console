import UIKit

/* Home as its own screen in Apple's tab container (Haris 2026-11-07: "our design as it is, but opening Apple's way instead
   of altering the code"): Home's tab is its own navigation (HomeNav) with Home's own view controller (HomeVC) at its root —
   as Apple builds a tab. Apple's bar is there from the start: the big title (E11 Day) with the date under it, at the top of
   Home's list, going small as it scrolls — all Apple's, nothing of ours moving the list; your Me pill as Apple's bar
   item; Apple's search box under the big title, as E11 Talk's (the results are rows of Home's own list); a task pushed and popped by Apple. The list, the cards, the
   boxes and "+ New task" are Home's own, as they were. My Tasks, the Inbox, Clients and Me: next, one by one. */
let APPLE_HOME = APPLE_NAV

// Me on the bar: a pill — your photo (a fixed 30 pt circle the bar can't stretch) and the word "Me", on Apple's own glass
// (Haris 2026-11-07: "the word Me only in the top area, next to the profile picture, in a pill" — with it the bar's
// right side is wide enough that iOS puts the small title on the left by its own rule)
// your Me button in Home's bar: Apple's own bar button (its glass, its size, its press), showing "Me" and your photo
// as one picture — Apple fits its own buttons beside the big title; our own pill view in the bar was the test's
// suspect for the big title jumping into the bar as a task slides in (Haris 2026-11-07)
enum MeBarImage {
  static func make(_ photo: UIImage?, _ t: UITraitCollection) -> UIImage {
    let word = NSAttributedString(string: "Me", attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.label.resolvedColor(with: t)])
    let ws = word.size(), d: CGFloat = 30, gap: CGFloat = 8
    let size = CGSize(width: ceil(ws.width) + gap + d, height: d)
    let f = UIGraphicsImageRendererFormat(for: t)
    return UIGraphicsImageRenderer(size: size, format: f).image { _ in
      word.draw(at: CGPoint(x: 0, y: (d - ws.height) / 2))
      let r = CGRect(x: size.width - d, y: 0, width: d, height: d)
      UIBezierPath(ovalIn: r).addClip()
      if let p = photo { p.draw(in: r) } else { UIColor.secondarySystemFill.resolvedColor(with: t).setFill(); UIRectFill(r) }
    }.withRenderingMode(.alwaysOriginal)
  }
}

final class AppleHomeBits {
  static let shared = AppleHomeBits()
  var meItem: UIBarButtonItem?
  var mePhoto: UIImage?
  var search: UISearchController?
}

// Home's screen: Home's own view (HomeView, as it was) filling it, under Apple's bar
final class HomeVC: UIViewController, UISearchResultsUpdating, UISearchControllerDelegate {
  static weak var shared: HomeVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); HomeVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = .systemGroupedBackground; view = v }
  override func viewDidLoad() {
    super.viewDidLoad()
    // (the big title: Apple's own default — its tab asks for big titles; never ".always", which kept the big title's room
    //  in the bar while search was open: the gap above the results, Haris 2026-11-07)
    navigationItem.backButtonDisplayMode = .minimal   // (a task over it: just ‹)
    // (the title and the date there before Home first shows — Apple sizes its bar for the big title from the start; with
    //  no title yet it came up small and stayed small)
    let d = UserDefaults.standard
    let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
    setTitle(d.string(forKey: "e11_home_title") ?? "E11 Day", f.string(from: Date()))
    // your Me button, as Apple's own bar button
    let meItem = UIBarButtonItem(image: MeBarImage.make(nil, traitCollection), primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.homeIfMade?.meTap() })
    meItem.accessibilityLabel = "Me"
    AppleHomeBits.shared.meItem = meItem
    // (its words drawn in the phone's look: drawn again when light / dark changes)
    if #available(iOS 17.0, *) { registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: HomeVC, _: UITraitCollection) in vc.paintMe() } }
    // Apple's search: its own controller, the results in Home's own list (as E11 Talk's lists — no second page)
    let s = UISearchController(searchResultsController: nil)
    s.obscuresBackgroundDuringPresentation = false
    s.searchResultsUpdater = self
    s.delegate = self
    s.searchBar.placeholder = "Search tasks, clients or people"
    s.searchBar.autocorrectionType = .no
    AppleHomeBits.shared.search = s
    // (Apple's search is in the bar only while it's open: at rest the box is on Home's own page, on Apple's glass —
    //  HomeView.appleSearchBox — so it slides in with Home, glass and all, as "+ New task": Haris 2026-11-07)
    navigationItem.hidesSearchBarWhenScrolling = false
    // (Apple's search box under the big title, as E11 Talk's lists — nothing set for where it goes: tapped, Apple folds the
    //  big title away and the results start right under the box. Apple's 🔍 bar button kept the big title's room above
    //  the results — measured on Apple's own screens, Haris 2026-11-07)
    // E11 Talk's bubble, an Apple bar button on its own glass beside the Me pill (Haris 2026-11-07): it will open E11 Talk,
    // or its App Store page when it isn't installed — the link comes later, with Talk's release; for now it does nothing
    // (in its own blue gradient, as E11 Talk's icon — the same in light and dark: Apple's original-colour image, Haris
    //  2026-11-07)
    let talk = UIBarButtonItem(image: UIImage(named: "TalkBubble")?.withRenderingMode(.alwaysOriginal), primaryAction: UIAction { _ in })
    talk.accessibilityLabel = "E11 Talk"
    navigationItem.rightBarButtonItems = [meItem, .fixedSpace(0), talk]
    if let h = Main.shared.homeIfMade { adopt(h) }
  }
  // (Home's own screen lays Home out: where the tab bar starts, for "+ New task" and the list's end — it was only ever set
  //  by the app's old shared screen laying itself out, which doesn't happen while Home's tab is on: after the startup
  //  screen "+ New task" sat on the tab bar until a task page came and went, Haris 2026-11-07)
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let m = Main.shared
    if let h = m.homeIfMade, h.superview === view { h.tabTop = m.homeTabTop }
  }
  // Home's own view, filling this screen (its list under Apple's bar, as Apple wants it)
  func adopt(_ h: HomeView) {
    loadViewIfNeeded()
    if h.superview !== view {
      h.removeFromSuperview()
      h.frame = view.bounds; h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(h, at: 0)
    }
    view.backgroundColor = h.backgroundColor ?? view.backgroundColor
    h.onAppleTitle = { [weak self] t, d in self?.setTitle(t, d) }
    h.onAppleFind = { [weak self] q in
      guard let s = AppleHomeBits.shared.search else { return }
      if let q = q { self?.openSearch(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { s.searchBar.text = q; Main.shared.homeIfMade?.appleSearchText(q) } } else { s.isActive = false }
    }
    h.onAppleSearchTap = { [weak self] in self?.openSearch() }
    h.onAppleMe = { [weak self] img in if let img = img { AppleHomeBits.shared.mePhoto = img; self?.paintMe() } }
    h.onAppleResign = { AppleHomeBits.shared.search?.searchBar.resignFirstResponder() }
    h.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    h.useAppleTop()
    setContentScrollView(h.appleScroll, for: .top)
  }
  func paintMe() { AppleHomeBits.shared.meItem?.image = MeBarImage.make(AppleHomeBits.shared.mePhoto, traitCollection) }
  private var shownDate: String?
  func setTitle(_ t: String, _ d: String) {
    guard !t.isEmpty else { return }
    if navigationItem.title != t { navigationItem.title = t; UserDefaults.standard.set(t, forKey: "e11_home_title") }
    // (only when it changed: set again on every Home redraw — after a task closes, every live update — Apple's bar laid
    //  itself out again and its search box's glass formed anew: Haris 2026-11-07)
    guard d != shownDate else { return }
    shownDate = d
    if #available(iOS 26.0, *) {
      navigationItem.subtitle = d.isEmpty ? nil : d
      // (under the big title: the date as our other pages have it — 15 regular, the secondary grey — Haris 2026-11-07)
      if d.isEmpty { navigationItem.largeAttributedSubtitle = nil } else {
        var a = AttributedString(d); a.uiKit.font = .systemFont(ofSize: 15); a.uiKit.foregroundColor = .secondaryLabel
        navigationItem.largeAttributedSubtitle = a
      }
    }
  }
  // ---------- Apple's search: it opened, its words changed, it closed ----------
  func updateSearchResults(for s: UISearchController) { Main.shared.homeIfMade?.appleSearchText(s.searchBar.text ?? "") }
  func willPresentSearchController(_ s: UISearchController) {
    Main.shared.homeIfMade?.appleSearchBegin()
  }
  func didPresentSearchController(_ s: UISearchController) { DispatchQueue.main.async { s.searchBar.becomeFirstResponder() } }
  func willDismissSearchController(_ s: UISearchController) { Main.shared.homeIfMade?.appleSearchEnd() }
  // (closed: out of the bar again — the box on the page is the way in)
  func didDismissSearchController(_ s: UISearchController) { if navigationItem.searchController === s { navigationItem.searchController = nil } }
  // the box on the page tapped: Apple's search, in the bar, open and ready to type
  func openSearch() {
    guard let s = AppleHomeBits.shared.search, !s.isActive else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    navigationItem.searchController = s
    DispatchQueue.main.async { s.isActive = true }
  }
}

extension Main {
  // the app's own navigation has no bar of its own any more: Home's bar is Home's screen's (HomeVC); a page pushed over
  // the app's other screens (a task) shows Apple's bar, and coming back it goes again
  func appleHomeBar(animated: Bool, splashGoing: Bool = false) {
    guard APPLE_HOME, let nav = navigationController, nav.topViewController === self, !nav.isNavigationBarHidden else { return }
    nav.setNavigationBarHidden(true, animated: animated)
  }
  // the navigation on show: Home's own when Home's tab is on, else the app's
  var stageNav: UINavigationController? { (AppleTabs.shared?.homeShown == true ? AppleTabs.shared?.homeNav : nil) ?? navigationController }
  // every navigation the app has (Home's and the app's), for what's open in any of them
  var allNavs: [UINavigationController] { [AppleTabs.shared?.homeNav, navigationController].compactMap { $0 } }
  // (a card over the tab bar, View as…: the window — over every tab)
  var stage: UIView { AppleTabs.shared?.view.window ?? view.window ?? view }
}
