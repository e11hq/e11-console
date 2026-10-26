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

// Version of this Mac app's native part. Raise it when a change here needs everyone to reinstall: the web app
// then shows a required-update banner in older Mac apps. (The earlier script app was 1–6.)
let SHELL_VERSION = 7

let info = Bundle.main.infoDictionary ?? [:]
let env = ProcessInfo.processInfo.environment
let SERVER: String = {
  if let s = env["E11_SERVER"], !s.isEmpty { return s }   // (the build machine's self-test)
  return (info["E11ServerURL"] as? String) ?? "https://console.e11hq.com"
}()
let APP_NAME = (info["CFBundleName"] as? String) ?? "E11 Console"
let SELFTEST = env["E11_SELFTEST"] ?? ""
let defaults = UserDefaults.standard
let LOCK_KEY = "E11TouchIDLock"

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
    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:withReply:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
  }
  func applicationDidFinishLaunching(_ n: Notification) {
    // stay connected while minimised or in the background (no App Nap; the Mac can still sleep)
    activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Keeps E11 Console live and notifications arriving")
    if SELFTEST.isEmpty { UNUserNotificationCenter.current().delegate = self }
    buildMenu()
    buildWindow()
    if defaults.bool(forKey: LOCK_KEY) { lock() }
    if !SELFTEST.isEmpty { startSelfTest() }
  }
  func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool { showWindow(); return true }
  func applicationDidBecomeActive(_ n: Notification) {
    // Touch ID lock: again after 10 minutes away
    if defaults.bool(forKey: LOCK_KEY), lockView == nil, Date().timeIntervalSince(lastActive) > 600 { lock() }
  }
  func applicationDidResignActive(_ n: Notification) { lastActive = Date() }
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
    guard let r = url.range(of: "(?:task/|[?&]task=)([A-Za-z0-9_-]{1,80})", options: .regularExpression) else { if window != nil { showWindow() }; return }
    let m = String(url[r])
    let id = m.replacingOccurrences(of: "^(?:task/|[?&]task=)", with: "", options: .regularExpression)
    if web == nil { pendingTask = id; return }
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
    web.setValue(false, forKey: "drawsBackground")
    if #available(macOS 13.3, *) { web.isInspectable = true }
    window.contentView!.addSubview(web)
    if !SELFTEST.isEmpty, let host = URL(string: SERVER)?.host, let email = env["E11_SELFTEST_EMAIL"],
       let c = HTTPCookie(properties: [.domain: host, .path: "/", .name: "e11_dev_email", .value: email]) {
      web.configuration.websiteDataStore.httpCookieStore.setCookie(c) { self.loadHome() }
    } else { loadHome() }
    window.makeKeyAndOrderFront(nil)
    placeLights()
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
  func windowWillClose(_ n: Notification) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) } }
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
    let html = "<html><body style=\"background:#0c0d0f;color:#bbb;font:15px -apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0\"><div style=\"text-align:center\"><b style=\"color:#fff\">Can’t reach E11 Console</b><br><br>Check your internet connection. Trying again…</div></body></html>"
    web.loadHTMLString(html, baseURL: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.loadHome() }
  }
  // links the window can't show itself (mailto:, e11console:, …) go to the Mac
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if let u = action.request.url, let s = u.scheme?.lowercased(), !["http", "https", "about", "blob", "data"].contains(s) {
      if s == "e11console" || s == "e11console-test" { openLink(u.absoluteString) } else { NSWorkspace.shared.open(u) }
      return decisionHandler(.cancel)
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
    case "appInfo":
      done(["ok": true, "server": SERVER, "shell": SHELL_VERSION, "native": "swift",
            "version": info["CFBundleShortVersionString"] as? String ?? "3.0.0", "touchID": defaults.bool(forKey: LOCK_KEY)])
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
    } else if let h = FileHandle(forWritingAtPath: dest!) {
      h.seekToEndOfFile(); h.write(data); h.closeFile()
    }
    if (a["done"] as? Bool) == true {
      saving.removeValue(forKey: t)
      if open { NSWorkspace.shared.open(URL(fileURLWithPath: dest!)) }
      else if SELFTEST.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dest!)]) }
    }
    return ["ok": true, "path": dest!]
  }
  // Dock icon chosen on the server: shown now, and written onto the app so it shows when closed too
  func setIcon(_ a: [String: Any]) -> [String: Any] {
    let appPath = Bundle.main.bundlePath
    if (a["reset"] as? Bool) == true {
      NSWorkspace.shared.setIcon(nil, forFile: appPath, options: [])
      NSApp.applicationIconImage = NSImage(contentsOfFile: appPath + "/Contents/Resources/AppIcon.icns")
      return ["ok": true, "saved": false]
    }
    guard let d = Data(base64Encoded: a["b64"] as? String ?? ""), let img = NSImage(data: d) else { return ["ok": false, "error": "Bad icon image"] }
    NSApp.applicationIconImage = img
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
    if #available(macOS 11.0, *) { done([.banner, .list]) } else { done([.alert]) }
  }
  func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
    clicked(r.notification.request.content.userInfo["click"] as? String ?? ""); done()
  }
  func clicked(_ key: String) {
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
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.unlock() }
  }
  @objc func unlock() {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { lockView?.removeFromSuperview(); lockView = nil; return }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock E11 Console") { ok, _ in
      DispatchQueue.main.async { if ok { self.lockView?.removeFromSuperview(); self.lockView = nil; self.lastActive = Date() } }
    }
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
    _ = sub(APP_NAME, [
      item("About " + APP_NAME, #selector(NSApplication.orderFrontStandardAboutPanel(_:))), .separator(),
      lockItem, .separator(),
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
      try? Data(jsonString(self.selftest).utf8).write(to: URL(fileURLWithPath: SELFTEST))
      NSApp.terminate(nil)
    }
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
