// E11 Console for iPhone — the native app around the E11 Console server (console.e11hq.com).
// The screens, data and updates come live from the server (the same phone layout as the browser); the app adds
// what only a real app can: a native tab bar, Apple's push notifications (with the app closed), opening the right
// page from a notification, the app icon badge, Face ID lock, downloads to Files / Photos through the share sheet,
// and the page running up under the status bar (no iOS 26 blur workaround needed in a native app).
// It talks to the page through the same kind of bridge as the Mac app (handler "e11ios"; replies via
// window.__e11NativeReply), so the web app (web/app.js Host.isIOSApp, web/phone.js) knows it's here.
import UIKit
import CoreText
import Network
import WebKit
import UserNotifications
import LocalAuthentication
import PhotosUI
import UniformTypeIdentifiers
import AudioToolbox

// Version of this iPhone app's native part (raise it with changes the web app needs to know about)
let SHELL_VERSION = 38   // 38: the CD's Reviews are the app's own (Me.swift reviewsBlocks / reviewBlocks, ReviewList, ReviewHero, AmendSheetVC; the page's NativeMe reviews and rvFile, rvTask, rvApprove, rvAmend; open kind review) · 37: an Office Admin's Claims and Expenses are the app's own (Me.swift claimsBlocks / expensesBlocks, SwipeRows, MoneyFormVC; the page's NativeMe claims / expenses and clApprove, clPaid, clOpen, clAdd, clPerson, exAdd, exEnd, exInv) · 36: an Office Admin's tabs — Overview (the app's own, Me.swift overviewBlocks: the page's NativeMe overview), Team as its own tab (without Finance), Claims and Expenses (the website's, for now) · 35: Content plans are the app's own in Me (Me.swift: plans, plan, PlanPostVC — the page's Plans.native: pl, plOpen, plPost, plReview, plApprove, plBack, plFile; open from the page) · 34: the pop-ups are the app's own (Popups.swift: pop — announce, claims, greet, profileAsk, whatsNew, viewAs, viewAsBar; the page's NativePop) · 33: the Me tab is the app's own (Me.swift: Me, Appearance, About, Shortcuts, Team members, a member — from the page: me show / me / light / model, about, toast; every change through window.__e11Me — nav, profile, push, lock, digest, theme, viewAs, backToMe, sample, signOut, team, about, update, videoCheck, import, addMember, member, cd, toast; the page's questions as iPhone's own: meAsk — alert / choice / form) · 32: Client Assets is the app's own (Assets.swift: All Client Assets, a client's assets, a folder — from the page: assets show / start / root / me / light; each screen's contents and every change through window.__e11Assets — want, uploaded, newFolder, renameFolder, deleteFolder, deleteFile, addClient, renameClient, deleteClient, back, me — answered with assets rid / ok / error / model; a client's page's folders open them) · 31: the Clients tab is the app's own (Clients.swift: the list, and a client's page with its Client Assets folders on top and its tasks by status as Home's cards; the page sends clients show / view / id / done / me / light; taps back: window.__e11Clients — client, back, folder, assets, done, add, and Home's; window.__e11ClientsOwn / __e11ClientsResend) · 30: the task page is the app's own (TaskPage.swift): it slides in from the right, ‹ / the edge swipe goes back; Details from /api/task, its changes to /api/home/act (from: task); the page sends taskPage open / changed and hears window.__e11Task — closed, copy, attach, from, web; its Comments tab shows the comments screen inside it · 29: 29: the morning round-up as iPhone's own sheet (dailySheet; taps back: window.__e11Daily — open, all) · 28: the Inbox is the app's own (each notification a row as Mail's, from /api/inbox; All / Unread / Mentions, swipe right: Read / Unread, Mark all read — read / unread / readAll to /api/home/act; the page sends inbox show / me / light; taps back: window.__e11Inbox — open, me; window.__e11InboxOwn) · 27: the page draws nothing under the app's My Tasks; the app says when it can't show its own (window.__e11MyTasksOwn) · 26: My Tasks is the app's own too (Home's screen as a list — All / Done, the filter buttons, what's on — from /api/mytasks?<filters>; the page sends mytasks show / tab / q / buttons / chips; taps back: window.__e11MyTasks — tab, filter, chip, reset, and Home's) · 25: Home straight from the server (/api/home; Done / reopen / Due / Delete / Undo to /api/home/act, kept on the phone until sent — ServerHome.swift); the page still says when Home shows · 24: a Home card swiped right: Done · Due (taps back: window.__e11Home — done, due; the page opens its date sheet) · 23: Home (E11 Day / My Day) is the app's own (Home.swift; the page sends it: home show / people / toast; taps back: window.__e11Home — open, search, me, add, copy, delete, attach, toast); a card swiped left: Copy link · Delete; held: Attach Files · 22: the startup screen is the app's own, there the moment it opens (Splash.swift; the page drives it: splash hello / memo / greet / tick / status / out; window.__e11SplashSkip / __e11SplashRetry) · 21: the comments screen tells its page how far it's slid up for the keyboard (--cm-top: a thread's bar stays in sight); its swipe right also takes iPhone's slow back drag from the edge; it starts at the latest comment only when the task opens and when the keyboard comes up, and keeps its place across Details / Comments · 20: a task's Comments on a screen of their own (a second web view showing only the comments, scrolled by iOS itself; window.__e11ShowComments, cmReady / cmEnd) · 19: on a task's Comments, iOS itself moves the comments list with the keyboard (its own scroll view, in the keyboard's own animation; window.__e11FeedKb) · 18: the file preview is iOS's own (preview / previewSet / window.__e11Preview; Preview.swift) · 17: the comment box on a task's Comments is iPhone's own, on the keyboard (commentBar / window.__e11CBar; CommentBar.swift) · 16: iPhone's own banners also while the app is open (the page draws no cards), each notification confirmed by the Notification Service Extension so the server sends again the ones an offline phone missed (register ack) · 15: New task / Request amendments as native sheets with iPhone's own fields that tuck into a bar like a Mail draft (formSheet / formSet / formClose; the page: window.__e11Form), a Trash task as a native sheet (trashSheet); native sheets and dates also open on top of those · 14: native sheets with people (round photos / initials) and a search box (+ a typed entry, "Use …") · 13: also dates picked in a native sheet (pickDate: closing it never sets a date) · a native sheet can stay open for ticking several (multi; each tick: window.__e11SheetPick) · 12: native sheets also with colour dots, a row of colours / emoji / numbers (chips), tinted icons, locked rows · 11: plain menus as iOS's own sheets (nativeSheet; the page: NativeSheet in app.js, showMenu(…, { native: true })) · 10: My Tasks, Inbox and Team lists swiped by iOS itself (Pager.syncLists in phone.js) · 9: a task’s Details / Comments swiped by iOS itself (the page: Pager in phone.js) · 8: iOS haptics for the page (haptic kind: light / medium / selection / success / warning / error) · 7: the comment box rides down / up with the keyboard frame by frame (__e11KbStep) · 6: the comment box gets the keyboard back after Photos / Camera / Files · 5: the page stays full height under the keyboard (the page makes room itself, --ios-kb) · 3: its own sheet for attaching files · 4: straight to Photos / Camera / Files (the page's attach bar), keyboard kept
let procEnv = ProcessInfo.processInfo.environment
let SELFTEST = procEnv["E11_SELFTEST"] ?? ""           // the build machine's self-test in the simulator
let info = Bundle.main.infoDictionary ?? [:]
let LOCK_KEY = "E11FaceIDLock", PUSH_OFF_KEY = "E11PushOff"
let defaults = UserDefaults.standard
// Live by default; Settings › E11 Console › Server can switch to the test copy. "review" is the App Review copy
// (made-up demo data, its own password sign-in) — chosen from the link under the sign-in page, for Apple's reviewer.
let LIVE_URL = info["E11ServerURL"] as? String ?? "https://console.e11hq.com"
func serverURL() -> String {
  if let s = procEnv["E11_SERVER"], !s.isEmpty { return s }
  let test = info["E11TestServerURL"] as? String ?? "https://test.e11hq.com"
  let review = info["E11ReviewServerURL"] as? String ?? "https://review.e11hq.com"
  switch defaults.string(forKey: "e11_server") {
  case "test": return test
  case "review": return review
  default: return LIVE_URL
  }
}
#if DEBUG
let APNS_ENV = "sandbox"
#else
let APNS_ENV = "production"
#endif
func jsonString(_ v: Any) -> String {
  guard JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v), let s = String(data: d, encoding: .utf8) else { return "null" }
  return s
}
let DARK_BG = UIColor(red: 0.047, green: 0.051, blue: 0.059, alpha: 1)
// The app's own light / dark from the last time it ran (the page says which with setAppearance): the app starts in it,
// so a light app doesn't begin with a dark background and white status bar — that showed as a dark band across the
// top of the light start-up screen (Haris, 2026-10-30)
var LAST_LIGHT: Bool { defaults.string(forKey: "e11_look") == "light" }
var BG: UIColor { LAST_LIGHT ? UIColor(red: 0.957, green: 0.957, blue: 0.969, alpha: 1) : DARK_BG }

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  // (iOS 27: an app built with its SDK must start through a scene — SceneDelegate below makes the window; without one
  //  iOS stops the app at launch)
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    Dirham.setup()
    return true
  }
  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let c = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    c.delegateClass = SceneDelegate.self
    return c
  }
  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Main.shared.gotToken(deviceToken.map { String(format: "%02x", $0) }.joined())
  }
  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    Main.shared.tokenFailed(error.localizedDescription)
  }
  // while the app is open too: iPhone's own banner, sound and badge, kept in Notification Centre (Haris, 2026-10-30 —
  // the page draws no cards of its own any more)
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound, .badge])
  }
  // (also a tap on a notification that started the app: with scenes it comes here, not in the launch options)
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    Main.shared.openPush(response.notification.request.content.userInfo)
    completionHandler()
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let ws = scene as? UIWindowScene else { return }
    let w = UIWindow(windowScene: ws)
    w.backgroundColor = BG
    w.rootViewController = Main.shared
    w.makeKeyAndVisible()
    window = w
    if let u = connectionOptions.urlContexts.first?.url { Main.shared.openLink(u) }   // (started by a widget tap)
    // (started by a file link tapped elsewhere — files.e11hq.com/f/…, iPhone's universal links)
    if let a = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }), let u = a.webpageURL { Main.shared.openLink(u) }
  }
  func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) { if let u = contexts.first?.url { Main.shared.openLink(u) } }
  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) { if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let u = userActivity.webpageURL { Main.shared.openLink(u) } }
  func sceneDidBecomeActive(_ scene: UIScene) { Main.shared.becameActive() }
  func sceneDidEnterBackground(_ scene: UIScene) { Main.shared.wentAway() }
}

