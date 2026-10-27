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

// Version of this iPhone app's native part (raise it with changes the web app needs to know about)
let SHELL_VERSION = 1
let procEnv = ProcessInfo.processInfo.environment
let SELFTEST = procEnv["E11_SELFTEST"] ?? ""           // the build machine's self-test in the simulator
let info = Bundle.main.infoDictionary ?? [:]
let LOCK_KEY = "E11FaceIDLock", PUSH_OFF_KEY = "E11PushOff"
let defaults = UserDefaults.standard
// Live by default; Settings › E11 Console › Server can switch to the test copy
func serverURL() -> String {
  if let s = procEnv["E11_SERVER"], !s.isEmpty { return s }
  let live = info["E11ServerURL"] as? String ?? "https://console.e11hq.com"
  let test = info["E11TestServerURL"] as? String ?? "https://test.e11hq.com"
  return defaults.string(forKey: "e11_server") == "test" ? test : live
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
  var window: UIWindow?
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    let w = UIWindow(frame: UIScreen.main.bounds)
    w.backgroundColor = BG
    w.rootViewController = Main.shared
    w.makeKeyAndVisible()
    window = w
    if let n = launchOptions?[.remoteNotification] as? [AnyHashable: Any] { Main.shared.openPush(n) }
    return true
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
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    Main.shared.openPush(response.notification.request.content.userInfo)
    completionHandler()
  }
  func applicationDidBecomeActive(_ application: UIApplication) { Main.shared.becameActive() }
  func applicationDidEnterBackground(_ application: UIApplication) { Main.shared.wentAway() }
}

// (the page's message handler is held weakly, so the screen and the web view don't keep each other alive)
final class WeakHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(_ t: WKScriptMessageHandler) { target = t }
  func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

