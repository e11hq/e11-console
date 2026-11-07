import UIKit

/* Home in iPhone's own navigation (Haris 2026-11-07: "the design will be ours, the behaviour Apple's"): on Home, Apple's
   bar — the big title (E11 Day) with the date under it, shrinking into the bar as the list scrolls, its frost, 🔍 and your
   photo as Apple's bar buttons, and Apple's search bar (the results are Home's own cards). Opening a task and coming back
   is Apple's title change. The list, the cards, the boxes and "+ New task" are as they were. Only Home: My Tasks, the
   Inbox and Clients keep their own headers until they're done the same way. */
let APPLE_HOME = APPLE_NAV

// your photo on the bar: a fixed 36 pt circle in the middle of whatever room the bar gives it — the bar can't stretch it
// (it came out an oval: Haris 2026-11-07)
final class MePhotoControl: UIControl {
  private let pic = UIImageView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    pic.contentMode = .scaleAspectFill; pic.clipsToBounds = true; pic.isUserInteractionEnabled = false
    pic.layer.cornerRadius = 18; pic.layer.cornerCurve = .circular
    pic.translatesAutoresizingMaskIntoConstraints = false
    addSubview(pic)
    NSLayoutConstraint.activate([pic.widthAnchor.constraint(equalToConstant: 36), pic.heightAnchor.constraint(equalToConstant: 36),
                                 pic.centerXAnchor.constraint(equalTo: centerXAnchor), pic.centerYAnchor.constraint(equalTo: centerYAnchor)])
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ img: UIImage?) { pic.image = img }
  override var intrinsicContentSize: CGSize { CGSize(width: 40, height: 40) }
}

final class AppleHomeBits {
  static let shared = AppleHomeBits()
  var meButton: MePhotoControl?
  var search: UISearchController?
}

