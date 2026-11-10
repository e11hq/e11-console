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
  // ---- taps that went to the website while there's none ----
  static var lost: [String] = []
  static func noteLost(_ js: String) {
    let benign = ["--ios-tabs-h", "\"ev\":\"back\"", "\"ev\":\"list\"", "__e11Kb", "__e11FeedKb", "KbStep", "Resend", "Own &&", "Theme.setMode", "ev:'closed'", "__e11Tab", "ev:'list'", "ev:'back'", "__e11ApnsToken"]
    if benign.contains(where: { js.contains($0) }) { return }
    let s = String(js.prefix(140))
    if !lost.contains(s) { lost.append(s); if lost.count > 60 { lost.removeFirst() } }
  }

  // ---- what's showing now ----
  func walkKindPublic(_ h: HomeView) -> String { walkKind(h) }
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
    web.configuration.websiteDataStore.httpCookieStore.setCookie(c) { self.bootCheck(); if SELFTEST == "walk" || SELFTEST == "apple" { self.walkWhenReady(0) } else { self.crawlAid() } }   // (crawl: Apple's UI testing taps it — ios/UITests)
  }
  private func walkWhenReady(_ n: Int) {
    if !(quickBooted && AppData.shared.ready && splash == nil && shownScreen != nil) && n < 240 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.walkWhenReady(n + 1) }; return
    }
    selfResult["walkBooted"] = ["after": Double(n) / 4, "quick": quickBooted, "copy": AppData.shared.ready, "pageReady": pageReady]
    walkRun(SELFTEST == "apple" ? appleSteps() : walkSteps(), 0)
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

  /* The Apple pages as the phone runs them — no website behind (Haris 2026-11-10: the self-test ran with the website and
     passed what failed on his phone). Each check's result in selfResult["apple"]; ios/walktest.py --apple fails the build
     on any one. */
  private func apple(_ k: String, _ v: [String: Any]) { var a = (selfResult["apple"] as? [String: Any]) ?? [:]; a[k] = v; selfResult["apple"] = a }
  private func appleSteps() -> [(String, () -> Void)] {
    let home = AppData.shared.screen("home").model ?? [:]
    let cards = ((home["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["cards"] as? [[String: Any]]) ?? [] }.compactMap { $0["id"] as? String }
    // (the task with the most comments, its oldest one — for the @ lists and opening a comment as the Inbox does)
    var best: (String, String, Int)? = nil
    for id in cards.prefix(60) { if let items = AppData.shared.screen("comments", id).model?["items"] as? [[String: Any]], items.count >= 4, let first = items.first?["id"] as? String, items.count > (best?.2 ?? 0) { best = (id, first, items.count) } }
    let roles = { (l: [[String: Any]]) -> [String] in l.prefix(8).map { "\($0["name"] ?? "?"): \(($0["role"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "<none>")" } }
    let p = { self.taskPages.last }
    return [
      ("aStart", { self.apple("start", ["cards": cards.count, "task": best?.0 ?? cards.first ?? "", "comments": best?.2 ?? 0, "pageReady": self.pageReady]) }),
      // Home's In review box: My Tasks, Waiting for CD review on
      ("aReview", { self.tab(self.tabKeys.first ?? "today"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.homeView.onEvent?(["ev": "review"]) } }),
      ("aReviewRead", {
        var sub = ""; if #available(iOS 26.0, *) { sub = MyTasksVC.shared?.navigationItem.subtitle ?? "" }
        self.apple("review", ["cd": (self.myTasksF["cd"] as? Bool) == true, "tab": self.selectedTabKey, "line": sub])
        self.myTasksF = (AppData.shared.meModel("tasks", "myTasksDefault")?["filters"] as? [String: Any]) ?? [:]; self.myTasksAgain()
      }),
      // a task's @ lists: the roles under the names — the description's people and the comment box's
      // (any task when none in the test's copy has four comments — 1655's check opened none and read empty lists)
      ("aTask", { self.tab(self.tabKeys.first ?? "today"); if let t = best?.0 ?? cards.first { self.openTaskPage(t, tab: "comments", focus: "") } }),
      ("aTaskWait", {}),
      ("aTaskRoles", {
        let desc = (p()?.model?["mentionable"] as? [[String: Any]]) ?? [], box = self.composeIfMade?.mentionable ?? []
        // (and drawn: Apple's list made with those rows, laid out — each role's words on screen inside its row, not squeezed
        //  out; 1656's data had the roles and the phone still showed none)
        let pl = PickList(); pl.frame = CGRect(x: 0, y: 0, width: 360, height: PickList.rowH * 4)
        pl.rows = (desc.isEmpty ? box : desc).prefix(4).map { PickList.person($0) {} }
        pl.layoutIfNeeded()
        let shown = pl.visibleCells.map { c -> String in
          var q: [UIView] = [c.contentView]; var got = "<none>"
          while !q.isEmpty { let v = q.removeFirst(); q += v.subviews
            if let l = v as? UILabel, let t = l.text, !t.isEmpty, l.font.pointSize < 15, l.bounds.height >= 10, c.contentView.bounds.contains(l.convert(l.bounds, to: c.contentView)) { got = t } }
          return got
        }
        self.apple("roles", ["desc": roles(desc), "box": roles(box), "rows": (desc.isEmpty ? box : desc).prefix(8).map { PickList.person($0) {}.sub ?? "<none>" }, "drawn": shown])
        for x in self.taskPages { self.closeTaskPage(x, animated: false) }
      }),
      // Content plans without the website (Me › Content plans for the Super Admin — mock-up "Content plans — fully Apple"):
      // the list from the phone's copy, then a client's month (its status cell, or Apple's Not Started Yet)
      ("aPlans", { self.tab(self.tabKeys.first ?? "today"); self.meCtl.openPlans() }),
      ("aPlansWait", {}),
      ("aPlansRead", { self.apple("plans", self.meCtl.selfPlans()); _ = self.meCtl.selfOpenPlan() }),
      ("aPlanWait", {}),
      ("aPlanRead", { self.apple("plan", self.meCtl.selfPlans()); self.meCtl.backToRoot(); self.tab(self.tabKeys.first ?? "today") }),
      // Team members (Me › Team members for the Super Admin — the approved mock-up "Team members — fully Apple"): the people
      // with their roles, a person's Apple menu, and their page's Role / Finance Access menus and switches
      ("aTeam", { self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.meCtl.selfOpen("team") } }),
      ("aTeamWait", {}),
      ("aTeamRead", { let o = self.meCtl.selfTeam(); self.apple("team", o); if let id = o["other"] as? String { self.meCtl.selfOpenMember(id) } }),
      ("aTeamMemberWait", {}),
      ("aTeamMemberRead", { self.apple("teamMember", self.meCtl.selfTeam()); self.meCtl.backToRoot(); self.tab(self.tabKeys.first ?? "today") }),
      // Social's own Plans tab (its first screen in Apple's navigation): a skeleton opened from it — the tab bar gone once it
      // has arrived, as a task; back — the tab bar there again and the list as it was (Haris 2026-11-10, the mock-up's A)
      ("aPlTab", { if self.tabKeys.contains("plans") { self.selfTapTab("plans") } }),
      ("aPlTabWait", {}),
      ("aPlTabRead", {
        guard self.tabKeys.contains("plans") else { return }
        var o = self.meCtl.selfPlans(); o["shown"] = MeTabVC.byKey["plans"]?.view.window != nil; o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("plansTab", o); _ = self.meCtl.selfOpenPlan()
      }),
      ("aPlTabPlanWait", {}),
      ("aPlTabPlanRead", {
        guard self.tabKeys.contains("plans") else { return }
        var o = self.meCtl.selfPlans(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("plansTabPlan", o); AppleTabs.shared?.roleNavs["plans"]?.popViewController(animated: true)
      }),
      ("aPlTabBackWait", {}),
      ("aPlTabBackRead", {
        guard self.tabKeys.contains("plans") else { return }
        var o = self.meCtl.selfPlans(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("plansTabBack", o)
      }),
      // (measurement, Haris 2026-11-10: a client's page sliding in from the Clients list — frame by frame, the search box
      //  and its glass in Apple's bar, and every touch of ours on the bar with its time)
      ("aBar", { self.tab("projects") }),
      ("aBarWait", {}),
      ("aBarPush", {
        BarLog.start()
        let nav = AppleTabs.shared?.clientsNav
        SelfFrames.run(1.6, {
          let t = Int((CACurrentMediaTime() - BarLog.t0) * 1000)
          guard let bar = nav?.navigationBar, let w = bar.window else { return ["t": t, "bar": false] }
          var q: [UIView] = [bar]; var fields: [String] = []
          while !q.isEmpty { let v = q.removeFirst(); q += v.subviews
            guard let tf = v as? UISearchTextField else { continue }
            let f = tf.convert(tf.bounds, to: w); let pa = tf.layer.presentation()?.opacity ?? tf.layer.opacity
            var bg: [String] = []
            var r: [UIView] = tf.subviews
            while !r.isEmpty { let x = r.removeFirst(); r += x.subviews
              let n = String(describing: type(of: x))
              if n.contains("Background") || n.contains("Glass") || n.contains("Effect") || n.contains("Backdrop") {
                bg.append("\(n) a\(String(format: "%.2f", x.layer.presentation()?.opacity ?? x.layer.opacity))\(x.isHidden ? " hidden" : "") \(Int(x.bounds.width))x\(Int(x.bounds.height))")
              }
            }
            fields.append("\(tf.placeholder ?? "") x\(Int(f.minX)) y\(Int(f.minY)) a\(String(format: "%.2f", pa)) bg[\(bg.joined(separator: "; "))] tfbg:\(tf.backgroundColor.map { "\($0)" } ?? "nil")")
          }
          return ["t": t, "fields": fields]
        }) { frames in self.apple("barFrames", ["frames": frames, "log": BarLog.notes]); BarLog.on = false }
        _ = self.clientsListIfMade?.selfOpenFirstClient()
      }),
      ("aBarRead", {}),
      // (the test, Haris 2026-11-10 19:58 "Yes": a plain Apple page with only a search bar pushed on the same navigation, then
      //  our page's pieces added one at a time — the one that makes the box's fill come late is the cause)
      ("aBarBackA", { AppleTabs.shared?.clientsNav.popToRootViewController(animated: false) }),
      ("aBarV0", { self.barVariant(0) }), ("aBarV0w", {}), ("aBarV0x", {}),
      ("aBarV8", { self.barVariant(8) }), ("aBarV8w", {}), ("aBarV8x", {}),
      ("aBarV9", { self.barVariant(9) }), ("aBarV9w", {}), ("aBarV9x", {}),
      ("aBarV10", { self.barVariant(10) }), ("aBarV10w", {}), ("aBarV10x", {}),
      ("aBarV11", { self.barVariant(11) }), ("aBarV11w", {}), ("aBarV11x", {}),
      ("aBarV12", { self.barVariant(12) }), ("aBarV12w", {}), ("aBarV12x", {}),
      ("aBarBack", { self.tab("projects"); AppleTabs.shared?.clientsNav.popToRootViewController(animated: false) }),
      // a long-ago comment opened as from the Inbox: in view once everything has come
      ("aFocus", { if let b = best { self.openTaskPage(b.0, tab: "comments", focus: "\(b.0)~\(b.1)") } }),
      ("aFocusWait", {}),
      ("aFocusRead", {
        if let b = best { self.apple("focus", self.taskPages.last?.feed?.selfInView(b.1) ?? ["feed": false]) } else { self.apple("focus", ["none": true]) }
        for x in self.taskPages { self.closeTaskPage(x, animated: false) }
      }),
    ]
  }
  // one variant pushed on the Clients tab's navigation, filmed for 3 s: when its search box gets Apple's fill, and
  // whether it has it at the end (1659 found: plain fills at once; with no big title (.never) or .inline it's late)
  //  0 plain: a title and a stacked search bar · 8 only no big title (.never)
  //  9 .never, Apple's own search placement (none set) · 10 .never, the search bar hiding on scroll (Apple's default)
  // 11 .never, the page laid out before it's pushed · 12 .never, the search controller given once the view is loaded
  private func barVariant(_ k: Int) {
    guard let nav = AppleTabs.shared?.clientsNav else { return }
    let vc = UIViewController(); vc.view.backgroundColor = HomeLook(lookBoth).bg
    vc.navigationItem.title = "Variant \(k)"
    if k >= 8 { vc.navigationItem.largeTitleDisplayMode = .never }
    let sc = UISearchController(searchResultsController: nil); sc.obscuresBackgroundDuringPresentation = false
    sc.searchBar.placeholder = "Variant \(k)"
    vc.navigationItem.hidesSearchBarWhenScrolling = k == 10
    if k != 9, #available(iOS 16.0, *) { vc.navigationItem.preferredSearchBarPlacement = .stacked }
    if k != 12 { vc.navigationItem.searchController = sc }
    if k == 11 { vc.view.frame = nav.view.bounds; vc.view.layoutIfNeeded() }
    if k == 12 { vc.loadViewIfNeeded(); vc.navigationItem.searchController = sc }
    let t0 = CACurrentMediaTime()
    SelfFrames.run(3.0, {
      let t = Int((CACurrentMediaTime() - t0) * 1000)
      var q: [UIView] = [nav.navigationBar]; var got = "none"
      while !q.isEmpty { let v = q.removeFirst(); q += v.subviews
        if let tf = v as? UISearchTextField, tf.placeholder == "Variant \(k)" { got = tf.backgroundColor == nil ? "nil" : "fill"; break } }
      return ["t": t, "f": got]
    }) { frames in
      let first = frames.first { ($0["f"] as? String) == "fill" }?["t"] as? Int ?? -1
      let seen = frames.first { ($0["f"] as? String) != "none" }?["t"] as? Int ?? -1
      var a = (self.selfResult["apple"] as? [String: Any]) ?? [:]; var v = (a["barVariants"] as? [String: Any]) ?? [:]
      let last = frames.last?["f"] as? String ?? "?"
      v["v\(k)"] = ["boxSeen": seen, "fillAt": first, "atEnd": last]; a["barVariants"] = v; self.selfResult["apple"] = a
      nav.popToRootViewController(animated: false)
    }
    nav.pushViewController(vc, animated: true)
  }
  private func walkSteps() -> [(String, () -> Void)] {
    // what to walk through, from the app's own copy
    let home = AppData.shared.screen("home").model ?? [:]
    let cards = ((home["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["cards"] as? [[String: Any]]) ?? [] }.compactMap { $0["id"] as? String }
    // (one that can be changed — not locked for the CD's review — so every picker opens; else the first)
    let task = cards.first { (((AppData.shared.screen("task", $0).model?["pool"] as? [Any]) ?? []).count) > 0 } ?? cards.first ?? ""
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
    // every tab's search (where it has one): words typed, the results counted, the first task result tapped (it must
    // open), back, then the first client result (its page), back, search closed
    let q4 = String(cname.prefix(4))
    for k in tabKeys where k != "me" {
      s.append(("find_" + k, { self.tab(k); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.shownScreen?.selfFind(q4) } }))
      s.append(("findTask_" + k, { self.selfResult["walkTap_" + k] = self.shownScreen?.selfTapResult(client: false) ?? "no screen" }))
      s.append(("findTaskBack_" + k, { for p in self.taskPages { self.closeTaskPage(p, animated: false) } }))
      s.append(("findClient_" + k, { self.selfResult["walkTapC_" + k] = self.shownScreen?.selfTapResult(client: true) ?? "no screen" }))
      s.append(("findClientBack_" + k, { if self.clientPageIfMade?.isHidden == false { self.ev(self.clientPageIfMade, ["ev": "back"]) }; for p in self.taskPages { self.closeTaskPage(p, animated: false) } }))
      s.append(("findClose_" + k, { self.shownScreen?.selfFindDone() }))
    }
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
      ("taskClient", { self.shut(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { p()?.pickClient() } }),
      ("taskGuardian", { self.shut(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { p()?.pickGuardian() } }),
      ("taskAttach", { self.shut(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { p()?.attachSheet() } }),
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
    // (Me's pages this person has: the money ones and Reviews only where they're theirs)
    var mine = ["profile", "appearance", "about", "shortcuts", "team", "trash", "plans"]
    if tabKeys.contains("reviews") { mine.append("reviews") }
    if tabKeys.contains("fin-reimb") { mine += ["claims", "expenses"] }
    if tabKeys.contains("team") || tabKeys.contains("fin-reimb") { mine.append("overview") }
    for k in mine {
      s.append(("me_" + k, { self.meCtl.pop(animated: false); self.meCtl.selfOpen(k) }))
    }
    s += [
      ("meBack", { self.meCtl.pop(animated: false) }),
      ("meClientAssets", { self.assetsCtl.command(["show": true, "me": AppData.shared.me ?? "", "start": [String: Any]()]) }),
      ("meClientAssetsFind", { self.assetsCtl.top?.selfFind(q4) }),
      ("meClientAssetsFindClose", { self.assetsCtl.top?.selfFindDone() }),
      ("meClientAssetsClient", { self.assetsCtl.openFromClients(client: cid, folder: nil) }),
      ("meClientAssetsBack", { self.ev(self.assetsCtl.top, ["ev": "back"]); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.ev(self.assetsCtl.top, ["ev": "back"]) } }),
      ("homeAgain", { self.tab("today") }),
    ]
    return s
  }

  // ---- for the crawl (ios/UITests): only the screen on top is seen by UI testing (the ones under it hidden from it, as
  //      from VoiceOver), and a label saying where the app is (screen, task pages, sheet) for it to read ----
  func crawlAid() {
    let tag = UILabel(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
    tag.alpha = 0.02; tag.isAccessibilityElement = true; tag.accessibilityIdentifier = "e11state"; tag.isUserInteractionEnabled = false
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self = self, let w = self.view.window else { return }
      if tag.superview !== w { w.addSubview(tag) } else { w.bringSubviewToFront(tag) }
      // (light: read four times a second — not the whole screen's words, as the walk's state does)
      var vcs: [String] = []; var vc: UIViewController = self
      while let p = vc.presentedViewController { vcs.append(String(describing: type(of: p))); vc = p }
      let scr = self.shownScreen.map { self.walkKindPublic($0) } ?? "none"
      tag.accessibilityLabel = "\(scr)|pages=\(self.taskPages.count)|ttab=\(self.taskPages.last?.tab ?? "")|tab=\(self.selectedTabKey)|sheet=\(vcs.joined(separator: ">"))|me=\(self.meCtl.isOpen ? self.meCtl.kind : "")|assets=\(self.assetsCtl.isOpen ? (self.assetsCtl.top?.assets ?? "") : "")|search=\(self.shownScreen?.searching ?? false)"
      let presented = self.presentedViewController != nil
      let top: UIView? = self.taskPages.last ?? self.shownScreen
      for v in self.view.subviews {
        let keep = !presented && (v === top || v === self.tabsMark || v === self.corner || v === self.composeIfMade || v === self.cbarIfMade || v is CornerButton)
        if v.accessibilityElementsHidden == keep { v.accessibilityElementsHidden = !keep }
      }
    }
  }
}
