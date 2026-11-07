import UIKit

/* iPhone's own tab container (Haris 2026-11-07: "Tab bar first and send all together"): Apple's UITabBarController is
   the app's root — its own tab bar, its glass, its switching, and the room it keeps (search, the keyboard and pages
   pushed over it know where it is). The app's screens are as they were: the one navigation (AppleNav, with Main and the
   task pages) sits in the tab that's selected, and Main still decides what each tab shows. Main's own tab bar stays as
   the source of the tabs (names, icons and their counts, your photo, which one is on, hidden or faded) — not a bar, only
   what it says, passed to Apple's at once (Tabs). */
let APPLE_TABS = APPLE_NAV

// The app's tabs (Haris 2026-11-07: no hidden bar of the app's own — it took taps above Apple's): what Main says about
// them — the tabs, the one that's on, shown / hidden / faded, the colours — kept here and told to Apple's tab bar at once.
// Not a view: nothing to see or touch.
final class Tabs {
  var items: [UITabBarItem]?
  var selectedItem: UITabBarItem?
  var isHidden = true { didSet { AppleTabs.shared?.mirrorShown(); HomeVC.shared?.viewIfLoaded?.setNeedsLayout() } }
  var alpha: CGFloat = 1 { didSet { AppleTabs.shared?.mirrorShown() } }
  var isUserInteractionEnabled: Bool {
    get { AppleTabs.shared?.tabBar.isUserInteractionEnabled ?? true }
    set { AppleTabs.shared?.tabBar.isUserInteractionEnabled = newValue }
  }
  var tintColor: UIColor?
  var unselectedItemTintColor: UIColor?
  var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
  var traitCollection: UITraitCollection {
    overrideUserInterfaceStyle == .unspecified ? Main.shared.traitCollection : UITraitCollection(userInterfaceStyle: overrideUserInterfaceStyle)
  }
  // (where Apple's bar is, as the app's screens measure it — Main's layout)
  var frame: CGRect = .zero
  func sizeThatFits(_ s: CGSize) -> CGSize { AppleTabs.shared?.tabBar.sizeThatFits(s) ?? CGSize(width: s.width, height: 49) }
}

// one tab: it holds the app's navigation while it's the one selected
final class TabSlot: UIViewController {
  override var childForStatusBarStyle: UIViewController? { children.first }
  override var childForStatusBarHidden: UIViewController? { children.first }
  override func loadView() { let v = UIView(); v.backgroundColor = .clear; view = v }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); if let c = children.first, c.view.frame != view.bounds { c.view.frame = view.bounds }; fit() }
  override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); fit() }
  // (the app's screens keep measuring their bottoms as before — from the phone's own edge, not above Apple's bar: they
  //  already keep the bar's room themselves — "+ New task", the lists' ends)
  func fit() {
    guard let c = children.first, let w = view.window else { return }
    let extra = max(0, view.safeAreaInsets.bottom - w.safeAreaInsets.bottom)
    if c.additionalSafeAreaInsets.bottom != -extra { c.additionalSafeAreaInsets.bottom = -extra }
  }
}

final class AppleTabs: UITabBarController, UITabBarControllerDelegate {
  static weak var shared: AppleTabs?
  let nav: UINavigationController   // (the app's own navigation: every tab but Home — it moves into the tab that's on)
  // Home's own tab: its own navigation with Home's screen at its root (AppleHome.swift) — the tab's view controller itself,
  // as Apple builds a tab
  let homeNav: AppleNav
  private var slots: [TabSlot] = []
  private var homeAt: Int?
  private var selecting = false
  init(nav: UINavigationController) {
    self.nav = nav
    homeNav = AppleNav(rootViewController: HomeVC())
    // (Home's own navigation: Apple's bar with its big title, from the start — set here, as the navigation is made: made
    //  with its first screen, it may load before that screen is in it)
    homeNav.navigationBar.prefersLargeTitles = APPLE_HOME
    homeNav.navigationBar.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.label]
    homeNav.setNavigationBarHidden(false, animated: false)
    super.init(nibName: nil, bundle: nil)
    AppleTabs.shared = self
    delegate = self
    let s = TabSlot(); slots = [s]
    setViewControllers(slots, animated: false)
    host(in: s)
    hideBar(true)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var childForStatusBarStyle: UIViewController? { selectedViewController }
  override var childForStatusBarHidden: UIViewController? { selectedViewController }
  // Home's tab on show
  var homeShown: Bool { selectedViewController === homeNav }
  private func tabVC(_ i: Int) -> UIViewController { i == homeAt ? homeNav : slots[i] }

  private func host(in s: TabSlot) {
    guard nav.parent !== s else { return }
    if nav.parent != nil { nav.willMove(toParent: nil); nav.view.removeFromSuperview(); nav.removeFromParent() }
    s.loadViewIfNeeded()
    s.addChild(nav)
    nav.view.frame = s.view.bounds
    nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    s.view.addSubview(nav.view)
    nav.didMove(toParent: s)
    s.fit()
  }
  private func hideBar(_ h: Bool, animated: Bool = false) {
    if #available(iOS 18.0, *) { if isTabBarHidden != h { setTabBarHidden(h, animated: animated) } } else if tabBar.isHidden != h { tabBar.isHidden = h }
  }

