import UIKit

/* The Clients tab in Apple's navigation (Haris 2026-11-08: "Clients and Client Assets together" — mock-ups
   clients-mockup.png and assets-mockup.png). Every page here follows the locked page of its category:
   · the Clients list is the tab's first screen, as Home: its own Apple navigation in Apple's tab bar, Apple's big title
     "Clients" with its line, Apple's search bar (it searches everything, as Home's), E11 Talk and your photo as Apple's bar
     buttons (Haris: "Talk button on top same as home"), the clients in Apple's list, "+ Add client" as Home's button, Apple's
     own frost untouched;
   · a client's page, a client's Client Assets and a folder are pushed pages, as the task page: Apple's push, Apple's bar
     (‹ · the name in the middle · •••, Apple's own menu), the tab bar staying under them (Haris 2026-11-08 — only a task or a reply hides it), each
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
    // (its list in it from the start, as the Inbox's — Haris 2026-11-08)
    BigLine.prime(self, "clients")
    if Main.shared.clientsApple { adopt(Main.shared.clientsListMade()) }
  }
  // (where the tab bar starts, for "+ Add client" and the list's end — as Home's screen does)
  // (its list drawn from what the phone kept before it first shows — never an empty tab: Haris 2026-11-08)
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    Main.shared.drawBeforeShow("projects")
  }
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
    BigLine.set(self, d, "clients")
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
  override func viewWillAppear(_ a: Bool) {
    super.viewWillAppear(a)
    // (over the app's own navigation — Client Assets opened from Me: Apple's bar shown, as over a task)
    if navigationController?.isNavigationBarHidden == true { navigationController?.setNavigationBarHidden(false, animated: a) }
  }
  // (the tab bar stays under these pages — Haris 2026-11-08: "+ New task" / "↑ Upload" above it, as on the tab's first page)
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if h.superview === view { h.tabTop = Main.shared.homeTabTop }
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
final class AssetsVC: ClientsPushedVC, UISearchResultsUpdating, UISearchControllerDelegate {
  var onGone: (() -> Void)?
  var onSearch: ((String) -> Void)?
  private var search: UISearchController?
  override init(_ h: HomeView) {
    super.init(h)
    // (All Client Assets: "Client Assets" and its line, "13 clients · 32 files", in the bar's middle)
    if h.assets == "all" {
      // (set only when it changes: set again on every redraw — the page drawn again as it arrives or comes back — Apple's bar
      //  laid itself out again mid-slide and its search box came in late: Haris 2026-11-08)
      h.onAppleTitle = { [weak self] t, d in
        guard let self = self else { return }
        if self.navigationItem.title != t { self.navigationItem.title = t }
        if #available(iOS 26.0, *) { let sub: String? = d.isEmpty ? nil : d; if self.navigationItem.subtitle != sub { self.navigationItem.subtitle = sub } }
      }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    if h.assets == "all" {
      navigationItem.rightBarButtonItem = nil
      let s = UISearchController(searchResultsController: nil)
      s.obscuresBackgroundDuringPresentation = false
      s.searchResultsUpdater = self; s.delegate = self
      s.searchBar.placeholder = "Search every client’s files"; s.searchBar.autocorrectionType = .no
      search = s
      navigationItem.searchController = s
      navigationItem.hidesSearchBarWhenScrolling = false
      if #available(iOS 16.0, *) { navigationItem.preferredSearchBarPlacement = .stacked }
      return
    }
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
  func placeholder(_ p: String) { if search?.searchBar.placeholder != p { search?.searchBar.placeholder = p } }   // (only when it changes — as the title)
  // (All Client Assets: "Client Assets" and its line come from its title — no client name or logo square in the bar's
  //  middle: an empty name with a grey square stood over it, the title never showing — Haris 2026-11-08 video)
  override func setBar(_ t: String, _ sub: String, _ col: UIColor, _ logo: String?, _ ini: String?, _ showLogo: Bool) {
    if h.assets == "all" { return }
    super.setBar(t, sub, col, logo, ini, showLogo)
  }
  override func menuItems() -> [CornerMenuItem] { h.assetsMenu?() ?? [] }
  func updateSearchResults(for s: UISearchController) { if h.assets == "all" { h.appleSearchText(s.searchBar.text ?? "") } else { onSearch?(s.searchBar.text ?? "") } }
  func willPresentSearchController(_ s: UISearchController) { if h.assets == "all" { h.appleSearchBegin() } }
  func didPresentSearchController(_ s: UISearchController) { DispatchQueue.main.async { s.searchBar.becomeFirstResponder() } }
  func willDismissSearchController(_ s: UISearchController) { if h.assets == "all" { h.appleSearchEnd() } }
  override func viewDidDisappear(_ a: Bool) {
    super.viewDidDisappear(a)
    if isMovingFromParent || navigationController == nil { onGone?(); onGone = nil }
  }
}

// Client Assets as a tab (the Office Admin's — Haris 2026-11-08, mock-up assets-main-mockup.png): its first screen, as
// Home — Apple's big title "Client Assets" with its line, Apple's search (every client's files), Talk and your photo, the
// clients' cards in Apple's list, + Add client; a client's Client Assets and a folder pushed on it
final class AssetsTabVC: UIViewController, TabRoot, UISearchResultsUpdating, UISearchControllerDelegate {
  static weak var shared: AssetsTabVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); AssetsTabVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = .systemGroupedBackground; view = v }
  private(set) weak var h: HomeView?
  private var meItem: UIBarButtonItem?, talkItem: UIBarButtonItem?
  private var mePhoto: UIImage?
  private var search: UISearchController?
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = "Client Assets"
    BigLine.prime(self, "assetsTab")
    let me = UIBarButtonItem(image: BarImage.me(nil, traitCollection), primaryAction: UIAction { [weak self] _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); self?.h?.meTap() })
    me.accessibilityLabel = "Me"
    BarImage.bare(me)
    meItem = me
    let talk = UIBarButtonItem(image: BarImage.talk(traitCollection), primaryAction: UIAction { _ in })
    talk.tintColor = .label; talk.accessibilityLabel = "E11 Talk"
    talkItem = talk
    navigationItem.rightBarButtonItems = [me, .fixedSpace(0), talk]
    if #available(iOS 17.0, *) { registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: AssetsTabVC, _: UITraitCollection) in vc.paintBar() } }
    let s = UISearchController(searchResultsController: nil)
    s.obscuresBackgroundDuringPresentation = false
    s.searchResultsUpdater = self; s.delegate = self
    s.searchBar.placeholder = "Search every client’s files"; s.searchBar.autocorrectionType = .no
    search = s
    navigationItem.searchController = s
    navigationItem.hidesSearchBarWhenScrolling = false
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
    v.onAppleTitle = { [weak self] _, d in self?.setLine(d) }
    v.onAppleMe = { [weak self] img in if let img = img { self?.mePhoto = img; self?.paintBar() } }
    v.onAppleResign = { [weak self] in self?.search?.searchBar.resignFirstResponder() }
    v.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    v.useAppleTop()
    setContentScrollView(v.appleScroll, for: .top)
  }
  func paintBar() { meItem?.image = BarImage.me(mePhoto, traitCollection); talkItem?.image = BarImage.talk(traitCollection) }
  private var shownLine: String?
  private func setLine(_ d: String) {
    guard d != shownLine else { return }
    shownLine = d
    BigLine.set(self, d, "assetsTab")
  }
  func updateSearchResults(for s: UISearchController) { h?.appleSearchText(s.searchBar.text ?? "") }
  func willPresentSearchController(_ s: UISearchController) { h?.appleSearchBegin() }
  func didPresentSearchController(_ s: UISearchController) { DispatchQueue.main.async { s.searchBar.becomeFirstResponder() } }
  func willDismissSearchController(_ s: UISearchController) { h?.appleSearchEnd() }
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