// (the page's message handler is held weakly, so the screen and the web view don't keep each other alive)
// the comments screen's web view (20): our server only (anything else opens in Safari); loaded → wait for its data
final class CommentsNav: NSObject, WKNavigationDelegate {
  weak var main: Main?
  init(_ m: Main) { main = m }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let m = main, let u = action.request.url else { return decisionHandler(.allow) }
    if action.targetFrame?.isMainFrame != false, let h = u.host, h.lowercased() != m.serverHost.lowercased() {
      if ["http", "https"].contains(u.scheme?.lowercased() ?? "") { UIApplication.shared.open(u) }
      return decisionHandler(.cancel)
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { main?.cwebPageLoaded() }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { main?.cwebLoaded = false; main?.cwebTask = nil; webView.reload() }
}

final class WeakHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(_ t: WKScriptMessageHandler) { target = t }
  func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

final class Main: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UITabBarDelegate, WKDownloadDelegate, UIGestureRecognizerDelegate {
  static let shared = Main()
  var web: WKWebView!
  let tabBar = UITabBar()
  var tabKeys: [String] = []
  var tabsHidden = true
  var pageReady = false
  var pendingPush: [String: Any]?
  var pendingToken: String?
  var lastToken: String?
  var pushWaiters: [([String: Any]) -> Void] = []
  var lockView: UIView?
  var awayAt: Date?
  var started = false
  var statusStyle: UIStatusBarStyle = LAST_LIGHT ? .darkContent : .lightContent
  var downloads: [ObjectIdentifier: URL] = [:]
  var downloadFrom: [ObjectIdentifier: String] = [:]      // what each download is fetching (one at a time per file)
  var downloadWatch: [ObjectIdentifier: NSKeyValueObservation] = [:]
  var downloadNames: [ObjectIdentifier: String] = [:]
  var hud: DownloadHUD?
  var retrying = false
  var launchLock = true          // ask for Face ID when the app starts (not every time it comes back to the front)
  var authing = false            // Face ID is on screen (it makes the app inactive and active again: never a new lock)
  // under the Cloudflare sign-in page only: "App Review sign-in" (Apple's reviewer can't get an E11 email code)
  lazy var reviewLink: UIButton = {
    let b = UIButton(type: .system)
    b.setTitle("App Review sign-in", for: .normal)
    b.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    b.setTitleColor(.secondaryLabel, for: .normal)
    b.accessibilityIdentifier = "review-sign-in"
    b.addTarget(self, action: #selector(toReview), for: .touchUpInside)
    b.isHidden = true
    return b
  }()
  @objc func toReview() { defaults.set("review", forKey: "e11_server"); reviewLink.isHidden = true; loadHome() }

  override var preferredStatusBarStyle: UIStatusBarStyle { statusStyle }
  override func loadView() { view = UIView(); view.backgroundColor = BG }
  override func viewDidLoad() {
    super.viewDidLoad()
    _ = netWatch   // (the phone's connection, for the Me tab's dot)
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()             // stay signed in between launches
    config.allowsInlineMediaPlayback = true
    config.applicationNameForUserAgent = "E11ConsoleiOS/\(SHELL_VERSION)"
    config.userContentController.add(WeakHandler(self), name: "e11ios")
    web = WKWebView(frame: view.bounds, configuration: config)
    FocusAfterPicker.install()
    web.navigationDelegate = self
    web.uiDelegate = self
    web.isOpaque = false
    web.backgroundColor = BG
    web.scrollView.backgroundColor = BG
    web.scrollView.contentInsetAdjustmentBehavior = .never   // the page handles the status bar area itself
    web.scrollView.bounces = false
    web.allowsLinkPreview = false   // (no Safari-style previews on touch and hold: the page has its own menus)
    web.scrollView.alwaysBounceHorizontal = false
    web.scrollView.showsHorizontalScrollIndicator = false
    if #available(iOS 16.4, *) { web.isInspectable = true }
    view.addSubview(web)
    web.hideKeyboardBar()
    // Like a native app, the keyboard makes the page shorter instead of pushing the whole page up (Safari's way):
    // the page ends at the top of the keyboard, and the page itself never scrolls as a whole (each page scrolls
    // inside itself), so the header stays put and boxes at the bottom (the comment box) sit just above the keyboard.
    // (the page as a whole never moves: no automatic insets, no scrolling or bouncing of the page itself, and if iPhone
    //  scrolls it anyway to show the comment box above the keyboard it's put straight back in the same moment — a
    //  moment later showed as the whole page jumping down and back)
    web.scrollView.contentInsetAdjustmentBehavior = .never
    web.scrollView.isScrollEnabled = false
    web.scrollView.bounces = false
    offsetWatch = web.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
      guard let self = self, self.pageReady, sv.contentOffset != .zero, !self.resetting else { return }
      self.resetting = true; sv.setContentOffset(.zero, animated: false); self.resetting = false
    }
    // like Messages: drag your finger down onto the top of the keyboard and it goes away. (Only attached while the
    // keyboard is up: on the web view all the time it got in the way of ordinary taps, which then lagged.)
    pull.cancelsTouchesInView = false
    pull.delaysTouchesBegan = false
    pull.delaysTouchesEnded = false
    pull.delegate = self
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in self?.keyboardMoves(n) }
    nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] n in self?.keyboardMoves(n, gone: true) }
    tabBar.delegate = self
    tabBar.isHidden = true
    view.addSubview(tabBar)
    view.addSubview(reviewLink)
    showSplash()
    quickStart()
    if !Main.noPage { loadHome() }
    // (Part B step 8: who's signed in, asked by the app itself — Boot.swift; the self-test's sign-in is set as the page
    //  loads: asked once it has)
    if SELFTEST.isEmpty { bootCheck() }
  }
  /* ---------- the quick start (iOS app data plan, step 3 — Haris, 2026-11-02): with this person's copy saved on the
     phone, the app opens on its own Home and tab bar at once, drawn from that copy; the website loads quietly behind,
     only for the screens that are still its own. Taps meant for it before it's there wait, and go once it is. ---------- */
  var quickBooted = false
  var earlyJS: [String] = []
  func saveQuick(_ add: [String: Any]) {
    var q = (defaults.data(forKey: "e11_quick").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    if (q["server"] as? String) != serverURL() { q = ["server": serverURL()] }
    add.forEach { q[$0.key] = $0.value }
    if JSONSerialization.isValidJSONObject(q), let d = try? JSONSerialization.data(withJSONObject: q) { defaults.set(d, forKey: "e11_quick") }
  }
  func quickStart() {
    guard SELFTEST.isEmpty, splash != nil,
          let q = defaults.data(forKey: "e11_quick").flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
          (q["server"] as? String) == serverURL(), let me = q["me"] as? String, AppData.shared.hasSaved(me),
          var tabs = q["tabs"] as? [String: Any], var list = tabs["tabs"] as? [[String: Any]], !list.isEmpty,
          list.contains(where: { ($0["v"] as? String) == "today" }) else { return }
    quickBooted = true
    // (Home's tab on, whichever was on last time: the website opens on Home too)
    for i in list.indices { list[i]["on"] = (list[i]["v"] as? String) == "today" }
    tabs["tabs"] = list; tabs["hidden"] = false
    setTabs(tabs)
    ownAppearanceWatch(); ownAppearanceTick()   // (Automatic light / dark by the app's own clock, from the start)
    // (an Office Admin: their first tab is Overview, not Home — no Home drawn under the startup screen for them)
    if list.contains(where: { ["fin-reimb", "fin-expenses", "team"].contains($0["v"] as? String ?? "") }) {
      AppData.shared.start(me: me, cookies: serverHome.cookies); watchCopy(); quickSplash(); ownPopsWatch(); return
    }
    view.layoutIfNeeded()
    homeLook = q["look"]; homePageMe = me
    let h = homeView
    if h.superview == nil { return }
    h.bottomRoom = (tabBar.isHidden ? 40 : view.bounds.height - tabBar.frame.minY) + 96
    h.tabTop = tabBar.isHidden ? nil : tabPillTop
    h.isHidden = false
    homeHadModel = true
    AppData.shared.start(me: me, cookies: serverHome.cookies)
    watchCopy()
    // (the startup screen plays all the way through all the same, on its own — Haris 2026-11-02; a tap closes it)
    quickSplash()
    ownPopsWatch()   // (the pop-ups — only while the website isn't there: step 9)
  }
  // the startup screen's checklist ticked here, as the website does (the icon first, then a row every 0.22 s, 3 s in all):
  // what each row said last time, the Inbox's count from the copy
  func quickSplash() {
    guard let s = splash else { return }
    splashHeard = true
    s.onSkip = { [weak self] in self?.splashGone() }
    let last = (defaults.data(forKey: "e11_splash_last").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    var vals = (last["vals"] as? [String]) ?? []
    while vals.count < 4 { vals.append("") }
    let icon: Double = UIAccessibility.isReduceMotionEnabled ? 0.3 : 2.15
    let age = CACurrentMediaTime() - s.t0
    var t = max(0, icon - age)
    DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
      guard let self = self, self.splash === s, !s.leaving else { return }
      var l4 = last["label4"] as? String
      // (all four rows as they are now, from the copy — Part B step 8, app.js Splash values(); kept for next time)
      if let r = AppData.shared.meModel("tasks", "startRows"), let l = r["list"] as? [String], l.count == 4 {
        vals = l; l4 = r["label4"] as? String ?? l4
        var keep = last; keep["vals"] = l; keep["label4"] = l4
        if let d = try? JSONSerialization.data(withJSONObject: keep) { defaults.set(d, forKey: "e11_splash_last") }
      }
      // (the Inbox's row: as it is now, from the copy)
      else if let m = AppData.shared.screen("inbox", "all").model, let n = m["unread"] as? Int { vals[2] = n > 0 ? "\(n > 99 ? "99+" : String(n)) new" : "all read" }
      if let l4 = l4 { s.command(["label4": l4]) }
      for i in 0..<4 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + 0.22 * Double(i)) { [weak self] in
          guard let self = self, self.splash === s, !s.leaving else { return }
          s.command(["tick": i, "value": vals[i], "n": i + 1])
          if !SELFTEST.isEmpty, i == 3 { self.selfResult["splashTickedGeo"] = s.geo(); self.writeSelf("splashTicked") }
        }
      }
    }
    t += 0.12 + 0.22 * 3
    DispatchQueue.main.asyncAfter(deadline: .now() + max(t + 0.42, 3.0 - age)) { [weak self] in if self?.splash === s { self?.splashGone() } }
  }
  // for the website behind: now, or as soon as it's there (a quick start's early taps)
  func pageJSSoon(_ js: String) { if pageReady || !quickBooted { pageJS(js) } else { earlyJS.append(js) } }
  // the app's own light / dark (from the page; at launch the last one, or the startup screen's)
  var appStyle: UIUserInterfaceStyle = LAST_LIGHT ? .light : .dark
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    view.window?.overrideUserInterfaceStyle = appStyle
  }
  /* ---------- the startup screen (22+): the app's own, over everything until the page says it's done ---------- */
  var splash: SplashView?
  var splashHeard = false
  func showSplash() {
    let m = SplashView.memo()
    if (m["native"] as? Bool) == false { return }   // (the website switched it off: the page's own startup screen)
    let s = SplashView(memo: m)
    appStyle = s.light ? .light : .dark
    s.frame = view.bounds; s.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    s.onSkip = { [weak self] in self?.pageJS("window.__e11SplashSkip && window.__e11SplashSkip()") }
    s.onRetry = { [weak self] in self?.bootRetry() }
    view.addSubview(s)
    splash = s
    statusStyle = s.light ? .darkContent : .lightContent
    setNeedsStatusBarAppearanceUpdate()
    // (the page never took it over — it couldn't load, or it's the sign-in page: it goes, whatever is under it shows)
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in if self?.splashHeard == false { self?.splashGone() } }
    if !SELFTEST.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
      guard let self = self, let s = self.splash else { return }
      self.selfResult["splashGeo"] = s.geo(); self.writeSelf("splash") } }
  }
  func splashGone(fast: Bool = false) {
    guard let s = splash else { return }
    s.leave(fast: fast) { [weak self] in if self?.splash === s { self?.splash = nil } }
  }
  func splashCommand(_ a: [String: Any]) -> [String: Any] {
    // (what each row said, and the fourth's name — for a quick start's own checklist next time)
    if a["tick"] != nil || a["label4"] != nil {
      var last = (defaults.data(forKey: "e11_splash_last").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
      if let l4 = a["label4"] as? String { last["label4"] = l4 }
      if let i = a["tick"] as? Int, (0..<4).contains(i) { var v = (last["vals"] as? [String]) ?? ["", "", "", ""]; while v.count < 4 { v.append("") }; v[i] = a["value"] as? String ?? ""; last["vals"] = v }
      if let d = try? JSONSerialization.data(withJSONObject: last) { defaults.set(d, forKey: "e11_splash_last") }
      if quickBooted || Main.boot.owned { return ["ok": true, "shown": splash != nil] }   // (the app ticks its own)
    }
    if a["hello"] != nil {
      splashHeard = true
      // (a quick start: the app's own startup screen is, or was, up — the page doesn't put up its own behind Home)
      guard let s = splash, !s.leaving else { return ["ok": true, "shown": quickBooted || Main.boot.owned, "age": quickBooted ? 60000 : 0] }
      return ["ok": true, "shown": true, "age": Int((CACurrentMediaTime() - s.t0) * 1000)]
    }
    if let m = a["memo"] as? [String: Any] {
      SplashView.save(m)
      if (m["native"] as? Bool) == false { splashGone(fast: true) }
    }
    guard let s = splash, !s.leaving else { return ["ok": true, "shown": false] }
    splashHeard = true
    if a["out"] != nil { if !quickBooted && !Main.boot.owned { splashGone() }; return ["ok": true] }   // (a quick start: it goes when its own run ends)
    s.command(a)
    if !SELFTEST.isEmpty, (a["tick"] as? Int) == 3 { selfResult["splashTickedGeo"] = s.geo(); writeSelf("splashTicked") }
    return ["ok": true, "shown": true]
  }
  /* The comment box on a task's Comments (17+): iPhone's own, pinned to the keyboard (the keyboard layout guide moves
     it with the keyboard itself, frame by frame); hidden until the page shows it. The page is told how tall it is
     (--ph-cbar) and keeps that much room under the comments. */
  var cbarIfMade: CommentBar?
  weak var previewVC: PreviewVC?
  lazy var cbar: CommentBar = {
    let b = CommentBar()
    b.translatesAutoresizingMaskIntoConstraints = false
    b.setLook(light: LAST_LIGHT)
    b.isHidden = true; b.alpha = 0
    self.view.insertSubview(b, belowSubview: self.tabBar)
    NSLayoutConstraint.activate([
      b.leadingAnchor.constraint(equalTo: self.view.leadingAnchor), b.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      b.bottomAnchor.constraint(equalTo: self.view.keyboardLayoutGuide.topAnchor),
    ])
    self.cbarIfMade = b
    b.onPresent = { [weak self] vc in self?.topMost().present(vc, animated: true) }
    b.onEvent = { [weak self] ev in self?.cbarPage?.evaluateJavaScript("window.__e11CBar && window.__e11CBar(\(jsonString(ev)))", completionHandler: nil) }
    b.onHeight = { [weak self] h in
      self?.cbarPage?.evaluateJavaScript("window.__e11CBarH && window.__e11CBarH(\(Int(h.rounded())))", completionHandler: nil)
      if self?.cwebShown == true { UIView.animate(withDuration: 0.15) { self?.cwebInset(keepEnd: self?.cwebAtEnd() ?? true) } }
    }
    return b
  }()
  static var uploadedSound: SystemSoundID = 0
  static func playUploaded() {
    if uploadedSound == 0, let url = Bundle.main.url(forResource: "uploaded", withExtension: "wav") {
      AudioServicesCreateSystemSoundID(url as CFURL, &uploadedSound)
    }
    if uploadedSound != 0 { AudioServicesPlaySystemSound(uploadedSound) }
  }
  /* ---------- 20: a task's Comments on a screen of their own (Haris, 2026-10-31) ----------
     A second web view, loaded once (a few seconds after the app's page is ready) and kept, shows only the open task's
     comments (the page in "comments only" mode: html.cm-only). As they're its whole page, they're scrolled by its own
     scroll view — iOS's — so the keyboard, staying at the latest comment and the jump button are iOS's own scrolling
     and nothing in the page moves the list (the jumping came from the page and iOS both moving it). It lies over the
     task page below its header while Comments is showing; the comment box is its page's then. Off with defaults
     e11_cweb_off. */
  var cweb: WKWebView?
  var cwebLoaded = false, cwebReadyToShow = false, cwebShown = false, cwebPaused = false
  var cwebTask: String?, cbarTask: String?
  var cmdSource: WKWebView?
  var cbarPage: WKWebView? { cwebShown ? cweb : web }
  let cbox = UIView()
  lazy var cwebNav = CommentsNav(self)
  func makeCommentsWeb() {
    guard cweb == nil, !defaults.bool(forKey: "e11_cweb_off"), let u = URL(string: serverURL() + "/?cm=1") else { return }
    let c = WKWebViewConfiguration()
    c.websiteDataStore = web.configuration.websiteDataStore     // (signed in as the app is)
    c.allowsInlineMediaPlayback = true
    c.applicationNameForUserAgent = "E11ConsoleiOS/\(SHELL_VERSION)"
    c.userContentController.add(WeakHandler(self), name: "e11ios")
    c.userContentController.addUserScript(WKUserScript(source: "window.__e11CommentsOnly = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
    let w = WKWebView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 400), configuration: c)
    w.isOpaque = false; w.backgroundColor = BG; w.scrollView.backgroundColor = BG
    w.scrollView.contentInsetAdjustmentBehavior = .never
    w.scrollView.alwaysBounceVertical = true
    w.scrollView.keyboardDismissMode = .none
    w.allowsLinkPreview = false
    w.navigationDelegate = cwebNav
    w.uiDelegate = self
    w.isHidden = true; w.alpha = 0
    w.hideKeyboardBar()
    if #available(iOS 16.4, *) { w.isInspectable = true }
    /* swiping right on the comments — a quick flick anywhere, or iPhone's slow "back" drag from the left edge: out of a
       reply thread to the comments first, from the comments to Details (Haris, 2026-10-31). On Details the page's own
       swipe goes back to the previous page. It acts once the finger has gone far enough sideways, without waiting for
       it to lift; a mostly-up/down drag stays a scroll. */
    let sw = UIPanGestureRecognizer(target: self, action: #selector(cwebPan(_:)))
    sw.delegate = self
    sw.cancelsTouchesInView = false
    cwebPanG = sw
    w.addGestureRecognizer(sw)
    // (in a box that clips it below the task's header: with the keyboard up the screen slides up under it)
    cbox.clipsToBounds = true
    cbox.isHidden = true
    cbox.backgroundColor = .clear
    w.isHidden = false; w.alpha = 1
    cbox.addSubview(w)
    view.insertSubview(cbox, aboveSubview: web)
    if jumpHitMade { view.insertSubview(jumpHit, aboveSubview: cbox) }
    cweb = w
    w.load(URLRequest(url: u))
  }
  var cwebPanG: UIPanGestureRecognizer?, cwebPanDone = false
  @objc func cwebPan(_ g: UIPanGestureRecognizer) {
    let t = g.translation(in: view), v = g.velocity(in: view)
    switch g.state {
    case .began: cwebPanDone = false
    case .changed, .ended:
      if cwebPanDone { return }
      // far enough to the right (or a quick flick), and more sideways than up / down
      if (t.x > 56 || (g.state == .ended && t.x > 16 && v.x > 500)) && t.x > abs(t.y) * 1.4 {
        cwebPanDone = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        cwebSwipe()
      }
    default: break
    }
  }
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard g === cwebPanG, let p = g as? UIPanGestureRecognizer else { return true }
    let v = p.velocity(in: view)
    return v.x > 0 && v.x > abs(v.y)
  }
  @objc func cwebSwipe() {
    cweb?.evaluateJavaScript("window.__e11CmBack ? window.__e11CmBack() : ''") { r, _ in
      if (r as? String) == "thread" { return }   // (out of a thread first)
      if let tp = self.taskPages.last { tp.setTab("details", tell: true); return }
      self.toDetails()
    }
  }
  func toDetails() {
    pageJS("(function(){ var b = document.querySelector('#detail .ph-seg.in-task [data-tab=\"details\"]'); if (b) b.click(); })()")
  }
  // its page has loaded: wait until it's signed in and has its data
  func cwebPageLoaded(_ n: Int = 0) {
    cweb?.evaluateJavaScript("((typeof db !== 'undefined' && db) && typeof currentUserId !== 'undefined' && currentUserId && window.__e11ShowComments) ? 'ok' : 'wait'") { r, _ in
      if (r as? String) == "ok" { self.cwebLoaded = true; self.cwebTask = nil; self.cwebUpdate() }
      else if n < 120 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.cwebPageLoaded(n + 1) } }
    }
  }
  // show it while the main page is on a task's Comments; hide it otherwise
  var cwebFresh = true
  func cwebUpdate() {
    guard let w = cweb else { return }
    if cbarTask == nil { cwebTask = nil }   // (the task closed: opened again, it starts at the latest comment)
    let want = cwebLoaded && !cwebPaused && cbarShow && cbarOnComments && cbarTask != nil && lockView == nil
    if want {
      if cwebTask != cbarTask || !cwebShown {
        // (every time it comes back: the task is opened again if its page closed it meanwhile)
        if cwebTask != cbarTask { cwebReadyToShow = false; cwebFresh = true }
        cwebTask = cbarTask
        w.evaluateJavaScript("window.__e11ShowComments && window.__e11ShowComments(\(jsonString([cbarTask ?? ""]).dropFirst().dropLast()))", completionHandler: nil)
      }
      if !cwebShown && cwebReadyToShow {
        cwebShown = true
        cbox.layer.removeAllAnimations()
        cbox.transform = .identity
        cbox.alpha = 0
        cbox.isHidden = false
        if taskComments != nil, taskPages.last?.feed != nil { cbox.isHidden = true }   // (30: the app draws the comments; this stays behind for writing)
        // at the latest comment only when the task has just been opened; back from Details, where it was (Haris, 2026-10-31)
        cwebInset(keepEnd: cwebFresh)
        cwebFresh = false
        UIView.animate(withDuration: 0.12) { self.cbox.alpha = 1 }
        // (the box is its page's now: it says what's in it)
        w.evaluateJavaScript("window.NativeComment && NativeComment.sync(true)", completionHandler: nil)
      }
    } else if cwebShown {
      // going: it slides off to the right with the task page going back to Details
      cwebShown = false
      let W = view.bounds.width
      UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut], animations: { self.cbox.transform = CGAffineTransform(translationX: W, y: 0) }) { _ in
        if !self.cwebShown { self.cbox.isHidden = true; self.cbox.transform = .identity }
      }
      pageJS("window.NativeComment && NativeComment.sync(true)")
    }
  }
  // the room under the comments: the comment box (and the keyboard under it); at the latest it stays at the latest
  func cwebAtEnd() -> Bool {
    guard let sv = cweb?.scrollView else { return true }
    return sv.contentOffset.y + sv.bounds.height >= sv.contentSize.height + sv.contentInset.bottom - 60
  }
  /* Where the comments screen is (Haris, 2026-10-31 — the third way; the first two fought WebKit):
     its box runs from below the task's header to the bottom of the screen and never changes size (a web view that
     changes size puts its scroll position back afterwards: the list jumped). With the keyboard up the comments slide
     up by the keyboard's height as one picture (a transform, in the keyboard's own animation) — so the web view is
     never under the keyboard and doesn't shift itself for it either; the room above (under the header) becomes
     scrollable room at the top, so the first comments can still be reached. Under the comments: the comment box. */
  func cwebInset(keepEnd: Bool, cover: CGFloat? = nil) {
    guard let w = cweb else { return }
    let sv = w.scrollView
    let kb = cover ?? keyboardCover
    let safe = view.safeAreaInsets.bottom
    let barH = cbarIfMade.map { $0.isHidden ? 0 : $0.bounds.height } ?? 0
    let top = cbarFeed?.minY ?? 172
    let box = CGRect(x: 0, y: top, width: view.bounds.width, height: view.bounds.height - top)
    if cbox.frame != box { cbox.frame = box }
    if w.frame.size != box.size || w.frame.origin != .zero { w.transform = .identity; w.frame = CGRect(origin: .zero, size: box.size) }
    let off = sv.contentOffset.y
    w.transform = CGAffineTransform(translationX: 0, y: -kb)
    sv.contentInset = UIEdgeInsets(top: kb, left: 0, bottom: (kb > 0 ? barH : safe + barH) + 6, right: 0)
    sv.verticalScrollIndicatorInsets = UIEdgeInsets(top: kb, left: 0, bottom: (kb > 0 ? barH : safe + barH), right: 0)
    let end = max(-kb, sv.contentSize.height + sv.contentInset.bottom - box.height)
    sv.contentOffset = CGPoint(x: 0, y: keepEnd ? end : min(max(-kb, off), end))
    // (--cm-top: how far the comments are slid up — the top of the page is then under the task's header, so a thread's
    // sticky "‹ Thread" bar sits that much lower)
    w.evaluateJavaScript("document.documentElement.style.setProperty('--cm-bottom','\(Int(sv.contentInset.bottom))px');document.documentElement.style.setProperty('--cm-top','\(Int(kb))px')", completionHandler: nil)
  }
  // the keyboard coming / going: the comments move with it, in its own animation
  func cwebRide(cover: CGFloat, duration: Double, curve: UInt, atEnd: Bool) {
    UIView.animate(withDuration: max(duration, 0.01), delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16).union(.beginFromCurrentState)) {
      self.cwebInset(keepEnd: atEnd, cover: cover)
    }
  }
  func cwebToEnd(animated: Bool) {
    guard let sv = cweb?.scrollView else { return }
    let end = max(-sv.contentInset.top, sv.contentSize.height + sv.contentInset.bottom - sv.bounds.height)
    sv.setContentOffset(CGPoint(x: 0, y: end), animated: animated)
  }
  // after Camera / Photos / Files from the comment box's +: once the picker has gone, the keyboard as it was before
  func cbarAfterPicker(_ n: Int) {
    guard let b = cbarIfMade, b.attaching else { return }
    if presentedViewController != nil && n < 30 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.cbarAfterPicker(n + 1) }; return }
    b.attachDone()
  }
  /* The page's "jump to the latest" button on Comments, tapped through a native spot over it: a tap on the page itself
     would take the keyboard away (the web view takes over the typing) and the list then jumped about (Haris,
     2026-10-30). Here the keyboard stays and iOS scrolls the list down itself. */
  var jumpHitMade = false
  lazy var jumpHit: UIButton = {
    jumpHitMade = true
    let b = UIButton(type: .custom)
    b.backgroundColor = .clear
    b.isHidden = true
    b.accessibilityLabel = "Jump to the latest comment"
    b.addAction(UIAction { [weak self] _ in self?.jumpToLatest() }, for: .touchUpInside)
    view.insertSubview(b, aboveSubview: cweb == nil ? web : cbox)
    return b
  }()
  func jumpToLatest() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    if cwebShown { return cwebToEnd(animated: true) }
    if let sv = feedScroll() {
      let end = max(-sv.adjustedContentInset.top, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
      sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: end), animated: true)
    } else { pageJS("(function(){ var b = document.querySelector('#detail .jl'); if (b) b.click(); })()") }
  }
  var cbarShow = false, cbarOnComments = false
  // the app's own task pages (TaskPage.swift, shell 30): a stack — a subtask opened from one goes on top
  var taskPages: [TaskPage] = []
  lazy var serverTask: ServerTask = { let s = ServerTask(); s.cookies = serverHome.cookies; return s }()
  var taskPan: UIScreenEdgePanGestureRecognizer?
  var taskPanSpent = false
  var cornerWaited = false
  var copyWatch: UUID?
  var prefetchedAt: [String: Date] = [:]
  // the screen hidden as a task was tapped (for the website's task page): the app's own page shows it again under itself
  var hiddenForOpen: (UIView?, Date)?
  var taskComments: String?           // the task whose comments show inside the page (its Comments tab)
  var taskTabHidden = false
  var cornerPending = false
  var composeIfMade: ComposeBox?
  lazy var corner: CornerButton = {
    CornerButton()   // (its taps are set the first time it's placed: updateCornerNow)
  }()
  func commentBar(_ a0: [String: Any]) {
    var a = a0
    // 30: under the app's own task page the page behind has no task open — what it says about the task (shown, on
    // Comments, which, where) is the task page's to say
    if taskComments != nil || !taskPages.isEmpty, cmdSource !== cweb { for k in ["show", "p", "feed", "task", "jump"] { a.removeValue(forKey: k) } }
    if taskPages.last?.feed != nil, cmdSource === cweb { a.removeValue(forKey: "jump") }   // (its jump button isn't seen)
    // 20: while the comments screen shows, the box is its page's; the main page only says where the task is (shown, on
    // Comments, which task, where its list starts) — and the other way round
    if let w = cweb, cmdSource === w {
      guard cwebShown else { return }
      for k in ["show", "p", "feed", "task"] { a.removeValue(forKey: k) }
      if let j = a["jump"] as? [NSNumber], j.count == 4 { a["jump"] = [j[0], NSNumber(value: j[1].doubleValue + cbox.frame.minY + w.transform.ty), j[2], j[3]] }
    } else if cweb != nil {
      if let t = a["task"] as? String { cbarTask = t } else if a["task"] is NSNull { cbarTask = nil }
      if cwebShown { a = a.filter { ["show", "p", "feed", "blur"].contains($0.key) } }
    }
    defer { cwebUpdate() }
    let b = cbar
    if let show = a["show"] as? Bool { cbarShow = show }
    if let p = a["p"] as? NSNumber { cbarOnComments = p.doubleValue > 0.5 }
    if let f = a["feed"] as? [NSNumber], f.count == 4 { cbarFeed = CGRect(x: f[0].doubleValue, y: f[1].doubleValue, width: f[2].doubleValue, height: f[3].doubleValue) }
    else if a["feed"] is NSNull || (a["show"] as? Bool) == false { cbarFeed = nil }
    if let j = a["jump"] as? [NSNumber], j.count == 4 { jumpHit.frame = CGRect(x: j[0].doubleValue, y: j[1].doubleValue, width: j[2].doubleValue, height: j[3].doubleValue); jumpHit.isHidden = false }
    else if a["jump"] is NSNull || (a["show"] as? Bool) == false { if cbarIfMade != nil || !jumpHit.isHidden { jumpHit.isHidden = true } }
    if !(cbarShow && cbarOnComments) && !jumpHit.isHidden { jumpHit.isHidden = true }
    // shown only on Comments at rest; leaving it (a swipe to Details, back to the list) takes the keyboard away too
    let want = cbarShow && cbarOnComments
    if want == b.isHidden {
      if want {
        b.isHidden = false
        UIView.animate(withDuration: 0.1) { b.alpha = 1 }
      } else {
        if b.text.isFirstResponder { b.text.resignFirstResponder() }
        UIView.animate(withDuration: 0.12, animations: { b.alpha = 0 }) { _ in if b.alpha == 0 { b.isHidden = true } }
      }
    } else if !want, b.text.isFirstResponder { b.text.resignFirstResponder() }
    if (a["clear"] as? Bool) == true { b.clear() }
    b.apply(a)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    defer { if let h = homeIfMade { h.tabTop = tabBar.isHidden ? nil : tabPillTop } }   // (23+: Home's + by the tab bar)
    let b = view.bounds
    // the page always fills the screen (no black band under it); the tab bar floats over its bottom and the page
    // keeps that much room free (--ios-tabs-h, web/phone.css)
    // (the page stays full height when the keyboard comes up — it's told how much the keyboard covers and makes room
    //  for it itself, so the list behind an open task never changes size and never has to be redrawn afterwards)
    web.frame = CGRect(x: 0, y: 0, width: b.width, height: b.height)
    let h = tabBar.sizeThatFits(b.size).height + view.safeAreaInsets.bottom
    tabBar.frame = CGRect(x: 0, y: b.height - h, width: b.width, height: h)
    // (iOS 26's floating bar reports more height than the glass capsule it draws: the page keeps room for the
    //  capsule itself, so the + button sits just above it rather than floating higher)
    var seen = h
    if #available(iOS 26, *) { seen = min(h, view.safeAreaInsets.bottom + 46) }
    let cover = tabBar.isHidden ? 0 : Int(seen.rounded())
    if cover != tabCover { tabCover = cover; pageJS("document.documentElement.style.setProperty('--ios-tabs-h','\(cover)px')") }
    lockView?.frame = b
    reviewLink.frame = CGRect(x: 0, y: b.height - view.safeAreaInsets.bottom - 44, width: b.width, height: 44)
    hud?.place(in: b, above: tabBar.isHidden ? view.safeAreaInsets.bottom : h)
  }
  func loadHome(_ path: String = "/") {
    guard let u = URL(string: serverURL() + path) else { return }
    if !SELFTEST.isEmpty, let host = u.host, let email = procEnv["E11_SELFTEST_EMAIL"],
       let c = HTTPCookie(properties: [.domain: host, .path: "/", .name: "e11_dev_email", .value: email]) {
      web.configuration.websiteDataStore.httpCookieStore.setCookie(c) { self.web.load(URLRequest(url: u)) }
    } else { web.load(URLRequest(url: u)) }
  }
  var tabCover = -1
  var keyboardUp = false
  // the app's own background (seen around the keyboard's rounded corners, and while the page resizes) takes the
  // page's colour, light or dark — not a black band
  func syncBackground() {
    guard pageReady else { return }
    web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") { v, _ in
      guard let str = v as? String else { return }
      let n = str.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).filter { !$0.isEmpty }.compactMap { Double($0) }
      guard n.count >= 3, n.count < 4 || n[3] > 0.5 else { return }
      let c = UIColor(red: n[0] / 255, green: n[1] / 255, blue: n[2] / 255, alpha: 1)
      self.view.backgroundColor = c; self.web.backgroundColor = c; self.web.scrollView.backgroundColor = c
    }
  }
  var keyboardCover: CGFloat = 0
  lazy var pull = UIPanGestureRecognizer(target: self, action: #selector(pullKeyboard(_:)))
  @objc func pullKeyboard(_ g: UIPanGestureRecognizer) {
    guard keyboardUp, keyboardCover > 0, g.state == .changed, g.velocity(in: view).y > 0 else { return }
    let edge = view.bounds.height - keyboardCover
    if g.location(in: view).y >= edge - 8 {
      pageJS("document.activeElement && document.activeElement.blur && document.activeElement.blur()")
      view.endEditing(true)
    }
  }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
  func keyboardMoves(_ n: Notification, gone: Bool = false) {
    if !gone { syncBackground() }
    var cover: CGFloat = 0
    if !gone, let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
      let r = view.convert(end, from: nil)
      cover = max(0, view.bounds.maxY - r.minY)
    }
    keyboardUp = cover > 0
    if keyboardUp { if pull.view == nil { web.addGestureRecognizer(pull) } } else if pull.view != nil { web.removeGestureRecognizer(pull) }
    if cover == keyboardCover { return }
    let rising = cover > 0 && keyboardCover == 0
    keyboardCover = cover
    let dur = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
    let curve = (n.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
    // (the comments screen's own web view also shifts itself for the keyboard — WebKit's automatic keyboard avoidance
    //  on its scroll view, which ran after ours and left the list short of the latest comment: ours goes after it)
    // (the keyboard coming up: to the latest comment, wherever the list was — Haris, 2026-10-31)
    if cwebShown { cwebRide(cover: cover, duration: dur, curve: curve, atEnd: rising || cwebAtEnd()) }   // (now, before its web view looks at the keyboard: by then it's no longer under it)
    else { feedRide(cover: cover, duration: dur, curve: curve) }   // (first: the page hears it's iOS moving the list this time)
    pageJS("window.__e11Kb && window.__e11Kb(\(Int(cover.rounded())), \(Int(dur * 1000)), 1)")
    rideKeyboard(to: cover, duration: dur, curve: curve)
    if web.scrollView.contentOffset != .zero { web.scrollView.setContentOffset(.zero, animated: false) }
  }
  /* Shell 19 (Haris, 2026-10-30: the comments "fight" and change position as the keyboard comes up): on a task's Comments
     the list is moved by iOS itself — its own scroll view, inside the keyboard's own animation (same duration and curve),
     as Messages does — instead of the page following the keyboard frame by frame. Coming up: the scroll view gets the
     keyboard's room as its own and scrolls up with it (a short list only by what the keyboard would cover); once up, the
     page keeps that room itself (--ph-kbpad, looks the same) and the scroll view's goes. Going down: it scrolls back
     with the keyboard, then the page lets go of the room. */
  var cbarFeed: CGRect?
  var feedT: CGFloat = 0
  var feedGeo: [String: Any] = [:]
  func feedScroll() -> UIScrollView? {
    guard cbarShow, cbarOnComments else { return nil }
    // (the page hasn't said where the list is yet — the box tapped the moment Comments opened: the tall list that fills
    //  the screen's width, below the task's header)
    let W = web.bounds.width
    let r = (cbarFeed.flatMap { $0.width > 10 && $0.height > 10 ? $0 : nil }) ?? CGRect(x: 0, y: -1, width: W, height: -1)
    // (the page's list is one of WebKit's own scroll views: the one where the page says it is, of its size — looked for
    //  among all of them, as hit-testing a point lands on the web view's own content)
    // (its size and top; the nearest to where the page said it was across — the page may say it a moment before a
    //  swipe to Comments has quite come to rest)
    var best: UIScrollView?, bestDX = CGFloat.greatestFiniteMagnitude
    func walk(_ v: UIView) {
      for c in v.subviews {
        if let sv = c as? UIScrollView, sv !== web.scrollView, !sv.isHidden, sv.window != nil {
          let f = sv.convert(sv.bounds, to: web)
          let fits = r.height < 0
            ? abs(f.width - W) < 4 && abs(f.minX) < 4 && f.height > 300 && f.minY > 80 && sv.contentSize.height > 0
            : abs(f.width - r.width) < 4 && abs(f.height - r.height) < 4 && abs(f.minY - r.minY) < 4
          if fits, abs(f.minX - r.minX) < bestDX { best = sv; bestDX = abs(f.minX - r.minX) }
        }
        walk(c)
      }
    }
    walk(web.scrollView)
    return best
  }
  // (for the self-test: every WebKit scroll view and where it is)
  func scrollViewsSeen() -> [String] {
    var out: [String] = []
    func walk(_ v: UIView) { for c in v.subviews { if let sv = c as? UIScrollView, sv !== web.scrollView { let f = sv.convert(sv.bounds, to: web); out.append("\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))") }; walk(c) } }
    walk(web.scrollView)
    return out
  }
  func feedRide(cover: CGFloat, duration: Double, curve: UInt) {
    guard let sv = feedScroll() else {
      if cover == 0 { feedT = 0 }
      // (why not, for the self-test: the box's state, where the page says the list is, the scroll views under that spot)
      let seen = scrollViewsSeen()
      feedGeo = ["found": false, "show": cbarShow, "comments": cbarOnComments, "feed": cbarFeed.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? [], "scrollViews": seen]
      return
    }
    let opts = UIView.AnimationOptions(rawValue: curve << 16).union(.beginFromCurrentState)
    let H = sv.bounds.height, C = sv.contentSize.height, off = sv.contentOffset.y
    if cover > 0 && feedT == 0 {
      let T = max(0, cover - view.safeAreaInsets.bottom)
      let shift = max(0, T - max(0, H + off - C))   // (a short list: only what the keyboard would cover of it)
      feedT = T
      feedGeo = ["found": true, "T": T, "shift": shift, "from": off]
      pageJS("window.__e11FeedKb && window.__e11FeedKb('start')")
      UIView.animate(withDuration: max(duration, 0.01), delay: 0, options: opts, animations: {
        sv.contentInset.bottom = T
        sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: off + shift)
      }) { _ in
        self.web.evaluateJavaScript("window.__e11FeedKb && window.__e11FeedKb('up', \(Int(T.rounded())))") { _, _ in
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sv.contentInset.bottom = 0   // (the page keeps the room now — also when the keyboard has gone again meanwhile; it was left behind, a keyboard-high gap under the last comment)
            self.feedGeo["inset"] = sv.contentInset.bottom; self.feedGeo["to"] = sv.contentOffset.y
          }
        }
      }
    } else if cover == 0 && feedT > 0 {
      let T = feedT
      feedT = 0
      let to = max(0, min(off, C - T - H))
      pageJS("window.__e11FeedKb && window.__e11FeedKb('start')")
      UIView.animate(withDuration: max(duration, 0.01), delay: 0, options: opts, animations: {
        sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: to)
        sv.contentInset.bottom = 0
      }) { _ in self.pageJS("window.__e11FeedKb && window.__e11FeedKb('down')"); self.feedGeo["down"] = to }
    }
  }
  // The comment box moves with the keyboard, not ahead of it: an invisible view is animated with the keyboard's own
  // duration and curve (the same animation iOS gives the keyboard), and every screen frame the page is told where
  // the keyboard's top is now (--ios-kb). A CSS curve of the page's own raced ahead and the box slammed down.
  let kbProbe: UIView = { let v = UIView(); v.alpha = 0; v.isUserInteractionEnabled = false; return v }()
  var kbLink: CADisplayLink?
  var kbUntil: CFTimeInterval = 0
  var kbTarget = 0
  var kbSent = -1
  func probeCover() -> CGFloat {
    let y = kbProbe.layer.presentation()?.frame.minY ?? kbProbe.frame.minY
    return max(0, view.bounds.maxY - y)
  }
  func rideKeyboard(to cover: CGFloat, duration: Double, curve: UInt) {
    if kbProbe.superview == nil { view.insertSubview(kbProbe, at: 0); kbProbe.frame = CGRect(x: 0, y: view.bounds.maxY, width: 1, height: 1) }
    let now = probeCover()                                   // (from where it is now, if the last move hasn't finished)
    kbProbe.layer.removeAllAnimations()
    kbProbe.frame = CGRect(x: 0, y: view.bounds.maxY - now, width: 1, height: 1)
    kbTarget = Int(cover.rounded())
    guard duration > 0.01 else { kbProbe.frame.origin.y = view.bounds.maxY - cover; sendKb(kbTarget); return }
    UIView.animate(withDuration: duration, delay: 0, options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState]) {
      self.kbProbe.frame.origin.y = self.view.bounds.maxY - cover
    }
    kbUntil = CACurrentMediaTime() + duration + 0.12
    if kbLink == nil {
      let l = CADisplayLink(target: self, selector: #selector(kbTick))
      if #available(iOS 15.0, *) { l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120) }
      l.add(to: .main, forMode: .common)
      kbLink = l
    }
  }
  @objc func kbTick() {
    if CACurrentMediaTime() >= kbUntil { kbLink?.invalidate(); kbLink = nil; sendKb(kbTarget); return }
    sendKb(Int(probeCover().rounded()))
  }
  func sendKb(_ px: Int) {
    if px == kbSent { return }
    kbSent = px
    pageJS("window.__e11KbStep ? window.__e11KbStep(\(px)) : (window.__e11Kb && window.__e11Kb(\(px), 0))")
  }
  var offsetWatch: NSKeyValueObservation?
  var resetting = false
  func pageJS(_ js: String) { web?.evaluateJavaScript(js, completionHandler: nil) }
  var serverHost: String { URL(string: serverURL())?.host ?? "" }

  /* ---------- navigation: our server and its sign-in stay here; other sites open in Safari ---------- */
  func allowedHere(_ u: URL) -> Bool {
    guard let h = u.host?.lowercased() else { return true }
    return h == serverHost.lowercased() || h.hasSuffix(".cloudflareaccess.com") || h.hasSuffix("cloudflare.com")
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if action.shouldPerformDownload { return decisionHandler(.download) }
    guard let u = action.request.url, let s = u.scheme?.lowercased() else { return decisionHandler(.allow) }
    if ["about", "blob", "data"].contains(s) { return decisionHandler(.allow) }
    if ["mailto", "tel"].contains(s) { UIApplication.shared.open(u); return decisionHandler(.cancel) }
    if s == "http" || s == "https" {
      // a file of ours opened as the whole page would leave no way back: it's downloaded to the share sheet instead
      if action.targetFrame?.isMainFrame != false, u.host == serverHost, u.path.hasPrefix("/__file/") { return decisionHandler(.download) }
      // the App Review copy's "Sign in to E11 Console" link: back to the live copy here, not in Safari
      if defaults.string(forKey: "e11_server") == "review", action.targetFrame?.isMainFrame != false, u.host == URL(string: LIVE_URL)?.host {
        defaults.set("live", forKey: "e11_server"); loadHome(); return decisionHandler(.cancel)
      }
      if action.targetFrame?.isMainFrame == false || allowedHere(u) { return decisionHandler(.allow) }
      UIApplication.shared.open(u)
      return decisionHandler(.cancel)
    }
    decisionHandler(.cancel)
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if let r = response.response as? HTTPURLResponse {
      let disp = (r.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
      if disp.hasPrefix("attachment") || !response.canShowMIMEType { return decisionHandler(.download) }
      if response.isForMainFrame, r.url?.host == serverHost, (502...504).contains(r.statusCode) || (520...530).contains(r.statusCode) {
        decisionHandler(.cancel); DispatchQueue.main.async { self.showOffline() }; return
      }
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    // our pages draw under the status bar themselves; the Cloudflare sign-in page doesn't, so it gets the usual margins
    let ours = webView.url?.host == serverHost || webView.url?.scheme == "about"
    webView.scrollView.contentInsetAdjustmentBehavior = ours ? .never : .always
    if ours { tabCover = -1; view.setNeedsLayout() }
    if webView.url?.host == serverHost { bootCommitted() }   // (back from signing in: the startup screen — Boot.swift)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let onServer = webView.url?.host == serverHost
    pageReady = onServer
    reviewLink.isHidden = !(webView.url?.host ?? "").hasSuffix(".cloudflareaccess.com")
    webView.hideKeyboardBar()
    if onServer { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.syncBackground() } }
    if onServer { shareSignIn(); bootPageArrived() }
    if onServer, !earlyJS.isEmpty { let js = earlyJS; earlyJS = []; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { js.forEach { self.pageJS($0) } } }
    if onServer { tabCover = -1; view.setNeedsLayout(); flushPending(); if !SELFTEST.isEmpty && !started { started = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.selfTest() } } }
    // (the sign-in page: no tabs, no startup screen — not the "can't reach" page under the app's own screens offline: the
    //  tab bar went, Haris 2026-11-05)
    else if !((quickBooted || Main.noPage) && webView.url?.scheme == "about") { tabBar.isHidden = true; tabsHidden = true; view.setNeedsLayout(); splashGone(fast: true) }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
  func failed(_ error: Error) {
    let e = error as NSError
    let offline = [NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                   NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorBadServerResponse, NSURLErrorSecureConnectionFailed]
    if e.domain == NSURLErrorDomain, offline.contains(e.code) { showOffline() }
  }
  func showOffline() {
    // (the startup screen up: it says so itself, with Try again — Part B step 8; the page underneath tries again)
    if let s = splash, !s.leaving, !quickBooted { splashHeard = true; s.command(["status": "Can’t reach E11 Console — check your internet connection", "retry": true]) }
    else if !quickBooted { splashGone(fast: true) }
    if retrying { return }
    retrying = true
    pageReady = false
    // (a quick start — the app's own screens from its copy: its tab bar and startup screen stay as they are; only the
    //  website behind tries again. They were taken away offline — the startup screen cut off mid-way, the tab bar gone
    //  after a few seconds: Haris 2026-11-05)
    if !quickBooted { tabBar.isHidden = true; tabsHidden = true; view.setNeedsLayout() }
    // (the app's own screens up — a quick start: nothing to show behind them, only the trying again)
    if quickBooted { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.retrying = false; self.loadHome() }; return }
    let html = "<html><head><meta name=viewport content='width=device-width'></head><body style=\"background:#0c0d0f;color:#bbb;font:16px -apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center\"><div><b style=\"color:#fff\">Can’t reach E11 Console</b><br><br>Check your internet connection.<br>Trying again…</div></body></html>"
    web.loadHTMLString(html, baseURL: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.retrying = false; self.loadHome() }
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

  /* ---------- the page's own boxes and windows ---------- */
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if let u = action.request.url { if allowedHere(u) { webView.load(action.request) } else { UIApplication.shared.open(u) } }
    return nil
  }
  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
    topMost().present(a, animated: true)
  }
  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
    a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
    topMost().present(a, animated: true)
  }

  /* ---------- downloads: saved, then the share sheet (Save to Files, Save Image, AirDrop…) ---------- */
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { adopt(download) }
  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { adopt(download) }
  func adopt(_ d: WKDownload) {
    let from = d.originalRequest?.url?.absoluteString ?? ""
    if !from.isEmpty, downloadFrom.values.contains(from) {
      d.cancel { _ in }
      pageJS("window.toast && toast('Already downloading')")
      return
    }
    let k = ObjectIdentifier(d)
    downloadFrom[k] = from
    downloadNames[k] = d.originalRequest?.url?.lastPathComponent.removingPercentEncoding ?? "file"
    d.delegate = self
    downloadWatch[k] = d.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
      DispatchQueue.main.async { self?.paintHUD() }
    }
    paintHUD()
  }
  func endDownload(_ d: WKDownload) {
    let k = ObjectIdentifier(d)
    downloadFrom.removeValue(forKey: k); downloadNames.removeValue(forKey: k)
    downloadWatch.removeValue(forKey: k)?.invalidate()
    paintHUD()
  }
  var liveDownloads: [WKDownload] = []
  func paintHUD() {
    liveDownloads = liveDownloads.filter { downloadFrom[ObjectIdentifier($0)] != nil }
    if downloadFrom.isEmpty { hud?.removeFromSuperview(); hud = nil; return }
    if hud == nil { let h = DownloadHUD(); h.onCancel = { [weak self] in self?.cancelDownloads() }; view.addSubview(h); hud = h; view.setNeedsLayout(); view.layoutIfNeeded() }
    var done: Int64 = 0, total: Int64 = 0, known = true
    for d in liveDownloads where downloadFrom[ObjectIdentifier(d)] != nil {
      done += d.progress.completedUnitCount
      if d.progress.totalUnitCount > 0 { total += d.progress.totalUnitCount } else { known = false }
    }
    let n = downloadFrom.count
    let name = n == 1 ? (downloadNames.values.first ?? "file") : "\(n) files"
    let mb = { (b: Int64) in String(format: "%.1f MB", Double(b) / 1_048_576) }
    let frac = known && total > 0 ? Float(done) / Float(total) : -1
    hud?.show(title: "Downloading \(name)", detail: known && total > 0 ? "\(mb(done)) of \(mb(total))" : (done > 0 ? mb(done) : "Starting…"), progress: frac)
  }
  func cancelDownloads() {
    for d in liveDownloads { d.cancel { _ in } }
    for d in liveDownloads { endDownload(d) }
    downloads.removeAll()
  }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let name = suggestedFilename.isEmpty ? "file" : suggestedFilename.replacingOccurrences(of: "/", with: "-")
    let url = dir.appendingPathComponent(name)
    downloads[ObjectIdentifier(download)] = url
    if !liveDownloads.contains(where: { $0 === download }) { liveDownloads.append(download) }
    paintHUD()
    completionHandler(url)
  }
  func downloadDidFinish(_ download: WKDownload) {
    endDownload(download)
    guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = view
    topMost().present(sheet, animated: true)
  }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    let wasLive = downloadFrom[ObjectIdentifier(download)] != nil
    downloads.removeValue(forKey: ObjectIdentifier(download))
    endDownload(download)
    if wasLive, (error as NSError).code != NSURLErrorCancelled { pageJS("window.toast && toast('Download failed — try again')") }
  }

  /* ---------- the native tab bar (the page's own tabs; tapping one taps the page's button) ---------- */
  func symbol(_ v: String) -> String {
    switch v {
    case "today": return "sun.max"
    case "mytasks": return "checkmark.circle"
    case "inbox": return "tray"
    case "reviews": return "checkmark.shield"
    case "projects": return "folder"
    case "clients": return "square.grid.2x2"
    case "plans": return "calendar"
    case "fin-reimb": return "doc.plaintext"
    case "fin-expenses": return "banknote"
    case "team": return "person.2"
    case "me": return "person.crop.circle"
    default: return "circle"
    }
  }
  // the Me tab: your photo (MePhoto — the same one as the top corner), with a ring when it's the open tab and the dot at its
  // bottom right (green online, red offline); the plain icon only before anything of you is known
  func paintMeTab() {
    guard let i = tabKeys.firstIndex(of: "me"), let item = tabBar.items?[i] else { return }
    guard let src = MePhoto.shared.picture(56) else { item.image = UIImage(systemName: symbol("me")); item.selectedImage = nil; return }
    let on = tabOnline[i] ?? netUp
    item.image = roundPhoto(src, ring: nil, online: on)
    item.selectedImage = roundPhoto(src, ring: tabBar.tintColor ?? .systemBlue, online: on)
  }
  private var meWatched = false
  // ---------- the app's own tab bar (Part B step 1, Haris 2026-11-04) ----------
  // The tabs, their names and counts come from the app's own copy (web/appview.js tabs — the page's rules, in the app),
  // at launch and with every change, not from the website. The page still says: whether the bar hides (a page of its own
  // over everything), the Plans tab's count (still its rules), your photo's place; and where it went by itself (an Inbox
  // update opening Reviews) — taken only when it changes. Off on the server (kv app-tabs): the page's tab bar, as before.
  private var pageTabs: [String: Any]?, pageOn: String?, quickMe: String?
  var lastTabTap: (key: String, at: Date)?
  func pageTabsIn(_ a: [String: Any]) {
    let on = (a["tabs"] as? [[String: Any]] ?? []).first(where: { ($0["on"] as? Bool) == true })?["v"] as? String
    var moved: String? = nil
    if on != pageOn {
      pageOn = on
      // (a tab tapped a moment ago: the page catching up with an earlier one isn't a move of its own)
      if let t = lastTabTap, Date().timeIntervalSince(t.at) < 1.5, on != t.key { moved = nil } else { moved = on }
    }
    pageTabs = a
    // (the person to open as next time: the page's now — an Office Admin has no Home to say it, so after View as… the
    //  app came back as the person before, with their photo — Haris 2026-11-05)
    if let w = pagePerson, !w.isEmpty, quickMe != w { quickMe = w; saveQuick(["me": w]) }
    // (the person the page is now — View as… someone, back to me: the app's copy follows at once, and until it is that
    //  person's, the page's tabs are shown — an Office Admin got the owner's tabs, Haris 2026-11-04)
    pageIs(pagePerson)
    if let own = ownTabs(moved) { setTabs(own) } else { setTabs(a) }
  }
  private var pagePerson: String? { ((pageTabs?["tabs"] as? [[String: Any]]) ?? []).first(where: { ($0["v"] as? String) == "me" })?["who"] as? String }
  // Automatic light / dark by the app's own clock: every minute (and on coming back), light from sunrise to sunset
  // (the day's times the page gave, moved to today), told to everything as the page's setAppearance would
  private var lookTimer: Timer?
  func ownAppearanceWatch() {
    guard lookTimer == nil else { return }
    lookTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.ownAppearanceTick() }
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.ownAppearanceTick() }
  }
  func ownAppearanceTick() {
    guard AppData.shared.tabsOn, defaults.string(forKey: "e11_theme_mode") == "auto",
          let r = defaults.string(forKey: "e11_sun_rise").flatMap({ isoDate($0) }),
          let st = defaults.string(forKey: "e11_sun_set").flatMap({ isoDate($0) }) else { return }
    let cal = Calendar.current, now = Date()
    let today = { (d: Date) -> Date in cal.date(bySettingHour: cal.component(.hour, from: d), minute: cal.component(.minute, from: d), second: 0, of: now) ?? d }
    let want = now >= today(r) && now < today(st) ? "light" : "dark"
    if defaults.string(forKey: "e11_look") != want { run("setAppearance", ["mode": want]) { _ in } }
  }
  private func isoDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
  }
  // the bar drawn again as it is — on the tab that's showing now, never the one the last drawing had on (coming back
  // from another app it went to Home: Haris 2026-11-05)
  func redrawTabs() {
    guard var a = lastTabs else { return }
    let cur = selectedTabKey
    if !cur.isEmpty, var list = a["tabs"] as? [[String: Any]], list.contains(where: { ($0["v"] as? String) == cur }) {
      for i in list.indices { list[i]["on"] = (list[i]["v"] as? String) == cur }
      a["tabs"] = list
    }
    setTabs(a)
  }
  func refreshOwnTabs() { if let own = ownTabs(nil) { setTabs(own) } }
  private func ownTabs(_ moved: String?) -> [String: Any]? {
    guard AppData.shared.tabsOn, AppData.shared.ready, pagePerson == nil || pagePerson == AppData.shared.me, let m = AppData.shared.screen("tabs").model,
          var list = m["tabs"] as? [[String: Any]], !list.isEmpty else { return nil }
    let page = (pageTabs?["tabs"] as? [[String: Any]]) ?? (lastTabs?["tabs"] as? [[String: Any]]) ?? []
    let keys = list.map { $0["v"] as? String ?? "" }
    let cur = selectedTabKey
    let on = moved.flatMap { keys.contains($0) ? $0 : nil } ?? (keys.contains(cur) ? cur : (pageOn.flatMap { keys.contains($0) ? $0 : nil } ?? "today"))
    for i in list.indices {
      let v = list[i]["v"] as? String ?? ""
      let p = page.first(where: { ($0["v"] as? String) == v })
      if v == "plans", (m["plans"] as? Bool) == true { list[i]["badge"] = p?["badge"] as? String ?? "" }
      if v == "me" {
        for k in ["photo", "photoUrl", "who", "online"] { if let x = p?[k] { list[i][k] = x } }
        if list[i]["who"] == nil, let me = AppData.shared.me { list[i]["who"] = me }
      }
      list[i]["on"] = v == on
    }
    return ["tabs": list, "hidden": (pageTabs?["hidden"] as? Bool) ?? false]
  }
  func setTabs(_ a: [String: Any]) {
    if !meWatched {
      meWatched = true
      MePhoto.shared.fetch = { [weak self] u, done in self?.fetchPhoto(u, done) }
      MePhoto.shared.watch { [weak self] in self?.paintMeTab() }
    }
    // (the bar in the app's own look before anything is drawn: without the website nobody said it at the start, so the
    //  bar kept iPhone's blue and its badged icons were baked in the phone's look — dark on dark after coming back from
    //  another app, Haris 2026-11-05)
    let ink: UIColor = appStyle == .dark ? .white : .black
    if tabBar.overrideUserInterfaceStyle != appStyle || tabBar.tintColor != ink || tabBar.unselectedItemTintColor != ink {
      tabBar.overrideUserInterfaceStyle = appStyle; tabBar.tintColor = ink; tabBar.unselectedItemTintColor = ink; tabBadgeKey = [:]
    }
    let list = a["tabs"] as? [[String: Any]] ?? []
    let keys = list.map { $0["v"] as? String ?? "" }
    if keys != tabKeys || (tabBar.items?.count ?? 0) != keys.count {
      tabKeys = keys
      tabPhoto = [:]
      tabBadgeKey = [:]
      tabBar.items = list.enumerated().map { i, t in
        // (an Office Admin's first tab is Overview: a grid — Haris 2026-11-04)
        UITabBarItem(title: t["label"] as? String ?? "", image: UIImage(systemName: (t["label"] as? String) == "Overview" ? "square.grid.2x2" : (t["label"] as? String) == "Client Assets" ? "folder" : symbol(t["v"] as? String ?? "")), tag: i)
      }
    } else {
      for (i, t) in list.enumerated() { tabBar.items?[i].title = t["label"] as? String ?? "" }
    }
    // the Me tab: your photo — the app's own (MePhoto), never the page's drawing of it (black when drawn before it had
    // loaded — Haris 2026-11-03); the page only says where it is on the server and whether you're online
    for (i, t) in list.enumerated() where (t["v"] as? String) == "me" {
      tabOnline[i] = (t["online"] as? Bool ?? true) && netUp
      if let w = t["who"] as? String, !w.isEmpty { MePhoto.shared.person(w) }
      MePhoto.shared.source(t["photoUrl"] as? String)
    }
    paintMeTab()
    // counts sit on the icon's top-right corner, overlapping it a little (like an app icon's badge), drawn into the
    // icon itself: iOS's own tab badge sits further out
    lastTabs = a
    saveQuick(["tabs": a])
    for (i, t) in list.enumerated() {
      guard let item = tabBar.items?[i] else { continue }
      let b = t["badge"] as? String ?? ""
      let v = t["v"] as? String ?? ""
      item.badgeValue = nil
      if t["photo"] == nil {
        let key = "\(v)|\(b)|\(tabBar.traitCollection.userInterfaceStyle.rawValue)"
        if tabBadgeKey[i] != key {
          tabBadgeKey[i] = key
          if b.isEmpty { item.image = UIImage(systemName: symbol(v)); item.selectedImage = nil }
          else {
            item.image = badged(symbol(v), b, color: tabBar.unselectedItemTintColor ?? ink)
            item.selectedImage = badged(symbol(v), b, color: tabBar.tintColor ?? .systemBlue)
          }
        }
      }
      if (t["on"] as? Bool) == true { tabBar.selectedItem = item; shownTab = item.tag }
    }
    let hide = (a["hidden"] as? Bool) == true || list.isEmpty
    // (a task page of the app's own is over everything: the bar stays as the page has it, and comes back to what the
    //  website wants now when the page closes — it came and went by itself, Haris 2026-11-02)
    if hide != tabsHidden && !taskPages.isEmpty { tabsHidden = hide; return }
    if hide != tabsHidden {
      tabsHidden = hide
      // in place first (never flying in from the corner), then a fade
      UIView.performWithoutAnimation { self.view.layoutIfNeeded() }
      if hide {
        UIView.animate(withDuration: 0.18, animations: { self.tabBar.alpha = 0 }) { _ in
          if self.tabsHidden { self.tabBar.isHidden = true; self.view.setNeedsLayout() }
        }
      } else {
        if tabBar.isHidden { tabBar.alpha = 0; tabBar.isHidden = false }
        UIView.performWithoutAnimation { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
        UIView.animate(withDuration: 0.18) { self.tabBar.alpha = self.formTucked ? 0 : 1 }
      }
    }
  }
  var lastOwnBadge = -1   // (the icon's count last set from the copy)
  var formTucked = false   // (a New task / amendments draft tucked at the bottom: the tab bar stays faded)
  var tabPhoto: [Int: String] = [:]
  var tabPhotoSrc: [Int: UIImage] = [:], tabOnline: [Int: Bool] = [:]
  // the phone's own connection: gone → the Me tab's dot turns red at once (the page says so too after a while)
  var netUp = true
  lazy var netWatch: NWPathMonitor = {
    let m = NWPathMonitor()
    m.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let up = path.status == .satisfied
        if up != self.netUp { self.netUp = up; self.redrawTabs() }
        if up { self.serverHome.send(); self.myTasksWaiting()?.send(); self.inboxWaiting()?.send() }   // (anything waiting goes now)
      }
    }
    m.start(queue: DispatchQueue(label: "e11.net"))
    return m
  }()
  var tabBadgeKey: [Int: String] = [:]
  var lastTabs: [String: Any]?
  // a tab's icon with its count on the top-right corner, overlapping the icon a little
  func badged(_ name: String, _ text: String, color: UIColor) -> UIImage {
    let resolved = color.resolvedColor(with: tabBar.traitCollection)   // (the tab bar's own light / dark — not the phone's)
    let sym = (UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)) ?? UIImage())
      .withTintColor(resolved, renderingMode: .alwaysOriginal)
    let font = UIFont.systemFont(ofSize: 11.5, weight: .bold)
    let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white])
    let ls = label.size()
    let bh: CGFloat = 17, bw = max(bh, ls.width + 9)
    let pad = max(bw - 8, 9)                 // room for the badge beyond the icon, the same on every side so the icon stays centred
    let size = CGSize(width: sym.size.width + pad * 2, height: sym.size.height + pad * 2)
    return UIGraphicsImageRenderer(size: size).image { _ in
      let ir = CGRect(x: pad, y: pad, width: sym.size.width, height: sym.size.height)
      sym.draw(in: ir)
      let br = CGRect(x: ir.maxX - bw + 8, y: ir.minY - 7, width: bw, height: bh)
      UIColor.systemRed.setFill()
      UIBezierPath(roundedRect: br, cornerRadius: bh / 2).fill()
      label.draw(at: CGPoint(x: br.midX - ls.width / 2, y: br.midY - ls.height / 2))
    }.withRenderingMode(.alwaysOriginal)
  }
  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle, lastTabs != nil { tabBadgeKey = [:]; redrawTabs() }
  }
  // a picture from our server, with the page's sign-in (its cookies)
  func fetchPhoto(_ url: URL, _ done: @escaping (UIImage?) -> Void) {
    // (people's photos kept on the phone too — after the app restarts or updates they're there at once: Haris 2026-11-05;
    //  a new photo has a new address, so an old one is never shown for it)
    let key = "ph:" + url.absoluteString
    if let d = DiskPics.get(key), let img = UIImage(data: d) { return done(img) }
    web.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
      var req = URLRequest(url: url)
      let mine = cookies.filter { url.host?.hasSuffix($0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain) == true }
      req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: mine)
      URLSession.shared.dataTask(with: req) { data, resp, _ in
        let ok = (resp as? HTTPURLResponse)?.statusCode == 200
        let img = ok ? data.flatMap { UIImage(data: $0) } : nil
        if img != nil, let d = data { DiskPics.put(key, d) }
        DispatchQueue.main.async { done(img) }
      }.resume()
    }
  }
  func roundPhoto(_ src: UIImage, ring: UIColor?, online: Bool? = nil) -> UIImage {
    let size: CGFloat = 28
    let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return r.image { ctx in
      defer {
        // the dot: 9 pt, at the bottom right, edged in the bar's colour (as a status dot on a photo)
        if let on = online {
          ctx.cgContext.resetClip()
          let d: CGFloat = 9, edge: CGFloat = 1.5
          let dot = CGRect(x: size - d, y: size - d, width: d, height: d)
          // (the gap round it cut out of the photo, not painted: the bar shows through in light and dark alike — painted in
          //  the colour of the moment, it stayed white after a switch to dark, Haris 2026-11-01)
          ctx.cgContext.setBlendMode(.clear)
          UIBezierPath(ovalIn: dot.insetBy(dx: -edge, dy: -edge)).fill()
          ctx.cgContext.setBlendMode(.normal)
          (on ? UIColor.systemGreen : UIColor.systemRed).setFill()
          UIBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)).fill()
        }
      }
      let box = CGRect(x: 0, y: 0, width: size, height: size)
      let inset: CGFloat = ring == nil ? 1 : 2.5
      let pic = box.insetBy(dx: inset, dy: inset)
      UIBezierPath(ovalIn: pic).addClip()
      let k = max(pic.width / max(src.size.width, 1), pic.height / max(src.size.height, 1))
      let w = src.size.width * k, h = src.size.height * k
      src.draw(in: CGRect(x: pic.midX - w / 2, y: pic.midY - h / 2, width: w, height: h))
      if let ring = ring {
        let p = UIBezierPath(ovalIn: box.insetBy(dx: 1, dy: 1)); p.lineWidth = 2
        UIGraphicsGetCurrentContext()?.resetClip(); ring.setStroke(); p.stroke()
      }
    }.withRenderingMode(.alwaysOriginal)
  }
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard item.tag < tabKeys.count else { return }
    ProfileAskCard.current?.go()   // (another page: the birthday / city card slips away)
    UISelectionFeedbackGenerator().selectionChanged()
    // (the tab you're on, tapped again — from a page inside it: back to the tab's first screen, as iPhone's own apps;
    //  Haris 2026-11-03. On its first screen: back to the top, as before.)
    let again = item.tag == shownTab
    shownTab = item.tag
    lastTabTap = (tabKeys[item.tag], Date())
    if again, tabKeys[item.tag] == "projects", clientsWanted, clientsBackToList() { return }
    // (the Clients list over Me: Me again — back to Me; another tab — it goes, as Me's pages do)
    if clientsListIfMade?.backFromMe == true {
      if tabKeys[item.tag] == "me" { clientsBackToMe(); return }
      if clientPageIfMade?.isHidden == false { clientPageIfMade?.isHidden = true }
      clientsCommand(["show": false])
    }
    // (offline — the website not there: the app's own lists from its copy; the page told the tab once it's there)
    if !again, offlineTab(tabKeys[item.tag]) {
      earlyJS.removeAll { $0.hasPrefix("window.__e11Tab ") }
      pageJSSoon("window.__e11Tab && window.__e11Tab(\(jsonString([tabKeys[item.tag]]).dropFirst().dropLast()))")
      return
    }
    // (Me, the app's own: again from a page under it — back to Me with the back slide; on Me — to the top)
    // (Content plans, a Social's own tab, is the same app's own pages — Haris 2026-11-04)
    // (the tab the app's own Me pages are showing now — Me, Content plans, an Office Admin's Overview / Team; another of
    //  them: hidden, and the page sends that one's first page — Me showed Overview, Haris 2026-11-04)
    let meLike = tabKeys[item.tag] == meCtl.tab
    if again, meLike, meCtl.isOpen { if meCtl.depth > 1 { meCtl.backToRoot() } else { meCtl.top?.scrollToTop() }; return }
    // (another tab: the app's own Me goes at once for the app's own tabs; back on Me, it's there at once as it was)
    if meLike { if !meCtl.screens.isEmpty, pageReady { meCtl.reveal() } }
    // (another of the app's own Me-made tabs — an Office Admin's Overview / Claims / Expenses / Team / Me, Social's Plans:
    //  the screen on now stays until the page sends the other one's first page, so the website's Home ("E11 Day") never
    //  shows in between — Haris 2026-11-04; at most 1.5 s)
    else if meServes(tabKeys[item.tag]), meCtl.isOpen {
      let key = tabKeys[item.tag]
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        guard let self = self, self.selectedTabKey == key, self.meCtl.tab != key else { return }
        self.meCtl.hide()
      }
    }
    else if ["today", "mytasks", "inbox", "projects", "me", "plans", "team", "clients", "fin-reimb", "fin-expenses", "reviews"].contains(tabKeys[item.tag]) { meCtl.hide() }   // (Me ↔ Content plans: the page then sends the other one's first page)
    // (the page's own tabs — Me, Plans, Reviews, Client Assets: from a deeper page, back to the tab's first with the back
    //  slide; Haris 2026-11-03)
    let key = tabKeys[item.tag]
    if again, !["today", "mytasks", "inbox", "projects"].contains(key), pageReady {
      web.evaluateJavaScript("window.__e11TabDeep ? window.__e11TabDeep(\(jsonString([key]).dropFirst().dropLast())) : false") { [weak self] r, _ in
        guard let self = self else { return }
        if (r as? Bool) == true || self.assetsCtl.isOpen { self.tabBackSlide(key) }
        else { self.pageJSSoon("window.__e11Tab && window.__e11Tab(\(jsonString([key]).dropFirst().dropLast()))") }
      }
      return
    }
    // (23+: Home is the app's own — another tab: it goes at once; Home again while on it: back to the top)
    // (the page's own Home must never show in between — Haris, 2026-10-31: leaving Home, it stays until the page has
    //  drawn the other tab and says so (show: false), at most 1.2 s; coming back, it's there at once with what it had,
    //  and the page brings it up to date)
    if let h = homeIfMade {
      if tabKeys[item.tag] == "today" {
        if !h.isHidden { h.scrollToTop() } else if homeHadModel { h.isHidden = false }
      } else if !h.isHidden {
        h.endEditing(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
          guard let self = self, self.pageReady, let sel = self.tabBar.selectedItem, sel.tag < self.tabKeys.count, self.tabKeys[sel.tag] != "today" else { return }
          self.homeIfMade?.isHidden = true
        }
      }
    }
    // (the Inbox, 28+: the same)
    if let h = inboxIfMade {
      if tabKeys[item.tag] == "inbox" {
        if !h.isHidden { h.scrollToTop() } else if inboxHadModel, serverInbox.on, (serverInbox.shown?["me"] as? String) == inboxPageMe { h.isHidden = false }
      } else if !h.isHidden {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
          guard let self = self, let sel = self.tabBar.selectedItem, sel.tag < self.tabKeys.count, self.tabKeys[sel.tag] != "inbox" else { return }
          self.inboxIfMade?.isHidden = true
        }
      }
    }
    // (My Tasks, 26+: the same — kept until the page has drawn the other tab; again while on it: back to the top)
    if let h = myTasksIfMade {
      if tabKeys[item.tag] == "mytasks" {
        if !h.isHidden { h.scrollToTop() } else if myTasksHadModel, serverMyTasks.on, (serverMyTasks.shown?["me"] as? String) == myTasksPageMe { h.isHidden = false }
      } else if !h.isHidden {
        h.endEditing(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
          guard let self = self, let sel = self.tabBar.selectedItem, sel.tag < self.tabKeys.count, self.tabKeys[sel.tag] != "mytasks" else { return }
          self.myTasksIfMade?.isHidden = true
        }
      }
    }
    // (a quick start, the website not there yet: only the last tab asked for goes, once it is)
    if !pageReady && quickBooted { earlyJS.removeAll { $0.hasPrefix("window.__e11Tab ") } }
    pageJSSoon("window.__e11Tab && window.__e11Tab(\(jsonString([tabKeys[item.tag]]).dropFirst().dropLast()))")
  }
  /* ---------- Home (23+): the app's own, under the tab bar; the page says what's on it (NativeHome in phone.js) ---------- */
  var homeIfMade: HomeView?
  // (who the page says you are: someone else than the app's own copy is for — View as…, Back to me, signed in as
  //  another — the copy for them, at once; until it's in, each screen asks the server. The lists stayed blank: they were
  //  worked out from the last person's copy, so they never matched who the page said — Haris 2026-11-04)
  func pageIs(_ me: String?) {
    guard let me = me, !me.isEmpty, let had = AppData.shared.me, had != me || !AppData.shared.isStarted else { return }
    AppData.shared.start(me: me, cookies: serverHome.cookies)
  }
  // (light / dark changed while the app is open — View as… someone with another look, Me › Appearance: every native
  //  screen drawn again in it at once, the hidden ones too, so none waits for the page or a restart — Haris 2026-11-04)
  func relight(_ light: Bool) {
    if let l = homeLook as? [String: Any], (l["light"] as? Bool) != light { homeLook = nil }
    let look: Any = homeLook ?? ["light": light]
    myTasksLight = light; inboxLight = light; clientsLight = light
    for h in view.subviews.compactMap({ $0 as? HomeView }) where !h.model.isEmpty && !h.isAssetsScreen {
      var mm = h.model; mm["look"] = look; h.update(mm)
    }
    meCtl.relight(light); assetsCtl.relight(light)
    ViewAsBar.current?.look(dark: !light)
  }
  var homeHadModel = false
  lazy var homeView: HomeView = {
    let h = HomeView(frame: view.bounds)
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.onEvent = { [weak self] ev in
      if self?.homeEventOnServer(ev) == true { return }
      if self?.pagelessEvent(ev) == true { return }   // (step 9: without the website, or its copy link)
      // (a task opening: Home goes at once, so the task slides in over the page's own Home, scrolled the same)
      // (a task opening: Home only goes if the website's own task page is the one coming — the app's own slides over it;
      //  hiding at once and showing again as the app's page came made Home flash blank, Haris 2026-11-02)
      // (a quick start, the website not there yet: the app's own task page at once)
      if let self = self, !self.pageReady, self.quickBooted, (ev["ev"] as? String) == "open", let id = ev["id"] as? String, !id.isEmpty, AppData.shared.ready {
        self.openTaskPage(id, tab: "details", focus: ""); return
      }
      if (ev["ev"] as? String) == "open" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in if self?.taskPages.isEmpty == true { self?.homeIfMade?.isHidden = true } } }
      self?.pageJSSoon("window.__e11Home && window.__e11Home(\(jsonString(ev)))")
    }
    h.present = { [weak self] vc in self?.topMost().present(vc, animated: true) }
    view.insertSubview(h, belowSubview: tabBar)
    homeIfMade = h
    return h
  }()
  /* the top of the tab bar as it's seen: iOS 26's floating bar is a pill inside a taller UITabBar view, so the view's
     own top is well above it (the + and the toasts sat ~35 pt too high — Haris, 2026-10-31). The pill: 61 tall, its
     bottom 11 pt into the home-indicator room (8 from the edge on a phone without one). */
  /* ---------- the pop-ups as the app's own (shell 34, Popups.swift — Haris 2026-11-03): the page says when and what
     (NativePop in app.js); the answer goes back to it ---------- */
  func popCommand(_ a: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    let dark = statusStyle != .darkContent
    let person = a["person"] as? [String: Any] ?? a["from"] as? [String: Any] ?? [:]
    let pIni = person["ini"] as? String ?? "", pCol = UIColor(hex: person["color"] as? String ?? "") ?? .systemIndigo, pPhoto = person["photo"] as? String
    var once = false
    let reply: ([String: Any]) -> Void = { r in if !once { once = true; done(r) } }
    switch a["kind"] as? String ?? "" {
    case "announce":
      let s = AnnouncementSheet(dark: dark, title: a["title"] as? String ?? "", body: a["body"] as? String ?? "", ask: a["ask"] as? String ?? "",
                                from: a["fromName"] as? String ?? "E11", fromIni: pIni, fromColor: pCol, when: a["when"] as? String ?? "", fromPhoto: pPhoto)
      s.onGone = { reply(["ok": true]) }
      s.show(from: topMost())
    case "claims":
      let s = ClaimsSheet(dark: dark, month: a["month"] as? String ?? "", today: a["today"] as? Int ?? 23)
      s.onAnswer = { x in reply(["a": x]) }
      s.onGone = { reply(["a": "tomorrow"]) }   // (pulled down: closed for today)
      s.show(from: topMost())
    case "greet":
      let show: (UIView) -> Void = { [weak self] top in
        guard let self = self else { return reply(["ok": false]) }
        let g = GreetingView(dark: dark, top: top, title: a["title"] as? String ?? "", sub: a["sub"] as? String ?? "")
        g.onGone = { reply(["ok": true]) }
        g.show(in: self.view.window ?? self.view)
      }
      // (its picture first — your photo or the occasion's — at most a moment's wait, else your initials / the tile)
      var shown = false
      let fallback: () -> UIView = { a["pic"] != nil ? GreetingView.occasionTile("🎉") : GreetingView.photoRing(roundPic(nil, initials: pIni, color: pCol, size: 112)) }
      let path = (a["pic"] as? String).map { "/" + $0 } ?? pPhoto
      if let p = path {
        FeedLoader.shared.image(p) { img in
          DispatchQueue.main.async {
            guard !shown else { return }; shown = true
            show(img.map { a["pic"] != nil ? GreetingView.picTile($0) : GreetingView.photoRing($0) } ?? fallback())
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { guard !shown else { return }; shown = true; show(fallback()) }
      } else { show(fallback()) }
    case "profileAsk":
      let c = ProfileAskCard(dark: dark, missing: a["missing"] as? String ?? "both")
      c.onProfile = { [weak self] in self?.openMePage("profile") }
      c.show(in: view, bottom: tabBar.isHidden ? view.bounds.height - view.safeAreaInsets.bottom : tabPillTop)
      reply(["ok": true])
    case "whatsNew":
      let secs = ((a["sections"] as? [[String: Any]]) ?? []).map { ($0["h"] as? String ?? "", ($0["items"] as? [String]) ?? []) }
      let s = WhatsNewSheet(dark: dark, version: a["version"] as? String ?? "", when: a["when"] as? String ?? "", sections: secs)
      s.onAllNotes = { [weak self] in self?.openMePage("about") }
      s.onGone = { reply(["ok": true]) }
      s.show(from: topMost())
    case "viewAs":
      let ppl: [ViewAsSheet.Person] = ((a["people"] as? [[String: Any]]) ?? []).compactMap { p in
        guard let id = p["id"] as? String else { return nil }
        return .init(id: id, name: p["name"] as? String ?? "", role: p["role"] as? String ?? "", ini: p["ini"] as? String ?? "", color: UIColor(hex: p["color"] as? String ?? "") ?? .systemGray, photo: p["photo"] as? String)
      }
      let s = ViewAsSheet(dark: dark, people: ppl, viewing: a["viewing"] as? String)
      s.closesOnPick = true
      s.onPick = { id in reply(id.map { ["id": $0] } ?? ["me": true]) }
      s.onClose = { reply([:]) }
      s.show(from: topMost())
    case "viewAsBar":
      if (a["on"] as? Bool) != true { ViewAsBar.current?.go(); return reply(["ok": true]) }
      let bar = ViewAsBar.current ?? ViewAsBar(dark: dark)
      bar.look(dark: appStyle == .dark)
      if let ph = a["photos"] as? [String] { ViewAsSheet.warm(ph) }
      bar.set(name: a["name"] as? String ?? "", role: a["role"] as? String ?? "")
      bar.bottomFor = { [weak self] in self?.viewAsBottom() ?? 0 }
      bar.onSwitch = { [weak self] in self?.meCtl.viewAsPick() }
      bar.onBackToMe = { [weak self] in self?.meCtl.viewAsSet(nil) }
      if bar.superview == nil { bar.show(in: view) }
      reply(["ok": true])
    default: reply(["ok": false])
    }
  }
  // (the tabs the app's own Me screens draw: Me, Plans, an Office Admin's Overview, Team, Claims, Expenses)
  func meServes(_ key: String) -> Bool {
    if ["me", "plans", "team", "fin-reimb", "fin-expenses", "reviews"].contains(key) { return true }
    return key == "today" && (tabKeys.contains("fin-reimb") || tabKeys.contains("team"))
  }
  // (a tab as if tapped — your photo on a tab's page: the Me tab)
  // View as… switched: the screens on show belong to the person before — all put away (the page starts again and sends
  // the new person's tabs and first page)
  func putAwayForSwitch() {
    for p in taskPages { closeTaskPage(p, animated: false) }
    if assetsCtl.isOpen { assetsCtl.close(animated: false) }
    meCtl.hide()
    [myTasksIfMade, inboxIfMade, clientsListIfMade, clientPageIfMade].forEach { $0?.isHidden = true }
    homeIfMade?.isHidden = true
    AppData.shared.suspend()
    serverHome.forget(); [serverMyTasksIfMade, serverInboxIfMade, serverClientsIfMade].forEach { $0?.forget() }
  }
  func selectTab(_ key: String) {
    if let i = tabKeys.firstIndex(of: key), let item = self.tabBar.items?.first(where: { $0.tag == i }) { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) }
  }
  // a page of Me from elsewhere: Me's tab, then that page
  func openMePage(_ kind: String) {
    meCtl.openSoon(kind)
    if selectedTabKey != "me", let i = tabKeys.firstIndex(of: "me"), let item = self.tabBar.items?.first(where: { $0.tag == i }) { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) }
  }
  // (the View as… bar's lower edge: above the comment box, else above the tab bar, else at the bottom edge)
  func viewAsBottom() -> CGFloat {
    if let b = cbarIfMade, !b.isHidden, b.alpha > 0.01 { return b.frame.minY - 8 }
    if tabBar.isHidden || !taskPages.isEmpty { return view.bounds.height - max(view.safeAreaInsets.bottom, 12) - 2 }
    return tabPillTop - 10
  }
  var tabPillTop: CGFloat {
    let H = view.bounds.height, safe = view.safeAreaInsets.bottom
    let pillBottom = H - (safe > 0 ? max(8, safe - 11) : 8)
    if #available(iOS 26.0, *) { return pillBottom - 61 }
    return tabBar.frame.minY
  }
  func homeGeo() -> [String: Any] {
    guard let h = homeIfMade else { return ["shown": false, "made": false] }
    if h.isHidden { return ["shown": false, "made": true] }
    var g = h.geo(); g["shown"] = true; g["server"] = serverHome.on
    return g
  }
  /* ---------- Home straight from the server (25+, ServerHome.swift): its model and its Done / Due / Delete; the page
     still says when Home is on screen (and does the rest) ---------- */
  lazy var serverHome: ServerHome = makeServer("home")
  var serverMyTasksIfMade: ServerHome?
  lazy var serverMyTasks: ServerHome = { let s = self.makeServer("mytasks"); self.serverMyTasksIfMade = s; return s }()
  // the screen a server's things show on (Home's or My Tasks'), when it's up
  func screenOf(_ kind: String) -> HomeView? {
    if kind == "clients" { return screenOf("client") ?? (clientsListIfMade?.isHidden == false ? clientsListIfMade : nil) }
    if kind == "client" { return clientPageIfMade?.isHidden == false && !clientLeaving ? clientPageIfMade : nil }   // (going: the buttons are already the list's)
    let h = kind == "home" ? homeIfMade : kind == "inbox" ? inboxIfMade : myTasksIfMade; return h?.isHidden == false ? h : nil
  }
  var shownScreen: HomeView? { (meCtl.isOpen ? meCtl.shown : nil) ?? (assetsCtl.isOpen ? assetsCtl.shown : nil) ?? screenOf("clients") ?? screenOf("inbox") ?? screenOf("mytasks") ?? screenOf("home") }
  func makeServer(_ kind: String) -> ServerHome {
    let s = ServerHome(kind: kind)
    s.cookies = { [weak self] done in
      guard let store = self?.web?.configuration.websiteDataStore.httpCookieStore else { return done(WidgetShare.signIn()?.cookie ?? "") }
      store.getAllCookies { cs in
        let host = URL(string: serverURL())?.host ?? ""
        let mine = cs.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return host == d || host.hasSuffix("." + d) }
        done(mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
      }
    }
    // (pictures and files are fetched with the same sign-in, from the start — the app's own copy draws a task page at
    //  once, before anything else would have handed it over: the file cards stayed grey)
    if kind == "home" { FeedLoader.shared.cookies = s.cookies }
    s.onModel = { [weak self] m in
      if kind == "home" { self?.drawServerHome(m) } else if kind == "inbox" { self?.drawServerInbox(m) } else if kind == "clients" { self?.drawServerClients(m) } else { self?.drawServerMyTasks(m) }
      // (the app's own copy of the data — iOS app data plan: started once we know who's signed in; until it's ready,
      //  the tasks on screen are fetched ahead as before)
      // (only the first time: who you are after that is the page's to say — pageIs; a screen kept from before must not
      //  switch the copy back to the last person)
      if let self = self, let me = m["me"] as? String { if AppData.shared.me == nil { AppData.shared.start(me: me, cookies: self.serverHome.cookies) }; self.watchCopy() }
      if kind != "inbox", kind != "clients", AppData.shared.ready == false { self?.prefetchTasks(m) }
    }
    // switched off on the server (or no Home for this person): the page's Home again, drawn at once
    // (My Tasks: the page's own list, under it)
    s.onOff = { [weak self] in
      if kind == "home" { self?.pageJS("window.__e11HomeResend && window.__e11HomeResend()") }
      else if kind == "inbox" { self?.inboxIfMade?.isHidden = true; self?.inboxOwn(true) }
      else if kind == "clients" { self?.clientsListIfMade?.isHidden = true; self?.clientPageIfMade?.isHidden = true; self?.clientsOwn(true) }
      else { self?.myTasksIfMade?.isHidden = true; self?.myTasksOwn(true) }
    }
    s.onToast = { [weak self] t, a, run in
      guard let h = self?.screenOf(kind) else { return }
      self?.homeToastRun = run
      h.toast(["t": t, "a": a ?? "", "ms": a != nil ? 6000.0 : 3000.0])
    }
    s.onAsk = { [weak self] _, answer in
      guard let self = self else { return answer(nil) }
      let al = UIAlertController(title: "Did the client approve?", message: "Saved with the final files in Client Assets.", preferredStyle: .actionSheet)
      al.addAction(UIAlertAction(title: "Yes, today", style: .default) { _ in answer("yes") })
      al.addAction(UIAlertAction(title: "Not needed", style: .default) { _ in answer("none") })
      al.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in answer(nil) })
      self.topMost().present(al, animated: true)
    }
    return s
  }
  var homeToastRun: (() -> Void)?
  var homePageMe: String?
  var homeLook: Any?, homePagePeople: [String: [String: Any]] = [:], homeServerPeople: [String: [String: Any]] = [:]
  // the server's Home drawn (with the page's colours), when Home is on screen
  func drawServerHome(_ m: [String: Any]) {
    defer { updateCorner() }
    guard let h = homeIfMade, !h.isHidden else { return }
    var mm = m; mm["show"] = true
    mm["look"] = homeLook ?? ["light": appStyle == .light]
    if let p = m["people"] as? [String: [String: Any]] {
      serverHome.photos(p) { [weak self] got in
        guard let self = self else { return }
        self.homeServerPeople = got
        self.homeIfMade?.people = got.merging(self.homePagePeople, uniquingKeysWith: { s, pg in pg["photo"] != nil || s["photo"] == nil ? pg : s })
      }
    }
    mm["people"] = nil
    h.drawFor(mm)   // (another person's list in it — after View as…: drawn afresh, never animated from theirs)
  }
  // Home's own taps the server does itself (false: the page does it, as before)
  func homeEventOnServer(_ ev: [String: Any]) -> Bool { eventOnServer(ev, serverHome, pageMe: homePageMe) }
  func eventOnServer(_ ev: [String: Any], _ serverHome: ServerHome, pageMe: String?) -> Bool {
    // (only for the person the page shows: right after another sign-in, the page's Home until the server's catches up)
    guard serverHome.on, serverHome.me != nil, serverHome.me == pageMe, let kind = ev["ev"] as? String else { return false }
    let id = ev["id"] as? String ?? ""
    // (the card on this screen — or, for a search result that isn't on it, the card that sent it)
    let card = ((serverHome.shown?["groups"] as? [[String: Any]]) ?? []).flatMap { $0["cards"] as? [[String: Any]] ?? [] }.first { ($0["id"] as? String) == id } ?? (ev["card"] as? [String: Any])
    switch kind {
    // (Part B step 6: search and New task — the app's own)
    case "find": return searchNative(ev["q"] as? String ?? "")
    case "add": return newTaskNative(view: serverHome.kind == "clients" ? "project" : serverHome.kind == "home" ? "home" : serverHome.kind, project: serverHome.kind == "clients" ? clientsShownId : nil)
    case "toast":
      guard let run = homeToastRun else { return false }
      homeToastRun = nil; run(); return true
    case "done":
      guard let c = card else { return true }
      if (ev["done"] as? Bool) == false { serverHome.act("reopen", id); return true }
      if (c["doneReady"] as? Bool) != true { if let why = c["why"] as? String, !why.isEmpty { serverHome.onToast?(why, nil, nil) }; return true }
      serverHome.act("done", id)
      return true
    case "due":
      guard let c = card else { return true }
      let due = c["due"] as? String ?? ""
      // the date sheet the task page uses (Today / Clear; closed any other way: nothing changes)
      guard let host = sheetHost() else { return true }
      host.present(DateSheetVC(["value": due, "min": "", "max": "", "clearable": !due.isEmpty, "md": false], dark: statusStyle != .darkContent) { r in
        if (r["cancel"] as? Bool) == true || (r["ok"] as? Bool) == false { return }
        let v = (r["clear"] as? Bool) == true ? "" : (r["date"] as? String ?? "")
        if v == due { return }
        serverHome.act("due", id, due: v.isEmpty ? nil : v)
      }, animated: true)
      return true
    case "delete":
      serverHome.act("delete", id); return true
    default: return false
    }
  }
  func homeCommand(_ a: [String: Any]) {
    defer { updateCorner() }
    if let p = a["people"] as? [String: [String: Any]] {
      homePagePeople = p
      homeView.people = serverHome.on ? homeServerPeople.merging(p, uniquingKeysWith: { s, pg in pg["photo"] != nil || s["photo"] == nil ? pg : s }) : p
      myTasksIfMade?.people = myTasksServerPeople.merging(p, uniquingKeysWith: { s, pg in pg["photo"] != nil || s["photo"] == nil ? pg : s })
      return
    }
    if let t = a["toast"] as? [String: Any] { homeToastRun = nil; shownScreen?.toast(t); return }   // (its button is the page's)
    if let r = a["search"] as? [String: Any] { (shownScreen ?? homeIfMade)?.searchResults(r); return }
    guard let show = a["show"] as? Bool else { return }
    if !show { homeIfMade?.endEditing(true); homeIfMade?.isHidden = true; return }
    let h = homeView
    h.bottomRoom = (tabBar.isHidden ? 40 : view.bounds.height - tabBar.frame.minY) + 96
    h.tabTop = tabBar.isHidden ? nil : tabPillTop
    homeLook = a["look"]
    homePageMe = a["me"] as? String
    pageIs(a["me"] as? String)
    if let me = homePageMe { saveQuick(["me": me, "look": homeLook ?? NSNull()]) }
    // (the server's Home when it's on — the page's model is only a sign something changed: the server asked again)
    if serverHome.on, let m = serverHome.shown, (m["me"] as? String) == (a["me"] as? String) {
      h.isHidden = false
      drawServerHome(m)
    } else { h.update(a) }
    homeHadModel = true
    h.isHidden = false
    serverHome.refresh()
  }

  /* ---------- My Tasks (26+): Home's screen as a list (HomeView.isList), straight from the server (/api/mytasks with the
     page's filters); the page says when it's on screen, its tab and filters (NativeMyTasks in phone.js) and does the
     filter sheets; Done / Due / Delete as on Home ---------- */
  var myTasksIfMade: HomeView?
  var myTasksHadModel = false, myTasksPageMe: String?, myTasksLight = true
  var myTasksServerPeople: [String: [String: Any]] = [:]
  lazy var myTasksView: HomeView = {
    let h = HomeView(frame: view.bounds)
    h.isList = true
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.onEvent = { [weak self] ev in
      guard let self = self else { return }
      if self.eventOnServer(ev, self.serverMyTasks, pageMe: self.myTasksPageMe) { return }
      if self.myTasksFilterEvent(ev) { return }   // (Part B step 6: the filters are the app's own)
      if self.pagelessEvent(ev) { return }   // (step 9)
      if (ev["ev"] as? String) == "open" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in if self?.taskPages.isEmpty == true { self?.myTasksIfMade?.isHidden = true } } }
      self.pageJS("window.__e11MyTasks && window.__e11MyTasks(\(jsonString(ev)))")
    }
    h.present = { [weak self] vc in self?.topMost().present(vc, animated: true) }
    view.insertSubview(h, belowSubview: tabBar)
    myTasksIfMade = h
    return h
  }()
  func drawServerMyTasks(_ m: [String: Any]) {
    defer { updateCorner() }
    guard let h = myTasksIfMade, myTasksPageMe != nil, (m["me"] as? String) == myTasksPageMe else { return }
    var mm = m; mm["show"] = true
    // (Home's colours from the page when they're for the same light / dark)
    if let l = homeLook as? [String: Any], (l["light"] as? Bool) == myTasksLight { mm["look"] = l } else { mm["look"] = ["light": myTasksLight] }
    if let p = m["people"] as? [String: [String: Any]] {
      serverMyTasks.photos(p) { [weak self] got in
        guard let self = self else { return }
        self.myTasksServerPeople = got
        self.myTasksIfMade?.people = got.merging(self.homePagePeople, uniquingKeysWith: { s, pg in pg["photo"] != nil || s["photo"] == nil ? pg : s })
      }
    }
    mm["people"] = nil
    h.drawFor(mm)   // (another person's list in it — after View as…: drawn afresh, never animated from theirs)
    myTasksHadModel = true
    // (shown once there's a list for these filters — until then the page's own, under it)
    if myTasksWanted && h.isHidden { h.isHidden = false; myTasksOwn(false) }
  }
  // (the page draws nothing under the app's My Tasks; when the app can't show it, the page's own list instead)
  var myTasksPageOwn = false
  func myTasksOwn(_ v: Bool) {
    guard v != myTasksPageOwn else { return }
    myTasksPageOwn = v
    pageJS("window.__e11MyTasksOwn && window.__e11MyTasksOwn(\(v))")
  }
  var myTasksWanted = false
  var myTasksPageSignal: [String: Any]?   // (the page's last "My Tasks shows" — who, light / dark)
  // (My Tasks' actions still waiting from before the app was closed go even if My Tasks isn't opened)
  func myTasksWaiting() -> ServerHome? { serverMyTasksIfMade ?? (defaults.data(forKey: "e11HomeQueue-mytasks").map { $0.count > 2 } == true ? serverMyTasks : nil) }
  func myTasksCommand(_ a0: [String: Any]) {
    defer { updateCorner() }
    guard let show = a0["show"] as? Bool else { return }
    if show { myTasksPageSignal = a0 }
    // (Part B step 6: the tab, the filters, their buttons and chips — the app's own, kept for this person; the page only
    //  says when My Tasks shows)
    var a = a0
    if show, let sig = myTasksOwnSignal(me: a0["me"] as? String) { for k in ["tab", "q", "buttons", "chips"] { a[k] = sig[k] } }
    if !show { myTasksWanted = false; myTasksIfMade?.endEditing(true); myTasksIfMade?.isHidden = true; return }
    let h = myTasksView
    myTasksWanted = true
    h.bottomRoom = (tabBar.isHidden ? 40 : view.bounds.height - tabBar.frame.minY) + 96
    h.tabTop = tabBar.isHidden ? nil : tabPillTop
    myTasksPageMe = a["me"] as? String
    pageIs(a["me"] as? String)
    myTasksLight = (a["light"] as? Bool) ?? (appStyle == .light)
    let s = serverMyTasks
    s.query = "tab=" + ((a["tab"] as? String) == "done" ? "done" : "all") + ((a["q"] as? String).map { $0.isEmpty ? "" : "&" + $0 } ?? "")
    h.setFilters(a)
    // (no list yet for this tab and these filters: the page's own shows until the server's comes — never the old one
    //  under the new filters)
    if s.on, let m = s.shown { drawServerMyTasks(m) } else {
      h.isHidden = true
      // (no list in a moment — no signal, or switched off: the page's own)
      let q = s.query
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        guard let self = self, self.myTasksWanted, self.serverMyTasks.query == q, self.myTasksIfMade?.isHidden == true else { return }
        self.myTasksOwn(true)
      }
    }
    s.refresh()
  }

  /* ---------- the Inbox (28+): Home's screen with Mail's rows (HomeView.isInbox), straight from the server (/api/inbox);
     the page says when it's on screen (NativeInbox in phone.js) and opens what's tapped; read / unread / all read go to
     the server from here (kept on the phone until sent) ---------- */
  var inboxIfMade: HomeView?
  var inboxHadModel = false, inboxPageMe: String?, inboxLight = true, inboxWanted = false, inboxPageOwn = false
  var serverInboxIfMade: ServerHome?
  lazy var serverInbox: ServerHome = { let s = self.makeServer("inbox"); s.query = "tab=all"; self.serverInboxIfMade = s; return s }()
  func inboxWaiting() -> ServerHome? { serverInboxIfMade ?? (defaults.data(forKey: "e11HomeQueue-inbox").map { $0.count > 2 } == true ? serverInbox : nil) }
  lazy var inboxView: HomeView = {
    let h = HomeView(frame: view.bounds)
    h.isInbox = true
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.onEvent = { [weak self] ev in
      guard let self = self else { return }
      let s = self.serverInbox
      switch ev["ev"] as? String ?? "" {
      case "tab":
        break   // (Unread and Mentions are picked from all of them in the app itself — at once, no asking)
      case "read", "unread":
        if s.on, s.me == self.inboxPageMe, let id = ev["id"] as? String { s.act(ev["ev"] as! String, id) }
      case "readAll":
        if s.on, s.me == self.inboxPageMe { s.act("readAll", "") } else { self.pageJS("window.__e11Inbox && window.__e11Inbox({ev:'readAll'})") }
      case "unreadList":
        let ids = (ev["ids"] as? [String]) ?? []
        if s.on, s.me == self.inboxPageMe, !ids.isEmpty { s.act("unreadList", ids.joined(separator: ",")) }
      case "open" where (ev["id"] as? String).map({ self.openNotifNative($0, hint: [:]) }) == true:
        break   // (Part B step 7: the app's own — the brain says where, the app's screens open it)
      default:
        // (not hidden here: the page hides it the moment what's tapped opens a page — a round-up or a sheet opens over
        //  the Inbox, which stays; hiding it first flashed the page behind — Haris, 2026-11-01)
        self.pageJS("window.__e11Inbox && window.__e11Inbox(\(jsonString(ev)))")
      }
    }
    h.present = { [weak self] vc in self?.topMost().present(vc, animated: true) }
    view.insertSubview(h, belowSubview: tabBar)
    inboxIfMade = h
    return h
  }()
  func drawServerInbox(_ m: [String: Any]) {
    defer { updateCorner() }
    guard let h = inboxIfMade, inboxPageMe != nil, (m["me"] as? String) == inboxPageMe else { return }
    var mm = m; mm["show"] = true
    if let l = homeLook as? [String: Any], (l["light"] as? Bool) == inboxLight { mm["look"] = l } else { mm["look"] = ["light": inboxLight] }
    if let p = m["people"] as? [String: [String: Any]] {
      serverInbox.photos(p) { [weak self] got in
        guard let self = self else { return }
        self.inboxIfMade?.people = got.merging(self.homePagePeople, uniquingKeysWith: { s, pg in pg["photo"] != nil || s["photo"] == nil ? pg : s })
      }
    }
    mm["people"] = nil
    h.drawFor(mm)   // (another person's list in it — after View as…: drawn afresh, never animated from theirs)
    inboxHadModel = true
    if inboxWanted && h.isHidden { h.isHidden = false; inboxOwn(false) }
  }
  func inboxOwn(_ v: Bool) {
    guard v != inboxPageOwn else { return }
    inboxPageOwn = v
    pageJS("window.__e11InboxOwn && window.__e11InboxOwn(\(v))")
  }
  func inboxCommand(_ a: [String: Any]) {
    defer { updateCorner() }
    guard let show = a["show"] as? Bool else { return }
    if !show { inboxWanted = false; inboxIfMade?.isHidden = true; return }
    let h = inboxView
    inboxWanted = true
    h.bottomRoom = (tabBar.isHidden ? 40 : view.bounds.height - tabBar.frame.minY) + 96
    h.tabTop = tabBar.isHidden ? nil : tabPillTop
    inboxPageMe = a["me"] as? String
    pageIs(a["me"] as? String)
    inboxLight = (a["light"] as? Bool) ?? (appStyle == .light)
    let s = serverInbox
    if s.on, let m = s.shown { drawServerInbox(m) } else {
      h.isHidden = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        guard let self = self, self.inboxWanted, self.inboxIfMade?.isHidden == true else { return }
        self.inboxOwn(true)
      }
    }
    s.refresh()
  }

  /* ---------- the Clients tab (31, Part B — Haris 2026-11-02): Home's screen with the list of clients
     (HomeView.isClients), and a client's page (HomeView.isClient: its Client Assets folders, its tasks by status as Home's
     cards) pushed in over it from the right; both from the app's own copy (/api/clients as the fallback). The page says
     which is on screen (NativeClients in phone.js) and does what's tapped. ---------- */
  var clientsListIfMade: HomeView?, clientPageIfMade: HomeView?
  var shownTab: Int?
  // back to a page tab's first screen as iPhone goes back: a picture of what's on screen slides away to the right while
  // the first screen (drawn by the page under it) comes in from the left
  func tabBackSlide(_ key: String) {
    let W = view.bounds.width
    let top: UIView = assetsCtl.top ?? web
    let snap = top.snapshotView(afterScreenUpdates: false)
    if assetsCtl.isOpen { assetsCtl.close(animated: false) }
    // (back to Me from a page deeper than it — My profile, Client Assets: the app's own Me comes in under the slide)
    let meRoot = key == meCtl.tab ? meCtl.rootUnder() : nil
    if let s = snap { s.frame = top.frame; view.insertSubview(s, belowSubview: tabBar) }
    if let r = meRoot {
      r.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
      UIView.animate(withDuration: 0.36, delay: 0.08, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) { r.transform = .identity }
    }
    pageJS("window.__e11Tab && window.__e11Tab(\(jsonString([key]).dropFirst().dropLast()))")
    web.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    updateCorner()
    // (a moment for the page to draw its first screen, then the slide)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
      UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        snap?.transform = CGAffineTransform(translationX: W, y: 0); self.web.transform = .identity
      } completion: { _ in snap?.removeFromSuperview(); self.web.transform = .identity }
    }
  }
  // the Clients tab tapped again from a client's page or Client Assets: what's on top slides away to the right, the list
  // comes back under it; everything between goes at once (false: already on the list)
  func clientsBackToList() -> Bool {
    guard let l = clientsListIfMade else { return false }
    let page = clientPageIfMade.flatMap { $0.isHidden ? nil : $0 }
    guard let top: UIView = assetsCtl.top ?? page else { if !l.isHidden { l.scrollToTop() }; return true }
    let W = view.bounds.width
    let snap = top.snapshotView(afterScreenUpdates: false)
    if let s = snap { s.frame = top.frame; view.insertSubview(s, belowSubview: tabBar) }
    assetsCtl.close(animated: false)
    if let p = clientPageIfMade, !p.isHidden { p.isHidden = true; p.transform = .identity }
    let wasPage = clientsOn == "client"
    clientsOn = "list"
    l.isHidden = false; l.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    edgePanOn(); updateCorner()
    UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      snap?.transform = CGAffineTransform(translationX: W, y: 0); l.transform = .identity
    } completion: { _ in snap?.removeFromSuperview() }
    if wasPage { pageJS("window.__e11Clients && window.__e11Clients({ev:'list'})") }
    return true
  }
  lazy var assetsCtl = AssetsCtl(self)   // (Client Assets, the app's own — Assets.swift, shell 32)
  lazy var meCtl = MeCtl(self)   // (the Me tab, the app's own — Me.swift, shell 33)
  var selectedTabKey: String { tabBar.selectedItem.map { tabKeys.indices.contains($0.tag) ? tabKeys[$0.tag] : "" } ?? "" }
  var clientsWanted = false, clientsPageMe: String?, clientsLight = true, clientsPageOwn = false, clientsOn = "list"
  var serverClientsIfMade: ServerHome?
  lazy var serverClients: ServerHome = { let s = self.makeServer("clients"); s.query = "view=list"; self.serverClientsIfMade = s; return s }()
  private func clientsScreen(_ page: Bool) -> HomeView {
    if page, let h = clientPageIfMade { return h }
    if !page, let h = clientsListIfMade { return h }
    let h = HomeView(frame: view.bounds)
    if page { h.isClient = true } else { h.isClients = true }
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.onEvent = { [weak self] ev in
      guard let self = self else { return }
      // (Done / Due / Delete on a card: as Home's, straight to the server)
      if page, self.eventOnServer(ev, self.serverClients, pageMe: self.clientsPageMe) { return }
      if page, self.pagelessEvent(ev) { return }   // (step 9)
      // (a client held: its sheet, the app's own — nothing for the website)
      if !page, (ev["ev"] as? String) == "clientHold", let id = ev["id"] as? String { self.clientSheet(id); return }
      if !page, (ev["ev"] as? String) == "addClient" { self.addClientSheet(); return }
      if !page, (ev["ev"] as? String) == "back", self.clientsListIfMade?.backFromMe == true { self.clientsBackToMe(); return }
      if page, (ev["ev"] as? String) == "back" { self.clientPageOut() }
      // (a client's Client Assets — a folder, or See all: the app's own screens over its page, shell 32)
      if page, let k = ev["ev"] as? String, k == "folder" || k == "assets", let c = ev["client"] as? String {
        self.assetsCtl.openFromClients(client: c, folder: k == "folder" ? ev["folder"] as? String : nil); return
      }
      // (a client tapped: its page comes in at once, from the copy — the website is only told; waiting for it made the
      //  page slow to come, Haris 2026-11-02)
      if !page, (ev["ev"] as? String) == "client", let id = ev["id"] as? String, AppData.shared.ready, self.serverClients.on {
        self.clientsOn = "client"
        self.serverClients.query = "view=client&id=\(id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")&done=0"
        self.serverClients.refresh()
      }
      self.pageJS("window.__e11Clients && window.__e11Clients(\(jsonString(ev)))")
    }
    h.present = { [weak self] vc in self?.topMost().present(vc, animated: true) }
    if page, let l = clientsListIfMade { view.insertSubview(h, aboveSubview: l) } else { view.insertSubview(h, belowSubview: tabBar) }
    if page { clientPageIfMade = h } else { clientsListIfMade = h }
    return h
  }
  // the Clients list over Me (Me › Work › Clients — the CD has Reviews in its place in the tab bar; Haris 2026-11-05: the
  // app's own list, sliding in over Me, ‹ and the edge swipe back to Me)
  func openClientsFromMe() {
    guard let me = AppData.shared.me ?? homePageMe else { return }
    let l = clientsScreen(false)
    let under = meCtl.top
    l.backFromMe = true
    clientsCommand(["show": true, "view": "list", "me": me, "light": appStyle == .light])
    if let u = under { view.insertSubview(l, aboveSubview: u) }
    let W = view.bounds.width
    l.isHidden = false
    l.transform = CGAffineTransform(translationX: W, y: 0)
    UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      l.transform = .identity; under?.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    } completion: { _ in under?.transform = .identity; if l.backFromMe { self.meCtl.hide() }; self.edgePanOn(); self.updateCorner() }
    updateCorner()
  }
  // ‹ / the edge swipe: back to Me, the list sliding out to the right
  func clientsBackToMe(fromX: CGFloat = 0) {
    guard let l = clientsListIfMade, l.backFromMe else { return }
    let W = view.bounds.width
    meCtl.reveal()
    if let r = meCtl.top { view.insertSubview(l, aboveSubview: r); r.transform = CGAffineTransform(translationX: -W * 0.3 * (1 - fromX / W), y: 0) }
    let r = meCtl.top
    UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      l.transform = CGAffineTransform(translationX: W, y: 0); r?.transform = .identity
    } completion: { _ in l.backFromMe = false; self.clientsCommand(["show": false]); l.transform = .identity; self.edgePanOn(); self.updateCorner() }
    updateCorner()
  }
  // a client's page going (‹, or the list asked for): it slides back out to the right, the list coming back under it
  func clientPageOut() {
    guard let p = clientPageIfMade, !p.isHidden, !clientLeaving else { return }
    clientLeaving = true
    let W = view.bounds.width
    let l = clientUnder()
    if let l = l, clientsWanted || clientFrom != nil {
      if clientFrom != nil { view.insertSubview(l, belowSubview: p); fromTabSelected() }
      l.isHidden = false; l.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
    }
    UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
      p.transform = CGAffineTransform(translationX: W, y: 0); l?.transform = .identity
    } completion: { _ in p.isHidden = true; p.transform = .identity; self.clientLeaving = false; self.edgePanOn(); self.updateCorner() }
    updateCorner()
  }
  var clientLeaving = false
  // (a client's page opened from another tab — Home's search, …: what its ‹ and the edge swipe go back to, as history —
  //  Haris 2026-11-03; nil: the list)
  var clientFrom: String?
  func clientUnder() -> HomeView? {
    guard let f = clientFrom else { return clientsListIfMade }
    return f == "home" || f == "today" ? homeIfMade : f == "mytasks" ? myTasksIfMade : f == "inbox" ? inboxIfMade : nil
  }
  // (that tab lit in the tab bar at once — the page says so too a moment later)
  func fromTabSelected() {
    guard let f = clientFrom else { return }
    let key = f == "home" ? "today" : f
    if let i = tabKeys.firstIndex(of: key), let item = tabBar.items?.first(where: { $0.tag == i }) { tabBar.selectedItem = item }
  }
  // a client's sheet (held in the list): from the list as the copy has it; Admins' changes to the server, into the copy
  func clientSheet(_ id: String) {
    guard let list = serverClients.shown, (list["kind"] as? String) == "clients" else { return }
    let rows = ((list["rows"] as? [[String: Any]]) ?? []) + ((list["inactive"] as? [[String: Any]]) ?? [])
    guard let row = rows.first(where: { ($0["id"] as? String) == id }) else { return }
    let ppl = (clientsListIfMade?.people ?? [:]).merging((list["people"] as? [String: [String: Any]]) ?? [:]) { a, _ in a }
    let inactive = ((list["inactive"] as? [[String: Any]]) ?? []).contains { ($0["id"] as? String) == id }
    let vc = ClientSheetVC(row: row, list: list, people: ppl, dark: !clientsLight, active: !inactive)
    vc.onSave = { [weak self] body, done in
      guard let self = self else { return }
      var b = body; b["act"] = "editClient"; b["id"] = id; b["from"] = "clients"; b["copy"] = true; b["op"] = UUID().uuidString
      self.serverTask.request("/api/home/act", body: b) { j in
        guard let j = j else { return done("No connection — try again") }
        if (j["ok"] as? Bool) != true { return done(j["error"] as? String ?? "That didn’t work — try again") }
        if let ch = j["changes"] as? [[String: Any]] { AppData.shared.applyLocal(ch) }
        done(nil)
        if let m = (j["messages"] as? [String])?.first, m != "Client saved" { self.clientsListIfMade?.toast(["t": m]) }
      }
    }
    let nav = FitNav(rootViewController: vc)
    nav.overrideUserInterfaceStyle = clientsLight ? .light : .dark
    if let sh = nav.sheetPresentationController { sh.prefersGrabberVisible = true }   // (its height: what's on it — FitNav)
    nav.prepare(width: view.bounds.width, bottom: view.safeAreaInsets.bottom)
    topMost().present(nav, animated: true)
  }
  // + Add client (Admins, the Clients list — Haris 2026-11-03): the client sheet as New client; the server makes the
  // client and its Client Assets folder (Logos, Brand Guidelines, Fonts, Files) and links them; an active one's page opens
  func addClientSheet() {
    guard let list = serverClients.shown, (list["kind"] as? String) == "clients", (list["canEdit"] as? Bool) == true else { return }
    let ppl = (clientsListIfMade?.people ?? [:]).merging((list["people"] as? [String: [String: Any]]) ?? [:]) { a, _ in a }
    let vc = ClientSheetVC(row: [:], list: list, people: ppl, dark: !clientsLight, isNew: true, active: true)
    vc.onSave = { [weak self] body, done in
      guard let self = self else { return }
      var b = body; b["act"] = "addClient"; b["from"] = "clients"; b["copy"] = true; b["op"] = UUID().uuidString
      self.serverTask.request("/api/home/act", body: b) { j in
        guard let j = j else { return done("No connection — try again") }
        if (j["ok"] as? Bool) != true { return done(j["error"] as? String ?? "That didn’t work — try again") }
        if let ch = j["changes"] as? [[String: Any]] { AppData.shared.applyLocal(ch) }
        done(nil)
        let msg = (j["messages"] as? [String])?.first
        if (body["active"] as? Bool) != false, let id = j["created"] as? String {
          // (its page slides in, as a tap on it — once the sheet has gone and the page behind has the new client too: it
          //  went half way, stopped and jumped when the page didn't know it yet — Haris 2026-11-03)
          self.whenPageHasClient(id, tries: 30) { [weak self] in
            guard let self = self, let l = self.clientsListIfMade else { return }
            l.onEvent?(["ev": "client", "id": id])
            if let m = msg { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.clientPageIfMade?.toast(["t": m]) } }
          }
        } else if let m = msg { self.serverClients.refresh(); self.clientsListIfMade?.toast(["t": m]) }
      }
    }
    let nav = FitNav(rootViewController: vc)
    nav.overrideUserInterfaceStyle = clientsLight ? .light : .dark
    if let sh = nav.sheetPresentationController { sh.prefersGrabberVisible = true }
    nav.prepare(width: view.bounds.width, bottom: view.safeAreaInsets.bottom)
    topMost().present(nav, animated: true)
  }
  // (the page behind knows this client — asked every 0.1 s, at most `tries` times — and no sheet is up)
  func whenPageHasClient(_ id: String, tries: Int, _ then: @escaping () -> Void) {
    let q = jsonString([id]).dropFirst().dropLast()
    web?.evaluateJavaScript("!!(typeof proj === 'function' && proj(\(q)))") { [weak self] r, _ in
      guard let self = self else { return }
      if (r as? Bool) == true, self.presentedViewController == nil { then(); return }
      if tries <= 0 { if (r as? Bool) == true || self.presentedViewController == nil { then() }; return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.whenPageHasClient(id, tries: tries - 1, then) }
    }
  }
  var clientPanFrom: ((CornerButton.Spot, CornerButton.Spot, CornerButton.Spot), (CornerButton.Spot, CornerButton.Spot, CornerButton.Spot))?
  // (let go part way through the edge swipe: the rest of the way out, from where the finger left it)
  func clientLeavingBySwipe(_ p: HomeView, _ l: HomeView) {
    clientLeaving = true
    let W = view.bounds.width
    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
      p.transform = CGAffineTransform(translationX: W, y: 0); l.transform = .identity
    } completion: { _ in p.isHidden = true; p.transform = .identity; self.clientLeaving = false; self.edgePanOn(); self.updateCorner() }
    updateCorner()
  }
  func drawServerClients(_ m: [String: Any]) {
    defer { updateCorner() }
    guard clientsPageMe != nil, (m["me"] as? String) == clientsPageMe else { return }
    let page = (m["kind"] as? String) == "client"
    // (only what's asked for now: an answer for the list while a client's page is wanted waits)
    if page != (clientsOn == "client") { return }
    let h = clientsScreen(page)
    var mm = m; mm["show"] = true
    if let l = homeLook as? [String: Any], (l["light"] as? Bool) == clientsLight { mm["look"] = l } else { mm["look"] = ["light": clientsLight] }
    if let p = m["people"] as? [String: [String: Any]] {
      serverClients.photos(p) { [weak self, weak h] got in
        guard let self = self else { return }
        h?.people = got.merging(self.homePagePeople, uniquingKeysWith: { s, pg in pg["photo"] != nil || s["photo"] == nil ? pg : s })
      }
    }
    mm["people"] = nil
    h.bottomRoom = (tabBar.isHidden ? 40 : view.bounds.height - tabBar.frame.minY) + 96
    h.tabTop = tabBar.isHidden ? nil : tabPillTop
    h.drawFor(mm)   // (another person's list in it — after View as…: drawn afresh, never animated from theirs)
    if clientsWanted && h.isHidden { reveal(h, page: page); clientsOwn(false) }
  }
  // shown: the list in place; a client's page pushed in from the right over the list (as iPhone's own pages)
  private func reveal(_ h: HomeView, page: Bool) {
    let W = view.bounds.width
    if page, let l = clientsListIfMade, !l.isHidden, view.window != nil {
      h.transform = CGAffineTransform(translationX: W, y: 0); h.isHidden = false
      UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
        h.transform = .identity; l.transform = CGAffineTransform(translationX: -W * 0.3, y: 0)
      } completion: { _ in if !h.isHidden { l.isHidden = true; l.transform = .identity }; self.updateCorner() }
    } else { h.transform = .identity; h.isHidden = false }
    if !page { clientPageIfMade?.isHidden = true }
    edgePanOn()
  }
  func clientsOwn(_ v: Bool) {
    guard v != clientsPageOwn else { return }
    clientsPageOwn = v
    pageJS("window.__e11ClientsOwn && window.__e11ClientsOwn(\(v))")
  }
  func clientsCommand(_ a: [String: Any]) {
    defer { updateCorner() }
    guard let show = a["show"] as? Bool else { return }
    if !show { clientsWanted = false; clientsListIfMade?.backFromMe = false; clientsListIfMade?.isHidden = true; if !clientLeaving { clientPageIfMade?.isHidden = true }; assetsCtl.closeIfFromClients(); edgePanOn(); return }
    if !clientsWanted { clientsListIfMade?.clientsFresh() }   // (the tab coming back: Inactive clients closed again)
    clientsWanted = true
    clientsPageMe = a["me"] as? String
    pageIs(a["me"] as? String)
    clientsLight = (a["light"] as? Bool) ?? (appStyle == .light)
    let page = (a["view"] as? String) == "client"
    let was = clientsOn
    clientsOn = page ? "client" : "list"
    let s = serverClients
    // (back to the list: it's on screen already as it was — brought up to date once the page has gone, not while the
    //  list and the top buttons are moving: working it out then made 🔍 hesitate on the way, Haris 2026-11-02)
    if !page && was == "client" {
      clientPageOut()
      s.query = "view=list"
      clientFrom = nil
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in guard let self = self, self.clientsOn == "list" else { return }; self.serverClients.refresh() }
      return
    }
    if page, !clientLeaving { clientFrom = (a["from"] as? String).flatMap { $0.isEmpty ? nil : $0 } } else if !page { clientFrom = nil }
    s.query = page ? "view=client&id=\((a["id"] as? String ?? "").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")&done=\((a["done"] as? Bool) == true ? 1 : 0)" : "view=list"
    if s.on, let m = s.shown, (m["kind"] as? String) == (page ? "client" : "clients"), !page || (m["id"] as? String) == (a["id"] as? String) { drawServerClients(m) }
    else if (page ? clientPageIfMade : clientsListIfMade)?.isHidden == false {
      // (already on screen: brought up to date below)
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        guard let self = self, self.clientsWanted, (page ? self.clientPageIfMade : self.clientsListIfMade)?.isHidden != false else { return }
        self.clientsOwn(true)
      }
    }
    s.refresh()
  }

  /* ---------- notifications ---------- */
  func pushState(_ done: @escaping (String) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { s in
      let st: String
      switch s.authorizationStatus {
      case .denied: st = "denied"
      case .notDetermined: st = "off"
      default: st = defaults.bool(forKey: PUSH_OFF_KEY) ? "off" : "on"
      }
      DispatchQueue.main.async { done(st) }
    }
  }
  func gotToken(_ hex: String) {
    lastToken = hex
    if pageReady || Main.boot.state == .signedIn { sendToken(hex) } else { pendingToken = hex }
    let w = pushWaiters; pushWaiters = []
    w.forEach { $0(["ok": true, "state": "on"]) }
  }
  func tokenFailed(_ msg: String) {
    let w = pushWaiters; pushWaiters = []
    w.forEach { $0(["ok": false, "error": "Notifications failed: " + msg]) }
  }
  func sendToken(_ hex: String) {
    // (the Notification Service Extension confirms each notification with this address — ack: the server sends again
    //  the ones that didn't arrive)
    WidgetShare.write("apnsToken", Data(hex.utf8))
    // (straight to the server — Part B step 7; the page only if that didn't work)
    let body: [String: Any] = ["token": hex, "env": APNS_ENV, "ack": true, "platform": "ios"]
    serverTask.request("/api/apns/register", body: body) { [weak self] j in
      if (j?["ok"] as? Bool) != true { self?.pageJS(self?.waitForApp("window.__e11ApnsToken && window.__e11ApnsToken(\(jsonString(body)))") ?? "") }
    }
  }
  // run something once the web app has its data (it may still be starting when the app opens from a notification)
  func waitForApp(_ js: String) -> String {
    "(function f(n){ if ((typeof db !== 'undefined' && db) && typeof currentUserId !== 'undefined' && currentUserId) { \(js) } else if (n < 80) setTimeout(function(){ f(n+1) }, 250); })(0)"
  }
  func openPush(_ userInfo: [AnyHashable: Any]) {
    let d = userInfo["e11"] as? [String: Any] ?? [:]
    // (Part B step 7: the app's own — where it goes and what's marked read from the copy; a view (the widget): its tab)
    if let v = d["view"] as? String, AppData.shared.ready { if tabKeys.contains(v) { selectTab(v); return } }
    else if d["view"] == nil, openNotifNative(d["nid"] as? String, hint: d) { return }
    if pageReady { pageJS(waitForApp("window.__e11PushTap && window.__e11PushTap(\(jsonString(d)))")) } else { pendingPush = d; if Main.noPage, !(AppData.shared.ready && quickBooted) { pagelessFlush(1) } }
  }
  func flushPending() {
    // (well after the app's own page has started — loading both at once slowed the start)
    if cweb == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.makeCommentsWeb() } }
    if let t = pendingToken { pendingToken = nil; sendToken(t) }
    // (every time the page loads: this phone's address again — the page wasn't told it after a fresh start, so the site
    //  might not have it, and "Send test" couldn't say how this phone did)
    else { pushState { st in if st == "on" { UIApplication.shared.registerForRemoteNotifications() } } }
    if let d = pendingPush { pendingPush = nil; pageJS(waitForApp("window.__e11PushTap && window.__e11PushTap(\(jsonString(d)))")) }
  }

  /* ---------- Face ID lock (optional, Me › Lock with Face ID) ---------- */
  func biometry() -> [String: Any]? {
    let ctx = LAContext(); var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return nil }
    let kind: String
    switch ctx.biometryType { case .touchID: kind = "Touch ID"; case .faceID: kind = "Face ID"; default: kind = "Face ID" }
    return ["kind": kind, "on": defaults.bool(forKey: LOCK_KEY)]
  }
  func becameActive() {
    let away = awayAt.map { Date().timeIntervalSince($0) } ?? 0
    if defaults.bool(forKey: LOCK_KEY), lockView == nil, !authing, launchLock || away > 600 { lock() }
    else if lockView != nil, !authing { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.unlock() } }   // (asked again on coming back)
    launchLock = false
    awayAt = nil
    if pageReady { serverHome.refresh() }   // (Home as it is now; anything still waiting goes)
    if pageReady, myTasksWanted { serverMyTasksIfMade?.refresh() } else if pageReady { myTasksWaiting()?.send() }
    if pageReady, inboxWanted { serverInboxIfMade?.refresh() } else if pageReady { inboxWaiting()?.send() }
    if pageReady, clientsWanted { serverClientsIfMade?.refresh() }
    if pageReady, assetsCtl.isOpen { assetsCtl.refresh() }
    if pageReady, meCtl.isOpen { meCtl.refresh() }
    if pageReady || Main.boot.state == .signedIn { pushState { st in if st == "on" { UIApplication.shared.registerForRemoteNotifications() } } }
  }
  func wentAway() { if !authing { awayAt = Date() }; if pageReady || Main.boot.state == .signedIn { shareSignIn() } }

  /* ---------- the widget (widget/E11Widget.swift) ---------- */
  // it asks the server with this app's own sign-in: the server and its cookies go to the shared Keychain
  func shareSignIn() {
    guard let store = web?.configuration.websiteDataStore.httpCookieStore else { return }
    store.getAllCookies { cookies in WidgetShare.saveSignIn(server: serverURL(), cookies: cookies) }
  }
  // e11console://open?task=<id> | ?plan=<id> | ?view=home|plans|fin-dash — a tap on the widget
  func openLink(_ u: URL) {
    // a task link (files…/t/<id>, Haris 2026-11-04): the task, in the app
    if u.path.range(of: "^/t/[A-Za-z0-9_-]{1,80}/?$", options: .regularExpression) != nil {
      let id = u.path.dropFirst(3).replacingOccurrences(of: "/", with: "")
      openPush(["e11": ["taskId": id]]); return
    }
    // a file link (files.e11hq.com/f/<token>, the test copy's files-test…): the page opens the file where it is
    if let r = u.path.range(of: "^/[fd]/[A-Za-z0-9]{6,16}", options: .regularExpression) {
      let tok = String(String(u.path[r]).dropFirst(3))
      if fileLinkNative(tok) { return }
      pageJSSoon("window.__e11FileLink && window.__e11FileLink(\(jsonString([tok]).dropFirst().dropLast()))")
      return
    }
    // (… or the link page's "Open in E11 Console": e11console://f/<token>)
    if u.scheme?.hasPrefix("e11console") == true, u.host == "f" || u.host == "d",
       let r = u.path.range(of: "^/[A-Za-z0-9]{6,16}", options: .regularExpression) {
      let tok = String(String(u.path[r]).dropFirst())
      if fileLinkNative(tok) { return }
      pageJSSoon("window.__e11FileLink && window.__e11FileLink(\(jsonString([tok]).dropFirst().dropLast()))")
      return
    }
    let q = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let v = { (k: String) in q.first { $0.name == k }?.value }
    var d: [String: Any] = [:]
    if let t = v("task") { d = ["taskId": t] } else if let p = v("plan") { d = ["planId": p, "kind": "plan"] } else if let w = v("view") { d = ["view": w] }
    if d.isEmpty { return }
    openPush(["e11": d])
  }
  func lock() {
    // a plain locked screen in the app's own colours: lock, name, and the button (Face ID is asked straight away)
    let v = UIView(frame: view.bounds)
    v.backgroundColor = BG
    let ic = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)))
    ic.tintColor = UIColor(red: 0.48, green: 0.41, blue: 0.93, alpha: 1)
    let t = UILabel(); t.text = "E11 Console is locked"; t.font = .systemFont(ofSize: 20, weight: .semibold); t.textColor = .white
    let kind = (biometry()?["kind"] as? String) ?? "Face ID"
    var cfg = UIButton.Configuration.filled()
    cfg.title = "Unlock with \(kind)"; cfg.cornerStyle = .capsule
    cfg.baseBackgroundColor = UIColor(red: 0.42, green: 0.34, blue: 0.9, alpha: 1)
    cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22)
    let b = UIButton(configuration: cfg)
    b.addTarget(self, action: #selector(unlock), for: .touchUpInside)
    let st = UIStackView(arrangedSubviews: [ic, t, b]); st.axis = .vertical; st.alignment = .center; st.spacing = 18
    st.setCustomSpacing(30, after: t)
    st.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(st)
    st.centerXAnchor.constraint(equalTo: v.centerXAnchor).isActive = true
    st.centerYAnchor.constraint(equalTo: v.centerYAnchor).isActive = true
    view.addSubview(v)
    lockView = v
    // (Face ID asked by itself — once the app is really active: opening, it isn't yet when this runs, and the ask was
    //  never made; only the button worked — Haris 2026-11-05)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.unlockTry(0) }
  }
  @objc func unlock() { unlockTry(0) }
  // (asked by itself as the app opens: iPhone can turn the first ask away while the app is still coming up — not
  //  interactive yet, or cancelled by the system — and then only the button worked; asked again, up to 3 times —
  //  Haris 2026-11-05. Cancelled by the person: the button, as before.)
  func unlockTry(_ n: Int) {
    if authing || lockView == nil { return }
    if UIApplication.shared.applicationState != .active { if n < 10 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.unlockTry(n + 1) } }; return }
    let ctx = LAContext(); var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return unlocked() }
    authing = true
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock E11 Console") { ok, e in
      DispatchQueue.main.async {
        if ok { self.unlocked() }
        let code = (e as? LAError)?.code
        let again = !ok && n < 12 && (code == .systemCancel || code == .appCancel || code == .notInteractive)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {   // (after the app is active again)
          self.authing = false
          if again, UIApplication.shared.applicationState == .active { self.unlockTry(n + 1) }
        }
      }
    }
  }
  func unlocked() { lockView?.removeFromSuperview(); lockView = nil }

  /* ---------- commands from the page ---------- */
  func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let raw = message.body as? String, let d = raw.data(using: .utf8),
          let msg = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
    let id = msg["id"] ?? NSNull()
    let from = message.webView ?? web
    let reply: ([String: Any]) -> Void = { res in
      from?.evaluateJavaScript("window.__e11NativeReply && window.__e11NativeReply(\(jsonString([id]).dropFirst().dropLast()),\(jsonString(res)))", completionHandler: nil)
    }
    let cmd = msg["cmd"] as? String ?? ""
    // (the comments screen's page: only what comments need — the app's tabs, look, badge and notifications stay the
    //  main page's)
    if from != nil, from === cweb, ["setTabs", "badge", "setAppearance", "pushRegister", "pushEnable", "pushDisable", "notify", "setLock", "pickDate", "formSheet", "formSet", "formClose", "trashSheet", "splash", "home", "mytasks", "inbox", "clients"].contains(cmd) { return reply(["ok": true, "ignored": true]) }
    cmdSource = from
    run(cmd, msg["args"] as? [String: Any] ?? [:], reply)
    cmdSource = nil
  }
  // the screen shown on top of everything now (alerts, the share sheet and file pickers go there)
  func topMost() -> UIViewController {
    var v: UIViewController = self
    while let p = v.presentedViewController, !p.isBeingDismissed { v = p }
    return v
  }
  // where a sheet from the page goes: on the app itself, or on top of an open form / Trash sheet (a tucked draft stays
  // where it is); nil while anything else is up
  func sheetHost() -> UIViewController? {
    var v: UIViewController = self
    while let p = v.presentedViewController {
      if p.isBeingDismissed { return nil }
      if p is FormSheetVC || p is TrashSheetVC || p is PreviewVC { v = p } else { return nil }
    }
    return v
  }
  func run(_ cmd: String, _ a: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    switch cmd {
    case "appInfo":
      var r: [String: Any] = ["ok": true, "shell": SHELL_VERSION, "native": "ios", "server": serverURL(),
                              "version": info["CFBundleShortVersionString"] as? String ?? "1.0", "build": info["CFBundleVersion"] as? String ?? "1"]
      r["faceID"] = biometry() ?? NSNull()
      r["refocus"] = FocusAfterPicker.installed
      done(r)
    case "setTabs": pageTabsIn(a); done(["ok": true])
    case "badge":
      if ownsBadge { ownBadge(); return done(["ok": true]) }   // (the app's own count — step 7)
      let n = (a["n"] as? NSNumber)?.intValue ?? Int(a["n"] as? String ?? "") ?? 0
      UNUserNotificationCenter.current().setBadgeCount(max(0, n)) { _ in }
      done(["ok": true])
    // your own settings on this phone (the look, …): kept by the app too — the page's own storage can lose its last
    // change when the app is closed soon after (Haris, 2026-10-31: dark came back as light on reopening)
    case "prefs":
      let key = "e11_prefs_\(a["id"].map { "\($0)" } ?? "")"
      if let p = a["set"] as? [String: Any] {
        if let d = try? JSONSerialization.data(withJSONObject: p) { defaults.set(d, forKey: key) }
        return done(["ok": true])
      }
      if let d = defaults.data(forKey: key), let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return done(["ok": true, "prefs": p]) }
      done(["ok": true])
    case "setAppearance":
      // (Automatic kept by the app itself — Part B step 1: the setting and the day's sunrise / sunset, for when the page
      //  isn't there to say it's light now)
      if let tm = a["themeMode"] as? String { defaults.set(tm, forKey: "e11_theme_mode") }
      if let r = a["rise"] as? String, let st = a["set"] as? String { defaults.set(r, forKey: "e11_sun_rise"); defaults.set(st, forKey: "e11_sun_set") }
      ownAppearanceWatch()
      statusStyle = (a["mode"] as? String) == "light" ? .darkContent : .lightContent
      defaults.set((a["mode"] as? String) == "light" ? "light" : "dark", forKey: "e11_look")
      setNeedsStatusBarAppearanceUpdate()
      // the tab bar follows the app's own light / dark (not only the phone's): every icon, the open page's too, white
      // in dark and black in light — Haris 2026-10-30 (only the tab bar: the page itself keeps following the phone)
      let style: UIUserInterfaceStyle = (a["mode"] as? String) == "light" ? .light : .dark
      // (everything the app draws itself follows the app's own light / dark, never the phone's — Haris, 2026-10-31:
      //  set on the whole window, so every native screen, sheet, alert, picker and keyboard takes it, now and later)
      let turned = appStyle != style
      appStyle = style; view.window?.overrideUserInterfaceStyle = style
      if turned { relight(style == .light) }
      cbarIfMade?.setLook(light: style == .light)
      taskPages.forEach { $0.light = style == .light }
      if tabBar.overrideUserInterfaceStyle != style || tabBar.tintColor != (style == .dark ? UIColor.white : UIColor.black) {
        tabBar.overrideUserInterfaceStyle = style
        let ink: UIColor = style == .dark ? .white : .black
        tabBar.tintColor = ink
        tabBar.unselectedItemTintColor = ink
        tabBadgeKey = [:]
        redrawTabs()
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.syncBackground() }
      done(["ok": true])
    case "openURL":
      let u = a["url"] as? String ?? ""
      guard u.range(of: "^(https?|mailto|tel):", options: [.regularExpression, .caseInsensitive]) != nil, let url = URL(string: u) else { return done(["ok": false, "error": "Only web links can be opened"]) }
      UIApplication.shared.open(url); done(["ok": true])
    case "haptic":
      // iOS's own taps: a light / medium knock, a tab-switch tick, or success / warning / error
      switch a["kind"] as? String ?? "light" {
      case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      case "selection": UISelectionFeedbackGenerator().selectionChanged()
      case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
      case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
      case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
      // an upload finished: the success tap and a soft two-note sound (uploaded.wav; silent with the ring switch off)
      case "uploaded":
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Main.playUploaded()
      default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }
      done(["ok": true])
    case "nativeSheet":
      // a plain menu from the page as a real iPhone sheet (floating; iOS grows it as it's pulled); replies with the
      // chosen row's index, or -1 when it's closed without a choice
      guard let host = sheetHost() else { return done(["ok": false]) }
      let src = cmdSource
      let vc = NativeSheetVC(a, dark: statusStyle != .darkContent, pick: { [weak self] i in
        (src ?? self?.web)?.evaluateJavaScript("window.__e11SheetPick && window.__e11SheetPick(\(i))", completionHandler: nil)
      }) { i, swatch in
        if i >= 0 { FocusAfterPicker.allow() }   // (a text box the option opens still brings the keyboard)
        var r: [String: Any] = ["ok": true, "index": i]
        if i == -2, let typed = swatch { r["custom"] = typed }   // (a typed entry: "Use …")
        else if let sw = swatch { r["swatch"] = sw }
        done(r)
      }
      host.present(vc, animated: true)
    case "pickDate":
      // a date from the page, picked in a native sheet with iPhone's own calendar: a day tapped → that date;
      // Today / Clear; closed any other way → nothing changes (iPhone's own date box set today when just closed)
      guard let host = sheetHost() else { return done(["ok": false]) }
      host.present(DateSheetVC(a, dark: statusStyle != .darkContent) { r in done(r) }, animated: true)
    case "formSheet":
      // New task / Request amendments as iOS's own sheet with iPhone's own fields; replies when it's closed:
      // closed = submit / cancel / discard (a tucked draft pulled away) / replaced (another form opened instead)
      let key = a["key"] as? String ?? ""
      if let open = FormSheetVC.current, open.isOpen {
        if open.key == key { open.expand(); return done(["ok": true, "already": true]) }   // (its tucked draft, carried on)
        open.finish("replaced") { [weak self] in self?.run(cmd, a, done) }
        return
      }
      guard let host = sheetHost() else { return done(["ok": false]) }
      let vc = FormSheetVC(a, dark: statusStyle != .darkContent, event: { [weak self] ev in
        self?.pageJS("window.__e11Form && window.__e11Form(\(jsonString(ev)))")
      }) { r in done(r) }
      vc.onTuck = { [weak self] t in
        guard let self, self.formTucked != t else { return }
        self.formTucked = t
        self.tabBar.isUserInteractionEnabled = !t
        UIView.animate(withDuration: 0.2) { self.tabBar.alpha = t || self.tabsHidden ? 0 : 1 }
      }
      host.present(vc, animated: true)
    case "commentBar": commentBar(a); done(["ok": true])
    case "preview":
      // the file preview (18+): files with their addresses on the server; fetched with the app's own cookies
      guard !a.isEmpty else { return done(["ok": false]) }
      let src = cmdSource
      PreviewLoad.refreshCookies(web.configuration.websiteDataStore.httpCookieStore) { [weak self] in
        guard let self else { return }
        if self.cbarIfMade?.text.isFirstResponder == true { self.cbarIfMade?.text.resignFirstResponder() }
        let vc = PreviewVC(a, dark: self.statusStyle != .darkContent) { [weak self] ev in (src ?? self?.web)?.evaluateJavaScript("window.__e11Preview && window.__e11Preview(\(jsonString(ev)))", completionHandler: nil) }
        self.previewVC = vc
        self.topMost().present(vc, animated: true)
        done(["ok": true])
      }
    case "previewSet":
      previewVC?.set(a); done(["ok": true])
    case "formSet":
      // what was picked for a field (Client, Assign to), CD review on / off, or a message about what's wrong
      if let f = FormSheetVC.current, f.isOpen, f.key == (a["key"] as? String ?? "") { f.set(a) }
      done(["ok": true])
    case "formClose":
      if let f = FormSheetVC.current, f.isOpen, f.key == (a["key"] as? String ?? "") { f.finish("submit") }
      done(["ok": true])
    case "trashSheet":
      // a task in the Trash, to look at: replies restore / preview (a file) / closed
      guard let host = sheetHost() else { return done(["ok": false]) }
      host.present(TrashSheetVC(a, dark: statusStyle != .darkContent) { r in done(r) }, animated: true)
    case "notify": done(["ok": true])   // (Apple's notifications come from the server)
    case "pushStatus": pushState { done(["ok": true, "state": $0]) }
    case "pushRegister":
      pushState { st in if st == "on" { UIApplication.shared.registerForRemoteNotifications() }; done(["ok": true, "state": st]) }
    case "pushEnable":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { ok, _ in
        DispatchQueue.main.async {
          if !ok { return self.pushState { done(["ok": true, "state": $0 == "on" ? "off" : $0]) } }
          defaults.set(false, forKey: PUSH_OFF_KEY)
          self.pushWaiters.append(done)
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    case "pushDisable":
      defaults.set(true, forKey: PUSH_OFF_KEY)
      done(["ok": true, "token": lastToken ?? NSNull()])
    case "openSettings":
      if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
      done(["ok": true])
    case "setLock":
      let on = (a["on"] as? Bool) == true
      if !on { defaults.set(false, forKey: LOCK_KEY); return done(["ok": true, "on": false]) }
      let ctx = LAContext(); var err: NSError?
      guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return done(["ok": false, "error": "This iPhone has no Face ID or passcode set up"]) }
      authing = true
      ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Lock E11 Console with Face ID") { ok, _ in
        DispatchQueue.main.async {
          if ok { defaults.set(true, forKey: LOCK_KEY) }; done(["ok": true, "on": ok])
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.authing = false }
        }
      }
    case "cmReady": cwebReadyToShow = true; cwebUpdate(); done(["ok": true])
    case "splash": done(splashCommand(a))
    case "home": homeCommand(a); done(["ok": true])
    case "mytasks": myTasksCommand(a); done(["ok": true])
    case "inbox": inboxCommand(a); done(["ok": true])
    case "clients": clientsCommand(a); done(["ok": true])
    case "assets": assetsCtl.command(a); done(["ok": true])
    case "me": meCtl.command(a); done(["ok": true])
    // (33: Copy link from the page — a preview it opened, its own lists: the link put on the clipboard here)
    case "role": Main.isAdmin = (a["admin"] as? Bool) == true; done(["ok": true])   // (Admins turn links off and on)
    case "copyText": UIPasteboard.general.string = a["text"] as? String ?? ""; done(["ok": true])
    case "copyLink":
      let f: [String: Any] = ["file": a["path"] as? String ?? "", "name": a["name"] as? String ?? "File", "id": a["id"] as? String ?? "", "size": a["size"] as? Int ?? 0, "thumb": a["thumb"] as? String ?? ""]
      copyFile(f) { [weak self] t in self?.previewVC?.set(["toast": t]); done(["ok": true, "toast": t]) }
    case "meAsk": meCtl.ask(a) { r in done(r) }
    case "pop": popCommand(a) { r in done(r) }
    case "taskPage": taskPageCommand(a); done(["ok": true])
    case "dailySheet":
      // the morning round-up (DailySheet.swift): what's tapped goes back to the page
      guard let host = sheetHost() else { return done(["ok": false]) }
      host.present(DailySheetVC(a) { [weak self] ev in self?.pageJS("window.__e11Daily && window.__e11Daily(\(jsonString(ev)))") }, animated: true)
      done(["ok": true])
    case "cmEnd": cwebToEnd(animated: (a["animated"] as? Bool) == true); done(["ok": true])
    case "pickFiles": Picker.shared.pick(from: topMost(), single: (a["single"] as? Bool) == true, source: a["source"] as? String) { [weak self] r in done(r); self?.cbarAfterPicker(0) }
    case "readLocalChunk": done(Picker.shared.read(a))
    default: done(["ok": false, "error": "Unknown command " + cmd])
    }
  }

  /* ---------- self-test on the build machine (simulator; E11_SELFTEST=1) ---------- */
  // Writes Documents/selftest.json in stages; the build machine takes a screenshot at each stage
  var selfResult: [String: Any] = [:]
  func writeSelf(_ stage: String) {
    selfResult["stage"] = stage
    selfResult["tabs"] = tabKeys
    selfResult["tabBarShown"] = !tabBar.isHidden
    selfResult["selected"] = tabBar.selectedItem.map { tabKeys.indices.contains($0.tag) ? tabKeys[$0.tag] : "" } ?? ""
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("selftest.json")
    try? Data(jsonString(selfResult).utf8).write(to: url)
  }
  func probe(_ key: String, _ js: String, _ then: @escaping () -> Void) {
    web.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { r in
      switch r {
      case .success(let v): self.selfResult[key] = (try? JSONSerialization.jsonObject(with: Data(((v as? String) ?? "null").utf8), options: [.fragmentsAllowed])) ?? NSNull()
      case .failure(let e): self.selfResult[key] = ["error": e.localizedDescription]
      }
      then()
    }
  }
  // (a native sheet for the self-test, replacing any open one)
  func selfSheet(_ sections: [[String: Any]]) {
    let show = { self.run("nativeSheet", ["sections": sections]) { _ in } }
    if let p = presentedViewController { p.dismiss(animated: false) { show() } } else { show() }
  }
  func pause(_ ms: Int) -> String { "await new Promise((r) => setTimeout(r, \(ms)));" }
  // the comments list as the page sees it: where it's scrolled, whether the latest comment shows, the room kept
  let feedJS = "const f = document.querySelector('#detail .tm-feed'); if (!f) return JSON.stringify({ error: 'no list' }); const last = f.lastElementChild; return JSON.stringify({ on: document.documentElement.classList.contains('ph-cb-on'), st: f.scrollTop, sh: f.scrollHeight, ch: f.clientHeight, toEnd: f.scrollHeight - f.scrollTop - f.clientHeight, lastBottom: last ? last.getBoundingClientRect().bottom : null, top: f.getBoundingClientRect().top, kbpad: getComputedStyle(document.documentElement).getPropertyValue('--ph-kbpad').trim(), transform: f.style.transform, n: f.children.length })"
  func fakeKeyboard(_ h: CGFloat) {
    let b = view.bounds
    let end = view.convert(CGRect(x: 0, y: h > 0 ? b.height - h : b.height, width: b.width, height: max(h, 1)), to: nil)
    NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: [
      UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: end), UIResponder.keyboardAnimationDurationUserInfoKey: 0.35, UIResponder.keyboardAnimationCurveUserInfoKey: UInt(7)])
  }
  func selfTest() {
    let wait = "for (let i = 0; i < 120 && !((typeof db !== 'undefined' && db) && typeof currentUserId !== 'undefined' && currentUserId && document.getElementById('ph-tabs')); i++) await new Promise((r) => setTimeout(r, 250));"
    let geo = "const cs = getComputedStyle(document.documentElement); const geo = { innerH: innerHeight, vvH: visualViewport ? visualViewport.height : null, shift: cs.getPropertyValue('--ph-shift'), tabsH: cs.getPropertyValue('--ios-tabs-h'), kb: cs.getPropertyValue('--ph-kb') };"
    // (name, script run in the page, what to do in the app first)
    let steps: [(String, String, (() -> Void)?)] = [
      ("home", wait + pause(1500) + """
        const info = await NativeMac.call('appInfo');
        \(geo)
        return JSON.stringify({ ios: document.documentElement.classList.contains('ios-app'), phone: typeof Phone !== 'undefined' && !!Phone.on, isIOSApp: Host.isIOSApp, isMacApp: Host.isMacApp,
          webTabsShown: getComputedStyle(document.getElementById('ph-tabs')).display !== 'none', view: ui.view, appInfo: info, geo,
          top: getComputedStyle(document.documentElement).getPropertyValue('--ph-top'), unknown: await NativeMac.call('nope').then(() => 'answered').catch((e) => e.message) });
        """, nil),
      // 23: Home's card swiped left (Copy link · Delete), then held (Attach Files: Camera · Photos · Files)
      ("homeSwipe", "return '{}'", { self.homeIfMade?.selfSwipe() }),
      ("homeLead", "return '{}'", { self.homeIfMade?.selfClose(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.homeIfMade?.selfSwipeRight() } }),
      ("homePress", "return '{}'", { self.homeIfMade?.selfClose(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.homeIfMade?.selfPress() } }),
      ("homeDone", "return '{}'", { self.presentedViewController?.dismiss(animated: false) }),
      // the header shrunk to its small bar once scrolled; Search stretched into its bar with results ("Ford")
      ("homeScrolled", "return '{}'", { self.homeIfMade?.selfScroll(400) }),
      ("homeFind", "return '{}'", { self.homeIfMade?.selfScroll(0); self.homeIfMade?.selfFind("Ford") }),
      ("homeFindDone", "return '{}'", { self.homeIfMade?.selfFindDone() }),
      // (the date sheet, as Home's Due opens it — it once crashed on iOS 27 while sizing itself)
      ("homeDate", "return '{}'", { if let host = self.sheetHost() { host.present(DateSheetVC(["value": "2026-11-23", "min": "", "max": "", "clearable": true, "md": false], dark: true) { _ in }, animated: false) } }),
      ("homeDateDone", "return '{}'", { self.presentedViewController?.dismiss(animated: false) }),
      // 26: My Tasks, the app's own (from the server): All, then the Done tab (read only), then All again
      ("mytasks", pause(2500) + "return JSON.stringify({ view: ui.view })", {
        if let i = self.tabKeys.firstIndex(of: "mytasks"), let item = self.tabBar.items?[i] { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) } }),
      ("mytasksDone", pause(2500) + "return JSON.stringify({ tab: ui.myTasksTab })", { self.myTasksIfMade?.selfTab("done") }),
      // (scrolled on the Done tab — the longer list: All / Done and the filters stuck under the frost bar)
      ("mytasksScrolled", "return JSON.stringify({ blank: !!document.querySelector('#content .ph-under-app') })", { self.myTasksIfMade?.selfScroll(400) }),
      ("mytasksTop", "return '{}'", { self.myTasksIfMade?.selfScroll(0) }),
      ("mytasksAll", pause(2000) + "return JSON.stringify({ tab: ui.myTasksTab })", { self.myTasksIfMade?.selfTab("all") }),
      // 28: the Inbox, the app's own: All, a row swiped right (Read / Unread), Unread, Mentions
      ("ibx", pause(2500) + "return JSON.stringify({ view: ui.view, blank: !!document.querySelector('#content .ph-under-app') })", {
        if let i = self.tabKeys.firstIndex(of: "inbox"), let item = self.tabBar.items?[i] { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) } }),
      ("ibxSwipe", "return '{}'", { self.inboxIfMade?.selfSwipeRow() }),
      ("ibxUnread", pause(2000) + "return '{}'", { self.inboxIfMade?.selfInboxTab("unread") }),
      ("ibxMentions", pause(2000) + "return '{}'", { self.inboxIfMade?.selfInboxTab("mentions") }),
      ("ibxAll", pause(2000) + "return '{}'", { self.inboxIfMade?.selfInboxTab("all") }),
      // 29: the morning round-up as iPhone's own sheet (the page's own sections, as the Inbox's round-up opens it)
      ("daily", pause(1500) + "return '{}'", { _ = self.dailyNative() }),   // (the app's own round-up — step 8)
      ("dailyDone", "return '{}'", { self.presentedViewController?.dismiss(animated: false) }),
      ("inbox", pause(1500) + "return JSON.stringify({ view: ui.view })", {
        if let i = self.tabKeys.firstIndex(of: "inbox"), let item = self.tabBar.items?[i] { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) } }),
      // (33: Me is the app's own — the page draws nothing under it; its Team members page pushed in, then back)
      ("me", "go('me'); " + pause(1200) + "for (let i = 0; i < 3; i++) { await Push.refresh(); " + pause(300) + " } return JSON.stringify({ native: typeof NativeMe !== 'undefined' && NativeMe.shown, blank: !!document.querySelector('#content .ph-under-app'), lockRows: document.querySelectorAll('#ph-lock, [data-ph-lock]').length, pushRows: document.querySelectorAll('#ph-push').length })", nil),
      ("meTeam", pause(2500) + "return '{}'", { self.meCtl.selfOpen("team") }),
      ("meAbout", pause(2500) + "return '{}'", { self.meCtl.pop(animated: false); self.meCtl.selfOpen("about") }),
      ("meProfile", pause(2500) + "return '{}'", { self.meCtl.pop(animated: false); self.meCtl.selfOpen("profile") }),
      ("meTrash", pause(2500) + "return '{}'", { self.meCtl.pop(animated: false); self.meCtl.selfOpen("trash") }),
      ("meBack", pause(1200) + "return '{}'", { self.meCtl.pop(animated: true) }),
      ("client", "try { let c = db.clients.find((x) => (x.folders || []).some((f) => (f.files || []).length > 1)) || db.clients[0]; if (!c) { c = createClient('Sample client'); c.folders[0].files = [{ id: 'st-a1', name: 'Logo primary.png', size: 48000, at: nowISO() }, { id: 'st-a2', name: 'Brand guidelines.pdf', size: 2400000, at: nowISO() }, { id: 'st-a3', name: 'Logo lockup.ai', size: 4800000, at: nowISO() }] } const f = (c.folders || []).find((x) => (x.files || []).length > 1) || (c.folders || [])[0]; if (!f) return JSON.stringify({ error: 'no folder' }); openClient(c.id, f.id); " + pause(1200) + "return JSON.stringify({ wide: document.getElementById('content').scrollWidth > innerWidth + 1 }) } catch (e) { return JSON.stringify({ error: String(e && e.message || e) }) }", nil),
      // 30: the app's own task page — pushed in, scrolled, its Comments, back (then the website's task page for the
      // stages after it)
      // (from Home — the Client Assets stage before leaves the page on a client's folder, the app's own screens over it —
      //  and a task that isn't locked for CD review: its Assignees lock then, 32)
      ("tpage", "if (ui.view === 'client' || ui.view === 'clients') go('today'); const free = (x) => !x.parentId && !x.done && !x.lockedAt && !(x.reviews || []).length; const t = db.tasks.find((x) => free(x) && (x.comments || []).length && (x.checklist || []).length) || db.tasks.find((x) => free(x) && (x.comments || []).length) || db.tasks.find(free) || db.tasks.find((x) => !x.parentId && !x.done); openTask(t.id); " + pause(3000) + "return JSON.stringify({ webTask: !!ui.taskId, id: t.id })", { self.presentedViewController?.dismiss(animated: false) }),
      ("tpageScrolled", pause(900) + "return '{}'", { self.taskPages.last?.scroll.setContentOffset(CGPoint(x: 0, y: 380), animated: false) }),
      ("tpageSheet", pause(1500) + "return '{}'", { self.taskPages.last?.pickPeople() }),
      ("tpageComments", pause(5000) + "return '{}'", { self.presentedViewController?.dismiss(animated: false); self.taskPages.last?.setTab("comments", tell: true) }),
      // (Comments → Details as the swipe does it — for the film: nothing of Comments may show on Details on the way)
      ("tpageSwipeDetails", pause(1500) + "return '{}'", { if let p = self.taskPages.last { self.toDetailsFromComments(p) } }),
      ("tpageBack", pause(1500) + "return JSON.stringify({ webTask: !!ui.taskId })", { if let p = self.taskPages.last { p.setTab("details", tell: true); self.closeTaskPage(p, animated: false) } }),
      // (for the film: from Home into a task and back — 🔍 and your photo melting into •••, ‹ growing in, and back)
      ("melt", pause(2500) + "return '{}'", { if let i = self.tabKeys.firstIndex(of: "today"), let item = self.tabBar.items?[i] { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) } }),
      ("meltOpen", pause(2500) + "return '{}'", {
        let id = ((self.serverHome.shown?["groups"] as? [[String: Any]]) ?? []).flatMap { $0["cards"] as? [[String: Any]] ?? [] }.compactMap { $0["id"] as? String }.first
        if let id = id { self.openTaskPage(id, tab: "details", focus: "") } }),
      ("meltBack", pause(2500) + "return '{}'", { if let p = self.taskPages.last { self.closeTaskPage(p) } }),
      ("task", "window.__e11WebTask = true; const t = db.tasks.find((x) => !x.parentId && !x.done && (x.comments || []).length) || db.tasks.find((x) => !x.parentId && !x.done); openTask(t.id); " + pause(1500) + "return JSON.stringify({ taskOpen: !!ui.taskId })", nil),
      ("sheet", "const m = showMenu(document.body, [{ html: '<div class=\"react-pick\">' + REACTIONS.map((e) => '<button>' + e + '</button>').join('') + '</div>' }, { label: 'Reply', icon: 'reply', run() {} }, { label: 'Edit comment', icon: 'edit', run() {} }, { label: 'Copy text', icon: 'copy', run() {} }, '-', { label: 'Delete comment', icon: 'trash', danger: true, run() {} }]); m.classList.add('cm-sheet'); " + pause(900) + geo + " const r = m.getBoundingClientRect(); return JSON.stringify({ menuTop: r.top, menuBottom: r.bottom, geo })", nil),
      ("back", "document.querySelectorAll('.menu, #ph-menu-scrim').forEach((x) => x.remove()); closeDetail(); " + pause(800) + "return JSON.stringify({ taskOpen: !!ui.taskId })", nil),
      // native sheets (Haris: the same room above and below as the Channel sheet, everywhere — and the last option of a
      // long list clear of the bottom edge at the end of the scroll): a long titled one at rest, the same scrolled to the
      // end, a short untitled one like Channel, a short one titled with a person
      ("nsheet", "return '{}'", { self.selfSheet([
        ["header": "Change role", "rows": ["Super Admin", "Office Admin", "Account Manager", "Production", "Social", "Freelancer", "Finance only · Admin", "Finance only · Viewer"].enumerated().map { ["i": $0.offset, "label": $0.element, "dot": [124, 108, 240]] }],
        ["rows": [["i": 20, "label": "Super Admin rights", "icon": "shield"], ["i": 21, "label": "No Finance access", "icon": "coin", "checked": true], ["i": 22, "label": "Finance Admin", "icon": "coin"], ["i": 23, "label": "Finance Viewer", "icon": "coin"]]],
        ["rows": [["i": 30, "label": "Remove from team", "icon": "trash", "danger": true]]]]) }),
      ("nsheetEnd", "return '{}'", { (self.presentedViewController as? NativeSheetVC)?.scrollToEnd() }),
      ("nsheetChannel", "return '{}'", { self.selfSheet([["rows": ["Instagram", "Facebook", "TikTok", "LinkedIn", "X", "YouTube"].enumerated().map { ["i": $0.offset, "label": $0.element, "dot": [230, 120, 160]] }]]) }),
      ("nsheetTitled", "return '{}'", { self.selfSheet([
        ["header": "Ali Raza’s priority", "person": ["initials": "AR", "color": [90, 120, 200]], "rows": [["i": 0, "label": "Urgent", "sub": "always on top", "icon": "flag", "tint": [220, 60, 60]]]],
        ["header": "Priority for Oct 28", "rows": [["i": -1, "label": "", "kind": "num", "chips": (1...10).map { ["i": $0, "label": String($0)] }]]],
        ["rows": [["i": 11, "label": "No priority", "icon": "flag"]]]]) }),
      // New task as a native form: typed in, then tucked into the bar (title + Continue must show — Haris 2026-10-30)
      ("form", "return '{}'", {
        let show = { self.run("formSheet", FormSheetVC.selfArgs()) { _ in } }
        if let p = self.presentedViewController { p.dismiss(animated: false) { show() } } else { show() } }),
      ("formTuck", "return '{}'", { FormSheetVC.current?.selfFill("Spring launch reel"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { FormSheetVC.current?.selfTuck() } }),
      // the native comment box (17+): replying, a file and one uploading, text typed — then @Sa for the people list
      ("cbar", "return '{}'", {
        self.presentedViewController?.dismiss(animated: false)
        self.commentBar(CommentBar.selfArgs())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.cbar.selfType("Thanks, can we make the logo a bit bigger on the last frame and keep the date as it is?") } }),
      ("cbarMention", "return '{}'", { self.cbar.selfType("Hi @Sa") }),
      ("cbarAttach", "return '{}'", { self.cbar.openAttach() }),
      // 19: a task's Comments with the keyboard coming up and going down (a pretend keyboard: the simulator shows none) —
      // the list is moved by iOS and stays at the latest comment, the page keeps the room once it's up
      ("cfeed", "window.__stPause = 1; const t = db.tasks.filter((x) => !x.parentId).sort((a, b) => (b.comments || []).length - (a.comments || []).length)[0]; openTask(t.id); " + pause(1200) + "document.querySelector('#detail .ph-seg.in-task [data-tab=\"comments\"]').click(); " + pause(2500) + feedJS, {
        self.presentedViewController?.dismiss(animated: false)
        self.cwebPaused = true; self.cwebUpdate()
        self.commentBar(["show": false, "clear": true]) }),
      ("cfeedKb", pause(1200) + feedJS, { self.fakeKeyboard(336) }),
      ("cfeedDown", pause(1200) + feedJS, { self.fakeKeyboard(0) }),
      // 20: the same task's Comments on their own screen — shown over the task, at the latest; the keyboard up and down
      ("cweb", pause(2500) + "return '{}'", { self.cwebPaused = false; self.cwebUpdate() }),
      ("cwebKb", pause(1200) + "return '{}'", { self.fakeKeyboard(336) }),
      ("cwebDown", pause(1200) + "return '{}'", { self.fakeKeyboard(0) }),
      ("preview", "return '{}'", {
        self.presentedViewController?.dismiss(animated: false)
        self.commentBar(["show": false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.run("preview", PreviewVC.selfArgs()) { _ in } } }),
      ("signin", pause(4000) + "return JSON.stringify({ host: location.host, top: (document.querySelector('h1, h2, img, form') || document.body).getBoundingClientRect().top })", {
        self.presentedViewController?.dismiss(animated: false)
        self.commentBar(["show": false])
        self.previewVC = nil
        self.web.load(URLRequest(url: URL(string: "https://e11hq.cloudflareaccess.com/")!)) }),
    ]
    func run(_ i: Int) {
      if i >= steps.count { selfResult["frame"] = ["web": web.frame.height, "screen": view.bounds.height, "inset": web.scrollView.contentInsetAdjustmentBehavior == .never ? "never" : "auto", "insetTop": web.scrollView.adjustedContentInset.top, "host": web.url?.host ?? "", "reviewLink": !reviewLink.isHidden, "privacy": Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil] as [String: Any]; return writeSelf("done") }
      let (name, js, before) = steps[i]
      before?()
      DispatchQueue.main.asyncAfter(deadline: .now() + (before == nil ? 0.2 : 1.5)) {
        self.probe(name, js) {
          if name.hasPrefix("cbar") { self.selfResult[name + "Geo"] = self.cbar.geo() }
          if name.hasPrefix("cfeed") { self.selfResult[name + "Geo"] = self.feedGeo }
          if name.hasPrefix("cweb") {
            let sv = self.cweb?.scrollView
            self.selfResult[name + "Geo"] = ["made": self.cweb != nil, "loaded": self.cwebLoaded, "shown": self.cwebShown, "atEnd": self.cwebAtEnd(),
              "inset": sv?.contentInset.bottom ?? -1, "offset": sv?.contentOffset.y ?? -1, "content": sv?.contentSize.height ?? -1, "height": sv?.bounds.height ?? -1,
              "top": self.cbox.frame.minY, "ty": self.cweb?.transform.ty ?? 0, "task": self.cwebTask ?? "", "cover": self.keyboardCover] as [String: Any]
          }
          if name.hasPrefix("form") { self.selfResult[name + "Geo"] = FormSheetVC.current?.geo() ?? ["error": "no form"] }
          if name.hasPrefix("nsheet") { self.selfResult[name + "Geo"] = (self.presentedViewController as? NativeSheetVC)?.geo() ?? ["error": "no native sheet"] }
          if name == "home" || name == "inbox" || name.hasPrefix("home") { var g = self.homeGeo(); g["corner"] = self.corner.kind; g["sheet"] = self.presentedViewController.map { String(describing: type(of: $0)) } ?? ""; self.selfResult[name + "Native"] = g }
          if name.hasPrefix("tpage") {
            let p = self.taskPages.last
            self.selfResult[name + "Native"] = ["pages": self.taskPages.count, "title": p?.model?["title"] as? String ?? "", "tab": p?.tab ?? "", "drawn": p?.model != nil,
              "x": p?.transform.tx ?? -1, "tabBar": !self.tabBar.isHidden, "comments": self.cwebShown, "box": self.cbarIfMade.map { !$0.isHidden } ?? false, "compose": self.composeIfMade.map { !$0.isHidden } ?? false, "content": p?.scroll.contentSize.height ?? 0, "feed": (p?.feed?.model?["items"] as? [Any])?.count ?? -1, "corner": self.corner.kind, "sheet": self.presentedViewController.map { String(describing: type(of: $0)) } ?? "", "cornerW": self.corner.frame.width, "cornerX": self.corner.frame.maxX, "copy": AppData.shared.ready, "copyTask": p.map { AppData.shared.screen("task", $0.taskId).model?["title"] as? String ?? "" } ?? ""] as [String: Any]
          }
          if ["me", "meTeam", "meAbout", "meProfile", "meTrash", "meBack"].contains(name) { let t = self.cornerTarget(); self.selfResult[name + "Native"] = self.meCtl.geo(corner: "\(t.0.kind),\(t.1.kind),\(t.2.kind)") }
          if name == "daily" { self.selfResult["dailyNative"] = ["sheet": self.presentedViewController.map { String(describing: type(of: $0)) } ?? ""] }
          // (Client Assets, the app's own — shell 32: the page's folder opened as the app's screens)
          if name == "client" { self.selfResult["clientAssets"] = ["open": self.assetsCtl.isOpen, "screens": self.assetsCtl.screens.count, "kind": self.assetsCtl.top?.assets ?? "", "parts": self.assetsCtl.top?.assetsParts.count ?? 0, "shown": self.assetsCtl.shown != nil, "corner": self.corner.kind, "web": (self.web?.isHidden ?? true) ? "hidden" : "under"] as [String: Any] }
          if name.hasPrefix("ibx") {
            var g: [String: Any] = ["made": self.inboxIfMade != nil, "shown": self.inboxIfMade?.isHidden == false, "server": self.serverInboxIfMade?.on ?? false, "query": self.serverInboxIfMade?.query ?? ""]
            if let h = self.inboxIfMade { g.merge(h.inboxGeo()) { a, _ in a } }
            g["corner"] = self.corner.kind; g["cornerW"] = self.corner.frame.width; g["cornerA"] = self.corner.alpha
            // (who the server's Inbox is for, who the page says is signed in, and what the server sent — for the empty-Inbox runs)
            g["me"] = self.serverInboxIfMade?.me ?? ""; g["pageMe"] = self.inboxPageMe ?? ""
            g["modelRows"] = (self.serverInboxIfMade?.shown?["rows"] as? [Any])?.count ?? -1; g["modelMe"] = self.serverInboxIfMade?.shown?["me"] as? String ?? ""
            self.selfResult[name + "Inbox"] = g
          }
          if name.hasPrefix("mytasks") || name == "inbox" {
            var g: [String: Any] = ["made": self.myTasksIfMade != nil, "shown": self.myTasksIfMade?.isHidden == false, "server": self.serverMyTasksIfMade?.on ?? false, "query": self.serverMyTasksIfMade?.query ?? ""]
            if let h = self.myTasksIfMade { g.merge(h.listGeo()) { a, _ in a }; g["title"] = h.geo()["title"] }
            g["me"] = self.serverMyTasksIfMade?.me ?? ""; g["pageMe"] = self.myTasksPageMe ?? ""; g["modelMe"] = self.serverMyTasksIfMade?.shown?["me"] as? String ?? ""
            g["modelCards"] = ((self.serverMyTasksIfMade?.shown?["groups"] as? [[String: Any]]) ?? []).reduce(0) { $0 + (($1["cards"] as? [Any])?.count ?? 0) }
            self.selfResult[name + "MyTasks"] = g
          }
          if name == "home" || name == "inbox" { self.selfResult[name + "Frame"] = ["web": self.web.frame.height, "screen": self.view.bounds.height, "tabBar": !self.tabBar.isHidden] as [String: Any] }
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.writeSelf(name); DispatchQueue.main.asyncAfter(deadline: .now() + 4) { run(i + 1) } }
        }
      }
    }
    // (22+: once the startup screen has gone — the page says when; Home is checked under it otherwise)
    func afterSplash(_ n: Int) {
      if splash != nil && n < 80 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { afterSplash(n + 1) }; return }
      selfResult["splashGone"] = splash == nil
      run(0)
    }
    afterSplash(0)
  }
}

