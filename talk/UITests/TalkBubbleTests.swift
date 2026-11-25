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
      let t = app.staticTexts["Bubble check"].firstMatch
      if t.waitForExistence(timeout: 3) {
        Thread.sleep(forTimeInterval: 1)
        t.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); Thread.sleep(forTimeInterval: 3)
        if app.textViews.firstMatch.waitForExistence(timeout: 5) { return true }
        t.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); Thread.sleep(forTimeInterval: 3)
        return app.textViews.firstMatch.waitForExistence(timeout: 5)
      }
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
    // (the reply's own route: a message of yours made by the server, not by this phone — as a reply from a notification is —
    //  arriving while the chat is open; then the app sent to the background, two more the same way, and back)
    func serverSend(_ text: String) {
      guard let base = URL(string: env["E11_SERVER"] ?? ""), let email = env["E11_EMAIL"] else { return }
      func call(_ path: String, _ body: [String: Any]?) -> [String: Any]? {
        var r = URLRequest(url: base.appendingPathComponent(path)); r.setValue(email, forHTTPHeaderField: "X-Dev-Email")
        if let b = body { r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: b) }
        let sem = DispatchSemaphore(value: 0); var out: [String: Any]?
        URLSession.shared.dataTask(with: r) { d, _, _ in out = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 20); return out
      }
      let st = call("api/talk/state", nil)
      let gid = (st?["groups"] as? [[String: Any]])?.first { ($0["name"] as? String) == "Bubble check" }?["id"] as? String
      if let g = gid { _ = call("api/talk/act", ["act": "send", "group": g, "text": text, "cid": UUID().uuidString]) }
    }
    serverSend("Blue or red? Check again"); Thread.sleep(forTimeInterval: 4); shot("server-open")
    serverSend("ok"); Thread.sleep(forTimeInterval: 4); shot("server-ok-open")
    XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 2)
    serverSend("Blue or red? Check again"); serverSend("ok"); Thread.sleep(forTimeInterval: 3)
    app.activate(); Thread.sleep(forTimeInterval: 5); shot("server-background")
    for i in 0..<12 { app.swipeDown(velocity: .slow); Thread.sleep(forTimeInterval: 1.2); shot("up\(i)") }
    // (the real thing — Haris 2026-11-25 21:23: a notification, held, replied to "Blue or red? Check again" — the chat left
    //  open behind, Talk in the background; the Mac pushes the notification (talk/shots.py) while this waits for it)
    for i in 0..<14 { app.swipeUp(velocity: .fast); _ = i }
    XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1)
    try? "1".write(to: URL(fileURLWithPath: (env["E11_SHOTS_OUT"] ?? NSTemporaryDirectory()) + "/push-now"), atomically: true, encoding: .utf8)
    let banner = sb.otherElements["Notification"].firstMatch
    let bn = banner.waitForExistence(timeout: 25) ? banner : sb.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bubble check")).firstMatch
    shot("notif")
    if bn.waitForExistence(timeout: 5) {
      bn.press(forDuration: 1.2); Thread.sleep(forTimeInterval: 1.5); shot("notif-held")
      let r = sb.buttons["Reply"].firstMatch
      if r.waitForExistence(timeout: 3) { r.tap(); Thread.sleep(forTimeInterval: 1) }
      let field = sb.textViews.firstMatch.exists ? sb.textViews.firstMatch : sb.textFields.firstMatch
      if field.waitForExistence(timeout: 4) {
        field.typeText("Blue or red? Check again"); Thread.sleep(forTimeInterval: 0.5); shot("notif-typed")
        let send = sb.buttons["Send"].firstMatch
        if send.exists { send.tap() } else { field.typeText("\n") }
        Thread.sleep(forTimeInterval: 8)
      }
    }
    app.activate(); Thread.sleep(forTimeInterval: 5); shot("after-reply")
    for i in 0..<14 { app.swipeUp(velocity: .fast); _ = i }
    Thread.sleep(forTimeInterval: 1); shot("after-reply-end")
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

  /* The kept height (Haris 2026-11-25 22:12): Talk keeps each row's height, also on disk (heights-<server>.json); the
     reply's row kept one line's height though its words and time need two — the time on the words. Here: Talk run once,
     closed; the Mac writes a one-line height for "Blue or red? Check again" (8:41 PM yesterday, cid bubble-Blue-41) into
     Talk's kept heights; Talk opened again on the chat, a message arriving (the chat drawn again), pictures. */
  func testStaleHeight() {
    continueAfterFailure = true
    let env = ProcessInfo.processInfo.environment
    let outDir = env["E11_SHOTS_OUT"] ?? NSTemporaryDirectory()
    let out = URL(fileURLWithPath: outDir, isDirectory: true)
    var n = 0
    func shot(_ name: String) { n += 1; try? XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent(String(format: "S-%03d-%@.png", n, name))) }
    let app = XCUIApplication()
    app.launchEnvironment = ["E11_TALK_SERVER": env["E11_SERVER"] ?? "", "E11_TALK_DEV_EMAIL": env["E11_EMAIL"] ?? ""]
    app.launch()
    _ = app.tabBars.firstMatch.waitForExistence(timeout: 90)
    Thread.sleep(forTimeInterval: 6)
    let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for l in ["Allow", "Don’t Allow", "Don't Allow"] { let b = sb.buttons[l]; if b.waitForExistence(timeout: 2) { b.tap(); break } }
    app.terminate(); Thread.sleep(forTimeInterval: 1)
    try? "1".write(toFile: outDir + "/stale-now", atomically: true, encoding: .utf8)
    for _ in 0..<60 { if FileManager.default.fileExists(atPath: outDir + "/stale-done") { break }; Thread.sleep(forTimeInterval: 1) }
    app.launch()
    _ = app.tabBars.firstMatch.waitForExistence(timeout: 60)
    Thread.sleep(forTimeInterval: 4)
    func open() -> Bool {
      let t = app.staticTexts["Bubble check"].firstMatch
      guard t.waitForExistence(timeout: 3) else { return false }
      Thread.sleep(forTimeInterval: 1); t.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); Thread.sleep(forTimeInterval: 3)
      return app.textViews.firstMatch.waitForExistence(timeout: 5)
    }
    var ok = false
    for t in 0..<2 where !ok {
      let tb = app.tabBars.firstMatch.buttons.element(boundBy: t); if tb.exists { tb.tap(); Thread.sleep(forTimeInterval: 2) }
      if open() { ok = true; break }
      let rows = app.tables.firstMatch.cells
      for i in 0..<min(rows.count, 6) where !ok {
        rows.element(boundBy: i).tap(); Thread.sleep(forTimeInterval: 2)
        if open() { ok = true } else { app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap(); Thread.sleep(forTimeInterval: 1.2) }
      }
    }
    // up to yesterday's 8:41 PM — each screenful
    for i in 0..<10 {
      shot("up\(i)")
      if app.staticTexts["8:41 PM"].exists && i > 0 { break }
      app.swipeDown(velocity: .slow); Thread.sleep(forTimeInterval: 1.5)
    }
    shot("at-841"); app.swipeDown(velocity: .slow); Thread.sleep(forTimeInterval: 1.5); shot("at-841-b")
  }
}

