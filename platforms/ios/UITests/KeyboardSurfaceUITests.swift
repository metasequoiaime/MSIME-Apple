import XCTest

final class KeyboardSurfaceUITests: KeyboardInterfaceTests {
  @MainActor
  func testKeyboardSpacingSettingsPersist() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["keyboardLayoutLink"].tap()
    let keys = app.sliders["appKeySpacingSlider"]
    let rows = app.sliders["appRowSpacingSlider"]
    XCTAssertTrue(keys.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["layoutPreset_msime"].exists)
    func position(_ slider: XCUIElement) throws -> CGFloat {
      let raw = try XCTUnwrap(slider.value as? String)
      let value = try XCTUnwrap(Double(raw.replacingOccurrences(of: "%", with: "")))
      if raw.contains("%") { return CGFloat(value / 100) }
      let minimum = slider.identifier == "appKeySpacingSlider" ? 3.0 : 4.0
      let maximum = slider.identifier == "appKeySpacingSlider" ? 6.0 : 10.0
      return CGFloat((value - minimum) / (maximum - minimum))
    }
    let originalKeys = try position(keys), originalRows = try position(rows)
    defer {
      keys.adjust(toNormalizedSliderPosition: originalKeys)
      rows.adjust(toNormalizedSliderPosition: originalRows)
    }
    keys.adjust(toNormalizedSliderPosition: originalKeys > 0.5 ? 0 : 1)
    rows.adjust(toNormalizedSliderPosition: originalRows > 0.5 ? 0 : 1)
    let changedKeys = try position(keys), changedRows = try position(rows)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["keyboardLayoutLink"].tap()
    XCTAssertEqual(try position(keys), changedKeys, accuracy: 0.01)
    XCTAssertEqual(try position(rows), changedRows, accuracy: 0.01)
  }

  @MainActor
  func testKeyboardHomePrioritizesTryoutAndQuickAdjustments() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-chat-ui-fixture"]
    app.launch()
    XCTAssertTrue(app.buttons["keyboardTryoutLink"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["skinSettingsLink"].exists)
    XCTAssertTrue(app.buttons["inputSettingsLink"].exists)
    XCTAssertTrue(app.buttons["keyboardLayoutLink"].exists)
    // 原来这几项藏在「键盘设置」那一页后面,现在直接摆在首页上。
    XCTAssertTrue(app.buttons["dictionarySettingsLink"].exists)
    XCTAssertTrue(app.buttons["aiSettingsLink"].exists)
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].exists)
    XCTAssertFalse(app.buttons["keyboardSettingsLink"].exists)
    XCTAssertFalse(app.buttons["keyboardGuideLink"].exists)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Keyboard home"; shot.lifetime = .deleteOnSuccess; add(shot)
    app.buttons["aiSettingsLink"].tap()
    XCTAssertTrue(app.navigationBars["AI 设置"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    // 首页原来有一张「高情商回复」卡片,点它会切到那个方案并进试用页;卡片撤了,试用页仍然从 keyboardTryoutLink 进。
    app.buttons["keyboardTryoutLink"].tap()
    XCTAssertTrue(app.navigationBars["试用键盘"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["keyboardTryoutField"].exists)
    app.navigationBars.buttons.firstMatch.tap()
    for _ in 0..<3 {
      if app.buttons["inputSettingsLink"].isHittable { break }
      app.swipeDown()
    }
    app.buttons["inputSettingsLink"].tap()
  }

  @MainActor
  func testReplyKeyboardPastesChoosesStyleAndInserts() {
    let app = XCUIApplication()
    app.launchArguments = ["-keyboardReplyPreview"]
    app.launch()
    XCTAssertTrue(app.buttons["replyPaste"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["replyStyle_8"].isHittable)
    let grid = XCTAttachment(screenshot: app.screenshot())
    grid.name = "Reply keyboard style grid"
    grid.lifetime = .deleteOnSuccess
    add(grid)
    app.buttons["replyPaste"].tap()
    XCTAssertTrue(app.buttons["replySource"].label.contains("你睡了吗"))
    app.buttons["replyStyle_7"].tap()
    let candidate = app.buttons["replyCandidate"]
    XCTAssertTrue(candidate.waitForExistence(timeout: 5))
    XCTAssertTrue(candidate.label.contains("还没呢"))
    candidate.tap()
    XCTAssertTrue(app.buttons["replyStyle_0"].exists)
    XCTAssertTrue(app.staticTexts["replyStatus"].label.contains("已插入"))
    app.segmentedControls["replyMode"].buttons["帮润色"].tap()
    app.buttons["replyClear"].tap()
    XCTAssertTrue(app.buttons["replySource"].label.contains("粘贴"))
  }

  @MainActor
  func testKeyboardAICompactLargeTextKeepsControlsReachable() {
    let app = XCUIApplication()
    app.launchArguments = ["-keyboardAIPreview", "-keyboardCompactPreview", "-keyboardLargeType", "-keyboardLongPreview"]
    app.launch()
    let send = app.buttons["keyboardAISend"]
    let close = app.buttons["keyboardServiceClose"]
    XCTAssertTrue(send.waitForExistence(timeout: 5))
    XCTAssertTrue(send.isHittable)
    XCTAssertTrue(close.isHittable)
    XCTAssertGreaterThanOrEqual(send.frame.height, 44)
    XCTAssertGreaterThanOrEqual(close.frame.height, 44)
    XCTAssertLessThanOrEqual(send.frame.maxY - close.frame.minY, 216.5)
    let scroll = app.scrollViews["keyboardAIScroll"]
    XCTAssertGreaterThan(scroll.frame.height, 60)
    // Error notifications must scroll back into view, including the same error on retry.
    for _ in 0..<2 {
      scroll.swipeUp()
      send.tap()
      let error = app.staticTexts["keyboardAIStatus"]
      XCTAssertTrue(error.waitForExistence(timeout: 5))
      XCTAssertGreaterThanOrEqual(error.frame.minY, scroll.frame.minY - 1)
      XCTAssertLessThan(error.frame.minY, send.frame.minY)
    }
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Keyboard AI compact accessibility text"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)
  }

  @MainActor
  func testKeyboardAIShowsSelectedTextAndRejectsStaleInput() {
    let app = XCUIApplication()
    app.launchArguments = ["-keyboardAIPreview"]
    app.launch()
    XCTAssertTrue(app.staticTexts["这是一段待润色的测试文字。只有点击发送才会请求服务。"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["输入位置或 AI 配置已变化，请关闭后重试。"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Keyboard AI narrow panel"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)
    XCTAssertGreaterThanOrEqual(app.buttons["keyboardAISend"].frame.height, 44)
    app.buttons["keyboardAISend"].tap()
    XCTAssertTrue(app.staticTexts["输入位置或 AI 配置已变化，请关闭后重试。"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["keyboardAIInsert"].exists)
  }

  @MainActor
  func testKeyboardAIOptInCanBeSavedAndRevoked() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-service.ai.provider", "custom",
      "-service.ai.endpoint", "https://keyboard-ai-fixture.invalid/v1/chat/completions",
      "-service.ai.model", "fixture"]
    func openAI() {
      openKeyboardSettingsIfNeeded(app)
    app.buttons["aiSettingsLink"].tap()
      for _ in 0..<6 {
        if app.switches["keyboardAIEnabled"].isHittable { break }
        app.swipeUp()
      }
    }
    app.launch()
    openAI()
    let toggle = app.switches["keyboardAIEnabled"]
    if toggle.value as? String == "1" { toggle.switches.firstMatch.tap() }
    toggle.switches.firstMatch.tap()
    for _ in 0..<6 {
      if app.buttons["saveServiceConfiguration"].isHittable { break }
      app.swipeDown()
    }
    app.buttons["saveServiceConfiguration"].tap()
    app.terminate()
    app.launch()
    openAI()
    XCTAssertEqual(toggle.value as? String, "1")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Keyboard AI settings enabled"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)
    toggle.switches.firstMatch.tap()
    app.terminate()
    app.launch()
    openAI()
    XCTAssertEqual(toggle.value as? String, "0")
  }

  @MainActor
  func testHapticStrengthPreviewAndPersistence() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    func openFeedback() {
      app.buttons["inputSettingsLink"].tap()
      for _ in 0..<5 {
        if app.switches["keyboardHapticsToggle"].isHittable { break }
        app.swipeUp()
      }
    }
    app.launch()
    openFeedback()
    let toggle = app.switches["keyboardHapticsToggle"]
    let initiallyEnabled = toggle.value as? String == "1"
    if !initiallyEnabled { toggle.switches.firstMatch.tap() }
    app.swipeUp()
    let picker = app.segmentedControls["keyboardHapticStrengthPicker"]
    let appeared = picker.waitForExistence(timeout: 5)
    if !appeared {
      let failure = XCTAttachment(screenshot: app.screenshot())
      failure.lifetime = .deleteOnSuccess
      add(failure)
    }
    XCTAssertTrue(appeared)
    let previous = picker.buttons.allElementsBoundByIndex.first { $0.isSelected }?.label ?? "中"
    picker.buttons["强"].tap()
    app.buttons["previewKeyboardHaptics"].tap()
    app.terminate()
    app.launch()
    openFeedback()
    app.swipeUp()
    XCTAssertTrue(picker.buttons["强"].isSelected)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Haptic strength settings"
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
    picker.buttons[previous].tap()
    if !initiallyEnabled { toggle.switches.firstMatch.tap() }
  }

  @MainActor
  func testKeyboardChatSendsAndDisplaysReply() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-chat-ui-fixture"]
    app.launch()
    for _ in 0..<6 {
      if app.buttons["keyboardTryoutLink"].isHittable { break }
      app.swipeUp()
    }
    app.buttons["keyboardTryoutLink"].tap()
    XCTAssertTrue(app.buttons["keyboardChatModelPicker"].waitForExistence(timeout: 5))
    let input = app.textFields["keyboardTryoutField"]
    input.tap(); input.typeText("hello")
    app.buttons["keyboardChatSend"].tap()
    XCTAssertTrue(app.staticTexts["已收到：hello"].waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, input.placeholderValue)
    app.buttons["dismissKeyboardButton"].tap()
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Keyboard chat with model selection"
    image.lifetime = .deleteOnSuccess
    add(image)
  }

  @MainActor
  func testResetRestoresTheKeyboardSettings() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["keyboardLayoutLink"].tap()

    let keys = app.sliders["appKeySpacingSlider"]
    let height = app.sliders["appKeyboardHeightSlider"]
    XCTAssertTrue(keys.waitForExistence(timeout: 5))

    // These settings outlive the app, and other cases here move them, so the defaults are taken by
    // resetting first rather than by assuming the values on arrival are untouched.
    app.buttons["appResetKeyboardSettings"].tap()
    let defaultKeys = try XCTUnwrap(keys.value as? String)
    let defaultHeight = try XCTUnwrap(height.value as? String)

    keys.adjust(toNormalizedSliderPosition: 0)
    height.adjust(toNormalizedSliderPosition: 1)
    XCTAssertNotEqual(keys.value as? String, defaultKeys, "滑块应先被改动,否则复位无从验证")

    app.buttons["appResetKeyboardSettings"].tap()
    XCTAssertTrue(wait(keys, until: "value == '\(defaultKeys)'"))
    XCTAssertEqual(height.value as? String, defaultHeight, "复位后高度应回到默认")

    // The values survive leaving and coming back, so the reset reached storage rather than only
    // the controls on screen.
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["keyboardLayoutLink"].tap()
    XCTAssertEqual(keys.value as? String, defaultKeys)
    XCTAssertEqual(height.value as? String, defaultHeight)
  }

  @MainActor
  func testNineKeySchemeSurvivesRelaunch() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    defer { restoreSchemeVisibility(in: app) }
    app.buttons["inputSettingsLink"].tap()
    let nine = app.switches["enabledInputScheme_nineKey"]
    XCTAssertTrue(nine.waitForExistence(timeout: 5))
    if nine.value as? String == "0" { nine.tap() }
    XCTAssertTrue(wait(nine, until: "value == '1'"))
    app.buttons["inputScheme_nineKey"].tap()
    XCTAssertEqual(app.buttons["inputScheme_nineKey"].value as? String, "已选择")
    app.terminate()
    app.launch()
    app.buttons["inputSettingsLink"].tap()
    XCTAssertTrue(app.buttons["inputScheme_nineKey"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["inputScheme_nineKey"].value as? String, "已选择",
                   "九键在重新启动后必须仍是选中的方案")
  }
}