// The download in progress, floating above the tab bar: the file, how far it's got, and Cancel
final class DownloadHUD: UIVisualEffectView {
  let title = UILabel(), detail = UILabel(), bar = UIProgressView(progressViewStyle: .default), cancel = UIButton(type: .system)
  var onCancel: (() -> Void)?
  init() {
    super.init(effect: UIBlurEffect(style: .systemThickMaterial))
    layer.cornerRadius = 18; layer.cornerCurve = .continuous; clipsToBounds = true
    title.font = .systemFont(ofSize: 15, weight: .semibold); title.lineBreakMode = .byTruncatingMiddle
    detail.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); detail.textColor = .secondaryLabel
    cancel.setTitle("Cancel", for: .normal); cancel.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    cancel.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)
    [title, detail, bar, cancel].forEach { contentView.addSubview($0) }
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func tapCancel() { onCancel?() }
  func show(title t: String, detail d: String, progress p: Float) {
    title.text = t; detail.text = d
    if p >= 0 { bar.isHidden = false; bar.setProgress(p, animated: true) } else { bar.isHidden = true }
  }
  func place(in b: CGRect, above bottom: CGFloat) {
    let w = min(b.width - 24, 420), h: CGFloat = 70
    frame = CGRect(x: (b.width - w) / 2, y: b.height - bottom - h - 12, width: w, height: h)
    cancel.sizeToFit()
    let cw = cancel.bounds.width + 8
    cancel.frame = CGRect(x: w - cw - 10, y: 0, width: cw, height: h)
    title.frame = CGRect(x: 16, y: 11, width: w - cw - 30, height: 20)
    detail.frame = CGRect(x: 16, y: 32, width: w - cw - 30, height: 17)
    bar.frame = CGRect(x: 16, y: 56, width: w - cw - 30, height: 4)
  }
}

