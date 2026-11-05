import XCTest

/* The crawl (Haris 2026-11-05: "I said everything — every single thing"). Apple's UI testing drives the app as a finger
   would, nothing scripted: signed in as one person (E11_EMAIL, the website off — E11_SELFTEST=crawl), it opens each tab
   and on every screen it reaches taps every control it can see — buttons, rows, switches, search fields, the words on
   cards — one at a time. After each tap it notes what happened (a new screen, a sheet, an alert, the keyboard, the screen
   changing, or nothing), goes one level deeper into what opened (sheets too), then back to where it was (Cancel / Close /
   Back / a swipe down — or the tab again and the way it came). Things that wipe are never tapped (Delete, Remove, Sign
   out, Start fresh, Empty, Leave…). A crash or a freeze is noted and the app started again. Everything is written to
   E11_CRAWL_OUT (crawl-<tag>.json, and a picture of each tap that did nothing or went wrong) — ios/crawl.py reads it. */
final class CrawlTests: XCTestCase {
  private var app: XCUIApplication!
  private let env = ProcessInfo.processInfo.environment
  private var log: [[String: Any]] = []
  private var done = Set<String>()
  private var deadline = Date.distantFuture
  private var shots = 0
  private var outDir: URL { URL(fileURLWithPath: env["E11_CRAWL_OUT"] ?? NSTemporaryDirectory(), isDirectory: true) }
  private var tag: String { env["E11_TAG"] ?? "role" }
  private let maxDepth = Int(ProcessInfo.processInfo.environment["E11_DEPTH"] ?? "2") ?? 2
  private let perScreen = 45
  private let skip = ["delete", "remove", "sign out", "log out", "start fresh", "empty", "leave", "unlink", "deactivate",
                      "remove from team", "delete forever", "restore all", "use without", "without the website"]

  // ---------- starting ----------
  private func launch() {
    app = XCUIApplication()
    app.launchEnvironment = ["E11_SERVER": env["E11_SERVER"] ?? "", "E11_SELFTEST": "crawl", "E11_SELFTEST_EMAIL": env["E11_EMAIL"] ?? ""]
    app.launch()
    _ = app.tabBars.firstMatch.waitForExistence(timeout: 60)
    sleep(3)
  }

  func testCrawl() {
    continueAfterFailure = true
    deadline = Date().addingTimeInterval(Double(env["E11_CRAWL_SECS"] ?? "900") ?? 900)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    launch()
    let tabs = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map { $0.label }
    note(["kind": "start", "tabs": tabs, "launched": app.state == .runningForeground])
    for t in tabs {
      if Date() > deadline { note(["kind": "timeUp", "at": t]); break }
      goTab(t)
      note(["kind": "tab", "tab": t, "screen": topWords(snap())])
      crawl(path: [t], depth: 0)
      write()
    }
    write()
  }

