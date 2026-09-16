import XCTest

final class SettingsUITests: KeyboardInterfaceTests {
  @MainActor
  func testPersonalDictionaryValidatesBeforeQueueing() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-personalDictionaryTestID", UUID().uuidString]
    app.launch()
    openKeyboardSettingsIfNeeded(app)
    app.buttons["dictionarySettingsLink"].tap()
    app.buttons["personalDictionaryLink"].tap()
    app.buttons["importPersonalDictionary"].tap()
    XCTAssertTrue(app.buttons["choosePersonalDictionaryFile"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["confirmPersonalDictionaryImport"].isEnabled)
    let importScreen = XCTAttachment(screenshot: app.screenshot())
    importScreen.name = "Personal dictionary import"
    importScreen.lifetime = .deleteOnSuccess
    add(importScreen)
    app.buttons["取消"].tap()
    app.buttons["addPersonalWord"].tap()
    app.textFields["personalWordValue"].tap()
    app.textFields["personalWordValue"].typeText("你好")
    app.textFields["personalWordCode"].tap()
    app.textFields["personalWordCode"].typeText("nihao")
    app.buttons["savePersonalWord"].tap()
    XCTAssertTrue(app.staticTexts["请填写完整拼音，用空格或英文单引号分隔音节，例如 ni hao。"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Personal word editor validation"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)
    app.textFields["personalWordCode"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "ni hao")
    app.buttons["savePersonalWord"].tap()
    XCTAssertTrue(app.staticTexts["1 项等待键盘同步"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    openKeyboardSettingsIfNeeded(app)
    app.buttons["dictionarySettingsLink"].tap()
    app.buttons["personalDictionaryLink"].tap()
    XCTAssertTrue(app.staticTexts["1 项等待键盘同步"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["等待同步 · 保存"].exists)
    let pending = XCTAttachment(screenshot: app.screenshot())
    pending.name = "Personal dictionary pending confirmation"
    pending.lifetime = .deleteOnSuccess
    add(pending)
  }

  @MainActor
  func testStatisticsTabsAndDaySelection() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.tabBars.buttons["统计"].tap()
    // 原来这里是 7 天 / 30 天 / 累计;时间切换撤了,三块内容改成标签轮流占这一屏。
    let tabs = app.segmentedControls["statisticsTab"]
    XCTAssertTrue(tabs.waitForExistence(timeout: 5))
    let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "statisticsDay_")).firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 3), app.debugDescription)
    day.tap()
    XCTAssertTrue(app.buttons["返回累计"].exists)
    app.buttons["返回累计"].tap()
    let trend = XCTAttachment(screenshot: app.screenshot())
    trend.name = "统计趋势"
    trend.lifetime = .keepAlways
    add(trend)

    tabs.buttons["类型"].tap()
    XCTAssertFalse(day.exists, "切到类型之后趋势那一块就不在了")
    let kind = XCTAttachment(screenshot: app.screenshot())
    kind.name = "统计字符类型"
    kind.lifetime = .keepAlways
    add(kind)

    tabs.buttons["模式"].tap()
    let mode = XCTAttachment(screenshot: app.screenshot())
    mode.name = "统计语言模式"
    mode.lifetime = .keepAlways
    add(mode)

    tabs.buttons["方案"].tap()
    let scheme = XCTAttachment(screenshot: app.screenshot())
    scheme.name = "统计输入方案"
    scheme.lifetime = .keepAlways
    add(scheme)

    tabs.buttons["趋势"].tap()
    XCTAssertTrue(day.waitForExistence(timeout: 3), "切回趋势要能看到柱形")

    // 开关、刷新、清空从每一屏底下挪进了右上角的菜单。
    XCTAssertFalse(app.switches["typingStatisticsEnabled"].exists)
    app.buttons["statisticsMenu"].tap()
    XCTAssertTrue(app.buttons["typingStatisticsEnabled"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["resetTypingStatistics"].exists)
    let menu = XCTAttachment(screenshot: app.screenshot())
    menu.name = "统计菜单"
    menu.lifetime = .keepAlways
    add(menu)
    app.buttons["刷新统计"].tap()
  }

  @MainActor
  func testFetchingModelsRequiresKeyButNotModel() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-service.ai.provider", "custom",
      "-service.ai.endpoint", "https://catalog-no-key.invalid/v1/chat/completions", "-service.ai.model", ""]
    app.launch()
    openKeyboardSettingsIfNeeded(app)
    app.buttons["aiSettingsLink"].tap()
    let fetch = app.buttons["fetchServiceModels"]
    XCTAssertTrue(fetch.waitForExistence(timeout: 5))
    fetch.tap()
    XCTAssertTrue(app.staticTexts["请先填写 API Key，或使用已保存的密钥。"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["serviceModel"].exists)
  }