  // Main's tabs → Apple's: one tab each, the same names and icons (with their counts drawn in), your photo on Me
  func sync(from bar: Tabs) {
    let items = bar.items ?? []
    guard !items.isEmpty else { return }
    let home = APPLE_HOME ? Main.shared.tabKeys.firstIndex(of: "today") : nil
    if slots.count != items.count || home != homeAt {
      while slots.count < items.count { slots.append(TabSlot()) }
      if slots.count > items.count { slots = Array(slots.prefix(items.count)) }
      homeAt = home.flatMap { $0 < items.count ? $0 : nil }
      let keep = nav.parent as? TabSlot
      setViewControllers(items.indices.map { tabVC($0) }, animated: false)
      if let k = keep, !slots.enumerated().contains(where: { $0.element === k && $0.offset != homeAt }) { if let j = slots.indices.first(where: { $0 != homeAt }) { host(in: slots[j]) } }
    }
    for (i, it) in items.enumerated() {
      let t = tabVC(i).tabBarItem!
      if t.title != it.title { t.title = it.title }
      if t.image !== it.image { t.image = it.image }
      if t.selectedImage !== it.selectedImage { t.selectedImage = it.selectedImage }
      t.tag = i
      t.badgeValue = it.badgeValue
      t.accessibilityLabel = it.accessibilityLabel ?? it.title
    }
    if tabBar.tintColor != bar.tintColor { tabBar.tintColor = bar.tintColor }
    if tabBar.unselectedItemTintColor != bar.unselectedItemTintColor { tabBar.unselectedItemTintColor = bar.unselectedItemTintColor }
    if tabBar.overrideUserInterfaceStyle != bar.overrideUserInterfaceStyle { tabBar.overrideUserInterfaceStyle = bar.overrideUserInterfaceStyle }
    if let sel = bar.selectedItem?.tag { select(sel) }
    mirrorShown()
  }
  private func select(_ i: Int) {
    guard slots.indices.contains(i) else { return }
    if i != homeAt { host(in: slots[i]) }
    if selectedIndex != i { selectedIndex = i }
  }
  // Main put another tab on (the page moved it, a tab "as if tapped")
  func mirrorSelected(_ tag: Int?) { guard !selecting, let t = tag else { return }; select(t) }
  // Main's bar shown / hidden / faded → Apple's; not over the startup screen or the lock; a page pushed over the tabs
  // (a task) hides it Apple's way
  func mirrorShown(animated: Bool = false, top: UIViewController? = nil) {
    let main = Main.shared
    // (no tabs — the sign-in page, the website's own screens: the app's own navigation on show, not Home's)
    if main.tabsHidden && homeShown, let j = slots.indices.first(where: { $0 != homeAt }), selectedIndex != j {
      host(in: slots[j]); selectedIndex = j
    }
    // (a page pushed over the tabs — a task, a reply: no tab bar, Apple's slide away)
    let shown = top ?? (homeShown ? homeNav.topViewController : nav.topViewController)
    // (on Home's own navigation Apple does it itself — the page hides the tab bar as it's pushed)
    if shown !== main && !(shown is HomeVC) { if !homeShown { hideBar(true, animated: animated) }; return }
    let b = main.tabBar
    // (faded by the app — a New task draft tucked over it: hidden Apple's way, never its alpha set by us; Apple put it
    //  back as the list scrolled, in a snap — Haris 2026-11-07)
    let hide = b.isHidden || b.alpha < 0.5 || main.lockView != nil || (main.splash != nil && !main.splashLeaving)
    hideBar(hide, animated: animated || UIView.inheritedAnimationDuration > 0)
    if tabBar.alpha != 1 { tabBar.alpha = 1 }
  }

  // ---------- a tab tapped on Apple's bar: the app's navigation moves into it (Home: its own), and Main does what a tap did ----------
  func tabBarController(_ c: UITabBarController, shouldSelect vc: UIViewController) -> Bool {
    guard let i = (0..<slots.count).first(where: { tabVC($0) === vc }) else { return false }
    let main = Main.shared
    guard let item = main.tabBar.items?.first(where: { $0.tag == i }) else { return false }
    if i != homeAt { host(in: slots[i]) }
    if main.tabBar.selectedItem !== item { selecting = true; main.tabBar.selectedItem = item; selecting = false }
    return true
  }
  func tabBarController(_ c: UITabBarController, didSelect vc: UIViewController) {
    guard let i = (0..<slots.count).first(where: { tabVC($0) === vc }) else { return }
    let main = Main.shared
    guard let item = main.tabBar.items?.first(where: { $0.tag == i }) else { return }
    main.tabBar(main.tabBar, didSelect: item)
  }
}