// No ‹ › Done bar above the keyboard (it covered the page in a native app; the page has its own buttons).
// The page's content view gets a version of itself without that bar, the same way other well-known iPhone apps
// built on a web view do it.
extension WKWebView {
  func hideKeyboardBar() {
    guard let content = scrollView.subviews.first(where: { String(describing: type(of: $0)).hasPrefix("WKContent") }),
          let base: AnyClass = object_getClass(content) else { return }
    let baseName = String(cString: class_getName(base))
    if baseName.hasSuffix("_E11NoBar") { return }
    let name = baseName + "_E11NoBar"
    var cls: AnyClass? = NSClassFromString(name)
    if cls == nil, let made = objc_allocateClassPair(base, name, 0) {
      let none: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
      class_addMethod(made, #selector(getter: UIResponder.inputAccessoryView), imp_implementationWithBlock(none), "@@:")
      objc_registerClassPair(made)
      cls = made
    }
    if let c = cls { object_setClass(content, c) }
  }
}


/* ---------- Attaching files: the app's own sheet from the bottom of the screen (never where the keyboard was) ----------
   Photo Library (several at once, pictures and videos in the usual formats), Take Photo or Video, or Choose Files. The
   chosen files are copied into the app's temporary folder; the page reads them in pieces (readLocalChunk, like the Mac
   app) and uploads them as usual. */
final class Picker: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
  static let shared = Picker()
  private var done: (([String: Any]) -> Void)?
  private var files: [String: URL] = [:]
  private let lock = NSLock()   // (photos are copied on background threads)
  private let dir: URL = { let d = FileManager.default.temporaryDirectory.appendingPathComponent("picked", isDirectory: true); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }()

