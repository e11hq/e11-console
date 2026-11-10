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
// Home's bar buttons: Apple's own bar buttons (their glass, size and press), each showing one picture of ours —
// your photo (Haris 2026-11-08: no "Me" word), and E11 Talk's bubble with "Talk" beside it (drawn again for light / dark)
enum BarImage {
  // (Haris 2026-11-08: "less space around my profile picture" — the photo is the button itself, without Apple's glass
  //  around it (bare), as Apple shows your account photo in its own apps: the whole circle the glass took, 44 pt)
  static func bare(_ b: UIBarButtonItem) { if #available(iOS 26.0, *) { b.hidesSharedBackground = true } }
  static func me(_ photo: UIImage?, _ t: UITraitCollection) -> UIImage {
    let d: CGFloat = 44
    return UIGraphicsImageRenderer(size: CGSize(width: d, height: d), format: UIGraphicsImageRendererFormat(for: t)).image { _ in
      let r = CGRect(x: 0, y: 0, width: d, height: d)
      UIBezierPath(ovalIn: r).addClip()
      if let p = photo { p.draw(in: r) } else { UIColor.secondarySystemFill.resolvedColor(with: t).setFill(); UIRectFill(r) }
    }.withRenderingMode(.alwaysOriginal)
  }
  // (Haris 2026-11-08: the bubble and "Talk" in the bar's own ink — white in dark, black in light (Apple tints the
  //  picture, no blue); the same room on the left and right of the two together as above and below them in Apple's button
  //  — Apple keeps 6 pt at each side of a bar button's picture and ~12 pt above and below, so 6 pt more each side here)
  static func talk(_ t: UITraitCollection) -> UIImage? {
    guard let src = UIImage(named: "TalkBubble"), let cg = src.cgImage else { return nil }
    // (the bubble without the empty margin its picture has around it)
    let sc = src.scale, crop = CGRect(x: 6, y: 9, width: 60, height: 55).applying(CGAffineTransform(scaleX: sc / 3, y: sc / 3))
    guard let cut = cg.cropping(to: crop) else { return nil }
    let bubble = UIImage(cgImage: cut, scale: sc, orientation: .up)
    let word = NSAttributedString(string: "Talk", attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.black])
    let ws = word.size(), b = bubble.size, gap: CGFloat = 6, side: CGFloat = 6
    let h = max(b.height, ceil(ws.height))
    let size = CGSize(width: side + b.width + gap + ceil(ws.width) + side, height: h)
    return UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: t)).image { _ in
      bubble.draw(in: CGRect(x: side, y: (h - b.height) / 2, width: b.width, height: b.height))
      word.draw(at: CGPoint(x: side + b.width + gap, y: (h - ws.height) / 2))
    }.withRenderingMode(.alwaysTemplate)
  }
}

final class AppleHomeBits {
  static let shared = AppleHomeBits()
  var meItem: UIBarButtonItem?
  var talkItem: UIBarButtonItem?
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
    let meItem = UIBarButtonItem(image: BarImage.me(nil, traitCollection), primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.homeIfMade?.meTap() })
    meItem.accessibilityLabel = "Me"
    BarImage.bare(meItem)
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
    // (Apple's own search bar in Apple's bar, under the big title, always — as E11 Talk's lists; it stays stuck under the
    //  bar as Home scrolls. Haris 2026-11-08: "apple's search looks more elegant" — our box on the page taken out; it
    //  only flew with the bar while the old "hide the bottom bar when pushed" snapped the bar small, now gone)
    navigationItem.searchController = s
    navigationItem.hidesSearchBarWhenScrolling = false
    // (Apple's search box under the big title, as E11 Talk's lists — nothing set for where it goes: tapped, Apple folds the
    //  big title away and the results start right under the box. Apple's 🔍 bar button kept the big title's room above
    //  the results — measured on Apple's own screens, Haris 2026-11-07)
    // E11 Talk's button, an Apple bar button beside your photo (Haris 2026-11-07): it will open E11 Talk, or its App
    // Store page when it isn't installed — the link comes later, with Talk's release; for now it does nothing. The bubble
    // and "Talk" in the bar's own ink, white in dark and black in light (Haris 2026-11-08)
    let talk = UIBarButtonItem(image: BarImage.talk(traitCollection), primaryAction: UIAction { _ in })
    talk.tintColor = .label
    AppleHomeBits.shared.talkItem = talk
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
    h.onAppleFind = { q in
      guard let s = AppleHomeBits.shared.search else { return }
      if let q = q { s.isActive = true; s.searchBar.text = q; Main.shared.homeIfMade?.appleSearchText(q) } else { s.isActive = false }
    }
    h.onAppleMe = { [weak self] img in if let img = img { AppleHomeBits.shared.mePhoto = img; self?.paintMe() } }
    h.onAppleResign = { AppleHomeBits.shared.search?.searchBar.resignFirstResponder() }
    h.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    h.useAppleTop()
    setContentScrollView(h.appleScroll, for: .top)
  }
  func paintMe() {
    AppleHomeBits.shared.meItem?.image = BarImage.me(AppleHomeBits.shared.mePhoto, traitCollection)
    AppleHomeBits.shared.talkItem?.image = BarImage.talk(traitCollection)
  }
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
}

extension Main {
  // the app's own navigation has no bar of its own any more: Home's bar is Home's screen's (HomeVC); a page pushed over
  // the app's other screens (a task) shows Apple's bar, and coming back it goes again
  func appleHomeBar(animated: Bool, splashGoing: Bool = false) {
    guard APPLE_HOME, let nav = navigationController, nav.topViewController === self, !nav.isNavigationBarHidden else { return }
    nav.setNavigationBarHidden(true, animated: animated)
  }
  // the navigation on show: Home's own when Home's tab is on, else the app's
  var stageNav: UINavigationController? { AppleTabs.shared?.ownNav ?? navigationController }
  // every navigation the app has (Home's and the app's), for what's open in any of them
  var allNavs: [UINavigationController] { [AppleTabs.shared?.homeNav, AppleTabs.shared?.myTasksNav, AppleTabs.shared?.inboxNav, AppleTabs.shared?.clientsNav, AppleTabs.shared?.assetsNav, AppleTabs.shared?.meNav, AppleTabs.shared?.plansNav, navigationController].compactMap { $0 } }
  // (a card over the tab bar, View as…: the window — over every tab)
  var stage: UIView { AppleTabs.shared?.view.window ?? view.window ?? view }
}
