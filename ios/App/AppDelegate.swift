// E11 Console for iPhone — the native app around the E11 Console server (console.e11hq.com).
// The screens, data and updates come live from the server (the same phone layout as the browser); the app adds
// what only a real app can: a native tab bar, Apple's push notifications (with the app closed), opening the right
// page from a notification, the app icon badge, Face ID lock, downloads to Files / Photos through the share sheet,
// and the page running up under the status bar (no iOS 26 blur workaround needed in a native app).
// It talks to the page through the same kind of bridge as the Mac app (handler "e11ios"; replies via
// window.__e11NativeReply), so the web app (web/app.js Host.isIOSApp, web/phone.js) knows it's here.
import UIKit
import WebKit
import UserNotifications
import LocalAuthentication
import PhotosUI
import UniformTypeIdentifiers

// Version of this iPhone app's native part (raise it with changes the web app needs to know about)
let SHELL_VERSION = 14   // 14: native sheets with people (their round photo, else initials on their colour) and a search box (search) · 13: also dates picked in a native sheet (pickDate: closing it never sets a date) · a native sheet can stay open for ticking several (multi; each tick: window.__e11SheetPick) · 12: native sheets also with colour dots, a row of colours / emoji / numbers (chips), tinted icons, locked rows · 11: plain menus as iOS's own sheets (nativeSheet; the page: NativeSheet in app.js, showMenu(…, { native: true })) · 10: My Tasks, Inbox and Team lists swiped by iOS itself (Pager.syncLists in phone.js) · 9: a task’s Details / Comments swiped by iOS itself (the page: Pager in phone.js) · 8: iOS haptics for the page (haptic kind: light / medium / selection / success / warning / error) · 7: the comment box rides down / up with the keyboard frame by frame (__e11KbStep) · 6: the comment box gets the keyboard back after Photos / Camera / Files · 5: the page stays full height under the keyboard (the page makes room itself, --ios-kb) · 3: its own sheet for attaching files · 4: straight to Photos / Camera / Files (the page's attach bar), keyboard kept
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
let BG = UIColor(red: 0.047, green: 0.051, blue: 0.059, alpha: 1)

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
  // while the app is open the page shows its own alert: here only the list and the badge
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.list, .badge])
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
  var statusStyle: UIStatusBarStyle = .lightContent
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
    loadHome()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
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
    keyboardCover = cover
    let dur = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
    let curve = (n.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
    pageJS("window.__e11Kb && window.__e11Kb(\(Int(cover.rounded())), \(Int(dur * 1000)), 1)")
    rideKeyboard(to: cover, duration: dur, curve: curve)
    if web.scrollView.contentOffset != .zero { web.scrollView.setContentOffset(.zero, animated: false) }
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
    else { tabBar.isHidden = true; tabsHidden = true; view.setNeedsLayout() }   // (the sign-in page: no tabs)
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
    present(a, animated: true)
  }
  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
    a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
    present(a, animated: true)
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
    (presentedViewController ?? self).present(sheet, animated: true)
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
    for (i, t) in list.enumerated() {
      guard let ph = t["photo"] as? String, ph != tabPhoto[i], let item = tabBar.items?[i] else { continue }
      tabPhoto[i] = ph
      let apply = { (src: UIImage) in
        item.image = self.roundPhoto(src, ring: nil)
        item.selectedImage = self.roundPhoto(src, ring: self.tabBar.tintColor ?? .systemBlue)
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
        let key = "\(v)|\(b)|\(traitCollection.userInterfaceStyle.rawValue)"
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
        UIView.animate(withDuration: 0.18) { self.tabBar.alpha = 1 }
      }
    }
  }
  var tabPhoto: [Int: String] = [:]
  var tabBadgeKey: [Int: String] = [:]
  var lastTabs: [String: Any]?
  // a tab's icon with its count on the top-right corner, overlapping the icon a little
  func badged(_ name: String, _ text: String, color: UIColor) -> UIImage {
    let resolved = color.resolvedColor(with: traitCollection)
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
  func roundPhoto(_ src: UIImage, ring: UIColor?) -> UIImage {
    let size: CGFloat = 28
    let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return r.image { _ in
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
    pageJS("window.__e11Tab && window.__e11Tab(\(jsonString([tabKeys[item.tag]]).dropFirst().dropLast()))")
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
    pageJS(waitForApp("window.__e11ApnsToken && window.__e11ApnsToken(\(jsonString(["token": hex, "env": APNS_ENV])))"))
  }
  // run something once the web app has its data (it may still be starting when the app opens from a notification)
  func waitForApp(_ js: String) -> String {
    "(function f(n){ if (window.db && typeof currentUserId !== 'undefined' && currentUserId) { \(js) } else if (n < 80) setTimeout(function(){ f(n+1) }, 250); })(0)"
  }
  func openPush(_ userInfo: [AnyHashable: Any]) {
    let d = userInfo["e11"] as? [String: Any] ?? [:]
    if pageReady { pageJS(waitForApp("window.__e11PushTap && window.__e11PushTap(\(jsonString(d)))")) } else { pendingPush = d }
  }
  func flushPending() {
    if let t = pendingToken { pendingToken = nil; sendToken(t) }
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
    run(msg["cmd"] as? String ?? "", msg["args"] as? [String: Any] ?? [:]) { res in
      self.pageJS("window.__e11NativeReply && window.__e11NativeReply(\(jsonString([id]).dropFirst().dropLast()),\(jsonString(res)))")
    }
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
    case "setAppearance":
      statusStyle = (a["mode"] as? String) == "light" ? .darkContent : .lightContent
      setNeedsStatusBarAppearanceUpdate()
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
      default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }
      done(["ok": true])
    case "nativeSheet":
      // a plain menu from the page as a real iPhone sheet (floating; iOS grows it as it's pulled); replies with the
      // chosen row's index, or -1 when it's closed without a choice
      if presentedViewController != nil { return done(["ok": false]) }
      let vc = NativeSheetVC(a, dark: statusStyle != .darkContent, pick: { [weak self] i in
        self?.pageJS("window.__e11SheetPick && window.__e11SheetPick(\(i))")
      }) { i, swatch in
        if i >= 0 { FocusAfterPicker.allow() }   // (a text box the option opens still brings the keyboard)
        var r: [String: Any] = ["ok": true, "index": i]
        if i == -2 { r["text"] = swatch ?? "" } else if let sw = swatch { r["swatch"] = sw }
        done(r)
      }
      vc.loadPhoto = { [weak self] u, got in self?.fetchPhoto(u, got) ?? got(nil) }
      present(vc, animated: true)
    case "pickDate":
      // a date from the page, picked in a native sheet with iPhone's own calendar: a day tapped → that date;
      // Today / Clear; closed any other way → nothing changes (iPhone's own date box set today when just closed)
      if presentedViewController != nil { return done(["ok": false]) }
      present(DateSheetVC(a, dark: statusStyle != .darkContent) { r in done(r) }, animated: true)
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
    case "pickFiles": Picker.shared.pick(from: self, single: (a["single"] as? Bool) == true, source: a["source"] as? String, done)
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
  func selfSheet(_ sections: [[String: Any]], search: String? = nil) {
    var args: [String: Any] = ["sections": sections, "multi": true]
    if let q = search { args["search"] = q; args["empty"] = "No one matches" }
    let show = { self.run("nativeSheet", args) { _ in } }
    if let p = presentedViewController { p.dismiss(animated: false) { show() } } else { show() }
  }
  func pause(_ ms: Int) -> String { "await new Promise((r) => setTimeout(r, \(ms)));" }
  func selfTest() {
    let wait = "for (let i = 0; i < 120 && !(window.db && typeof currentUserId !== 'undefined' && currentUserId && document.getElementById('ph-tabs')); i++) await new Promise((r) => setTimeout(r, 250));"
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
      ("inbox", pause(1500) + "return JSON.stringify({ view: ui.view })", {
        if let i = self.tabKeys.firstIndex(of: "inbox"), let item = self.tabBar.items?[i] { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) } }),
      ("me", "go('me'); " + pause(1200) + "for (let i = 0; i < 3; i++) { await Push.refresh(); " + pause(300) + " } return JSON.stringify({ lockRows: document.querySelectorAll('#ph-lock, [data-ph-lock]').length, pushRows: document.querySelectorAll('#ph-push').length })", nil),
      ("client", "try { const c = db.clients.find((x) => (x.folders || []).some((f) => (f.files || []).length > 1)) || db.clients[0]; const f = (c.folders || []).find((x) => (x.files || []).length > 1) || (c.folders || [])[0]; if (!f) return JSON.stringify({ error: 'no folder' }); openClient(c.id, f.id); " + pause(1200) + "return JSON.stringify({ wide: document.getElementById('content').scrollWidth > innerWidth + 1 }) } catch (e) { return JSON.stringify({ error: String(e && e.message || e) }) }", nil),
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
      // a people picker (app 14): search box, people with their photo / initials and role, ticks
      ("nsheetPeople", "return '{}'", { self.selfSheet([
        ["header": "Assignees", "rows": [["i": 0, "label": "Me", "sub": "Super Admin", "checked": true, "multi": true, "find": "haris", "avatar": ["initials": "H", "color": [40, 160, 100]]]]],
        ["header": "People", "rows": ["Ali Raza", "Areej Khan", "Claire Dubois", "Leila Aziz", "Lena Farouk", "Maya Rahman", "Omar Said", "Sara Noor", "Zain Ali"].enumerated().map {
          ["i": $0.offset + 1, "label": $0.element, "sub": "Production", "multi": true, "find": $0.element, "avatar": ["initials": String($0.element.split(separator: " ").map { $0.prefix(1) }.joined()), "color": [90 + $0.offset * 15, 110, 200]]] }]],
        search: "Search people") }),
      ("nsheetSearch", "return '{}'", { (self.presentedViewController as? NativeSheetVC)?.selfSearch("al") }),
      ("signin", pause(4000) + "return JSON.stringify({ host: location.host, top: (document.querySelector('h1, h2, img, form') || document.body).getBoundingClientRect().top })", {
        self.presentedViewController?.dismiss(animated: false)
        self.web.load(URLRequest(url: URL(string: "https://e11hq.cloudflareaccess.com/")!)) }),
    ]
    func run(_ i: Int) {
      if i >= steps.count { selfResult["frame"] = ["web": web.frame.height, "screen": view.bounds.height, "inset": web.scrollView.contentInsetAdjustmentBehavior == .never ? "never" : "auto", "insetTop": web.scrollView.adjustedContentInset.top, "host": web.url?.host ?? "", "reviewLink": !reviewLink.isHidden, "privacy": Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil] as [String: Any]; return writeSelf("done") }
      let (name, js, before) = steps[i]
      before?()
      DispatchQueue.main.asyncAfter(deadline: .now() + (before == nil ? 0.2 : 1.5)) {
        self.probe(name, js) {
          if name.hasPrefix("nsheet") { self.selfResult[name + "Geo"] = (self.presentedViewController as? NativeSheetVC)?.geo() ?? ["error": "no native sheet"] }
          if name == "home" || name == "inbox" { self.selfResult[name + "Frame"] = ["web": self.web.frame.height, "screen": self.view.bounds.height, "tabBar": !self.tabBar.isHidden] as [String: Any] }
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.writeSelf(name); DispatchQueue.main.asyncAfter(deadline: .now() + 4) { run(i + 1) } }
        }
      }
    }
    run(0)
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
                var avatar: Avatar? = nil; var find: String = "" }
  struct Avatar { let photo: URL?; let initials: String; let color: UIColor }
  struct Section { let header: String?; let rows: [Row]; var photo: UIImage? = nil; var initials: String? = nil; var color: UIColor? = nil }
  private var sections: [Section] = []      // (what's shown: all of them, or those matching the search)
  private var allSections: [Section] = []
  private var ticked: [Int: Bool] = [:]     // (ticks flipped while the sheet is open — several can be ticked)
  // a search box at the top (people pickers): the list is filtered here as you type, by name and anything in find
  private var searchText: String?
  private var emptyText = "No matches"
  private var customText: String?           // ("Use “%@”": what's typed can be chosen as it is — a city that isn't listed)
  private let searchBox = UISearchBar()
  private var frozen = false                // (searching: the sheet keeps its size while the list changes)
  private var kbPad: CGFloat = 0, baseBottom: CGFloat = 0
  var loadPhoto: ((URL, @escaping (UIImage?) -> Void) -> Void)?
  private static let photos = NSCache<NSString, UIImage>()
  private static var loading = Set<String>()
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private var answer: ((Int, String?) -> Void)?
  private static func color(_ v: Any?) -> UIColor? {
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
                   avatar: (r["avatar"] as? [String: Any]).map { av in Avatar(photo: (av["photo"] as? String).flatMap { URL(string: $0) },
                     initials: av["initials"] as? String ?? "?", color: NativeSheetVC.color(av["color"]) ?? .systemGray) },
                   find: r["find"] as? String ?? "")
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
    allSections = sections
    searchText = (a["search"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    if let e = a["empty"] as? String, !e.isEmpty { emptyText = e }
    customText = (a["custom"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    overrideUserInterfaceStyle = dark ? .dark : .light
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController {
      // (at most about two-thirds of the screen, so even a long list stays the floating card; it scrolls inside)
      sh.detents = [.custom(identifier: .init("fit")) { [weak self] ctx in min(ctx.maximumDetentValue * 0.68, self?.fitHeight ?? 320) }]
      // (with a search box: typing takes the sheet to full height, so the list has room above the keyboard)
      if searchText != nil { sh.detents.append(.large()) }
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
    NSLayoutConstraint.activate([table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                                 table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    if let ph = searchText {
      // (the search box's field starts TOP under the sheet's top edge, like a first option; the list follows it)
      searchBox.searchBarStyle = .minimal; searchBox.placeholder = ph; searchBox.delegate = self
      searchBox.autocapitalizationType = .none; searchBox.autocorrectionType = .no; searchBox.returnKeyType = .done
      searchBox.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(searchBox)
      NSLayoutConstraint.activate([searchBox.topAnchor.constraint(equalTo: view.topAnchor, constant: NativeSheetVC.TOP - NativeSheetVC.SEARCH_PAD),
                                   searchBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                                   searchBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
                                   searchBox.heightAnchor.constraint(equalToConstant: NativeSheetVC.SEARCH_H),
                                   table.topAnchor.constraint(equalTo: searchBox.bottomAnchor)])
      table.contentInset.top = NativeSheetVC.UNDER_SEARCH
      table.keyboardDismissMode = .onDrag
      let empty = UILabel(); empty.text = emptyText; empty.textColor = .secondaryLabel; empty.textAlignment = .center
      empty.font = .systemFont(ofSize: 15); empty.isHidden = true; table.backgroundView = empty
      NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
      NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    } else {
      table.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
    }
  }
  static let SEARCH_H: CGFloat = 56, SEARCH_PAD: CGFloat = 10, UNDER_SEARCH: CGFloat = 6   // (a minimal search bar: 56 tall, its field ~10 in)
  // the keyboard: the list's end clears it (the sheet has gone to full height)
  @objc private func keyboard(_ n: Notification) {
    var pad: CGFloat = 0
    if n.name != UIResponder.keyboardWillHideNotification, let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
       let win = view.window {
      pad = max(0, view.convert(view.bounds, to: win).maxY - end.minY)
    }
    kbPad = pad
    table.contentInset.bottom = baseBottom + kbPad
    table.verticalScrollIndicatorInsets.bottom = 22 + kbPad
  }
  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    frozen = true
    if let sh = sheetPresentationController { sh.animateChanges { sh.selectedDetentIdentifier = .large } }
  }
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
  func searchBar(_ searchBar: UISearchBar, textDidChange q: String) {
    frozen = true
    let t = q.trimmingCharacters(in: .whitespaces)
    let has = { (s: String) in s.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    sections = t.isEmpty ? allSections : allSections.compactMap { sec in
      let rows = sec.rows.filter { r in r.chips == nil && r.i >= 0 && (has(r.label) || has(r.find)) }
      return rows.isEmpty ? nil : Section(header: sec.header, rows: rows, photo: sec.photo, initials: sec.initials, color: sec.color)
    }
    if let c = customText, !t.isEmpty, !allSections.contains(where: { sec in sec.rows.contains { row in row.label.caseInsensitiveCompare(t) == .orderedSame } }) {
      sections.insert(Section(header: nil, rows: [Row(i: -2, label: c.replacingOccurrences(of: "%@", with: t), sub: nil, icon: "plus", danger: false, checked: false,
                                                     disabled: false, dot: nil, tint: nil, locked: false, chips: nil, chipKind: "")]), at: 0)
    }
    table.backgroundView?.isHidden = !sections.isEmpty
    table.reloadData()
    table.setContentOffset(CGPoint(x: 0, y: -table.contentInset.top), animated: false)
  }
  // a person's round picture: their photo (loaded once with the page's sign-in, then kept), else initials on their colour
  private func avatarImage(_ av: Avatar, row i: Int) -> UIImage {
    if let u = av.photo {
      if let img = NativeSheetVC.photos.object(forKey: u.absoluteString as NSString) { return img }
      if !NativeSheetVC.loading.contains(u.absoluteString), let load = loadPhoto {
        NativeSheetVC.loading.insert(u.absoluteString)
        load(u) { [weak self] img in
          NativeSheetVC.loading.remove(u.absoluteString)
          guard let img else { return }
          NativeSheetVC.photos.setObject(NativeSheetVC.roundAvatar(img), forKey: u.absoluteString as NSString)
          self?.refreshRows(photo: u)
        }
      }
    }
    let d: CGFloat = 30
    return UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { _ in
      av.color.setFill(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d)).fill()
      let f = UIFont.systemFont(ofSize: 12, weight: .semibold)
      let s = NSAttributedString(string: av.initials, attributes: [.font: f, .foregroundColor: UIColor.white])
      let z = s.size(); s.draw(at: CGPoint(x: (d - z.width) / 2, y: (d - z.height) / 2))
    }
  }
  private static func roundAvatar(_ src: UIImage) -> UIImage {
    let d: CGFloat = 30, w = src.size.width, h = src.size.height, k = min(w, h)
    guard k > 0 else { return src }
    let sc = d / k
    return UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { _ in
      UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d)).addClip()
      src.draw(in: CGRect(x: (d - w * sc) / 2, y: (d - h * sc) / 2, width: w * sc, height: h * sc))
    }
  }
  private func refreshRows(photo u: URL) {
    var ips: [IndexPath] = []
    for (s, sec) in sections.enumerated() { for (k, r) in sec.rows.enumerated() where r.avatar?.photo == u { ips.append(IndexPath(row: k, section: s)) } }
    let shown = Set(table.indexPathsForVisibleRows ?? [])
    let now = ips.filter { shown.contains($0) }
    if !now.isEmpty { table.reconfigureRows(at: now) }
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
    if frozen { lastContent = ch; return }
    // (first time: start at the very top of the list, below the room for the grab handle — with the insets set by
    //  hand a table otherwise starts at 0, which hid that room and put the first option against the handle)
    if lastContent < 0 { table.contentOffset = CGPoint(x: 0, y: -table.contentInset.top) }
    lastContent = ch
    resize()
  }
  private func resize() {
    let ch = table.contentSize.height
    // (iOS adds the home-bar strip below a sheet's height by itself — on a floating sheet too, where it just showed
    //  as empty space under the last option — so that strip is taken off here)
    let strip = presentingViewController?.view.window?.safeAreaInsets.bottom ?? view.window?.safeAreaInsets.bottom ?? 0
    let head = searchText != nil ? NativeSheetVC.TOP - NativeSheetVC.SEARCH_PAD + NativeSheetVC.SEARCH_H + NativeSheetVC.UNDER_SEARCH : NativeSheetVC.TOP
    fitHeight = max(120, head + ch + NativeSheetVC.END - (floating ? strip : 0) + (floating ? 0 : view.safeAreaInsets.bottom))
    // (a list too long for the sheet scrolls: at the end of the scroll its last option must clear the sheet's visible
    //  bottom edge by the same gap as a fitting list (Channel) — whatever of the sheet lies below that edge is added
    //  (measured once shown; until then iOS's home-bar strip). A list that fits gets none, so it never scrolls — the
    //  finger moves the sheet.)
    let cap = ((presentingViewController?.view.bounds.height ?? view.window?.bounds.height ?? 800) - 60) * 0.68
    scrolls = fitHeight > cap
    // (measured in the simulator: none of a floating sheet lies below its visible edge — 0 until measured)
    let below = floating ? (hiddenBelow ?? 0) : view.safeAreaInsets.bottom
    baseBottom = NativeSheetVC.END + (scrolls || !floating ? below : 0)
    table.contentInset.bottom = baseBottom + kbPad
    table.verticalScrollIndicatorInsets.bottom = 22 + (scrolls ? below : 0) + kbPad
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
    let lastRow = ls >= 0 ? table.rectForRow(at: IndexPath(row: sections[ls].rows.count - 1, section: ls)).maxY : table.contentSize.height
    let lastBottom = tableTop + lastRow - atEnd
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
  // (self-test: type into the search box as a person would)
  func selfSearch(_ q: String) { guard searchText != nil else { return }; searchBox.text = q; searchBarTextDidBeginEditing(searchBox); searchBar(searchBox, textDidChange: q) }
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
    if let av = r.avatar {
      c.image = avatarImage(av, row: r.i)
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
    let on = ticked[r.i] ?? r.checked
    cell.accessoryType = on ? .checkmark : .none
    if r.locked && !on { let lock = UIImageView(image: UIImage(systemName: "lock.fill")); lock.tintColor = .tertiaryLabel; cell.accessoryView = lock }
    cell.tintColor = .systemBlue
    cell.selectionStyle = r.disabled || (r.i < 0 && r.i != -2) ? .none : .default
    if #available(iOS 26, *) { cell.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6) }
    return cell
  }
  func tableView(_ tableView: UITableView, shouldHighlightRowAt ip: IndexPath) -> Bool { let r = sections[ip.section].rows[ip.row]; return r.chips == nil && !r.disabled && (r.i >= 0 || r.i == -2) }
  func tableView(_ tableView: UITableView, didSelectRowAt ip: IndexPath) {
    let r = sections[ip.section].rows[ip.row]
    if r.i == -2 { return choose(-2, (searchBox.text ?? "").trimmingCharacters(in: .whitespaces)) }   // (what's typed, as it is)
    guard r.chips == nil, !r.disabled, r.i >= 0 else { return }
    // ticking several (channels…): the sheet stays open, the tick flips here, the page is told each time
    if multi && r.multi {
      tableView.deselectRow(at: ip, animated: true)
      let on = !(ticked[r.i] ?? r.checked)
      ticked[r.i] = on
      if let cell = tableView.cellForRow(at: ip) { cell.accessoryType = on ? .checkmark : .none }
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


/* A date picked in a native sheet (the page's date fields on the iPhone): iPhone's own calendar, with Today and —
   when the field can be emptied — Clear. Tapping a day picks it and closes; dragging it down or tapping outside
   changes nothing. */
final class DateSheetVC: UIViewController, UISheetPresentationControllerDelegate {
  private let picker = UIDatePicker()
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
    picker.datePickerMode = .date
    picker.preferredDatePickerStyle = .inline
    if let v = a["value"] as? String, let d = fmt.date(from: v) { picker.date = d }
    if let v = a["min"] as? String, let d = fmt.date(from: v) { picker.minimumDate = d }
    if let v = a["max"] as? String, let d = fmt.date(from: v) { picker.maximumDate = d }
    modalPresentationStyle = .pageSheet
    if let sh = sheetPresentationController {
      // (sized to the calendar, with the same gap under it as under a native list's last option — Channel: END + the
      //  ~18 a list keeps after its last section)
      sh.detents = [.custom(identifier: .init("date")) { [weak self] ctx in min(ctx.maximumDetentValue, self?.fitHeight ?? 470) }]
      sh.prefersGrabberVisible = true
      sh.delegate = self
    }
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
    picker.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      self.finish(["ok": true, "date": self.fmt.string(from: self.picker.date)])
    }, for: .valueChanged)
    [today, clear, picker].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    NSLayoutConstraint.activate([
      clear.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22), clear.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
      today.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22), today.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
      picker.topAnchor.constraint(equalTo: today.bottomAnchor, constant: 4),
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    ])
  }
  private var fitHeight: CGFloat = 470
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard view.bounds.width > 0 else { return }
    let floating: Bool; if #available(iOS 26, *) { floating = true } else { floating = false }
    let strip = presentingViewController?.view.window?.safeAreaInsets.bottom ?? view.window?.safeAreaInsets.bottom ?? 0
    let pickerH = picker.systemLayoutSizeFitting(CGSize(width: view.bounds.width - 24, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    let h = max(320, picker.frame.minY + pickerH + NativeSheetVC.END + 18 - (floating ? strip : 0) + (floating ? 0 : view.safeAreaInsets.bottom))
    guard picker.frame.minY > 0, abs(h - fitHeight) > 0.5 else { return }
    fitHeight = h
    sheetPresentationController?.animateChanges { sheetPresentationController?.invalidateDetents() }
  }
  private func finish(_ r: [String: Any]) {
    guard let a = answer else { return }
    answer = nil
    dismiss(animated: true) { a(r) }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { let a = answer; answer = nil; a?(["ok": true, "cancel": true]) }
}
