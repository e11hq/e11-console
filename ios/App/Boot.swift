import UIKit
import WebKit

/* ================= Part B step 8: the app starts by itself (Haris, 2026-11-05) =================
   The app asks the server itself who's signed in (/api/app/start, with the sign-in the web view keeps) — no page needed:
   - signed in: the startup screen's memo kept for next time (the first name, the CD's row, three weeks of greetings and
     sunrise / sunset); the app's own copy started for that person; once it's in, the tab bar, Home and the startup
     screen's four ticks from it — a first start too, not only a quick start from the copy kept on the phone;
   - signed out (Cloudflare's sign-in — or the App Review copy's — answered instead): every screen of the person before
     put away, nothing kept for a quick start, the sign-in page shows (the website's page only while signing in); once
     the web view is back on our site, asked again;
   - no answer (no connection, the server down): a quick start carries on from the copy kept on the phone; a first start
     says so on the startup screen — "Can't reach E11 Console", Try again — and tries again by itself every 5 s.
   The website still loads behind, for the screens that are still its own (step 9 takes it away). */
final class BootState {
  enum State { case unknown, asking, signedIn, signedOut, unreachable }
  var state: State = .unknown
  var me: String?
  var retry: DispatchWorkItem?
  var owned = false          // (the app runs the startup screen itself this time — the page's ticks and "out" ignored)
  var signingIn = false      // (back from the sign-in page: the startup screen is the app's until its screens are there)
  var popBusy = false, popTimer: Timer?   // (the app's own pop-ups — step 9)
  lazy var session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.httpShouldSetCookies = false; c.httpCookieAcceptPolicy = .never
    c.timeoutIntervalForRequest = 12
    return URLSession(configuration: c)
  }()
}

extension Main {
  static let boot = BootState()
  // the step 9 trial (test site, Me › Test site): the app on its own — the website isn't loaded at all (only to sign in)
  static var noPage: Bool { defaults.bool(forKey: "e11_nopage") }
  func setNoPage(_ on: Bool) {
    defaults.set(on, forKey: "e11_nopage")
    if on { pageReady = false; web.loadHTMLString("<html><body style='background:#0c0d0f'></body></html>", baseURL: nil) }
    restartApp()
    if !on { loadHome() }
  }
  // what the server said at the last start (/api/app/start), for this person
  var startInfo: [String: Any] { (defaults.data(forKey: "e11_start").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:] }
  var bootState: BootState { Main.boot }

  func bootCheck() {
    let b = bootState
    if b.state == .asking { return }
    b.retry?.cancel(); b.retry = nil
    b.state = .asking
    guard let url = URL(string: serverURL() + "/api/app/start") else { return }
    serverHome.cookies { [weak self] cookie in
      var req = URLRequest(url: url)
      req.setValue("application/json", forHTTPHeaderField: "Accept")
      if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
      b.session.dataTask(with: req) { data, resp, err in
        let http = resp as? HTTPURLResponse
        let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        DispatchQueue.main.async { self?.bootAnswer(http, j, err) }
      }.resume()
    }
  }

  private func bootAnswer(_ http: HTTPURLResponse?, _ j: [String: Any]?, _ err: Error?) {
    let status = http?.statusCode ?? 0
    let finalHost = http?.url?.host?.lowercased() ?? ""
    if status == 200, let j = j, (j["ok"] as? Bool) == true, let me = j["me"] as? String, !me.isEmpty { return booted(me, j) }
    // (only a clear "sign in first" puts the app away: Cloudflare's sign-in page, or our own 401 / 403)
    if status == 401 || status == 403 || finalHost.hasSuffix(".cloudflareaccess.com") { return signedOut() }
    unreachable()
  }

