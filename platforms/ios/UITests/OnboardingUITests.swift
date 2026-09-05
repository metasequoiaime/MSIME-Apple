import XCTest

final class OnboardingUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testOnboardingExposesEnablementPathAndTryoutField() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["水杉输入法"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].exists)

    let schemePicker = app.segmentedControls["inputSchemePicker"]
    XCTAssertTrue(schemePicker.exists)
    XCTAssertTrue(schemePicker.buttons["全拼"].exists)
    XCTAssertTrue(schemePicker.buttons["小鹤双拼"].exists)

    let outputPicker = app.segmentedControls["chineseOutputPicker"]
    XCTAssertTrue(outputPicker.exists)
    XCTAssertTrue(outputPicker.buttons["简体"].exists)
    XCTAssertTrue(outputPicker.buttons["繁体"].exists)

    let tryoutField = app.textFields["keyboardTryoutField"]
    XCTAssertTrue(tryoutField.exists)
    tryoutField.tap()
    // Tapping only requests first responder. Typing before the field actually holds keyboard focus fails with "Neither element nor any descendant has keyboard focus", so wait for the focus rather than assuming the transition already landed.
    let focused = expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: tryoutField)
    wait(for: [focused], timeout: 10)
    tryoutField.typeText("test")
    XCTAssertEqual(tryoutField.value as? String, "test")

    // The field had no way to put the keyboard away without leaving the app.
    let dismissButton = app.buttons["dismissKeyboardButton"]
    XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
    dismissButton.tap()
    let unfocused = expectation(
      for: NSPredicate(format: "hasKeyboardFocus == false"), evaluatedWith: tryoutField)
    wait(for: [unfocused], timeout: 10)
    XCTAssertEqual(tryoutField.value as? String, "test")
  }
}
