// E11 Console for Mac — the native app (Swift) around the E11 Console server (console.e11hq.com).
// Built by GitHub's Macs (mac/swift/build.sh) into one program for Intel and Apple-silicon Macs; the one-line
// installer downloads it, puts it into an app with this server's address and icon, and signs it for that Mac,
// so no Apple Developer account is needed. Screens, data and updates all come live from the server.
//
// It answers the same commands as the earlier Mac app (mac/main.js), so the web app works with both:
// file picker + reading picked files in pieces, saving downloads, opening links, notifications with sound,
// Dock badge, light/dark window, Dock icon, the page's own title bar (drag / zoom), app info.
// New here: clicking a notification opens what it's about, Touch ID lock (optional), <input type=file>,
// and the page's alert / confirm boxes.
import Cocoa
import WebKit
import UserNotifications
import LocalAuthentication
import CryptoKit
#if APPSTORE
import ServiceManagement
#endif

// Version of this Mac app's native part. Raise it when a change here needs everyone to reinstall: the web app
// then shows a required-update banner in older Mac apps. (The earlier script app was 1–6.)
let SHELL_VERSION = 11   // 10: fast office use (shared-folder copies, office-network uploads and downloads) · 11: office-network downloads show their progress

let info = Bundle.main.infoDictionary ?? [:]
let env = ProcessInfo.processInfo.environment
#if APPSTORE
// The Mac App Store app (sandboxed, same code; mac/appstore/): Live by default, or Test / App Review, chosen in
// the app menu (Server) or with the "App Review sign-in" link under the sign-in page, like the iPhone app.
var SERVER: String {
  if let s = env["E11_SERVER"], !s.isEmpty { return s }
  switch defaults.string(forKey: "e11_server") {
  case "test": return (info["E11TestServerURL"] as? String) ?? "https://test.e11hq.com"
  case "review": return (info["E11ReviewServerURL"] as? String) ?? "https://review.e11hq.com"
  default: return (info["E11ServerURL"] as? String) ?? "https://console.e11hq.com"
  }
}
let IS_STORE = true
#else
let SERVER: String = {
  if let s = env["E11_SERVER"], !s.isEmpty { return s }   // (the build machine's self-test)
  return (info["E11ServerURL"] as? String) ?? "https://console.e11hq.com"
}()
let IS_STORE = false
#endif
let APP_NAME = (info["CFBundleName"] as? String) ?? "E11 Console"
let SELFTEST = env["E11_SELFTEST"] ?? ""
let defaults = UserDefaults.standard
let LOCK_KEY = "E11TouchIDLock"
var AT_LOGIN = CommandLine.arguments.contains("--login")   // started by "Open at Login": stay in the background
let LOGIN_AGENT = NSHomeDirectory() + "/Library/LaunchAgents/" + (Bundle.main.bundleIdentifier ?? "ae.e11.console.client") + ".login.plist"

