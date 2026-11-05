import UIKit

/* The walk-through (Haris 2026-11-05: "go through the whole app, click on every button… see all is working"): on the build
   machine, a second run of the app with the website off (E11_SELFTEST=walk) taps its way through every screen — Home and
   its search (a client in it, the client's page, Show completed, its Client Assets), a task (every picker, attach,
   comments, its ••• menu, Copy link), a task's files in the preview, New task, My Tasks (filters, Done), the Inbox (each
   kind of update opened, + New task, your photo), Clients (search, a client held, Add client), Me and every page under it,
   the morning round-up, the date sheet. At each step: what's on screen, what sheet is up, any "Loading…" / error words
   showing, and any tap that went to the website (which isn't there — so nothing happened). selftest.py reads it all,
   takes a screenshot at each step and lists what failed. */

extension Main {
  // ---- taps that went to the website while there's none (also counted on real phones: SlowWatch's note) ----
  static var lost: [String] = []
  static func noteLost(_ js: String) {
    let benign = ["__e11Kb", "__e11FeedKb", "KbStep", "Resend", "Own &&", "Theme.setMode", "__e11SplashSkip", "ev:'closed'", "__e11Tab", "ev:'list'", "ev:'back'", "__e11SplashRetry", "__e11ApnsToken"]
    if benign.contains(where: { js.contains($0) }) { return }
    let s = String(js.prefix(140))
    if !lost.contains(s) { lost.append(s); if lost.count > 60 { lost.removeFirst() } }
  }

  // ---- what's showing now ----
  private func walkKind(_ h: HomeView) -> String {
    if h.isInbox { return "inbox" }
    if h.isClient { return "client" }
    if h.isClients { return "clients" }
    if let a = h.assets { return a }
    if h === homeIfMade { return "home" }
    if h === myTasksIfMade { return "mytasks" }
    return "?"
  }
  private func labels(_ v: UIView, _ out: inout [String], depth: Int = 0) {
    if v.isHidden || v.alpha < 0.02 || depth > 40 { return }
    if let l = v as? UILabel, let t = l.text, !t.isEmpty { out.append(t) }
    if let b = v as? UIButton, let t = b.configuration?.title ?? b.title(for: .normal), !t.isEmpty { out.append(t) }
    for s in v.subviews { labels(s, &out, depth: depth + 1) }
  }
  func walkState() -> [String: Any] {
    var s: [String: Any] = ["tab": selectedTabKey, "pages": taskPages.count]
    if let p = taskPages.last { s["task"] = p.model?["title"] as? String ?? "(not drawn)"; s["taskTab"] = p.tab }
    if let h = shownScreen { s["screen"] = walkKind(h); let g = h.geo(); s["title"] = g["title"] ?? ""; s["cards"] = g["cards"] ?? 0; s["results"] = g["results"] ?? 0; s["searching"] = g["searching"] ?? false; s["fab"] = g["fab"] ?? false }
    else { s["screen"] = "none" }
    var vcs: [String] = []; var v: UIViewController = self
    while let p = v.presentedViewController { vcs.append(String(describing: type(of: p))); v = p }
    s["sheet"] = vcs.joined(separator: " > ")
    s["assets"] = assetsCtl.isOpen ? (assetsCtl.top?.assets ?? "?") : ""
    s["me"] = meCtl.isOpen ? meCtl.kind : ""
    // (words showing anywhere that mean something didn't come: Loading…, an error, "try again")
    var all: [String] = []
    if let w = view.window { labels(w, &all) }
    var p: UIViewController? = presentedViewController
    while let x = p { labels(x.view, &all); p = x.presentedViewController }
    let bad = ["Loading", "No answer", "went wrong", "Couldn", "Could not", "try again", "isn’t here", "not available", "on the computer", "Error"]
    s["issues"] = Array(Set(all.filter { t in bad.contains { t.localizedCaseInsensitiveContains($0) } })).prefix(6).map { String($0.prefix(90)) }
    s["words"] = Array(all.filter { $0.count > 1 }.prefix(40)).map { String($0.prefix(50)) }
    s["corner"] = "\(corner.left.kind),\(corner.mid.kind),\(corner.corner.kind)"
    return s
  }

