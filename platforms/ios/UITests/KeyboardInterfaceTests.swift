import XCTest

/// What every interface case needs, and the reason they are in more than one class.
///
/// Xcode spreads a parallel test run across simulator clones by *class*, not by case. Thirty-eight
/// cases in one class meant one clone working and the rest idle, which is the whole of why enabling
/// parallel testing changed nothing. Split by the surface each case walks through, so the clones
/// have something to divide.
class KeyboardInterfaceTests: XCTestCase {
  @MainActor
  func wait(_ element: XCUIElement, until predicate: String, timeout: TimeInterval = 5) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: predicate), object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  // Driving the switches back on would need the app to still be on a screen this test can reach,
  // which a failure part way through does not promise. A relaunch clears the stored set instead,
  // and an absent set means every scheme is visible.

  @MainActor
  func restoreSchemeVisibility(in app: XCUIApplication) {
    app.terminate()
    app.launchArguments = ["--reset-input-schemes-for-ui-tests"]
    app.launch()
    app.terminate()
  }

  /// 设置项都在首页上了,这里只负责把它滚到看得见 —— 原来还要先点开「键盘设置」那一页。

  @MainActor
  func openKeyboardSettingsIfNeeded(_ app: XCUIApplication) {
    let entry = app.buttons["aiSettingsLink"]
    guard entry.exists else { return }
    for _ in 0..<4 { if entry.isHittable { break }; app.swipeUp() }
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func selectProvider(_ name: String, picker: String, app: XCUIApplication) {
    for _ in 0..<4 {
      if app.buttons[picker].isHittable { break }
      app.swipeDown()
    }
    app.buttons[picker].tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText(name)
    app.buttons[name].tap()
  }
}
