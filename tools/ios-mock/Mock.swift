import UIKit

// Scenes (launch argument -scene N): 1 My Tasks at the top · 2 scrolled · 3 the status line after sending a comment
// (A: iOS 26's bar above the tab bar) · 4 B: compose in the top bar
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
    // A: iOS 26's own accessory bar above the tab bar (as Music's Now Playing): the status line and compose
    if SCENE != 4, #available(iOS 26.0, *) {
      let v = UIView()
      let status = UILabel(), sub = UILabel()
      status.font = .systemFont(ofSize: 13, weight: .semibold); sub.font = .systemFont(ofSize: 11.5); sub.textColor = .secondaryLabel
      if SCENE == 3 { status.text = "Comment sent"; sub.text = "Winter campaign — final key visual" } else { status.text = "Updated Just Now"; sub.text = "12 open tasks" }
      let st = UIStackView(arrangedSubviews: [status, sub]); st.axis = .vertical; st.translatesAutoresizingMaskIntoConstraints = false
      let b = UIButton(type: .system); b.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
      b.translatesAutoresizingMaskIntoConstraints = false
      v.addSubview(st); v.addSubview(b)
      NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20), st.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                                   b.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16), b.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
      tabs.bottomAccessory = UITabAccessory(contentView: v)
      tabs.tabBarMinimizeBehavior = .onScrollDown
    }
    w.rootViewController = tabs; window = w; w.makeKeyAndVisible()
  }
}

// (made-up tasks, the details today's My Tasks shows: status, client colour, status name, due, comments, CD chip,
//  priority, assignees)
struct Person { let ini: String; let color: UIColor; let done: Bool }
struct Task { let title: String; let client: String; let cc: UIColor; let status: String; let kind: String; let sc: UIColor
  let due: String; let when: String; let comments: Int; let cd: String?; let prio: String?; let people: [Person] }