  // (the keyboard isn't put down here: iPhone hides it while a picker covers the screen and brings it back for the
  //  comment box afterwards)
  func pick(from vc: UIViewController, single: Bool, source: String? = nil, _ done: @escaping ([String: Any]) -> Void) {
    finish([])   // (a sheet still open from before answers "nothing")
    self.done = done
    let photos = {
      var c = PHPickerConfiguration()
      c.selectionLimit = single ? 1 : 0
      c.filter = .any(of: [.images, .videos])
      c.preferredAssetRepresentationMode = .compatible   // (JPEG and H.264, like a web page gets)
      let p = PHPickerViewController(configuration: c); p.delegate = self
      vc.present(p, animated: true)
    }
    let camera = {
      let p = UIImagePickerController(); p.sourceType = .camera
      p.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? ["public.image"]
      p.videoQuality = .typeHigh; p.delegate = self
      vc.present(p, animated: true)
    }
    let files = {
      let p = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
      p.allowsMultipleSelection = !single; p.delegate = self
      vc.present(p, animated: true)
    }
    // straight to one (the page's attach bar: Photos · Camera · Files)
    switch source {
    case "photos": return photos()
    case "camera": return UIImagePickerController.isSourceTypeAvailable(.camera) ? camera() : finish([])
    case "files": return files()
    default: break
    }
    let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in photos() })
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      sheet.addAction(UIAlertAction(title: "Take Photo or Video", style: .default) { _ in camera() })
    }
    sheet.addAction(UIAlertAction(title: "Choose Files", style: .default) { _ in files() })
    sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in self.finish([]) })
    if let pop = sheet.popoverPresentationController {   // (iPad: from the bottom middle)
      pop.sourceView = vc.view; pop.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY - 40, width: 1, height: 1); pop.permittedArrowDirections = []
    }
    vc.present(sheet, animated: true)
  }

  private func keep(_ src: URL, name: String) -> [String: Any]? {
    let tok = UUID().uuidString
    let dest = dir.appendingPathComponent(tok + "-" + name.replacingOccurrences(of: "/", with: "-"))
    do { try FileManager.default.copyItem(at: src, to: dest) } catch { return nil }
    lock.lock(); files[tok] = dest; lock.unlock()
    let size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber)?.int64Value ?? 0
    return ["token": tok, "name": name, "size": size]
  }
  private func finish(_ out: [[String: Any]]) {
    guard let d = done else { return }
    done = nil
    FocusAfterPicker.allow()   // (the page puts the cursor back in the comment box, keyboard and all)
    DispatchQueue.main.async { d(["ok": true, "files": out]) }
  }

  // Photo Library
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    if results.isEmpty { return finish([]) }
    var out = [[String: Any]?](repeating: nil, count: results.count)
    let group = DispatchGroup()
    for (i, r) in results.enumerated() {
      let p = r.itemProvider
      let isVideo = p.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      let type = isVideo ? UTType.movie.identifier : (p.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier)
      group.enter()
      p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
        if let url = url {
          let ext = url.pathExtension.isEmpty ? (isVideo ? "mov" : "jpg") : url.pathExtension
          let base = (p.suggestedName ?? (isVideo ? "Video" : "Photo"))
          out[i] = self.keep(url, name: base.hasSuffix("." + ext) ? base : base + "." + ext)
        }
        group.leave()
      }
    }
    group.notify(queue: .main) { self.finish(out.compactMap { $0 }) }
  }
  // Camera
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    picker.dismiss(animated: true)
    let stamp = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"; return f.string(from: Date()) }()
    if let url = info[.mediaURL] as? URL { return finish([keep(url, name: "Video \(stamp).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)")].compactMap { $0 }) }
    if let img = info[.originalImage] as? UIImage, let data = img.jpegData(compressionQuality: 0.9) {
      let tmp = dir.appendingPathComponent(UUID().uuidString + ".jpg")
      if (try? data.write(to: tmp)) != nil { let r = keep(tmp, name: "Photo \(stamp).jpg"); try? FileManager.default.removeItem(at: tmp); return finish([r].compactMap { $0 }) }
    }
    finish([])
  }
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true); finish([]) }
  // Files
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(urls.compactMap { u in let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }; return keep(u, name: u.lastPathComponent) })
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }

  // (30: the app uploads a chosen file itself — SubmitSheet.swift)
  func url(_ tok: String) -> URL? { lock.lock(); defer { lock.unlock() }; return files[tok] }
  // A piece of a chosen file, for the page to upload (the file is let go after its last piece)
  func read(_ a: [String: Any]) -> [String: Any] {
    lock.lock(); let known = (a["token"] as? String).flatMap { files[$0] }; lock.unlock()
    guard let tok = a["token"] as? String, let url = known, let fh = try? FileHandle(forReadingFrom: url) else { return ["ok": false, "error": "File no longer available"] }
    defer { try? fh.close() }
    let off = UInt64((a["offset"] as? NSNumber)?.int64Value ?? 0), len = (a["length"] as? NSNumber)?.intValue ?? 0
    try? fh.seek(toOffset: off)
    let data = (try? fh.read(upToCount: max(0, len))) ?? Data()
    if (a["last"] as? Bool) == true { lock.lock(); files[tok] = nil; lock.unlock(); try? FileManager.default.removeItem(at: url) }
    return ["ok": true, "b64": data.base64EncodedString()]
  }
}

