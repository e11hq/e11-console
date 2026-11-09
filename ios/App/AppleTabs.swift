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
  var isHidden = true { didSet { AppleTabs.shared?.mirrorShown(); HomeVC.shared?.viewIfLoaded?.setNeedsLayout(); MyTasksVC.shared?.viewIfLoaded?.setNeedsLayout(); InboxVC.shared?.viewIfLoaded?.setNeedsLayout(); ClientsVC.shared?.viewIfLoaded?.setNeedsLayout(); AssetsTabVC.shared?.viewIfLoaded?.setNeedsLayout(); MeVC.shared?.viewIfLoaded?.setNeedsLayout() } }
  var alpha: CGFloat = 1 { didSet { AppleTabs.shared?.mirrorShown() } }
  var isUserInteractionEnabled: Bool {
    get { AppleTabs.shared?.tabBar.isUserInteractionEnabled ?? true }
    set { AppleTabs.shared?.tabBar.isUserInteractionEnabled = newValue }
  }
  var tintColor: UIColor?
  var unselectedItemTintColor: UIColor?
  var traitCollection: UITraitCollection { AppleTabs.shared?.traitCollection ?? Main.shared.traitCollection }
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
  // My Tasks' own tab, the same way (AppleMyTasks.swift — Haris 2026-11-08: it follows Home)
  let myTasksNav: AppleNav
  // the Inbox's own tab, the same way (AppleInbox.swift)
  let inboxNav: AppleNav
  // the Clients tab's own, the same way (AppleClients.swift)
  let clientsNav: AppleNav
  // Client Assets as a tab (the Office Admin's), the same way (AppleClients.swift)
  let assetsNav: AppleNav
  // Me's own, the same way (AppleMe.swift — Haris 2026-11-08)
  let meNav: AppleNav
  private var slots: [TabSlot] = []
  private var homeAt: Int?, myTasksAt: Int?, inboxAt: Int?, clientsAt: Int?, assetsAt: Int?, meAt: Int?
  private var selecting = false
  init(nav: UINavigationController) {
    self.nav = nav
    homeNav = AppleNav(rootViewController: HomeVC())
    // (Home's own navigation: Apple's bar with its big title, from the start — set here, as the navigation is made: made
    //  with its first screen, it may load before that screen is in it)
    homeNav.navigationBar.prefersLargeTitles = APPLE_HOME
    homeNav.navigationBar.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.label]
    homeNav.setNavigationBarHidden(false, animated: false)
    myTasksNav = AppleNav(rootViewController: MyTasksVC())
    myTasksNav.navigationBar.prefersLargeTitles = APPLE_MYTASKS
    myTasksNav.navigationBar.largeTitleTextAttributes = homeNav.navigationBar.largeTitleTextAttributes
    myTasksNav.setNavigationBarHidden(false, animated: false)
    inboxNav = AppleNav(rootViewController: InboxVC())
    inboxNav.navigationBar.prefersLargeTitles = APPLE_INBOX
    inboxNav.navigationBar.largeTitleTextAttributes = homeNav.navigationBar.largeTitleTextAttributes
    inboxNav.setNavigationBarHidden(false, animated: false)
    clientsNav = AppleNav(rootViewController: ClientsVC())
    clientsNav.navigationBar.prefersLargeTitles = APPLE_CLIENTS
    clientsNav.navigationBar.largeTitleTextAttributes = homeNav.navigationBar.largeTitleTextAttributes
    clientsNav.setNavigationBarHidden(false, animated: false)
    assetsNav = AppleNav(rootViewController: AssetsTabVC())
    assetsNav.navigationBar.prefersLargeTitles = APPLE_CLIENTS
    assetsNav.navigationBar.largeTitleTextAttributes = homeNav.navigationBar.largeTitleTextAttributes
    assetsNav.setNavigationBarHidden(false, animated: false)
    meNav = AppleNav(rootViewController: MeVC())
    meNav.navigationBar.prefersLargeTitles = APPLE_ME
    meNav.navigationBar.largeTitleTextAttributes = homeNav.navigationBar.largeTitleTextAttributes
    meNav.setNavigationBarHidden(false, animated: false)
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
  // the phone switched light / dark: the app follows at once, whichever tab is on (Main.followPhoneLook — the app's old
  // shared screen only heard it while it was the one on show)
  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { Main.shared.followPhoneLook() }
  }
  // Home's tab on show
  var homeShown: Bool { selectedViewController === homeNav }
  // the tab on show is one with its own navigation (Home, My Tasks) — and that navigation
  var ownNav: AppleNav? { [homeNav, myTasksNav, inboxNav, clientsNav, assetsNav, meNav].first { $0 === selectedViewController } }
  var ownShown: Bool { ownNav != nil }
  // (no tab of the app's own screen left — every tab its own Apple screen)
  private var noSlot: Bool { !slots.isEmpty && !slots.indices.contains { !own($0) } }
  private let spare = TabSlot()
  // the app's own screen kept out of sight inside Me's (or Home's) screen: still in the app, so what it presents opens
  private func stash() {
    guard let holder: UIViewController = (meAt != nil ? MeVC.shared as UIViewController? : nil) ?? homeNav.viewControllers.first else { return }
    guard nav.parent !== holder else { return }
    if nav.parent != nil { nav.willMove(toParent: nil); nav.view.removeFromSuperview(); nav.removeFromParent() }
    holder.loadViewIfNeeded()
    holder.addChild(nav)
    nav.view.frame = holder.view.bounds
    nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    nav.view.isHidden = true; nav.view.isUserInteractionEnabled = false
    holder.view.insertSubview(nav.view, at: 0)
    nav.didMove(toParent: holder)
  }
  private func own(_ i: Int) -> Bool { i == homeAt || i == myTasksAt || i == inboxAt || i == clientsAt || i == assetsAt || i == meAt }
  private func tabVC(_ i: Int) -> UIViewController { i == homeAt ? homeNav : i == myTasksAt ? myTasksNav : i == inboxAt ? inboxNav : i == clientsAt ? clientsNav : i == assetsAt ? assetsNav : i == meAt ? meNav : slots[i] }

  private func host(in s: TabSlot) {
    guard nav.parent !== s else { return }
    if nav.parent != nil { nav.willMove(toParent: nil); nav.view.removeFromSuperview(); nav.removeFromParent() }
    nav.view.isHidden = false; nav.view.isUserInteractionEnabled = true
    s.loadViewIfNeeded()
    s.addChild(nav)
    nav.view.frame = s.view.bounds
    nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    s.view.addSubview(nav.view)
    nav.didMove(toParent: s)
    s.fit()
  }
  // a page coming on Home's own navigation: the tab bar away for a task or a reply, back for Home — Apple's own tab bar
  // call, with the slide; a swipe back let go of half way: as it was (Haris 2026-11-08)
  // (going to a page: the tab bar slides away once the page has arrived — hidden as the slide began, the tab container
  //  laid itself out again at the slide's first moment and Apple's bar snapped small, the big title jumping into it:
  //  build 1547, Haris 2026-11-08. Back to Home: it comes as the slide begins.)
  func homeNavWillShow(_ vc: UIViewController, animated: Bool, nav: UINavigationController? = nil) {
    // (the Clients tab's pages — a client's page, Client Assets, a folder — keep the tab bar: Haris 2026-11-08 "all will have navbar")
    let hide = !(vc is TabRoot || vc is ClientsPushedVC)
    guard let tc = (nav ?? homeNav).transitionCoordinator else { hideBar(hide, animated: animated); return }
    if hide {
      tc.animate(alongsideTransition: nil) { [weak self] c in if !c.isCancelled { self?.hideBar(true, animated: true) } }
    } else {
      hideBar(false, animated: animated)
      // (a swipe back let go of half way: as the page that stays has it — hidden only for a page that hides it (a task, a
      //  reply); a page that keeps it (Me's, the Clients tab's) kept it — hidden there, it went and came back: Haris
      //  2026-11-08, a plan's page)
      if tc.isInteractive { tc.notifyWhenInteractionChanges { [weak self] c in
        guard c.isCancelled else { return }
        let stays = c.viewController(forKey: .from)
        if !(stays is TabRoot || stays is ClientsPushedVC) { self?.hideBar(true, animated: true) }
      } }
    }
  }
  private func hideBar(_ h: Bool, animated: Bool = false) {
    if #available(iOS 18.0, *) { if isTabBarHidden != h { setTabBarHidden(h, animated: animated) } } else if tabBar.isHidden != h { tabBar.isHidden = h }
  }

  // Main's tabs → Apple's: one tab each, the same names and icons (with their counts drawn in), your photo on Me
  func sync(from bar: Tabs) {
    let items = bar.items ?? []
    guard !items.isEmpty else { return }
    let home = APPLE_HOME ? Main.shared.tabKeys.firstIndex(of: "today") : nil
    let mt = APPLE_MYTASKS ? Main.shared.tabKeys.firstIndex(of: "mytasks") : nil
    let ib = APPLE_INBOX ? Main.shared.tabKeys.firstIndex(of: "inbox") : nil
    let cl = APPLE_CLIENTS ? Main.shared.tabKeys.firstIndex(of: "projects") : nil
    let ca = APPLE_CLIENTS ? Main.shared.tabKeys.firstIndex(of: "clients") : nil
    let me = APPLE_ME ? Main.shared.tabKeys.firstIndex(of: "me") : nil
    if slots.count != items.count || home != homeAt || mt != myTasksAt || ib != inboxAt || cl != clientsAt || ca != assetsAt || me != meAt {
      while slots.count < items.count { slots.append(TabSlot()) }
      if slots.count > items.count { slots = Array(slots.prefix(items.count)) }
      homeAt = home.flatMap { $0 < items.count ? $0 : nil }
      myTasksAt = mt.flatMap { $0 < items.count ? $0 : nil }
      inboxAt = ib.flatMap { $0 < items.count ? $0 : nil }
      clientsAt = cl.flatMap { $0 < items.count ? $0 : nil }
      assetsAt = ca.flatMap { $0 < items.count ? $0 : nil }
      meAt = me.flatMap { $0 < items.count ? $0 : nil }
      let keep = nav.parent as? TabSlot
      setViewControllers(items.indices.map { tabVC($0) }, animated: false)
      if let k = keep, !slots.enumerated().contains(where: { $0.element === k && !own($0.offset) }) { if let j = slots.indices.first(where: { !own($0) }) { host(in: slots[j]) } }
      if noSlot { stash() }
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
    if let sel = bar.selectedItem?.tag { select(sel) }
    mirrorShown()
  }
  private func select(_ i: Int) {
    guard slots.indices.contains(i) else { return }
    if !own(i) { host(in: slots[i]) }
    if selectedIndex != i { selectedIndex = i }
  }
  // Main put another tab on (the page moved it, a tab "as if tapped")
  func mirrorSelected(_ tag: Int?) { guard !selecting, let t = tag else { return }; select(t) }
  // Main's bar shown / hidden / faded → Apple's; not over the startup screen or the lock; a page pushed over the tabs
  // (a task) hides it Apple's way
  func mirrorShown(animated: Bool = false, top: UIViewController? = nil) {
    let main = Main.shared
    // (every tab its own Apple screen — Me's too, AppleMe.swift: no tab holds the app's own screen any more. With no tabs
    //  — the sign-in page, the website's own screens — it goes into a tab of its own, out of sight with the tab bar;
    //  with tabs, it's kept out of sight in Me's screen, still part of the app, so sheets can open from it)
    if noSlot {
      if main.tabsHidden {
        if !(viewControllers ?? []).contains(spare) { setViewControllers((viewControllers ?? []) + [spare], animated: false) }
        host(in: spare)
        if selectedViewController !== spare { selectedViewController = spare }
      } else if (viewControllers ?? []).contains(spare) {
        setViewControllers((viewControllers ?? []).filter { $0 !== spare }, animated: false)
        stash()
        if let sel = main.tabBar.selectedItem?.tag { select(sel) }
      } else if nav.parent == nil || (nav.parent is TabSlot && !(viewControllers ?? []).contains(nav.parent!)) { stash() }
    }
    // (no tabs — the sign-in page, the website's own screens: the app's own navigation on show, not Home's)
    if main.tabsHidden && ownShown, let j = slots.indices.first(where: { !own($0) }), selectedIndex != j {
      host(in: slots[j]); selectedIndex = j
    }
    // (Home's own navigation sliding a page in or out: Apple shows and hides the tab bar itself — told anything mid-slide
    //  (the task page's closing told it "hidden" as Home slid back), the tab container laid itself out again under the
    //  slide and Home's search box was drawn anew, its glass coming in at the end: Haris 2026-11-07. Told once it's done.)
    if let o = ownNav, o.transitionCoordinator != nil { return }
    // (a page pushed over the tabs — a task, a reply: no tab bar, Apple's slide away)
    let shown = top ?? (ownNav?.topViewController ?? nav.topViewController)
    // (on a tab's own navigation — Home's, My Tasks' — it's done as the page comes: homeNavWillShow)
    if shown !== main && !(shown is TabRoot) && !(shown is ClientsPushedVC) { if !ownShown { hideBar(true, animated: animated) }; return }   // (Client Assets opened from Me keeps it — Haris 2026-11-08)
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
    // (the button in the corner as the tab left showed it — the next tab's squashes and stretches out of it)
    fabLeft = vc === selectedViewController ? nil : AppleTabs.cornerScreen(selectedViewController)?.fabInWindow
    if !own(i) { host(in: slots[i]) }
    if main.tabBar.selectedItem !== item { selecting = true; main.tabBar.selectedItem = item; selecting = false }
    return true
  }
  // ---- + New task ↔ + Add client as the tab changes: our button only (Haris 2026-11-08) ----
  private var fabLeft: (frame: CGRect, config: UIButton.Configuration?, label: String)?
  // the screen on show in a tab with its own button (the tab's top page)
  static func cornerScreen(_ vc: UIViewController?) -> HomeView? {
    let top = (vc as? UINavigationController)?.topViewController ?? vc
    // (a tab's own Apple first screen only — Home, My Tasks, the Inbox, Clients, Client Assets; never the app's old shared screen)
    guard top is TabRoot, let v = top?.viewIfLoaded, v.window != nil else { return nil }
    var q: [UIView] = [v]
    while !q.isEmpty { let x = q.removeFirst(); if let h = x as? HomeView, !h.isHidden { return h }; q += x.subviews }
    return nil
  }
  func tabBarController(_ c: UITabBarController, didSelect vc: UIViewController) {
    guard let i = (0..<slots.count).first(where: { tabVC($0) === vc }) else { return }
    let main = Main.shared
    guard let item = main.tabBar.items?.first(where: { $0.tag == i }) else { return }
    main.tabBar(main.tabBar, didSelect: item)
    if let old = fabLeft { fabLeft = nil; AppleTabs.cornerScreen(vc)?.fabArrive(from: old) }
  }
}
