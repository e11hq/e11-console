import UIKit

/* Home in iPhone's own navigation (Haris 2026-11-07: "the design will be ours, the behaviour Apple's"): on Home, Apple's
   bar — the big title (E11 Day) with the date under it, shrinking into the bar as the list scrolls, its frost, 🔍 and your
   photo as Apple's bar buttons, and Apple's search bar (the results are Home's own cards). Opening a task and coming back
   is Apple's title change. The list, the cards, the boxes and "+ New task" are as they were. Only Home: My Tasks, the
   Inbox and Clients keep their own headers until they're done the same way. */
let APPLE_HOME = APPLE_NAV

final class AppleHomeBits {
  static let shared = AppleHomeBits()
  var meButton: UIButton?
  var search: UISearchController?
  let small = LeadingTitle()
}

// the bar's small title with the date under it, on the left (17 semibold; 12 regular grey — as Home's own were). As wide
// as the bar lets it be, so its words start at the left edge.
final class LeadingTitle: UIView {
  private let t = UILabel(), d = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    t.font = .systemFont(ofSize: 17, weight: .semibold); t.textColor = .label
    d.font = .systemFont(ofSize: 12); d.textColor = .secondaryLabel
    [t, d].forEach { $0.lineBreakMode = .byTruncatingTail; addSubview($0) }
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    setContentHuggingPriority(.defaultLow, for: .horizontal)
  }
  required init?(coder: NSCoder) { fatalError() }
  func set(_ title: String, _ date: String) { t.text = title; d.text = date; d.isHidden = date.isEmpty; setNeedsLayout() }
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.layoutFittingExpandedSize.width, height: 40) }
  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    if d.isHidden { t.frame = CGRect(x: 0, y: (H - 21) / 2, width: W, height: 21) }
    else { t.frame = CGRect(x: 0, y: H / 2 - 19, width: W, height: 21); d.frame = CGRect(x: 0, y: H / 2 + 3, width: W, height: 15) }
  }
}

extension Main: UISearchResultsUpdating, UISearchControllerDelegate {
  // once, as Home is made
  func appleHomeSetup(_ h: HomeView) {
    guard APPLE_HOME else { return }
    navigationItem.largeTitleDisplayMode = .always
    navigationItem.titleView = AppleHomeBits.shared.small
    AppleHomeBits.shared.small.alpha = 0
    h.onAppleScroll = { [weak self] in self?.appleSmallTitle() }
    // (the big title as our other pages' — 34 bold, the label colour — Haris 2026-11-07)
    navigationController?.navigationBar.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.label]
    h.onAppleTitle = { [weak self] t, d in
      self?.navigationItem.title = t
      // (the small title and its date on the bar: on the left, as ours were — Haris 2026-11-07; Apple's big title as is)
      AppleHomeBits.shared.small.set(t, d)
      if #available(iOS 26.0, *) {
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
    let b = UIButton(type: .custom)
    b.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
    b.widthAnchor.constraint(equalToConstant: 34).isActive = true; b.heightAnchor.constraint(equalToConstant: 34).isActive = true
    b.layer.cornerRadius = 17; b.clipsToBounds = true
    b.imageView?.contentMode = .scaleAspectFill
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
    if want, let h = homeIfMade { setContentScrollView(h.appleScroll, for: .top); DispatchQueue.main.async { self.appleSmallTitle() } }
  }
  // the small title on the left only once Apple's big title has gone up into the bar (shown with it, it was there twice)
  func appleSmallTitle() {
    guard APPLE_HOME, let nb = navigationController?.navigationBar, !nb.isHidden else { return }
    let small = AppleHomeBits.shared.small
    let want: CGFloat = nb.frame.height < 70 ? 1 : 0
    if small.alpha != want { UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { small.alpha = want } }
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
