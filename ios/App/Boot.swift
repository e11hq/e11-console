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
  lazy var session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.httpShouldSetCookies = false; c.httpCookieAcceptPolicy = .never
    c.timeoutIntervalForRequest = 12
    return URLSession(configuration: c)
  }()
}

extension Main {
  static let boot = BootState()
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
    // (the sign-in page: the web view is on its way there already — Cloudflare's answer to our address)
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
  // Clients (Haris 2026-11-05: offline only Home opened). The page is told the tab once it's there. Me and the pages
  // still the website's open once it is (step 9).
  func offlineTab(_ key: String) -> Bool {
    guard !pageReady, quickBooted, AppData.shared.ready, let me = AppData.shared.me else { return false }
    guard ["today", "mytasks", "inbox", "projects"].contains(key) else { return false }
    let light = appStyle == .light
    if key != "today" { homeIfMade?.isHidden = true }
    if key != "mytasks" { myTasksCommand(["show": false]) }
    if key != "inbox" { inboxCommand(["show": false]) }
    if key != "projects" { clientsCommand(["show": false]) }
    meCtl.hide()
    switch key {
    case "today": if homeHadModel { homeIfMade?.isHidden = false }; serverHome.refresh()
    case "mytasks": myTasksCommand(["show": true, "me": me, "light": light])
    case "inbox": inboxCommand(["show": true, "me": me, "light": light])
    default: clientsCommand(["show": true, "view": "list", "me": me, "light": light])
    }
    return true
  }
}