final class Main: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UITabBarDelegate, WKDownloadDelegate {
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
  var retrying = false

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
    web.navigationDelegate = self
    web.uiDelegate = self
    web.isOpaque = false
    web.backgroundColor = BG
    web.scrollView.backgroundColor = BG
    web.scrollView.contentInsetAdjustmentBehavior = .never   // the page handles the status bar area itself
    web.scrollView.bounces = false
    if #available(iOS 16.4, *) { web.isInspectable = true }
    view.addSubview(web)
    tabBar.delegate = self
    tabBar.isHidden = true
    view.addSubview(tabBar)
    loadHome()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let b = view.bounds
    if tabBar.isHidden {
      web.frame = b
    } else {
      let h = tabBar.sizeThatFits(b.size).height + view.safeAreaInsets.bottom
      tabBar.frame = CGRect(x: 0, y: b.height - h, width: b.width, height: h)
      web.frame = CGRect(x: 0, y: 0, width: b.width, height: b.height - h)
    }
    lockView?.frame = b
  }
  func loadHome(_ path: String = "/") {
    guard let u = URL(string: serverURL() + path) else { return }
    if !SELFTEST.isEmpty, let host = u.host, let email = procEnv["E11_SELFTEST_EMAIL"],
       let c = HTTPCookie(properties: [.domain: host, .path: "/", .name: "e11_dev_email", .value: email]) {
      web.configuration.websiteDataStore.httpCookieStore.setCookie(c) { self.web.load(URLRequest(url: u)) }
    } else { web.load(URLRequest(url: u)) }
  }
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
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let onServer = webView.url?.host == serverHost
    pageReady = onServer
    if onServer { flushPending(); if !SELFTEST.isEmpty && !started { started = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.selfTest() } } }
    else { tabBar.isHidden = true; view.setNeedsLayout() }   // (the sign-in page: no tabs)
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
    tabBar.isHidden = true; view.setNeedsLayout()
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
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let name = suggestedFilename.isEmpty ? "file" : suggestedFilename.replacingOccurrences(of: "/", with: "-")
    let url = dir.appendingPathComponent(name)
    downloads[ObjectIdentifier(download)] = url
    completionHandler(url)
  }
  func downloadDidFinish(_ download: WKDownload) {
    guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = view
    (presentedViewController ?? self).present(sheet, animated: true)
  }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    downloads.removeValue(forKey: ObjectIdentifier(download))
    pageJS("window.toast && toast('Download failed')")
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
    case "me": return "person.crop.circle"
    default: return "circle"
    }
  }
  func setTabs(_ a: [String: Any]) {
    let list = a["tabs"] as? [[String: Any]] ?? []
    let keys = list.map { $0["v"] as? String ?? "" }
    if keys != tabKeys || (tabBar.items?.count ?? 0) != keys.count {
      tabKeys = keys
      tabBar.items = list.enumerated().map { i, t in
        let v = t["v"] as? String ?? ""
        return UITabBarItem(title: t["label"] as? String ?? "", image: UIImage(systemName: symbol(v)), tag: i)
      }
    } else {
      for (i, t) in list.enumerated() { tabBar.items?[i].title = t["label"] as? String ?? "" }
    }
    for (i, t) in list.enumerated() {
      let b = t["badge"] as? String ?? ""
      tabBar.items?[i].badgeValue = b.isEmpty ? nil : b
      if (t["on"] as? Bool) == true { tabBar.selectedItem = tabBar.items?[i] }
    }
    let hide = (a["hidden"] as? Bool) == true || list.isEmpty
    if hide != tabBar.isHidden {
      tabBar.isHidden = hide
      UIView.animate(withDuration: 0.2) { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
    }
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
    if defaults.bool(forKey: LOCK_KEY), lockView == nil, awayAt == nil || Date().timeIntervalSince(awayAt!) > 600 { lock() }
    awayAt = nil
    if pageReady { pushState { st in if st == "on" { UIApplication.shared.registerForRemoteNotifications() } } }
  }
  func wentAway() { awayAt = Date() }
  func lock() {
    let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    v.frame = view.bounds
    let b = UIButton(type: .system)
    b.setTitle("Unlock E11 Console", for: .normal)
    b.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    b.tintColor = .white
    b.addTarget(self, action: #selector(unlock), for: .touchUpInside)
    b.translatesAutoresizingMaskIntoConstraints = false
    v.contentView.addSubview(b)
    b.centerXAnchor.constraint(equalTo: v.contentView.centerXAnchor).isActive = true
    b.centerYAnchor.constraint(equalTo: v.contentView.centerYAnchor).isActive = true
    view.addSubview(v)
    lockView = v
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.unlock() }
  }
  @objc func unlock() {
    let ctx = LAContext(); var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return unlocked() }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock E11 Console") { ok, _ in DispatchQueue.main.async { if ok { self.unlocked() } } }
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
      done(r)
    case "setTabs": setTabs(a); done(["ok": true])
    case "badge":
      let n = (a["n"] as? NSNumber)?.intValue ?? Int(a["n"] as? String ?? "") ?? 0
      UNUserNotificationCenter.current().setBadgeCount(max(0, n)) { _ in }
      done(["ok": true])
    case "setAppearance":
      statusStyle = (a["mode"] as? String) == "light" ? .darkContent : .lightContent
      setNeedsStatusBarAppearanceUpdate()
      done(["ok": true])
    case "openURL":
      let u = a["url"] as? String ?? ""
      guard u.range(of: "^(https?|mailto|tel):", options: [.regularExpression, .caseInsensitive]) != nil, let url = URL(string: u) else { return done(["ok": false, "error": "Only web links can be opened"]) }
      UIApplication.shared.open(url); done(["ok": true])
    case "haptic": UIImpactFeedbackGenerator(style: .light).impactOccurred(); done(["ok": true])
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
      ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Lock E11 Console with Face ID") { ok, _ in
        DispatchQueue.main.async { if ok { defaults.set(true, forKey: LOCK_KEY) }; done(["ok": true, "on": ok]) }
      }
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
  func selfTest() {
    let wait = "for (let i = 0; i < 120 && !(window.db && typeof currentUserId !== 'undefined' && currentUserId && document.getElementById('ph-tabs')); i++) await new Promise((r) => setTimeout(r, 250));"
    probe("page", wait + """
      await new Promise((r) => setTimeout(r, 1500));
      const info = await NativeMac.call('appInfo');
      return JSON.stringify({ ios: document.documentElement.classList.contains('ios-app'), phone: !!(window.Phone && Phone.on), isIOSApp: Host.isIOSApp, isMacApp: Host.isMacApp,
        webTabsShown: getComputedStyle(document.getElementById('ph-tabs')).display !== 'none', view: ui.view, appInfo: info,
        top: getComputedStyle(document.documentElement).getPropertyValue('--ph-top'), unknown: await NativeMac.call('nope').then(() => 'answered').catch((e) => e.message) });
      """) {
      self.writeSelf("home")
      DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        if let i = self.tabKeys.firstIndex(of: "inbox"), let item = self.tabBar.items?[i] { self.tabBar.selectedItem = item; self.tabBar(self.tabBar, didSelect: item) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
          self.probe("inbox", "return JSON.stringify({ view: ui.view })") {
            self.writeSelf("inbox")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
              self.probe("task", "const t = db.tasks.find((x) => !x.parentId && !x.done); if (t) openTask(t.id); await new Promise((r) => setTimeout(r, 1500)); return JSON.stringify({ taskOpen: !!ui.taskId })") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                  self.writeSelf("task")
                  DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    self.probe("back", "closeDetail(); await new Promise((r) => setTimeout(r, 800)); return JSON.stringify({ taskOpen: !!ui.taskId })") {
                      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.writeSelf("done") }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
