import UIKit

// Scenes (launch argument -scene N): 1 My Tasks at the top · 2 scrolled · 3 the status line after sending a comment
// (A: iOS 26's bar above the tab bar) · 4 B: compose in the top bar · 7 touch and hold A: Apple's context menu (held by
// the UI test) · 8 touch and hold B: the sheet
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
  s.append(NSAttributedString(string: " \(t.client) · \(t.status) · ".replacingOccurrences(of: " ", with: "\u{00A0}"), attributes: [.font: f, .foregroundColor: UIColor.secondaryLabel]))
  s.append(NSAttributedString(string: t.due, attributes: [.font: t.when.isEmpty ? f : UIFont.systemFont(ofSize: f.pointSize, weight: .semibold),
                                                          .foregroundColor: t.when == "late" ? UIColor.systemRed : t.when == "today" ? UIColor.systemOrange : UIColor.secondaryLabel]))
  if t.comments > 0 || t.cd != nil || t.prio != nil {
    s.append(NSAttributedString(string: "\n", attributes: [.font: f]))
    if t.comments > 0 {
      s.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))!.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal))))
      s.append(NSAttributedString(string: " \(t.comments)   ", attributes: [.font: f, .foregroundColor: UIColor.secondaryLabel]))
    }
    if let p = t.prio {
      s.append(NSAttributedString(string: p + "   ", attributes: [.font: UIFont.systemFont(ofSize: f.pointSize, weight: .bold), .foregroundColor: p == "Urgent" ? UIColor.systemRed : UIColor.secondaryLabel]))
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
  let d: CGFloat = 24, step: CGFloat = 19
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
  private var pushed = false
  override func viewDidAppear(_ a: Bool) {
    super.viewDidAppear(a)
    if (SCENE == 5 || SCENE == 6) && !pushed { pushed = true; navigationController?.pushViewController(TaskVC(page: SCENE == 6 ? 1 : 0), animated: false); return }
    if SCENE == 8 && !pushed {
      pushed = true
      // (the row held: highlighted the Apple way, then the sheet)
      collectionView.selectItem(at: IndexPath(item: 0, section: 0), animated: false, scrollPosition: [])
      let n = UINavigationController(rootViewController: AttachSheet())
      if let sh = n.sheetPresentationController { sh.detents = [.medium()]; sh.prefersGrabberVisible = true }
      present(n, animated: false)
    }
    if SCENE == 2 { collectionView.setContentOffset(CGPoint(x: 0, y: 420 - collectionView.adjustedContentInset.top), animated: false) }
  }
}
extension MyTasks {
  override func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemsAt ips: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
    guard SCENE == 7 else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
      UIMenu(title: "Attach Files", children: [UIAction(title: "Camera", image: UIImage(systemName: "camera")) { _ in },
                                               UIAction(title: "Photos", image: UIImage(systemName: "photo")) { _ in },
                                               UIAction(title: "Files", image: UIImage(systemName: "doc.badge.arrow.up")) { _ in }])
    }
  }
}
// B: the same choices in a sheet (as today's, without our own shrink)
final class AttachSheet: UITableViewController {
  init() { super.init(style: .insetGrouped) }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() { super.viewDidLoad(); title = "Attach Files"; navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close) }
  override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { 3 }
  override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(); var cfg = c.defaultContentConfiguration()
    let r = [("Camera", "camera"), ("Photos", "photo"), ("Files", "doc.badge.arrow.up")][ip.row]
    cfg.text = r.0; cfg.image = UIImage(systemName: r.1); c.contentConfiguration = cfg; return c
  }
}
extension UIFont { func withWeight(_ w: UIFont.Weight) -> UIFont { UIFont.systemFont(ofSize: pointSize, weight: w) } }
extension UIContextualAction { func then(_ f: (UIContextualAction) -> Void) -> UIContextualAction { f(self); return self } }


