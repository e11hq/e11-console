import UIKit

/* Home in iPhone's own navigation (Haris 2026-11-07: "the design will be ours, the behaviour Apple's"): on Home, Apple's
   bar — the big title (E11 Day) with the date under it, shrinking into the bar as the list scrolls, its frost, 🔍 and your
   photo as Apple's bar buttons, and Apple's search bar (the results are Home's own cards). Opening a task and coming back
   is Apple's title change. The list, the cards, the boxes and "+ New task" are as they were. Only Home: My Tasks, the
   Inbox and Clients keep their own headers until they're done the same way. */
let APPLE_HOME = APPLE_NAV

final class RoundPhotoButton: UIButton {
  override func layoutSubviews() { super.layoutSubviews(); layer.cornerRadius = min(bounds.width, bounds.height) / 2; imageView?.frame = bounds }
  override var intrinsicContentSize: CGSize { CGSize(width: 38, height: 38) }
}

final class AppleHomeBits {
  static let shared = AppleHomeBits()
  var meButton: UIButton?
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
      AppleHomeBits.shared.meButton?.setImage(img, for: .normal)
    }
    h.onAppleResign = { AppleHomeBits.shared.search?.searchBar.resignFirstResponder() }
    // your photo (Me) and 🔍, as Apple's bar buttons
    // (always a circle: its own size, its corners half its size whatever the bar does with it — it came out stretched,
    //  not round: Haris 2026-11-07)
    let b = RoundPhotoButton(type: .custom)
    b.frame = CGRect(x: 0, y: 0, width: 38, height: 38)
    b.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 38), b.heightAnchor.constraint(equalToConstant: 38)])
    b.clipsToBounds = true
    b.imageView?.contentMode = .scaleAspectFill
    b.contentHorizontalAlignment = .fill; b.contentVerticalAlignment = .fill
    b.accessibilityLabel = "Me"
    b.addAction(UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.homeIfMade?.meTap() }, for: .touchUpInside)
    AppleHomeBits.shared.meButton = b
    let meItem = UIBarButtonItem(customView: b)
    if #available(iOS 26.0, *) { meItem.hidesSharedBackground = true }
    let find = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), primaryAction: UIAction { [weak self] _ in
      UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.appleHomeSearch()
    })
    find.accessibilityLabel = "Search"
    navigationItem.rightBarButtonItems = [meItem, find]
    h.useAppleTop()
  }
  // Apple's bar shows while Home is the screen on show (and Main is on top); hidden for every other screen of the app's
  // (not over the startup screen: it comes as that fades out)
  func appleHomeBar(animated: Bool, splashGoing: Bool = false) {
    guard APPLE_HOME, let nav = navigationController, nav.topViewController === self else { return }
    let want = homeIfMade?.appleTop == true && shownScreen === homeIfMade && lockView == nil && (splash == nil || splashGoing)
    if nav.isNavigationBarHidden == want { nav.setNavigationBarHidden(!want, animated: animated) }
    if want, let h = homeIfMade { setContentScrollView(h.appleScroll, for: .top) }
  }
  // 🔍: Apple's search bar comes in under the bar, ready to type
  func appleHomeSearch() {
    let s: UISearchController
    if let x = AppleHomeBits.shared.search { s = x } else {
      s = UISearchController(searchResultsController: nil)
      s.obscuresBackgroundDuringPresentation = false
      s.searchResultsUpdater = self
      s.delegate = self
      s.searchBar.placeholder = "Search tasks, clients or people"
      s.searchBar.autocorrectionType = .no
      AppleHomeBits.shared.search = s
    }
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
    setContentScrollView(h.appleScroll, for: .top)
  }
  func didPresentSearchController(_ s: UISearchController) {
    guard s === AppleHomeBits.shared.search else { return }
    DispatchQueue.main.async { s.searchBar.becomeFirstResponder() }
  }
  func willDismissSearchController(_ s: UISearchController) {
    guard s === AppleHomeBits.shared.search else { return }
    homeIfMade?.appleSearchEnd()
  }
  func didDismissSearchController(_ s: UISearchController) {
    guard s === AppleHomeBits.shared.search else { return }
    navigationItem.searchController = nil
    if let h = homeIfMade { setContentScrollView(h.appleScroll, for: .top) }
  }
}