/* After Photos / Camera / Files the page puts the cursor back where it was, and the keyboard should come back with it.
   The web view only brings the keyboard up for a focus that comes from a tap, so for a moment after a picker closes it
   treats the page's focus as one (the same hook the Ionic/Capacitor keyboard settings use). Nowhere else. */
enum FocusAfterPicker {
  private(set) static var installed = false
  private static var until = Date.distantPast
  static func allow() { until = Date().addingTimeInterval(2) }
  static func install() {
    guard !installed, let cls = NSClassFromString("WKContentView") else { return }
    let sel = sel_getUid("_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:")
    guard let m = class_getInstanceMethod(cls, sel) else { return }
    // (activity-state changes is a set of flags: passed on whole)
    typealias Orig = @convention(c) (AnyObject, Selector, UnsafeRawPointer, Bool, Bool, UInt64, AnyObject?) -> Void
    let orig = unsafeBitCast(method_getImplementation(m), to: Orig.self)
    let block: @convention(block) (AnyObject, UnsafeRawPointer, Bool, Bool, UInt64, AnyObject?) -> Void = { me, info, user, blur, changes, obj in
      orig(me, sel, info, user || Date() < until, blur, changes, obj)
    }
    method_setImplementation(m, imp_implementationWithBlock(block))
    installed = true
  }
}


/* A plain menu from the page as iOS's own sheet: sections of rows (icon, text, an optional second line, a tick,
   red for delete, a coloured dot for a role), sized to fit, with the grab handle. iOS draws it — floating at rest,
   it grows with the finger when pulled and springs back; dragged down or tapped outside, it closes. */