// ---------- the task page: pushed (Apple's push, ‹ My Tasks, the edge swipe), Details · Comments ----------
final class TaskVC: UIViewController, UICollectionViewDelegate {
  let t = SECTIONS[0].1[0]
  private var page: Int
  private var cv: UICollectionView!
  private var data: UICollectionViewDiffableDataSource<Int, String>!
  private var cds: AnyObject?
  private let seg = UISegmentedControl(items: ["Details", "Comments  3"])
  init(page: Int) { self.page = page; super.init(nibName: nil, bundle: nil); hidesBottomBarWhenPushed = true }
  required init?(coder: NSCoder) { fatalError() }
  override var canBecomeFirstResponder: Bool { page == 1 }
  private lazy var bar: UIView = {
    // the comment box (as E11 Talk's): Apple's text view in a rounded box, attach on the left, send on the right
    let v = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 60)); v.backgroundColor = .clear
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial)); blur.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(blur)
    let plus = UIButton(type: .system); plus.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
    let box = UITextView(); box.font = .preferredFont(forTextStyle: .body); box.layer.cornerRadius = 18; box.layer.borderWidth = 0.5; box.layer.borderColor = UIColor.separator.cgColor
    box.backgroundColor = .secondarySystemBackground; box.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    box.text = "Looks great — just push the logo a bit up"
    let send = UIButton(type: .system); send.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30)), for: .normal)
    [plus, box, send].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; v.addSubview($0) }
    NSLayoutConstraint.activate([
      blur.leadingAnchor.constraint(equalTo: v.leadingAnchor), blur.trailingAnchor.constraint(equalTo: v.trailingAnchor), blur.topAnchor.constraint(equalTo: v.topAnchor), blur.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: 40),
      plus.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12), plus.centerYAnchor.constraint(equalTo: box.centerYAnchor), plus.widthAnchor.constraint(equalToConstant: 32),
      box.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 8), box.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -8),
      box.topAnchor.constraint(equalTo: v.topAnchor, constant: 8), box.heightAnchor.constraint(equalToConstant: 38),
      send.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -10), send.centerYAnchor.constraint(equalTo: box.centerYAnchor)])
    return v
  }()
  override var inputAccessoryView: UIView? { page == 1 ? bar : nil }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    navigationItem.largeTitleDisplayMode = .never
    seg.selectedSegmentIndex = page
    navigationItem.titleView = seg
    let more = UIMenu(children: [UIAction(title: "Copy link", image: UIImage(systemName: "link")) { _ in },
                                 UIMenu(title: "Attach Files", image: UIImage(systemName: "paperclip"), children: [
                                   UIAction(title: "Camera", image: UIImage(systemName: "camera")) { _ in }, UIAction(title: "Photos", image: UIImage(systemName: "photo.on.rectangle")) { _ in },
                                   UIAction(title: "Files", image: UIImage(systemName: "folder")) { _ in }]),
                                 UIMenu(options: .displayInline, children: [UIAction(title: "Delete task", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in }])])
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "ellipsis"), primaryAction: nil, menu: more)
    var cfg = UICollectionLayoutListConfiguration(appearance: page == 0 ? .insetGrouped : .plain)
    cfg.headerMode = page == 0 ? .supplementary : .none
    cfg.showsSeparators = page == 0
    cfg.backgroundColor = page == 0 ? .systemGroupedBackground : .systemBackground
    cv = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: cfg))
    cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cv.keyboardDismissMode = .interactive
    view.addSubview(cv)
    page == 0 ? details() : comments()
  }
  override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); if #available(iOS 26.0, *) { tabBarController?.bottomAccessory = nil } }
  override func viewDidAppear(_ a: Bool) { super.viewDidAppear(a); if page == 1 { becomeFirstResponder() } }

  // Details: the title, its facts as Apple's rows (each opens its sheet / menu), description, files, subtasks
  private func details() {
    let rows: [(Int, [String])] = [(0, ["title"]), (1, ["Status", "Assignees", "Due", "Priority", "CD review", "Client"]), (2, ["desc"]), (3, ["f1", "f2"]), (4, ["s1", "s2", "add"])]
    let heads = ["", "", "Description", "Files  2", "Subtasks  1 of 2"]
    let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [t] c, ip, id in
      var cfg = UIListContentConfiguration.valueCell()
      c.accessories = []
      switch id {
      case "title":
        var sc = UIListContentConfiguration.subtitleCell(); sc.text = t.title; sc.textProperties.font = .preferredFont(forTextStyle: .title2).withWeight(.bold)
        let m = NSMutableAttributedString(string: "Northline · Winter campaign", attributes: [.font: UIFont.preferredFont(forTextStyle: .footnote), .foregroundColor: UIColor.secondaryLabel])
        sc.secondaryAttributedText = m; sc.textToSecondaryTextVerticalPadding = 6
        sc.image = statusIcon(t); sc.directionalLayoutMargins = .init(top: 4, leading: 4, bottom: 8, trailing: 4)
        c.contentConfiguration = sc; c.backgroundConfiguration = .clear(); return
      case "Status": cfg.text = "Status"; cfg.secondaryText = "In progress"; cfg.image = statusIcon(t)
      case "Assignees":
        cfg.text = "Assignees"; cfg.image = UIImage(systemName: "person.2")
        c.accessories = [.customView(configuration: .init(customView: people(t.people), placement: .trailing(displayed: .always), reservedLayoutWidth: .actual)), .disclosureIndicator()]
        c.contentConfiguration = cfg; return
      case "Due": cfg.text = "Due"; cfg.secondaryText = "Yesterday, 6:00 PM"; cfg.secondaryTextProperties.color = .systemRed; cfg.image = UIImage(systemName: "calendar")
      case "Priority": cfg.text = "Priority"; cfg.secondaryText = "Urgent"; cfg.secondaryTextProperties.color = .systemRed; cfg.image = UIImage(systemName: "flag")
      case "CD review": cfg.text = "CD review"; cfg.secondaryText = "Waiting"; cfg.secondaryTextProperties.color = .systemYellow; cfg.image = UIImage(systemName: "checkmark.shield")
      case "Client": cfg.text = "Client"; cfg.secondaryText = "Northline"; cfg.image = UIImage(systemName: "building.2")
      case "desc":
        cfg = .cell(); cfg.text = "Final key visual for the winter campaign. Use the snow-forest shot, logo top left, headline “Warmth, wherever you go”. Deliver 1:1, 4:5 and 9:16."
        cfg.textProperties.font = .preferredFont(forTextStyle: .body)
        cfg.directionalLayoutMargins = .init(top: 4, leading: 4, bottom: 4, trailing: 4)
        c.contentConfiguration = cfg; c.backgroundConfiguration = .clear(); return
      case "f1", "f2":
        cfg = .subtitleCell(); cfg.text = id == "f1" ? "key-visual-v4.jpg" : "brief-winter.pdf"; cfg.secondaryText = id == "f1" ? "2.4 MB · Leila · Yesterday" : "380 KB · Haris · 3 Nov"
        cfg.image = UIImage(systemName: id == "f1" ? "photo" : "doc.richtext"); cfg.imageProperties.tintColor = id == "f1" ? .systemBlue : .systemRed
        cfg.secondaryTextProperties.color = .secondaryLabel
      case "s1", "s2":
        cfg = .cell(); cfg.text = id == "s1" ? "Pick the hero photo" : "Write the headline options"
        cfg.image = UIImage(systemName: id == "s1" ? "checkmark.circle.fill" : "circle"); cfg.imageProperties.tintColor = id == "s1" ? .systemGreen : .tertiaryLabel
        if id == "s1" { cfg.textProperties.color = .secondaryLabel }
      default: cfg = .cell(); cfg.text = "Add subtask"; cfg.textProperties.color = .tintColor; cfg.image = UIImage(systemName: "plus")
      }
      if ["Status", "Due", "Priority", "CD review", "Client", "f1", "f2"].contains(id) { c.accessories = [.disclosureIndicator()] }
      c.contentConfiguration = cfg
    }
    let head = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { h, _, ip in
      var cfg = UIListContentConfiguration.header(); cfg.text = heads[ip.section]; h.contentConfiguration = cfg
    }
    data = UICollectionViewDiffableDataSource(collectionView: cv) { cv, ip, id in cv.dequeueConfiguredReusableCell(using: cell, for: ip, item: id) }
    data.supplementaryViewProvider = { cv, k, ip in cv.dequeueConfiguredReusableSupplementary(using: head, for: ip) }
    var snap = NSDiffableDataSourceSnapshot<Int, String>()
    for (sct, ids) in rows { snap.appendSections([sct]); snap.appendItems(ids, toSection: sct) }
    data.apply(snap, animatingDifferences: false)
  }
  // Comments: each as Apple's list row — the picture, name and time, the words; the box at the bottom
  private func comments() {
    let cs: [(Person, String, String, String)] = [
      (L, "Leila K", "Yesterday 4:12 PM", "Uploaded v4 — moved the headline lower and warmed up the colours."),
      (H, "Haris", "Yesterday 5:03 PM", "Much better. Can we try the logo a little smaller?"),
      (Y, "Yousef A", "Today 9:20 AM", "Sent for CD review ✓")]
    let cell = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { c, ip, i in
      let (p, n, time, text) = cs[i]
      var cfg = UIListContentConfiguration.subtitleCell()
      let a = NSMutableAttributedString(string: n, attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)])
      a.append(NSAttributedString(string: "  " + time, attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor.secondaryLabel]))
      cfg.attributedText = a; cfg.secondaryText = text
      cfg.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline); cfg.secondaryTextProperties.color = .label
      cfg.textToSecondaryTextVerticalPadding = 4
      cfg.image = UIGraphicsImageRenderer(size: CGSize(width: 34, height: 34)).image { _ in
        p.color.setFill(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 34, height: 34)).fill()
        let at: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.white]
        let sz = (p.ini as NSString).size(withAttributes: at); (p.ini as NSString).draw(at: CGPoint(x: 17 - sz.width / 2, y: 17 - sz.height / 2), withAttributes: at)
      }
      cfg.imageProperties.reservedLayoutSize = CGSize(width: 34, height: 34)
      cfg.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
      c.contentConfiguration = cfg
    }
    let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) { cv, ip, id in cv.dequeueConfiguredReusableCell(using: cell, for: ip, item: id) }
    var snap = NSDiffableDataSourceSnapshot<Int, Int>(); snap.appendSections([0]); snap.appendItems([0, 1, 2]); ds.apply(snap, animatingDifferences: false)
    cds = ds
  }
}