  // ---------- what's on the screen ----------
  private struct Item { let type: XCUIElement.ElementType; let label: String; let frame: CGRect; let inTabBar: Bool; let inKeyboard: Bool }
  private func snap() -> [Item] {
    guard let root = try? app.snapshot() else { return [] }
    var out: [Item] = []
    func walk(_ s: XCUIElementSnapshot, tab: Bool, kb: Bool) {
      let t = tab || s.elementType == .tabBar, k = kb || s.elementType == .keyboard
      let lbl = s.label.isEmpty ? (s.value as? String ?? s.placeholderValue ?? s.identifier) : s.label
      if [.button, .cell, .switch, .link, .staticText, .textField, .searchField, .secureTextField, .image, .slider, .segmentedControl, .menuItem].contains(s.elementType) {
        out.append(Item(type: s.elementType, label: lbl, frame: s.frame, inTabBar: t, inKeyboard: k))
      }
      for c in s.children { walk(c, tab: t, kb: k) }
    }
    walk(root, tab: false, kb: false)
    return out
  }
  private var screenSize: CGSize { app.windows.firstMatch.frame.size }
  private func visible(_ i: Item) -> Bool {
    let b = CGRect(origin: .zero, size: screenSize)
    return i.frame.width >= 6 && i.frame.height >= 6 && b.contains(CGPoint(x: i.frame.midX, y: i.frame.midY)) && i.frame.minY > 44
  }
  // a screen's fingerprint: its buttons and the first words (changing times / counts aside)
  private func sig(_ s: [Item]) -> Set<String> {
    Set(s.filter { visible($0) && !$0.inKeyboard && ($0.type == .button || $0.type == .staticText || $0.type == .switch) }
      .map { "\($0.type.rawValue):\($0.label.prefix(30))" }.filter { !$0.contains(":") || $0.count > 3 }.prefix(80))
  }
  private func same(_ a: Set<String>, _ b: Set<String>) -> Bool {
    if a.isEmpty && b.isEmpty { return true }
    let j = Double(a.intersection(b).count) / Double(max(1, a.union(b).count))
    return j >= 0.82
  }
  private func topWords(_ s: [Item]) -> [String] { Array(s.filter { visible($0) && $0.type == .staticText && !$0.label.isEmpty && !$0.inTabBar }.prefix(6).map { String($0.label.prefix(40)) }) }
  private func keyboardUp() -> Bool { app.keyboards.count > 0 }

  // ---------- the crawl ----------
  private func crawl(path: [String], depth: Int) {
    let base = snap()
    let baseSig = sig(base)
    let screenKey = topWords(base).prefix(3).joined(separator: "|")
    // what to tap here: buttons, switches, rows and fields first, then the words on cards (deduped by label)
    let order: [XCUIElement.ElementType] = [.button, .switch, .segmentedControl, .cell, .link, .searchField, .textField, .menuItem, .image, .staticText]
    var seenLabels = Set<String>()
    let cands = base.filter { visible($0) && !$0.inTabBar && !$0.inKeyboard && !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
      .sorted { (order.firstIndex(of: $0.type) ?? 99, $0.frame.minY) < (order.firstIndex(of: $1.type) ?? 99, $1.frame.minY) }
      .filter { i in
        let low = i.label.lowercased()
        if skip.contains(where: { low.contains($0) }) { note(["kind": "skipped", "path": path, "label": i.label]); return false }
        let k = "\(i.type.rawValue)|\(i.label)"
        if seenLabels.contains(k) { return false }
        seenLabels.insert(k); return true
      }
      .prefix(perScreen)
    for c in cands {
      if Date() > deadline { return }
      let key = "\(screenKey)#\(c.type.rawValue)#\(c.label)"
      if done.contains(key) { continue }
      done.insert(key)
      // (the list may have moved since: the same control found again by its label)
      let now = snap()
      guard let target = now.first(where: { $0.type == c.type && $0.label == c.label && visible($0) && !$0.inTabBar }) else { continue }
      let before = sig(now)
      tap(target.frame)
      Thread.sleep(forTimeInterval: 1.1)
      if app.state != .runningForeground {
        note(["kind": "crash", "path": path, "label": c.label, "type": typeName(c.type)]); shot("CRASH-\(c.label)")
        launch(); replay(path); continue
      }
      let after = snap()
      var outcome = "nothing"
      if app.alerts.count > 0 { outcome = "alert: " + (app.alerts.firstMatch.label) + " [" + app.alerts.firstMatch.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: ", ") + "]" }
      else if keyboardUp() && !(before.contains { $0.hasPrefix("keyboard") }) { outcome = "keyboard" }
      else if !same(before, sig(after)) { outcome = "changed: " + topWords(after).joined(separator: " | ") }
      var row: [String: Any] = ["kind": "tap", "path": path, "label": c.label, "type": typeName(c.type), "outcome": outcome]
      // (a control that did nothing: a picture — words on a card doing nothing is usually fine, a button doing nothing isn't)
      if outcome == "nothing" && [.button, .switch, .cell, .link, .menuItem].contains(c.type) { row["shot"] = shot("nothing-\(c.label)") }
      note(row)
      // deeper: into what opened (a sheet, another page) — not alerts or the keyboard
      if outcome.hasPrefix("changed") && depth < maxDepth { crawl(path: path + [c.label], depth: depth + 1) }
      back(to: before, path: path)
    }
  }
  private func typeName(_ t: XCUIElement.ElementType) -> String {
    switch t { case .button: return "button"; case .staticText: return "text"; case .cell: return "row"; case .switch: return "switch"; case .textField, .searchField: return "field"; case .image: return "image"; default: return "\(t.rawValue)" }
  }
  private func tap(_ f: CGRect) {
    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
  }