let NL = UIColor.systemBlue, SG = UIColor.systemRed, BB = UIColor.systemTeal, CH = UIColor.systemOrange
let H = Person(ini: "HS", color: .systemPink, done: false), L = Person(ini: "LK", color: .systemPurple, done: false)
let Y = Person(ini: "YA", color: .systemIndigo, done: true), S = Person(ini: "SM", color: .systemGreen, done: false)
let SECTIONS: [(String, [Task])] = [
  ("Overdue", [Task(title: "Winter campaign — final key visual", client: "Northline", cc: NL, status: "In progress", kind: "half", sc: .systemBlue, due: "Yesterday", when: "late", comments: 3, cd: "CD Review", prio: "Urgent", people: [H, Y]),
               Task(title: "Approve shoot call sheet", client: "Southgate", cc: SG, status: "To do", kind: "todo", sc: .systemGray, due: "Tue", when: "late", comments: 0, cd: nil, prio: "P2", people: [L])]),
  ("Today", [Task(title: "Instagram carousel: 5 frames", client: "Northline", cc: NL, status: "In progress", kind: "half", sc: .systemBlue, due: "Today", when: "today", comments: 1, cd: "✓ CD Approved", prio: nil, people: [S, H]),
             Task(title: "Reply to client on logo colours", client: "Bluebay", cc: BB, status: "Waiting", kind: "near", sc: .systemOrange, due: "Today", when: "today", comments: 0, cd: nil, prio: nil, people: [H]),
             Task(title: "Upload reel cut v3", client: "Southgate", cc: SG, status: "To do", kind: "todo", sc: .systemGray, due: "Today", when: "today", comments: 5, cd: nil, prio: "P1", people: [Y, L, S])]),
  ("This week", [Task(title: "Monthly content plan — December", client: "Northline", cc: NL, status: "To do", kind: "todo", sc: .systemGray, due: "Thu", when: "", comments: 2, cd: nil, prio: nil, people: [H]),
                 Task(title: "Storyboard for launch video", client: "Bluebay", cc: BB, status: "In progress", kind: "half", sc: .systemBlue, due: "Fri", when: "", comments: 0, cd: nil, prio: nil, people: [L, H]),
                 Task(title: "Website banner set (4 sizes)", client: "Cedar Homes", cc: CH, status: "To do", kind: "todo", sc: .systemGray, due: "Fri", when: "", comments: 0, cd: nil, prio: nil, people: [S])]),
]
func statusIcon(_ t: Task) -> UIImage? {
  let name = t.kind == "todo" ? "circle.dashed" : t.kind == "half" ? "circle.lefthalf.filled" : "circle.inset.filled"
  return UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium))?.withTintColor(t.sc, renderingMode: .alwaysOriginal)
}
func meta(_ t: Task) -> NSAttributedString {
  let f = UIFont.preferredFont(forTextStyle: .footnote)
  let s = NSMutableAttributedString()
  let dot = NSTextAttachment(image: UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in t.cc.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 8, height: 8), cornerRadius: 2).fill() })
  dot.bounds = CGRect(x: 0, y: 1, width: 8, height: 8)
  s.append(NSAttributedString(attachment: dot))
  s.append(NSAttributedString(string: " \(t.client) · \(t.status) · ", attributes: [.font: f, .foregroundColor: UIColor.secondaryLabel]))
  s.append(NSAttributedString(string: t.due, attributes: [.font: t.when.isEmpty ? f : UIFont.systemFont(ofSize: f.pointSize, weight: .semibold),
                                                          .foregroundColor: t.when == "late" ? UIColor.systemRed : t.when == "today" ? UIColor.systemOrange : UIColor.secondaryLabel]))
  if let p = t.prio {
    s.append(NSAttributedString(string: " · ", attributes: [.font: f, .foregroundColor: UIColor.secondaryLabel]))
    s.append(NSAttributedString(string: p, attributes: [.font: UIFont.systemFont(ofSize: f.pointSize, weight: .bold), .foregroundColor: p == "Urgent" ? UIColor.systemRed : UIColor.secondaryLabel]))
  }
  if t.comments > 0 || t.cd != nil {
    s.append(NSAttributedString(string: "\n", attributes: [.font: f]))
    if t.comments > 0 {
      s.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))!.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal))))
      s.append(NSAttributedString(string: " \(t.comments)   ", attributes: [.font: f, .foregroundColor: UIColor.secondaryLabel]))
    }
    if let cd = t.cd {
      let col: UIColor = cd.hasPrefix("✓") ? .systemGreen : .systemYellow
      let cf = UIFont.systemFont(ofSize: f.pointSize - 2.5, weight: .bold)
      let ts = (cd as NSString).size(withAttributes: [.font: cf]), size = CGSize(width: ceil(ts.width) + 12, height: ceil(ts.height) + 4)
      let pill = UIGraphicsImageRenderer(size: size).image { _ in
        col.withAlphaComponent(0.16).setFill(); UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).fill()
        (cd as NSString).draw(at: CGPoint(x: 6, y: 2), withAttributes: [.font: cf, .foregroundColor: col])
      }
      let a = NSTextAttachment(image: pill); a.bounds = CGRect(x: 0, y: (f.capHeight - size.height) / 2, width: size.width, height: size.height)
      s.append(NSAttributedString(attachment: a))
    }
  }
  return s
}
// the assignees: Apple's own monogram-style circles, overlapping (a green tick: their part done)
func people(_ ps: [Person]) -> UIView {
  let d: CGFloat = 24, step: CGFloat = 17
  let shown = Array(ps.prefix(2))
  let v = UIView(frame: CGRect(x: 0, y: 0, width: d + CGFloat(shown.count - 1) * step + (ps.count > 2 ? 22 : 0) + 2, height: d + 2))
  for (i, p) in shown.enumerated().reversed() {   // (the first one on top)
    let c = UILabel(frame: CGRect(x: CGFloat(i) * step, y: 1, width: d, height: d))
    c.text = p.ini; c.font = .systemFont(ofSize: 9.5, weight: .semibold); c.textColor = .white; c.textAlignment = .center
    c.backgroundColor = p.color; c.layer.cornerRadius = d / 2; c.clipsToBounds = true
    c.layer.borderWidth = 2; c.layer.borderColor = UIColor.secondarySystemGroupedBackground.cgColor
    v.addSubview(c)
    if p.done {
      let t = UIImageView(image: UIImage(systemName: "checkmark.circle.fill")); t.tintColor = .systemGreen
      t.backgroundColor = .secondarySystemGroupedBackground; t.layer.cornerRadius = 6
      t.frame = CGRect(x: CGFloat(i) * step + d - 10, y: d - 9, width: 12, height: 12); v.addSubview(t)
    }
  }
  if ps.count > 2 {
    let m = UILabel(frame: CGRect(x: CGFloat(shown.count - 1) * step + d + 3, y: 1, width: 22, height: d)); m.text = "+\(ps.count - 2)"
    m.font = .systemFont(ofSize: 11, weight: .semibold); m.textColor = .secondaryLabel; v.addSubview(m)
  }
  return v
}
func prioView(_ p: String) -> UIView {
  let l = UILabel(); l.text = " \(p) "; l.font = .systemFont(ofSize: 11, weight: .bold)
  let urgent = p == "Urgent"
  l.textColor = urgent ? .systemRed : .secondaryLabel; l.backgroundColor = (urgent ? UIColor.systemRed : UIColor.systemGray).withAlphaComponent(0.15)
  l.layer.cornerRadius = 5; l.clipsToBounds = true; l.sizeToFit(); l.frame.size.height = 18; l.frame.size.width += 4; l.textAlignment = .center
  return l
}

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
    toolbarItems = nil
    if SCENE == 4 {
      navigationItem.rightBarButtonItems = [UIBarButtonItem(title: nil, image: UIImage(systemName: "square.and.pencil"), primaryAction: UIAction { _ in }, menu: nil),
                                            UIBarButtonItem(title: nil, image: UIImage(systemName: "line.3.horizontal.decrease"), primaryAction: nil, menu: filters)]
    }

    let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { c, ip, id in
      let t = SECTIONS[ip.section].1[ip.item]
      var cfg = UIListContentConfiguration.subtitleCell()
      cfg.text = t.title
      cfg.textProperties.font = .preferredFont(forTextStyle: .callout).withWeight(.semibold)
      cfg.secondaryAttributedText = meta(t)
      cfg.image = statusIcon(t)
      cfg.textToSecondaryTextVerticalPadding = 4
      cfg.directionalLayoutMargins.top = 10; cfg.directionalLayoutMargins.bottom = 10
      c.contentConfiguration = cfg
      var acc: [UICellAccessory] = []
      acc.append(.customView(configuration: .init(customView: people(t.people), placement: .trailing(displayed: .always), reservedLayoutWidth: .actual)))
      c.accessories = acc
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
extension UIFont { func withWeight(_ w: UIFont.Weight) -> UIFont { UIFont.systemFont(ofSize: pointSize, weight: w) } }
extension UIContextualAction { func then(_ f: (UIContextualAction) -> Void) -> UIContextualAction { f(self); return self } }
