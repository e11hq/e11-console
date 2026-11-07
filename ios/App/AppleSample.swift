import UIKit

/* The self-test only — never shown in the app (Haris 2026-11-07): a screen made of Apple's parts alone, none of ours —
   Apple's navigation, Apple's list, a big title with a date under it, Apple's search (its 🔍 in the bar as Home's, or its plain field as
   E11 Talk's), the results in the same list — opened with its search active and measured as Home's is: where the search field ends, how tall Apple's
   bar stays, where the results start. Side by side with Home, it shows whether the gap above Home's results is Apple's
   own way or something of ours. */
final class AppleSampleList: UITableViewController, UISearchResultsUpdating {
  // (two kinds, both with the results in this same list as E11 Talk: Apple's 🔍 in the bar (Home's), or Apple's plain
  //  search field (E11 Talk's — nothing set for where it goes))
  let button: Bool
  init(button: Bool) { self.button = button; super.init(style: .plain) }
  required init?(coder: NSCoder) { fatalError() }
  lazy var search = UISearchController(searchResultsController: nil)
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "E11 Day"
    if #available(iOS 26.0, *) { navigationItem.subtitle = "Saturday, November 7" }
    search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    if #available(iOS 26.0, *), button {
      navigationItem.preferredSearchBarPlacement = .integratedButton
      navigationItem.searchBarPlacementAllowsToolbarIntegration = false
      navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Me", style: .plain, target: nil, action: nil), .fixedSpace(0), navigationItem.searchBarPlacementBarButtonItem]
    }
  }
  func updateSearchResults(for s: UISearchController) {}
  override func numberOfSections(in t: UITableView) -> Int { 1 }
  override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { 30 }
  override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(); c.textLabel?.text = "Task \(i.row + 1)"; return c
  }
  // the same measures as Home's (Home.geo's probe)
  func measure() -> [String: Any] {
    guard let nb = navigationController?.navigationBar, let w = view.window else { return ["shown": false] }
    let rt = tableView!
    return ["searchActive": search.isActive, "barH": nb.frame.height, "barMaxYWin": nb.convert(nb.bounds, to: w).maxY,
            "fieldMaxYWin": search.searchBar.window == nil ? -1 : search.searchBar.convert(search.searchBar.bounds, to: w).maxY,
            "listInsetTop": rt.adjustedContentInset.top,
            "firstRowYWin": rt.convert(rt.rectForRow(at: IndexPath(row: 0, section: 0)), to: w).minY]
  }
}

extension Main {
  // each kind opened full screen, measured as it opens and with its search active, then closed — the 🔍 first, then
  // E11 Talk's field
  func appleSampleOpen() { appleSampleRun(button: true) { self.appleSampleRun(button: false) {} } }
  private func appleSampleRun(button: Bool, then: @escaping () -> Void) {
    let list = AppleSampleList(button: button)
    let nav = UINavigationController(rootViewController: list)
    nav.navigationBar.prefersLargeTitles = true
    nav.modalPresentationStyle = .fullScreen
    let k = button ? "appleSampleButton" : "appleSampleField"
    topMost().present(nav, animated: false) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        self.selfResult[k + "Top"] = list.measure()
        list.search.isActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
          self.selfResult[k + "Find"] = list.measure()
          list.search.isActive = false
          nav.dismiss(animated: false) { then() }
        }
      }
    }
  }
}
