import UIKit

/* Me and its pages in Apple's navigation (Haris 2026-11-08: "start the me page … me page and its inner pages"):
   · Me is its tab's first screen, as Home: its own Apple navigation in Apple's tab bar, Apple's big title "Me" with its
     line; no bar buttons and no search (Haris: "Nothing", "No search");
   · its pages — My profile, Appearance, About, Shortcuts, Team members and a member, Trash, Content plans and a plan,
     Client Assets — are pushed on it, as the task page: Apple's push and swipe back, Apple's bar (‹ · the name), Apple's
     firm frost with its line, the tab bar staying (as the Clients tab's pages);
   · the rows are iPhone Settings' own: Apple's grouped list, Apple's cells set by Apple's configurations, Apple's
     headers and footers, Apple's ›, value text and switches, Apple's highlight (HomeView.applyMeList). Ours, shown by
     Apple's cells: the coloured icons and the pictures; and the few blocks of our own design (Appearance's phones,
     About's cards, a member's header, a plan's posts) in a cell of Apple's list.
   MeCtl keeps the pages' contents and actions, as before; only where they live and who draws them changed. */
let APPLE_ME = APPLE_NAV

extension Main {
  // (Me in its own Apple navigation — for everyone with a Me tab)
  var meApple: Bool { APPLE_ME && tabKeys.contains("me") }
  // Me's navigation has settled (a push, a pop, the tab tapped again popping everything): the pages no longer in it are
  // gone for the app too — Me's, Client Assets', the Clients list opened from Me
  func meNavShown(_ n: UINavigationController) {
    guard meApple, n === AppleTabs.shared?.meNav else { return }
    let vcs = n.viewControllers
    meCtl.reconcile(vcs)
    if assetsCtl.appleNav === n { assetsCtl.reconcile(vcs) }   // (Client Assets opened over Me)
    if ClientVC.pushed, clientsNavNow === n, !vcs.contains(where: { $0 is ClientVC }) { clientPageGone() }
  }
}

// Me: its tab's first screen
final class MeVC: UIViewController, TabRoot {
  static weak var shared: MeVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); MeVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = .systemGroupedBackground; view = v }
  private(set) weak var h: HomeView?
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = "Me"
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let h = h, h.superview === view { h.tabTop = Main.shared.homeTabTop }
  }
  func adopt(_ v: HomeView) {
    loadViewIfNeeded()
    if let old = h, old !== v, old.superview === view { old.removeFromSuperview() }
    h = v
    if v.superview !== view {
      v.removeFromSuperview()
      v.frame = view.bounds; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(v, at: 0)
    }
    v.isHidden = false; v.transform = .identity
    view.backgroundColor = v.backgroundColor ?? view.backgroundColor
    v.onAppleTitle = { [weak self] t, d in self?.setLine(t, d) }
    v.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    v.useAppleTop()
    setContentScrollView(v.appleScroll, for: .top)
  }
  private var shownLine: String?
  private func setLine(_ t: String, _ d: String) {
    if !t.isEmpty, navigationItem.title != t { navigationItem.title = t }
    guard d != shownLine else { return }
    shownLine = d
    if #available(iOS 26.0, *) {
      navigationItem.subtitle = d.isEmpty ? nil : d
      if d.isEmpty { navigationItem.largeAttributedSubtitle = nil } else {
        var a = AttributedString(d); a.uiKit.font = .systemFont(ofSize: 15); a.uiKit.foregroundColor = .secondaryLabel
        navigationItem.largeAttributedSubtitle = a
      }
    }
  }
}

// a page of Me pushed on its tab: as the Clients tab's pages (tab bar staying, Apple's firm frost, Apple's bar)
final class MePageVC: ClientsPushedVC {
  var onGone: (() -> Void)?
  override init(_ h: HomeView) {
    super.init(h)
    // (a page whose name is its big title on the old page — Content plans opened from Me: its name and line in the bar)
    h.onAppleTitle = { [weak self] t, d in
      guard let self = self, !t.isEmpty else { return }
      self.navigationItem.title = t
      if #available(iOS 26.0, *) { self.navigationItem.subtitle = d.isEmpty ? nil : d }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    // (Me's pages have no ••• of their own: none in the bar)
    if menuItems().isEmpty { navigationItem.rightBarButtonItem = nil }
  }
  override func viewDidDisappear(_ a: Bool) {
    super.viewDidDisappear(a)
    if isMovingFromParent || navigationController == nil { onGone?(); onGone = nil }
  }
  // (a page without a name of its own in the bar — Content plans: its big title's name instead, never an empty name with
  //  a grey square)
  override func setBar(_ t: String, _ sub: String, _ col: UIColor, _ logo: String?, _ ini: String?, _ showLogo: Bool) {
    if t.isEmpty { return }
    super.setBar(t, sub, col, logo, ini, false)
  }
}

// the Clients list opened from Me (Me › Work › Clients — the CD's, who has no Clients tab): pushed on Me, as Me's pages
final class ClientsFromMeVC: ClientsPushedVC {
  var onGone: (() -> Void)?
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = "Clients"
    navigationItem.rightBarButtonItem = nil
  }
  override func setBar(_ t: String, _ sub: String, _ col: UIColor, _ logo: String?, _ ini: String?, _ showLogo: Bool) {}   // ("Clients" only)
  override func viewDidDisappear(_ a: Bool) {
    super.viewDidDisappear(a)
    if isMovingFromParent || navigationController == nil { onGone?(); onGone = nil }
  }
}
