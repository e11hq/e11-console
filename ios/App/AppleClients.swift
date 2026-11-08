import UIKit

/* The Clients tab in Apple's navigation (Haris 2026-11-08: "Clients and Client Assets together" — mock-ups
   clients-mockup.png and assets-mockup.png). Every page here follows the locked page of its category:
   · the Clients list is the tab's first screen, as Home: its own Apple navigation in Apple's tab bar, Apple's big title
     "Clients" with its line, Apple's search bar (it searches everything, as Home's), E11 Talk and your photo as Apple's bar
     buttons (Haris: "Talk button on top same as home"), the clients in Apple's list, "+ Add client" as Home's button, Apple's
     own frost untouched;
   · a client's page, a client's Client Assets and a folder are pushed pages, as the task page: Apple's push, Apple's bar
     (‹ · the name in the middle · •••, Apple's own menu), the tab bar hidden once the page has arrived (AppleTabs), each
     thing its own cell of Apple's list, Apple's firm frost with its line.
   The screens' contents are HomeView's, as they were; only where they live and who draws the bar changed. */
let APPLE_CLIENTS = APPLE_NAV

extension Main {
  // (Clients in its own Apple navigation: only for those with a Clients tab — the CD opens the list from Me, the old way)
  var clientsApple: Bool { APPLE_CLIENTS && tabKeys.contains("projects") }
  // the Clients tab's navigation has settled (a push, a pop, the tab tapped again popping everything): what's no longer
  // in it is gone for the app too
  func clientsNavShown(_ n: UINavigationController) {
    guard clientsApple, n === AppleTabs.shared?.clientsNav else { return }
    let vcs = n.viewControllers
    assetsCtl.reconcile(vcs)
    if ClientVC.pushed, !vcs.contains(where: { $0 is ClientVC }) { clientPageGone() }
  }
}

// the Clients tab's first screen
final class ClientsVC: UIViewController, TabRoot, UISearchResultsUpdating, UISearchControllerDelegate {
  static weak var shared: ClientsVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); ClientsVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = .systemGroupedBackground; view = v }
  private var meItem: UIBarButtonItem?, talkItem: UIBarButtonItem?
  private var mePhoto: UIImage?
  private(set) var search: UISearchController?

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = "Clients"
    // your photo and E11 Talk's button, Apple's own bar buttons — exactly as Home's (Haris 2026-11-08)
    let me = UIBarButtonItem(image: BarImage.me(nil, traitCollection), primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.clientsListIfMade?.meTap() })
    me.accessibilityLabel = "Me"
    BarImage.bare(me)
    meItem = me
    let talk = UIBarButtonItem(image: BarImage.talk(traitCollection), primaryAction: UIAction { _ in })
    talk.tintColor = .label
    talk.accessibilityLabel = "E11 Talk"
    talkItem = talk
    navigationItem.rightBarButtonItems = [me, .fixedSpace(0), talk]
    if #available(iOS 17.0, *) { registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: ClientsVC, _: UITraitCollection) in vc.paintBar() } }
    // Apple's search, always in Apple's bar under the big title — the results in the list's own rows (as Home's)
    let s = UISearchController(searchResultsController: nil)
    s.obscuresBackgroundDuringPresentation = false
    s.searchResultsUpdater = self
    s.delegate = self
    s.searchBar.placeholder = "Search tasks, clients or people"
    s.searchBar.autocorrectionType = .no
    search = s
    navigationItem.searchController = s
    navigationItem.hidesSearchBarWhenScrolling = false
    if let h = Main.shared.clientsListIfMade, Main.shared.clientsApple { adopt(h) }
  }
  // (where the tab bar starts, for "+ Add client" and the list's end — as Home's screen does)
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let m = Main.shared
    if let h = m.clientsListIfMade, h.superview === view { h.tabTop = m.homeTabTop }
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
    h.onAppleMe = { [weak self] img in if let img = img { self?.mePhoto = img; self?.paintBar() } }
    h.onAppleResign = { [weak self] in self?.search?.searchBar.resignFirstResponder() }
    h.onAppleFind = { [weak self] q in
      guard let s = self?.search else { return }
      if let q = q { s.isActive = true; s.searchBar.text = q; Main.shared.clientsListIfMade?.appleSearchText(q) } else { s.isActive = false }
    }
    h.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    h.useAppleTop()
    setContentScrollView(h.appleScroll, for: .top)
  }
  func paintBar() { meItem?.image = BarImage.me(mePhoto, traitCollection); talkItem?.image = BarImage.talk(traitCollection) }
  func closeSearch() { if search?.isActive == true { search?.isActive = false } }
  private var shownLine: String?
  private func setLine(_ d: String) {
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
  // ---------- Apple's search: it opened, its words changed, it closed (as Home's) ----------
  func updateSearchResults(for s: UISearchController) { Main.shared.clientsListIfMade?.appleSearchText(s.searchBar.text ?? "") }
  func willPresentSearchController(_ s: UISearchController) { Main.shared.clientsListIfMade?.appleSearchBegin() }
  func didPresentSearchController(_ s: UISearchController) { DispatchQueue.main.async { s.searchBar.becomeFirstResponder() } }
  func willDismissSearchController(_ s: UISearchController) { Main.shared.clientsListIfMade?.appleSearchEnd() }
}

