import UIKit

/* TEMPORARY — check build only (Haris 2026-11-07): Home's big title jumps as a task slides in, E11 Talk's doesn't. The
   slide is played 10× slower in the simulator so its film catches every frame of the big title: Home, then Apple's
   parts alone set up as E11 Talk's list is, then the same with Home's date line and bar buttons. Taken out after. */
enum SlowLook {
  static func slow(_ w: UIWindow?, _ on: Bool) { w?.layer.speed = on ? 0.1 : 1 }
  static func run(full: Bool, on host: UIViewController, _ done: @escaping () -> Void) {
    final class ListVC: UIViewController, UITableViewDataSource {
      let t = UITableView(frame: .zero, style: .plain)
      override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        t.frame = view.bounds; t.autoresizingMask = [.flexibleWidth, .flexibleHeight]; t.dataSource = self; t.rowHeight = 72; view.addSubview(t)
      }
      func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { 30 }
      func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell { let c = UITableViewCell(); c.textLabel?.text = "Row \(i.row)"; return c }
    }
    // (as E11 Talk's Groups: title, Apple's search in the bar, big title always)
    let list = ListVC(); list.title = "E11 Day"
    list.navigationItem.largeTitleDisplayMode = .always
    let s = UISearchController(searchResultsController: nil); s.obscuresBackgroundDuringPresentation = false
    list.navigationItem.searchController = s; list.navigationItem.hidesSearchBarWhenScrolling = false
    if full {
      if #available(iOS 26.0, *) { list.navigationItem.subtitle = "Saturday, November 7" }
      list.navigationItem.rightBarButtonItems = [UIBarButtonItem(image: UIImage(systemName: "person.circle"), primaryAction: UIAction { _ in }), UIBarButtonItem(image: UIImage(systemName: "bubble.left.fill"), primaryAction: UIAction { _ in })]
      list.navigationItem.backButtonDisplayMode = .minimal
    }
    let nav = UINavigationController(rootViewController: list); nav.navigationBar.prefersLargeTitles = true
    let tabs = UITabBarController(); tabs.viewControllers = [nav, UIViewController()]
    tabs.modalPresentationStyle = .fullScreen
    host.present(tabs, animated: false) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        let page = UIViewController(); page.view.backgroundColor = .systemBackground; page.title = "KOREA 360"
        page.navigationItem.largeTitleDisplayMode = .never; page.hidesBottomBarWhenPushed = true
        let w = tabs.view.window
        slow(w, true)
        nav.pushViewController(page, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
          nav.popViewController(animated: true)
          DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { slow(w, false); tabs.dismiss(animated: false) { done() } }
        }
      }
    }
  }
}
