import UIKit

/* ================= iPhone's own navigation (Haris 2026-11-07: "the design will be our's (look UI) behavior will be
   apples") — project doc claude/ios-back-swipe-idea.md. =================
   The app's screens keep their own look; moving between them is Apple's own: a UINavigationController at the root (its
   bar hidden over the app's own screens), each task page pushed as its own view controller with Apple's bar on top (‹,
   the client, •••), Apple's push and pop and the swipe back from the edge — as E11 Talk.
   Step 1 (this): the task page. Next: the tabs' own screens, one by one. */
let APPLE_NAV = true

// Apple's handler for a gesture, kept: everything goes to it; ours only adds a "may it start" of its own
final class PopGuard: NSObject, UIGestureRecognizerDelegate {
  weak var original: UIGestureRecognizerDelegate?
  let may: (UIGestureRecognizer) -> Bool
  init(original: UIGestureRecognizerDelegate?, may: @escaping (UIGestureRecognizer) -> Bool) { self.original = original; self.may = may }
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { (original?.gestureRecognizerShouldBegin?(g) ?? true) && may(g) }
  override func responds(to s: Selector!) -> Bool { super.responds(to: s) || (original?.responds(to: s) ?? false) }
  override func forwardingTarget(for s: Selector!) -> Any? { (original?.responds(to: s) ?? false) ? original : nil }
}

final class AppleNav: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
  private var popGuard: PopGuard?
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override func viewDidLoad() {
    super.viewDidLoad()
    delegate = self
    interactivePopGestureRecognizer?.delegate = self
    // (iOS 26: the swipe back from anywhere on the page — the same rules as the edge's)
    // (Apple's own handler for it stays — it also lets taps through to the rows under the finger; replacing it, a
    //  checklist's box couldn't be ticked: Haris 2026-11-07. Ours only adds: on a task's Comments it doesn't start.)
    if #available(iOS 26.0, *), let g = interactiveContentPopGestureRecognizer {
      let guardian = PopGuard(original: g.delegate) { [unowned self] _ in
        guard let t = self.topViewController as? TaskVC else { return true }
        return Main.shared.taskSwipeMayGo(t.page)
      }
      popGuard = guardian
      g.delegate = guardian
    }
    // (Home's own navigation: Apple's bar there from the start, with its big title — AppleHome.swift; the app's: no bar
    //  over its own screens)
    let home = viewControllers.first is HomeVC || viewControllers.first is MyTasksVC
    setNavigationBarHidden(!home, animated: false)
    navigationBar.prefersLargeTitles = home
  }
  // the swipe back: Apple's own; a comment written and not sent on the page asks first (as ‹ does)
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g === interactivePopGestureRecognizer, viewControllers.count > 1 else { return false }
    if let t = topViewController as? TaskVC { return Main.shared.taskSwipeMayGo(t.page) }
    if topViewController is ReplyVC { Main.shared.composeIfMade?.text.resignFirstResponder() }
    return true
  }
  var backAnywhere: UIGestureRecognizer? { if #available(iOS 26.0, *) { return interactiveContentPopGestureRecognizer } else { return nil } }
  // (Apple's swipe back and the app's own gestures inside a page — the comments' swipes, the files row — together)
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { false }
  // a page gone (popped by ‹, swiped away, or taken out): the app lets go of it as when it closes
  // (Apple's tab bar slides away as a page comes over the tabs, and back as the app's screen comes back — AppleTabs.swift)
  func navigationController(_ n: UINavigationController, willShow vc: UIViewController, animated: Bool) {
    // (Home's navigation is its tab's own: the tab bar slides away as a page comes and back as Home does — Apple's tab bar
    //  call, not "hide the bottom bar when pushed": that re-sized the whole screen at the slide's first moment and Apple's
    //  bar snapped small, the big title jumping into it — Haris 2026-11-08, build 1544's test)
    if n === AppleTabs.shared?.homeNav || n === AppleTabs.shared?.myTasksNav { AppleTabs.shared?.homeNavWillShow(vc, animated: animated, nav: n); return }
    AppleTabs.shared?.mirrorShown(animated: animated, top: vc)
  }
  func navigationController(_ n: UINavigationController, didShow vc: UIViewController, animated: Bool) {
    Main.shared.taskPagesGone(stack: Main.shared.allNavs.flatMap { $0.viewControllers })
    AppleTabs.shared?.mirrorShown()   // (back on the app's screens: Apple's tab bar as Main has it)
  }
}

