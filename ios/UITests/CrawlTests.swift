import XCTest

/* The crawl (Haris 2026-11-05: "I said everything — every single thing"). Apple's UI testing drives the app as a finger
   would, nothing scripted: signed in as one person (E11_EMAIL, the website off — E11_SELFTEST=crawl), it opens each tab
   and on every screen it reaches taps every control it can see — buttons, rows, switches, search fields, the words on
   cards — one at a time. The app (crawl mode, WalkTest.swift crawlAid) shows UI testing only the screen on top and says
   where it is in a hidden label "e11state" (screen, task pages, sheet…). After each tap: what happened (opened something
   new, went back, an alert, the keyboard, the screen changed, or nothing); into what opened, one level deeper (sheets
   too); then back to where it was (Cancel / Close / Back / a swipe down — or the tab again and the way it came). Things
   that wipe are never tapped (Delete, Remove, Sign out, Start fresh, Empty…). A crash or a freeze is noted and the app
   started again. Written to E11_CRAWL_OUT: crawl-<tag>.json, and a picture of each control that did nothing or went
   wrong — ios/crawl.py reads it. */
final class CrawlTests: XCTestCase {
  private var app: XCUIApplication!
  private let env = ProcessInfo.processInfo.environment
  private var log: [[String: Any]] = []
  private var done = Set<String>()
  private var deadline = Date.distantFuture
  private var shots = 0
  private var outDir: URL { URL(fileURLWithPath: env["E11_CRAWL_OUT"] ?? NSTemporaryDirectory(), isDirectory: true) }
  private var tag: String { env["E11_TAG"] ?? "role" }
  private let maxDepth = 2
  private let perScreen = 40, wordsPerScreen = 10
  private let skip = ["delete", "remove", "sign out", "log out", "start fresh", "empty", "leave", "unlink", "deactivate",
                      "without the website", "grabber", "e11state", "dismiss"]

  // ---------- starting ----------
  private func launch() {
    app = XCUIApplication()
    app.launchEnvironment = ["E11_SERVER": env["E11_SERVER"] ?? "", "E11_SELFTEST": "crawl", "E11_SELFTEST_EMAIL": env["E11_EMAIL"] ?? ""]
    app.launch()
    _ = app.tabBars.firstMatch.waitForExistence(timeout: 60)
    Thread.sleep(forTimeInterval: 3)
  }

  func testCrawl() {
    continueAfterFailure = true
    deadline = Date().addingTimeInterval(Double(env["E11_CRAWL_SECS"] ?? "1200") ?? 1200)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    launch()
    let tabs = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map { $0.label }
    note(["kind": "start", "tabs": tabs, "state": state()])
    // (an even share of the time for each tab, the rest carried on)
    for (i, t) in tabs.enumerated() {
      if Date() > deadline { note(["kind": "timeUp", "at": t]); break }
      let left = deadline.timeIntervalSinceNow
      tabDeadline = Date().addingTimeInterval(left / Double(tabs.count - i))
      goTab(t)
      note(["kind": "tab", "tab": t, "state": state(), "screen": topWords(snap())])
      crawl(path: [t], states: [], depth: 0)
      write()
    }
    write()
  }
  private var tabDeadline = Date.distantFuture

