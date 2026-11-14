import XCTest

/* The App Store screenshots that need a finger (Haris 2026-11-14: "Simulator does it"): Apple's UI testing, signed in as one
   person against the App Review copy's made-up demo data (ios/shots_ui.py), holds an Inbox row for Apple's peek and taps a
   birthday for its greeting, taking a screenshot at each moment into E11_CRAWL_OUT. A test only — nothing in the app changes. */
final class ShotsTests: XCTestCase {
  func testHold() {
    let env = ProcessInfo.processInfo.environment
    let out = URL(fileURLWithPath: env["E11_CRAWL_OUT"] ?? NSTemporaryDirectory(), isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let app = XCUIApplication()
    app.launchEnvironment = ["E11_SERVER": env["E11_SERVER"] ?? "", "E11_SELFTEST": "crawl", "E11_SELFTEST_EMAIL": env["E11_EMAIL"] ?? ""]
    app.launch()
    _ = app.tabBars.firstMatch.waitForExistence(timeout: 90)
    Thread.sleep(forTimeInterval: 5)
    func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent("U-\(n).png")) }
    func find(_ s: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    shot("00-start")
    let inbox = app.tabBars.firstMatch.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox'")).firstMatch
    if inbox.exists { inbox.tap() }
    Thread.sleep(forTimeInterval: 3)
    let all = app.buttons["All"]
    if all.exists { all.tap(); Thread.sleep(forTimeInterval: 2) }
    shot("01-inbox")
    // the peek: a comment row held
    for text in (env["E11_PEEK"] ?? "A is the one|Two directions|Amendments required").split(separator: "|").map(String.init) {
      let row = find(text)
      guard row.waitForExistence(timeout: 5) else { continue }
      row.press(forDuration: 1.3)
      Thread.sleep(forTimeInterval: 1.6)
      shot("02-peek")
      Thread.sleep(forTimeInterval: 1.0)
      shot("03-peek")
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
      Thread.sleep(forTimeInterval: 1.5)
      break
    }
    // the birthday's greeting
    let bday = app.cells.containing(NSPredicate(format: "label CONTAINS 'birthday'")).firstMatch
    if bday.waitForExistence(timeout: 5) {
      bday.tap()
      for i in 0..<8 { Thread.sleep(forTimeInterval: 0.8); shot("04-greet-\(i)") }
    }
    shot("07-end")
  }
  // the birthday person's own greeting, as the app opens on their birthday (Boot: the pops' birthday)
  func testGreet() {
    let env = ProcessInfo.processInfo.environment
    let out = URL(fileURLWithPath: env["E11_CRAWL_OUT"] ?? NSTemporaryDirectory(), isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let app = XCUIApplication()
    app.launchEnvironment = ["E11_SERVER": env["E11_SERVER"] ?? "", "E11_SELFTEST": "crawl", "E11_SELFTEST_EMAIL": env["E11_EMAIL2"] ?? ""]
    app.launch()
    for i in 0..<30 { Thread.sleep(forTimeInterval: 1.0); try? XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent(String(format: "G-%02d.png", i))) }
  }
}
