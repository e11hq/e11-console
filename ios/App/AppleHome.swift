import UIKit

/* Home as its own screen in Apple's tab container (Haris 2026-11-07: "our design as it is, but opening Apple's way instead
   of altering the code"): Home's tab is its own navigation (HomeNav) with Home's own view controller (HomeVC) at its root —
   as Apple builds a tab. Apple's bar is there from the start: the big title (E11 Day) with the date under it, at the top of
   Home's list, going small as it scrolls — all Apple's, nothing of ours moving the list; your Me pill and 🔍 as Apple's bar
   items; Apple's search (the results are Home's own cards); a task pushed and popped by Apple. The list, the cards, the
   boxes and "+ New task" are Home's own, as they were. My Tasks, the Inbox, Clients and Me: next, one by one. */
let APPLE_HOME = APPLE_NAV

// Me on the bar: a pill — your photo (a fixed 30 pt circle the bar can't stretch) and the word "Me", on Apple's own glass
// (Haris 2026-11-07: "the word Me only in the top area, next to the profile picture, in a pill" — with it the bar's
// right side is wide enough that iOS puts the small title on the left by its own rule)
final class MePhotoControl: UIControl {
  private let pic = UIImageView(), word = UILabel()
  static let size = CGSize(width: 74, height: 40)
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.contentMode = .scaleAspectFill; pic.clipsToBounds = true; pic.isUserInteractionEnabled = false
    pic.layer.cornerRadius = 15; pic.layer.cornerCurve = .circular
    word.text = "Me"; word.font = .systemFont(ofSize: 15, weight: .semibold); word.textColor = .label; word.isUserInteractionEnabled = false
    [pic, word].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
    NSLayoutConstraint.activate([pic.widthAnchor.constraint(equalToConstant: 30), pic.heightAnchor.constraint(equalToConstant: 30),
                                 // ("Me", then your photo — Haris 2026-11-07)
                                 word.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13), word.centerYAnchor.constraint(equalTo: centerYAnchor),
                                 pic.leadingAnchor.constraint(equalTo: word.trailingAnchor, constant: 8), pic.centerYAnchor.constraint(equalTo: centerYAnchor)])
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ img: UIImage?) { pic.image = img }
  override var intrinsicContentSize: CGSize { MePhotoControl.size }
}

final class AppleHomeBits {
  static let shared = AppleHomeBits()
  var meButton: MePhotoControl?
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
    // your Me pill and 🔍, as Apple's bar items
    let b = MePhotoControl(frame: CGRect(origin: .zero, size: MePhotoControl.size))
    b.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: MePhotoControl.size.width), b.heightAnchor.constraint(equalToConstant: MePhotoControl.size.height)])
    b.isAccessibilityElement = true; b.accessibilityTraits = .button
    b.accessibilityLabel = "Me"
    b.addAction(UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.homeIfMade?.meTap() }, for: .touchUpInside)
    AppleHomeBits.shared.meButton = b
    let meItem = UIBarButtonItem(customView: b)
    // Apple's search: its own controller, the results in Home's own list (as E11 Talk's lists — no second page)
    let s = UISearchController(searchResultsController: nil)
    s.obscuresBackgroundDuringPresentation = false
    s.searchResultsUpdater = self
    s.delegate = self
    s.searchBar.placeholder = "Search tasks, clients or people"
    s.searchBar.autocorrectionType = .no
    AppleHomeBits.shared.search = s
    navigationItem.searchController = s
    navigationItem.hidesSearchBarWhenScrolling = false
    if #available(iOS 26.0, *) {
      // (iOS 26: Apple's own 🔍 in the bar, opening into its search field there; on its own glass apart from the Me pill —
      //  a fixed space splits the groups, Apple's way)
      navigationItem.preferredSearchBarPlacement = .integratedButton
      navigationItem.searchBarPlacementAllowsToolbarIntegration = false
      navigationItem.rightBarButtonItems = [meItem, .fixedSpace(0), navigationItem.searchBarPlacementBarButtonItem]
    } else {
      if #available(iOS 16.0, *) { navigationItem.preferredSearchBarPlacement = .stacked }
      navigationItem.rightBarButtonItems = [meItem]
    }
    if let h = Main.shared.homeIfMade { adopt(h) }
  }
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    navigationController?.setNavigationBarHidden(false, animated: a)
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
    h.onAppleFind = { q in
      guard let s = AppleHomeBits.shared.search else { return }
      if let q = q { s.isActive = true; s.searchBar.text = q; Main.shared.homeIfMade?.appleSearchText(q) } else { s.isActive = false }
    }
    h.onAppleMe = { img in if let img = img { AppleHomeBits.shared.meButton?.set(img) } }
    h.onAppleResign = { AppleHomeBits.shared.search?.searchBar.resignFirstResponder() }
    h.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    h.appleProbe = { [weak self] in
      guard let self = self, let nb = self.navigationController?.navigationBar, let w = self.view.window else { return [:] }
      let s = AppleHomeBits.shared.search
      let rv = s?.searchResultsController?.view
      return ["barFrameY": nb.frame.minY, "barH": nb.frame.height, "barMaxYWin": nb.convert(nb.bounds, to: w).maxY,
              "searchActive": s?.isActive ?? false,
              "fieldMaxYWin": s.map { $0.searchBar.convert($0.searchBar.bounds, to: w).maxY } ?? -1,
              "resultsVCSafeTop": rv?.safeAreaInsets.top ?? -1, "resultsVCY": rv.map { $0.convert($0.bounds, to: w).minY } ?? -1,
              "homeVCSafeTop": self.view.safeAreaInsets.top]
    }
    h.useAppleTop()
    setContentScrollView(h.appleScroll, for: .top)
  }
  func setTitle(_ t: String, _ d: String) {
    guard !t.isEmpty else { return }
    if navigationItem.title != t { navigationItem.title = t; UserDefaults.standard.set(t, forKey: "e11_home_title") }
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
  // the app's top layer: the window — over every tab (the startup screen, a card over the tab bar, View as…)
  var stage: UIView { AppleTabs.shared?.view.window ?? view.window ?? view }
  // (the startup screen up to the window, before Home's own screen comes up under it)
  func liftSplash() {
    guard let s = splash, let w = AppleTabs.shared?.view.window ?? view.window, s.superview !== w else { return }
    s.removeFromSuperview(); s.frame = w.bounds; s.autoresizingMask = [.flexibleWidth, .flexibleHeight]; w.addSubview(s)
  }
}
