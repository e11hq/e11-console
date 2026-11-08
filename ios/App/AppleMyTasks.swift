import UIKit

/* My Tasks as its own screen in Apple's tab container (Haris 2026-11-08: "lets start my tasks page" — it follows Home,
   locked): My Tasks' tab is its own navigation with this screen at its root. Apple's bar from the start: the big title
   "My Tasks" with its line under it (how many open, and what's filtered), Apple's search bar under the big title (the
   results in My Tasks' own list, as Home's), your photo, and Apple's filter button with Apple's own menu (no Talk button
   here — Haris). All / Done is Apple's segmented control at the top of the list; the cards are in Apple's list with
   Apple's swipes, as Home's. People and AMs open the same people sheet as before (search and ticks — Haris: "open same
   style sheet for am's too"). */
let APPLE_MYTASKS = APPLE_NAV

final class MyTasksVC: UIViewController, UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {
  static weak var shared: MyTasksVC?
  override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil); MyTasksVC.shared = self }
  required init?(coder: NSCoder) { fatalError() }
  override var preferredStatusBarStyle: UIStatusBarStyle { Main.shared.statusStyle }
  override func loadView() { let v = UIView(); v.backgroundColor = .systemGroupedBackground; view = v }
  private var meItem: UIBarButtonItem?
  private var filterItem: UIBarButtonItem?
  private var mePhoto: UIImage?
  private var search: UISearchController?
  // what the list says (how many open) and what's filtered (the page's buttons and chips)
  private var openLine = ""
  private var filters: [String: Any] = [:]

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    navigationItem.title = "My Tasks"
    // your photo, Apple's own bar button (as Home's)
    let me = UIBarButtonItem(image: BarImage.me(nil, traitCollection), primaryAction: UIAction { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); Main.shared.myTasksIfMade?.meTap() })
    me.accessibilityLabel = "Me"
    meItem = me
    // the filter button: Apple's bar button with Apple's own menu, made each time it opens (what's on now)
    let f = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), menu: UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.menuItems() ?? []) }]))
    f.accessibilityLabel = "Filters"
    f.tintColor = .label
    filterItem = f
    navigationItem.rightBarButtonItems = [me, .fixedSpace(0), f]
    if #available(iOS 17.0, *) { registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: MyTasksVC, _: UITraitCollection) in vc.paintMe() } }
    // Apple's search, always in Apple's bar under the big title — the results in My Tasks' own list (as Home's)
    let s = UISearchController(searchResultsController: nil)
    s.obscuresBackgroundDuringPresentation = false
    s.searchResultsUpdater = self
    s.delegate = self
    s.searchBar.placeholder = "Search tasks, clients or people"
    s.searchBar.autocorrectionType = .no
    // All / Done: Apple's own scope bar under the search field, in Apple's bar — it stays under the bar as the list
    // scrolls (Haris 2026-11-08: "can the segmented tabs stick in my tasks" — yes)
    s.searchBar.scopeButtonTitles = ["All", "Done"]
    s.searchBar.showsScopeBar = true
    if #available(iOS 16.0, *) { s.scopeBarActivation = .manual }
    s.searchBar.delegate = self
    search = s
    navigationItem.searchController = s
    navigationItem.hidesSearchBarWhenScrolling = false
    showLine()
    if let h = Main.shared.myTasksIfMade { adopt(h) }
  }
  // (where the tab bar starts, for "+ New task" and the list's end — as Home's screen does)
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let m = Main.shared
    if let h = m.myTasksIfMade, h.superview === view { h.tabTop = m.homeTabTop }
  }
  func adopt(_ h: HomeView) {
    loadViewIfNeeded()
    if h.superview !== view {
      h.removeFromSuperview()
      h.frame = view.bounds; h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.insertSubview(h, at: 0)
    }
    view.backgroundColor = h.backgroundColor ?? view.backgroundColor
    h.onAppleTitle = { [weak self] _, d in self?.openLine = d; self?.showLine() }
    h.onAppleFilters = { [weak self] a in self?.filters = a; self?.showLine() }
    h.onAppleFind = { [weak self] q in
      guard let s = self?.search else { return }
      if let q = q { s.isActive = true; s.searchBar.text = q; Main.shared.myTasksIfMade?.appleSearchText(q) } else { s.isActive = false }
    }
    h.onAppleMe = { [weak self] img in if let img = img { self?.mePhoto = img; self?.paintMe() } }
    h.onAppleResign = { [weak self] in self?.search?.searchBar.resignFirstResponder() }
    h.appleBarHeight = { [weak self] in
      guard let nb = self?.navigationController?.navigationBar, !nb.isHidden, nb.window != nil else { return 0 }
      return nb.frame.height
    }
    h.useAppleTop()
    setContentScrollView(h.appleScroll, for: .top)
  }
  func paintMe() { meItem?.image = BarImage.me(mePhoto, traitCollection) }

  // ---------- the line under the title: how many open, and what's filtered (one short line, always) ----------
  private var chips: [[String: Any]] { (filters["chips"] as? [[String: Any]]) ?? [] }
  private var shownLine: String?
  private func showLine() {
    // ("12 open tasks" → "12 open"; one filter: its name; more: how many — Haris 2026-11-08)
    var open = openLine
    for s in [" open tasks", " open task"] where open.hasSuffix(s) { open = String(open.dropLast(s.count - 5)) }
    let c = chips
    let what = c.count == 1 ? chipName(c[0]) : c.count > 1 ? "\(c.count) filters" : ""
    let line = [open, what].filter { !$0.isEmpty }.joined(separator: " · ")
    let scope = (filters["tab"] as? String) == "done" ? 1 : 0
    if let b = search?.searchBar, b.selectedScopeButtonIndex != scope { b.selectedScopeButtonIndex = scope }
    // the filter button: Apple's filled symbol while a filter is on (as Mail's)
    filterItem?.image = UIImage(systemName: c.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
    guard line != shownLine else { return }
    shownLine = line
    if #available(iOS 26.0, *) {
      navigationItem.subtitle = line.isEmpty ? nil : line
      if line.isEmpty { navigationItem.largeAttributedSubtitle = nil } else {
        var a = AttributedString(line); a.uiKit.font = .systemFont(ofSize: 15); a.uiKit.foregroundColor = .secondaryLabel
        navigationItem.largeAttributedSubtitle = a
      }
    }
  }
  // a filter's own name in the line ("Due: This week" → "This week", "Leila Haddad’s tasks" → "Leila Haddad")
  private func chipName(_ c: [String: Any]) -> String {
    var t = c["t"] as? String ?? ""
    if t.hasPrefix("Due: ") { t = String(t.dropFirst(5)) }
    if t.hasSuffix("’s tasks") { t = String(t.dropLast(8)) }
    return t
  }
  // the names picked, for a filter's grey line in the menu: one, two, or the first and how many more
  private func names(_ act: String) -> String? {
    let n = chips.filter { ($0["act"] as? String) == act }.map(chipName)
    if n.isEmpty { return nil }
    // (one name; more: the first and how many more — "Ali Raza + 1 more", Haris 2026-11-08)
    return n.count == 1 ? n[0] : "\(n[0]) + \(n.count - 1) more"
  }

  // ---------- Apple's menu: what's on, and changing it (each person sees only the filters their role has) ----------
  private func menuItems() -> [UIMenuElement] {
    let main = Main.shared
    let ks = ((filters["buttons"] as? [[String: Any]]) ?? []).compactMap { $0["k"] as? String }
    let ev = { (e: [String: Any]) in main.myTasksIfMade?.menuEvent(e) }
    var out: [UIMenuElement] = []
    if ks.contains("due") {
      let cur = main.myTasksF["due"] as? String
      let due = [("late", "Overdue"), ("today", "Today"), ("week", "This week")].map { k, t in
        UIAction(title: t, state: cur == k ? .on : .off) { _ in UISelectionFeedbackGenerator().selectionChanged(); ev(["ev": "dueSet", "k": k]) }
      }
      out.append(UIMenu(title: "Due", options: .displayInline, children: due))
    }
    var who: [UIMenuElement] = []
    if ks.contains("people") {
      let a = UIAction(title: "People", subtitle: names("person"), image: UIImage(systemName: "person.2")) { _ in ev(["ev": "filter", "k": "people"]) }
      who.append(a)
    }
    if ks.contains("ams") {
      let team = chips.contains { ($0["act"] as? String) == "team" }
      let a = UIAction(title: "AMs", subtitle: team ? "All Account Managers & Admins" : names("am"), image: UIImage(systemName: "person.crop.circle")) { _ in ev(["ev": "filter", "k": "ams"]) }
      who.append(a)
    }
    if ks.contains("assigned") {
      let on = chips.contains { ($0["act"] as? String) == "assigned" }
      who.append(UIAction(title: "Assigned to me", image: UIImage(systemName: "person.fill.checkmark"), state: on ? .on : .off) { _ in ev(["ev": "filter", "k": "assigned"]) })
    }
    // (Waiting for CD review — set from Home's "In review" box: ticked here, a tap takes it off)
    if chips.contains(where: { ($0["act"] as? String) == "cd" }) {
      who.append(UIAction(title: "Waiting for CD review", state: .on) { _ in ev(["ev": "chip", "act": "cd"]) })
    }
    if !who.isEmpty { out.append(UIMenu(options: .displayInline, children: who)) }
    if !chips.isEmpty {
      out.append(UIMenu(options: .displayInline, children: [UIAction(title: "Clear filters", attributes: .destructive) { _ in UIImpactFeedbackGenerator(style: .light).impactOccurred(); ev(["ev": "reset"]) }]))
    }
    return out
  }

  var scopeShown: Bool { search?.searchBar.showsScopeBar == true }
  // All / Done picked in Apple's scope bar
  func searchBar(_ b: UISearchBar, selectedScopeButtonIndexDidChange i: Int) {
    UISelectionFeedbackGenerator().selectionChanged()
    Main.shared.myTasksIfMade?.menuEvent(["ev": "tab", "tab": i == 1 ? "done" : "all"])
  }
  // ---------- Apple's search: it opened, its words changed, it closed (as Home's) ----------
  func updateSearchResults(for s: UISearchController) { Main.shared.myTasksIfMade?.appleSearchText(s.searchBar.text ?? "") }
  func willPresentSearchController(_ s: UISearchController) { Main.shared.myTasksIfMade?.appleSearchBegin() }
  func didPresentSearchController(_ s: UISearchController) { DispatchQueue.main.async { s.searchBar.becomeFirstResponder() } }
  func willDismissSearchController(_ s: UISearchController) { Main.shared.myTasksIfMade?.appleSearchEnd() }
}
