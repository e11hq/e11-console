import XCTest
// The finger: on the seek bar's knob, dragged to the very start in about a third of a second, held 0.2 s, let go — as in
// Haris's recording. Once as the apps are, once with the fix.
final class DragTests: XCTestCase {
  func drag(_ args: [String]) {
    let app = XCUIApplication(); app.launchArguments = args; app.launch()
    let state = app.staticTexts["state"]
    let ok = NSPredicate(format: "label == 'playing'")
    expectation(for: ok, evaluatedWith: state); waitForExpectations(timeout: 20)
    let bar = app.sliders["bar"]
    let knob = bar.coordinate(withNormalizedOffset: CGVector(dx: CGFloat(bar.normalizedSliderPosition), dy: 0.5))
    let start = bar.coordinate(withNormalizedOffset: CGVector(dx: -0.05, dy: 0.5))
    knob.press(forDuration: 0.05, thenDragTo: start, withVelocity: .fast, thenHoldForDuration: 0.2)
    sleep(3)
    app.terminate()
  }
  func test1AsTheAppsAre() { drag(["bar"]) }
  func test2WithTheFix() { drag(["bar", "fix"]) }
}