func token() -> String { String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(UUID().uuidString.prefix(6)).lowercased() }
func uniquePath(_ dir: String, _ name: String) -> String {
  let clean = name.isEmpty ? "file" : name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
  let ns = clean as NSString
  let ext = ns.pathExtension, base = ext.isEmpty ? clean : ns.deletingPathExtension
  var p = dir + "/" + clean, i = 2
  while FileManager.default.fileExists(atPath: p) { p = dir + "/" + base + " (\(i))" + (ext.isEmpty ? "" : "." + ext); i += 1 }
  return p
}
func jsonString(_ v: Any) -> String {
  guard JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v), let s = String(data: d, encoding: .utf8) else { return "null" }
  return s
}
func jsString(_ s: String) -> String {   // a JavaScript string literal
  let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
  let a = String(data: d, encoding: .utf8) ?? "[\"\"]"
  return String(a.dropFirst().dropLast())
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, UNUserNotificationCenterDelegate {
  var window: NSWindow!
  var web: WKWebView!
  var picked: [String: String] = [:]   // token -> picked file
  var saving: [String: String] = [:]   // token -> file being written
  var pendingTask: String?
  var activity: NSObjectProtocol?
  var lockView: NSView?
  var lastActive = Date()
  var notifAllowed: Bool?
  var selftest: [String: Any] = [:]
  let LIGHTS_X: CGFloat = 20, BAR_H: CGFloat = 48

  /* ---------- start ---------- */
  func applicationWillFinishLaunching(_ n: Notification) {
    #if APPSTORE
    // (opened by macOS as a login item: stay in the background, like the Terminal app's --login)
    if let ev = NSAppleEventManager.shared().currentAppleEvent, ev.eventID == AEEventID(kAEOpenApplication),
       ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) { AT_LOGIN = true }
    #endif
    if SELFTEST.isEmpty { UNUserNotificationCenter.current().delegate = self }
    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:withReply:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
  }
  func applicationDidFinishLaunching(_ n: Notification) {
    // stay connected while minimised or in the background (no App Nap; the Mac can still sleep)
    activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Keeps E11 Console live and notifications arriving")
    buildMenu()
    buildWindow()
    if defaults.bool(forKey: LOCK_KEY) { lock() }
    // the lock also comes back when the screen sleeps or the Mac is locked
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(lockNow), name: NSWorkspace.screensDidSleepNotification, object: nil)
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(lockNow), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
    if !SELFTEST.isEmpty { startSelfTest() }
    #if APPSTORE
    registerPush()
    #endif
  }
  func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool { showWindow(); return true }
  func applicationDidBecomeActive(_ n: Notification) {
    // Touch ID lock: again after 10 minutes away
    if defaults.bool(forKey: LOCK_KEY), lockView == nil, Date().timeIntervalSince(lastActive) > 600 { lock() }
  }
  func applicationDidResignActive(_ n: Notification) {
    lastActive = Date()
    #if APPSTORE
    if web?.url?.host == URL(string: SERVER)?.host { shareSignIn() }
    #endif
  }
  func showWindow() {
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /* ---------- links: e11console://task/<id> ---------- */
  @objc func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
    openLink(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "")
  }
  func openLink(_ url: String) {
    // from the widget: e11console://open?plan=<id> or ?view=home|plans|fin-dash
    if let q = URLComponents(string: url)?.queryItems, q.first(where: { $0.name == "task" }) == nil,
       let item = q.first(where: { ["plan", "view"].contains($0.name) }), let v = item.value, v.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil {
      let d = item.name == "plan" ? ["planId": v] : ["view": v]
      if web != nil, !web.isLoading, web.url?.host == URL(string: SERVER)?.host { pageJS("window.__e11Widget && window.__e11Widget(\(jsonString(d)))") }
      if window != nil { showWindow() }
      return
    }
    guard let r = url.range(of: "(?:task/|[?&]task=)([A-Za-z0-9_-]{1,80})", options: .regularExpression) else { if window != nil { showWindow() }; return }
    let m = String(url[r])
    let id = m.replacingOccurrences(of: "^(?:task/|[?&]task=)", with: "", options: .regularExpression)
    if web == nil { pendingTask = id; return }
    let ready = !web.isLoading && (web.url?.host == URL(string: SERVER)?.host)
    if !ready { pendingTask = id; loadHome(); showWindow(); return }
    pageJS("window.__e11OpenTask ? window.__e11OpenTask(\(jsString(id))) : (location.href = '/?task=' + \(jsString(id)))")
    showWindow()
  }

  /* ---------- window ---------- */
  func buildWindow() {
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = APP_NAME
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(srgbRed: 0.047, green: 0.051, blue: 0.059, alpha: 1)
    window.minSize = NSSize(width: 960, height: 620)
    window.center()
    window.setFrameAutosaveName("E11ConsoleClientWindow")
    window.delegate = self

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()   // stay signed in between launches
    config.userContentController.add(self, name: "e11")
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    web = WKWebView(frame: window.contentView!.bounds, configuration: config)
    web.autoresizingMask = [.width, .height]
    web.uiDelegate = self
    web.navigationDelegate = self
    #if APPSTORE
    if #available(macOS 12.0, *) { web.underPageBackgroundColor = window.backgroundColor }   // (public API only in the store app)
    #else
    web.setValue(false, forKey: "drawsBackground")
    if #available(macOS 13.3, *) { web.isInspectable = true }
    #endif
    window.contentView!.addSubview(web)
    #if APPSTORE
    reviewLink.frame = NSRect(x: 0, y: 14, width: window.contentView!.bounds.width, height: 30)
    reviewLink.autoresizingMask = [.width]
    window.contentView!.addSubview(reviewLink)
    #endif
    if !SELFTEST.isEmpty, let host = URL(string: SERVER)?.host, let email = env["E11_SELFTEST_EMAIL"],
       let c = HTTPCookie(properties: [.domain: host, .path: "/", .name: "e11_dev_email", .value: email]) {
      web.configuration.websiteDataStore.httpCookieStore.setCookie(c) { self.loadHome() }
    } else { loadHome() }
    placeLights()
    if AT_LOGIN { return }   // (loads and stays connected; the Dock icon brings the window)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func loadHome() {
    let path = pendingTask.map { "/?task=" + $0 } ?? "/"
    pendingTask = nil
    if let u = URL(string: SERVER + path) { web.load(URLRequest(url: u)) }
  }
  // The page draws its own 48px top strip; the close / minimise / full-screen buttons are centred in it
  // (like Electron's trafficLightPosition: the title-bar container grows, the buttons move).
  func placeLights() {
    guard let w = window, !w.styleMask.contains(.fullScreen),
          let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton),
          let zoom = w.standardWindowButton(.zoomButton), let bar = close.superview, let container = bar.superview else { return }
    let bh = close.frame.size.height
    container.frame = NSRect(x: container.frame.origin.x, y: w.frame.size.height - BAR_H, width: container.frame.size.width, height: BAR_H)
    bar.frame = NSRect(x: 0, y: 0, width: container.frame.size.width, height: BAR_H)
    var gap = mini.frame.origin.x - close.frame.origin.x
    if !(gap > 10 && gap < 40) { gap = 20 }
    let y = ((BAR_H - bh) / 2).rounded()
    for (i, b) in [close, mini, zoom].enumerated() { b.setFrameOrigin(NSPoint(x: LIGHTS_X + CGFloat(i) * gap, y: y)) }
  }
  // Closing the window keeps the app running in the background (like Slack): still connected, notifications and the
  // Dock badge keep coming; the Dock icon brings the window back. Quit (⌘Q) really quits.
  func windowShouldClose(_ w: NSWindow) -> Bool {
    if w.styleMask.contains(.fullScreen) {
      w.toggleFullScreen(nil)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { w.orderOut(nil) }
    } else { w.orderOut(nil) }
    return false
  }
  func windowDidResize(_ n: Notification) { placeLights() }
  func windowDidEndLiveResize(_ n: Notification) { placeLights() }
  func windowDidBecomeKey(_ n: Notification) { placeLights() }
  func windowDidEnterFullScreen(_ n: Notification) { pageJS("document.documentElement.classList.add('mac-fs')") }
  func windowDidExitFullScreen(_ n: Notification) { placeLights(); pageJS("document.documentElement.classList.remove('mac-fs')") }
  func pageJS(_ js: String) { web?.evaluateJavaScript(js, completionHandler: nil) }

  /* ---------- the page's own boxes and windows ---------- */
  // links that open a new window (target=_blank) go to the default browser
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if let u = action.request.url { NSWorkspace.shared.open(u) }
    return nil
  }
  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK")
    a.beginSheetModal(for: window) { _ in completionHandler() }
  }
  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
    a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
  }
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
    let p = NSOpenPanel()
    p.canChooseFiles = true; p.canChooseDirectories = false
    p.allowsMultipleSelection = parameters.allowsMultipleSelection
    p.beginSheetModal(for: window) { r in completionHandler(r == .OK ? p.urls : nil) }
  }
  // the server may stop answering for a moment (an update): try again shortly instead of a blank window
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { retryLater(error) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retryLater(error) }
  func retryLater(_ error: Error) {
    let e = error as NSError
    let offline = [NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                   NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorBadServerResponse, NSURLErrorSecureConnectionFailed]
    guard e.domain == NSURLErrorDomain, offline.contains(e.code) else { return }
    showOffline()
  }
  var retrying = false
  func showOffline() {
    if retrying { return }
    retrying = true
    let html = "<html><body style=\"background:#0c0d0f;color:#bbb;font:15px -apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0\"><div style=\"text-align:center\"><b style=\"color:#fff\">Can’t reach E11 Console</b><br><br>Check your internet connection. Trying again…</div></body></html>"
    web.loadHTMLString(html, baseURL: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.retrying = false; self.loadHome() }
  }
  #if APPSTORE
  // under the Cloudflare sign-in page only: "App Review sign-in" (Apple's reviewer can't get an E11 email code)
  lazy var reviewLink: NSButton = {
    let b = NSButton(title: "App Review sign-in", target: self, action: #selector(toReview))
    b.isBordered = false
    b.font = .systemFont(ofSize: 13, weight: .medium)
    b.contentTintColor = .secondaryLabelColor
    b.setAccessibilityIdentifier("review-sign-in")
    b.isHidden = true
    return b
  }()
  @objc func toReview() { setServer("review") }
  func setServer(_ k: String) { defaults.set(k, forKey: "e11_server"); reviewLink.isHidden = true; loadHome(); buildMenu() }
  @objc func pickServer(_ sender: NSMenuItem) { setServer(sender.representedObject as? String ?? "live") }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    reviewLink.isHidden = !(webView.url?.host ?? "").hasSuffix(".cloudflareaccess.com")
    if webView.url?.host == URL(string: SERVER)?.host { shareSignIn(); sendApnsToken(tries: 0) }
  }
  /* Apple's notifications (APNs) for the Mac App Store app (Haris, 2026-10-30): every notification comes as the
     Mac's own, also when the app is closed or in front; the page draws none of its own (AppPush in app.js). The
     Notification Service Extension (notify/) confirms each one, so the ones a Mac that was offline missed are sent
     again. */
  var apnsToken: String?
  func registerPush() {
    guard SELFTEST.isEmpty else { return }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
      DispatchQueue.main.async { NSApp.registerForRemoteNotifications() }
    }
  }
  func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsToken = hex
    WidgetShare.write("apnsToken", Data(hex.utf8))
    sendApnsToken(tries: 0)
  }
  func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    NSLog("E11 Console: Apple notifications not available: %@", error.localizedDescription)
  }
  // to the page once it's signed in and has its data (it registers this Mac's address with the server)
  func sendApnsToken(tries: Int) {
    guard let hex = apnsToken, tries < 90, let web = web else { return }
    #if DEBUG
    let env = "sandbox"
    #else
    let env = "production"
    #endif
    let arg = jsonText(["token": hex, "env": env, "ack": true, "platform": "mac"])
    web.evaluateJavaScript("(typeof window.__e11ApnsToken === 'function' && typeof db !== 'undefined' && db && typeof currentUserId !== 'undefined' && currentUserId) ? (window.__e11ApnsToken(\(arg)), 'ok') : 'wait'") { r, _ in
      if (r as? String) != "ok" { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.sendApnsToken(tries: tries + 1) } }
    }
  }
  // a notification clicked: the window comes forward and the page opens what it's about
  func openPush(_ d: [String: Any], tries: Int = 0) {
    if tries == 0 { showWindow() }
    guard tries < 30, let web = web else { return }
    web.evaluateJavaScript("(typeof window.__e11PushTap === 'function' && typeof db !== 'undefined' && db && typeof currentUserId !== 'undefined' && currentUserId) ? (window.__e11PushTap(\(jsonText(d))), 'ok') : 'wait'") { r, _ in
      if (r as? String) != "ok" { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.openPush(d, tries: tries + 1) } }
    }
  }
  func jsonText(_ v: Any) -> String {
    guard JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v), let t = String(data: d, encoding: .utf8) else { return "null" }
    return t
  }
  // the widget (widget/E11Widget.swift) asks the server with this app's own sign-in: server + cookies to the shared Keychain
  func shareSignIn() {
    web?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in WidgetShare.saveSignIn(server: SERVER, cookies: cookies) }
  }
  #endif
  // links the window can't show itself (mailto:, e11console:, …) go to the Mac
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    #if APPSTORE
    // the review copy's "Sign in to E11 Console" link goes back to the live server
    if defaults.string(forKey: "e11_server") == "review", action.targetFrame?.isMainFrame != false,
       let u = action.request.url, u.host == URL(string: (info["E11ServerURL"] as? String) ?? "https://console.e11hq.com")?.host {
      setServer("live"); return decisionHandler(.cancel)
    }
    #endif
    if let u = action.request.url, let s = u.scheme?.lowercased(), !["http", "https", "about", "blob", "data"].contains(s) {
      if action.targetFrame?.isMainFrame != false {
        if s == "e11console" || s == "e11console-test" { openLink(u.absoluteString) }
        else if ["mailto", "tel"].contains(s) { NSWorkspace.shared.open(u) }
      }
      return decisionHandler(.cancel)
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if response.isForMainFrame, let r = response.response as? HTTPURLResponse, r.url?.host == URL(string: SERVER)?.host,
       (502...504).contains(r.statusCode) || (520...530).contains(r.statusCode) {
      decisionHandler(.cancel)
      DispatchQueue.main.async { self.showOffline() }
      return
    }
    decisionHandler(.allow)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

  /* ---------- commands from the page ---------- */
  func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let raw = message.body as? String, let d = raw.data(using: .utf8),
          let msg = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
    let id = msg["id"] ?? NSNull()
    let cmd = msg["cmd"] as? String ?? ""
    let args = msg["args"] as? [String: Any] ?? [:]
    run(cmd, args) { res in
      let js = "window.__e11NativeReply && window.__e11NativeReply(\(jsonString([id]).dropFirst().dropLast()),\(jsonString(res)))"
      self.pageJS(js)
    }
  }
  func run(_ cmd: String, _ a: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    switch cmd {
    case "pickLocalFiles": pickLocalFiles(a, done)
    case "readLocalChunk": done(readLocalChunk(a))
    case "saveFile": done(saveFile(a))
    case "openURL":
      let u = a["url"] as? String ?? ""
      guard u.range(of: "^(https?|mailto):", options: [.regularExpression, .caseInsensitive]) != nil, let url = URL(string: u) else { return done(["ok": false, "error": "Only web links can be opened"]) }
      NSWorkspace.shared.open(url); done(["ok": true])
    case "notify": notify(a); done(["ok": true])
    case "badge":
      let n = a["n"]
      let s = (n as? NSNumber).map { $0.intValue > 0 ? "\($0.intValue)" : "" } ?? (n as? String ?? "")
      NSApp.dockTile.badgeLabel = s.isEmpty ? nil : s
      done(["ok": true])
    case "setAppearance":
      let light = (a["mode"] as? String) == "light"
      window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
      window.backgroundColor = light ? .white : NSColor(srgbRed: 0.047, green: 0.051, blue: 0.059, alpha: 1)
      placeLights()
      done(["ok": true])
    case "setIcon": done(setIcon(a))
    case "dragWindow":
      if let ev = NSApp.currentEvent { window.performDrag(with: ev) }
      done(["ok": true])
    case "zoomWindow": window.performZoom(nil); done(["ok": true])
    case "shareInfo": DispatchQueue.global(qos: .userInitiated).async { let r = self.shareInfo(a); DispatchQueue.main.async { done(r) } }
    case "uploadLocal": done(uploadLocal(a))
    case "uploadStatus": done(uploadStatus(a))
    case "uploadCancel": (jobs[a["job"] as? String ?? ""])?.cancel(); done(["ok": true])
    case "downloadLocal":
      if (a["job"] as? Bool) == true { done(downloadLocalJob(a)) } else { downloadLocal(a, done) }
    case "downloadStatus":
      let id = a["job"] as? String ?? ""
      guard let j = downloads[id] else { return done(["ok": false, "state": "error", "error": "No such download"]) }
      let st = j.snapshot()
      if let x = st["state"] as? String, x != "receiving" { downloads.removeValue(forKey: id) }
      done(st)
    case "downloadCancel": (downloads[a["job"] as? String ?? ""])?.cancel(); done(["ok": true])
    case "selftestFile":
      guard !SELFTEST.isEmpty else { return done(["ok": false, "error": "Unknown command selftestFile"]) }
      let n = (a["size"] as? NSNumber)?.intValue ?? 1000
      let p = NSTemporaryDirectory() + "e11-selftest-\(token()).bin"
      var bytes = [UInt8](repeating: 0, count: n); for i in 0..<n { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
      FileManager.default.createFile(atPath: p, contents: Data(bytes))
      let t = token(); picked[t] = p
      done(["ok": true, "token": t, "size": n])
    case "appInfo":
      done(["ok": true, "server": SERVER, "shell": SHELL_VERSION, "native": "swift",
            "version": info["CFBundleShortVersionString"] as? String ?? "3.0.0", "touchID": defaults.bool(forKey: LOCK_KEY),
            "glass": FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/Contents/Resources/Assets.car"), "store": IS_STORE, "apns": IS_STORE])
    default: done(["ok": false, "error": "Unknown command " + cmd])
    }
  }

  func pickLocalFiles(_ a: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    let p = NSOpenPanel()
    NSApp.activate(ignoringOtherApps: true)
    p.canChooseFiles = true; p.canChooseDirectories = false
    p.allowsMultipleSelection = (a["multiple"] as? Bool) != false
    if (a["images"] as? Bool) == true { p.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff", "bmp", "svg"] }
    p.prompt = a["prompt"] as? String ?? "Choose"
    if let m = a["message"] as? String { p.message = m }
    p.beginSheetModal(for: window) { r in
      guard r == .OK else { return done(["ok": true, "files": []]) }
      var out: [[String: Any]] = []
      for u in p.urls {
        let t = token()
        self.picked[t] = u.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        out.append(["token": t, "name": u.lastPathComponent, "size": size])
      }
      done(["ok": true, "files": out])
    }
  }
  func readLocalChunk(_ a: [String: Any]) -> [String: Any] {
    let t = a["token"] as? String ?? ""
    guard let p = picked[t] else { return ["ok": false, "error": "File no longer available"] }
    guard let fh = FileHandle(forReadingAtPath: p) else { return ["ok": false, "error": "Could not read " + (p as NSString).lastPathComponent] }
    defer { fh.closeFile() }
    fh.seek(toFileOffset: UInt64((a["offset"] as? NSNumber)?.int64Value ?? 0))
    let data = fh.readData(ofLength: (a["length"] as? NSNumber)?.intValue ?? 0)
    if (a["last"] as? Bool) == true { picked.removeValue(forKey: t) }
    return ["ok": true, "b64": data.base64EncodedString()]
  }
  /* ---------- fast office use (server office.js) ---------- */
  // Is a picked file on the NAS shared folder? Its place in the share, size and fingerprint (SHA-256 of its first and
  // last MB, the same as the server checks), so the server can copy it on the NAS instead of it being uploaded
  func shareInfo(_ a: [String: Any]) -> [String: Any] {
    guard let p = picked[a["token"] as? String ?? ""] else { return ["ok": false, "error": "File no longer available"] }
    let want = (a["share"] as? String ?? "E11 Share").lowercased()
    let u = URL(fileURLWithPath: p)
    guard let rv = try? u.resourceValues(forKeys: [.volumeURLKey, .volumeURLForRemountingKey]),
          let vol = rv.volume, let remote = rv.volumeURLForRemounting,
          ["smb", "cifs", "afp", "nfs"].contains((remote.scheme ?? "").lowercased()) else { return ["ok": true, "onShare": false] }
    let shareName = (remote.path as NSString).lastPathComponent.removingPercentEncoding ?? remote.lastPathComponent
    guard shareName.lowercased() == want else { return ["ok": true, "onShare": false, "share": shareName] }
    let root = vol.standardizedFileURL.path.hasSuffix("/") ? vol.standardizedFileURL.path : vol.standardizedFileURL.path + "/"
    let full = u.standardizedFileURL.path
    guard full.hasPrefix(root) else { return ["ok": true, "onShare": false] }
    let rel = String(full.dropFirst(root.count))
    let size = ((try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.int64Value ?? 0
    guard let fh = FileHandle(forReadingAtPath: p) else { return ["ok": true, "onShare": false] }
    defer { fh.closeFile() }
    let n = Int(min(Int64(1 << 20), size))
    let head = fh.readData(ofLength: n)
    fh.seek(toFileOffset: UInt64(max(0, size - Int64(n))))
    let tail = fh.readData(ofLength: n)
    var h = SHA256(); h.update(data: head); h.update(data: tail)
    let fp = h.finalize().map { String(format: "%02x", $0) }.joined()
    return ["ok": true, "onShare": true, "rel": rel, "size": size, "fp": fp]
  }
  // Uploads straight to the NAS over the office network: the server gave a pass (ticket) and its certificate's
  // fingerprint (cert); only a server showing that certificate gets the file. Runs in the background; the page
  // follows it with uploadStatus and can stop it with uploadCancel.
  var jobs: [String: LocalJob] = [:]
  func uploadLocal(_ a: [String: Any]) -> [String: Any] {
    let t = a["token"] as? String ?? ""
    guard let p = picked[t] else { return ["ok": false, "error": "File no longer available"] }
    guard let base = a["url"] as? String, let ticket = a["ticket"] as? String, let pin = a["cert"] as? String, base.hasPrefix("https://") else { return ["ok": false, "error": "Missing details"] }
    let size = ((try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.int64Value ?? 0
    let id = token()
    let job = LocalJob(size: size)
    jobs[id] = job
    DispatchQueue.global(qos: .userInitiated).async {
      job.run(path: p, base: base, ticket: ticket, pin: pin)
      if job.snapshot()["state"] as? String == "done" { DispatchQueue.main.async { self.picked.removeValue(forKey: t) } }
    }
    return ["ok": true, "job": id]
  }
  func uploadStatus(_ a: [String: Any]) -> [String: Any] {
    let id = a["job"] as? String ?? ""
    guard let j = jobs[id] else { return ["ok": false, "state": "error", "error": "No such upload"] }
    let s = j.snapshot()
    if let st = s["state"] as? String, st != "sending" { jobs.removeValue(forKey: id) }
    return s
  }
  // Downloads straight from the NAS over the office network, into Downloads (shown in Finder) or opened
  func downloadLocal(_ a: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
    guard let base = a["url"] as? String, let ticket = a["ticket"] as? String, let pin = a["cert"] as? String, base.hasPrefix("https://"),
          var comps = URLComponents(string: base + "/local/file") else { return done(["ok": false, "error": "Missing details"]) }
    comps.queryItems = [URLQueryItem(name: "t", value: ticket)]
    guard let url = comps.url else { return done(["ok": false, "error": "Bad address"]) }
    let open = (a["open"] as? Bool) == true, name = a["name"] as? String ?? "file"
    let session = URLSession(configuration: .ephemeral, delegate: Pinner(pin), delegateQueue: nil)
    var req = URLRequest(url: url); req.timeoutInterval = 60
    session.downloadTask(with: req) { tmp, resp, err in
      defer { session.finishTasksAndInvalidate() }
      guard err == nil, let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
        return DispatchQueue.main.async { done(["ok": false, "error": err?.localizedDescription ?? "Download failed"]) }
      }
      let dir = open ? (NSTemporaryDirectory() as NSString).appendingPathComponent("E11 Console") : NSHomeDirectory() + "/Downloads"
      try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
      let dest = uniquePath(dir, name)
      do { try FileManager.default.moveItem(at: tmp, to: URL(fileURLWithPath: dest)) } catch { return DispatchQueue.main.async { done(["ok": false, "error": "Couldn’t save to " + dir]) } }
      var u = URL(fileURLWithPath: dest)
      var rv = URLResourceValues()
      rv.quarantineProperties = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String, kLSQuarantineAgentNameKey as String: APP_NAME]
      try? u.setResourceValues(rv)
      DispatchQueue.main.async {
        if open { NSWorkspace.shared.open(u) } else if SELFTEST.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        done(["ok": true, "path": dest])
      }
    }.resume()
  }

  // The same, in the background: the page follows it with downloadStatus (how much has arrived) and can stop it with
  // downloadCancel
  var downloads: [String: LocalDownload] = [:]
  func downloadLocalJob(_ a: [String: Any]) -> [String: Any] {
    guard let base = a["url"] as? String, let ticket = a["ticket"] as? String, let pin = a["cert"] as? String, base.hasPrefix("https://"),
          var comps = URLComponents(string: base + "/local/file") else { return ["ok": false, "error": "Missing details"] }
    comps.queryItems = [URLQueryItem(name: "t", value: ticket)]
    guard let url = comps.url else { return ["ok": false, "error": "Bad address"] }
    let id = token()
    let d = LocalDownload(pin: pin, name: a["name"] as? String ?? "file", open: (a["open"] as? Bool) == true)
    downloads[id] = d
    d.start(url)
    return ["ok": true, "job": id]
  }

  // a download in pieces: into Downloads (and shown in Finder), or a temporary folder (and opened)
  func saveFile(_ a: [String: Any]) -> [String: Any] {
    let t = a["token"] as? String ?? token()
    let open = (a["open"] as? Bool) == true
    let data = Data(base64Encoded: a["b64"] as? String ?? "") ?? Data()
    var dest = saving[t]
    if dest == nil {
      let dir = open ? (NSTemporaryDirectory() as NSString).appendingPathComponent("E11 Console") : NSHomeDirectory() + "/Downloads"
      try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
      let p = uniquePath(dir, a["name"] as? String ?? "file")
      guard FileManager.default.createFile(atPath: p, contents: data) else { return ["ok": false, "error": "Couldn’t save to " + dir] }
      saving[t] = p; dest = p
    } else {
      guard let h = FileHandle(forWritingAtPath: dest!) else { return ["ok": false, "error": "Couldn’t write " + (dest! as NSString).lastPathComponent] }
      defer { h.closeFile() }
      do { try h.seekToEnd(); try h.write(contentsOf: data) } catch { return ["ok": false, "error": "Couldn’t save — is the disk full?"] }
    }
    if (a["done"] as? Bool) == true {
      saving.removeValue(forKey: t)
      var u = URL(fileURLWithPath: dest!)
      if (a["name"] as? String) != "Update E11 Console.terminal" {   // (the app's own updater runs as it is)
        var rv = URLResourceValues()
        rv.quarantineProperties = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String, kLSQuarantineAgentNameKey as String: APP_NAME]
        try? u.setResourceValues(rv)
      }
      if open { NSWorkspace.shared.open(u) }
      else if SELFTEST.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dest!)]) }
    }
    return ["ok": true, "path": dest!]
  }
  // Dock icon chosen on the server: shown now, and written onto the app so it shows when closed too
  func setIcon(_ a: [String: Any]) -> [String: Any] {
    let appPath = Bundle.main.bundlePath
    if (a["reset"] as? Bool) == true {
      // back to the app's own icon: the glass one (macOS draws it) when the app has it
      if !IS_STORE { NSWorkspace.shared.setIcon(nil, forFile: appPath, options: []) }
      NSApp.applicationIconImage = nil
      return ["ok": true, "saved": false]
    }
    guard let d = Data(base64Encoded: a["b64"] as? String ?? ""), let img = NSImage(data: d) else { return ["ok": false, "error": "Bad icon image"] }
    NSApp.applicationIconImage = img
    // (the Mac App Store app can't write onto itself: the icon shows while it runs)
    if IS_STORE { return ["ok": true, "saved": false] }
    return ["ok": true, "saved": NSWorkspace.shared.setIcon(img, forFile: appPath, options: [])]
  }

  /* ---------- notifications ---------- */
  func notify(_ a: [String: Any]) {
    if let s = a["sound"] as? String, !s.isEmpty { NSSound(named: NSSound.Name(s))?.play() }
    if (a["banner"] as? Bool) == false || !SELFTEST.isEmpty { return }
    let title = a["title"] as? String ?? APP_NAME, body = a["body"] as? String ?? "", sub = a["subtitle"] as? String ?? ""
    let click = a["click"] as? String ?? ""
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .badge]) { ok, _ in
      DispatchQueue.main.async {
        self.notifAllowed = ok
        if ok {
          let c = UNMutableNotificationContent()
          c.title = title; c.body = body; if !sub.isEmpty { c.subtitle = sub }
          c.userInfo = ["click": click]
          center.add(UNNotificationRequest(identifier: token(), content: c, trigger: nil), withCompletionHandler: nil)
        } else { self.oldNotify(title, sub, body, click) }
      }
    }
  }
  // Macs that don't allow the newer notifications for an app signed only on that Mac: the older kind
  func oldNotify(_ title: String, _ sub: String, _ body: String, _ click: String) {
    let n = NSUserNotification()
    n.title = title; n.informativeText = body; if !sub.isEmpty { n.subtitle = sub }
    n.userInfo = ["click": click]
    NSUserNotificationCenter.default.delegate = OldNotifs.shared
    NSUserNotificationCenter.default.deliver(n)
  }
  func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
    // (Apple's own from the server: also its sound and the Dock badge)
    let remote = n.request.content.userInfo["e11"] != nil
    if #available(macOS 11.0, *) { done(remote ? [.banner, .list, .sound, .badge] : [.banner, .list]) } else { done([.alert]) }
  }
  func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
    #if APPSTORE
    if let d = r.notification.request.content.userInfo["e11"] as? [String: Any] { DispatchQueue.main.async { self.openPush(d) }; return done() }
    #endif
    let k = r.notification.request.content.userInfo["click"] as? String ?? ""
    DispatchQueue.main.async { self.clicked(k) }
    done()
  }
  func clicked(_ key: String) {
    if window == nil { return }
    showWindow()
    if !key.isEmpty { pageJS("window.__e11NotifClick && window.__e11NotifClick(\(jsString(key)))") }
  }

  /* ---------- Touch ID lock (optional, menu: E11 Console › Lock with Touch ID) ---------- */
  func lock() {
    guard lockView == nil, let cv = window.contentView else { return }
    let v = NSVisualEffectView(frame: cv.bounds)
    v.autoresizingMask = [.width, .height]; v.material = .hudWindow; v.blendingMode = .withinWindow; v.state = .active
    let b = NSButton(title: "Unlock E11 Console", target: self, action: #selector(unlock))
    b.bezelStyle = .rounded; b.controlSize = .large; b.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(b)
    b.centerXAnchor.constraint(equalTo: v.centerXAnchor).isActive = true
    b.centerYAnchor.constraint(equalTo: v.centerYAnchor).isActive = true
    cv.addSubview(v, positioned: .above, relativeTo: web)
    lockView = v
    web.isHidden = true
    window.makeFirstResponder(b)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.unlock() }
  }
  @objc func unlock() {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { unlocked(); return }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock E11 Console") { ok, _ in
      DispatchQueue.main.async { if ok { self.unlocked() } }
    }
  }
  func unlocked() {
    lockView?.removeFromSuperview(); lockView = nil
    web.isHidden = false
    window.makeFirstResponder(web)
    lastActive = Date()
  }
  @objc func lockNow() { if defaults.bool(forKey: LOCK_KEY) { lock() } }
  /* ---------- Open at Login (a small login item in ~/Library/LaunchAgents; no account needed) ---------- */
  func atLogin() -> Bool {
    #if APPSTORE
    if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
    return false
    #else
    return FileManager.default.fileExists(atPath: LOGIN_AGENT)
    #endif
  }
  @discardableResult func setAtLogin(_ on: Bool) -> Bool {
    #if APPSTORE
    // (the store app is sandboxed: macOS's own login item, listed in System Settings › General › Login Items)
    if #available(macOS 13.0, *) {
      do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { return false }
      return atLogin() == on
    }
    return false
    #endif
    if !on { try? FileManager.default.removeItem(atPath: LOGIN_AGENT); return !atLogin() }
    let plist: [String: Any] = ["Label": ((LOGIN_AGENT as NSString).lastPathComponent as NSString).deletingPathExtension,
                                "ProgramArguments": ["/usr/bin/open", "-g", "-a", Bundle.main.bundlePath, "--args", "--login"],
                                "RunAtLoad": true, "LimitLoadToSessionType": "Aqua"]
    try? FileManager.default.createDirectory(atPath: (LOGIN_AGENT as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    guard let d = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return false }
    return FileManager.default.createFile(atPath: LOGIN_AGENT, contents: d)
  }
  @objc func toggleLogin(_ sender: NSMenuItem) {
    let on = !atLogin()
    if !setAtLogin(on) { let a = NSAlert(); a.messageText = "Couldn’t change Open at Login."; a.runModal() }
    sender.state = atLogin() ? .on : .off
  }
  @objc func toggleLock(_ sender: NSMenuItem) {
    let on = !defaults.bool(forKey: LOCK_KEY)
    if on {
      let ctx = LAContext(); var err: NSError?
      guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
        let a = NSAlert(); a.messageText = "This Mac can’t lock apps with Touch ID or a password."; a.runModal(); return
      }
    }
    defaults.set(on, forKey: LOCK_KEY)
    sender.state = on ? .on : .off
  }

  /* ---------- menu bar ---------- */
  @objc func reloadPage(_ s: Any?) { web.reload() }
  @objc func goHome(_ s: Any?) { loadHome() }
  @objc func openInBrowser(_ s: Any?) { if let u = URL(string: SERVER + "/") { NSWorkspace.shared.open(u) } }
  @objc func zoomIn(_ s: Any?) { web.pageZoom = min(2, web.pageZoom + 0.1) }
  @objc func zoomOut(_ s: Any?) { web.pageZoom = max(0.6, web.pageZoom - 0.1) }
  @objc func zoomReset(_ s: Any?) { web.pageZoom = 1 }
  func item(_ title: String, _ action: Selector?, _ key: String = "", _ mask: NSEvent.ModifierFlags = .command, _ target: AnyObject? = nil) -> NSMenuItem {
    let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
    it.keyEquivalentModifierMask = mask
    if let t = target { it.target = t }
    return it
  }
  func buildMenu() {
    let main = NSMenu(title: "Main")
    func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
      let m = NSMenu(title: title); items.forEach { m.addItem($0) }
      let it = NSMenuItem(); it.submenu = m; main.addItem(it); return m
    }
    let lockItem = item("Lock with Touch ID", #selector(toggleLock(_:)), "", .command, self)
    lockItem.state = defaults.bool(forKey: LOCK_KEY) ? .on : .off
    let loginItem = item("Open at Login", #selector(toggleLogin(_:)), "", .command, self)
    loginItem.state = atLogin() ? .on : .off
    var serverItems: [NSMenuItem] = []
    #if APPSTORE
    let serverMenu = NSMenu(title: "Server")
    let cur = defaults.string(forKey: "e11_server") ?? "live"
    for (k, t) in [("live", "Live"), ("test", "Test"), ("review", "App Review")] {
      let it = item(t, #selector(pickServer(_:)), "", .command, self); it.representedObject = k; it.state = cur == k ? .on : .off
      serverMenu.addItem(it)
    }
    let serverItem = NSMenuItem(title: "Server", action: nil, keyEquivalent: ""); serverItem.submenu = serverMenu
    serverItems = [serverItem, .separator()]
    #endif
    _ = sub(APP_NAME, [
      item("About " + APP_NAME, #selector(NSApplication.orderFrontStandardAboutPanel(_:))), .separator(),
      loginItem, lockItem, .separator()] + serverItems + [
      item("Hide " + APP_NAME, #selector(NSApplication.hide(_:)), "h"),
      item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
      item("Show All", #selector(NSApplication.unhideAllApplications(_:))), .separator(),
      item("Quit " + APP_NAME, #selector(NSApplication.terminate(_:)), "q"),
    ])
    _ = sub("Edit", [
      item("Undo", Selector(("undo:")), "z"), item("Redo", Selector(("redo:")), "z", [.command, .shift]), .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x"), item("Copy", #selector(NSText.copy(_:)), "c"),
      item("Paste", #selector(NSText.paste(_:)), "v"), item("Select All", #selector(NSText.selectAll(_:)), "a"),
    ])
    _ = sub("View", [
      item("Reload", #selector(reloadPage(_:)), "r", .command, self),
      item("Go to Home", #selector(goHome(_:)), "h", [.command, .shift], self), .separator(),
      item("Actual Size", #selector(zoomReset(_:)), "0", .command, self),
      item("Zoom In", #selector(zoomIn(_:)), "+", .command, self),
      item("Zoom Out", #selector(zoomOut(_:)), "-", .command, self), .separator(),
      item("Open in Browser", #selector(openInBrowser(_:)), "", .command, self),
    ])
    let win = sub("Window", [
      item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
      item("Zoom", #selector(NSWindow.performZoom(_:))),
      item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]), .separator(),
      item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
    ])
    NSApp.mainMenu = main
    NSApp.windowsMenu = win
  }

  /* ---------- self-test on the build machine (E11_SELFTEST=<result file>) ---------- */
  // Loads the real web app from a local test server, then has the page call every command through the
  // same bridge it uses normally, and writes the answers (plus a picture of the window) for the build to check.
  func startSelfTest() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 90) { self.finishSelfTest(error: "timed out") }
    waitForPage(0)
  }
  func waitForPage(_ n: Int) {
    web.evaluateJavaScript("typeof NativeMac !== 'undefined' && typeof Host !== 'undefined' && !!document.querySelector('#app') ? (Host.isMacApp ? 'mac' : 'web') : 'wait'") { r, _ in
      let s = r as? String ?? "wait"
      if s == "wait" { if n < 120 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.waitForPage(n + 1) } } else { self.finishSelfTest(error: "the page never loaded") }; return }
      self.selftest["page"] = s
      self.selftest["url"] = self.web.url?.absoluteString ?? ""
      let js = """
      return await (async () => {
        const out = {};
        const t = async (k, f) => { try { out[k] = await f(); } catch (e) { out[k] = { error: String(e.message || e) }; } };
        await t('appInfo', () => NativeMac.call('appInfo'));
        await t('badge', () => NativeMac.call('badge', { n: 3 }));
        await t('badgeOff', () => NativeMac.call('badge', { n: 0 }));
        await t('notify', () => NativeMac.call('notify', { title: 'Test', body: 'Self-test', sound: 'Glass' }));
        await t('light', () => NativeMac.call('setAppearance', { mode: 'light' }));
        await t('dark', () => NativeMac.call('setAppearance', { mode: 'dark' }));
        await t('save1', () => NativeMac.call('saveFile', { token: 'st1', name: 'e11-selftest.txt', b64: btoa('hello '), done: false }));
        await t('save2', () => NativeMac.call('saveFile', { token: 'st1', name: 'e11-selftest.txt', b64: btoa('mac'), done: true }));
        await t('badURL', () => NativeMac.call('openURL', { url: 'file:///etc/passwd' }));
        await t('unknown', () => NativeMac.call('nope'));
        await t('chunkGone', () => NativeMac.call('readLocalChunk', { token: 'missing', offset: 0, length: 4 }));
        // fast office use: a local file isn't on the shared folder; an upload over the "office network" (the test
        // server's own office port) with its pinned certificate; one with the wrong certificate is refused
        await t('stFile', () => NativeMac.call('selftestFile', { size: 20000000 }));
        await t('share', () => NativeMac.call('shareInfo', { token: out.stFile.token, share: 'E11 Share' }));
        await t('ticket', () => api('POST', '/api/local/ticket', { kind: 'up', taskId: '_uploads', name: 'office-test.bin', size: 20000000 }));
        const follow = async (job) => { for (let i = 0; i < 120; i++) { const q = await NativeMac.call('uploadStatus', { job }); if (q.state !== 'sending') return q; await new Promise((r) => setTimeout(r, 250)); } return { state: 'timeout' }; };
        await t('upLocal', async () => follow((await NativeMac.call('uploadLocal', { token: out.stFile.token, url: out.ticket.url, ticket: out.ticket.token, cert: out.ticket.cert, size: 20000000 })).job));
        await t('stFile2', () => NativeMac.call('selftestFile', { size: 1000 }));
        await t('upBadPin', async () => follow((await NativeMac.call('uploadLocal', { token: out.stFile2.token, url: out.ticket.url, ticket: out.ticket.token, cert: '00'.repeat(32), size: 1000 })).job));
        await t('dlTicket', () => api('POST', '/api/local/ticket', { kind: 'file', path: out.upLocal.file.path }));
        await t('dlLocal', () => NativeMac.call('downloadLocal', { url: out.dlTicket.url, ticket: out.dlTicket.token, cert: out.dlTicket.cert, name: 'e11-office-dl.bin', open: false }));
        await t('dlTicket2', () => api('POST', '/api/local/ticket', { kind: 'file', path: out.upLocal.file.path }));
        await t('dlJob', async () => {
          const r = await NativeMac.call('downloadLocal', { url: out.dlTicket2.url, ticket: out.dlTicket2.token, cert: out.dlTicket2.cert, name: 'e11-office-dl2.bin', open: false, job: true });
          let q = null, seen = 0;
          for (let i = 0; i < 300; i++) { q = await NativeMac.call('downloadStatus', { job: r.job }); if (q.done > seen) seen = q.done; if (q.state !== 'receiving') break; await new Promise((x) => setTimeout(x, 100)); }
          return { ...q, seen, job: !!r.job };
        });
        for (let i = 0; i < 50 && !document.getElementById('mac-bar'); i++) await new Promise((r) => setTimeout(r, 100));   // (the page adds it a moment after it loads)
        out.macChrome = document.documentElement.classList.contains('mac-chrome');
        out.macBar = !!document.getElementById('mac-bar');
        out.updateBar = !!document.getElementById('mac-update');
        out.notifClick = typeof window.__e11NotifClick;
        out.openTask = typeof window.__e11OpenTask;
        return JSON.stringify(out);
      })()
      """
      if #available(macOS 11.0, *) {
        self.web.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { res in
          switch res {
          case .success(let v): self.selftest["calls"] = (try? JSONSerialization.jsonObject(with: Data(((v as? String) ?? "{}").utf8))) ?? [:]
          case .failure(let e): self.selftest["callsError"] = e.localizedDescription
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.finishSelfTest(error: nil) }
        }
      }
    }
  }
  var finished = false
  func finishSelfTest(error: String?) {
    if finished { return }
    finished = true
    if let e = error { selftest["error"] = e }
    selftest["shell"] = SHELL_VERSION
    selftest["lights"] = window.standardWindowButton(.closeButton).map { ["x": $0.frame.origin.x, "y": $0.frame.origin.y] } ?? [:]
    selftest["saved"] = (try? String(contentsOfFile: NSHomeDirectory() + "/Downloads/e11-selftest.txt")) ?? ""
    let picture = (SELFTEST as NSString).deletingPathExtension + ".png"
    web.takeSnapshot(with: nil) { img, _ in
      if let img = img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: picture))
      }
      _ = self.windowShouldClose(self.window)
      self.selftest["closedVisible"] = self.window.isVisible
      _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
      self.selftest["reopenedVisible"] = self.window.isVisible
      self.selftest["loginOn"] = self.setAtLogin(true) && ((try? String(contentsOfFile: LOGIN_AGENT)) ?? "").contains(Bundle.main.bundlePath)
      self.selftest["loginOff"] = self.setAtLogin(false) && !self.atLogin()
      try? Data(jsonString(self.selftest).utf8).write(to: URL(fileURLWithPath: SELFTEST))
      NSApp.terminate(nil)
    }
  }
}

// Only talks to a server showing the certificate whose SHA-256 fingerprint the E11 server named (the office port's
// own certificate isn't signed by anyone, so it's recognised by its fingerprint instead of its name)
// One download over the office network, with its progress (downloadLocalJob)
final class LocalDownload: NSObject, URLSessionDownloadDelegate {
  let pinner: Pinner, name: String, open: Bool
  private let lock = NSLock()
  private var state = "receiving", got: Int64 = 0, size: Int64 = 0, path = "", error = ""
  private var task: URLSessionDownloadTask?
  init(pin: String, name: String, open: Bool) { pinner = Pinner(pin); self.name = name; self.open = open }
  func start(_ url: URL) {
    let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    var req = URLRequest(url: url); req.timeoutInterval = 60
    task = session.downloadTask(with: req)
    task?.resume()
  }
  private func set(_ f: () -> Void) { lock.lock(); f(); lock.unlock() }
  func cancel() { set { if self.state == "receiving" { self.state = "cancelled" } }; task?.cancel() }
  func snapshot() -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    var r: [String: Any] = ["ok": state != "error", "state": state, "done": got, "size": size]
    if !path.isEmpty { r["path"] = path }
    if !error.isEmpty { r["error"] = error }
    return r
  }
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    pinner.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    set { self.got = totalBytesWritten; if totalBytesExpectedToWrite > 0 { self.size = totalBytesExpectedToWrite } }
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { return set { self.state = "error"; self.error = "Download failed" } }
    let dir = open ? (NSTemporaryDirectory() as NSString).appendingPathComponent("E11 Console") : NSHomeDirectory() + "/Downloads"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let dest = uniquePath(dir, name)
    do { try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: dest)) } catch { return set { self.state = "error"; self.error = "Couldn’t save to " + dir } }
    var u = URL(fileURLWithPath: dest)
    var rv = URLResourceValues()
    rv.quarantineProperties = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String, kLSQuarantineAgentNameKey as String: APP_NAME]
    try? u.setResourceValues(rv)
    let open = self.open
    DispatchQueue.main.async {
      if open { NSWorkspace.shared.open(u) } else if SELFTEST.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([u]) }
      self.set { self.state = "done"; self.path = dest; if self.size == 0 { self.size = self.got } }
    }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError err: Error?) {
    if let err = err { set { if self.state == "receiving" { self.state = "error"; self.error = err.localizedDescription } } }
    session.finishTasksAndInvalidate()
  }
}

