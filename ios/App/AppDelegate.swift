// E11 Console for iPhone — the native app around the E11 Console server (console.e11hq.com).
// The screens, data and updates come live from the server (the same phone layout as the browser); the app adds
// what only a real app can: a native tab bar, Apple's push notifications (with the app closed), opening the right
// page from a notification, the app icon badge, Face ID lock, downloads to Files / Photos through the share sheet,
// and the page running up under the status bar (no iOS 26 blur workaround needed in a native app).
// It talks to the page through the same kind of bridge as the Mac app (handler "e11ios"; replies via
// window.__e11NativeReply), so the web app (web/app.js Host.isIOSApp, web/phone.js) knows it's here.
import UIKit
import Network
import WebKit
import UserNotifications
import LocalAuthentication
import PhotosUI
import UniformTypeIdentifiers
import AudioToolbox

// Version of this iPhone app's native part (raise it with changes the web app needs to know about)
let SHELL_VERSION = 25   // 25: Home straight from the server (/api/home; Done / reopen / Due / Delete / Undo to /api/home/act, kept on the phone until sent — ServerHome.swift); the page still says when Home shows · 24: a Home card swiped right: Done · Due (taps back: window.__e11Home — done, due; the page opens its date sheet) · 23: Home (E11 Day / My Day) is the app's own (Home.swift; the page sends it: home show / people / toast; taps back: window.__e11Home — open, search, me, add, copy, delete, attach, toast); a card swiped left: Copy link · Delete; held: Attach Files · 22: the startup screen is the app's own, there the moment it opens (Splash.swift; the page drives it: splash hello / memo / greet / tick / status / out; window.__e11SplashSkip / __e11SplashRetry) · 21: the comments screen tells its page how far it's slid up for the keyboard (--cm-top: a thread's bar stays in sight); its swipe right also takes iPhone's slow back drag from the edge; it starts at the latest comment only when the task opens and when the keyboard comes up, and keeps its place across Details / Comments · 20: a task's Comments on a screen of their own (a second web view showing only the comments, scrolled by iOS itself; window.__e11ShowComments, cmReady / cmEnd) · 19: on a task's Comments, iOS itself moves the comments list with the keyboard (its own scroll view, in the keyboard's own animation; window.__e11FeedKb) · 18: the file preview is iOS's own (preview / previewSet / window.__e11Preview; Preview.swift) · 17: the comment box on a task's Comments is iPhone's own, on the keyboard (commentBar / window.__e11CBar; CommentBar.swift) · 16: iPhone's own banners also while the app is open (the page draws no cards), each notification confirmed by the Notification Service Extension so the server sends again the ones an offline phone missed (register ack) · 15: New task / Request amendments as native sheets with iPhone's own fields that tuck into a bar like a Mail draft (formSheet / formSet / formClose; the page: window.__e11Form), a Trash task as a native sheet (trashSheet); native sheets and dates also open on top of those · 14: native sheets with people (round photos / initials) and a search box (+ a typed entry, "Use …") · 13: also dates picked in a native sheet (pickDate: closing it never sets a date) · a native sheet can stay open for ticking several (multi; each tick: window.__e11SheetPick) · 12: native sheets also with colour dots, a row of colours / emoji / numbers (chips), tinted icons, locked rows · 11: plain menus as iOS's own sheets (nativeSheet; the page: NativeSheet in app.js, showMenu(…, { native: true })) · 10: My Tasks, Inbox and Team lists swiped by iOS itself (Pager.syncLists in phone.js) · 9: a task’s Details / Comments swiped by iOS itself (the page: Pager in phone.js) · 8: iOS haptics for the page (haptic kind: light / medium / selection / success / warning / error) · 7: the comment box rides down / up with the keyboard frame by frame (__e11KbStep) · 6: the comment box gets the keyboard back after Photos / Camera / Files · 5: the page stays full height under the keyboard (the page makes room itself, --ios-kb) · 3: its own sheet for attaching files · 4: straight to Photos / Camera / Files (the page's attach bar), keyboard kept
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
  }
  func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) { if let u = contexts.first?.url { Main.shared.openLink(u) } }
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
    loadHome()
  }
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
    s.onRetry = { [weak self] in self?.pageJS("window.__e11SplashRetry && window.__e11SplashRetry()") }
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
    if a["hello"] != nil {
      splashHeard = true
      guard let s = splash, !s.leaving else { return ["ok": true, "shown": false] }
      return ["ok": true, "shown": true, "age": Int((CACurrentMediaTime() - s.t0) * 1000)]
    }
    if let m = a["memo"] as? [String: Any] {
      SplashView.save(m)
      if (m["native"] as? Bool) == false { splashGone(fast: true) }
    }
    guard let s = splash, !s.leaving else { return ["ok": true, "shown": false] }
    splashHeard = true
    if a["out"] != nil { splashGone(); return ["ok": true] }
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
  func commentBar(_ a0: [String: Any]) {
    var a = a0
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
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let onServer = webView.url?.host == serverHost
    pageReady = onServer
    reviewLink.isHidden = !(webView.url?.host ?? "").hasSuffix(".cloudflareaccess.com")
    webView.hideKeyboardBar()
    if onServer { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.syncBackground() } }
    if onServer { shareSignIn() }
    if onServer { tabCover = -1; view.setNeedsLayout(); flushPending(); if !SELFTEST.isEmpty && !started { started = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.selfTest() } } }
    else { tabBar.isHidden = true; tabsHidden = true; view.setNeedsLayout(); splashGone(fast: true) }   // (the sign-in page: no tabs, no startup screen)
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
    splashGone(fast: true)
    if retrying { return }
    retrying = true
    pageReady = false
    tabBar.isHidden = true; tabsHidden = true; view.setNeedsLayout()
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
      pageJS("window.toast && toast('Already downloading — it opens when it’s done')")
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
    if wasLive, (error as NSError).code != NSURLErrorCancelled { pageJS("window.toast && toast('Download failed — check your connection and try again')") }
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
    case "me": return "person.crop.circle"
    default: return "circle"
    }
  }
  func setTabs(_ a: [String: Any]) {
    let list = a["tabs"] as? [[String: Any]] ?? []
    let keys = list.map { $0["v"] as? String ?? "" }
    if keys != tabKeys || (tabBar.items?.count ?? 0) != keys.count {
      tabKeys = keys
      tabPhoto = [:]
      tabBadgeKey = [:]
      tabBar.items = list.enumerated().map { i, t in
        let v = t["v"] as? String ?? ""
        return UITabBarItem(title: t["label"] as? String ?? "", image: UIImage(systemName: symbol(v)), tag: i)
      }
    } else {
      for (i, t) in list.enumerated() { tabBar.items?[i].title = t["label"] as? String ?? "" }
    }
    // the Me tab: the person's own picture (round, as drawn by the page), with a ring when it's the open tab
    // (and a small dot at its bottom right: green online, red offline — Haris, 2026-10-31)
    for (i, t) in list.enumerated() {
      let online = (t["online"] as? Bool ?? true) && netUp
      if let item = tabBar.items?[i], let src = tabPhotoSrc[i], tabOnline[i] != online, t["photo"] as? String == tabPhoto[i] {
        tabOnline[i] = online
        item.image = roundPhoto(src, ring: nil, online: online)
        item.selectedImage = roundPhoto(src, ring: tabBar.tintColor ?? .systemBlue, online: online)
      }
      guard let ph = t["photo"] as? String, ph != tabPhoto[i], let item = tabBar.items?[i] else { continue }
      tabPhoto[i] = ph
      tabOnline[i] = online
      let apply = { (src: UIImage) in
        self.tabPhotoSrc[i] = src
        let on = self.tabOnline[i] ?? true
        item.image = self.roundPhoto(src, ring: nil, online: on)
        item.selectedImage = self.roundPhoto(src, ring: self.tabBar.tintColor ?? .systemBlue, online: on)
      }
      // the page's own drawing first (initials, or the picture), then the picture itself fetched here when there is one
      if let comma = ph.firstIndex(of: ","), let data = Data(base64Encoded: String(ph[ph.index(after: comma)...])), let src = UIImage(data: data) { apply(src) }
      if let s = t["photoUrl"] as? String, let url = URL(string: s) { fetchPhoto(url) { img in if self.tabPhoto[i] == ph, let img = img { apply(img) } } }
    }
    // counts sit on the icon's top-right corner, overlapping it a little (like an app icon's badge), drawn into the
    // icon itself: iOS's own tab badge sits further out
    lastTabs = a
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
            item.image = badged(symbol(v), b, color: tabBar.unselectedItemTintColor ?? .label)
            item.selectedImage = badged(symbol(v), b, color: tabBar.tintColor ?? .systemBlue)
          }
        }
      }
      if (t["on"] as? Bool) == true { tabBar.selectedItem = item }
    }
    let hide = (a["hidden"] as? Bool) == true || list.isEmpty
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
        if up != self.netUp { self.netUp = up; if let t = self.lastTabs { self.setTabs(t) } }
        if up { self.serverHome.send() }   // (anything waiting goes now)
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
    if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle, let a = lastTabs { tabBadgeKey = [:]; setTabs(a) }
  }
  // a picture from our server, with the page's sign-in (its cookies)
  func fetchPhoto(_ url: URL, _ done: @escaping (UIImage?) -> Void) {
    web.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
      var req = URLRequest(url: url)
      let mine = cookies.filter { url.host?.hasSuffix($0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain) == true }
      req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: mine)
      URLSession.shared.dataTask(with: req) { data, resp, _ in
        let ok = (resp as? HTTPURLResponse)?.statusCode == 200
        let img = ok ? data.flatMap { UIImage(data: $0) } : nil
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
          (appStyle == .light ? UIColor.white : UIColor(white: 0.12, alpha: 1)).setFill()
          UIBezierPath(ovalIn: dot.insetBy(dx: -edge, dy: -edge).intersection(CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: -edge, dy: -edge))).fill()
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
    UISelectionFeedbackGenerator().selectionChanged()
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
          guard let self = self, let sel = self.tabBar.selectedItem, sel.tag < self.tabKeys.count, self.tabKeys[sel.tag] != "today" else { return }
          self.homeIfMade?.isHidden = true
        }
      }
    }
    pageJS("window.__e11Tab && window.__e11Tab(\(jsonString([tabKeys[item.tag]]).dropFirst().dropLast()))")
  }
  /* ---------- Home (23+): the app's own, under the tab bar; the page says what's on it (NativeHome in phone.js) ---------- */
  var homeIfMade: HomeView?
  var homeHadModel = false
  lazy var homeView: HomeView = {
    let h = HomeView(frame: view.bounds)
    h.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    h.isHidden = true
    h.onEvent = { [weak self] ev in
      if self?.homeEventOnServer(ev) == true { return }
      // (a task opening: Home goes at once, so the task slides in over the page's own Home, scrolled the same)
      if (ev["ev"] as? String) == "open" { self?.homeIfMade?.isHidden = true }
      self?.pageJS("window.__e11Home && window.__e11Home(\(jsonString(ev)))")
    }
    h.present = { [weak self] vc in self?.topMost().present(vc, animated: true) }
    view.insertSubview(h, belowSubview: tabBar)
    homeIfMade = h
    return h
  }()
  /* the top of the tab bar as it's seen: iOS 26's floating bar is a pill inside a taller UITabBar view, so the view's
     own top is well above it (the + and the toasts sat ~35 pt too high — Haris, 2026-10-31). The pill: 61 tall, its
     bottom 11 pt into the home-indicator room (8 from the edge on a phone without one). */
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
  lazy var serverHome: ServerHome = {
    let s = ServerHome()
    s.cookies = { [weak self] done in
      guard let store = self?.web?.configuration.websiteDataStore.httpCookieStore else { return done(WidgetShare.signIn()?.cookie ?? "") }
      store.getAllCookies { cs in
        let host = URL(string: serverURL())?.host ?? ""
        let mine = cs.filter { c in let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain; return host == d || host.hasSuffix("." + d) }
        done(mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
      }
    }
    s.onModel = { [weak self] m in self?.drawServerHome(m) }
    // switched off on the server (or no Home for this person): the page's Home again, drawn at once
    s.onOff = { [weak self] in self?.pageJS("window.__e11HomeResend && window.__e11HomeResend()") }
    s.onToast = { [weak self] t, a, run in
      guard let h = self?.homeIfMade, !h.isHidden else { return }
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
  }()
  var homeToastRun: (() -> Void)?
  var homePageMe: String?
  var homeLook: Any?, homePagePeople: [String: [String: Any]] = [:], homeServerPeople: [String: [String: Any]] = [:]
  // the server's Home drawn (with the page's colours), when Home is on screen
  func drawServerHome(_ m: [String: Any]) {
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
    h.update(mm)
  }
  // Home's own taps the server does itself (false: the page does it, as before)
  func homeEventOnServer(_ ev: [String: Any]) -> Bool {
    // (only for the person the page shows: right after another sign-in, the page's Home until the server's catches up)
    guard serverHome.on, serverHome.me != nil, serverHome.me == homePageMe, let kind = ev["ev"] as? String else { return false }
    let id = ev["id"] as? String ?? ""
    let card = ((serverHome.shown?["groups"] as? [[String: Any]]) ?? []).flatMap { $0["cards"] as? [[String: Any]] ?? [] }.first { ($0["id"] as? String) == id }
    switch kind {
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
      host.present(DateSheetVC(["value": due, "min": "", "max": "", "clearable": !due.isEmpty, "md": false], dark: statusStyle != .darkContent) { [weak self] r in
        if (r["cancel"] as? Bool) == true || (r["ok"] as? Bool) == false { return }
        let v = (r["clear"] as? Bool) == true ? "" : (r["date"] as? String ?? "")
        if v == due { return }
        self?.serverHome.act("due", id, due: v.isEmpty ? nil : v)
      }, animated: true)
      return true
    case "delete":
      serverHome.act("delete", id); return true
    default: return false
    }
  }
  func homeCommand(_ a: [String: Any]) {
    if let p = a["people"] as? [String: [String: Any]] {
      homePagePeople = p
      homeView.people = serverHome.on ? homeServerPeople.merging(p, uniquingKeysWith: { s, pg in pg["photo"] != nil || s["photo"] == nil ? pg : s }) : p
      return
    }
    if let t = a["toast"] as? [String: Any] { homeToastRun = nil; if let h = homeIfMade, !h.isHidden { h.toast(t) }; return }   // (its button is the page's)
    if let r = a["search"] as? [String: Any] { homeIfMade?.searchResults(r); return }
    guard let show = a["show"] as? Bool else { return }
    if !show { homeIfMade?.endEditing(true); homeIfMade?.isHidden = true; return }
    let h = homeView
    h.bottomRoom = (tabBar.isHidden ? 40 : view.bounds.height - tabBar.frame.minY) + 96
    h.tabTop = tabBar.isHidden ? nil : tabPillTop
    homeLook = a["look"]
    homePageMe = a["me"] as? String
    // (the server's Home when it's on — the page's model is only a sign something changed: the server asked again)
    if serverHome.on, let m = serverHome.shown, (m["me"] as? String) == (a["me"] as? String) {
      h.isHidden = false
      drawServerHome(m)
    } else { h.update(a) }
    homeHadModel = true
    h.isHidden = false
    serverHome.refresh()
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
    if pageReady { sendToken(hex) } else { pendingToken = hex }
    let w = pushWaiters; pushWaiters = []
    w.forEach { $0(["ok": true, "state": "on"]) }
  }
  func tokenFailed(_ msg: String) {
    let w = pushWaiters; pushWaiters = []
    w.forEach { $0(["ok": false, "error": "Couldn’t turn on notifications: " + msg]) }
  }
  func sendToken(_ hex: String) {
    // (the Notification Service Extension confirms each notification with this address — ack: the server sends again
    //  the ones that didn't arrive)
    WidgetShare.write("apnsToken", Data(hex.utf8))
    pageJS(waitForApp("window.__e11ApnsToken && window.__e11ApnsToken(\(jsonString(["token": hex, "env": APNS_ENV, "ack": true, "platform": "ios"])))"))
  }
  // run something once the web app has its data (it may still be starting when the app opens from a notification)
  func waitForApp(_ js: String) -> String {
    "(function f(n){ if ((typeof db !== 'undefined' && db) && typeof currentUserId !== 'undefined' && currentUserId) { \(js) } else if (n < 80) setTimeout(function(){ f(n+1) }, 250); })(0)"
  }
  func openPush(_ userInfo: [AnyHashable: Any]) {
    let d = userInfo["e11"] as? [String: Any] ?? [:]
    if pageReady { pageJS(waitForApp("window.__e11PushTap && window.__e11PushTap(\(jsonString(d)))")) } else { pendingPush = d }
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
    if pageReady { pushState { st in if st == "on" { UIApplication.shared.registerForRemoteNotifications() } } }
  }
  func wentAway() { if !authing { awayAt = Date() }; if pageReady { shareSignIn() } }

  /* ---------- the widget (widget/E11Widget.swift) ---------- */
  // it asks the server with this app's own sign-in: the server and its cookies go to the shared Keychain
  func shareSignIn() {
    guard let store = web?.configuration.websiteDataStore.httpCookieStore else { return }
    store.getAllCookies { cookies in WidgetShare.saveSignIn(server: serverURL(), cookies: cookies) }
  }
  // e11console://open?task=<id> | ?plan=<id> | ?view=home|plans|fin-dash — a tap on the widget
  func openLink(_ u: URL) {
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
    if UIApplication.shared.applicationState == .active { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.unlock() } }
  }
  @objc func unlock() {
    if authing || lockView == nil { return }
    let ctx = LAContext(); var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return unlocked() }
    authing = true
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock E11 Console") { ok, _ in
      DispatchQueue.main.async {
        if ok { self.unlocked() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.authing = false }   // (after the app is active again)
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
    if from != nil, from === cweb, ["setTabs", "badge", "setAppearance", "pushRegister", "pushEnable", "pushDisable", "notify", "setLock", "pickDate", "formSheet", "formSet", "formClose", "trashSheet", "splash", "home"].contains(cmd) { return reply(["ok": true, "ignored": true]) }
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
    case "setTabs": setTabs(a); done(["ok": true])
    case "badge":
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
      statusStyle = (a["mode"] as? String) == "light" ? .darkContent : .lightContent
      defaults.set((a["mode"] as? String) == "light" ? "light" : "dark", forKey: "e11_look")
      setNeedsStatusBarAppearanceUpdate()
      // the tab bar follows the app's own light / dark (not only the phone's): every icon, the open page's too, white
      // in dark and black in light — Haris 2026-10-30 (only the tab bar: the page itself keeps following the phone)
      let style: UIUserInterfaceStyle = (a["mode"] as? String) == "light" ? .light : .dark
      // (everything the app draws itself follows the app's own light / dark, never the phone's — Haris, 2026-10-31:
      //  set on the whole window, so every native screen, sheet, alert, picker and keyboard takes it, now and later)
      appStyle = style; view.window?.overrideUserInterfaceStyle = style
      cbarIfMade?.setLook(light: style == .light)
      if tabBar.overrideUserInterfaceStyle != style || tabBar.tintColor != (style == .dark ? UIColor.white : UIColor.black) {
        tabBar.overrideUserInterfaceStyle = style
        let ink: UIColor = style == .dark ? .white : .black
        tabBar.tintColor = ink
        tabBar.unselectedItemTintColor = ink
        tabBadgeKey = [:]
        if let t = lastTabs { setTabs(t) }
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
      ("inbox", pause(1500) + "return JSON.stringify({ view: ui.view })", {
        if let i = self.tabKeys.firstIndex(of: "inbox"), let item = self.tabBar.items?[i] { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) } }),
      ("me", "go('me'); " + pause(1200) + "for (let i = 0; i < 3; i++) { await Push.refresh(); " + pause(300) + " } return JSON.stringify({ lockRows: document.querySelectorAll('#ph-lock, [data-ph-lock]').length, pushRows: document.querySelectorAll('#ph-push').length })", nil),
      ("client", "try { let c = db.clients.find((x) => (x.folders || []).some((f) => (f.files || []).length > 1)) || db.clients[0]; if (!c) { c = createClient('Sample client'); c.folders[0].files = [{ id: 'st-a1', name: 'Logo primary.png', size: 48000, at: nowISO() }, { id: 'st-a2', name: 'Brand guidelines.pdf', size: 2400000, at: nowISO() }, { id: 'st-a3', name: 'Logo lockup.ai', size: 4800000, at: nowISO() }] } const f = (c.folders || []).find((x) => (x.files || []).length > 1) || (c.folders || [])[0]; if (!f) return JSON.stringify({ error: 'no folder' }); openClient(c.id, f.id); " + pause(1200) + "return JSON.stringify({ wide: document.getElementById('content').scrollWidth > innerWidth + 1 }) } catch (e) { return JSON.stringify({ error: String(e && e.message || e) }) }", nil),
      ("task", "const t = db.tasks.find((x) => !x.parentId && !x.done && (x.comments || []).length) || db.tasks.find((x) => !x.parentId && !x.done); openTask(t.id); " + pause(1500) + "return JSON.stringify({ taskOpen: !!ui.taskId })", nil),
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
          if name == "home" || name == "inbox" || name.hasPrefix("home") { var g = self.homeGeo(); g["sheet"] = self.presentedViewController.map { String(describing: type(of: $0)) } ?? ""; self.selfResult[name + "Native"] = g }
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
    var pic: UIImage? = nil; var initials: String? = nil; var picColor: UIColor? = nil; var find: String = "" }
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
    "shield": "checkmark.shield", "lock": "lock", "logout": "rectangle.portrait.and.arrow.right", "bell": "bell",
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
                   picColor: NativeSheetVC.color((r["person"] as? [String: Any])?["color"]), find: ((r["find"] as? String) ?? (r["label"] as? String) ?? "").lowercased())
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
    let tint: UIColor = r.disabled ? .tertiaryLabel : r.danger ? .systemRed : .label
    c.textProperties.color = r.disabled ? .secondaryLabel : r.danger ? .systemRed : .label
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
  private func choose(_ i: Int, _ swatch: String?) {
    guard let a = answer else { return }
    answer = nil
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
  // A row of round choices: colours (swatch), emoji (reactions) or numbers (priority). Scrolls sideways if it doesn't fit.
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
        b.setTitle(ch.label ?? "", for: .normal)
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
    if let p = pic { p.draw(in: rect); return }
    (color ?? .systemGray).setFill(); UIRectFill(rect)
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
      if i > 0 { s.append(NSAttributedString(string: "    ", attributes: [.font: font])) }
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
  // iPhone's own calendar (the one inside its date picker), so today can carry a mark: a blue dot under it, only to see —
  // the date picked is still the filled circle (Haris, 2026-11-01)
  private let cal = UICalendarView()
  private let gregorian = Calendar(identifier: .gregorian)
  private var answer: (([String: Any]) -> Void)?
  private let fmt: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f }()
  private let clearable: Bool
  private let md: Bool
  init(_ a: [String: Any], dark: Bool, answer: @escaping ([String: Any]) -> Void) {
    self.answer = answer
    clearable = (a["clearable"] as? Bool) == true
    md = (a["md"] as? Bool) == true
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = dark ? .dark : .light
    cal.calendar = gregorian
    cal.locale = Locale(identifier: "en_US")
    let pick = UICalendarSelectionSingleDate(delegate: self)
    if let v = a["value"] as? String, let d = fmt.date(from: v) {
      let dc = gregorian.dateComponents([.year, .month, .day], from: d)
      pick.selectedDate = dc
      cal.visibleDateComponents = dc
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
  // today: a small blue dot under it
  func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
    let t = gregorian.dateComponents([.year, .month, .day], from: Date())
    return dateComponents.year == t.year && dateComponents.month == t.month && dateComponents.day == t.day ? .default(color: .systemBlue, size: .small) : nil
  }
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
    [today, clear, cal].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    NSLayoutConstraint.activate([
      clear.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22), clear.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
      today.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22), today.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
      cal.topAnchor.constraint(equalTo: today.bottomAnchor, constant: 4),
      cal.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), cal.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    ])
  }
  private var fitHeight: CGFloat = 470, sized = false
  // sized to the calendar once, from where it was laid out — measuring it again inside the layout (and resizing the sheet
  // from there) sent iOS 27's calendar round in circles until the app crashed (TestFlight report, build 1195: the date
  // sheet from Home's Due)
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard !sized, view.bounds.width > 0, cal.frame.minY > 0, cal.frame.height > 100 else { return }
    sized = true
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
  private func finish(_ r: [String: Any]) {
    guard let a = answer else { return }
    answer = nil
    dismiss(animated: true) { a(r) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { let a = answer; answer = nil; a?(["ok": true, "cancel": true]) }
}