  private func booted(_ me: String, _ j: [String: Any]) {
    let b = bootState
    let first = b.state != .signedIn || b.me != me
    b.state = .signedIn; b.me = me
    // (kept for Me's own rows — the owner, the Test site rows, the version — also offline: step 9)
    var keep = j; keep["days"] = nil
    if JSONSerialization.isValidJSONObject(keep), let d = try? JSONSerialization.data(withJSONObject: keep) { defaults.set(d, forKey: "e11_start") }
    // the startup screen's memo for next time (the look is this phone's own)
    var memo = SplashView.memo()
    for k in ["name", "cd", "days"] { if let v = j[k] { memo[k] = v } }
    if let tm = defaults.string(forKey: "e11_theme_mode") { memo["themeMode"] = tm }
    SplashView.save(memo)
    if let l4 = j["label4"] as? String {
      var last = (defaults.data(forKey: "e11_splash_last").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
      last["label4"] = l4
      if let d = try? JSONSerialization.data(withJSONObject: last) { defaults.set(d, forKey: "e11_splash_last") }
    }
    if let s = splash, !s.leaving { s.command(["status": ""]); s.command(["greet": SplashView.greeting(memo)]) }
    saveQuick(["me": me])
    if first && quickBooted { ownAfterStart() }   // (What's new, the View as… bar — without the website: step 9)
    guard first, !quickBooted else { return }
    // (a first start, or another person than the copy kept: their copy, then the app's own screens from it — the startup
    //  screen stays up until they're all there (the tab bar too), then plays out; the page's own ticks and "out" aren't
    //  waited for. Signed in again, the tab bar came a moment after Home: Haris 2026-11-05)
    if splash == nil, Main.boot.state == .signedIn, view.window != nil, signingIn { showSplash() }
    signingIn = false
    if splash != nil { bootState.owned = true }
    if AppData.shared.me != me || !AppData.shared.isStarted { AppData.shared.start(me: me, cookies: serverHome.cookies) }
    watchCopy()
    bootWhenReady(me, 0)
  }

  // the copy in: the tab bar, Home and the startup screen's ticks from it (as a quick start does); up to 20 s, else the
  // page's way as before
  private func bootWhenReady(_ me: String, _ n: Int) {
    guard bootState.me == me, !quickBooted else { return }
    guard AppData.shared.ready, AppData.shared.me == me, let tabs = ownTabsNow() else {
      if n < 100 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.bootWhenReady(me, n + 1) } }
      else { bootState.owned = false; splashGone() }   // (the copy never came: the page's way, as before)
      return
    }
    quickBooted = true
    bootState.owned = true
    var t = tabs
    var list = (t["tabs"] as? [[String: Any]]) ?? []
    // (the first tab on — Home, or an Office Admin's Overview; the page already there and its tabs drawn: as it has them)
    if pageReady, lastTabs != nil { refreshOwnTabs() }
    else { for i in list.indices { list[i]["on"] = i == 0 }; t["tabs"] = list; t["hidden"] = false; setTabs(t) }
    ownAppearanceWatch(); ownAppearanceTick()
    let office = list.contains(where: { ["fin-reimb", "fin-expenses", "team"].contains($0["v"] as? String ?? "") })
    // (no website — step 9: an Office Admin's Overview drawn by the app itself)
    if office, !pageReady, let k = list.first?["v"] as? String { _ = offlineTab(k) }
    if !office, (list.first?["v"] as? String) == "today", !pageReady || selectedTabKey == "today" {
      view.layoutIfNeeded()
      homePageMe = me
      let h = homeView
      if h.superview != nil {
        h.bottomRoom = (tabBar.isHidden ? 40 : view.bounds.height - tabBar.frame.minY) + 96
        h.tabTop = tabBar.isHidden ? nil : tabPillTop
        h.isHidden = false
        homeHadModel = true
        serverHome.refresh()
      }
    }
    quickSplash()
    ownPopsWatch()
    ownAfterStart()
  }
  private func ownTabsNow() -> [String: Any]? {
    guard AppData.shared.tabsOn, let m = AppData.shared.screen("tabs").model, let list = m["tabs"] as? [[String: Any]], !list.isEmpty else { return nil }
    return ["tabs": list, "hidden": false]
  }

  private func signedOut() {
    let b = bootState
    // (the website itself is in, on our site: it's the one to know — asked again later, nothing put away)
    if pageReady, web.url?.host == serverHost { return unreachable() }
    let was = b.state
    b.state = .signedOut; b.me = nil; b.owned = false
    // (nothing of the person before: their screens, their copy, a quick start next time)
    splashGone(fast: true)
    if was == .signedIn || quickBooted || AppData.shared.isStarted { putAwayForSwitch() }
    quickBooted = false
    tabBar.isHidden = true; tabsHidden = true; view.setNeedsLayout()
    var q = (defaults.data(forKey: "e11_quick").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    q["me"] = nil
    if let d = try? JSONSerialization.data(withJSONObject: q) { defaults.set(d, forKey: "e11_quick") }
    // (the sign-in page: the web view is on its way there already — Cloudflare's answer to our address; without the
    //  website (the step 9 trial) it's loaded now, for signing in only)
    if Main.noPage, web.url == nil || web.url?.scheme == "about" { loadHome() }
  }

  private func unreachable() {
    let b = bootState
    b.state = .unreachable
    // (a first start: said on the startup screen, which stays — the page would have taken it away)
    if !quickBooted, let s = splash, !s.leaving {
      splashHeard = true
      s.command(["status": "Can’t reach E11 Console — check your internet connection", "retry": true])
    }
    let w = DispatchWorkItem { [weak self] in self?.bootCheck() }
    b.retry = w
    DispatchQueue.main.asyncAfter(deadline: .now() + (quickBooted ? 15 : 5), execute: w)
  }

  // Try again on the startup screen: asked again at once, and the page loaded again if it couldn't be
  func bootRetry() {
    splash?.command(["status": "Connecting…", "retry": false])
    bootCheck()
    if !pageReady { retrying = false; loadHome() }
    pageJS("window.__e11SplashRetry && window.__e11SplashRetry()")
  }

  // Sign out (Me › Sign out — the page's signOut): this person's screens and copy put away, then Cloudflare's sign-out
  // (the App Review copy's own); the sign-in page follows, and the app asks again once it's back on our site
  func signOutNative() {
    bootState.state = .signedOut; bootState.me = nil; bootState.owned = false
    putAwayForSwitch()
    quickBooted = false
    tabBar.isHidden = true; tabsHidden = true; view.setNeedsLayout()
    var q = (defaults.data(forKey: "e11_quick").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    q["me"] = nil
    if let d = try? JSONSerialization.data(withJSONObject: q) { defaults.set(d, forKey: "e11_quick") }
    let review = defaults.string(forKey: "e11_server") == "review"
    // (anything the page still had to send goes first — its own sign out waited 0.3 s the same way)
    pageJS("try { Sync.push() } catch (e) {}")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.loadHome(review ? "/review/sign-out" : "/cdn-cgi/access/logout") }
  }

  // signing in: the web view has just come back to our site from the sign-in page — the startup screen at once, as the app
  // opening does, until the app's own screens are there
  var signingIn: Bool { get { Main.boot.signingIn } set { Main.boot.signingIn = newValue } }
  func bootCommitted() {
    guard bootState.state == .signedOut || (bootState.state == .asking && signingIn) else { return }
    // (not the sign-out itself — Cloudflare's /cdn-cgi/… and the App Review copy's sign-out page are on our site too)
    let path = web.url?.path ?? ""
    if path.hasPrefix("/cdn-cgi/") || path.hasPrefix("/review/") { return }
    // (the App Review copy signs in on a page of our own site: no startup screen over it)
    if defaults.string(forKey: "e11_server") == "review" { return }
    signingIn = true
    if splash == nil { showSplash(); splashHeard = true; if splash != nil { bootState.owned = true } }
  }
  // the web view reached our site (after signing in, or the page loaded again): asked again if we weren't signed in
  func bootPageArrived() {
    if bootState.state == .signedOut || bootState.state == .unreachable || bootState.state == .unknown { bootCheck() }
  }

  // Offline (the website couldn't load): the app's own lists still open from its copy — Home, My Tasks, the Inbox,
  // Clients, Me and every Me-made tab (Haris 2026-11-05: offline only Home opened, then Me took the tab bar away) —
  // and with no website at all (step 9). The page, if it comes, is told the tab once it's there.
  func offlineTab(_ key: String) -> Bool {
    guard !pageReady, quickBooted, AppData.shared.ready, let me = AppData.shared.me else { return false }
    // (an Office Admin's first tab is Overview, the app's own Me-made one; the Me-made tabs — Me, Plans, Reviews, Team,
    //  Claims, Expenses — are all Me's; Client Assets as a tab is Client Assets' own)
    let office = tabKeys.contains("fin-reimb") || tabKeys.contains("team")
    let meMade = ["me", "plans", "team", "fin-reimb", "fin-expenses", "reviews"].contains(key) || (key == "today" && office)
    guard meMade || ["today", "mytasks", "inbox", "projects", "clients"].contains(key) else { return false }
    let light = appStyle == .light
    if key != "today" || office { homeIfMade?.isHidden = true }
    if key != "mytasks" { myTasksCommand(["show": false]) }
    if key != "inbox" { inboxCommand(["show": false]) }
    if key != "projects" { clientsCommand(["show": false]) }
    if key != "clients", assetsCtl.isOpen { assetsCtl.close(animated: false) }
    if !meMade { meCtl.hide() }
    if meMade {
      // (Me's own rows from the app's copy and this phone; the rest — the server's — from the last start)
      meCtl.command(["show": true, "me": me, "tab": key, "light": light, "model": ["env": ["shell": SHELL_VERSION]]])
      return true
    }
    switch key {
    case "today": if homeHadModel { homeIfMade?.isHidden = false }; serverHome.refresh()
    case "mytasks": myTasksCommand(["show": true, "me": me, "light": light])
    case "inbox": inboxCommand(["show": true, "me": me, "light": light])
    case "clients": assetsCtl.command(["show": true, "root": true, "me": me, "light": light, "start": [String: Any]()])
    default: clientsCommand(["show": true, "view": "list", "me": me, "light": light])
    }
    return true
  }
  // everything again from the start — after Start fresh, Owner view switched (the page reloaded itself for these): this
  // person's screens put away, asked again who's signed in, the copy and the screens drawn again from it
  func restartApp() {
    putAwayForSwitch()
    quickBooted = false
    bootState.state = .unknown; bootState.me = nil; bootState.owned = false
    if splash == nil { showSplash(); splashHeard = true }
    bootCheck()
    if pageReady { web.reload() }
  }

  // ---------- Step 9: the pop-ups, decided by the app (the brain's pops — as the page did after the startup screen and
  // every 30 s): your birthday, the birthday / city nudge, an announcement, the claims reminder. Only without the website
  // (it decides them itself while it's there), one at a time, never over something open. ----------
  func ownPops() {
    guard !pageReady, quickBooted, splash == nil, lockView == nil, AppData.shared.ready, !popBusy, presentedViewController == nil,
          let p = AppData.shared.meModel("tasks", "pops") else { return }
    let seen = { [weak self] (k: String, v: String) in
      self?.serverTask.request("/api/app/act", body: ["ev": "pfSet", "field": "seen", "k": k, "value": v, "op": UUID().uuidString]) { j in
        if let ch = j?["changes"] as? [[String: Any]], !ch.isEmpty { AppData.shared.applyLocal(ch) }
      }
    }
    let next = { [weak self] in self?.popBusy = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.ownPops() } }
    let today = p["today"] as? String ?? ""
    if let b = p["birthday"] as? [String: Any], let key = b["key"] as? String, defaults.string(forKey: "e11-hello-bday") != key {
      defaults.set(key, forKey: "e11-hello-bday"); popBusy = true
      popCommand(["kind": "greet", "title": b["title"] ?? "", "sub": b["sub"] ?? "", "person": b["person"] ?? [:]]) { _ in next() }
      return
    }
    // (the season's greeting — Eid, National Day…: as the server worked it out at the start, once each on this phone)
    if let g = startInfo["greet"] as? [String: Any], let key = g["key"] as? String, (startInfo["me"] as? String) == AppData.shared.me, defaults.string(forKey: "e11-hello") != key {
      defaults.set(key, forKey: "e11-hello"); popBusy = true
      popCommand(["kind": "greet", "title": g["title"] ?? "", "sub": g["sub"] ?? "", "pic": g["pic"] ?? "", "tile": g["tile"] ?? []]) { _ in next() }
      return
    }
    if let k = p["profileAsk"] as? String {
      popBusy = true; seen("profileAsked", today)
      popCommand(["kind": "profileAsk", "missing": k]) { _ in next() }
      return
    }
    if var a = p["announce"] as? [String: Any], let id = a["id"] as? String {
      popBusy = true; a["kind"] = "announce"
      popCommand(a) { _ in seen("annSeen", id); next() }
      return
    }
    if let c = p["claims"] as? [String: Any] {
      popBusy = true; seen("claimNag", today)
      popCommand(["kind": "claims", "month": c["month"] ?? "", "today": c["today"] ?? 0]) { [weak self] r in
        let a = r["a"] as? String ?? ""
        if a == "none" || a == "offline" {
          self?.serverTask.request("/api/app/act", body: ["ev": "clMark", "state": a, "op": UUID().uuidString]) { j in
            if let ch = j?["changes"] as? [[String: Any]], !ch.isEmpty { AppData.shared.applyLocal(ch) }
            if let m = (j?["messages"] as? [String])?.first { self?.shownScreen?.toast(["t": m]) }
          }
        }
        next()
      }
      return
    }
  }
  var popBusy: Bool { get { Main.boot.popBusy } set { Main.boot.popBusy = newValue } }
  // (after the startup screen, and every 30 s — as the page's own timer)
  func ownPopsWatch() {
    guard Main.boot.popTimer == nil else { return }
    Main.boot.popTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.ownPops() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in self?.ownPops() }
  }

  // What's new after an update (app.js maybeShowWhatsNew), and the View as… bar (viewas.js) — the app's own, without
  // the website
  func ownAfterStart() {
    guard !pageReady else { return }
    let st = startInfo
    if let v = st["version"] as? String, !v.isEmpty {
      let seen = defaults.string(forKey: "e11-seen-version")
      defaults.set(v, forKey: "e11-seen-version")
      if let s = seen, s != v {
        serverTask.request("/api/whatsnew", body: nil) { [weak self] r in
          guard let self = self, !self.pageReady, let r = r, let notes = r["notes"] as? String, !notes.isEmpty else { return }
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.popCommand(["kind": "whatsNew", "version": r["name"] ?? r["version"] ?? v, "when": (r["publishedAt"] as? String).map { Main.dateTimeText($0) } ?? "", "sections": Main.noteSections(notes)]) { _ in }
          }
        }
      }
    }
    if let va = st["viewAs"] as? [String: Any], let who = va["as"] as? [String: Any] {
      let role = ((AppData.shared.meModel("me", "me", [["shell": SHELL_VERSION]])?["card"] as? [String: Any])?["role"] as? String) ?? ""
      popCommand(["kind": "viewAsBar", "on": true, "name": who["name"] ?? "", "role": role]) { _ in }
    } else { ViewAsBar.current?.go() }
  }
  // (app.js NativePop.sections: the notes' lines in sections — headings, then their points)
  static func noteSections(_ md: String) -> [[String: Any]] {
    var out: [[String: Any]] = []
    let plain = { (t: String) -> String in t.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression).replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
    for l in md.components(separatedBy: .newlines) {
      if let r = l.range(of: "^#{1,3}\\s+", options: .regularExpression) { out.append(["h": plain(String(l[r.upperBound...])), "items": [String]()]); continue }
      var t = l
      if let r = l.range(of: "^\\s*[-*]\\s+", options: .regularExpression) { t = String(l[r.upperBound...]) }
      t = plain(t)
      if t.isEmpty { continue }
      if out.isEmpty { out.append(["h": "", "items": [String]()]) }
      var last = out.removeLast(); var items = last["items"] as? [String] ?? []; items.append(t); last["items"] = items; out.append(last)
    }
    return out.isEmpty ? [["h": "", "items": ["Improvements and fixes."]]] : out
  }
  // (app.js fmtDateTime: "Nov 5, 2026, 7:15 PM")
  static func dateTimeText(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let o = DateFormatter(); o.locale = Locale(identifier: "en_US"); o.dateFormat = "MMM d, yyyy, h:mm a"
    return o.string(from: d)
  }

  // ---------- Step 9: the list screens' and the task page's taps the page did — done by the app when it isn't there
  // (Home's, My Tasks', a client's page's cards: open, copy, attach, me, review; the task page's copy, from) ----------
  func pagelessEvent(_ ev: [String: Any]) -> Bool {
    let id = ev["id"] as? String ?? ""
    switch ev["ev"] as? String ?? "" {
    case "copy": guard !id.isEmpty else { return false }; copyTaskLink(id); return true
    case "open", "attach":
      guard !pageReady, !id.isEmpty, AppData.shared.ready else { return false }
      openTaskPage(id, tab: "details", focus: ""); return true
    case "me": guard !pageReady else { return false }; selectTab("me"); return true
    case "review":
      // (Home's In review box: My Tasks, waiting for the CD's review — the whole team's for those who see everyone's)
      guard !pageReady else { return false }
      var to = (AppData.shared.meModel("tasks", "myTasksDefault")?["filters"] as? [String: Any]) ?? [:]
      to["cd"] = true
      if (AppData.shared.screen("home").model?["title"] as? String) == "E11 Day" { to["team"] = true }
      myTasksF = to; myTasksTab = "all"
      selectTab("mytasks"); return true
    case "from":
      guard !pageReady, !id.isEmpty else { return false }
      let name = (AppData.shared.screen("task", id).model?["title"] as? String) ?? ""
      meCtl.ask(["kind": "alert", "title": "New task from this", "body": "The same client, people, tags and description.", "input": ["value": name, "placeholder": "Task name"], "okText": "Create", "cancelText": "Cancel"]) { [weak self] r in
        guard let self = self, (r["ok"] as? Bool) == true else { return }
        let title = (r["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { self.shownScreen?.toast(["t": "Give the task a name"]); return }
        self.serverTask.request("/api/app/act", body: ["ev": "tkFrom", "id": id, "title": title, "op": UUID().uuidString]) { j in
          guard let j = j, (j["ok"] as? Bool) == true, let nid = (j["answer"] as? [String: Any])?["id"] as? String else { self.taskPages.last?.toast(j?["error"] as? String ?? "That didn’t work — try again"); return }
          if let ch = j["changes"] as? [[String: Any]] { AppData.shared.applyLocal(ch) }
          for p in self.taskPages { self.closeTaskPage(p, animated: false) }
          self.openTaskPage(nid, tab: "details", focus: "")
        }
      }
      return true
    default: return false
    }
  }
  // a task's link on the clipboard (app.js TaskLink.url: files.e11hq.com/t/… on the office's sites)
  func copyTaskLink(_ id: String) {
    let host = URL(string: serverURL())?.host ?? ""
    let enc = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
    let link = host == "console.e11hq.com" ? "https://files.e11hq.com/t/\(enc)" : host == "test.e11hq.com" ? "https://files-test.e11hq.com/t/\(enc)" : serverURL() + "/?task=" + enc
    UIPasteboard.general.string = link
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    if let p = taskPages.last { p.toast("Link copied") } else { shownScreen?.toast(["t": "Link copied"]) }
  }
}