  // ---- the walk ----
  func walkTest() {
    // (signed in as the build machine's test person — the dev sign-in's cookie — and started the app's own way)
    guard let host = URL(string: serverURL())?.host, let email = procEnv["E11_SELFTEST_EMAIL"],
          let c = HTTPCookie(properties: [.domain: host, .path: "/", .name: "e11_dev_email", .value: email]) else { return }
    web.configuration.websiteDataStore.httpCookieStore.setCookie(c) { self.bootCheck(); self.walkWhenReady(0) }
  }
  private func walkWhenReady(_ n: Int) {
    if !(quickBooted && AppData.shared.ready && splash == nil && homeIfMade?.isHidden == false) && n < 240 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.walkWhenReady(n + 1) }; return
    }
    selfResult["walkBooted"] = ["after": Double(n) / 4, "quick": quickBooted, "copy": AppData.shared.ready, "pageReady": pageReady]
    walkRun(walkSteps(), 0)
  }
  private func walkRun(_ steps: [(String, () -> Void)], _ i: Int) {
    if i >= steps.count { selfResult["walkLost"] = Main.lost; writeSelf("done"); return }
    let (name, act) = steps[i]
    let lostBefore = Main.lost.count
    act()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
      var st = self.walkState()
      st["lost"] = Array(Main.lost.suffix(from: min(lostBefore, Main.lost.count)))
      var list = (self.selfResult["walk"] as? [[String: Any]]) ?? []
      st["step"] = name; list.append(st)
      self.selfResult["walk"] = list
      self.writeSelf("w\(String(format: "%02d", i))_\(name)")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.walkRun(steps, i + 1) }
    }
  }
  private func shut() { if let p = presentedViewController { p.dismiss(animated: false) } }
  private func tab(_ k: String) { shut(); for p in taskPages { closeTaskPage(p, animated: false) }; selectTab(k) }
  private func ev(_ h: HomeView?, _ e: [String: Any]) { h?.onEvent?(e) }

  private func walkSteps() -> [(String, () -> Void)] {
    // what to walk through, from the app's own copy
    let home = AppData.shared.screen("home").model ?? [:]
    let cards = ((home["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["cards"] as? [[String: Any]]) ?? [] }.compactMap { $0["id"] as? String }
    let task = cards.first ?? ""
    let withFiles = cards.prefix(40).first { !((AppData.shared.screen("task", $0).model?["files"] as? [Any]) ?? []).isEmpty }
    let clientsM = AppData.shared.screen("clients", ServerHome.clientsJSON("view=list")).model ?? [:]
    let client = ((clientsM["rows"] as? [[String: Any]]) ?? []).first
    let cid = client?["id"] as? String ?? "", cname = client?["name"] as? String ?? "a"
    let inboxRows = (AppData.shared.screen("inbox", "all").model?["rows"] as? [[String: Any]]) ?? []
    var kinds = Set<String>(); var rows: [(String, String)] = []
    for r in inboxRows { let k = r["kind"] as? String ?? r["type"] as? String ?? "?"; if let id = r["id"] as? String, !kinds.contains(k), rows.count < 6 { kinds.insert(k); rows.append((k, id)) } }
    selfResult["walkData"] = ["cards": cards.count, "task": task, "withFiles": withFiles ?? "", "client": cname, "inboxKinds": rows.map { $0.0 }]
    let p = { self.taskPages.last }

    var s: [(String, () -> Void)] = [("home", {})]
    // every tab, and its floating button (+ New task, Add client, Add subscription…) where it has one
    for k in tabKeys {
      s.append(("tab_" + k, { self.tab(k) }))
      s.append(("tabFab_" + k, { self.selfResult["walkFab_" + k] = self.shownScreen?.selfFab() ?? false }))
      s.append(("tabFabClose_" + k, { FormSheetVC.current?.finish("discard"); self.shut() }))
    }
    s += [
      ("homeStart", { self.tab(self.tabKeys.first ?? "today") }),
      // Home: search, a client in the results, its page, Show completed, its Client Assets, back
      ("homeFind", { self.homeIfMade?.selfScroll(0); self.homeIfMade?.selfFind(String(cname.prefix(4))) }),
      ("findClient", { self.ev(self.homeIfMade, ["ev": "client", "id": cid]) }),
      ("clientShowDone", { self.ev(self.clientPageIfMade, ["ev": "showDone"]) }),
      ("clientAssets", { self.ev(self.clientPageIfMade, ["ev": "assets", "client": cid]) }),
      ("clientAssetsBack", { self.ev(self.assetsCtl.top, ["ev": "back"]) }),
      ("clientBack", { self.ev(self.clientPageIfMade, ["ev": "back"]) }),
      ("findTask", { self.homeIfMade?.selfFind("e") }),
      ("findClose", { self.homeIfMade?.selfFindDone() }),
      // a task: every picker, attach, comments, its menu, Copy link, back
      ("task", { self.openTaskPage(task, tab: "details", focus: "") }),
      ("taskPeople", { p()?.pickPeople() }),
      ("taskTags", { self.shut(); p()?.pickTags() }),
      ("taskClient", { self.shut(); p()?.pickClient() }),
      ("taskChannels", { self.shut(); p()?.pickChannels() }),
      ("taskGuardian", { self.shut(); p()?.pickGuardian() }),
      ("taskAttach", { self.shut(); p()?.attachSheet() }),
      ("taskComments", { self.shut(); p()?.setTab("comments", tell: true) }),
      ("taskMenu", { self.selfResult["walkMenu"] = self.corner.items.map { $0.title + ($0.children.isEmpty ? "" : " [" + $0.children.map { $0.title }.joined(separator: ", ") + "]") } }),
      ("taskCopy", { func find(_ l: [CornerMenuItem]) -> CornerMenuItem? { for x in l { if x.title.contains("Copy") { return x }; if let y = find(x.children) { return y } }; return nil }; find(self.corner.items)?.run?() }),
      ("taskBack", { if let x = p() { x.setTab("details", tell: true); self.closeTaskPage(x, animated: false) } }),
    ]
    if let f = withFiles {
      s += [
        ("fileTask", { self.openTaskPage(f, tab: "details", focus: "") }),
        ("fileOpen", { if let files = AppData.shared.screen("task", f).model?["files"] as? [[String: Any]] { self.openFiles(files, at: 0) } }),
        ("fileBack", { self.shut(); if let x = p() { self.closeTaskPage(x, animated: false) } }),
      ]
    }
    s += [
      ("homeAdd", { self.ev(self.homeIfMade, ["ev": "add"]) }),
      ("homeAddClose", { FormSheetVC.current?.finish("discard"); self.shut() }),
      ("homeDue", { self.ev(self.homeIfMade, ["ev": "due", "id": task]) }),
      ("homeDaily", { self.shut(); _ = self.dailyNative() }),
      // My Tasks: filters, Done, a task
      ("mytasks", { self.tab("mytasks") }),
      ("mtFilterDue", { self.ev(self.myTasksIfMade, ["ev": "filter", "k": "due"]) }),
      ("mtFilterPeople", { self.shut(); self.ev(self.myTasksIfMade, ["ev": "filter", "k": "people"]) }),
      ("mtDone", { self.shut(); self.myTasksIfMade?.selfTab("done") }),
      ("mtAll", { self.myTasksIfMade?.selfTab("all") }),
      ("mtOpen", { if let id = ((self.serverMyTasksIfMade?.shown?["groups"] as? [[String: Any]]) ?? []).flatMap({ ($0["cards"] as? [[String: Any]]) ?? [] }).first?["id"] as? String { self.ev(self.myTasksIfMade, ["ev": "open", "id": id]) } }),
      ("mtAdd", { if let x = p() { self.closeTaskPage(x, animated: false) }; self.ev(self.myTasksIfMade, ["ev": "add"]) }),
      ("mtAddClose", { FormSheetVC.current?.finish("discard"); self.shut() }),
      // the Inbox: each kind of update opened, + New task, your photo
      ("inbox", { self.tab("inbox") }),
    ]
    for (k, id) in rows {
      s.append(("inboxOpen_" + k, { self.tab("inbox"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.ev(self.inboxIfMade, ["ev": "open", "id": id]) } }))
    }
    s += [
      ("inboxAdd", { self.tab("inbox"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.ev(self.inboxIfMade, ["ev": "add"]) } }),
      ("inboxAddClose", { FormSheetVC.current?.finish("discard"); self.shut() }),
      ("inboxMe", { self.ev(self.inboxIfMade, ["ev": "me"]) }),
      // Clients: the list, its search, a client held, Add client, a client's page
      ("clients", { self.tab(self.tabKeys.contains("projects") ? "projects" : "clients") }),
      ("clientsFind", { self.shownScreen?.selfFind(String(cname.prefix(4))) }),
      ("clientsFindClose", { self.shownScreen?.selfFindDone() }),
      ("clientHold", { self.ev(self.clientsListIfMade, ["ev": "clientHold", "id": cid]) }),
      ("addClient", { self.shut(); self.ev(self.clientsListIfMade, ["ev": "addClient"]) }),
      ("clientOpen", { self.shut(); self.ev(self.clientsListIfMade, ["ev": "client", "id": cid]) }),
      ("clientTask", { if let id = ((self.serverClients.shown?["groups"] as? [[String: Any]]) ?? []).flatMap({ ($0["cards"] as? [[String: Any]]) ?? [] }).first?["id"] as? String { self.ev(self.clientPageIfMade, ["ev": "open", "id": id]) } }),
      ("clientTaskBack", { if let x = p() { self.closeTaskPage(x, animated: false) } }),
      ("clientsBack", { self.ev(self.clientPageIfMade, ["ev": "back"]) }),
      // Me and every page under it
      ("me", { self.tab("me") }),
    ]
    for k in ["profile", "appearance", "about", "shortcuts", "team", "trash", "plans", "reviews", "claims", "expenses", "overview"] {
      s.append(("me_" + k, { self.meCtl.pop(animated: false); self.meCtl.selfOpen(k) }))
    }
    s += [
      ("meBack", { self.meCtl.pop(animated: false) }),
      ("meClientAssets", { self.assetsCtl.command(["show": true, "me": AppData.shared.me ?? "", "light": self.appStyle == .light, "start": [String: Any]()]) }),
      ("meClientAssetsClient", { self.assetsCtl.openFromClients(client: cid, folder: nil) }),
      ("meClientAssetsBack", { self.ev(self.assetsCtl.top, ["ev": "back"]); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.ev(self.assetsCtl.top, ["ev": "back"]) } }),
      ("homeAgain", { self.tab("today") }),
    ]
    return s
  }
}