// ---------- a page pushed on the Clients tab: a client's page, a client's Client Assets, a folder ----------
class ClientsPushedVC: UIViewController {
  let h: HomeView
  init(_ h: HomeView) { self.h = h; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(frame: UIScreen.main.bounds); v.backgroundColor = .systemGroupedBackground; view = v }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .never
    navigationItem.backButtonDisplayMode = .minimal
    if h.superview !== view {
      h.removeFromSuperview()
      h.frame = view.bounds; h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(h, at: 0)
    }
    h.isHidden = false; h.transform = .identity
    view.backgroundColor = h.backgroundColor ?? view.backgroundColor
    h.onApplePage = { [weak self] t, sub, col, logo, ini, showLogo in self?.setBar(t, sub, col, logo, ini, showLogo) }
    h.tellApplePage()   // (what it shows already — drawn before this page was made)
    h.useAppleTop()
    // (as the task page: Apple's firm frost with its line)
    if #available(iOS 26.0, *), h.appleScroll.topEdgeEffect.style != .hard { h.appleScroll.topEdgeEffect.style = .hard }
    setContentScrollView(h.appleScroll, for: .top)
    // •••: Apple's own menu, made each time it opens (what the page has now)
    let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(UIMenu.items(self?.menuItems() ?? [])) }]))
    more.accessibilityLabel = "More"
    navigationItem.rightBarButtonItem = more
  }
  func menuItems() -> [CornerMenuItem] { h.menuItems }
  // (no tab bar here once the page has arrived: "+ New task" / "↑ Upload" at the bottom, as the task page's button)
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if h.superview === view {
      h.tabTop = view.bounds.height - max(view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom, 20) + 6
    }
  }
  // the bar's middle: the name (a client's: its colour or logo beside it), and the line under it (Client Assets)
  private var shownBar = ""
  private var logoShown: String?
  private let logoView = UIImageView(), iniLabel = UILabel()
  private var logoMade = false
  func setBar(_ t: String, _ sub: String, _ col: UIColor, _ logo: String?, _ ini: String?, _ showLogo: Bool) {
    let key = "\(t)|\(sub)|\(col)|\(logo ?? "")|\(ini ?? "")|\(showLogo)"
    guard key != shownBar else { return }
    shownBar = key
    navigationItem.title = t
    if #available(iOS 26.0, *) { navigationItem.subtitle = sub.isEmpty ? nil : sub }
    guard showLogo else { navigationItem.titleView = nil; return }
    let name = UILabel(); name.text = t; name.font = .systemFont(ofSize: 17, weight: .semibold); name.textColor = .label; name.lineBreakMode = .byTruncatingTail
    if !logoMade {
      logoMade = true
      logoView.layer.cornerRadius = 7; logoView.layer.cornerCurve = .continuous; logoView.clipsToBounds = true; logoView.contentMode = .scaleAspectFill
      logoView.translatesAutoresizingMaskIntoConstraints = false
      logoView.widthAnchor.constraint(equalToConstant: 22).isActive = true; logoView.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }
    iniLabel.font = .systemFont(ofSize: 9, weight: .bold); iniLabel.textColor = .white; iniLabel.textAlignment = .center; iniLabel.text = ini
    if iniLabel.superview !== logoView { logoView.addSubview(iniLabel) }
    iniLabel.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
    if logo != logoShown { logoShown = logo; logoView.image = nil; logoView.contentMode = .scaleAspectFill }
    if logoView.image == nil { logoView.backgroundColor = col; iniLabel.isHidden = false }
    if let p = logo, logoView.image == nil {
      FeedLoader.shared.image(p) { [weak self] img in
        DispatchQueue.main.async { guard let self = self, self.logoShown == p, let img = img else { return }; LogoLook.put(img, key: p, in: self.logoView); self.iniLabel.isHidden = true }
      }
    }
    let s = UIStackView(arrangedSubviews: [logoView, name]); s.spacing = 8; s.alignment = .center
    navigationItem.titleView = s
  }
}

