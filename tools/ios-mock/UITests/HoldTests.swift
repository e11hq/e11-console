import XCTest

// Holds the first task in My Tasks (scene 7) and photographs Apple's context menu.
final class HoldTests: XCTestCase {
  func testHold() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-scene", "7"]
    app.launch()
    let cell = app.collectionViews.cells.element(boundBy: 0)
    XCTAssertTrue(cell.waitForExistence(timeout: 10))
    sleep(1)
    cell.press(forDuration: 1.3)
    sleep(2)
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "hold-A"; a.lifetime = .keepAlways; add(a)
  }
}