  // ---------- what's on the screen ----------
  private struct Item { let type: XCUIElement.ElementType; let label: String; let frame: CGRect; let inTabBar: Bool; let inKeyboard: Bool }
  private var lastState = ""
  private func snap() -> [Item] {
    guard let root = try? app.snapshot() else { return [] }
    var out: [Item] = []
    func walk(_ s: XCUIElementSnapshot, tab: Bool, kb: Bool) {
      let t = tab || s.elementType == .tabBar, k = kb || s.elementType == .keyboard
      if s.identifier == "e11state" { lastState = s.label; return }
      let lbl = s.label.isEmpty ? ((s.value as? String) ?? s.placeholderValue ?? s.identifier) : s.label
      if [.button, .cell, .switch, .link, .staticText, .textField, .searchField, .secureTextField, .image, .slider, .segmentedControl, .menuItem].contains(s.elementType) {
        out.append(Item(type: s.elementType, label: lbl, frame: s.frame, inTabBar: t, inKeyboard: k))
      }
      for c in s.children { walk(c, tab: t, kb: k) }
    }
    walk(root, tab: false, kb: false)
    return out
  }
  private func state() -> String { _ = snap(); return lastState }
  private var screenSize: CGSize { app.windows.firstMatch.frame.size }
  private func visible(_ i: Item) -> Bool {
    let b = CGRect(origin: .zero, size: screenSize)
    return i.frame.width >= 6 && i.frame.height >= 6 && b.contains(CGPoint(x: i.frame.midX, y: i.frame.midY)) && i.frame.minY > 40
  }
  private func sig(_ s: [Item]) -> Set<String> {
    Set(s.filter { visible($0) && !$0.inKeyboard && !$0.inTabBar && ($0.type == .button || $0.type == .staticText || $0.type == .switch || $0.type == .cell) }
      .map { "\($0.type.rawValue):\($0.label.prefix(30))" }.prefix(80))
  }
  private func same(_ a: Set<String>, _ b: Set<String>) -> Bool {
    if a.isEmpty && b.isEmpty { return true }
    return Double(a.intersection(b).count) / Double(max(1, a.union(b).count)) >= 0.8
  }
  private func topWords(_ s: [Item]) -> [String] { Array(s.filter { visible($0) && $0.type == .staticText && !$0.label.isEmpty && !$0.inTabBar && !$0.inKeyboard }.prefix(5).map { String($0.label.prefix(40)) }) }
  private func keyboardUp() -> Bool { app.keyboards.count > 0 }
  // (where the app is, without the parts that change by themselves)
  private func place(_ st: String) -> String { st.components(separatedBy: "|").filter { !$0.hasPrefix("search=") }.joined(separator: "|") }

  // ---------- the crawl ----------
  private func crawl(path: [String], states: [String], depth: Int) {
    let base = snap()
    let baseState = place(lastState)
    let order: [XCUIElement.ElementType] = [.button, .switch, .segmentedControl, .cell, .link, .searchField, .textField, .menuItem, .image, .staticText]
    var seen = Set<String>(); var words = 0
    let cands = base.filter { visible($0) && !$0.inTabBar && !$0.inKeyboard && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted { (order.firstIndex(of: $0.type) ?? 99, $0.frame.minY) < (order.firstIndex(of: $1.type) ?? 99, $1.frame.minY) }
      .filter { i in
        let low = i.label.lowercased()
        if skip.contains(where: { low.contains($0) }) { note(["kind": "skipped", "path": path, "label": i.label]); return false }
        let k = "\(i.type.rawValue)|\(i.label)"
        if seen.contains(k) { return false }
        if i.type == .staticText { if words >= wordsPerScreen { return false }; words += 1 }
        seen.insert(k); return true
      }
      .prefix(perScreen)
    for c in cands {
      if Date() > deadline || Date() > tabDeadline { return }
      let key = "\(baseState)#\(c.type.rawValue)#\(c.label)"
      if done.contains(key) { continue }
      done.insert(key)
      let now = snap()
      guard let target = now.first(where: { $0.type == c.type && $0.label == c.label && visible($0) && !$0.inTabBar && !$0.inKeyboard }) else { continue }
      let before = sig(now)
      tap(target.frame)
      Thread.sleep(forTimeInterval: 1.0)
      if app.state != .runningForeground {
        note(["kind": "crash", "path": path, "label": c.label, "type": typeName(c.type), "state": baseState]); shot("CRASH-\(c.label)")
        launch(); replay(path); continue
      }
      let after = snap(); let afterState = place(lastState)
      var outcome = "nothing"
      if app.alerts.count > 0 { outcome = "alert: " + app.alerts.firstMatch.label + " [" + app.alerts.firstMatch.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: ", ") + "]" }
      else if afterState != baseState && (states.contains(afterState)) { outcome = "back: " + afterState }
      else if afterState != baseState { outcome = "opened: " + afterState + " — " + topWords(after).joined(separator: " | ") }
      else if keyboardUp() { outcome = "keyboard" }
      else if !same(before, sig(after)) { outcome = "changed: " + topWords(after).joined(separator: " | ") }
      var row: [String: Any] = ["kind": "tap", "path": path, "label": c.label, "type": typeName(c.type), "outcome": outcome, "state": baseState]
      if outcome == "nothing" && [.button, .switch, .cell, .link, .menuItem].contains(c.type) { row["shot"] = shot("nothing-\(c.label)") }
      note(row)
      if outcome.hasPrefix("opened") && depth < maxDepth { crawl(path: path + [c.label], states: states + [baseState], depth: depth + 1) }
      back(to: baseState, sig: before, path: path)
    }
  }
  private func typeName(_ t: XCUIElement.ElementType) -> String {
    switch t { case .button: return "button"; case .staticText: return "text"; case .cell: return "row"; case .switch: return "switch"; case .textField, .searchField: return "field"; case .image: return "image"; default: return "\(t.rawValue)" }
  }
  private func tap(_ f: CGRect) { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap() }

