import UIKit

// Scenes (launch argument -scene N): 1 My Tasks at the top · 2 scrolled · 3 the status line after sending a comment
let SCENE = max(1, UserDefaults.standard.integer(forKey: "scene"))

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let c = UISceneConfiguration(name: nil, sessionRole: s.role); c.delegateClass = Scene.self; return c
  }
}
final class Scene: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ s: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let ws = s as? UIWindowScene else { return }
    let w = UIWindow(windowScene: ws)
    let tabs = UITabBarController()
    func nav(_ vc: UIViewController, _ title: String, _ img: String) -> UINavigationController {
      let n = UINavigationController(rootViewController: vc); n.navigationBar.prefersLargeTitles = true
      n.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: img), selectedImage: UIImage(systemName: img + ".fill")); return n
    }
    let blank = { (t: String) -> UIViewController in let v = UIViewController(); v.title = t; v.view.backgroundColor = .systemGroupedBackground; return v }
    tabs.viewControllers = [nav(blank("Home"), "Home", "house"), nav(MyTasks(), "My Tasks", "checkmark.circle"), nav(blank("Inbox"), "Inbox", "tray"),
                            nav(blank("Clients"), "Clients", "person.2"), nav(blank("Me"), "Me", "person.crop.circle")]
    tabs.selectedIndex = 1
    w.rootViewController = tabs; window = w; w.makeKeyAndVisible()
  }
}

struct Task { let title: String; let client: String; let due: String; let late: Bool }
let SECTIONS: [(String, [Task])] = [
  ("Overdue", [Task(title: "Winter campaign — final key visual", client: "Northline", due: "Yesterday", late: true),
               Task(title: "Approve shoot call sheet", client: "Southgate", due: "Tue", late: true)]),
  ("Today", [Task(title: "Instagram carousel: 5 frames", client: "Northline", due: "Today", late: false),
             Task(title: "Reply to client on logo colours", client: "Bluebay", due: "Today", late: false),
             Task(title: "Upload reel cut v3", client: "Southgate", due: "Today", late: false)]),
  ("This week", [Task(title: "Monthly content plan — December", client: "Northline", due: "Thu", late: false),
                 Task(title: "Storyboard for launch video", client: "Bluebay", due: "Fri", late: false),
                 Task(title: "Website banner set (4 sizes)", client: "Cedar Homes", due: "Fri", late: false),
                 Task(title: "Press kit photos selection", client: "Southgate", due: "Sat", late: false)]),
  ("Later", [Task(title: "Quarterly report deck", client: "Northline", due: "18 Nov", late: false),
             Task(title: "Brand guidelines update", client: "Cedar Homes", due: "21 Nov", late: false),
             Task(title: "New year greetings post", client: "Bluebay", due: "28 Dec", late: false)]),
]

final class MyTasks: UICollectionViewController {
  private var data: UICollectionViewDiffableDataSource<Int, String>!
  init() {
    var cfg = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
    cfg.headerMode = .supplementary
    cfg.trailingSwipeActionsConfigurationProvider = { _ in
      UISwipeActionsConfiguration(actions: [UIContextualAction(style: .normal, title: "Done") { _, _, d in d(true) }.then { $0.backgroundColor = .systemGreen; $0.image = UIImage(systemName: "checkmark") }])
    }
    super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: cfg))
  }
  required init?(coder: NSCoder) { fatalError() }
  private let status = UILabel(), sub = UILabel()
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "My Tasks"
    // search and the All / Done scope, as Apple's search bar does
    let sc = UISearchController(searchResultsController: nil)
    sc.searchBar.placeholder = "Search tasks"
    sc.searchBar.scopeButtonTitles = ["All", "Done"]
    sc.automaticallyShowsScopeBar = false
    sc.searchBar.showsScopeBar = true
    navigationItem.searchController = sc
    navigationItem.hidesSearchBarWhenScrolling = false
    // filters: Apple's filter button with a menu (as Mail)
    let filters = UIMenu(title: "Filter", children: [
      UIAction(title: "Assigned to me", image: UIImage(systemName: "person"), state: .on) { _ in },
      UIAction(title: "Due this week", image: UIImage(systemName: "calendar")) { _ in },
      UIAction(title: "High priority", image: UIImage(systemName: "flag")) { _ in },
      UIAction(title: "In review", image: UIImage(systemName: "checkmark.shield")) { _ in }])
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "line.3.horizontal.decrease"), primaryAction: nil, menu: filters)
    // the bottom toolbar: the status line in the middle (as Mail), compose on the right
    status.font = .systemFont(ofSize: 12, weight: .semibold); status.textAlignment = .center
    sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabel; sub.textAlignment = .center
    if SCENE == 3 { status.text = "Comment sent"; sub.text = "Winter campaign — final key visual" }
    else { status.text = "Updated Just Now"; sub.text = "12 open tasks" }
    let st = UIStackView(arrangedSubviews: [status, sub]); st.axis = .vertical; st.spacing = 0
    let mid = UIBarButtonItem(customView: st)
    if #available(iOS 26.0, *) { mid.hidesSharedBackground = true }
    toolbarItems = [.flexibleSpace(), mid, .flexibleSpace(),
                    UIBarButtonItem(title: nil, image: UIImage(systemName: "square.and.pencil"), primaryAction: UIAction { _ in }, menu: nil)]
    navigationController?.isToolbarHidden = false

    let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { c, ip, id in
      let t = SECTIONS[ip.section].1[ip.item]
      var cfg = UIListContentConfiguration.subtitleCell()
      cfg.text = t.title
      cfg.secondaryText = "\(t.client) · \(t.due)"
      cfg.secondaryTextProperties.color = t.late ? .systemRed : .secondaryLabel
      cfg.image = UIImage(systemName: "circle"); cfg.imageProperties.tintColor = .tertiaryLabel
      cfg.textToSecondaryTextVerticalPadding = 3
      c.contentConfiguration = cfg
    }
    let head = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { h, _, ip in
      var cfg = UIListContentConfiguration.header()
      cfg.text = SECTIONS[ip.section].0 + "  \(SECTIONS[ip.section].1.count)"
      h.contentConfiguration = cfg
    }
    data = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, id in cv.dequeueConfiguredReusableCell(using: cell, for: ip, item: id) }
    data.supplementaryViewProvider = { cv, k, ip in cv.dequeueConfiguredReusableSupplementary(using: head, for: ip) }
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    for (i, s) in SECTIONS.enumerated() { snap.appendSections([i]); snap.appendItems(s.1.map { s.0 + $0.title }, toSection: i) }
    data.apply(snap, animatingDifferences: false)
  }
  override func viewDidAppear(_ a: Bool) {
    super.viewDidAppear(a)
    if SCENE == 2 { collectionView.setContentOffset(CGPoint(x: 0, y: 420 - collectionView.adjustedContentInset.top), animated: false) }
  }
}
extension UIContextualAction { func then(_ f: (UIContextualAction) -> Void) -> UIContextualAction { f(self); return self } }