final class NativeSheetVC: UIViewController, UITableViewDataSource, UITableViewDelegate, UISheetPresentationControllerDelegate, UISearchBarDelegate {
  struct Chip { let i: Int; let swatch: String?; let label: String?; let color: UIColor?; let on: Bool; let disabled: Bool }
  struct Row { let i: Int; let label: String; let sub: String?; let icon: String?; let danger: Bool; let checked: Bool; let disabled: Bool; let dot: UIColor?; let tint: UIColor?; let locked: Bool; let chips: [Chip]?; let chipKind: String; var multi: Bool = false
    var pic: UIImage? = nil; var initials: String? = nil; var picColor: UIColor? = nil; var find: String = ""; var accent: Bool = false; var red: Bool = false }
  struct Section { let header: String?; let rows: [Row]; var photo: UIImage? = nil; var initials: String? = nil; var color: UIColor? = nil }
  private var sections: [Section] = []
  // (a sheet with a search box: everything, what the search shows, the ticks flipped here, the typed entry option)
  private var all: [Section] = []
  private var ticks: [Int: Bool] = [:]
  private var searchBar: UISearchBar?
  private var searchHint = ""
  private var customLabel: String?
  private var emptyText = "No matches"
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private var answer: ((Int, String?) -> Void)?
  static func photo(_ v: Any?) -> UIImage? {
    guard let p = v as? [String: Any], let d = p["photo"] as? String, let comma = d.firstIndex(of: ","),
          let data = Data(base64Encoded: String(d[d.index(after: comma)...])) else { return nil }
    return UIImage(data: data)
  }
  static func color(_ v: Any?) -> UIColor? {
    guard let d = v as? [NSNumber], d.count >= 3 else { return nil }
    return UIColor(red: CGFloat(d[0].doubleValue) / 255, green: CGFloat(d[1].doubleValue) / 255, blue: CGFloat(d[2].doubleValue) / 255, alpha: 1)
  }
  // The same room on every sheet, as on the Channel sheet (Haris, 2026-10-30): from the sheet's top edge to the first
  // thing in it (a title's text or the first option's card) is always TOP; from the last option's card to the sheet's
  // visible bottom edge is always what a fitting list like Channel gets (END + the list's own ~20 after its last
  // section ≈ 25 on screen, simulator 2026-10-30) — a list that scrolls gets the same at the end of its scroll.
  static let TOP: CGFloat = 30
  static let END: CGFloat = 8
  private static let TITLE_H: CGFloat = 18, TITLE_GAP: CGFloat = 8   // (a section title's text, and its gap to its card)
  private static let SYMBOLS: [String: String] = [
    "plus": "plus", "edit": "pencil", "trash": "trash", "x": "xmark", "clip": "paperclip", "folder": "folder",
    "info": "info.circle", "copy": "doc.on.doc", "search": "magnifyingglass", "download": "arrow.down.circle",
    "reply": "arrowshape.turn.up.left", "user": "person", "users": "person.2", "coin": "dollarsign.circle",
    "shield": "checkmark.shield", "lock": "lock", "unlock": "lock.open", "logout": "rectangle.portrait.and.arrow.right", "bell": "bell",
    "camera": "camera", "image": "photo", "chev-left": "chevron.left", "chev-right": "chevron.right", "chev": "chevron.down",
    "chev-up": "chevron.up", "link": "link", "open": "arrow.up.right.square", "check": "checkmark", "assets": "photo.on.rectangle",
    "mail": "envelope", "clock": "clock", "eye": "eye", "upload": "arrow.up.circle", "sun": "sun.max", "moon": "moon",
    "cal": "calendar", "flag": "flag", "tag": "tag", "pin": "pin", "pushpin": "pin", "gift": "gift", "home": "house",
    "inbox": "tray", "comment": "text.bubble", "chat": "bubble.left", "list": "list.bullet", "board": "rectangle.split.3x1",
    "send": "paperplane", "play": "play", "smile": "face.smiling", "more": "ellipsis", "check-circle": "checkmark.circle",
    "checklist": "checklist", "activity": "waveform.path.ecg", "details": "doc.text", "arrow": "arrow.right", "select": "checkmark.square",
  ]
  private var multi = false
  private var pick: ((Int) -> Void)?
  init(_ a: [String: Any], dark: Bool, pick: ((Int) -> Void)? = nil, answer: @escaping (Int, String?) -> Void) {
    self.answer = answer
    self.pick = pick
    multi = (a["multi"] as? Bool) == true
    instant = (a["instant"] as? Bool) == true
    super.init(nibName: nil, bundle: nil)
    for sec in a["sections"] as? [[String: Any]] ?? [] {
      let rows = (sec["rows"] as? [[String: Any]] ?? []).map { r -> Row in
        let chips = (r["chips"] as? [[String: Any]]).map { list in list.map { c in
          Chip(i: (c["i"] as? NSNumber)?.intValue ?? -1, swatch: c["swatch"] as? String, label: c["label"] as? String,
               color: NativeSheetVC.color(c["color"]), on: (c["on"] as? Bool) == true, disabled: (c["disabled"] as? Bool) == true) } }
        return Row(i: (r["i"] as? NSNumber)?.intValue ?? -1, label: r["label"] as? String ?? "", sub: (r["sub"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                   icon: r["icon"] as? String, danger: (r["danger"] as? Bool) == true, checked: (r["checked"] as? Bool) == true,
                   disabled: (r["disabled"] as? Bool) == true, dot: NativeSheetVC.color(r["dot"]), tint: NativeSheetVC.color(r["tint"]),
                   locked: (r["locked"] as? Bool) == true, chips: chips, chipKind: r["kind"] as? String ?? "", multi: (r["multi"] as? Bool) == true,
                   pic: NativeSheetVC.photo(r["person"]), initials: (r["person"] as? [String: Any])?["initials"] as? String,
                   picColor: NativeSheetVC.color((r["person"] as? [String: Any])?["color"]), find: ((r["find"] as? String) ?? (r["label"] as? String) ?? "").lowercased(),
                   accent: (r["accent"] as? Bool) == true, red: (r["red"] as? Bool) == true)
      }
      if !rows.isEmpty {
        var sc = Section(header: (sec["header"] as? String).flatMap { $0.isEmpty ? nil : $0 }, rows: rows)
        if let p = sec["person"] as? [String: Any] {
          if let d = p["photo"] as? String, let comma = d.firstIndex(of: ","), let data = Data(base64Encoded: String(d[d.index(after: comma)...])) { sc.photo = UIImage(data: data) }
          sc.initials = p["initials"] as? String; sc.color = NativeSheetVC.color(p["color"])
        }
        sections.append(sc)
      }
    }
    all = sections
    if let hint = a["search"] as? String { searchHint = hint; searchBar = UISearchBar() }
    customLabel = a["custom"] as? String          // e.g. "Use “%@”" — a typed entry that isn't in the list
    if let e = a["empty"] as? String { emptyText = e }
    overrideUserInterfaceStyle = dark ? .dark : .light
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController {
      // (at most about two-thirds of the screen, so even a long list stays the floating card; it scrolls inside)
      sh.detents = [.custom(identifier: .init("fit")) { [weak self] ctx in min(ctx.maximumDetentValue * 0.68, self?.fitHeight ?? 320) }]
      // (a sheet with a search box can also go full height — it does when typing starts, so the keyboard leaves room)
      if searchBar != nil { sh.detents.append(.large()) }
      sh.prefersGrabberVisible = true
      sh.prefersScrollingExpandsWhenScrolledToEdge = false
      sh.delegate = self
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  private var fitHeight: CGFloat = 320
  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26, *) { view.backgroundColor = .clear; table.backgroundColor = .clear }
    else { view.backgroundColor = .systemGroupedBackground; table.backgroundColor = .systemGroupedBackground }
    table.dataSource = self; table.delegate = self
    table.translatesAutoresizingMaskIntoConstraints = false
    // (tight like Apple's own sheets: just room for the grab handle above, a small margin below — the page's
    //  automatic safe-area padding is off, the bottom margin is set by hand)
    table.contentInsetAdjustmentBehavior = .never
    // (the list starts under the grab handle, but scrolls up behind it to the sheet's own rounded edge — no flat cut)
    // (a titled first section: its header is exactly the title's text + its gap, so the text starts at TOP too)
    table.contentInset = UIEdgeInsets(top: NativeSheetVC.TOP, left: 0, bottom: NativeSheetVC.END + (floating ? 0 : 34), right: 0)
    table.alwaysBounceVertical = false   // (a list that fits doesn't scroll: the finger moves the sheet itself)
    // (rows ignore the screen's bottom safe area: a row lying over it had its text pushed up inside it, and the text
    //  slid about within the row as the sheet moved — "Remove from team")
    table.insetsContentViewsToSafeArea = false
    table.insetsLayoutMarginsFromSafeArea = false
    // (every row measured up front, not estimated: estimated heights changed the list's length while it scrolled,
    //  which made the options jump near the end)
    table.estimatedRowHeight = 0
    table.estimatedSectionHeaderHeight = 0
    table.estimatedSectionFooterHeight = 0
    table.verticalScrollIndicatorInsets = UIEdgeInsets(top: 22, left: 0, bottom: 22, right: 0)
    table.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude))   // (no default gap on top)
    table.tableFooterView = UIView(frame: .zero)
    table.sectionHeaderTopPadding = 0
    view.addSubview(table)
    if let sb = searchBar {
      // the search box sits where a first option would start (TOP under the sheet's top edge); the list below it
      sb.searchBarStyle = .minimal
      sb.placeholder = searchHint
      sb.autocapitalizationType = .none
      sb.autocorrectionType = .no
      sb.delegate = self
      sb.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(sb)
      table.contentInset.top = 6
      table.keyboardDismissMode = .onDrag
      NSLayoutConstraint.activate([sb.topAnchor.constraint(equalTo: view.topAnchor, constant: NativeSheetVC.TOP - 10),
                                   sb.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
                                   sb.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
                                   table.topAnchor.constraint(equalTo: sb.bottomAnchor), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                                   table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    } else {
      NSLayoutConstraint.activate([table.topAnchor.constraint(equalTo: view.topAnchor), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                                   table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
  }
  // Search: the rows whose name / email / role hold the text; a typed entry ("Use “…”") when allowed; else a grey line.
  // (Only what's shown changes — the sheet keeps its size while typing.)
  func searchBar(_ searchBar: UISearchBar, textDidChange text: String) { applySearch(text) }
  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    guard let sh = sheetPresentationController else { return }
    sh.animateChanges { sh.selectedDetentIdentifier = .large }
  }
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
  private func applySearch(_ text: String) {
    let q = text.trimmingCharacters(in: .whitespaces).lowercased()
    var out: [Section] = []
    for sec in all {
      let rows = q.isEmpty ? sec.rows : sec.rows.filter { $0.chips == nil && $0.find.contains(q) }
      if !rows.isEmpty { out.append(Section(header: sec.header, rows: rows, photo: sec.photo, initials: sec.initials, color: sec.color)) }
    }
    let typed = text.trimmingCharacters(in: .whitespaces)
    if let fmt = customLabel, !typed.isEmpty, !all.contains(where: { $0.rows.contains { $0.label.lowercased() == q } }) {
      out.append(Section(header: nil, rows: [Row(i: -2, label: fmt.replacingOccurrences(of: "%@", with: typed), sub: nil, icon: "plus", danger: false, checked: false,
                                                 disabled: false, dot: nil, tint: nil, locked: false, chips: nil, chipKind: "", find: typed)]))
    }
    if out.isEmpty {
      out = [Section(header: nil, rows: [Row(i: -1, label: emptyText.replacingOccurrences(of: "%@", with: typed), sub: nil, icon: nil, danger: false, checked: false,
                                             disabled: true, dot: nil, tint: nil, locked: false, chips: nil, chipKind: "")])]
    }
    sections = out
    table.reloadData()
  }
  // a person's round picture for a row: their photo, or their initials on their colour
  private static func avatar(_ r: Row) -> UIImage? {
    guard r.pic != nil || r.initials != nil else { return nil }
    let size = CGSize(width: 30, height: 30)
    return UIGraphicsImageRenderer(size: size).image { _ in
      let rect = CGRect(origin: .zero, size: size)
      UIBezierPath(ovalIn: rect).addClip()
      if let p = r.pic { p.draw(in: rect); return }
      (r.picColor ?? .systemGray).setFill(); UIRectFill(rect)
      let t = (r.initials ?? "") as NSString
      let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor.white]
      let ts = t.size(withAttributes: attrs)
      t.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
    }
  }
  // Sized from the list alone, once (and again only if the list itself changes) — never from the sheet's own size,
  // which iOS stretches while it's pulled: re-sizing then made the options jump at the end of a scroll.
  private var lastContent: CGFloat = -1
  private var hiddenBelow: CGFloat?   // (how much of this sheet's own view lies below its visible bottom edge — measured once shown)
  private var scrolls = false
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    table.layoutIfNeeded()
    let ch = table.contentSize.height
    guard abs(ch - lastContent) > 0.5 else { return }
    if searchBar != nil && lastContent >= 0 { lastContent = ch; return }   // (searching never re-sizes the sheet)
    // (first time: start at the very top of the list, below the room for the grab handle — with the insets set by
    //  hand a table otherwise starts at 0, which hid that room and put the first option against the handle)
    if lastContent < 0 { table.contentOffset = CGPoint(x: 0, y: -table.adjustedContentInset.top) }
    lastContent = ch
    resize()
  }
  private func resize() {
    let ch = table.contentSize.height
    // (iOS adds the home-bar strip below a sheet's height by itself — on a floating sheet too, where it just showed
    //  as empty space under the last option — so that strip is taken off here)
    let strip = presentingViewController?.view.window?.safeAreaInsets.bottom ?? view.window?.safeAreaInsets.bottom ?? 0
    // (with a search box: its bottom — before it's laid out, where it will be — plus the list's own gap)
    let above: CGFloat = searchBar.map { sb in (sb.frame.maxY > 0 ? sb.frame.maxY : NativeSheetVC.TOP - 10 + 56) + table.contentInset.top } ?? NativeSheetVC.TOP
    fitHeight = max(120, above + ch + NativeSheetVC.END - (floating ? strip : 0) + (floating ? 0 : view.safeAreaInsets.bottom))
    // (a list too long for the sheet scrolls: at the end of the scroll its last option must clear the sheet's visible
    //  bottom edge by the same gap as a fitting list (Channel) — whatever of the sheet lies below that edge is added
    //  (measured once shown; until then iOS's home-bar strip). A list that fits gets none, so it never scrolls — the
    //  finger moves the sheet.)
    let cap = ((presentingViewController?.view.bounds.height ?? view.window?.bounds.height ?? 800) - 60) * 0.68
    scrolls = fitHeight > cap
    // (measured in the simulator: none of a floating sheet lies below its visible edge — 0 until measured)
    let below = floating ? (hiddenBelow ?? 0) : view.safeAreaInsets.bottom
    // (a list that scrolls gets iOS's own room at its end — the space Apple leaves under a long list in a sheet —
    //  instead of a gap worked out here: with ours the last option was squeezed under the bottom edge while the list
    //  scrolled, Haris 2026-10-30. A list that fits keeps the Channel gap and doesn't scroll.)
    table.contentInsetAdjustmentBehavior = scrolls ? .automatic : .never
    table.contentInset.bottom = scrolls ? NativeSheetVC.END : NativeSheetVC.END + (!floating ? below : 0)
    if scrolls { table.layoutIfNeeded(); if table.contentOffset.y < -table.adjustedContentInset.top { table.contentOffset.y = -table.adjustedContentInset.top } }
    table.verticalScrollIndicatorInsets.bottom = 22 + (scrolls ? below : 0)
    sheetPresentationController?.animateChanges { sheetPresentationController?.invalidateDetents() }
  }
  // Once on screen, the real edges are measured (the bottom edge has differed between iOS versions and between
  // fitting and scrolling sheets — the last option ended up under the rounded edge, "Remove from team"): a scrolling
  // one gets whatever of it lies below that edge added to the room at its end.
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard floating, let g = edges() else { return }
    if scrolls && abs(g.hidden - (hiddenBelow ?? 0)) > 0.5 { hiddenBelow = g.hidden; resize() } else { hiddenBelow = g.hidden }
  }
  // the sheet's visible bottom edge, how much of this view is below it, and the gap under the last option's card
  // (in a list that fits; at the very end of the scroll in one that scrolls) — also read by the self-test
  func edges() -> (hidden: CGFloat, endGap: CGFloat, card: CGRect, topGap: CGFloat)? {
    guard let win = view.window else { return nil }
    let cardView: UIView = sheetPresentationController?.presentedView ?? view
    let card = cardView.convert(cardView.bounds, to: win)
    let visBottom = min(card.maxY, win.bounds.maxY)
    let hidden = max(0, view.convert(view.bounds, to: win).maxY - visBottom)
    let maxOffset = max(-table.contentInset.top, table.contentSize.height + table.contentInset.bottom - table.bounds.height)
    // (where the list is now — the self-test scrolls it to the end first; a sheet's own room is set by resize(), not by this)
    let atEnd = table.contentOffset.y; _ = maxOffset
    let tableTop = table.superview?.convert(table.frame, to: win).minY ?? 0
    // (the last option's card itself — the list has ~20 of its own after its last section)
    let ls = sections.count - 1
    let lastRow = ls >= 0 && !sections[ls].rows.isEmpty ? table.rectForRow(at: IndexPath(row: sections[ls].rows.count - 1, section: ls)).maxY : table.contentSize.height
    var lastBottom = tableTop + lastRow - atEnd
    // (the last option's real place on screen when it's showing — the sum above came out ~8 short at the end of a scroll
    // although the screenshots showed the same gap as in a list that fits)
    if ls >= 0, !sections[ls].rows.isEmpty, let cell = table.cellForRow(at: IndexPath(row: sections[ls].rows.count - 1, section: ls)) { lastBottom = cell.convert(cell.bounds, to: win).maxY }
    // (the first thing's top when scrolled to the start: the first card, or a title's text — the header is exactly its text + gap)
    let firstTop = tableTop + table.contentInset.top
    return (hidden, visBottom - lastBottom, card, firstTop - card.minY)
  }
  func geo() -> [String: Any] {
    guard let g = edges() else { return ["error": "not shown"] }
    return ["card": [g.card.minX, g.card.minY, g.card.width, g.card.height], "hiddenBelow": g.hidden, "endGap": g.endGap,
            "topGap": g.topGap, "scrolls": scrolls, "fitHeight": fitHeight, "end": NativeSheetVC.END, "insetBottom": table.contentInset.bottom,
            "content": table.contentSize.height, "offset": table.contentOffset.y, "titled": sections.first?.header != nil]
  }
  func scrollToEnd() {
    table.setContentOffset(CGPoint(x: 0, y: max(-table.contentInset.top, table.contentSize.height + table.contentInset.bottom - table.bounds.height)), animated: false)
  }
  // Each row's height, worked out here (exact, no estimates — estimates made the list jump while scrolling, and
  // without them iOS would squeeze every row to the default height)
  func tableView(_ tableView: UITableView, heightForRowAt ip: IndexPath) -> CGFloat {
    let r = sections[ip.section].rows[ip.row]
    if let chips = r.chips {
      switch r.chipKind {
      case "num": let lines = CGFloat((chips.count + 4) / 5); return lines * 44 + (lines - 1) * 10 + 24
      case "emoji": return 46 + 20
      default: return 30 + 20
      }
    }
    return r.sub == nil ? 52 : 66
  }
  func numberOfSections(in tableView: UITableView) -> Int { sections.count }
  func tableView(_ tableView: UITableView, numberOfRowsInSection s: Int) -> Int { sections[s].rows.count }
  func tableView(_ tableView: UITableView, titleForHeaderInSection s: Int) -> String? { sections[s].header }
  // Every section title is drawn here (not iOS's own), so its place is exact: its text sits TITLE_GAP above its card,
  // and a first section's title starts TOP under the sheet's top edge — where the first option starts on a sheet with
  // no title (Channel). A person's title has their round picture first (their photo, or initials on their colour).
  func tableView(_ tableView: UITableView, viewForHeaderInSection s: Int) -> UIView? {
    let sec = sections[s]
    guard let title = sec.header else { return nil }
    let v = UIView()
    let label = UILabel(); label.text = title; label.textColor = .secondaryLabel
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(label)
    var cs = [label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -NativeSheetVC.TITLE_GAP),
              label.heightAnchor.constraint(equalToConstant: NativeSheetVC.TITLE_H),
              label.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -20)]
    if sec.photo != nil || sec.initials != nil {
      let pic = UIImageView(); pic.layer.cornerRadius = 11; pic.clipsToBounds = true; pic.contentMode = .scaleAspectFill
      let ini = UILabel(); ini.font = .systemFont(ofSize: 10, weight: .bold); ini.textColor = .white; ini.textAlignment = .center
      if let p = sec.photo { pic.image = p } else { pic.backgroundColor = sec.color ?? .systemGray; ini.text = sec.initials }
      [pic, ini].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; v.addSubview($0) }
      cs += [pic.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20), pic.centerYAnchor.constraint(equalTo: label.centerYAnchor),
             pic.widthAnchor.constraint(equalToConstant: 22), pic.heightAnchor.constraint(equalToConstant: 22),
             ini.centerXAnchor.constraint(equalTo: pic.centerXAnchor), ini.centerYAnchor.constraint(equalTo: pic.centerYAnchor),
             label.leadingAnchor.constraint(equalTo: pic.trailingAnchor, constant: 8)]
    } else {
      cs.append(label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 17))
    }
    NSLayoutConstraint.activate(cs)
    return v
  }
  // (a first section's title is just its text + gap, so the text starts at TOP like a first card; later titles get room above)
  func tableView(_ tableView: UITableView, heightForHeaderInSection s: Int) -> CGFloat {
    sections[s].header == nil ? (s == 0 ? .leastNonzeroMagnitude : 12) : NativeSheetVC.TITLE_H + NativeSheetVC.TITLE_GAP + (s == 0 ? 0 : 14)
  }
  func tableView(_ tableView: UITableView, heightForFooterInSection s: Int) -> CGFloat { .leastNonzeroMagnitude }
  func tableView(_ tableView: UITableView, viewForFooterInSection s: Int) -> UIView? { UIView() }
  // (iOS 26 floats a short sheet above the bottom edge: no home-indicator padding inside it then)
  private var floating: Bool { if #available(iOS 26, *) { return true } else { return false } }
  func tableView(_ tableView: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let r = sections[ip.section].rows[ip.row]
    if let chips = r.chips { return chipCell(chips, kind: r.chipKind) }
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.insetsLayoutMarginsFromSafeArea = false; cell.contentView.insetsLayoutMarginsFromSafeArea = false
    var c = r.sub == nil ? cell.defaultContentConfiguration() : UIListContentConfiguration.subtitleCell()
    c.text = r.label
    c.secondaryText = r.sub
    c.secondaryTextProperties.color = .secondaryLabel
    // (accent: the words and the icon in blue — Turn on link)
    // (red: in red where it is, not moved down with Delete — Turn off link)
    let tint: UIColor = r.disabled ? .tertiaryLabel : r.danger || r.red ? .systemRed : r.accent ? .systemBlue : .label
    c.textProperties.color = r.disabled ? .secondaryLabel : r.danger || r.red ? .systemRed : r.accent ? .systemBlue : .label
    if let av = NativeSheetVC.avatar(r) {
      c.image = av
      c.imageProperties.maximumSize = CGSize(width: 30, height: 30)
      c.imageProperties.reservedLayoutSize = CGSize(width: 30, height: 30)
    } else if let dot = r.dot {
      c.image = UIImage(systemName: "circle.fill")?.withTintColor(dot, renderingMode: .alwaysOriginal)
      c.imageProperties.maximumSize = CGSize(width: 12, height: 12)
    } else if let name = r.icon.flatMap({ NativeSheetVC.SYMBOLS[$0] }), let img = UIImage(systemName: name) {
      c.image = img; c.imageProperties.tintColor = r.tint ?? tint
    }
    if r.locked { c.textProperties.color = .secondaryLabel }
    cell.contentConfiguration = c
    cell.accessoryType = (ticks[r.i] ?? r.checked) ? .checkmark : .none
    if r.locked && !r.checked { let lock = UIImageView(image: UIImage(systemName: "lock.fill")); lock.tintColor = .tertiaryLabel; cell.accessoryView = lock }
    cell.tintColor = .systemBlue
    cell.selectionStyle = r.disabled || r.i < 0 ? .none : .default
    if #available(iOS 26, *) { cell.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6) }
    return cell
  }
  func tableView(_ tableView: UITableView, shouldHighlightRowAt ip: IndexPath) -> Bool { let r = sections[ip.section].rows[ip.row]; return r.chips == nil && !r.disabled && (r.i >= 0 || r.i == -2) }
  func tableView(_ tableView: UITableView, didSelectRowAt ip: IndexPath) {
    let r = sections[ip.section].rows[ip.row]
    if r.i == -2 { searchBar?.resignFirstResponder(); choose(-2, searchBar?.text?.trimmingCharacters(in: .whitespaces)); return }   // (the typed entry)
    guard r.chips == nil, !r.disabled, r.i >= 0 else { return }
    // ticking several (channels…): the sheet stays open, the tick flips here, the page is told each time
    if multi && r.multi {
      tableView.deselectRow(at: ip, animated: true)
      let now = !(ticks[r.i] ?? r.checked)
      ticks[r.i] = now
      if let cell = tableView.cellForRow(at: ip) { cell.accessoryType = now ? .checkmark : .none }
      UISelectionFeedbackGenerator().selectionChanged()
      pick?(r.i)
      return
    }
    choose(r.i, nil)
  }
  private var instant = false
  private func choose(_ i: Int, _ swatch: String?) {
    guard let a = answer else { return }
    answer = nil
    // (instant: the page changes and the tap is felt the moment the row is touched, while the sheet slides away —
    //  they came only once it had gone, Haris 2026-11-02)
    if instant { if i >= 0 { UISelectionFeedbackGenerator().selectionChanged() }; pick?(i); dismiss(animated: true) { a(i, swatch) }; return }
    dismiss(animated: true) { a(i, swatch) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { let a = answer; answer = nil; a?(-1, nil) }
  // Priority numbers: all in view, in rows of five (as on the page), each one round
  private func numGrid(_ chips: [Chip]) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.insetsLayoutMarginsFromSafeArea = false; cell.contentView.insetsLayoutMarginsFromSafeArea = false
    cell.selectionStyle = .none
    if #available(iOS 26, *) { cell.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6) }
    let rows = UIStackView(); rows.axis = .vertical; rows.spacing = 10
    stride(from: 0, to: chips.count, by: 5).forEach { start in
      let line = UIStackView(); line.axis = .horizontal; line.distribution = .equalSpacing; line.alignment = .center
      for ch in chips[start..<min(start + 5, chips.count)] {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 52).isActive = true
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.layer.cornerRadius = 12; b.layer.cornerCurve = .continuous
        b.isEnabled = !ch.disabled
        b.setTitle(ch.label ?? "", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.backgroundColor = ch.on ? .systemBlue : .tertiarySystemFill
        b.setTitleColor(ch.on ? .white : .label, for: .normal)
        b.setTitleColor(.quaternaryLabel, for: .disabled)
        b.addAction(UIAction { [weak self] _ in self?.choose(ch.i, nil) }, for: .touchUpInside)
        line.addArrangedSubview(b)
      }
      // (a short last row keeps the same spacing as the full ones)
      for _ in 0..<(5 - min(5, chips.count - start)) { let gap = UIView(); gap.translatesAutoresizingMaskIntoConstraints = false; gap.widthAnchor.constraint(equalToConstant: 52).isActive = true; line.addArrangedSubview(gap) }
      rows.addArrangedSubview(line)
    }
    rows.translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.addSubview(rows)
    NSLayoutConstraint.activate([
      rows.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
      rows.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
      rows.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
      rows.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
    ])
    return cell
  }
  // A row of round choices: colours (swatch), emoji (reactions — drawn as SF Symbols) or numbers (priority). Scrolls
  // sideways if it doesn't fit.
  private func chipCell(_ chips: [Chip], kind: String) -> UITableViewCell {
    if kind == "num" { return numGrid(chips) }
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.insetsLayoutMarginsFromSafeArea = false; cell.contentView.insetsLayoutMarginsFromSafeArea = false
    cell.selectionStyle = .none
    if #available(iOS 26, *) { cell.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6) }
    let size: CGFloat = kind == "emoji" ? 46 : kind == "swatch" ? 30 : 38
    let scroll = UIScrollView(); scroll.showsHorizontalScrollIndicator = false
    let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = kind == "emoji" ? 8 : 10; stack.alignment = .center
    if kind == "emoji" { stack.distribution = .equalSpacing }
    for ch in chips {
      let b = UIButton(type: .system)
      b.translatesAutoresizingMaskIntoConstraints = false
      b.widthAnchor.constraint(equalToConstant: size).isActive = true
      b.heightAnchor.constraint(equalToConstant: size).isActive = true
      b.layer.cornerRadius = size / 2
      b.isEnabled = !ch.disabled
      if kind == "swatch" {
        b.backgroundColor = ch.color ?? .systemGray
        if ch.on { b.layer.borderWidth = 3; b.layer.borderColor = UIColor.label.cgColor }
      } else {
        // (the reactions as SF Symbols in iPhone's colours — Haris 2026-11-04; still saved as their emoji)
        if kind == "emoji", let img = ReactionSym.image(ch.label ?? "", size: 17) { b.setImage(img, for: .normal) }
        else { b.setTitle(ch.label ?? "", for: .normal) }
        b.titleLabel?.font = kind == "emoji" ? .systemFont(ofSize: 26) : .systemFont(ofSize: 16, weight: .semibold)
        b.backgroundColor = ch.on ? .systemBlue : .tertiarySystemFill
        b.setTitleColor(ch.on ? .white : .label, for: .normal)
        b.setTitleColor(.quaternaryLabel, for: .disabled)
        if ch.on && kind == "emoji" { b.backgroundColor = .tertiarySystemFill; b.layer.borderWidth = 2; b.layer.borderColor = UIColor.systemBlue.cgColor }
      }
      b.addAction(UIAction { [weak self] _ in self?.choose(ch.swatch == nil ? ch.i : -1, ch.swatch) }, for: .touchUpInside)
      stack.addArrangedSubview(b)
    }
    scroll.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    cell.contentView.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
      scroll.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
      scroll.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
      scroll.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10),
      scroll.heightAnchor.constraint(equalToConstant: size),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
    ])
    if kind == "emoji" { stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor).isActive = true }
    return cell
  }
}


/* A person's round picture: their photo, or their initials on their colour */
func roundPic(_ pic: UIImage?, initials: String?, color: UIColor?, size: CGFloat) -> UIImage {
  let s = CGSize(width: size, height: size)
  return UIGraphicsImageRenderer(size: s).image { _ in
    let rect = CGRect(origin: .zero, size: s)
    UIBezierPath(ovalIn: rect).addClip()
    (color ?? .systemGray).setFill(); UIRectFill(rect)
    // (filled and cropped to the circle, never stretched)
    if let p = pic, p.size.width > 0, p.size.height > 0 {
      let k = max(size / p.size.width, size / p.size.height), w = p.size.width * k, hh = p.size.height * k
      p.draw(in: CGRect(x: (size - w) / 2, y: (size - hh) / 2, width: w, height: hh)); return
    }
    let t = (initials ?? "") as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size * 0.4, weight: .bold), .foregroundColor: UIColor.white]
    let ts = t.size(withAttributes: attrs)
    t.draw(at: CGPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2), withAttributes: attrs)
  }
}


/* New task / Request amendments as iOS's own sheet with iPhone's own fields (the computer keeps the page's form).
   Pulled down (or tapped outside) with something typed, it tucks into a small bar at the bottom, like a draft in Mail:
   the app behind stays usable; the bar tapped or pulled up brings the form back; the bar pulled down throws the draft
   away. With nothing typed, pulling down just closes it. Client / Assign to are the page's own native sheets, shown on
   top of this one; the page sets what was picked (formSet). Create / Send back asks the page (submit), which closes it
   (formClose) or says what's wrong (an alert). */
final class FormSheetVC: UIViewController, UITableViewDataSource, UITableViewDelegate, UISheetPresentationControllerDelegate, UITextFieldDelegate, UITextViewDelegate {
  static weak var current: FormSheetVC?
  static let TUCK = UISheetPresentationController.Detent.Identifier("tuck")
  static let FORM = UISheetPresentationController.Detent.Identifier("form")
  let key: String
  private let isTask: Bool
  private let dark: Bool
  private let heading: String, dock: String, note: String?, button: String, need: String
  private let tint: UIColor
  private let showWho: Bool
  private let hasCD: Bool
  private var clientText: String
  private var whoText = ""
  private var whoPic: UIImage?
  private var due: String
  private let event: ([String: Any]) -> Void
  private var answer: (([String: Any]) -> Void)?
  var isOpen: Bool { answer != nil }
  // (tucked: the app's tab bar fades away, so the bar sits alone at the bottom — Haris 2026-10-30)
  var onTuck: ((Bool) -> Void)?
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private let titleField = UITextField()
  private let desc = UITextView()
  private let descHint = UILabel()
  private let cdSwitch = UISwitch()
  private let topBar = UIView()
  private let bar = UIView()          // (the tucked draft)
  private let barText = UILabel()
  private var fitHeight: CGFloat = 420
  private var strip: CGFloat = 0
  private var barTop: NSLayoutConstraint?
  private var dirtyNow = false
  private var focused = false
  private let fmt: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f }()
  private var floating: Bool { if #available(iOS 26, *) { return true } else { return false } }
  // (the form sized to fit — iOS keeps it above the keyboard; the tucked bar: a 62-point card, as tall as the tab bar's pill)
  private var formDetent: UISheetPresentationController.Detent {
    .custom(identifier: FormSheetVC.FORM) { [weak self] ctx in min(ctx.maximumDetentValue, self?.fitHeight ?? 420) }
  }
  private var tuckDetent: UISheetPresentationController.Detent {
    .custom(identifier: FormSheetVC.TUCK) { _ in
      // (the card's own height on screen: iOS adds nothing under a sheet this small — self-test 2026-10-30 showed a
      //  24-point card when the home-bar strip was taken off here, and the title and Continue were cut off; 62 = the
      //  height of the tab bar's own pill, Haris 2026-10-30)
      62
    }
  }

  init(_ a: [String: Any], dark: Bool, event: @escaping ([String: Any]) -> Void, answer: @escaping ([String: Any]) -> Void) {
    key = a["key"] as? String ?? ""
    isTask = (a["kind"] as? String) == "task"
    self.dark = dark
    heading = a["title"] as? String ?? ""
    dock = a["dock"] as? String ?? "Draft"
    note = (a["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    button = a["button"] as? String ?? "Done"
    need = a["required"] as? String ?? ""
    tint = (a["color"] as? String) == "amber" ? UIColor(red: 0.96, green: 0.62, blue: 0.11, alpha: 1) : .systemBlue
    showWho = a["assign"] is [String: Any]
    hasCD = a["cd"] is Bool
    clientText = a["client"] as? String ?? ""
    due = a["due"] as? String ?? ""
    self.event = event
    self.answer = answer
    super.init(nibName: nil, bundle: nil)
    FormSheetVC.current = self
    if let w = a["assign"] as? [String: Any] { setWho(w) }
    cdSwitch.isOn = (a["cd"] as? Bool) == true
    titleField.placeholder = a["titleHint"] as? String
    descHint.text = a["descHint"] as? String
    overrideUserInterfaceStyle = dark ? .dark : .light
    modalPresentationStyle = .pageSheet
    if let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first { strip = w.safeAreaInsets.bottom }
    if let sh = sheetPresentationController {
      sh.detents = [formDetent]
      sh.selectedDetentIdentifier = FormSheetVC.FORM
      // (the app behind stays usable when tucked — set only while the tucked height exists: pulled down to close with
      //  nothing typed, iOS crashed looking for it, Haris 2026-10-30)
      sh.largestUndimmedDetentIdentifier = nil
      sh.prefersGrabberVisible = true
      sh.prefersScrollingExpandsWhenScrolledToEdge = false
      sh.delegate = self
    }
  }
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26, *) { view.backgroundColor = .clear; table.backgroundColor = .clear }
    else { view.backgroundColor = .systemGroupedBackground; table.backgroundColor = .systemGroupedBackground }
    // the top: Cancel and the form's name
    let cancel = UIButton(type: .system)
    cancel.setTitle("Cancel", for: .normal); cancel.titleLabel?.font = .systemFont(ofSize: 17)
    cancel.addAction(UIAction { [weak self] _ in self?.finish("cancel") }, for: .touchUpInside)
    let name = UILabel(); name.text = heading; name.font = .systemFont(ofSize: 17, weight: .semibold); name.textAlignment = .center
    [cancel, name].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; topBar.addSubview($0) }
    topBar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(topBar)
    // the fields
    titleField.font = .systemFont(ofSize: 17); titleField.returnKeyType = .next; titleField.delegate = self
    titleField.clearButtonMode = .whileEditing; titleField.autocapitalizationType = .sentences
    titleField.addAction(UIAction { [weak self] _ in self?.changed() }, for: .editingChanged)
    desc.font = .systemFont(ofSize: 17); desc.backgroundColor = .clear; desc.delegate = self
    desc.textContainerInset = UIEdgeInsets(top: 15, left: 0, bottom: 12, right: 0); desc.textContainer.lineFragmentPadding = 0
    descHint.font = .systemFont(ofSize: 17); descHint.textColor = .placeholderText; descHint.numberOfLines = 0
    cdSwitch.addAction(UIAction { _ in UISelectionFeedbackGenerator().selectionChanged() }, for: .valueChanged)
    table.dataSource = self; table.delegate = self
    table.translatesAutoresizingMaskIntoConstraints = false
    table.contentInsetAdjustmentBehavior = .never
    table.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: NativeSheetVC.END, right: 0)
    table.estimatedRowHeight = 0; table.estimatedSectionHeaderHeight = 0; table.estimatedSectionFooterHeight = 0
    table.sectionHeaderTopPadding = 0
    table.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude))
    table.tableFooterView = UIView(frame: .zero)
    table.keyboardDismissMode = .interactive
    table.alwaysBounceVertical = false
    table.insetsContentViewsToSafeArea = false
    table.insetsLayoutMarginsFromSafeArea = false
    view.addSubview(table)
    // the tucked draft: "New task · its title" … Continue
    bar.translatesAutoresizingMaskIntoConstraints = false; bar.alpha = 0; bar.isHidden = true
    barText.translatesAutoresizingMaskIntoConstraints = false; barText.lineBreakMode = .byTruncatingTail
    let go = UIButton(type: .system); go.setTitle("Continue", for: .normal); go.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    go.translatesAutoresizingMaskIntoConstraints = false
    go.setContentCompressionResistancePriority(.required, for: .horizontal)
    go.addAction(UIAction { [weak self] _ in self?.expand() }, for: .touchUpInside)
    bar.addSubview(barText); bar.addSubview(go)
    bar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(barTapped)))
    view.addSubview(bar)
    NSLayoutConstraint.activate([
      topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14), topBar.heightAnchor.constraint(equalToConstant: 44),
      topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      cancel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 20), cancel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      name.centerXAnchor.constraint(equalTo: topBar.centerXAnchor), name.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
      name.leadingAnchor.constraint(greaterThanOrEqualTo: cancel.trailingAnchor, constant: 8),
      table.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4), table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bar.heightAnchor.constraint(equalToConstant: 48),
      bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      barText.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24), barText.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
      go.leadingAnchor.constraint(greaterThanOrEqualTo: barText.trailingAnchor, constant: 10),
      go.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -22), go.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
    ])
    barTop = bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 10)
    barTop?.isActive = true
  }
  // Where the sheet's card shows on screen, in this view (tucked, iOS 26 showed only a slice of this view, not its top
  // — the bar sat outside it, Haris 2026-10-30): the bar goes just under the card's visible top
  private func visibleCard() -> CGRect {
    guard let win = view.window else { return view.bounds }
    let cardView: UIView = sheetPresentationController?.presentedView ?? view
    let card = cardView.convert(cardView.bounds, to: win).intersection(win.bounds)
    // (sliding away off the screen there's nothing in view: an empty rectangle has endless edges — giving that to the
    //  bar crashed the app when an empty form was pulled down, crash report 2026-10-30)
    if card.isNull || card.isEmpty { return view.bounds }
    return view.convert(card, from: win)
  }
  private func placeBar() {
    guard isOpen, !isBeingDismissed else { return }
    let c = visibleCard()
    guard c.minY.isFinite, c.height.isFinite else { return }
    // (the title and Continue in the very middle of the card's height — Haris 2026-10-30)
    let top = max(0, c.minY) + max(0, (min(c.height, 70) - 48) / 2)
    if abs((barTop?.constant ?? 0) - top) > 0.5 { barTop?.constant = top }
  }
  func geo() -> [String: Any] {
    guard let win = view.window else { return ["error": "not shown"] }
    let f = { (v: UIView) -> [CGFloat] in let r = v.convert(v.bounds, to: win); return [r.minX, r.minY, r.width, r.height] }
    return ["view": f(view), "card": f(sheetPresentationController?.presentedView ?? view), "bar": f(bar), "barText": f(barText),
            "barAlpha": bar.alpha, "barHidden": bar.isHidden, "tableAlpha": table.alpha, "tucked": tucked, "text": barText.text ?? "",
            "visible": [visibleCard().minY, visibleCard().height], "fit": fitHeight, "strip": strip]
  }
  func selfFill(_ t: String) { titleField.text = t; changed() }
  static func selfArgs() -> [String: Any] {
    let person: [String: Any] = ["initials": "HA", "color": [120, 90, 220]]
    let assign: [String: Any] = ["label": "Me", "person": person]
    var a: [String: Any] = ["kind": "task", "key": "selftest", "title": "New task", "titleHint": "What needs doing?", "descHint": "Details"]
    a["client"] = "No client (My Tasks)"; a["assign"] = assign; a["due"] = ""; a["cd"] = false
    a["button"] = "Create task"; a["dock"] = "New task"; a["required"] = "title"
    return a
  }
  func selfTuck() { tuck() }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // (New task: no keyboard until a field is tapped — Haris, 2026-10-31; Request amendments still opens typing)
    if !focused { focused = true; if !isTask { _ = desc.becomeFirstResponder() } }
  }
  // sized to the form (its fields as they are — never to the sheet's own size, which iOS changes while it's pulled)
  private var lastWidth: CGFloat = 0
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let w = view.window { strip = w.safeAreaInsets.bottom }
    placeBar()
    if note != nil && abs(table.bounds.width - lastWidth) > 0.5 { lastWidth = table.bounds.width; table.beginUpdates(); table.endUpdates() }
    table.layoutIfNeeded()
    let ch = table.contentSize.height
    guard ch > 0 else { return }
    // (the top bar: 14 + 44 + 4; under the button: END + 10; iOS adds the home-bar strip under a floating sheet)
    var h: CGFloat = 62 + ch + NativeSheetVC.END + 10
    if floating { h -= strip } else { h += view.safeAreaInsets.bottom }
    guard abs(h - fitHeight) > 0.5 else { return }
    fitHeight = h
    sheetPresentationController?.animateChanges { sheetPresentationController?.invalidateDetents() }
  }

  // ---- the rows ----
  private var rows: [[String]] {
    if !isTask { return [["desc"], ["go"]] }
    var fields: [String] = ["client"]
    if showWho { fields.append("who") }
    fields.append("due")
    if hasCD { fields.append("cd") }
    return [["title", "desc"], fields, ["go"]]
  }
  func numberOfSections(in tableView: UITableView) -> Int { rows.count }
  func tableView(_ tableView: UITableView, numberOfRowsInSection s: Int) -> Int { rows[s].count }
  func tableView(_ tableView: UITableView, heightForRowAt ip: IndexPath) -> CGFloat {
    switch rows[ip.section][ip.row] { case "desc": return isTask ? 96 : 150; case "go": return 52; default: return 52 }
  }
  func tableView(_ tableView: UITableView, heightForHeaderInSection s: Int) -> CGFloat {
    if s == 0, let n = note { return noteHeight(n) }
    return s == 0 ? .leastNonzeroMagnitude : (rows[s] == ["go"] ? 20 : 16)
  }
  func tableView(_ tableView: UITableView, viewForHeaderInSection s: Int) -> UIView? {
    guard s == 0, let n = note else { return UIView() }
    let v = UIView()
    let l = UILabel(); l.text = n; l.numberOfLines = 0; l.font = .systemFont(ofSize: 15); l.textColor = .secondaryLabel
    l.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(l)
    NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
                                 l.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),
                                 l.topAnchor.constraint(equalTo: v.topAnchor, constant: 2)])
    return v
  }
  private func noteHeight(_ n: String) -> CGFloat {
    let w = max(200, (table.bounds.width > 0 ? table.bounds.width : view.bounds.width) - 40)
    let r = (n as NSString).boundingRect(with: CGSize(width: w, height: 400), options: [.usesLineFragmentOrigin],
                                         attributes: [.font: UIFont.systemFont(ofSize: 15)], context: nil)
    return ceil(r.height) + 2 + 12
  }
  func tableView(_ tableView: UITableView, heightForFooterInSection s: Int) -> CGFloat { .leastNonzeroMagnitude }
  func tableView(_ tableView: UITableView, viewForFooterInSection s: Int) -> UIView? { UIView() }
  private func put(_ v: UIView, in cell: UITableViewCell, _ i: UIEdgeInsets) {
    v.removeFromSuperview(); v.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(v)
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: i.left),
                                 v.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -i.right),
                                 v.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: i.top),
                                 v.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -i.bottom)])
  }
  // (a picker row's end: the person's picture, if any, then iOS's up-down chevron)
  private func pickerEnd(_ pic: UIImage?) -> UIView {
    let chev = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)))
    chev.tintColor = .tertiaryLabel
    let cs = chev.intrinsicContentSize
    guard let p = pic else { chev.frame = CGRect(origin: .zero, size: cs); return chev }
    let v = UIView(frame: CGRect(x: 0, y: 0, width: 26 + 8 + cs.width, height: 26))
    let iv = UIImageView(image: p); iv.frame = CGRect(x: 0, y: 0, width: 26, height: 26)
    chev.frame = CGRect(x: 34, y: (26 - cs.height) / 2, width: cs.width, height: cs.height)
    v.addSubview(iv); v.addSubview(chev)
    return v
  }
  func tableView(_ tableView: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let id = rows[ip.section][ip.row]
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.insetsLayoutMarginsFromSafeArea = false; cell.contentView.insetsLayoutMarginsFromSafeArea = false
    if #available(iOS 26, *) { cell.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6) }
    cell.selectionStyle = .none
    switch id {
    case "title": put(titleField, in: cell, UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 12))
    case "desc":
      put(desc, in: cell, UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 16))
      descHint.removeFromSuperview(); descHint.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(descHint)
      NSLayoutConstraint.activate([descHint.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
                                   descHint.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                                   descHint.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 15)])
      descHint.isHidden = !desc.text.isEmpty
    case "client", "who", "due":
      var c = UIListContentConfiguration.valueCell()
      c.text = id == "client" ? "Client" : id == "who" ? "Assign to" : "Due"
      c.secondaryText = id == "client" ? clientText : id == "who" ? whoText : dueText()
      if id == "due" && !due.isEmpty { c.secondaryTextProperties.color = .systemBlue }
      cell.contentConfiguration = c
      cell.selectionStyle = .default
      if id != "due" { cell.accessoryView = pickerEnd(id == "who" ? whoPic : nil) }
    case "cd":
      var c = cell.defaultContentConfiguration(); c.text = "CD review"
      cell.contentConfiguration = c
      cell.accessoryView = cdSwitch
    case "go":
      cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
      var bc = UIButton.Configuration.filled()
      bc.cornerStyle = .capsule; bc.baseBackgroundColor = tint; bc.baseForegroundColor = .white
      bc.title = button
      let b = UIButton(configuration: bc)
      b.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
      put(b, in: cell, .zero)
    default: break
    }
    return cell
  }
  func tableView(_ tableView: UITableView, shouldHighlightRowAt ip: IndexPath) -> Bool { ["client", "who", "due"].contains(rows[ip.section][ip.row]) }
  func tableView(_ tableView: UITableView, didSelectRowAt ip: IndexPath) {
    tableView.deselectRow(at: ip, animated: true)
    let id = rows[ip.section][ip.row]
    switch id {
    case "client", "who": view.endEditing(true); event(["ev": "pick", "key": key, "field": id])
    case "due": pickDue()
    default: break
    }
  }
  private func reloadRow(_ id: String) {
    for (s, list) in rows.enumerated() { if let r = list.firstIndex(of: id) { table.reloadRows(at: [IndexPath(row: r, section: s)], with: .none) } }
  }
  private func dueText() -> String {
    guard let d = fmt.date(from: due) else { return "None" }
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInTomorrow(d) { return "Tomorrow" }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_GB")
    f.setLocalizedDateFormatFromTemplate(cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEEdMMM" : "EEEdMMMyyyy")
    return f.string(from: d)
  }
  private func pickDue() {
    view.endEditing(true)
    present(DateSheetVC(["value": due, "clearable": true], dark: dark) { [weak self] r in
      guard let self else { return }
      if (r["clear"] as? Bool) == true { self.due = "" } else if let d = r["date"] as? String { self.due = d } else { return }
      self.reloadRow("due")
    }, animated: true)
  }
  private func setWho(_ w: [String: Any]) {
    whoText = w["label"] as? String ?? ""
    whoPic = (w["person"] as? [String: Any]).map { p in roundPic(NativeSheetVC.photo(p), initials: p["initials"] as? String, color: NativeSheetVC.color(p["color"]), size: 26) }
  }
  // from the page: what was picked, CD review on / off, or what's wrong
  func set(_ a: [String: Any]) {
    if let c = a["client"] as? String { clientText = c; reloadRow("client") }
    if let w = a["assign"] as? [String: Any] { setWho(w); reloadRow("who") }
    if let cd = a["cd"] as? Bool { cdSwitch.setOn(cd, animated: true) }
    if let msg = a["alert"] as? String {
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      let al = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
      al.addAction(UIAlertAction(title: "OK", style: .default))
      (presentedViewController ?? self).present(al, animated: true)
    }
  }

  // ---- typing, tucking ----
  private var dirty: Bool {
    !(titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !desc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  private func changed() {
    descHint.isHidden = !desc.text.isEmpty
    let d = dirty
    guard d != dirtyNow, let sh = sheetPresentationController else { return }
    dirtyNow = d
    // (something typed: it can tuck, and pulling it down tucks it instead of closing it)
    isModalInPresentation = d && !tucked
    sh.animateChanges {
      sh.detents = d ? [tuckDetent, formDetent] : [formDetent]
      sh.largestUndimmedDetentIdentifier = d ? FormSheetVC.TUCK : nil
      if !tucked { sh.selectedDetentIdentifier = FormSheetVC.FORM }
    }
  }
  func textViewDidChange(_ textView: UITextView) { changed() }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool { desc.becomeFirstResponder(); return false }
  private var tucked: Bool { sheetPresentationController?.selectedDetentIdentifier == FormSheetVC.TUCK }
  func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) { applyMode() }
  private func applyMode() {
    let t = tucked
    if t {
      view.endEditing(true)
      let first = (isTask ? (titleField.text ?? "") : desc.text).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
      let s = NSMutableAttributedString(string: dock, attributes: [.font: UIFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: UIColor.label])
      if !first.isEmpty { s.append(NSAttributedString(string: " · " + first, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.secondaryLabel])) }
      barText.attributedText = s
    }
    isModalInPresentation = dirty && !t   // (tucked: pulled down, the draft goes)
    bar.isHidden = false
    view.setNeedsLayout()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.placeBar() }
    UIView.animate(withDuration: 0.2, animations: {
      self.bar.alpha = t ? 1 : 0; self.table.alpha = t ? 0 : 1; self.topBar.alpha = t ? 0 : 1
    }, completion: { _ in self.bar.isHidden = !self.tucked })
    onTuck?(t)
  }
  @objc private func barTapped() { expand() }
  func expand() {
    guard let sh = sheetPresentationController, tucked else { return }
    sh.animateChanges { sh.selectedDetentIdentifier = FormSheetVC.FORM }
    applyMode()
  }
  private func tuck() {
    guard dirty, let sh = sheetPresentationController else { return }
    view.endEditing(true)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    sh.animateChanges { sh.selectedDetentIdentifier = FormSheetVC.TUCK }
    applyMode()
  }
  // (tapped outside, or pulled down past the bottom, with something typed: tucked)
  func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { tuck() }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    onTuck?(false)
    let a = answer; answer = nil
    a?(["ok": true, "closed": dirty ? "discard" : "cancel"])
  }

  private func submit() {
    let t = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let d = desc.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if need == "title" && t.isEmpty { UINotificationFeedbackGenerator().notificationOccurred(.warning); titleField.becomeFirstResponder(); return }
    if need == "desc" && d.isEmpty { UINotificationFeedbackGenerator().notificationOccurred(.warning); desc.becomeFirstResponder(); return }
    event(["ev": "submit", "key": key, "title": t, "desc": d, "due": due, "cd": cdSwitch.isOn])
  }
  // closed: submit (the page did it) / cancel / replaced (another form opened instead)
  func finish(_ reason: String, then: (() -> Void)? = nil) {
    guard let a = answer else { then?(); return }
    answer = nil
    view.endEditing(true)
    onTuck?(false)
    let done = { a(["ok": true, "closed": reason]); then?() }
    if let p = presentingViewController { p.dismiss(animated: true, completion: done) } else { done() }
  }
}


