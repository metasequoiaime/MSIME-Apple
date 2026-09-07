import XCTest

final class OnboardingUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  private func selectProvider(_ name: String, picker: String, app: XCUIApplication) {
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

  @MainActor
  func testFetchingModelsRequiresKeyButNotModel() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-service.ai.provider", "custom",
      "-service.ai.endpoint", "https://catalog-no-key.invalid/v1/chat/completions", "-service.ai.model", ""]
    app.launch()
    app.buttons["aiSettingsLink"].tap()
    let fetch = app.buttons["fetchServiceModels"]
    XCTAssertTrue(fetch.waitForExistence(timeout: 5))
    fetch.tap()
    XCTAssertTrue(app.staticTexts["请先填写 API Key，或使用已保存的密钥。"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["serviceModel"].exists)
  }

  @MainActor
  func testSkinShowsFullKeyboardInBothLayoutsAndAppearances() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    let layout = app.segmentedControls["skinPreviewLayout"]
    XCTAssertTrue(layout.waitForExistence(timeout: 5))
    layout.buttons["26 键"].tap()
    let preview = app.otherElements["fullKeyboardSkinPreview"]
    XCTAssertTrue(preview.exists)
    XCTAssertTrue(preview.label.contains("26 键"))
    let light = XCTAttachment(screenshot: app.screenshot())
    light.name = "完整 26 键皮肤预览"
    light.lifetime = .keepAlways
    add(light)
    layout.buttons["9 键"].tap()
    app.switches["skinPreviewDark"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertEqual(app.switches["skinPreviewDark"].value as? String, "1")
    XCTAssertTrue(preview.label.contains("9 键"))
    let dark = XCTAttachment(screenshot: app.screenshot())
    dark.name = "完整 9 键深色皮肤预览"
    dark.lifetime = .keepAlways
    add(dark)
  }

  @MainActor
  func testDesignedSkinsShowDistinctPreviews() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    for skin in ["typewriter", "candy", "midnight", "blueprint"] {
      let button = app.buttons["skin_" + skin]
      for _ in 0..<8 {
        if button.isHittable { break }
        app.swipeUp()
      }
      button.tap()
      XCTAssertEqual(button.value as? String, "已选择")
      for _ in 0..<8 {
        if app.segmentedControls["skinPreviewLayout"].isHittable { break }
        app.swipeDown()
      }
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = "设计皮肤-" + skin
      image.lifetime = .keepAlways
      add(image)
    }
  }

  @MainActor
  func testProviderCatalogShowsIcons() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["aiSettingsLink"].tap()
    app.buttons["aiProviderPicker"].tap()
    XCTAssertTrue(app.buttons["EveryAPI"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "AI 服务商图标列表"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["取消"].tap()
  }

  @MainActor
  func testVoiceProviderSelectionAutofillsAndClearsUnsavedKey() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-service.voice.provider", "custom",
                           "-service.voice.endpoint", "", "-service.voice.model", ""]
    app.launch()
    let link = app.buttons["voiceSettingsLink"]
    if !link.isHittable { app.swipeUp() }
    link.tap()
    let token = app.secureTextFields["serviceToken"]
    token.tap()
    token.typeText("voice-switch-fixture")
    app.buttons["serviceDismissKeyboard"].tap()
    selectProvider("硅基流动 · SenseVoice", picker: "voiceProviderPicker", app: app)
    XCTAssertEqual(app.textFields["serviceEndpoint"].value as? String,
                   "https://api.siliconflow.cn/v1/audio/transcriptions")
    XCTAssertEqual(app.buttons["serviceModelPicker"].value as? String, "FunAudioLLM/SenseVoiceSmall")
    XCTAssertFalse(app.textFields["serviceEndpoint"].isEnabled)
    XCTAssertEqual(token.value as? String, token.placeholderValue)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "语音服务商预设"
    attachment.lifetime = .keepAlways
    add(attachment)
    selectProvider("Groq · Whisper", picker: "voiceProviderPicker", app: app)
    XCTAssertEqual(app.buttons["serviceModelPicker"].value as? String, "whisper-large-v3-turbo")
    XCTAssertFalse(app.textFields["serviceModel"].exists)
    app.buttons["serviceModelPicker"].tap()
    app.buttons["whisper-large-v3"].tap()
    XCTAssertEqual(app.buttons["serviceModelPicker"].value as? String, "whisper-large-v3")

    selectProvider("EveryAPI", picker: "voiceProviderPicker", app: app)
    XCTAssertEqual(app.textFields["serviceEndpoint"].value as? String, "https://api.everyapi.ai/v1/audio/transcriptions")
    XCTAssertEqual(app.buttons["serviceModelPicker"].value as? String, "openai/whisper-large-v3-turbo")
    XCTAssertTrue(app.images["everyAPIProviderLogo"].exists)
    selectProvider("自定义", picker: "voiceProviderPicker", app: app)
    XCTAssertTrue(app.textFields["serviceEndpoint"].isEnabled)
    XCTAssertEqual(app.textFields["serviceEndpoint"].value as? String, app.textFields["serviceEndpoint"].placeholderValue)
  }

  @MainActor
  func testAIProviderSelectionAutofillsAndClearsUnsavedKey() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-service.ai.provider", "custom",
                           "-service.ai.endpoint", "", "-service.ai.model", ""]
    app.launch()
    app.buttons["aiSettingsLink"].tap()
    let token = app.secureTextFields["serviceToken"]
    token.tap()
    token.typeText("provider-switch-fixture")
    app.buttons["serviceDismissKeyboard"].tap()
    selectProvider("DeepSeek", picker: "aiProviderPicker", app: app)
    XCTAssertEqual(app.textFields["serviceEndpoint"].value as? String, "https://api.deepseek.com/chat/completions")
    XCTAssertEqual(app.buttons["serviceModelPicker"].value as? String, "deepseek-v4-flash")
    XCTAssertFalse(app.textFields["serviceModel"].exists)
    app.buttons["serviceModelPicker"].tap()
    app.buttons["deepseek-v4-pro"].tap()
    XCTAssertEqual(app.buttons["serviceModelPicker"].value as? String, "deepseek-v4-pro")
    app.buttons["serviceModelPicker"].tap()
    app.buttons["自定义模型…"].tap()
    XCTAssertTrue(app.textFields["serviceModel"].exists)
    app.buttons["serviceModelPicker"].tap()
    app.buttons["deepseek-v4-flash"].tap()
    XCTAssertFalse(app.textFields["serviceModel"].exists)

    XCTAssertEqual(token.value as? String, token.placeholderValue)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "AI 服务商预设"
    attachment.lifetime = .keepAlways
    add(attachment)
    selectProvider("Google · Gemini", picker: "aiProviderPicker", app: app)
    XCTAssertEqual(app.textFields["serviceEndpoint"].value as? String,
                   "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    selectProvider("EveryAPI", picker: "aiProviderPicker", app: app)
    XCTAssertEqual(app.textFields["serviceEndpoint"].value as? String, "https://api.everyapi.ai/v1/chat/completions")
    XCTAssertEqual(app.buttons["serviceModelPicker"].value as? String, "deepseek-v4-flash")
    XCTAssertTrue(app.images["everyAPIProviderLogo"].exists)
    selectProvider("自定义", picker: "aiProviderPicker", app: app)
    XCTAssertTrue(app.textFields["serviceEndpoint"].isEnabled)
    XCTAssertEqual(app.textFields["serviceEndpoint"].value as? String, app.textFields["serviceEndpoint"].placeholderValue)
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
      ("typingStatisticsLink", "打字统计"),
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
          app.buttons["serviceDismissKeyboard"].tap()
          app.secureTextFields["serviceToken"].tap()
          app.secureTextFields["serviceToken"].typeText("msime-ui-fixture")
          app.buttons["serviceDismissKeyboard"].tap()
          app.buttons["saveServiceConfiguration"].tap()
          for _ in 0..<3 {
            if app.staticTexts["配置已保存"].exists { break }
            app.swipeUp()
          }
          XCTAssertTrue(app.staticTexts["配置已保存"].waitForExistence(timeout: 5))
          let deleteKey = app.buttons["删除此服务的密钥"]
          for _ in 0..<3 {
            if deleteKey.isHittable { break }
            app.swipeDown()
          }
          deleteKey.tap()
          for _ in 0..<3 {
            if app.staticTexts["已删除此服务的密钥"].exists { break }
            app.swipeUp()
          }
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