  // ---------- back to where it was ----------
  private func back(to baseState: String, sig base: Set<String>, path: [String]) {
    for _ in 0..<7 {
      let s = snap()
      if place(lastState) == baseState && !keyboardUp() && app.alerts.count == 0 { return }
      if app.alerts.count > 0 {
        let bs = app.alerts.firstMatch.buttons.allElementsBoundByIndex
        let soft = bs.first { ["cancel", "not now", "ok", "close", "keep", "no", "keep editing"].contains($0.label.lowercased()) } ?? bs.last
        soft?.tap(); Thread.sleep(forTimeInterval: 0.6); continue
      }
      if keyboardUp() {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screenSize.width / 2, dy: 70)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        if keyboardUp() { app.keyboards.buttons.allElementsBoundByIndex.last { ["return", "done", "search", "go"].contains($0.label.lowercased()) }?.tap(); Thread.sleep(forTimeInterval: 0.5) }
        continue
      }
      var hit = false
      for name in ["Cancel", "Close", "Close search", "Done", "Back", "Not now", "OK"] {
        if let i = s.first(where: { $0.type == .button && $0.label == name && visible($0) && !$0.inTabBar }) { tap(i.frame); hit = true; break }
      }
      if hit { Thread.sleep(forTimeInterval: 0.9); continue }
      // (a sheet with no Cancel: dragged down)
      let z = screenSize
      app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: z.width / 2, dy: z.height * 0.3))
        .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: z.width / 2, dy: z.height * 0.98)))
      Thread.sleep(forTimeInterval: 0.9)
    }
    if place(state()) != baseState { note(["kind": "lost", "path": path, "want": baseState, "at": lastState]); replay(path) }
  }
  private func goTab(_ t: String) {
    let b = app.tabBars.firstMatch.buttons[t]
    if b.exists { b.tap(); Thread.sleep(forTimeInterval: 1.0); b.tap(); Thread.sleep(forTimeInterval: 1.4) }
  }
  private func replay(_ path: [String]) {
    if app.state != .runningForeground { launch() }
    for _ in 0..<4 {
      if app.alerts.count == 0 && !keyboardUp() && lastState.contains("sheet=|") { break }   // (nothing over the screen)
      if app.alerts.count > 0 { app.alerts.firstMatch.buttons.allElementsBoundByIndex.last?.tap() }
      else if keyboardUp() { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screenSize.width / 2, dy: 70)).tap() }
      else {
        let z = screenSize
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: z.width / 2, dy: z.height * 0.3))
          .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: z.width / 2, dy: z.height * 0.98)))
      }
      Thread.sleep(forTimeInterval: 0.8); _ = state()
    }
    // (task pages left open: ‹ until none)
    for _ in 0..<4 where lastState.contains("pages=") && !lastState.contains("pages=0") {
      if let b = snap().first(where: { $0.type == .button && $0.label == "Back" && visible($0) }) { tap(b.frame); Thread.sleep(forTimeInterval: 0.8) } else { break }
    }
    guard let t = path.first else { return }
    goTab(t)
    for l in path.dropFirst() {
      if let i = snap().first(where: { $0.label == l && visible($0) && !$0.inTabBar }) { tap(i.frame); Thread.sleep(forTimeInterval: 1.2) }
    }
  }

  // ---------- notes ----------
  private func note(_ d: [String: Any]) { var x = d; x["t"] = Int(Date().timeIntervalSince1970); log.append(x) }
  @discardableResult private func shot(_ name: String) -> String {
    shots += 1
    guard shots <= 200 else { return "" }
    let clean = String(name.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression).prefix(40))
    let f: String = tag + "-" + String(format: "%03d", shots) + "-" + clean + ".png"
    try? app.screenshot().pngRepresentation.write(to: outDir.appendingPathComponent(f))
    return f
  }
  private func write() {
    if let d = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted]) { try? d.write(to: outDir.appendingPathComponent("crawl-\(tag).json")) }
  }
}