/* A task in the Trash, to look at (nothing can be changed there): iOS's own tall sheet — the Trash bar with Restore,
   the task's details, its description, subtasks, checklist, files (tapped: the page previews it, then brings this
   back) and comments. */
final class TrashSheetVC: UIViewController, UISheetPresentationControllerDelegate {
  private let a: [String: Any]
  private let dark: Bool
  private var answer: (([String: Any]) -> Void)?
  private let scroll = UIScrollView()
  private let stack = UIStackView()
  init(_ a: [String: Any], dark: Bool, answer: @escaping ([String: Any]) -> Void) {
    self.a = a; self.dark = dark; self.answer = answer
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = dark ? .dark : .light
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController { sh.detents = [.large()]; sh.prefersGrabberVisible = true; sh.delegate = self }
  }
  required init?(coder: NSCoder) { fatalError() }
  private var cardColor: UIColor {
    if #available(iOS 26, *) { return UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6) } else { return .secondarySystemGroupedBackground }
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26, *) { view.backgroundColor = .clear } else { view.backgroundColor = .systemGroupedBackground }
    scroll.translatesAutoresizingMaskIntoConstraints = false; stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical; stack.spacing = 8
    scroll.alwaysBounceVertical = true
    view.addSubview(scroll); scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: NativeSheetVC.TOP),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
    ])
    build()
  }
  private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .label, lines: Int = 0) -> UILabel {
    let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; l.numberOfLines = lines
    return l
  }
  private func padded(_ v: UIView, _ i: UIEdgeInsets) -> UIView {
    let w = UIView(); v.translatesAutoresizingMaskIntoConstraints = false; w.addSubview(v)
    NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: w.leadingAnchor, constant: i.left), v.trailingAnchor.constraint(equalTo: w.trailingAnchor, constant: -i.right),
                                 v.topAnchor.constraint(equalTo: w.topAnchor, constant: i.top), v.bottomAnchor.constraint(equalTo: w.bottomAnchor, constant: -i.bottom)])
    return w
  }
  // a rounded card of rows, with hairlines between them
  private func card(_ rows: [UIView]) -> UIView {
    let c = UIStackView(); c.axis = .vertical
    c.backgroundColor = cardColor; c.layer.cornerRadius = 16; c.layer.cornerCurve = .continuous; c.clipsToBounds = true
    for (i, r) in rows.enumerated() {
      if i > 0 {
        let line = UIView(); line.backgroundColor = .separator; line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        c.addArrangedSubview(padded(line, UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)))
      }
      c.addArrangedSubview(r)
    }
    return c
  }
  private func section(_ title: String, _ count: Int?, _ body: UIView) {
    let t = NSMutableAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.secondaryLabel])
    if let n = count { t.append(NSAttributedString(string: "  \(n)", attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.tertiaryLabel])) }
    let l = UILabel(); l.attributedText = t
    let last = stack.arrangedSubviews.last
    if let last { stack.setCustomSpacing(22, after: last) }
    stack.addArrangedSubview(padded(l, UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)))
    stack.addArrangedSubview(body)
  }
  private func person(_ p: Any?, _ size: CGFloat) -> UIImage {
    let d = p as? [String: Any]
    return roundPic(NativeSheetVC.photo(d), initials: d?["initials"] as? String, color: NativeSheetVC.color(d?["color"]), size: size)
  }
  private func peopleText(_ list: [[String: Any]]) -> NSAttributedString {
    let s = NSMutableAttributedString(), font = UIFont.systemFont(ofSize: 16)
    for (i, p) in list.enumerated() {
      // (each person on a line of their own — Haris 2026-11-04: they ran into each other)
      if i > 0 { s.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: { let ps = NSMutableParagraphStyle(); ps.paragraphSpacingBefore = 6; return ps }()])) }
      let att = NSTextAttachment(); att.image = person(p["person"], 22)
      att.bounds = CGRect(x: 0, y: (font.capHeight - 22) / 2, width: 22, height: 22)
      s.append(NSAttributedString(attachment: att))
      s.append(NSAttributedString(string: " " + (p["name"] as? String ?? ""), attributes: [.font: font, .foregroundColor: UIColor.label]))
    }
    return s
  }
  private func text(_ s: String) -> UITextView {
    let t = UITextView(); t.text = s; t.font = .systemFont(ofSize: 16); t.isEditable = false; t.isScrollEnabled = false
    t.backgroundColor = .clear; t.dataDetectorTypes = [.link]; t.textContainerInset = .zero; t.textContainer.lineFragmentPadding = 0
    return t
  }
  // a file: its picture (or its type), its name under it; tapped → previewed
  private func tile(_ f: [String: Any]) -> UIView {
    let box = UIStackView(); box.axis = .vertical; box.spacing = 4; box.alignment = .leading
    let b = UIButton(type: .custom)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 76).isActive = true; b.heightAnchor.constraint(equalToConstant: 76).isActive = true
    b.layer.cornerRadius = 12; b.layer.cornerCurve = .continuous; b.clipsToBounds = true; b.backgroundColor = .tertiarySystemFill
    if let img = NativeSheetVC.photo(f["thumb"].map { ["photo": $0] }) {
      let iv = UIImageView(image: img); iv.contentMode = .scaleAspectFill; iv.isUserInteractionEnabled = false
      iv.frame = CGRect(x: 0, y: 0, width: 76, height: 76); b.addSubview(iv)
    } else {
      b.setTitle((f["ext"] as? String ?? "file").uppercased(), for: .normal)
      b.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold); b.setTitleColor(.secondaryLabel, for: .normal)
    }
    let id = f["id"] as? String ?? ""
    b.addAction(UIAction { [weak self] _ in self?.finish(["ok": true, "action": "preview", "file": id]) }, for: .touchUpInside)
    let name = label(f["name"] as? String ?? "", size: 11, color: .secondaryLabel, lines: 1); name.lineBreakMode = .byTruncatingMiddle
    name.translatesAutoresizingMaskIntoConstraints = false; name.widthAnchor.constraint(equalToConstant: 76).isActive = true
    box.addArrangedSubview(b); box.addArrangedSubview(name)
    return box
  }
  private func tiles(_ files: [[String: Any]]) -> UIView {
    let sc = UIScrollView(); sc.showsHorizontalScrollIndicator = false
    let row = UIStackView(); row.axis = .horizontal; row.spacing = 10; row.alignment = .top
    files.forEach { row.addArrangedSubview(tile($0)) }
    row.translatesAutoresizingMaskIntoConstraints = false; sc.addSubview(row)
    sc.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: sc.contentLayoutGuide.leadingAnchor), row.trailingAnchor.constraint(equalTo: sc.contentLayoutGuide.trailingAnchor),
                                 row.topAnchor.constraint(equalTo: sc.contentLayoutGuide.topAnchor), row.bottomAnchor.constraint(equalTo: sc.contentLayoutGuide.bottomAnchor),
                                 row.heightAnchor.constraint(equalTo: sc.frameLayoutGuide.heightAnchor), sc.heightAnchor.constraint(equalToConstant: 76 + 4 + 14)])
    return sc
  }
  private func lines(_ list: [[String: Any]], strike: Bool) -> UIView {
    card(list.map { l -> UIView in
      let done = (l["done"] as? Bool) == true
      let ic = UIImageView(image: UIImage(systemName: done ? "checkmark.circle.fill" : "circle"))
      ic.tintColor = done ? .systemGreen : .tertiaryLabel; ic.setContentHuggingPriority(.required, for: .horizontal)
      let t = label(l["t"] as? String ?? "", size: 16, color: done && strike ? .secondaryLabel : .label)
      if done && strike { t.attributedText = NSAttributedString(string: t.text ?? "", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.secondaryLabel]) }
      let r = UIStackView(arrangedSubviews: [ic, t]); r.spacing = 10; r.alignment = .center
      return padded(r, UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16))
    })
  }
  private func build() {
    // the task's name
    stack.addArrangedSubview(padded(label(a["title"] as? String ?? "", size: 22, weight: .bold), UIEdgeInsets(top: 0, left: 4, bottom: 4, right: 4)))
    // In the Trash · who · when · days left, and Restore
    let orange = UIColor.systemOrange
    let barL = label(a["bar"] as? String ?? "", size: 14, color: dark ? orange : UIColor(red: 0.55, green: 0.33, blue: 0, alpha: 1))
    let barRow = UIStackView(arrangedSubviews: [UIImageView(image: UIImage(systemName: "trash")), barL]); barRow.spacing = 10; barRow.alignment = .center
    (barRow.arrangedSubviews[0] as? UIImageView)?.tintColor = barL.textColor
    barRow.arrangedSubviews[0].setContentHuggingPriority(.required, for: .horizontal)
    if (a["canRestore"] as? Bool) == true {
      var bc = UIButton.Configuration.filled(); bc.cornerStyle = .capsule; bc.image = UIImage(systemName: "arrow.uturn.backward"); bc.imagePadding = 6
      bc.title = "Restore"; bc.buttonSize = .medium
      bc.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
      let rb = UIButton(configuration: bc)
      rb.setContentHuggingPriority(.required, for: .horizontal); rb.setContentCompressionResistancePriority(.required, for: .horizontal)
      rb.addAction(UIAction { [weak self] _ in self?.finish(["ok": true, "action": "restore"]) }, for: .touchUpInside)
      barRow.addArrangedSubview(rb)
    }
    let barBox = padded(barRow, UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 12))
    barBox.backgroundColor = orange.withAlphaComponent(0.14); barBox.layer.cornerRadius = 16; barBox.layer.cornerCurve = .continuous
    stack.addArrangedSubview(barBox)
    stack.setCustomSpacing(14, after: barBox)
    // Client, Status, Assignees, Dates, Tags
    let props = (a["props"] as? [[String: Any]] ?? []).map { p -> UIView in
      let k = label(p["label"] as? String ?? "", size: 16, color: .secondaryLabel, lines: 1)
      k.translatesAutoresizingMaskIntoConstraints = false; k.widthAnchor.constraint(equalToConstant: 96).isActive = true
      let v: UIView
      if let people = p["people"] as? [[String: Any]] {
        let l = UILabel(); l.numberOfLines = 0; l.attributedText = people.isEmpty ? NSAttributedString(string: "Nobody", attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.secondaryLabel]) : peopleText(people); v = l
      } else if let st = p["status"] as? [String: Any] {
        let c = NativeSheetVC.color(st["color"]) ?? .systemBlue
        let l = label(st["name"] as? String ?? "", size: 14, weight: .semibold, color: c, lines: 1)
        let pill = padded(l, UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)); pill.backgroundColor = c.withAlphaComponent(0.15); pill.layer.cornerRadius = 8
        let w = UIStackView(arrangedSubviews: [pill, UIView()]); w.alignment = .center; v = w
      } else { v = label(p["text"] as? String ?? "", size: 16) }
      let r = UIStackView(arrangedSubviews: [k, v]); r.spacing = 8; r.alignment = .center
      return padded(r, UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16))
    }
    if !props.isEmpty { stack.addArrangedSubview(card(props)) }
    if let d = a["desc"] as? String, !d.isEmpty { section("Description", nil, card([padded(text(d), UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16))])) }
    if let s = a["subtasks"] as? [[String: Any]], !s.isEmpty { section("Subtasks", s.count, lines(s, strike: false)) }
    if let s = a["checklist"] as? [[String: Any]], !s.isEmpty { section("Checklist", nil, lines(s, strike: true)) }
    if let f = a["files"] as? [[String: Any]], !f.isEmpty { section("Attachments", f.count, card([padded(tiles(f), UIEdgeInsets(top: 12, left: 12, bottom: 10, right: 12))])) }
    let comments = a["comments"] as? [[String: Any]] ?? []
    if comments.isEmpty {
      section("Comments", 0, card([padded(label("No comments", size: 16, color: .secondaryLabel), UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16))]))
      return
    }
    section("Comments", comments.count, card(comments.map { c -> UIView in
        let pic = UIImageView(image: person(c["person"], 28)); pic.translatesAutoresizingMaskIntoConstraints = false
        pic.widthAnchor.constraint(equalToConstant: 28).isActive = true; pic.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let meta = NSMutableAttributedString(string: c["name"] as? String ?? "", attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.label])
        meta.append(NSAttributedString(string: " · " + (c["when"] as? String ?? ""), attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.secondaryLabel]))
        let m = UILabel(); m.attributedText = meta
        let col = UIStackView(arrangedSubviews: [m]); col.axis = .vertical; col.spacing = 4
        if let t = c["text"] as? String, !t.isEmpty { col.addArrangedSubview(text(t)) }
        if let f = c["files"] as? [[String: Any]], !f.isEmpty { col.addArrangedSubview(tiles(f)) }
        let r = UIStackView(arrangedSubviews: [pic, col]); r.spacing = 10; r.alignment = .top
        return padded(r, UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
    }))
  }
  private func finish(_ r: [String: Any]) {
    guard let a = answer else { return }
    answer = nil
    if let p = presentingViewController { p.dismiss(animated: true) { a(r) } } else { a(r) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { let a = answer; answer = nil; a?(["ok": true, "closed": true]) }
}


/* A date picked in a native sheet (the page's date fields on the iPhone): iPhone's own calendar, with Today and —
   when the field can be emptied — Clear. Tapping a day picks it and closes; dragging it down or tapping outside
   changes nothing. */
final class DateSheetVC: UIViewController, UISheetPresentationControllerDelegate, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
  // iPhone's own calendar (the one inside its date picker): today as iPhone marks it, the date picked the filled circle
  private let cal = UICalendarView()
  private let gregorian = Calendar(identifier: .gregorian)
  private var answer: (([String: Any]) -> Void)?
  private let fmt: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f }()
  private let clearable: Bool
  private let md: Bool
  private var titleText: String?, subText: String?
  init(_ a: [String: Any], dark: Bool, answer: @escaping ([String: Any]) -> Void) {
    self.answer = answer
    clearable = (a["clearable"] as? Bool) == true
    md = (a["md"] as? Bool) == true
    titleText = a["title"] as? String; subText = a["sub"] as? String
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = dark ? .dark : .light
    cal.calendar = gregorian
    cal.locale = Locale(identifier: "en_US")
    let pick = UICalendarSelectionSingleDate(delegate: self)
    if let v = a["value"] as? String, let d = fmt.date(from: v) {
      let dc = gregorian.dateComponents([.year, .month, .day], from: d)
      pick.selectedDate = dc
      // (the month only, and set again once on screen — set with its day before the calendar was laid out, its first
      //  swipe forward skipped a month: October → December, Haris 2026-11-01)
      startMonth = DateComponents(calendar: gregorian, year: dc.year, month: dc.month)
      cal.visibleDateComponents = startMonth!
    }
    cal.selectionBehavior = pick
    let lo = (a["min"] as? String).flatMap { fmt.date(from: $0) }, hi = (a["max"] as? String).flatMap { fmt.date(from: $0) }
    if lo != nil || hi != nil { cal.availableDateRange = DateInterval(start: lo ?? .distantPast, end: max(hi ?? .distantFuture, lo ?? .distantPast)) }
    cal.delegate = self
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController {
      // (sized to the calendar, with the same gap under it as under a native list's last option — Channel: END + the
      //  ~18 a list keeps after its last section)
      sh.detents = [.custom(identifier: .init("date")) { [weak self] ctx in min(ctx.maximumDetentValue, self?.fitHeight ?? 470) }]
      sh.prefersGrabberVisible = true
      sh.delegate = self
    }
  }
  // today: only iPhone's own mark for it (no dot of ours — Haris, 2026-11-01)
  func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? { nil }
  // a day tapped: that date
  func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
    guard let dc = dateComponents, let d = gregorian.date(from: dc) else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    finish(["ok": true, "date": fmt.string(from: d)])
  }
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 26, *) { view.backgroundColor = .clear } else { view.backgroundColor = .systemGroupedBackground }
    let today = UIButton(type: .system); today.setTitle("Today", for: .normal); today.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    today.isHidden = md   // (a birthday: day and month only — the year shown doesn't matter)
    today.addAction(UIAction { [weak self] _ in guard let self else { return }; self.finish(["ok": true, "date": self.fmt.string(from: Date())]) }, for: .touchUpInside)
    let clear = UIButton(type: .system); clear.setTitle("Clear", for: .normal); clear.titleLabel?.font = .systemFont(ofSize: 17); clear.tintColor = .systemRed
    clear.isHidden = !clearable
    clear.addAction(UIAction { [weak self] _ in self?.finish(["ok": true, "clear": true]) }, for: .touchUpInside)
    // (a title in the middle, and a line under it — Paid on · the person and the amount: Haris 2026-11-04)
    let head = UIStackView(); head.axis = .vertical; head.alignment = .center; head.spacing = 1
    if let t = titleText, !t.isEmpty { let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: 17, weight: .semibold); head.addArrangedSubview(l) }
    if let t = subText, !t.isEmpty { let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: 13); l.textColor = .secondaryLabel; head.addArrangedSubview(l) }
    [today, clear, cal, head].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    let calTop = cal.topAnchor.constraint(equalTo: today.bottomAnchor, constant: 4); calTop.priority = .defaultHigh
    NSLayoutConstraint.activate([
      clear.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22), clear.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
      today.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22), today.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
      head.centerXAnchor.constraint(equalTo: view.centerXAnchor), head.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
      head.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 90), head.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -90),
      calTop, cal.topAnchor.constraint(greaterThanOrEqualTo: head.bottomAnchor, constant: 8),
      cal.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), cal.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    ])
  }
  private var startMonth: DateComponents?
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if let m = startMonth { startMonth = nil; cal.setVisibleDateComponents(m, animated: false) }
  }
  /* one height for every month (Haris 2026-11-05: the sheet grew and shrank with each month's 5 or 6 week rows, and
     resizing it under the calendar threw it a month or two on — January → March, March → June). Sized once to the
     calendar as iPhone lays it out, with room for six rows like iPhone's own; then never changed while it's open. */
  private var fitHeight: CGFloat = 470, sized = false
  private func fit() {
    let floating: Bool; if #available(iOS 26, *) { floating = true } else { floating = false }
    let strip = presentingViewController?.view.window?.safeAreaInsets.bottom ?? view.window?.safeAreaInsets.bottom ?? 0
    let h = max(320, cal.frame.maxY + NativeSheetVC.END + 18 - (floating ? strip : 0) + (floating ? 0 : view.safeAreaInsets.bottom))
    guard abs(h - fitHeight) > 0.5 else { return }
    fitHeight = h
    DispatchQueue.main.async { [weak self] in
      guard let sh = self?.sheetPresentationController else { return }
      sh.animateChanges { sh.invalidateDetents() }
    }
  }
  // (sized from where it was first laid out — measuring it again inside the layout and resizing from there sent iOS 27's
  //  calendar round in circles until the app crashed: TestFlight report, build 1195)
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard !sized, view.bounds.width > 0, cal.frame.minY > 0, cal.frame.height > 100 else { return }
    sized = true
    fit()
  }
  private func finish(_ r: [String: Any]) {
    guard let a = answer else { return }
    answer = nil
    dismiss(animated: true) { a(r) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { let a = answer; answer = nil; a?(["ok": true, "cancel": true]) }
}

/* The UAE dirham sign (U+20C3), shown as the Central Bank's symbol wherever the app writes an amount — "⃃ 1,250.00",
   as tall as the digits (Haris 2026-11-05). iPhone's own font doesn't have it yet, so the app carries a one-character
   font (web/fonts/e11-dirham.ttf, made by tools/make-dirham-font.py) and every system font it makes falls back to it
   for that character only (a cascade list). Once iOS has the sign itself, nothing is changed. */
enum Dirham {
  static let ch = "\u{20C3}"
  private static var desc: UIFontDescriptor?
  private static let ttf = "AAEAAAAKAIAAAwAgT1MvMkhZZwUAAAEoAAAAYGNtYXBBd9/aAAABlAAAADxnbHlmIWVtcQAAAdgAAAKkaGVhZDCgLj0AAACsAAAANmhoZWEG7ARuAAAA5AAAACRobXR4B0QAHgAAAYgAAAAMbG9jYQAAAVIAAAHQAAAACG1heHAACAD9AAABCAAAACBuYW1lP8806AAABHwAAAFEcG9zdDmtsp4AAAXAAAAAMAABAAAAAQAA3oDxTV8PPPUAAwPoAAAAAOcR9U4AAAAA5xH1TgAeAAADSALBAAAAAwACAAAAAAAAAAEAAAOE/wYAAARWAB4BDgNIAAEAAAAAAAAAAAAAAAAAAAADAAEAAAADAPsABAAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAwJsAZAABQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAgAAAAAAAAAAPz8/PwAAACAgwwOE/wYAAAOEAPoAAAAAAAAAAAIIAsEAAAAgAAAB9AAAAPoAAARWAB4AAAACAAAAAwAAABQAAwABAAAAFAAEACgAAAAGAAQAAQACACAgw///AAAAICDD////4d8/AAEAAAAAAAAAAAAAAAABUgAEAB4AAANIAsEAqgDGANYA+gAAEzEiNjIzMjIWFzIWFxYWFxYXFhYXMBcWFhcWFxYVFBcWMzIWFxYXFhUVJyYnIiYjIxUUFBUVFzMXFhcWFxYVFAYnJicmJiMiIiMGBxQGBgciBwYGBwYHBgcGBgciBgcGBwYHBgYHBgcGBwYGIwYGByIGIyM3Njc2NzQ2NTUnIiInJicmNCc1FxYXFzMXNTUjIiYjJicmJyY0JzQ2FxYXFhYzMzU0JiYnJicmBSImIyMVIhQVFzMyMjYxMCc0JjUmJyYmJyYnJhMnIyIGMSIUFRczFzc8AgcxNCMqAiMHFRUzMjI2NzY2NzY3NDM2Njc2NzY3NjY3Njc2ZgEXPDdBQx0JAgsEHEAVAwYDFgMGBRUFThwDAQEgGwwIGQkDBAwOAw4XJBsbBxoMAgQBAQYGBwcNIRAZAQIBBwcBAQEBCwIDAxQeBA4DAQQDCwUBBgQUBR0gFgwCBgIGKQwHVD2JAxQIAgEBGRIJBSMLAgEGCQkHJSYbEAwCEw0JBQIBAQQLDwUMGCIBAQIIEwMBDAYpGDkBAbQxUjIBAgUMAQ0CLVkZywG4T2kBAbi4AQkBATFRMrM/HhsNCBIoDBABAgQVBiUXBAECCQIKBwYCwAEBAQEBAw8KAQICCgIDAw4EO2UJAgEBAQIEDR0MEgwECwQBCwkfCgkBAgkbBQwDEA4BBQYDBAEBAwQXFQEDAxkDBAUiHAQLAgQCCAIBAwILAg0IBgEBAQEEAQEDFi4MCQQtIUgBAgkpBQcLEAUJBAIBJCMBBhALEgUHCw0CBAsDAQFHJiQSCS8WBSMBAj4raQEFAggDGB8DGwRKFQb+5gMBFQ4iAQMBHx+JAQFpaQEBAQkEBQEBAQsEGCQHAgIRBRYdGQAAAAAIAGYAAQAAAAAAAAAoAAAAAQAAAAAAAQAKACgAAQAAAAAAAgAHADIAAQAAAAAABgARADkAAwABBAkAAABQAEoAAwABBAkAAQAUAJoAAwABBAkAAgAOAK4AAwABBAkABgAiALxVQUUgZGlyaGFtIHNpZ246IENlbnRyYWwgQmFuayBvZiB0aGUgVUFFRTExIERpcmhhbVJlZ3VsYXJFMTFEaXJoYW0tUmVndWxhcgBVAEEARQAgAGQAaQByAGgAYQBtACAAcwBpAGcAbgA6ACAAQwBlAG4AdAByAGEAbAAgAEIAYQBuAGsAIABvAGYAIAB0AGgAZQAgAFUAQQBFAEUAMQAxACAARABpAHIAaABhAG0AUgBlAGcAdQBsAGEAcgBFADEAMQBEAGkAcgBoAGEAbQAtAFIAZQBnAHUAbABhAHIAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAAAAAwECB3VuaTIwQzM="
  static func setup() {
    guard desc == nil else { return }
    // (iOS already has it: nothing to do)
    var g: CGGlyph = 0, u: UniChar = 0x20C3
    if CTFontGetGlyphsForCharacters(UIFont.systemFont(ofSize: 17) as CTFont, &u, &g, 1), g != 0 { return }
    guard let data = Data(base64Encoded: ttf), let prov = CGDataProvider(data: data as CFData), let cg = CGFont(prov) else { return }
    var err: Unmanaged<CFError>?
    CTFontManagerRegisterGraphicsFont(cg, &err)
    guard let name = cg.postScriptName as String?, UIFont(name: name, size: 12) != nil else { return }
    desc = UIFontDescriptor(name: name, size: 0)
    for (a, b) in [(#selector(UIFont.systemFont(ofSize:weight:)), #selector(UIFont.e11_systemFont(ofSize:weight:))),
                   (#selector(UIFont.systemFont(ofSize:)), #selector(UIFont.e11_systemFont(ofSize:))),
                   (#selector(UIFont.boldSystemFont(ofSize:)), #selector(UIFont.e11_boldSystemFont(ofSize:))),
                   (#selector(UIFont.monospacedDigitSystemFont(ofSize:weight:)), #selector(UIFont.e11_monospacedDigitSystemFont(ofSize:weight:)))] {
      if let m1 = class_getClassMethod(UIFont.self, a), let m2 = class_getClassMethod(UIFont.self, b) { method_exchangeImplementations(m1, m2) }
    }
  }
  static func cascade(_ f: UIFont) -> UIFont {
    guard let d = desc else { return f }
    return UIFont(descriptor: f.fontDescriptor.addingAttributes([.cascadeList: [d]]), size: f.pointSize)
  }
}
extension UIFont {
  // (swapped with the system's own at start: these call the originals)
  @objc class func e11_systemFont(ofSize s: CGFloat, weight w: UIFont.Weight) -> UIFont { Dirham.cascade(e11_systemFont(ofSize: s, weight: w)) }
  @objc class func e11_systemFont(ofSize s: CGFloat) -> UIFont { Dirham.cascade(e11_systemFont(ofSize: s)) }
  @objc class func e11_boldSystemFont(ofSize s: CGFloat) -> UIFont { Dirham.cascade(e11_boldSystemFont(ofSize: s)) }
  @objc class func e11_monospacedDigitSystemFont(ofSize s: CGFloat, weight w: UIFont.Weight) -> UIFont { Dirham.cascade(e11_monospacedDigitSystemFont(ofSize: s, weight: w)) }
}