// a client's page
final class ClientVC: ClientsPushedVC {
  static weak var shared: ClientVC?
  static var pushed = false   // (one is in the Clients tab's navigation — set as it's pushed, cleared as it goes)
  override init(_ h: HomeView) { super.init(h); ClientVC.shared = self; ClientVC.pushed = true }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidDisappear(_ a: Bool) {
    super.viewDidDisappear(a)
    // (‹, the swipe back, the tab tapped again: gone — the app's own state follows)
    if isMovingFromParent || navigationController == nil { if ClientVC.pushed { Main.shared.clientPageGone() } }
  }
}

// a client's Client Assets, or a folder (AssetsCtl's screens)
final class AssetsVC: ClientsPushedVC, UISearchResultsUpdating {
  var onGone: (() -> Void)?
  var onSearch: ((String) -> Void)?
  private var search: UISearchController?
  override func viewDidLoad() {
    super.viewDidLoad()
    // (a client's Client Assets: Apple's search for its files, under the bar — instead of the box of ours)
    if h.assets == "client" {
      let s = UISearchController(searchResultsController: nil)
      s.obscuresBackgroundDuringPresentation = false
      s.searchResultsUpdater = self
      s.searchBar.autocorrectionType = .no
      search = s
      navigationItem.searchController = s
      navigationItem.hidesSearchBarWhenScrolling = false
      if #available(iOS 16.0, *) { navigationItem.preferredSearchBarPlacement = .stacked }
    }
  }
  func placeholder(_ p: String) { search?.searchBar.placeholder = p }
  override func menuItems() -> [CornerMenuItem] { h.assetsMenu?() ?? [] }
  func updateSearchResults(for s: UISearchController) { onSearch?(s.searchBar.text ?? "") }
  override func viewDidDisappear(_ a: Bool) {
    super.viewDidDisappear(a)
    if isMovingFromParent || navigationController == nil { onGone?(); onGone = nil }
  }
}

// a list block (the clients' group, Client Assets' folders, files…) in a cell of Apple's list: drawn the whole width, as on
// the page — the cell keeps the list's 16 pt sides for the cards, the block reaches past them to the edges
final class BlockWrap: UIView {
  let block: HomeBlock
  init(_ b: HomeBlock) { block = b; super.init(frame: .zero); clipsToBounds = false; addSubview(b) }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    if block.superview !== self { addSubview(block) }
    let f = bounds.insetBy(dx: -16, dy: 0)
    block.bounds = CGRect(origin: .zero, size: f.size); block.center = CGPoint(x: f.midX, y: f.midY)
  }
}

// the page's ••• as Apple's own menu (the same choices the shared ••• had)
extension UIMenu {
  static func items(_ list: [CornerMenuItem]) -> [UIMenuElement] {
    list.map { it -> UIMenuElement in
      if it.inline || !it.children.isEmpty {
        return UIMenu(title: it.title, image: it.symbol.flatMap { UIImage(systemName: $0) }, options: it.inline ? .displayInline : [], children: items(it.children))
      }
      let run = it.run
      return UIAction(title: it.title, image: it.symbol.flatMap { UIImage(systemName: $0) }, attributes: it.destructive ? .destructive : []) { _ in run?() }
    }
  }
}
