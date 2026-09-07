import XCTest

final class OnboardingUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testSettingsPersistAndExposeGuideAndTryout() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-onboarding-for-ui-tests"]
    app.launch()
    let finish = app.buttons["finishOnboardingButton"]
    XCTAssertTrue(finish.waitForExistence(timeout: 10))
    if !finish.isHittable { app.swipeUp() }
    finish.tap()
    app.launchArguments = ["-service.ai.endpoint", "", "-service.ai.model", ""]

    XCTAssertTrue(app.staticTexts["水杉输入法"].waitForExistence(timeout: 10))

    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    app.buttons["inputSettingsLink"].tap()
    XCTAssertTrue(app.buttons["inputScheme_quanpin"].exists)
    XCTAssertTrue(app.buttons["inputScheme_shuangpin"].exists)
    let nineKey = app.buttons["inputScheme_nineKey"]
    XCTAssertTrue(nineKey.exists)
    nineKey.tap()
    XCTAssertEqual(nineKey.value as? String, "已选择")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    app.buttons["inputSettingsLink"].tap()
    XCTAssertEqual(app.buttons["inputScheme_nineKey"].value as? String, "已选择")

    let outputPicker = app.segmentedControls["chineseOutputPicker"]
    XCTAssertTrue(outputPicker.exists)
    XCTAssertTrue(outputPicker.buttons["简体"].exists)
    XCTAssertTrue(outputPicker.buttons["繁体"].exists)

    app.navigationBars.buttons.element(boundBy: 0).tap()
    for (identifier, title) in [
      ("skinSettingsLink", "皮肤"), ("dictionarySettingsLink", "词库"),
      ("aiSettingsLink", "AI 设置"), ("voiceSettingsLink", "语音设置"),
    ] {
      let link = app.buttons[identifier]
      for _ in 0..<5 {
        if link.isHittable { break }
        app.swipeUp()
      }
      link.tap()
      XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
      if identifier == "skinSettingsLink" {
        app.buttons["skin_ocean"].tap()
        XCTAssertEqual(app.buttons["skin_ocean"].value as? String, "已选择")
      }
      if identifier == "aiSettingsLink" || identifier == "voiceSettingsLink" {
        XCTAssertTrue(app.textFields["serviceEndpoint"].exists)
        XCTAssertTrue(app.secureTextFields["serviceToken"].exists)
        if identifier == "aiSettingsLink" {
          let endpoint = app.textFields["serviceEndpoint"]
          endpoint.tap()
          endpoint.typeText("https://msime-ui-tests.invalid/v1/chat/completions")
          app.textFields["serviceModel"].tap()
          app.textFields["serviceModel"].typeText("fixture")
          app.secureTextFields["serviceToken"].tap()
          app.secureTextFields["serviceToken"].typeText("msime-ui-fixture")
          app.buttons["serviceDismissKeyboard"].tap()
          app.buttons["saveServiceConfiguration"].tap()
          XCTAssertTrue(app.staticTexts["配置已保存"].waitForExistence(timeout: 5))
          app.buttons["删除此服务的密钥"].tap()
          XCTAssertTrue(app.staticTexts["已删除此服务的密钥"].waitForExistence(timeout: 5))
        }
      }
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = title
      attachment.lifetime = .keepAlways
      add(attachment)
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }
    let tryoutLink = app.buttons["keyboardTryoutLink"]
    for _ in 0..<5 {
      if tryoutLink.isHittable { break }
      app.swipeUp()
    }
    let overview = XCTAttachment(screenshot: app.screenshot())
    overview.name = "设置分类"
    overview.lifetime = .keepAlways
    add(overview)
    tryoutLink.tap()
    let tryoutField = app.textFields["keyboardTryoutField"]
    XCTAssertTrue(tryoutField.waitForExistence(timeout: 10))
    // The first tap can be lost while XCTest is establishing the automation session on a fresh
    // simulator. Retap a bounded number of times, and only type after the field reports focus;
    // otherwise typeText fails with "Neither element nor any descendant has keyboard focus".
    var hasFocus = false
    for _ in 0..<3 {
      tryoutField.tap()
      let focused = expectation(
        for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: tryoutField)
      if XCTWaiter().wait(for: [focused], timeout: 4) == .completed {
        hasFocus = true
        break
      }
    }
    XCTAssertTrue(hasFocus, "The tryout field did not receive keyboard focus after tapping")
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
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["keyboardGuideLink"].tap()
    XCTAssertTrue(app.navigationBars["启用指南"].exists)
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].exists)
  }
}