// a reply thread, pushed over its task (Haris 2026-11-07): an Apple page of its own — Apple's bar ("Thread"), ‹ and the
// swipe back to the comments; the thread's list and the comment box as they were
final class ReplyVC: UIViewController {
  let page: TaskPage, feed: CommentsFeed
  init(page: TaskPage, feed: CommentsFeed) { self.page = page; self.feed = feed; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() {
    let v = UIView(frame: UIScreen.main.bounds)
    v.backgroundColor = .systemGroupedBackground
    view = v
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Thread"
    navigationItem.largeTitleDisplayMode = .never
    feed.transform = .identity
    feed.frame = view.bounds
    feed.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(feed)
    setContentScrollView(feed.scroll, for: .top)   // (Apple's frost under its bar follows the thread's list)
    if #available(iOS 16.0, *) {
      navigationItem.backAction = UIAction { [weak self] _ in
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Main.shared.composeIfMade?.text.resignFirstResponder()
        self?.navigationController?.popViewController(animated: true)
      }
    }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let top = view.safeAreaInsets.top   // (its own bar's bottom — the bar's frame changes during a swipe back)
    if feed.topInset != top { feed.topInset = top }
    feed.follow(box: Main.shared.composeIfMade)   // (the room under the thread: the box on Apple's keyboard guide)
  }
}

// one task page, pushed: the page (TaskPage, its look as it is) fills it; Apple's bar on top
final class TaskVC: UIViewController {
  let page: TaskPage
  // (no tab bar under a task: Apple's tab bar call hides it as the page comes — AppleNav's willShow / AppleTabs)
  init(_ p: TaskPage) { page = p; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() {
    let v = UIView(frame: UIScreen.main.bounds)
    v.backgroundColor = .systemBackground
    view = v
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .never
    navigationItem.backButtonDisplayMode = .minimal   // (a subtask over it: just ‹)
    // ‹: leaving the page (a comment not sent: asked first, as before)
    if #available(iOS 16.0, *) {
      navigationItem.backAction = UIAction { [weak self] _ in
        guard let p = self?.page else { return }
        if p.editingDesc { p.finishDesc() }   // (‹ while writing the description: it's kept, then back)
        // (‹ as the swipes, a step at a time: a reply → the comments → Details → back — Haris 2026-11-07)
        if p.threadFeed != nil || p.tab == "comments" { Main.shared.taskBackStep(p); return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Main.shared.leaveTaskPage(p)
      }
    }
    // Details · Comments in the middle of Apple's bar — Apple's own control in Apple's bar, its glass look, the bar's frost
    // never breaking under it (Haris 2026-11-08: the switch in a strip of ours lost the frost while held); the client's
    // dot and name are at the top of Details now
    let seg = page.seg
    seg.translatesAutoresizingMaskIntoConstraints = false
    seg.widthAnchor.constraint(equalToConstant: 236).isActive = true
    navigationItem.titleView = seg
    page.onBarTitle = { [weak self] t, _ in self?.navigationItem.title = t }   // (not shown: the name for ‹'s history menu)
    // (the bar's frost follows the list showing — Details, the comments, a reply)
    page.onEdgeScroll = { [weak self] sv in self?.setContentScrollView(sv, for: .top) }
    page.edgeScroll(page.scroll)
    page.onMenuMade = { [weak self] in self?.setMenu() }
    page.onDescEditing = { [weak self] _ in self?.setMenu() }
    setMenu()
  }
  // •••: the page's own menu (Copy link, Attach Files, Delete task — as it was)
  func setMenu() {
    // (the description being written: Apple's own Done ends it, where ••• is — Haris 2026-11-07; the shared Done was
    //  hidden behind this page)
    if page.editingDesc {
      let p = page
      navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); p.finishDesc() })
      return
    }
    if let m = page.cornerMenu {
      if let b = navigationItem.rightBarButtonItem, b.menu != nil { b.menu = m }
      else { navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "ellipsis"), primaryAction: nil, menu: m) }
    } else { navigationItem.rightBarButtonItem = nil }
  }
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    // (Apple's bar shown over the task — only where it was hidden, the app's own navigation; Home's has it always and
    //  isn't told again: told during the slide back it drew its search box anew, the box's glass coming in at the end —
    //  Haris 2026-11-07, E11 Talk never does it)
    if navigationController?.isNavigationBarHidden == true { navigationController?.setNavigationBarHidden(false, animated: a) }
    // (Details' edge swipe goes back; the paging scroller waits for it — on Comments it doesn't start, so the scroller takes it)
    // (and on Details the swipe back from anywhere too, as before the paging — Haris 2026-11-07)
    if let g = navigationController?.interactivePopGestureRecognizer { page.pagerWaits(for: g) }
    if let g = (navigationController as? AppleNav)?.backAnywhere { page.pagerWaits(for: g) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if page.superview === view { page.frame = view.bounds }
    // (the page's own top: its safe area, which is this page's bar — not the bar's frame, which during the swipe back is
    //  already turning into Home's taller one with its big title and search box, and the page dropped down with it:
    //  Haris 2026-11-07)
    page.appleRow = view.safeAreaInsets.top
    page.feed?.follow(box: Main.shared.composeIfMade)   // (the room under the comments: the box on Apple's keyboard guide)
  }
}
