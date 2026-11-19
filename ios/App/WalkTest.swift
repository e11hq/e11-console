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
    return s
  }

  // ---- the walk ----
  func walkTest() {
    // (signed in as the build machine's test person — the dev sign-in's cookie — and started the app's own way)
    guard let host = URL(string: serverURL())?.host, let email = procEnv["E11_SELFTEST_EMAIL"],
          let c = HTTPCookie(properties: [.domain: host, .path: "/", .name: "e11_dev_email", .value: email]) else { return }
    web.configuration.websiteDataStore.httpCookieStore.setCookie(c) { self.bootCheck(); if SELFTEST == "walk" || SELFTEST == "apple" || SELFTEST == "1" { self.walkWhenReady(0) } else { self.crawlAid() } }   // (crawl: Apple's UI testing taps it — ios/UITests)
  }
  private func walkWhenReady(_ n: Int) {
    if !(quickBooted && AppData.shared.ready && splash == nil && shownScreen != nil) && n < 240 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.walkWhenReady(n + 1) }; return
    }
    selfResult["walkBooted"] = ["after": Double(n) / 4, "quick": quickBooted, "copy": AppData.shared.ready, "pageReady": false]
    // (the main self-test, the phone's way — Haris 2026-11-11: no website loaded; it starts once the app's own screens are up)
    if SELFTEST == "1" { if !started { started = true; selfTest() }; return }
    // (E11_ONLY — a quick run of a few checks only, Haris 2026-11-16: the steps whose names start with one of these)
    let only = (procEnv["E11_ONLY"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let steps = SELFTEST == "apple" ? appleSteps() : walkSteps()
    walkRun(only.isEmpty ? steps : steps.filter { s in s.0 == "aStart" || only.contains { s.0.hasPrefix($0) } }, 0)
  }
  private func walkRun(_ steps: [(String, () -> Void)], _ i: Int) {
    if i >= steps.count { writeSelf("done"); return }
    let (name, act) = steps[i]
    act()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
      var st = self.walkState()
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
  // every piece of text on screen against what's really behind it, in light and in dark (the full test, Haris 2026-11-16:
  // nothing invisible from its colours, as the Sign-in Code's digits were) — the colours resolved for each look, nothing
  // switched; text over glass or a blur is skipped (what's behind it isn't known), said so in the count
  func selfContrast() -> [String: Any] {
    guard let w = screenWindow else { return ["none": "no window"] }
    func lum(_ c: UIColor) -> CGFloat {
      var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; c.getRed(&r, green: &g, blue: &b, alpha: &a)
      let f = { (x: CGFloat) -> CGFloat in x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }
    func blend(_ top: UIColor, over bot: UIColor) -> UIColor {
      var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
      top.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); bot.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
      return UIColor(red: r1 * a1 + r2 * (1 - a1), green: g1 * a1 + g2 * (1 - a1), blue: b1 * a1 + b2 * (1 - a1), alpha: 1)
    }
    var bad: [String] = [], checked = 0, glass = 0
    // (only the look on show: Apple's list cells hold colours already worked out for it, so asking them for the other look
    //  gives this one's back — 1.00 everywhere in light while dark was on. ios/walktest.py switches the simulator's look and
    //  the steps read again: aContrastLight / aContrastDark)
    for style in [w.traitCollection.userInterfaceStyle] {
      let tc = w.traitCollection
      var q: [UIView] = [w]
      while !q.isEmpty {
        let v = q.removeFirst()
        if v.isHidden || v.alpha < 0.05 { continue }
        q += v.subviews
        guard let l = v as? UILabel, let t = l.text, !t.trimmingCharacters(in: .whitespaces).isEmpty, l.bounds.width > 2,
              l.convert(l.bounds, to: nil).intersects(w.bounds) else { continue }
        // what's behind: the first ancestor painting a solid colour (half-see-through ones blended over it)
        var layers: [UIColor] = [], x: UIView? = l, solid: UIColor? = nil, overGlass = false   // (from the label itself: a chip's label paints its own pill)
        while let y = x {
          if y is UIVisualEffectView { overGlass = true; break }
          // (a view's own colour, or its layer's — chips and badges paint the layer; a cell's background as Apple's
          //  configuration has it — a clear one is no background: what's behind the cell shows, as on the Inbox)
          var own: [UIColor] = []
          if let c = y as? UICollectionViewListCell, let bg = c.backgroundConfiguration?.resolvedBackgroundColor(for: c.tintColor).resolvedColor(with: tc) { own.append(bg) }
          if let bg = y.backgroundColor?.resolvedColor(with: tc) { own.append(bg) }
          else if let cg = y.layer.backgroundColor { own.append(UIColor(cgColor: cg)) }
          var done = false
          for bg in own {
            var a: CGFloat = 0; bg.getRed(nil, green: nil, blue: nil, alpha: &a)
            if a > 0.97 { solid = bg; done = true; break } else if a > 0.02 { layers.append(bg) }
          }
          if done { break }
          x = y.superview
        }
        if !overGlass, solid == nil { solid = TaskPage.page.resolvedColor(with: tc) }
        if overGlass { glass += 1; continue }
        var back = solid!
        for c in layers.reversed() { back = blend(c, over: back) }
        let fg = blend(l.textColor.resolvedColor(with: tc).withAlphaComponent(l.textColor.resolvedColor(with: tc).cgColor.alpha * l.alpha), over: back)
        let a = lum(fg), b = lum(back), ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        checked += 1
        if ratio < 1.6 { bad.append("\(style == .light ? "light" : "dark") \(String(format: "%.2f", ratio)) “\(String(t.prefix(24)))”") }
      }
    }
    return ["checked": checked, "glass": glass, "faint": Array(Set(bad)).sorted().prefix(12).map { $0 }]
  }
  // a change made elsewhere: straight to the server as this person on another device (the test server's dev sign-in)
  private func elsewhere(_ path: String, _ body: [String: Any], _ done: @escaping (String) -> Void) {
    guard let url = URL(string: serverURL() + path), let email = procEnv["E11_SELFTEST_EMAIL"], let d = try? JSONSerialization.data(withJSONObject: body) else { return done("no request") }
    var r = URLRequest(url: url); r.httpMethod = "POST"; r.httpBody = d
    r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue(email, forHTTPHeaderField: "X-Dev-Email")
    URLSession.shared.dataTask(with: r) { d, resp, _ in
      let s = "\((resp as? HTTPURLResponse)?.statusCode ?? 0) " + String(decoding: (d ?? Data()).prefix(160), as: UTF8.self)
      DispatchQueue.main.async { done(s) }
    }.resume()
  }
  private func tabBadge(_ k: String) -> String {
    guard let t = AppleTabs.shared, let i = tabKeys.firstIndex(of: k), let vcs = t.viewControllers, i < vcs.count else { return "?" }
    return vcs[i].tabBarItem.badgeValue ?? ""
  }
  // (the Clients list's bar at this moment: its height, the search bar's place, the list's top — the search pilot)
  private func srchState() -> [String: Any] {
    let n = AppleTabs.shared?.clientsNav, nb = n?.navigationBar, vc = n?.viewControllers.first as? ClientsVC
    let sb = vc?.search?.searchBar, sv = clientsListIfMade?.appleScroll
    let f = sb.flatMap { b in b.window.map { _ in b.convert(b.bounds, to: nil) } } ?? .zero
    return ["bar": Int(nb?.frame.height ?? -1), "barBottom": Int(nb.map { $0.convert($0.bounds, to: nil).maxY } ?? -1),
            "search": [Int(f.minY), Int(f.height)], "searchShown": f.height > 8 && (sb?.alpha ?? 0) > 0.5 && f.minY >= 0,
            "offset": Int(sv?.contentOffset.y ?? 0), "inset": Int(sv?.adjustedContentInset.top ?? 0)]
  }
  private func srchAddAny(_ k: String, _ v: Any) {
    var d = ((selfResult["apple"] as? [String: Any])?["srch"] as? [String: Any]) ?? [:]; d[k] = v; apple("srch", d)
  }
  private func srchAdd(_ k: String) {
    var d = ((selfResult["apple"] as? [String: Any])?["srch"] as? [String: Any]) ?? [:]; d[k] = srchState(); apple("srch", d)
  }
  // (one line of the Clients list's bar at this moment, for the back-to-the-list watch: the bar's height, the search bar's
  //  top and height, the list's offset and top inset, its content height against its own — Haris 2026-11-19 15:05)
  private func srchLine(_ t0: CFTimeInterval) -> String {
    let n = AppleTabs.shared?.clientsNav, nb = n?.navigationBar, vc = n?.viewControllers.first as? ClientsVC
    let sb = vc?.search?.searchBar, sv = clientsListIfMade?.appleScroll
    let f = sb.flatMap { b in b.window.map { _ in b.convert(b.bounds, to: nil) } } ?? .zero
    return String(format: "%.2f bar=%d sy=%d sh=%d off=%d in=%d n=%d", CACurrentMediaTime() - t0, Int(nb?.frame.height ?? -1), Int(f.minY), Int(f.height),
                  Int(sv?.contentOffset.y ?? 0), Int(sv?.adjustedContentInset.top ?? 0), n?.viewControllers.count ?? -1)
  }
  private func apple(_ k: String, _ v: [String: Any]) { var a = (selfResult["apple"] as? [String: Any]) ?? [:]; a[k] = v; selfResult["apple"] = a }

  // The icon-swap lab: the app's swapping icons at their real sizes and colours —
  // the comment box's mic ↔ ↑ in its circle, + ↔ ✕, ▶ ↔ ⏸ and ○ ↔ ✓ — swapped together at 1.0 s, 2.4 s and 3.8 s
  private static var labWin: UIWindow?
  func swapLab() {
    guard let scene = screenWindow?.windowScene else { return }
    let w = UIWindow(windowScene: scene); w.windowLevel = .alert + 1; w.backgroundColor = .systemBackground
    let vc = UIViewController(); vc.view.backgroundColor = .systemBackground; w.rootViewController = vc; w.isHidden = false; Self.labWin = w
    let ways = ["SymSwap"]
    var rows: [(Int, UIView, UIImageView, UIView, UIImageView, UIView, UIImageView, UIImageView)] = []
    let cfg = { (n: String, pt: CGFloat, wt: UIImage.SymbolWeight) in UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: pt, weight: wt)) }
    for (i, name) in ways.enumerated() {
      let y = 70 + CGFloat(i) * 96
      let l = UILabel(frame: CGRect(x: 12, y: y, width: 90, height: 40)); l.text = name; l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabel; l.numberOfLines = 2; vc.view.addSubview(l)
      func circle(_ x: CGFloat, _ d: CGFloat, _ bg: UIColor, _ tint: UIColor, _ img: UIImage?) -> (UIView, UIImageView) {
        let c = UIView(frame: CGRect(x: x, y: y + 20 - d / 2, width: d, height: d)); c.layer.cornerRadius = d / 2; c.backgroundColor = bg; c.tintColor = tint
        let v = UIImageView(image: img); v.contentMode = .center; v.frame = c.bounds; c.addSubview(v); vc.view.addSubview(c); return (c, v)
      }
      let (s, sv) = circle(110, 36, .tertiarySystemFill, .label, cfg("mic", 15, .medium))
      let (pl, pv) = circle(165, 34, UIColor.label.withAlphaComponent(0.07), .label, cfg("plus", 15, .semibold))
      let (pp, ppv) = circle(220, 60, UIColor.black.withAlphaComponent(0.45), .white, cfg("play.fill", 24, .bold))
      let tick = UIImageView(image: UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))); tick.tintColor = .tertiaryLabel
      tick.frame = CGRect(x: 300, y: y + 5, width: 30, height: 30); tick.contentMode = .center; vc.view.addSubview(tick)
      rows.append((i, s, sv, pl, pv, pp, ppv, tick))
    }
    func swap(_ on: Bool) {
      for (i, s, sv, _, pv, _, ppv, tick) in rows {
        let send = cfg(on ? "arrow.up" : "mic", on ? 14 : 15, on ? .bold : .medium), plus = cfg(on ? "xmark" : "plus", 15, .semibold)
        let play = cfg(on ? "pause.fill" : "play.fill", 24, .bold), t = UIImage(systemName: on ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))
        let fill = { s.backgroundColor = on ? .label : .tertiarySystemFill }
        let pairs: [(UIImageView, UIImage?)] = [(sv, send), (pv, plus), (ppv, play), (tick, t)]
        // (the app's own swap, then the colours, as the app's buttons do)
        for (v, im) in pairs { SymSwap.set(v, im, animated: true) }
        UIView.performWithoutAnimation { s.tintColor = on ? .systemBackground : .label; tick.tintColor = on ? .systemBlue : .tertiaryLabel }
        UIView.animate(withDuration: SymSwap.time, delay: 0, options: .curveEaseInOut, animations: fill)
      }
    }
    for (t, on) in [(1.0, true), (2.4, false), (3.8, true)] { DispatchQueue.main.asyncAfter(deadline: .now() + t) { swap(on) } }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) { Self.labWin?.isHidden = true; Self.labWin = nil }
  }
  private func appleSteps() -> [(String, () -> Void)] {
    let home = AppData.shared.screen("home").model ?? [:]
    let cards = ((home["groups"] as? [[String: Any]]) ?? []).flatMap { ($0["cards"] as? [[String: Any]]) ?? [] }.compactMap { $0["id"] as? String }
    // (the task with the most comments, its oldest one — for the @ lists and opening a comment as the Inbox does)
    var best: (String, String, Int)? = nil
    for id in cards.prefix(60) { if let items = AppData.shared.screen("comments", id).model?["items"] as? [[String: Any]], items.count >= 4, let first = items.first?["id"] as? String, items.count > (best?.2 ?? 0) { best = (id, first, items.count) } }
    let roles = { (l: [[String: Any]]) -> [String] in l.prefix(8).map { "\($0["name"] ?? "?"): \(($0["role"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "<none>")" } }
    let p = { self.taskPages.last }
    // each tab's first screen and a task page, in the look on show (keys "dark:today", "light:task" …)
    let look = { self.screenWindow?.traitCollection.userInterfaceStyle == .light ? "light" : "dark" }
    let contrastRun = {
      self.tab(self.tabKeys.first ?? "today")
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        var all = ((self.selfResult["apple"] as? [String: Any])?["contrast"] as? [String: Any]) ?? [:]
        all[look() + ":" + self.selectedTabKey] = self.selfContrast(); self.apple("contrast", all)
        let rest = Array(self.tabKeys.dropFirst())
        func next(_ i: Int) {
          guard i < rest.count else { if let t = best?.0 ?? cards.first { self.openTaskPage(t, tab: "details", focus: "") }; return }
          self.tab(rest[i])
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            var a = ((self.selfResult["apple"] as? [String: Any])?["contrast"] as? [String: Any]) ?? [:]
            a[look() + ":" + rest[i]] = self.selfContrast(); self.apple("contrast", a); next(i + 1)
          }
        }
        next(0)
      }
    }
    let contrastTask = {
      var a = ((self.selfResult["apple"] as? [String: Any])?["contrast"] as? [String: Any]) ?? [:]
      a[look() + ":task"] = self.taskPages.isEmpty ? ["none": "no task opened"] : self.selfContrast()
      self.apple("contrast", a)
      for x in self.taskPages { self.closeTaskPage(x, animated: false) }
      self.tab(self.tabKeys.first ?? "today")
    }
    return [
      ("aStart", { self.apple("start", ["cards": cards.count, "task": best?.0 ?? cards.first ?? "", "comments": best?.2 ?? 0, "pageReady": false]) }),
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
        AppleTabs.shared?.mirrorShown()   // (a count changing while the page shows: the tab bar stays away)
        var o = self.meCtl.selfPlans(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("plansTabPlan", o); AppleTabs.shared?.roleNavs["plans"]?.popViewController(animated: true)
      }),
      ("aPlTabBackWait", {}),
      ("aPlTabBackRead", {
        guard self.tabKeys.contains("plans") else { return }
        var o = self.meCtl.selfPlans(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("plansTabBack", o)
      }),
      // the CD's Reviews tab (Haris 2026-11-10, the mock-up "Review Requests — fully Apple"): its own Apple screen, Waiting ·
      // Reviewed, a request held — Apple's menu; a request opened — Request Amendments · Approve on Apple's toolbar, the tab
      // bar gone once it's there; back
      ("aRv", { if self.tabKeys.contains("reviews") { self.selfTapTab("reviews") } }),
      ("aRvWait", {}),
      ("aRvRead", {
        guard self.tabKeys.contains("reviews") else { return }
        var o = self.meCtl.selfReviews(); o["shown"] = MeTabVC.byKey["reviews"]?.view.window != nil
        self.apple("reviews", o); _ = self.meCtl.selfOpenReview()
      }),
      ("aRvReqWait", {}),
      ("aRvReqRead", {
        guard self.tabKeys.contains("reviews") else { return }
        AppleTabs.shared?.mirrorShown()   // (a count changing while the page shows: the tab bar stays away)
        var o = self.meCtl.selfReviews(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("reviewReq", o); if o["kind"] as? String == "review" { AppleTabs.shared?.roleNavs["reviews"]?.popViewController(animated: true) }
      }),
      ("aRvBackWait", {}),
      ("aRvBackRead", {
        guard self.tabKeys.contains("reviews") else { return }
        var o = self.meCtl.selfReviews(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("reviewsBack", o); self.tab(self.tabKeys.first ?? "today")
      }),
      // an Office Admin's Overview, Claims and Expenses, and Me › Trash (Haris 2026-11-11, the mock-up "Remaining pages —
      // fully Apple"): each tab its own Apple screen from the phone's copy; a claim's swipes and Apple's menu; a claim opened —
      // HR Approved / Paid On… on Apple's toolbar, the tab bar gone; back; the Trash's rows with their swipes and menu
      ("aOv", { if self.officeTabs { self.selfTapTab("today") } }),
      ("aOvWait", {}),
      ("aOvRead", {
        guard self.officeTabs else { return }
        var o = self.meCtl.selfOffice(); o["shown"] = MeTabVC.byKey["today"]?.view.window != nil; o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("overview", o)
        if self.tabKeys.contains("fin-reimb") { self.selfTapTab("fin-reimb") }
      }),
      ("aClWait", {}),
      ("aClRead", {
        guard self.tabKeys.contains("fin-reimb") else { return }
        var o = self.meCtl.selfOffice(); o["shown"] = MeTabVC.byKey["fin-reimb"]?.view.window != nil
        self.apple("claims", o); _ = self.meCtl.selfOpenClaim()
      }),
      ("aClOpenWait", {}),
      ("aClOpenRead", {
        guard self.tabKeys.contains("fin-reimb") else { return }
        AppleTabs.shared?.mirrorShown()   // (a count changing while the page shows: the tab bar stays away)
        var o = self.meCtl.selfOffice(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("claim", o); if o["kind"] as? String == "claim" { AppleTabs.shared?.roleNavs["fin-reimb"]?.popViewController(animated: true) }
      }),
      ("aClBackWait", {}),
      ("aClBackRead", {
        guard self.tabKeys.contains("fin-reimb") else { return }
        var o = self.meCtl.selfOffice(); o["barHidden"] = (AppleTabs.shared?.barHiddenNow ?? false)
        self.apple("claimsBack", o)
        if self.tabKeys.contains("fin-expenses") { self.selfTapTab("fin-expenses") }
      }),
      ("aExWait", {}),
      ("aExRead", {
        guard self.tabKeys.contains("fin-expenses") else { return }
        var o = self.meCtl.selfOffice(); o["shown"] = MeTabVC.byKey["fin-expenses"]?.view.window != nil
        self.apple("expenses", o); self.tab(self.tabKeys.first ?? "today")
      }),
      ("aTr", { if self.meApple, !self.officeTabs { self.selfTapTab("me") } }),
      ("aTrWait", {}),
      ("aTrOpen", { if self.meApple, !self.officeTabs { self.meCtl.selfOpenTrash() } }),
      ("aTrOpenWait", {}),
      ("aTrRead", {
        guard self.meApple, !self.officeTabs else { return }
        self.apple("trash", self.meCtl.selfOffice()); self.meCtl.backToRoot(); self.tab(self.tabKeys.first ?? "today")
      }),
      // (measurement, Haris 2026-11-11 07:58: back from a client's Client Assets to All Client Assets — every row or tile set
      //  again with its signature before and after, any tile made anew, every title / line set on Apple's bar, and the
      //  search box's fill, frame by frame, with their times)
      ("aCaAll", { if self.meApple { self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.command(["show": true, "me": AppData.shared.me ?? "", "start": [String: Any]()]) } }),
      ("aCaAllWait", {}),
      ("aCaOpen", { if self.meApple { self.apple("caOpen", ["r": self.assetsCtl.selfOpenClient()]) } }),
      ("aCaOpenWait", {}),
      ("aCaLift", { if self.meApple { self.apple("caLift", self.assetsCtl.selfLift) } }),
      // (live, the full test 2026-11-16: a folder added elsewhere while the client's Client Assets are open — it arrives in
      //  place, the page not drawn again)
      ("aLiveA", {
        guard self.meApple, let c = self.assetsCtl.selfTop["client"] as? String, !c.isEmpty else { self.apple("liveAssets", ["none": "not open", "top": self.assetsCtl.selfTop]); return }
        self.liveBefore = ["top": self.assetsCtl.selfTop]
        self.elsewhere("/api/app/act", ["ev": "caNewFolder", "client": c, "name": "Live \(Int(Date().timeIntervalSince1970) % 100000)", "op": UUID().uuidString]) { r in self.liveBefore["sent"] = r }
      }),
      ("aLiveAWait", {}),
      ("aLiveARead", { if self.meApple, self.liveBefore["top"] != nil { self.apple("liveAssets", ["before": self.liveBefore, "after": self.assetsCtl.selfTop]) } }),
      ("aCaBack", {
        guard self.meApple else { return }
        BarLog.start()
        let nav = self.assetsCtl.appleNav
        // (each frame of the slide back: the search box's fill on Apple's bar, as the video showed it coming in)
        func field(_ v: UIView?) -> UISearchTextField? { guard let v = v else { return nil }; if let f = v as? UISearchTextField { return f }; for s in v.subviews { if let f = field(s) { return f } }; return nil }
        SelfFrames.run(1.6, {
          let f = field(nav?.navigationBar)
          return ["t": Int((CACurrentMediaTime() - BarLog.t0) * 1000), "field": f != nil, "alpha": Double(f?.alpha ?? -1),
                  "bgAlpha": Double(f?.subviews.first?.alpha ?? -1), "y": Double(f?.convert(CGPoint.zero, to: nil).y ?? -1)]
        }) { fr in self.apple("caBackFrames", ["frames": fr]) }
        self.assetsCtl.selfBack()
      }),
      ("aCaBackWait", {}),
      ("aCaBackWait2", {}),
      ("aCaBackWait3", {}),
      ("aCaBackRead", {
        guard self.meApple else { return }
        BarLog.on = false; self.apple("caBack", ["notes": BarLog.notes]); self.assetsCtl.close(animated: false); self.tab(self.tabKeys.first ?? "today")
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
      // (measurement, Haris 2026-11-10 21:34: "Active · 18" doubled in Team members' scope bar while going back to it — a page
      //  with Apple's search and scope bar, another page pushed over it, then back, filmed: how many "Active · 18" words show
      //  in Apple's bar each frame and where; 0 plain, 1 no big title (.never), as our pushed pages have)
      ("aScV0", { self.scopeBase(0) }), ("aScV0w", {}), ("aScV0p", { self.scopeOver() }), ("aScV0pw", {}), ("aScV0b", { self.scopeBack(0) }), ("aScV0bw", {}), ("aScV0x", {}),
      ("aScV1", { self.scopeBase(1) }), ("aScV1w", {}), ("aScV1p", { self.scopeOver() }), ("aScV1pw", {}), ("aScV1b", { self.scopeBack(1) }), ("aScV1bw", {}), ("aScV1x", {}),
      ("aBarBack", { self.tab("projects"); AppleTabs.shared?.clientsNav.popToRootViewController(animated: false) }),
      // a long-ago comment opened as from the Inbox: in view once everything has come
      ("aFocus", { if let b = best { self.openTaskPage(b.0, tab: "comments", focus: "\(b.0)~\(b.1)") } }),
      ("aFocusWait", {}),
      ("aFocusRead", {
        if let b = best { self.apple("focus", self.taskPages.last?.feed?.selfInView(b.1) ?? ["feed": false]) } else { self.apple("focus", ["none": true]) }
        for x in self.taskPages { self.closeTaskPage(x, animated: false) }
      }),
      // (Haris 2026-11-16: a client tapped in My Day's search — where it goes; a Client Assets file's link — the preview
      //  flying out of its picture and back into it)
      ("aFindC", {
        self.tab("today")
        // (a client as search gives it — its Clients-list id, the one its page is opened by)
        let rows = (AppData.shared.screen("clients", ServerHome.clientsJSON("view=list")).model?["rows"] as? [[String: Any]]) ?? []
        guard let cid = rows.first?["id"] as? String else { self.apple("findC", ["none": "no client"]); return }
        AppleHomeBits.shared.search?.isActive = true
        ClientTrail.notes = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ClientTrail.note("tap \(cid)"); self.ev(self.homeIfMade, ["ev": "client", "id": cid]) }
      }),
      ("aFindCWait", {}),
      ("aFindCRead", {
        let cn = AppleTabs.shared?.clientsNav, hn = self.clientsHereNav
        self.apple("findC", ["tab": self.selectedTabKey, "clientsOn": self.clientsOn, "pushed": ClientVC.pushed, "wanted": self.clientsWanted,
                             "clientsNav": cn?.viewControllers.map { String(describing: type(of: $0)) } ?? [], "hereNav": hn?.viewControllers.map { String(describing: type(of: $0)) } ?? [],
                             "own": AppleTabs.shared?.ownNav.map { String(describing: type(of: $0.viewControllers.first as Any)) } ?? "",
                             "page": ["made": self.clientPageIfMade != nil, "hidden": self.clientPageIfMade?.isHidden ?? true, "window": self.clientPageIfMade?.window != nil],
                             "query": self.serverClients.query, "on": self.serverClients.on, "off": self.serverClients.off, "trail": ClientTrail.notes])
        self.tab("today")
      }),
      // (Haris 2026-11-18 22:39: on the Clients tab, back from a client's page, a tap on a client within about a second did
      //  nothing — the same client tapped again 0.1 / 0.3 / 0.6 / 1.0 / 1.5 s after ‹, and every 0.05 s what the app and
      //  Apple's navigation say, so the one place that holds the tap back is seen, not guessed)
      ("aReTap", {
        let delays: [Double] = [0.1, 0.3, 0.6, 1.0, 1.5]
        var all: [String: Any] = [:]
        // one page, five times: opened from its list, ‹, then the same row tapped again `d` s after ‹ — every 0.05 s what
        // Apple's navigation and the app's own record say
        func run(_ name: String, nav: @escaping () -> UINavigationController?, tap: @escaping () -> Void, record: @escaping () -> String,
                 opened: @escaping () -> Bool, then: @escaping () -> Void) {
          guard let base = nav()?.viewControllers.count, base > 0 else { all[name] = ["none": "no navigation"]; then(); return }
          var rounds: [[String: Any]] = []
          func state(_ t0: CFTimeInterval) -> String {
            let n = nav()
            return String(format: "%.2f", CACurrentMediaTime() - t0) + " moving=\(n?.transitionCoordinator != nil) n=\(n?.viewControllers.count ?? -1) top=\(n?.topViewController.map { String(describing: type(of: $0)) } ?? "-") ours=\(record())"
          }
          func go(_ i: Int) {
            guard i < delays.count else { all[name] = ["rounds": rounds]; self.apple("reTap", all); then(); return }
            let d = delays[i]
            ClientTrail.notes = []
            tap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
              let first = opened() && (nav()?.viewControllers.count ?? 0) == base + 1
              let t0 = CACurrentMediaTime()
              var log: [String] = [], last = ""
              func watch() {
                let st = state(t0); let k = st.split(separator: " ").dropFirst().joined(separator: " ")
                if k != last { log.append(st); last = k }
                if CACurrentMediaTime() - t0 < d + 2.5 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { watch() } }
              }
              watch()
              nav()?.popViewController(animated: true)   // (‹)
              DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                log.append(String(format: "%.2f", CACurrentMediaTime() - t0) + " TAP"); ClientTrail.note("tap again after \(d)")
                tap()
                log.append(state(t0) + " (just after the tap)")
              }
              DispatchQueue.main.asyncAfter(deadline: .now() + d + 2.6) {
                let n = nav()
                let ok = opened() && (n?.viewControllers.count ?? 0) == base + 1
                rounds.append(["after": d, "firstOpened": first, "opened": ok, "log": log, "trail": ClientTrail.notes])
                if let n = n, n.viewControllers.count > base { n.popToViewController(n.viewControllers[base - 1], animated: false) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { go(i + 1) }
              }
            }
          }
          go(0)
        }
        let meNav = { AppleTabs.shared?.meNav }
        let kinds = { ((self.meCtl.selfPlans()["kinds"] as? [String]) ?? []).joined(separator: ",") }
        // 5. a sheet (New task — every form sheet opens the same way): closed, then opened again `d` s after
        let sheet = {
          self.tab(self.tabKeys.first ?? "today")
          var rounds: [[String: Any]] = []
          let isUp = { (self.presentedViewController is FormSheetVC) && self.presentedViewController?.isBeingDismissed == false }
          func go(_ i: Int) {
            guard i < delays.count else { all["sheet"] = ["rounds": rounds]; self.apple("reTap", all); return }
            let d = delays[i]
            _ = self.newTaskNative(view: "home", project: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
              let first = isUp()
              let t0 = CACurrentMediaTime(); var log: [String] = []
              self.presentedViewController?.dismiss(animated: true)   // (pulled down)
              DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                log.append(String(format: "%.2f TAP closing=%@", CACurrentMediaTime() - t0, String(self.presentedViewController?.isBeingDismissed ?? false)))
                let r = self.newTaskNative(view: "home", project: nil)
                log.append("asked=\(r) host=\(self.sheetHost() != nil)")
              }
              DispatchQueue.main.asyncAfter(deadline: .now() + d + 2.6) {
                rounds.append(["after": d, "firstOpened": first, "opened": isUp(), "log": log])
                self.presentedViewController?.dismiss(animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { go(i + 1) }
              }
            }
          }
          go(0)
        }
        // 4b. a task page from the first tab (fixed in build 1870 — kept checked)
        let task = {
          self.tab(self.tabKeys.first ?? "today")
          guard let tid = cards.first else { all["task"] = ["none": "no task"]; self.apple("reTap", all); sheet(); return }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let tnav = { self.stageNav }
            let base = tnav()?.viewControllers.count ?? 0
            run("task", nav: tnav, tap: { self.openTaskPage(tid, tab: "details", focus: "") },
                record: { "pages=\(self.taskPages.count) inView=\(self.taskPages.last?.superview != nil)" },
                opened: { (tnav()?.viewControllers.count ?? 0) == base + 1 && (tnav()?.topViewController as? TaskVC).map { t in self.taskPages.contains { $0 === t.page } && t.page.superview === t.view } == true }) {
              for x in self.taskPages { self.closeTaskPage(x, animated: false) }
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { sheet() }
            }
          }
        }
        // 4. Me › Client Assets › a client
        let assets = {
          self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.close(animated: false); AppleTabs.shared?.meNav.popToRootViewController(animated: false)
          self.assetsCtl.command(["show": true, "me": AppData.shared.me ?? "", "start": [String: Any]()])
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let cid = self.assetsCtl.selfFirstClient else { all["assets"] = ["none": "no client"]; self.apple("reTap", all); return }
            run("assets", nav: { self.assetsCtl.selfNav }, tap: { self.assetsCtl.selfTapClient(cid) }, record: { self.assetsCtl.selfKinds.joined(separator: ",") },
                opened: { self.assetsCtl.selfNav?.topViewController is AssetsVC && self.assetsCtl.selfKinds.last == "client" }) {
              self.assetsCtl.close(animated: false); self.tab(self.tabKeys.first ?? "today")
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { task() }
            }
          }
        }
        // 3. Me › Content plans › a plan
        let plans = {
          self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.close(animated: false); AppleTabs.shared?.meNav.popToRootViewController(animated: false)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.meCtl.selfOpen("plans") }
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            let base = meNav()?.viewControllers.count ?? 0
            run("plans", nav: meNav, tap: { _ = self.meCtl.selfOpenPlan() }, record: kinds,
                opened: { (meNav()?.viewControllers.count ?? 0) == base + 1 && kinds().hasSuffix(",plan") }) {
              self.meCtl.backToRoot(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { assets() }
            }
          }
        }
        // 2. Me › Team members › a member
        let team = {
          self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.close(animated: false); AppleTabs.shared?.meNav.popToRootViewController(animated: false)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.meCtl.selfOpen("team") }
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard let id = self.meCtl.selfTeam()["other"] as? String else { all["team"] = ["none": "no member"]; self.meCtl.backToRoot(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { plans() }; return }
            let base = meNav()?.viewControllers.count ?? 0
            run("team", nav: meNav, tap: { self.meCtl.selfOpenMember(id) }, record: kinds,
                opened: { (meNav()?.viewControllers.count ?? 0) == base + 1 && kinds().hasSuffix(",member") }) {
              self.meCtl.backToRoot(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { plans() }
            }
          }
        }
        // 1b. no Clients tab (the CD, Social…): Me › Clients
        if !self.tabKeys.contains("projects") {
          guard self.meApple else { all["clientsFromMe"] = ["none": "Me not in Apple's navigation"]; team(); return }
          self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.close(animated: false); AppleTabs.shared?.meNav.popToRootViewController(animated: false)
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let base = meNav()?.viewControllers.count ?? 0
            run("clientsFromMe", nav: meNav, tap: { self.openClientsFromMe() }, record: { "fromMe=\(self.clientsFromMeApple) on=\(self.clientsOn)" },
                opened: { meNav()?.topViewController is ClientsFromMeVC && (meNav()?.viewControllers.count ?? 0) == base + 1 }) {
              self.meCtl.backToRoot(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { team() }
            }
          }
          return
        }
        // 1. the Clients tab › a client
        let rows = (AppData.shared.screen("clients", ServerHome.clientsJSON("view=list")).model?["rows"] as? [[String: Any]]) ?? []
        guard let cid = rows.first?["id"] as? String else { all["clients"] = ["none": "no client"]; team(); return }
        self.tab("projects"); AppleTabs.shared?.clientsNav.popToRootViewController(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
          run("clients", nav: { AppleTabs.shared?.clientsNav }, tap: { self.ev(self.clientsListIfMade, ["ev": "client", "id": cid]) },
              record: { "on=\(self.clientsOn) pushed=\(ClientVC.pushed) waiting=\(self.clientPushWaiting != nil) hidden=\(self.clientPageIfMade?.isHidden ?? true) shown=\(self.clientsShownId ?? "-")" },
              opened: { AppleTabs.shared?.clientsNav.topViewController is ClientVC && self.clientsShownId == cid }) {
            AppleTabs.shared?.clientsNav.popToRootViewController(animated: false); team()
          }
        }
      }),
      ("aReTapWait0", {}),
      ("aReTapWait1", {}),
      ("aReTapWait2", {}),
      ("aReTapWait3", {}),
      ("aReTapWait4", {}),
      ("aReTapWait5", {}),
      ("aReTapWait6", {}),
      ("aReTapWait7", {}),
      ("aReTapWait8", {}),
      ("aReTapWait9", {}),
      ("aReTapWait10", {}),
      ("aReTapWait11", {}),
      ("aReTapWait12", {}),
      ("aReTapWait13", {}),
      ("aReTapWait14", {}),
      ("aReTapWait15", {}),
      ("aReTapWait16", {}),
      ("aReTapWait17", {}),
      ("aReTapWait18", {}),
      ("aReTapWait19", {}),
      ("aReTapWait20", {}),
      ("aReTapWait21", {}),
      ("aReTapWait22", {}),
      ("aReTapWait23", {}),
      ("aReTapWait24", {}),
      ("aReTapWait25", {}),
      ("aReTapWait26", {}),
      ("aReTapWait27", {}),
      ("aReTapWait28", {}),
      ("aReTapWait29", {}),
      ("aReTapWait30", {}),
      ("aReTapWait31", {}),
      ("aReTapWait32", {}),
      ("aReTapWait33", {}),
      ("aReTapWait34", {}),
      ("aReTapWait35", {}),
      ("aReTapWait36", {}),
      ("aReTapWait37", {}),
      ("aReTapWait38", {}),
      ("aReTapWait39", {}),
      ("aReTapWait40", {}),
      ("aReTapWait41", {}),
      ("aReTapWait42", {}),
      ("aReTapWait43", {}),
      ("aReTapWait44", {}),
      ("aReTapWait45", {}),
      ("aReTapWait46", {}),
      ("aReTapWait47", {}),
      ("aReTapWait48", {}),
      ("aReTapWait49", {}),
      ("aReTapWait50", {}),
      ("aReTapWait51", {}),
      ("aReTapWait52", {}),
      ("aReTapWait53", {}),
      ("aReTapWait54", {}),
      ("aReTapWait55", {}),
      ("aReTapWait56", {}),
      ("aReTapWait57", {}),
      ("aReTapWait58", {}),
      ("aReTapWait59", {}),
      ("aReTapWait60", {}),
      ("aReTapWait61", {}),
      ("aReTapWait62", {}),
      ("aReTapWait63", {}),
      ("aReTapWait64", {}),
      ("aReTapWait65", {}),
      ("aReTapWait66", {}),
      ("aReTapWait67", {}),
      ("aReTapWait68", {}),
      ("aReTapWait69", {}),
      ("aReTapWait70", {}),
      ("aReTapWait71", {}),
      ("aReTapWait72", {}),
      ("aReTapWait73", {}),
      ("aReTapWait74", {}),
      ("aReTapWait75", {}),
      ("aReTapWait76", {}),
      ("aReTapWait77", {}),
      ("aReTapWait78", {}),
      ("aReTapWait79", {}),
      ("aReTapWait80", {}),
      ("aReTapWait81", {}),
      ("aReTapWait82", {}),
      ("aReTapWait83", {}),
      ("aReTapWait84", {}),
      ("aReTapWait85", {}),
      ("aReTapWait86", {}),
      ("aReTapWait87", {}),
      ("aReTapWait88", {}),
      ("aReTapWait89", {}),
      ("aReTapWait90", {}),
      ("aReTapWait91", {}),
      ("aReTapWait92", {}),
      ("aReTapWait93", {}),
      ("aReTapWait94", {}),
      ("aReTapWait95", {}),
      ("aReTapWait96", {}),
      ("aReTapWait97", {}),
      ("aReTapWait98", {}),
      ("aReTapWait99", {}),
      ("aReTapWait100", {}),
      ("aReTapWait101", {}),
      ("aReTapWait102", {}),
      ("aReTapWait103", {}),
      // (the search pilot on the Clients list, Haris 2026-11-19 12:06: where Apple's bar, its big title and its search are
      //  at each moment — opened, scrolled down, back at the top, pulled down, after another tab — and a picture of each)
      ("aSrchOpen", { self.tab("projects"); AppleTabs.shared?.clientsNav.popToRootViewController(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.srchAdd("open") } }),
      ("aSrchDown", { if let sv = self.clientsListIfMade?.appleScroll { sv.setContentOffset(CGPoint(x: 0, y: sv.contentOffset.y + 320), animated: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.srchAdd("down") } }),
      ("aSrchTop", { if let sv = self.clientsListIfMade?.appleScroll { sv.setContentOffset(CGPoint(x: 0, y: -sv.adjustedContentInset.top), animated: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.srchAdd("top") } }),
      ("aSrchPull", { if let sv = self.clientsListIfMade?.appleScroll { sv.setContentOffset(CGPoint(x: 0, y: -sv.adjustedContentInset.top - 70), animated: true)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sv.setContentOffset(CGPoint(x: 0, y: -sv.adjustedContentInset.top), animated: true) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.srchAdd("pull") } }),
      // (back to the list from a client — the jump Haris saw, 2026-11-19 15:02: from the list at the top, with the search tucked,
      //  and just pulled; a client opened, ‹, and every 0.03 s for 1.8 s where the bar, the search and the list are)
      ("aSrchBack", {
        let rows = (AppData.shared.screen("clients", ServerHome.clientsJSON("view=list")).model?["rows"] as? [[String: Any]]) ?? []
        guard let cid = rows.first?["id"] as? String else { self.srchAddAny("back", ["none": "no client"]); return }
        self.tab("projects"); AppleTabs.shared?.clientsNav.popToRootViewController(animated: false)
        // (and, as Haris does — 15:06 — a scroll right after coming back: up a little and let go, or pulled down and let go,
        //  0.35 s after ‹)
        let starts: [(String, CGFloat, CGFloat)] = [("top", 0, 0), ("tucked", 70, 0), ("part", 30, 0), ("top+up", 0, 60), ("top+pull", 0, -60), ("tucked+pull", 70, -60)]
        var out: [String: Any] = ["clients": rows.count]
        func go(_ i: Int) {
          guard i < starts.count else { self.srchAddAny("back", out); return }
          let (name, dy, flick) = starts[i]
          if let sv = self.clientsListIfMade?.appleScroll { sv.setContentOffset(CGPoint(x: 0, y: -sv.adjustedContentInset.top + dy), animated: false) }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let before = self.srchLine(CACurrentMediaTime())
            self.ev(self.clientsListIfMade, ["ev": "client", "id": cid])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
              let t0 = CACurrentMediaTime(); var log: [String] = [], last = ""
              func watch() {
                let l = self.srchLine(t0); let k = l.split(separator: " ").dropFirst().joined(separator: " ")
                if k != last { log.append(l); last = k }
                if CACurrentMediaTime() - t0 < 1.8 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { watch() } }
              }
              watch()
              AppleTabs.shared?.clientsNav.popViewController(animated: true)   // (‹)
              if flick != 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                  log.append(String(format: "%.2f SCROLL %d", CACurrentMediaTime() - t0, Int(flick)))
                  if let sv = self.clientsListIfMade?.appleScroll {
                    let y0 = sv.contentOffset.y; sv.setContentOffset(CGPoint(x: 0, y: y0 + flick), animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                      log.append(String(format: "%.2f LET GO", CACurrentMediaTime() - t0))
                      let top = -sv.adjustedContentInset.top, maxY = max(top, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
                      sv.setContentOffset(CGPoint(x: 0, y: min(maxY, max(top, sv.contentOffset.y))), animated: true)
                    }
                  }
                }
              }
              DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                out[name] = ["before": before, "log": log]
                AppleTabs.shared?.clientsNav.popToRootViewController(animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { go(i + 1) }
              }
            }
          }
        }
        go(0)
      }),
      ("aSrchBackW0", {}), ("aSrchBackW1", {}), ("aSrchBackW2", {}), ("aSrchBackW3", {}), ("aSrchBackW4", {}), ("aSrchBackW5", {}), ("aSrchBackW6", {}), ("aSrchBackW7", {}), ("aSrchBackW8", {}), ("aSrchBackW9", {}), ("aSrchBackW10", {}), ("aSrchBackW11", {}),
      // (pages opened from a list, their search tucking away — Haris 2026-11-19 15:16; Client Assets is a tab for some roles
      //  and opened from Me for others, both kept as they are: 15:16): a client's page, Team members, All Client Assets — each
      //  opened fresh every round, at its top or scrolled, a page opened from it, ‹, a scroll right after; every 0.03 s the
      //  bar, the search and the list)
      ("aPush", {
        var out: [String: Any] = [:]
        let rounds: [(String, CGFloat, CGFloat, Bool)] = [("open", 0, 0, false), ("top", 0, 0, true), ("top+pull", 0, -60, true), ("top+up", 0, 60, true), ("scrolled", 250, 0, true), ("scrolled+pull", 250, -60, true)]
        func line(_ nav: UINavigationController?, _ pg: UIViewController?, _ t0: CFTimeInterval) -> String {
          let nb = nav?.navigationBar, sb = pg?.navigationItem.searchController?.searchBar, sv = (pg as? ClientsPushedVC)?.h.appleScroll
          let f = sb.flatMap { b in b.window.map { _ in b.convert(b.bounds, to: nil) } } ?? .zero
          return String(format: "%.2f bar=%d sy=%d sh=%d off=%d in=%d n=%d top=%@", CACurrentMediaTime() - t0, Int(nb?.frame.height ?? -1), Int(f.minY), Int(f.height),
                        Int(sv?.contentOffset.y ?? 0), Int(sv?.adjustedContentInset.top ?? 0), nav?.viewControllers.count ?? -1,
                        nav?.topViewController.map { String(describing: type(of: $0)) } ?? "-")
        }
        func page(_ name: String, nav: @escaping () -> UINavigationController?, open: @escaping () -> Void, child: @escaping () -> Void, then: @escaping () -> Void) {
          var res: [String: Any] = [:]
          func go(_ i: Int) {
            guard i < rounds.count else { out[name] = res; self.srchAddAny("push", out); then(); return }
            let (rn, dy, flick, kid) = rounds[i]
            open()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
              let n = nav(), pg = n?.topViewController
              let fresh = line(n, pg, CACurrentMediaTime())
              if dy > 0, let sv = (pg as? ClientsPushedVC)?.h.appleScroll { sv.setContentOffset(CGPoint(x: 0, y: -sv.adjustedContentInset.top + dy), animated: true) }
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let before = line(n, pg, CACurrentMediaTime())
                guard kid else { res[rn] = ["fresh": fresh, "before": before]; go(i + 1); return }
                child()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                  let t0 = CACurrentMediaTime(); var log: [String] = [], last = ""
                  func watch() {
                    let l = line(n, pg, t0); let k = l.split(separator: " ").dropFirst().joined(separator: " ")
                    if k != last { log.append(l); last = k }
                    if CACurrentMediaTime() - t0 < 1.8 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { watch() } }
                  }
                  watch()
                  n?.popViewController(animated: true)   // (‹)
                  if flick != 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                      log.append(String(format: "%.2f SCROLL %d", CACurrentMediaTime() - t0, Int(flick)))
                      if let sv = (pg as? ClientsPushedVC)?.h.appleScroll {
                        sv.setContentOffset(CGPoint(x: 0, y: sv.contentOffset.y + flick), animated: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                          log.append(String(format: "%.2f LET GO", CACurrentMediaTime() - t0))
                          let top = -sv.adjustedContentInset.top, maxY = max(top, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
                          sv.setContentOffset(CGPoint(x: 0, y: min(maxY, max(top, sv.contentOffset.y))), animated: true)
                        }
                      }
                    }
                  }
                  DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { res[rn] = ["fresh": fresh, "before": before, "log": log]; go(i + 1) }
                }
              }
            }
          }
          go(0)
        }
        let meNav = { AppleTabs.shared?.meNav }
        let tid = cards.first
        let assets = {
          page("assets", nav: { self.assetsCtl.selfNav }, open: {
            self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.close(animated: false); AppleTabs.shared?.meNav.popToRootViewController(animated: false)
            self.assetsCtl.command(["show": true, "me": AppData.shared.me ?? "", "start": [String: Any]()])
          }, child: { if let c = self.assetsCtl.selfFirstClient { self.assetsCtl.selfTapClient(c) } }) {
            self.assetsCtl.close(animated: false); self.tab(self.tabKeys.first ?? "today")
          }
        }
        let team = {
          page("team", nav: meNav, open: {
            self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.close(animated: false); AppleTabs.shared?.meNav.popToRootViewController(animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.meCtl.selfOpen("team") }
          }, child: { if let id = self.meCtl.selfTeam()["other"] as? String { self.meCtl.selfOpenMember(id) } }) {
            self.meCtl.backToRoot(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { assets() }
          }
        }
        let rows = (AppData.shared.screen("clients", ServerHome.clientsJSON("view=list")).model?["rows"] as? [[String: Any]]) ?? []
        guard self.tabKeys.contains("projects"), let cid = rows.first?["id"] as? String, let t = tid else { out["client"] = ["none": "no Clients tab, client or task"]; team(); return }
        page("client", nav: { AppleTabs.shared?.clientsNav }, open: {
          self.tab("projects"); AppleTabs.shared?.clientsNav.popToRootViewController(animated: false)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.ev(self.clientsListIfMade, ["ev": "client", "id": cid]) }
        }, child: { self.openTaskPage(t, tab: "details", focus: "") }) {
          AppleTabs.shared?.clientsNav.popToRootViewController(animated: false); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { team() }
        }
      }),
      ("aPushW0", {}), ("aPushW1", {}), ("aPushW2", {}), ("aPushW3", {}), ("aPushW4", {}), ("aPushW5", {}), ("aPushW6", {}), ("aPushW7", {}), ("aPushW8", {}), ("aPushW9", {}), ("aPushW10", {}), ("aPushW11", {}), ("aPushW12", {}), ("aPushW13", {}), ("aPushW14", {}), ("aPushW15", {}), ("aPushW16", {}), ("aPushW17", {}), ("aPushW18", {}), ("aPushW19", {}), ("aPushW20", {}), ("aPushW21", {}), ("aPushW22", {}), ("aPushW23", {}), ("aPushW24", {}), ("aPushW25", {}), ("aPushW26", {}), ("aPushW27", {}), ("aPushW28", {}), ("aPushW29", {}), ("aPushW30", {}), ("aPushW31", {}), ("aPushW32", {}), ("aPushW33", {}), ("aPushW34", {}), ("aPushW35", {}), ("aPushW36", {}), ("aPushW37", {}), ("aPushW38", {}), ("aPushW39", {}), ("aPushW40", {}), ("aPushW41", {}), ("aPushW42", {}), ("aPushW43", {}), ("aPushW44", {}), ("aPushW45", {}), ("aPushW46", {}), ("aPushW47", {}), ("aPushW48", {}), ("aPushW49", {}), ("aPushW50", {}), ("aPushW51", {}), ("aPushW52", {}), ("aPushW53", {}), ("aPushW54", {}), ("aPushW55", {}), ("aPushW56", {}), ("aPushW57", {}), ("aPushW58", {}), ("aPushW59", {}),
      // (the task page opening: the frost Haris saw for a glance as it slides in, 2026-11-19 18:15 — every frame for 1.2 s:
      //  the page's list, where it is against its top, Apple's frost under the bar (hidden or not), Home's list under it,
      //  and the bar's own background; three openings)
      ("aTaskFrost", {
        guard let tid = cards.first else { self.apple("taskFrost", ["none": "no task"]); return }
        var runs: [[String]] = []
        func bg(_ v: UIView?) -> String {
          guard let v = v else { return "-" }
          var out: [String] = []
          func walk(_ x: UIView, _ d: Int) { let n = String(describing: type(of: x)); if n.contains("Background") || n.contains("Effect") || n.contains("Pocket") { out.append("\(n):\(String(format: "%.2f", x.alpha))\(x.isHidden ? "h" : "")") }; if d < 4 { x.subviews.forEach { walk($0, d + 1) } } }
          walk(v, 0); return out.joined(separator: ",")
        }
        func run(_ i: Int) {
          guard i < 3 else { self.apple("taskFrost", ["runs": runs]); return }
          self.tab(self.tabKeys.first ?? "today")
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let nav = self.stageNav, home = Main.shared.homeIfMade?.appleScroll
            let t0 = CACurrentMediaTime(); var log: [String] = [], last = ""
            self.openTaskPage(tid, tab: "details", focus: "")
            func watch() {
              let vc = nav?.topViewController as? TaskVC, sv = vc?.page.scroll
              var e = "-"
              if #available(iOS 26.0, *), let sv = sv { e = sv.topEdgeEffect.isHidden ? "hidden" : String(describing: sv.topEdgeEffect.style) }
              let k = String(format: "top=%@ task[off=%d in=%d edge=%@] home[off=%d in=%d] bar=%@", nav?.topViewController.map { String(describing: type(of: $0)) } ?? "-",
                             Int(sv?.contentOffset.y ?? 0), Int(sv?.adjustedContentInset.top ?? 0), e, Int(home?.contentOffset.y ?? 0), Int(home?.adjustedContentInset.top ?? 0), bg(nav?.navigationBar))
              if k != last { log.append(String(format: "%.3f ", CACurrentMediaTime() - t0) + k); last = k }
              if CACurrentMediaTime() - t0 < 1.2 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { watch() } }
            }
            watch()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
              runs.append(log); for x in self.taskPages { self.closeTaskPage(x, animated: false) }
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run(i + 1) }
            }
          }
        }
        run(0)
      }),
      ("aTaskFrostW0", {}), ("aTaskFrostW1", {}), ("aTaskFrostW2", {}), ("aTaskFrostW3", {}), ("aTaskFrostW4", {}),
      // (search with the keyboard up, scrolled to the end: the last result and the scroll bar's end above the keyboard —
      //  Haris 2026-11-19 18:48)
      ("aFindKb", {
        var kbTop: CGFloat = -1
        let o = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { n in
          if let r = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue { kbTop = r.minY }
        }
        self.tab(self.tabKeys.first ?? "today")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.shownScreen?.selfFind("a") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
          guard let sv = self.shownScreen?.appleScroll else { self.apple("findKb", ["none": "no list"]); return }
          // (to the very end: Apple's list sizes its rows as they come, so its end is gone to again until it stays put)
          func toEnd() { sv.layoutIfNeeded(); sv.setContentOffset(CGPoint(x: 0, y: max(-sv.adjustedContentInset.top, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)), animated: false); sv.layoutIfNeeded() }
          for _ in 0..<6 { toEnd() }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { toEnd() }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NotificationCenter.default.removeObserver(o)
            let cv = sv as? UICollectionView, cells = cv?.visibleCells ?? []
            // (the list's very last row — not the lowest one drawn, which may sit past the screen's foot)
            let lastIP: IndexPath? = cv.flatMap { c in (0..<c.numberOfSections).reversed().first { c.numberOfItems(inSection: $0) > 0 }.map { IndexPath(item: c.numberOfItems(inSection: $0) - 1, section: $0) } }
            let last = lastIP.flatMap { cv?.layoutAttributesForItem(at: $0) }.map { cv!.convert($0.frame, to: nil).maxY } ?? -1
            let barEnd = sv.convert(sv.bounds, to: nil).maxY - (sv.adjustedContentInset.bottom - sv.contentInset.bottom) - sv.verticalScrollIndicatorInsets.bottom   // (the scroll bar's end: the view's foot less the safe area and its own inset)
            self.apple("findKb", ["kbTop": Int(kbTop), "lastResultBottom": Int(last), "barEnd": Int(barEnd), "cells": cells.count,
                                  "insetBottom": Int(sv.contentInset.bottom), "adjBottom": Int(sv.adjustedContentInset.bottom), "barInset": Int(sv.verticalScrollIndicatorInsets.bottom),
                                  "ok": kbTop > 0 && last > 0 && last <= kbTop + 1 && barEnd <= kbTop + 1])
            self.shownScreen?.selfFindDone()
          }
        }
      }),
      ("aFindKbW0", {}), ("aFindKbW1", {}),
      // (a file opened from Client Assets' search and closed: why it flew back or faded — the preview's own note, and whether
      //  its picture in the results was found on screen as it opened and as it closed — Haris 2026-11-19 18:52)
      // (a file opened from Client Assets' search and closed — Haris 2026-11-19 18:49 / 19:07: in steps, each with its own
      //  picture, reading Client Assets' own list — the first runs read Me's list, which is open under it)
      ("aFindPrevOpen", {
        self.tab(self.tabKeys.first ?? "today"); self.selectTab("me"); self.assetsCtl.close(animated: false); AppleTabs.shared?.meNav.popToRootViewController(animated: false)
        self.assetsCtl.command(["show": true, "me": AppData.shared.me ?? "", "start": [String: Any]()])
      }),
      ("aFindPrevSearch", {
        let files = (AppData.shared.meModel("assets", "assets", [""])?["files"] as? [[String: Any]]) ?? []
        let name = (files.first { CommentCell.isPic($0["name"] as? String ?? "") }?["name"] as? String) ?? "e"
        let q = String(name.prefix(3))
        var o: [String: Any] = ["query": q, "top": String(describing: type(of: self.assetsCtl.selfNav?.topViewController as Any)), "assetsOpen": self.assetsCtl.isOpen]
        if let vc = self.assetsCtl.selfNav?.topViewController, let sc = vc.navigationItem.searchController {
          sc.isActive = true; sc.searchBar.text = q; sc.searchResultsUpdater?.updateSearchResults(for: sc); o["searched"] = true
        } else { o["searched"] = false }
        self.apple("findPrev", o)
      }),
      ("aFindPrevTap", {
        var o = (((self.selfResult["apple"] as? [String: Any])?["findPrev"]) as? [String: Any]) ?? [:]
        guard let cv = self.assetsCtl.shown?.appleScroll as? UICollectionView else { o["none"] = "no Client Assets list"; self.apple("findPrev", o); return }
        // (each row on screen: its words, its pictures — drawn or not, how wide — and the file mark on each)
        let allFiles = (AppData.shared.meModel("assets", "assets", [""])?["files"] as? [[String: Any]]) ?? []
        let picIds = Set(allFiles.filter { CommentCell.isPic($0["name"] as? String ?? "") }.map { FileTouch.key($0) })
        var rows: [String] = [], pick: IndexPath?
        for ip in cv.indexPathsForVisibleItems.sorted() {
          guard let c = cv.cellForItem(at: ip) else { continue }
          var ivs: [UIImageView] = []; func walk(_ v: UIView) { if let iv = v as? UIImageView { ivs.append(iv) }; v.subviews.forEach(walk) }; walk(c.contentView)
          let words = (c.contentConfiguration as? UIListContentConfiguration)?.text ?? ""
          let pics = ivs.map { "\($0.image != nil ? "img" : "none")w\(Int($0.bounds.width))mark=\(FileTouch.markOf($0) ?? "-")" }.joined(separator: "|")
          rows.append("\(ip.section)/\(ip.item) \(words) [\(pics)]")
          // (a picture file's row, by its mark — the rows' names aren't in Apple's configuration, so words came back empty)
          if pick == nil, ivs.contains(where: { iv in FileTouch.markOf(iv).map { picIds.contains($0) } ?? false }) { pick = ip }
        }
        o["rows"] = rows
        guard let ip = pick else { o["none"] = "no file row"; self.apple("findPrev", o); return }
        o["tapped"] = rows.first { $0.hasPrefix("\(ip.section)/\(ip.item) ") } ?? ""
        FileTouch.note(cv.cellForItem(at: ip))
        cv.delegate?.collectionView?(cv, didSelectItemAt: ip)
        self.apple("findPrev", o)
      }),
      ("aFindPrevShown", {
        var o = (((self.selfResult["apple"] as? [String: Any])?["findPrev"]) as? [String: Any]) ?? [:]
        o["preview"] = self.previewVC.map { $0.walkInfo } ?? ["shown": false]
        self.apple("findPrev", o)
        self.previewVC?.close()
      }),
      ("aFindPrevClosed", {
        var o = (((self.selfResult["apple"] as? [String: Any])?["findPrev"]) as? [String: Any]) ?? [:]
        o["closedHow"] = PreviewVC.lastClose
        self.apple("findPrev", o)
        self.assetsCtl.selfNav?.topViewController?.navigationItem.searchController?.isActive = false; self.assetsCtl.close(animated: false); self.tab(self.tabKeys.first ?? "today")
      }),
      ("aSrchTab", { self.tab(self.tabKeys.first ?? "today")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.tab("projects"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.srchAdd("tabBack") } } }),
      ("aLink", {
        let files = (AppData.shared.meModel("assets", "assets", [""])?["files"] as? [[String: Any]]) ?? []
        guard let f = files.first(where: { ($0["file"] as? String) != nil && CommentCell.isPic($0["name"] as? String ?? "") }), let path = f["file"] as? String else { self.apple("link", ["none": "no picture file"]); return }
        self.serverTask.request("/api/flink", body: ["path": path]) { j in
          guard let u = (j?["url"] as? String).flatMap(URL.init) else { self.apple("link", ["none": "no link", "j": "\(j ?? [:])"]); return }
          self.apple("link", ["url": u.absoluteString, "file": f["id"] ?? ""])
          self.openLink(u)
        }
      }),
      ("aLinkWait", {}), ("aLinkWait2", {}),
      ("aLinkRead", {
        var o = (((self.selfResult["apple"] as? [String: Any])?["link"]) as? [String: Any]) ?? [:]
        o["preview"] = self.previewVC.map { $0.walkInfo } ?? ["shown": false]
        o["marked"] = (o["file"] as? String).map { FileTouch.marked($0, in: self.screenWindow) != nil } ?? false
        o["assets"] = ["open": self.assetsCtl.isOpen, "top": self.assetsCtl.top.map { String(describing: type(of: $0)) } ?? ""]
        self.apple("link", o)
        self.previewVC?.close()
      }),
      ("aLinkClosed", {
        var o = (((self.selfResult["apple"] as? [String: Any])?["link"]) as? [String: Any]) ?? [:]
        o["closedHow"] = PreviewVC.lastClose; o["trail"] = ClientTrail.link
        self.apple("link", o)
        self.assetsCtl.close(animated: false); self.tab("today")
      }),
      // Colours (the full test, Haris 2026-11-16): each tab's first screen and a task page, light and dark
      ("aContrast", { self.tab(self.tabKeys.first ?? "today") }),
      ("aContrastRead", { contrastRun() }),
      ("aContrastWait", {}), ("aContrastWait2", {}), ("aContrastWait3", {}), ("aContrastWait4", {}),
      ("aContrastTask", { contrastTask() }),
      // (ios/walktest.py turns the simulator light on this step and dark again on aContrastDark)
      ("aContrastLight", {}), ("aContrastLightWait", {}), ("aContrastLightWait2", {}),
      ("aContrastLightRead", { contrastRun() }),
      ("aContrastLightWait3", {}), ("aContrastLightWait4", {}), ("aContrastLightWait5", {}), ("aContrastLightWait6", {}),
      ("aContrastLightTask", { contrastTask() }),
      ("aContrastDark", {}), ("aContrastDarkWait", {}),
      // The keyboard on return (the full test, Haris 2026-11-16): a comment being typed, the app sent away to another app and
      // back (ios/walktest.py does it on the "aKbAway" step) — the words still there, the keyboard as it was, the list where it was
      ("aKb", { self.tab(self.tabKeys.first ?? "today"); if let t = best?.0 ?? cards.first { self.openTaskPage(t, tab: "comments", focus: "") } }),
      ("aKbWait", {}),
      ("aKbType", {
        guard let c = self.composeIfMade else { self.apple("keyboard", ["none": "no comment box"]); return }
        c.text.becomeFirstResponder(); c.text.insertText("Draft kept 42")
      }),
      ("aKbTyped", {
        let f = p()?.feed
        self.liveBefore = ["text": self.composeIfMade?.text.text ?? "", "first": self.composeIfMade?.text.isFirstResponder ?? false, "y": Int(f?.scroll.contentOffset.y ?? -1)]
      }),
      ("aKbAway", {}), ("aKbAwayWait", {}), ("aKbAwayWait2", {}), ("aKbAwayWait3", {}),
      ("aKbRead", {
        let f = p()?.feed
        self.apple("keyboard", ["before": self.liveBefore, "text": self.composeIfMade?.text.text ?? "", "first": self.composeIfMade?.text.isFirstResponder ?? false,
                                "y": Int(f?.scroll.contentOffset.y ?? -1), "active": UIApplication.shared.applicationState == .active])
        self.composeIfMade?.text.text = ""; self.composeIfMade?.text.resignFirstResponder()
        for x in self.taskPages { self.closeTaskPage(x, animated: false) }
      }),
      // Live (the full test, Haris 2026-11-16): a change made elsewhere — straight to the server, as the Mac or another phone
      // would — while the page is open; read a few seconds later, without leaving the page
      ("aLiveC", { self.liveBefore = [:]; self.tab(self.tabKeys.first ?? "today"); if let t = best?.0 ?? cards.first { self.openTaskPage(t, tab: "comments", focus: "") } }),
      ("aLiveCWait", {}),
      ("aLiveCSend", {
        guard let f = p()?.feed, let t = p()?.taskId else { self.apple("liveComment", ["none": "no feed"]); return }
        self.liveBefore = ["n": f.selfOrder.count, "again": f.setAgain]
        self.elsewhere("/api/home/act", { () -> [String: Any] in let w = "Live check \(Int(Date().timeIntervalSince1970))"; return ["act": "comment", "id": t, "html": "<p>\(w)</p>", "text": w, "from": "task", "copy": true, "op": UUID().uuidString] }()) { r in self.liveBefore["sent"] = r }
        // (frame by frame while it arrives: each comment already there — the biggest move it made in one frame; a glide moves a
        //  few points a frame, a snap tens at once)
        // (each row's move frame by frame; a glide eases — its steps grow and shrink gradually — a snap is one step far bigger
        //  than the frames either side of it: the snap is what's flagged, with the steps around it and the list's own scroll)
        var last: [String: CGFloat] = [:], steps: [String: [CGFloat]] = [:], scrolls: [CGFloat] = [], lastY: CGFloat? = nil, frames = 0
        SelfFrames.run(3.0, {
          let now = f.selfRowTops; frames += 1
          for (id, y) in now { steps[id, default: []].append(last[id].map { abs(y - $0) } ?? 0) }
          let oy = f.scroll.contentOffset.y; scrolls.append(lastY.map { oy - $0 } ?? 0); lastY = oy
          last = now; return [:]
        }) { _ in
          var top: CGFloat = 0, snap: CGFloat = 0, around: [Int] = []
          for (_, st) in steps {
            for (i, d) in st.enumerated() where d > 0 {
              top = max(top, d)
              let prev = i > 0 ? st[i - 1] : 0, nxt = i + 1 < st.count ? st[i + 1] : 0
              if d > 12, max(prev, nxt) < d * 0.35, d > snap { snap = d; around = st[max(0, i - 3)...min(st.count - 1, i + 3)].map { Int($0.rounded()) } }
            }
          }
          let moving = scrolls.filter { abs($0) > 0.3 }.map { Int($0.rounded()) }
          self.apple("liveCommentFrames", ["frames": frames, "biggestStep": Int(top.rounded()), "snap": Int(snap.rounded()), "around": around,
                                            "scrollSteps": Array(moving.prefix(40)), "rows": steps.count])
        }
      }),
      ("aLiveCWait2", {}),
      ("aLiveCRead", {
        // (no task open — a role with no tasks to hand: the "none" from aLiveCSend stays, not the last check's before)
        guard let f = p()?.feed, self.liveBefore["n"] != nil else { for x in self.taskPages { self.closeTaskPage(x, animated: false) }; return }
        self.apple("liveComment", ["before": self.liveBefore, "after": f.selfOrder.count, "again": f.setAgain - ((self.liveBefore["again"] as? Int) ?? 0)])
        for x in self.taskPages { self.closeTaskPage(x, animated: false) }
      }),
      ("aLiveI", {
        guard self.tabKeys.contains("inbox") else { self.apple("liveInbox", ["none": "no Inbox tab"]); return }
        self.tab("inbox"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.inboxIfMade?.selfInboxTab("unread") }
      }),
      ("aLiveIWait", {}),
      ("aLiveISend", {
        guard let h = self.inboxIfMade, let first = (h.selfInbox["unread"] as? [String])?.first else { self.apple("liveInbox", ["none": "nothing unread", "inbox": self.inboxIfMade?.selfInbox ?? [:]]); return }
        self.liveBefore = ["inbox": h.selfInbox, "badge": self.tabBadge("inbox"), "id": first]
        self.elsewhere("/api/home/act", ["act": "read", "id": first, "from": "inbox", "copy": true, "op": UUID().uuidString]) { r in self.liveBefore["sent"] = r }
      }),
      ("aLiveIWait2", {}),
      ("aLiveIRead", {
        self.apple("liveInbox", ["before": self.liveBefore, "after": self.inboxIfMade?.selfInbox ?? [:], "badge": self.tabBadge("inbox"),
                                 "copyUnread": AppData.shared.screen("inbox", "all").model?["unread"] ?? -1])
        self.tab(self.tabKeys.first ?? "today")
      }),
      // Uploads and downloads (the full test, Haris 2026-11-16): a 20 MB file up as the comment box sends one (three 8 MB pieces
      // side by side), its progress read as it goes and the bar at the bottom while it does; put on a comment; then fetched back
      // as the preview's Download does — every byte the same, its progress too
      // Midnight (the full test, Haris 2026-11-16): iPhone's day-changed signal — every screen worked out again for the new day;
      // on the same day nothing on E11 Day is set again (only what changed changes)
      // Memory (the full test, Haris 2026-11-16): what the app holds once every page above has been through — iPhone's own
      // count (phys_footprint, as Xcode's gauge shows it)
      // Icon swaps filmed (Haris 2026-11-17 10:55: "check on simulator before, stop guessing"): ios/walktest.py films the
      // screen from aSwapRec to aSwapEnd (ios-swap.mp4) while aSwapLab shows each icon swap in each way, side by side
      ("aSwapRec", {}),
      ("aSwapLab", { self.swapLab() }),
      ("aSwapEnd", {}),
      ("aMem", {
        var info = task_vm_info_data_t(), n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n) } }
        self.apple("memory", ["MB": kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1])
      }),
      ("aDay", { self.tab(self.tabKeys.first ?? "today") }),
      ("aDaySend", {
        self.liveBefore = ["rows": self.homeView.rowsSet, "gen": AppData.shared.gen]
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
      }),
      ("aDayRead", { self.apple("day", ["before": self.liveBefore, "rows": self.homeView.rowsSet, "gen": AppData.shared.gen]) }),
      ("aUp", { self.liveBefore = [:]; self.tab(self.tabKeys.first ?? "today"); if let t = best?.0 ?? cards.first { self.openTaskPage(t, tab: "comments", focus: "") } }),
      ("aUpWait", {}),
      ("aUpSend", {
        guard let t = p()?.taskId else { self.apple("upload", ["none": "no task"]); return }
        var bytes = Data(count: 20 * 1024 * 1024); bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-up.bin")
        guard (try? bytes.write(to: url)) != nil else { self.apple("upload", ["none": "couldn't write"]); return }
        let name = "Selftest \(Int(Date().timeIntervalSince1970)).bin", t0 = CACurrentMediaTime()
        var steps = 0, back = 0, top = 0.0, bar = false
        Uploader.send(url, name: name, task: t, bar: true, cookies: self.serverTask.cookies, progress: { v in
          steps += 1; if v + 0.0001 < top { back += 1 }; top = max(top, v); if !UploadCenter.shared.jobs.isEmpty { bar = true }
        }) { path in
          var a: [String: Any] = ["path": path ?? "", "secs": Double(Int((CACurrentMediaTime() - t0) * 100)) / 100, "steps": steps, "backwards": back,
                                  "top": top, "bar": bar, "barGone": UploadCenter.shared.jobs.isEmpty, "size": bytes.count]
          self.apple("upload", a)
          guard let path = path else { return }
          // (on a comment, as the box does — the server's own act; the file's address comes back with the comment)
          self.serverTask.request("/api/home/act", body: ["act": "comment", "id": t, "html": "", "text": "", "from": "task", "copy": true, "op": UUID().uuidString,
                                                          "files": [["name": name, "size": bytes.count, "path": path]]]) { j in
            a["comment"] = (j?["ok"] as? Bool) == true; a["name"] = name; self.apple("upload", a)
          }
        }
        self.liveBefore["upBytes"] = bytes
      }),
      ("aUpWait2", {}), ("aUpWait3", {}), ("aUpWait4", {}), ("aUpWait5", {}),
      ("aUpDown", {
        var a = ((self.selfResult["apple"] as? [String: Any])?["upload"] as? [String: Any]) ?? [:]
        let t = p()?.taskId ?? "", name = a["name"] as? String ?? "-"
        let items = (AppData.shared.screen("comments", t).model?["items"] as? [[String: Any]]) ?? []
        let file = items.reversed().compactMap { ($0["files"] as? [[String: Any]])?.first { ($0["name"] as? String) == name } }.first
        a["inFeed"] = p()?.feed?.selfOrder.count ?? -1; a["fileListed"] = file != nil; self.apple("upload", a)
        guard let u = file?["url"] as? String, let url = URL(string: serverURL() + u.replacingOccurrences(of: "?view=1", with: "")) else { return }
        let t0 = CACurrentMediaTime(); var steps = 0, back: Int64 = 0, last: Int64 = 0
        self.serverTask.cookies { c in DispatchQueue.main.async {
          var r = URLRequest(url: url); if !c.isEmpty { r.setValue(c, forHTTPHeaderField: "Cookie") }
          _ = Transfers.shared.download(r, name: name, progress: { w, _ in steps += 1; if w < last { back += 1 }; last = w }) { dest in
            let got = dest.flatMap { try? Data(contentsOf: $0) }
            var b = ((self.selfResult["apple"] as? [String: Any])?["upload"] as? [String: Any]) ?? [:]
            b["down"] = ["secs": Double(Int((CACurrentMediaTime() - t0) * 100)) / 100, "steps": steps, "backwards": back, "size": got?.count ?? -1,
                         "same": got != nil && got == (self.liveBefore["upBytes"] as? Data)]
            self.apple("upload", b); self.liveBefore["upBytes"] = nil
          }
        } }
      }),
      ("aUpDownWait", {}), ("aUpDownWait2", {}), ("aUpDownWait3", {}),
      ("aUpDone", { for x in self.taskPages { self.closeTaskPage(x, animated: false) }; self.tab(self.tabKeys.first ?? "today") }),
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
  private func scopeBase(_ k: Int) {
    guard let nav = AppleTabs.shared?.clientsNav else { return }
    nav.popToRootViewController(animated: false)
    let vc = UIViewController(); vc.view.backgroundColor = HomeLook(lookBoth).bg
    vc.navigationItem.title = "Scope \(k)"
    if k == 1 { vc.navigationItem.largeTitleDisplayMode = .never; vc.navigationItem.backButtonDisplayMode = .minimal }
    let sc = UISearchController(searchResultsController: nil); sc.obscuresBackgroundDuringPresentation = false
    sc.searchBar.placeholder = "Search people"; sc.searchBar.scopeButtonTitles = ["Active · 18", "Past · 0"]; sc.searchBar.showsScopeBar = true
    if #available(iOS 16.0, *) { sc.scopeBarActivation = .manual; vc.navigationItem.preferredSearchBarPlacement = .stacked }
    vc.navigationItem.hidesSearchBarWhenScrolling = false
    vc.navigationItem.searchController = sc
    nav.pushViewController(vc, animated: false)
  }
  private func scopeOver() {
    guard let nav = AppleTabs.shared?.clientsNav else { return }
    let top = UIViewController(); top.view.backgroundColor = HomeLook(lookBoth).bg; top.navigationItem.title = "Over"
    top.navigationItem.largeTitleDisplayMode = .never
    nav.pushViewController(top, animated: true)
  }
  private func scopeBack(_ k: Int) {
    guard let nav = AppleTabs.shared?.clientsNav else { return }
    let t0 = CACurrentMediaTime()
    SelfFrames.run(0.9, {
      var q: [UIView] = [nav.view]; var seen: [String] = []
      while !q.isEmpty { let v = q.removeFirst(); q += v.subviews
        if let l = v as? UILabel, l.text == "Active · 18", l.window != nil, !l.isHidden, l.alpha > 0.05 {
          let f = l.convert(l.bounds, to: nil); seen.append("\(Int(f.minX)),\(Int(f.minY))") } }
      return ["t": Int((CACurrentMediaTime() - t0) * 1000), "n": seen.count, "at": seen.joined(separator: " ")]
    }) { frames in
      let most = frames.map { $0["n"] as? Int ?? 0 }.max() ?? 0
      var a = (self.selfResult["apple"] as? [String: Any]) ?? [:]; var v = (a["scopeBack"] as? [String: Any]) ?? [:]
      v["v\(k)"] = ["most": most, "after": frames.last?["n"] ?? -1, "frames": frames.enumerated().filter { $0.offset % 4 == 0 }.map { "\($0.element["t"] ?? 0)ms \($0.element["n"] ?? 0) [\($0.element["at"] ?? "")]" }]
      a["scopeBack"] = v; self.selfResult["apple"] = a
      nav.popToRootViewController(animated: false)
    }
    nav.popViewController(animated: true)
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
        let keep = !presented && (v === top || v === self.tabsMark || v === self.composeIfMade)
        if v.accessibilityElementsHidden == keep { v.accessibilityElementsHidden = !keep }
      }
    }
  }
}

// what a client tapped in search, and a file opened by a link, went through — kept only while the self-test runs (Haris
// 2026-11-16: the two that weren't fixed, read step by step instead of guessed)
enum ClientTrail {
  static var notes: [String] = [], link: [String] = []
  private static let t0 = CACurrentMediaTime()
  private static func at() -> String { String(format: "%.2f", CACurrentMediaTime() - t0) }
  // (who called: the app's own frames just above, by name)
  static func callers() -> String {
    Thread.callStackSymbols.dropFirst(2).prefix(8).compactMap { l -> String? in
      guard let r = l.range(of: "E11Console") ?? l.range(of: "$s10E11Console") else { return nil }
      return String(l[r.lowerBound...].prefix(110))
    }.joined(separator: " < ")
  }
  static func note(_ s: String, stack: Bool = false) { guard !SELFTEST.isEmpty else { return }; notes.append("\(at()) \(s)" + (stack ? " ← " + callers() : "")) }
  static func linkNote(_ s: String) { guard !SELFTEST.isEmpty else { return }; link.append("\(at()) \(s)") }
}
