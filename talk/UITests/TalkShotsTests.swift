import XCTest

/* E11 Talk's App Store screenshots (Haris 2026-11-14): Apple's UI testing walks Talk in the simulator, signed in to a local
   server holding the App Review copy's made-up chats (talk/shots.py), and takes a screenshot of each screen the approved
   boards need — the E11 Agency list, the Clients list, client pages and their chats, search, Settings, Chat Backup, Linked
   Devices. A test only: the sign-in it uses exists in simulator test builds alone (Net.swift, #if DEBUG). */
final class TalkShotsTests: XCTestCase {
  private var app: XCUIApplication!
  private var out: URL!
  private var n = 0
  private func shot(_ name: String) {
    n += 1
    try? XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent(String(format: "T-%03d-%@.png", n, name)))
  }
  private func back() {
    let b = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
    if b.exists { b.tap() } else { app.swipeRight() }
    Thread.sleep(forTimeInterval: 1.2)
  }
  private func tab(_ i: Int) {
    let b = app.tabBars.firstMatch.buttons.element(boundBy: i)
    if b.exists { b.tap(); Thread.sleep(forTimeInterval: 2) }
  }
  private var rows: XCUIElementQuery { app.tables.firstMatch.cells }

  func testTalkShots() {
    continueAfterFailure = true
    let env = ProcessInfo.processInfo.environment
    out = URL(fileURLWithPath: env["E11_SHOTS_OUT"] ?? NSTemporaryDirectory(), isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    app = XCUIApplication()
    app.launchEnvironment = ["E11_TALK_SERVER": env["E11_SERVER"] ?? "", "E11_TALK_DEV_EMAIL": env["E11_EMAIL"] ?? ""]
    // Chat Backup as on a phone that's been backing up (the simulator has no iCloud): last night, 3:00
    let three = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3 * 3600).timeIntervalSince1970
    app.launchArguments = ["-talk_backup_at", String(three), "-talk_backup_size", "195035136"]
    app.launch()
    _ = app.tabBars.firstMatch.waitForExistence(timeout: 90)
    Thread.sleep(forTimeInterval: 8)
    // iPhone's "Would Like to Send You Notifications" — answered, so it isn't in the pictures
    let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for l in ["Allow", "Don’t Allow", "Don't Allow"] { let b = sb.buttons[l]; if b.waitForExistence(timeout: 2) { b.tap(); break } }
    Thread.sleep(forTimeInterval: 2)
    shot("agency")
    // each tab's clients, each client's groups, each group's chat — scrolled to its end and once up
    for t in 0..<2 {
      tab(t); shot("tab\(t)")
      let nc = min(rows.count, 4)
      for i in 0..<nc {
        let c = rows.element(boundBy: i); guard c.exists else { continue }
        c.tap(); Thread.sleep(forTimeInterval: 2.5); shot("t\(t)-client\(i)")
        let ng = min(rows.count, 3)
        for g in 0..<ng {
          let r = rows.element(boundBy: g); guard r.exists else { continue }
          r.tap(); Thread.sleep(forTimeInterval: 3); shot("t\(t)-c\(i)-chat\(g)")
          app.swipeDown(); Thread.sleep(forTimeInterval: 1.2); shot("t\(t)-c\(i)-chat\(g)-up")
          back()
        }
        back()
      }
    }
    // search on the E11 Agency list
    tab(0)
    rows.element(boundBy: 0).swipeDown(); Thread.sleep(forTimeInterval: 1)
    let sf = app.searchFields.firstMatch
    if sf.waitForExistence(timeout: 3) {
      sf.tap(); sf.typeText(env["E11_SEARCH"] ?? "captions"); Thread.sleep(forTimeInterval: 2.5); shot("search")
      for l in ["Cancel", "Close"] { let b = app.buttons[l]; if b.exists { b.tap(); break } }; Thread.sleep(forTimeInterval: 1)
    }
    // the voice note in the Social group, then who reacted to it
    tab(0)
    let k = rows.containing(NSPredicate(format: "label CONTAINS %@", "Kestrel")).firstMatch
    if k.waitForExistence(timeout: 3) {
      k.tap(); Thread.sleep(forTimeInterval: 2.5)
      let s = rows.containing(NSPredicate(format: "label CONTAINS %@", "Social")).firstMatch
      if s.waitForExistence(timeout: 3) {
        s.tap(); Thread.sleep(forTimeInterval: 3.5); shot("voice")
        let pill = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "🔥")).firstMatch
        let pill2 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "🔥")).firstMatch
        if pill.waitForExistence(timeout: 2) { pill.tap() } else if pill2.exists { pill2.tap() }
        Thread.sleep(forTimeInterval: 2); shot("reactions")
        app.swipeDown(velocity: .fast); Thread.sleep(forTimeInterval: 1.2)
        back()
      }
      back()
    }
    // Settings, Chat Backup, Linked Devices
    tab(2); shot("settings")
    for name in ["Chat Backup", "Linked Devices", "Mac"] {
      let r = app.cells.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
      if r.waitForExistence(timeout: 2) { r.tap(); Thread.sleep(forTimeInterval: 2.5); shot("settings-" + name.replacingOccurrences(of: " ", with: "")); back() }
    }
  }
}