  @MainActor
  func testAIProviderSelectionAutofillsAndClearsUnsavedKey() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-service.ai.provider", "custom",
                           "-service.ai.endpoint", "", "-service.ai.model", ""]
    app.launch()
    openKeyboardSettingsIfNeeded(app)
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
    attachment.lifetime = .deleteOnSuccess
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
  func testFuzzyPreferencesAndInformationPages() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["inputSettingsLink"].tap()
    for _ in 0..<5 {
      if app.buttons["fuzzyPinyinSettingsLink"].isHittable { break }
      app.swipeUp()
    }
    app.buttons["fuzzyPinyinSettingsLink"].tap()
    XCTAssertTrue(app.staticTexts["fuzzyPinyinAvailability"].exists)
    let enabled = app.switches["fuzzyPinyinEnabled"]
    if enabled.value as? String == "0" { enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
    let rule = app.switches["fuzzyPinyinRule_z-zh"]
    if rule.value as? String == "0" { rule.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
    XCTAssertEqual(enabled.value as? String, "1")
    XCTAssertEqual(rule.value as? String, "1")
    app.terminate()
    app.launch()
    app.buttons["inputSettingsLink"].tap()
    for _ in 0..<5 {
      if app.buttons["fuzzyPinyinSettingsLink"].isHittable { break }
      app.swipeUp()
    }
    app.buttons["fuzzyPinyinSettingsLink"].tap()
    XCTAssertEqual(enabled.value as? String, "1")
    XCTAssertEqual(rule.value as? String, "1")
    rule.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.tabBars.buttons["我的"].tap()
    for _ in 0..<6 {
      if app.buttons["aboutSettingsLink"].isHittable { break }
      app.swipeUp()
    }
    // 下载指南挂在「关于水杉」里。「我的」页上原本还有一个指向同一页的入口,重复的那个已经去掉。
    app.buttons["aboutSettingsLink"].tap()
    XCTAssertTrue(app.navigationBars["关于水杉"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["aboutAppVersion"].exists)
    app.buttons["desktopDownloadLink"].tap()
    for platform in ["macOS", "Windows", "Linux"] {
      app.segmentedControls["desktopPlatformPicker"].buttons[platform].tap()
      XCTAssertTrue(app.staticTexts[platform + " 安装指南"].exists)
      XCTAssertTrue(app.buttons["desktopReleaseLink"].exists)
    }
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Desktop download guide"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.navigationBars["关于水杉"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testHandwritingCanBeEnabledSelectedAndDisabled() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    // This one ends with handwriting hidden on purpose, which is still a scheme later tests cannot
    // select until the stored set is cleared.
    defer { restoreSchemeVisibility(in: app) }
    app.buttons["inputSettingsLink"].tap()
    let enabled = app.switches["enabledInputScheme_handwriting"]
    for _ in 0..<8 { if enabled.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(enabled.isHittable)
    if enabled.value as? String == "0" { enabled.tap() }
    let scheme = app.buttons["inputScheme_handwriting"]
    scheme.tap()
    XCTAssertEqual(scheme.value as? String, "已选择")
    app.terminate(); app.launch()
    XCTAssertTrue(app.staticTexts["手写输入"].waitForExistence(timeout: 5))
    app.buttons["inputSettingsLink"].tap()
    for _ in 0..<8 { if enabled.isHittable { break }; app.swipeUp() }
    enabled.tap()
    XCTAssertFalse(scheme.isEnabled)
  }

  @MainActor
  func testInputSchemeVisibilityPersistsAndFallsBack() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    // Hidden schemes live in the app group and outlive this bundle, and a scheme this test leaves
    // hidden makes InputSchemePreference downgrade every later assignment of it. Restore visibility
    // even when an assertion below fails, or the keyboard unit tests inherit a crippled scheme list.
    defer { restoreSchemeVisibility(in: app) }
    app.buttons["inputSettingsLink"].tap()
    let full = app.switches["enabledInputScheme_quanpin"]
    let nine = app.switches["enabledInputScheme_nineKey"]
    if full.value as? String == "0" { full.tap() }
    if nine.value as? String == "0" { nine.tap() }
    app.buttons["inputScheme_nineKey"].tap()
    nine.tap()
    // Toggling visibility rebuilds the scheme list, so wait for the switch to report its new
    // state instead of reading it while SwiftUI is still applying the change.
    XCTAssertTrue(wait(nine, until: "value == '0'"))
    XCTAssertEqual(app.buttons["inputScheme_quanpin"].value as? String, "已选择")
    app.terminate()
    app.launch()
    app.buttons["inputSettingsLink"].tap()
    XCTAssertEqual(nine.value as? String, "0")
    // The switch reports its stored value before SwiftUI has rebuilt the scheme list below it, so
    // the button is briefly still enabled after a relaunch.
    XCTAssertTrue(wait(app.buttons["inputScheme_nineKey"], until: "isEnabled == false"))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Input scheme visibility settings"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)
    nine.tap()
    // Same two steps as the hide above: the switch commits first and the scheme list is rebuilt
    // from it, so waiting on the button alone races a rebuild that has not been asked for yet.
    // Toggling back also follows a screenshot, which leaves the app busy for a moment longer.
    // The switch itself needs the same budget as the rebuild that follows it, not the default 5s. The
    // case passed in 59.9s on develop and failed here at 94.274s on a contended Intel runner, on this
    // line: the tap lands, the screenshot above is still settling, and 5s runs out before SwiftUI
    // reports the new value.
    XCTAssertTrue(wait(nine, until: "value == '1'", timeout: 15))
    XCTAssertTrue(wait(app.buttons["inputScheme_nineKey"], until: "isEnabled == true", timeout: 15))
  }

  @MainActor
  func testSettingsPersistAndExposeGuideAndTryout() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-onboarding-for-ui-tests"]
    app.launch()
    let finish = app.buttons["skipOnboardingButton"]
    XCTAssertTrue(finish.waitForExistence(timeout: 10))
    if !finish.isHittable { app.swipeUp() }
    finish.tap()
    app.launchArguments = ["-service.ai.endpoint", "", "-service.ai.model", ""]

    XCTAssertTrue(app.staticTexts["让输入，更像你"].waitForExistence(timeout: 10))

    XCTAssertTrue(app.buttons["inputSettingsLink"].waitForExistence(timeout: 5))
    app.buttons["inputSettingsLink"].tap()
    XCTAssertTrue(app.buttons["inputScheme_quanpin"].exists)
    XCTAssertTrue(app.buttons["inputScheme_shuangpin"].exists)
    let nineKey = app.buttons["inputScheme_nineKey"]
    XCTAssertTrue(nineKey.exists)
    nineKey.tap()
    XCTAssertEqual(nineKey.value as? String, "已选择")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["inputSettingsLink"].waitForExistence(timeout: 5))
    app.buttons["inputSettingsLink"].tap()
    XCTAssertEqual(app.buttons["inputScheme_nineKey"].value as? String, "已选择")

    let outputPicker = app.segmentedControls["chineseOutputPicker"]
    for _ in 0..<6 {
      if outputPicker.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(outputPicker.exists)
    XCTAssertTrue(outputPicker.buttons["简体"].exists)
    XCTAssertTrue(outputPicker.buttons["繁体"].exists)

    app.navigationBars.buttons.element(boundBy: 0).tap()
    for (identifier, title) in [
      ("skinSettingsLink", "皮肤"), ("dictionarySettingsLink", "词库"),
      ("aiSettingsLink", "AI 设置"),
    ] {
      if !app.buttons[identifier].exists { openKeyboardSettingsIfNeeded(app) }
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
      if identifier == "aiSettingsLink" {
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
      attachment.lifetime = .deleteOnSuccess
      add(attachment)
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }
    if !app.buttons["keyboardTryoutLink"].exists { app.navigationBars.buttons.firstMatch.tap() }
    let tryoutLink = app.buttons["keyboardTryoutLink"]
    for _ in 0..<5 {
      if tryoutLink.isHittable { break }
      app.swipeUp()
    }
    let overview = XCTAttachment(screenshot: app.screenshot())
    overview.name = "设置分类"
    overview.lifetime = .deleteOnSuccess
    add(overview)
    tryoutLink.tap()
    let tryoutField = app.textFields["keyboardTryoutField"]
    XCTAssertTrue(tryoutField.waitForExistence(timeout: 10))
    // This screen focuses the field on appearance. Avoid tapping an already focused field
    // while the keyboard is animating: XCTest can hit a keyboard key instead of the field.
    let focused = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: tryoutField)
    guard XCTWaiter.wait(for: [focused], timeout: 10) == .completed else {
      XCTFail("The tryout field did not receive focus on appearance")
      return
    }
    tryoutField.typeText("test")
    // A loaded runner reports the field's value while it is still catching up with the keystrokes,
    // which reads as a prefix of the typed text rather than a lost character.
    XCTAssertTrue(wait(tryoutField, until: "value == 'test'"))

    // The field had no way to put the keyboard away without leaving the app.
    let dismissButton = app.buttons["dismissKeyboardButton"]
    XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
    dismissButton.tap()
    let unfocused = expectation(
      for: NSPredicate(format: "hasKeyboardFocus == false"), evaluatedWith: tryoutField)
    wait(for: [unfocused], timeout: 10)
    XCTAssertEqual(tryoutField.value as? String, "test")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertFalse(app.buttons["keyboardGuideLink"].exists)
    openKeyboardSettingsIfNeeded(app)
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].exists)
  }
}
