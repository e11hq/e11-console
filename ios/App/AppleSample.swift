import UIKit

/* The self-test only — never shown in the app (Haris 2026-11-07): a screen made of Apple's parts alone, none of ours —
   Apple's navigation, Apple's list, a big title with a date under it, Apple's 🔍 in the bar (as Home's) and Apple's search
   results page — opened with its search active and measured as Home's is: where the search field ends, how tall Apple's
   bar stays, where the results start. Side by side with Home, it shows whether the gap above Home's results is Apple's
   own way or something of ours. */
final class AppleSampleResults: UITableViewController {
  override func numberOfSections(in t: UITableView) -> Int { 1 }
  override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { 20 }
  override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
    let c = UITableViewCell(); c.textLabel?.text = "Result \(i.row + 1)"; return c
  }
}

final class AppleSampleList: UITableViewController, UISearchResultsUpdating {
  let results = AppleSampleResults(style: .plain)
  lazy var search = UISearchController(searchResultsController: results)
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "E11 Day"
    if #available(iOS 26.0, *) { navigationItem.subtitle = "Saturday, November 7" }
    search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false
    navigationItem.searchController = search
    navigationItem.hidesSearchBarWhenScrolling = false
    if #available(iOS 26.0, *) {
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
    let rt = results.tableView!
    return ["searchActive": search.isActive, "barH": nb.frame.height, "barMaxYWin": nb.convert(nb.bounds, to: w).maxY,
            "fieldMaxYWin": search.searchBar.convert(search.searchBar.bounds, to: w).maxY,
            "resultsSafeTop": results.view.safeAreaInsets.top, "resultsInsetTop": rt.adjustedContentInset.top,
            "resultsFirstRowYWin": rt.window == nil ? -1 : rt.convert(rt.rectForRow(at: IndexPath(row: 0, section: 0)), to: w).minY]
  }
}

extension Main {
  // opened full screen, then its search made active; measured twice: before and with search
  func appleSampleOpen() {
    let list = AppleSampleList(style: .plain)
    let nav = UINavigationController(rootViewController: list)
    nav.navigationBar.prefersLargeTitles = true
    nav.modalPresentationStyle = .fullScreen
    topMost().present(nav, animated: false) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        self.selfResult["appleSampleTop"] = list.measure()
        list.search.isActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.selfResult["appleSampleFind"] = list.measure() }
      }
    }
  }
}
