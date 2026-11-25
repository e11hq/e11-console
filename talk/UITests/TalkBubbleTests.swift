import XCTest

/* The chat bubble's time beside its words, looked at in the simulator (Haris 2026-11-25 20:57): the reviewer's own
   "Blue or red? Check again" (yesterday) and "Red or blue? Check again" (today) at every minute 8:30–8:59 PM, in the group
   "Bubble check" (talk/shots-demo.mjs, E11_BUBBLE=1), on a 393-point iPhone — a picture of each screenful, from the end
   up. Then the same words typed in the chat and sent. Measuring only. */
final class TalkBubbleTests: XCTestCase {
  func testBubbles() {
    continueAfterFailure = true
    let env = ProcessInfo.processInfo.environment
    let out = URL(fileURLWithPath: env["E11_SHOTS_OUT"] ?? NSTemporaryDirectory(), isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var n = 0
    func shot(_ name: String) { n += 1; try? XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent(String(format: "B-%03d-%@.png", n, name))) }
    let app = XCUIApplication()
    app.launchEnvironment = ["E11_TALK_SERVER": env["E11_SERVER"] ?? "", "E11_TALK_DEV_EMAIL": env["E11_EMAIL"] ?? ""]
    app.launch()
    _ = app.tabBars.firstMatch.waitForExistence(timeout: 90)
    Thread.sleep(forTimeInterval: 6)
    let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for l in ["Allow", "Don’t Allow", "Don't Allow"] { let b = sb.buttons[l]; if b.waitForExistence(timeout: 2) { b.tap(); break } }
    // the group: on the E11 Agency list or under its client
    func find() -> Bool {
      let c = app.tables.firstMatch.cells.containing(NSPredicate(format: "label CONTAINS %@", "Bubble check")).firstMatch
      if c.waitForExistence(timeout: 3) { c.tap(); return true }
      return false
    }
    var ok = false
    for t in 0..<2 where !ok {
      let tb = app.tabBars.firstMatch.buttons.element(boundBy: t); if tb.exists { tb.tap(); Thread.sleep(forTimeInterval: 2) }
      if find() { ok = true; break }
      let rows = app.tables.firstMatch.cells
      for i in 0..<min(rows.count, 6) where !ok {
        rows.element(boundBy: i).tap(); Thread.sleep(forTimeInterval: 2)
        if find() { ok = true } else { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap(); Thread.sleep(forTimeInterval: 1.2) }
      }
    }
    Thread.sleep(forTimeInterval: 3); shot("end")
    for i in 0..<12 { app.swipeDown(velocity: .slow); Thread.sleep(forTimeInterval: 1.2); shot("up\(i)") }
    // the same words typed and sent
    for i in 0..<14 { app.swipeUp(velocity: .fast); _ = i }
    Thread.sleep(forTimeInterval: 1)
    let box = app.textViews.firstMatch
    if box.waitForExistence(timeout: 3) {
      box.tap(); box.typeText("Blue or red? Check again"); Thread.sleep(forTimeInterval: 0.5)
      let send = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'send'")).firstMatch
      if send.exists { send.tap() } else { box.typeText("\n") }
      Thread.sleep(forTimeInterval: 4); shot("typed")
    }
  }
}