  // ---------- back to where it was ----------
  private func back(to base: Set<String>, path: [String]) {
    for _ in 0..<6 {
      if same(base, sig(snap())) && !keyboardUp() && app.alerts.count == 0 { return }
      if app.alerts.count > 0 {
        let bs = app.alerts.firstMatch.buttons.allElementsBoundByIndex
        let soft = bs.first { ["cancel", "not now", "ok", "close", "keep", "no"].contains($0.label.lowercased()) } ?? bs.last
        soft?.tap(); Thread.sleep(forTimeInterval: 0.6); continue
      }
      if keyboardUp() {
        // (a tap away from typing only puts the keyboard away — KeyboardShield)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screenSize.width / 2, dy: 60)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        if keyboardUp() { app.keyboards.buttons.allElementsBoundByIndex.last { ["return", "done", "search", "go"].contains($0.label.lowercased()) }?.tap(); Thread.sleep(forTimeInterval: 0.5) }
        continue
      }
      var hit = false
      for name in ["Cancel", "Close", "Close search", "Done", "Back", "Not now", "OK", "✕"] {
        let b = app.buttons[name]
        if b.exists && b.isHittable { b.tap(); hit = true; break }
      }
      if hit { Thread.sleep(forTimeInterval: 0.8); continue }
      // (a sheet: dragged down)
      let s = screenSize
      app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: s.width / 2, dy: s.height * 0.32))
        .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: s.width / 2, dy: s.height * 0.98)))
      Thread.sleep(forTimeInterval: 0.9)
    }
    if !same(base, sig(snap())) { note(["kind": "lost", "path": path, "screen": topWords(snap())]); replay(path) }
  }
  private func goTab(_ t: String) {
    let b = app.tabBars.firstMatch.buttons[t]
    if b.exists { b.tap(); Thread.sleep(forTimeInterval: 1.2); b.tap(); Thread.sleep(forTimeInterval: 1.5) }   // (twice: the tab's first screen)
  }
  // the way back to a screen: its tab, then the same labels tapped again
  private func replay(_ path: [String]) {
    if app.state != .runningForeground { launch() }
    for _ in 0..<3 where app.alerts.count > 0 || keyboardUp() { back(to: [], path: []) }
    guard let t = path.first else { return }
    // (anything still open over the tabs: dragged away first)
    for _ in 0..<2 { for name in ["Cancel", "Close", "Done", "Back"] { let b = app.buttons[name]; if b.exists && b.isHittable { b.tap(); Thread.sleep(forTimeInterval: 0.6) } } }
    goTab(t)
    for l in path.dropFirst() {
      if let i = snap().first(where: { $0.label == l && visible($0) && !$0.inTabBar }) { tap(i.frame); Thread.sleep(forTimeInterval: 1.2) }
    }
  }

  // ---------- notes ----------
  private func note(_ d: [String: Any]) { var x = d; x["t"] = Int(Date().timeIntervalSince1970); log.append(x) }
  @discardableResult private func shot(_ name: String) -> String {
    shots += 1
    guard shots <= 160 else { return "" }
    let clean = String(name.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression).prefix(40))
    let f: String = tag + "-" + String(format: "%03d", shots) + "-" + clean + ".png"
    try? app.screenshot().pngRepresentation.write(to: outDir.appendingPathComponent(f))
    return f
  }
  private func write() {
    if let d = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted]) { try? d.write(to: outDir.appendingPathComponent("crawl-\(tag).json")) }
  }
}
