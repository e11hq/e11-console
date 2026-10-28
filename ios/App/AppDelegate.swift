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
let SHELL_VERSION = 2
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
  var downloadFrom: [ObjectIdentifier: String] = [:]      // what each download is fetching (one at a time per file)
  var downloadWatch: [ObjectIdentifier: NSKeyValueObservation] = [:]
  var downloadNames: [ObjectIdentifier: String] = [:]
  var hud: DownloadHUD?
  var retrying = false
  var launchLock = true          // ask for Face ID when the app starts (not every time it comes back to the front)
  var authing = false            // Face ID is on screen (it makes the app inactive and active again: never a new lock)

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
    web.scrollView.alwaysBounceHorizontal = false
    web.scrollView.showsHorizontalScrollIndicator = false
    if #available(iOS 16.4, *) { web.isInspectable = true }
    view.addSubview(web)
    web.hideKeyboardBar()
    // Our pages never scroll as a whole (each page scrolls inside itself). iPhone scrolls the whole page up to
    // show a box being typed in and can leave it there after the keyboard goes, which pushed everything pinned
    // to the bottom (sheets, menus) below the screen: once the keyboard is down, it goes back to the top.
    offsetWatch = web.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
      guard let self = self, !self.keyboardUp, self.pageReady, sv.contentOffset != .zero else { return }
      DispatchQueue.main.async { if !self.keyboardUp, sv.contentOffset != .zero { sv.setContentOffset(.zero, animated: false) } }
    }
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in self?.keyboardUp = true }
    nc.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self else { return }
      self.keyboardUp = false
      if self.pageReady, self.web.scrollView.contentOffset != .zero { self.web.scrollView.setContentOffset(.zero, animated: true) }
    }
    tabBar.delegate = self
    tabBar.isHidden = true
    view.addSubview(tabBar)
    loadHome()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let b = view.bounds
    // the page always fills the screen (no black band under it); the tab bar floats over its bottom and the page
    // keeps that much room free (--ios-tabs-h, web/phone.css)
    web.frame = b
    let h = tabBar.sizeThatFits(b.size).height + view.safeAreaInsets.bottom
    tabBar.frame = CGRect(x: 0, y: b.height - h, width: b.width, height: h)
    let cover = tabBar.isHidden ? 0 : Int(h.rounded())
    if cover != tabCover { tabCover = cover; pageJS("document.documentElement.style.setProperty('--ios-tabs-h','\(cover)px')") }
    lockView?.frame = b
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
  var offsetWatch: NSKeyValueObservation?
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
    webView.hideKeyboardBar()
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
    for (i, t) in list.enumerated() {
      let b = t["badge"] as? String ?? ""
      tabBar.items?[i].badgeValue = b.isEmpty ? nil : b
      if (t["on"] as? Bool) == true { tabBar.selectedItem = tabBar.items?[i] }
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
    launchLock = false
    awayAt = nil
    if pageReady { pushState { st in if st == "on" { UIApplication.shared.registerForRemoteNotifications() } } }
  }
  func wentAway() { if !authing { awayAt = Date() } }
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
      authing = true
      ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Lock E11 Console with Face ID") { ok, _ in
        DispatchQueue.main.async {
          if ok { defaults.set(true, forKey: LOCK_KEY) }; done(["ok": true, "on": ok])
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.authing = false }
        }
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
      ("signin", pause(4000) + "return JSON.stringify({ host: location.host, top: (document.querySelector('h1, h2, img, form') || document.body).getBoundingClientRect().top })", {
        self.web.load(URLRequest(url: URL(string: "https://e11hq.cloudflareaccess.com/")!)) }),
    ]
    func run(_ i: Int) {
      if i >= steps.count { selfResult["frame"] = ["web": web.frame.height, "screen": view.bounds.height, "inset": web.scrollView.contentInsetAdjustmentBehavior == .never ? "never" : "auto", "insetTop": web.scrollView.adjustedContentInset.top, "host": web.url?.host ?? ""] as [String: Any]; return writeSelf("done") }
      let (name, js, before) = steps[i]
      before?()
      DispatchQueue.main.asyncAfter(deadline: .now() + (before == nil ? 0.2 : 1.5)) {
        self.probe(name, js) {
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
