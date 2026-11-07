import UIKit

/* ================= iPhone's own navigation (Haris 2026-11-07: "the design will be our's (look UI) behavior will be
   apples") — project doc claude/ios-back-swipe-idea.md. =================
   The app's screens keep their own look; moving between them is Apple's own: a UINavigationController at the root (its
   bar hidden over the app's own screens), each task page pushed as its own view controller with Apple's bar on top (‹,
   the client, •••), Apple's push and pop and the swipe back from the edge — as E11 Talk.
   Step 1 (this): the task page. Next: the tabs' own screens, one by one. */
let APPLE_NAV = true

final class AppleNav: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override func viewDidLoad() {
    super.viewDidLoad()
    delegate = self
    interactivePopGestureRecognizer?.delegate = self
    setNavigationBarHidden(true, animated: false)
  }
  // the swipe back: Apple's own; a comment written and not sent on the page asks first (as ‹ does)
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g === interactivePopGestureRecognizer, viewControllers.count > 1 else { return false }
    if let t = topViewController as? TaskVC { return Main.shared.taskSwipeMayGo(t.page) }
    return true
  }
  // (Apple's swipe back and the app's own gestures inside a page — the comments' swipes, the files row — together)
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { false }
  // a page gone (popped by ‹, swiped away, or taken out): the app lets go of it as when it closes
  func navigationController(_ n: UINavigationController, didShow vc: UIViewController, animated: Bool) {
    Main.shared.taskPagesGone(stack: n.viewControllers)
  }
}

// one task page, pushed: the page (TaskPage, its look as it is) fills it; Apple's bar on top
final class TaskVC: UIViewController {
  let page: TaskPage
  private let titleBox = UIStackView(), dot = UIView(), name = UILabel()
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
        // (‹ as the swipes, a step at a time: a reply → the comments → Details → back — Haris 2026-11-07)
        if p.threadFeed != nil || p.tab == "comments" { Main.shared.taskBackStep(p); return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Main.shared.leaveTaskPage(p)
      }
    }
    // the client's dot and name in the middle of the bar, as the page had them
    dot.layer.cornerRadius = 4; dot.widthAnchor.constraint(equalToConstant: 8).isActive = true; dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
    name.font = .systemFont(ofSize: 17, weight: .semibold); name.lineBreakMode = .byTruncatingTail
    titleBox.axis = .horizontal; titleBox.alignment = .center; titleBox.spacing = 8
    titleBox.addArrangedSubview(dot); titleBox.addArrangedSubview(name)
    navigationItem.titleView = titleBox
    page.onBarTitle = { [weak self] t, c in self?.setTitle(t, c) }
    page.onMenuMade = { [weak self] in self?.setMenu() }
    setMenu()
  }
  func setTitle(_ t: String, _ c: UIColor?) {
    name.text = t
    dot.isHidden = c == nil; dot.backgroundColor = c
    titleBox.sizeToFit()
  }
  // •••: the page's own menu (Copy link, Attach Files, Delete task — as it was)
  func setMenu() {
    if let m = page.cornerMenu {
      if let b = navigationItem.rightBarButtonItem { b.menu = m }
      else { navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "ellipsis"), primaryAction: nil, menu: m) }
    } else { navigationItem.rightBarButtonItem = nil }
  }
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    navigationController?.setNavigationBarHidden(false, animated: a)
    // (Details' edge swipe goes back; the paging scroller waits for it — on Comments it doesn't start, so the scroller takes it)
    if let g = navigationController?.interactivePopGestureRecognizer { page.pagerWaits(for: g) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if page.superview === view { page.frame = view.bounds }
    page.appleRow = navigationController?.navigationBar.frame.maxY
  }
}
