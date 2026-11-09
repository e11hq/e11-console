import UIKit

/* The Inbox as its own screen in Apple's tab container (Haris 2026-11-08 — it follows Home, as My Tasks): its tab is its
   own navigation with this screen at its root. Apple's bar from the start: the big title "Inbox" with its line under it
   (how many unread), "Mark all read" (or "Mark all unread", asked first) and your photo as Apple's own bar buttons. No
   search (Haris). All / Unread / Mentions stay as Mail's buttons, at the top of Apple's list, scrolling away with it as
   Mail's do (Haris: "Same as mail"); the rows in Apple's list, edge to edge as Mail's, with Apple's own swipe (Read /
   Unread). "+ New task" as before. */
let APPLE_INBOX = APPLE_NAV

// a tab's first screen with its own Apple navigation (Home, My Tasks, the Inbox)
protocol TabRoot: UIViewController {}
extension HomeVC: TabRoot {}
extension MyTasksVC: TabRoot {}

final class InboxVC: UIViewController, TabRoot {
  static weak var shared: InboxVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); InboxVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = .systemGroupedBackground; view = v }
  private var meItem: UIBarButtonItem?
  private var markItem: UIBarButtonItem?
  private var mePhoto: UIImage?
  private var markKind = "", markText = ""

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = "Inbox"
    let me = UIBarButtonItem(image: BarImage.me(nil, traitCollection), primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.inboxIfMade?.meTap() })
    me.accessibilityLabel = "Me"
    BarImage.bare(me)
    meItem = me
    // "Mark all read" / "Mark all unread": Apple's own bar button with its words
    let mark = UIBarButtonItem(title: "Mark all read", primaryAction: UIAction { [weak self] _ in
      guard let self = self, !self.markKind.isEmpty else { return }
      Main.shared.inboxIfMade?.cornerTap(self.markKind)
    })
    mark.tintColor = .label
    mark.accessibilityIdentifier = "mark-all-read"
    markItem = mark
    navigationItem.rightBarButtonItems = [me]
    if #available(iOS 17.0, *) { registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: InboxVC, _: UITraitCollection) in vc.paintMe() } }
    // (its screen in it from the start — made now if it wasn't: the tab never comes up empty, and Apple's bar has its list
    //  before the first look — Haris 2026-11-08: a black flash, the big title cut, on each tab's first open)
    BigLine.prime(self, "inbox")   // (its line there before it first shows, as Home's date)
    if APPLE_INBOX { adopt(Main.shared.inboxView) } else if let h = Main.shared.inboxIfMade { adopt(h) }
  }
  // (where the tab bar starts, for "+ New task" and the list's end — as Home's screen does)
  // (its list drawn from what the phone kept before it first shows — never an empty tab: Haris 2026-11-08)
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    Main.shared.drawBeforeShow("inbox")
  }
  override func viewDidAppear(_ a: Bool) {
    super.viewDidAppear(a)
    // (Apple's bar told this page's list again each time it shows — on the phone the bar was left following another, empty
    //  list in the page and the big title stuck; the cause not found: Haris's exception, 2026-11-09 19:15)
    if let h = Main.shared.inboxIfMade { setContentScrollView(h.appleScroll, for: .top) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let m = Main.shared
    if let h = m.inboxIfMade, h.superview === view { h.tabTop = m.homeTabTop }
  }
  func adopt(_ h: HomeView) {
    loadViewIfNeeded()
    if h.superview !== view {
      h.removeFromSuperview()
      h.frame = view.bounds; h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(h, at: 0)
    }
    view.backgroundColor = h.backgroundColor ?? view.backgroundColor
    h.onAppleTitle = { [weak self] _, d in self?.setLine(d) }
    h.onAppleMe = { [weak self] img in if let img = img { self?.mePhoto = img; self?.paintMe() } }
    h.onAppleCorner = { [weak self, weak h] in self?.showMark(h?.corner()) }
    h.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    h.useAppleTop()
    setContentScrollView(h.appleScroll, for: .top)
    showMark(h.corner())
  }
  func paintMe() { meItem?.image = BarImage.me(mePhoto, traitCollection) }
  var markShown: String { markKind }   // (for the self-test: "read", "unread" or "" — the bar button showing)
  // Mark all read (unread ones in the list) or Mark all unread (none unread, rows in the list) — or neither
  private func showMark(_ c: (kind: String, text: String, frame: CGRect)?) {
    let kind = c.map { $0.kind == "read" || $0.kind == "unread" ? $0.kind : "" } ?? ""
    let text = c?.text ?? ""
    guard kind != markKind || text != markText else { return }
    markKind = kind; markText = text
    guard let me = meItem, let mark = markItem else { return }
    if kind.isEmpty { navigationItem.rightBarButtonItems = [me]; return }
    mark.title = c?.text
    navigationItem.rightBarButtonItems = [me, .fixedSpace(0), mark]
  }
  private var shownLine: String?
  private func setLine(_ d: String) {
    guard d != shownLine else { return }
    shownLine = d
    BigLine.set(self, d, "inbox")
  }
}