final class Pinner: NSObject, URLSessionDelegate {
  let pin: String
  init(_ pin: String) { self.pin = pin.lowercased() }
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust,
          SecTrustGetCertificateCount(trust) > 0, let cert = SecTrustGetCertificateAtIndex(trust, 0) else { return completionHandler(.cancelAuthenticationChallenge, nil) }
    let der = SecCertificateCopyData(cert) as Data
    let fp = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    if fp == pin { completionHandler(.useCredential, URLCredential(trust: trust)) } else { completionHandler(.cancelAuthenticationChallenge, nil) }
  }
}
// One upload over the office network, in 16 MB pieces, one after another (the office network is fast; the server
// writes each piece at its place in the file)
final class LocalJob {
  let lock = NSLock()
  let size: Int64
  var sent: Int64 = 0, state = "sending", error = "", remotePath = "", file: [String: Any]? = nil, cancelled = false
  init(size: Int64) { self.size = size }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
  func snapshot() -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    var s: [String: Any] = ["ok": true, "state": state, "sent": sent, "size": size]
    if !error.isEmpty { s["error"] = error }
    if !remotePath.isEmpty { s["path"] = remotePath }
    if let f = file { s["file"] = f }
    return s
  }
  func set(_ f: () -> Void) { lock.lock(); f(); lock.unlock() }
  func run(path: String, base: String, ticket: String, pin: String) {
    let session = URLSession(configuration: .ephemeral, delegate: Pinner(pin), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    guard let fh = FileHandle(forReadingAtPath: path) else { return set { state = "error"; error = "Could not read the file" } }
    defer { fh.closeFile() }
    let piece = 16 << 20
    var off: Int64 = 0
    repeat {
      lock.lock(); let stop = cancelled; lock.unlock()
      if stop { return set { state = "cancelled" } }
      fh.seek(toFileOffset: UInt64(off))
      let data = fh.readData(ofLength: piece)
      guard var comps = URLComponents(string: base + "/local/upload") else { return set { state = "error"; error = "Bad address" } }
      comps.queryItems = [URLQueryItem(name: "t", value: ticket), URLQueryItem(name: "offset", value: String(off))]
      guard let url = comps.url else { return set { state = "error"; error = "Bad address" } }
      var req = URLRequest(url: url)
      req.httpMethod = "POST"; req.timeoutInterval = 120
      req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
      let sem = DispatchSemaphore(value: 0)
      var answer: [String: Any]? = nil, failure = ""
      session.uploadTask(with: req, from: data) { d, r, e in
        if let e = e { failure = e.localizedDescription }
        else if (r as? HTTPURLResponse)?.statusCode != 200 { failure = "The NAS answered \((r as? HTTPURLResponse)?.statusCode ?? 0)" }
        else if let d = d { answer = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
        sem.signal()
      }.resume()
      sem.wait()
      guard failure.isEmpty, let a = answer, let rp = a["path"] as? String else { return set { state = "error"; error = failure.isEmpty ? "Unexpected answer" : failure } }
      off += Int64(data.count)
      set { sent = off; remotePath = rp; if off >= size { file = ["path": rp, "name": a["name"] as? String ?? "", "size": (a["size"] as? NSNumber)?.int64Value ?? off] } }
      if data.isEmpty { break }
    } while off < size
    set { if state == "sending" { state = file != nil ? "done" : "error"; if file == nil { error = "The upload didn’t finish" } } }
  }
}

// older notifications: clicking one opens what it's about
final class OldNotifs: NSObject, NSUserNotificationCenterDelegate {
  static let shared = OldNotifs()
  func userNotificationCenter(_ c: NSUserNotificationCenter, shouldPresent n: NSUserNotification) -> Bool { true }
  func userNotificationCenter(_ c: NSUserNotificationCenter, didActivate n: NSUserNotification) {
    (NSApp.delegate as? App)?.clicked(n.userInfo?["click"] as? String ?? "")
  }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