extension Main: UISearchResultsUpdating, UISearchControllerDelegate {
  // once, as Home is made
  func appleHomeSetup(_ h: HomeView) {
    guard APPLE_HOME else { return }
    navigationItem.largeTitleDisplayMode = .always
    // (the big title as our other pages' — 34 bold, the label colour — Haris 2026-11-07)
    navigationController?.navigationBar.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.label]
    h.onAppleTitle = { [weak self] t, d in
      self?.navigationItem.title = t
      if #available(iOS 26.0, *) {
        self?.navigationItem.subtitle = d.isEmpty ? nil : d
        // (under the big title: the date as our other pages have it — 15 regular, the secondary grey — Haris 2026-11-07)
        if d.isEmpty { self?.navigationItem.largeAttributedSubtitle = nil } else {
          var a = AttributedString(d); a.uiKit.font = .systemFont(ofSize: 15); a.uiKit.foregroundColor = .secondaryLabel
          self?.navigationItem.largeAttributedSubtitle = a
        }
      }
    }
    h.onAppleMe = { img in
      guard let img = img else { return }
      AppleHomeBits.shared.meButton?.set(img)
    }
    h.onAppleResign = { AppleHomeBits.shared.search?.searchBar.resignFirstResponder() }
    // your photo (Me) and 🔍, as Apple's bar buttons
    // (always a circle: its own size, its corners half its size whatever the bar does with it — it came out stretched,
    //  not round: Haris 2026-11-07)
    let b = MePhotoControl(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    b.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 40), b.heightAnchor.constraint(equalToConstant: 40)])
    b.isAccessibilityElement = true; b.accessibilityTraits = .button
    b.accessibilityLabel = "Me"
    b.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.homeIfMade?.meTap() }, for: .touchUpInside)
    AppleHomeBits.shared.meButton = b
    let meItem = UIBarButtonItem(customView: b)
    if #available(iOS 26.0, *) { meItem.hidesSharedBackground = true }
    let find = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), primaryAction: UIAction { [weak self] _ in
      UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.appleHomeSearch()
    })
    find.accessibilityLabel = "Search"
    // iOS 26: Apple's own search button in the bar — it opens into the search field there and closes back, all Apple's
    // (Haris 2026-11-07: the search bar went to the bottom, and a second search left it gone and the page stuck)
    if #available(iOS 26.0, *) {
      navigationItem.searchController = makeHomeSearch()
      navigationItem.hidesSearchBarWhenScrolling = false
      navigationItem.preferredSearchBarPlacement = .integratedButton
      navigationItem.searchBarPlacementAllowsToolbarIntegration = false
      // (Apple's own item for where its search button goes: 🔍, then your photo at the right end, as before — Haris
      //  2026-11-07)
      navigationItem.rightBarButtonItems = [meItem, navigationItem.searchBarPlacementBarButtonItem]
    } else {
      navigationItem.rightBarButtonItems = [meItem, find]
    }
    h.useAppleTop()
  }
  // Apple's bar shows while Home is the screen on show (and Main is on top); hidden for every other screen of the app's
  // (not over the startup screen: it comes as that fades out)
  func appleHomeBar(animated: Bool, splashGoing: Bool = false) {
    guard APPLE_HOME, let nav = navigationController, nav.topViewController === self else { return }
    let want = homeIfMade?.appleTop == true && shownScreen === homeIfMade && lockView == nil && (splash == nil || splashGoing)
    if nav.isNavigationBarHidden == want { nav.setNavigationBarHidden(!want, animated: animated) }
    if want, let h = homeIfMade { setContentScrollView(h.appleScroll, for: .top); h.appleKeepTop(); DispatchQueue.main.async { h.appleKeepTop() } }
  }
  // 🔍: Apple's search bar comes in under the bar, ready to type
  func makeHomeSearch() -> UISearchController {
    if let x = AppleHomeBits.shared.search { return x }
    let s = UISearchController(searchResultsController: nil)
    s.obscuresBackgroundDuringPresentation = false
    s.searchResultsUpdater = self
    s.delegate = self
    s.searchBar.placeholder = "Search tasks, clients or people"
    s.searchBar.autocorrectionType = .no
    AppleHomeBits.shared.search = s
    return s
  }
  // (before iOS 26: our 🔍 bar button brings Apple's search bar in under the bar)
  func appleHomeSearch() {
    let s = makeHomeSearch()
    navigationItem.searchController = s
    navigationItem.hidesSearchBarWhenScrolling = false
    if #available(iOS 16.0, *) { navigationItem.preferredSearchBarPlacement = .stacked }
    // (at the top, under the bar — iOS 26 put it at the bottom among the toolbar's things: Haris 2026-11-07)
    if #available(iOS 26.0, *) { navigationItem.searchBarPlacementAllowsToolbarIntegration = false }
    DispatchQueue.main.async { s.isActive = true }
  }
  func updateSearchResults(for s: UISearchController) {
    guard s === AppleHomeBits.shared.search else { return }
    homeIfMade?.appleSearchText(s.searchBar.text ?? "")
  }
  func willPresentSearchController(_ s: UISearchController) {
    guard s === AppleHomeBits.shared.search, let h = homeIfMade else { return }
    h.appleSearchBegin()
    // (while searching, no big title under the search field — it showed there, cut at the left edge: Haris 2026-11-07;
    //  as Mail, only the field and the results)
    navigationItem.largeTitleDisplayMode = .never
    setContentScrollView(h.appleScroll, for: .top)
  }
  func didPresentSearchController(_ s: UISearchController) {
    guard s === AppleHomeBits.shared.search else { return }
    DispatchQueue.main.async { s.searchBar.becomeFirstResponder() }
  }
  func willDismissSearchController(_ s: UISearchController) {
    guard s === AppleHomeBits.shared.search else { return }
    homeIfMade?.appleSearchEnd()
    navigationItem.largeTitleDisplayMode = .always
  }
  func didDismissSearchController(_ s: UISearchController) {
    guard s === AppleHomeBits.shared.search else { return }
    if #unavailable(iOS 26.0) { navigationItem.searchController = nil }   // (iOS 26: it stays, as Apple's button)
    if let h = homeIfMade { setContentScrollView(h.appleScroll, for: .top) }
  }
}
