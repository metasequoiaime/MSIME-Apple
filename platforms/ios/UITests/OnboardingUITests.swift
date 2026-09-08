import XCTest

final class OnboardingUITests: XCTestCase {
  @MainActor
  func testAccountEntryExplainsExplicitDataSharing() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    let account = app.tabBars.buttons["我的"]
    XCTAssertTrue(account.waitForExistence(timeout: 5))
    account.tap()
    XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["accountLocalDesigns"].exists)
  }

  @MainActor
  func testLayoutPresetSelectionPersists() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["keyboardLayoutLink"].tap()
    let mode = app.segmentedControls["layoutPreviewMode"]
    let first = app.buttons["layoutPreset_msime"]
    var previewHeights: [CGFloat] = []
    for title in ["26 键", "9 键"] {
      mode.buttons[title].tap()
      previewHeights.append(first.frame.height)
      XCTAssertGreaterThan(first.frame.height, 280, "完整布局预览不能使用压缩缩略图高度")
      let shot = XCTAttachment(screenshot: app.screenshot())
      shot.name = "Full layout preview \(title)"; shot.lifetime = .keepAlways; add(shot)
    }
    XCTAssertEqual(previewHeights[0], previewHeights[1], accuracy: 1)
    let wechat = app.buttons["layoutPreset_wechat"]
    for _ in 0..<6 {
      if wechat.isHittable { break }
      app.swipeUp()
    }
    wechat.tap()
    XCTAssertEqual(wechat.value as? String, "已选择")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["keyboardLayoutLink"].tap()
    for _ in 0..<6 {
      if wechat.isHittable { break }
      app.swipeUp()
    }
    XCTAssertEqual(wechat.value as? String, "已选择")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Layout presets selection"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["keyboardLayoutLink"].tap()
    app.buttons["layoutPreset_msime"].tap()
  }

  @MainActor
  func testAISkinGenerationSavesAndPreparesCommunityPublication() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-aiSkinPreview"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    app.buttons["openAISkinDesigner"].tap()
    XCTAssertTrue(app.navigationBars["AI 皮肤抽卡"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.textViews["aiSkinPrompt"].exists)
    XCTAssertTrue(app.buttons["generateAISkins"].isEnabled)
    let deck = XCTAttachment(screenshot: app.screenshot())
    deck.name = "AI 皮肤抽卡入口"; deck.lifetime = .keepAlways; add(deck)
    app.buttons["generateAISkins"].tap()
    let save = app.buttons["saveAISkin_AI 测试 1"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    save.tap()
    XCTAssertEqual(save.label, "已保存")
    app.buttons["publishAISkin_AI 测试 1"].tap()
    XCTAssertTrue(app.navigationBars["发布皮肤"].waitForExistence(timeout: 5))
    XCTAssertTrue((app.textFields["皮肤名称（最多 32 字）"].value as? String)?.hasPrefix("AI 测试 1") == true)
    XCTAssertFalse(app.buttons["confirmCommunitySkinPublication"].isEnabled, "Publication requires explicit consent")
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "AI 生成皮肤的发布预览"; shot.lifetime = .keepAlways; add(shot)
    app.buttons["取消"].tap()
  }

  @MainActor
  func testCommunityCategoriesPreviewAndPublisher() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-communityPreview"]
    app.launch()
    app.tabBars.buttons["社区"].tap()
    app.buttons["communityCategory-1"].tap()
    XCTAssertEqual(app.segmentedControls.count, 0)
    let first = app.buttons["communityResource-10000000-0000-4000-8000-000000000001"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    let second = app.buttons["communityResource-10000000-0000-4000-8000-000000000002"]
    XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Community word packs"; shot.lifetime = .keepAlways; add(shot)
    first.tap()
    XCTAssertTrue(app.buttons["communityImportLocal"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["communityCategory-2"].tap()
    app.buttons["communityResource-10000000-0000-4000-8000-000000000003"].tap()
    XCTAssertTrue(app.buttons["添加到回复键盘"].waitForExistence(timeout: 5))
    let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Community reply preview"; detail.lifetime = .keepAlways; add(detail)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["publishCommunityWork"].tap()
    XCTAssertTrue(app.navigationBars["发布回复"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textViews["communityPromptEditor"].exists)
    app.buttons["取消"].tap()
    app.buttons["communityCategory-1"].tap()
    app.buttons["publishCommunityWork"].tap()
    XCTAssertTrue(app.navigationBars["发布词库"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["添加到待发布词库"].exists)
    app.buttons["取消"].tap()
    app.buttons["communityCategory-0"].tap()
    app.buttons["publishCommunityWork"].tap()
    XCTAssertTrue(app.navigationBars["发布皮肤"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSkinDownloadOpensTryoutAndRestores() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-communityPreview", "--keyboard-chat-ui-fixture"]
    app.launch()
    XCTAssertFalse(app.buttons["keyboardGuideLink"].exists)
    XCTAssertFalse(app.buttons["aboutSettingsLink"].exists)
    app.tabBars.buttons["社区"].tap()
    let card = app.buttons["communitySkinCard-20000000-0000-4000-8000-000000000001"]
    XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
    app.buttons["downloadCommunitySkin"].tap()
    XCTAssertTrue(app.navigationBars["试用键盘"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["keyboardTryoutField"].exists)
    XCTAssertTrue(app.buttons["keepTrialSkin"].exists)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Skin trial with undo"; shot.lifetime = .keepAlways; add(shot)
    app.buttons["restoreTrialSkin"].tap()
    XCTAssertTrue(app.navigationBars["皮肤详情"].waitForExistence(timeout: 5))
    app.tabBars.buttons["我的"].tap()
    for _ in 0..<5 {
      if app.buttons["aboutSettingsLink"].isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(app.buttons["desktopDownloadLink"].exists)
    app.buttons["aboutSettingsLink"].tap()
    XCTAssertTrue(app.navigationBars["关于水杉"].waitForExistence(timeout: 5))
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
    XCTAssertFalse(app.buttons["aiSettingsLink"].exists)
    XCTAssertFalse(app.buttons["keyboardGuideLink"].exists)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Keyboard home"; shot.lifetime = .keepAlways; add(shot)
    openKeyboardSettingsIfNeeded(app)
    XCTAssertTrue(app.navigationBars["键盘设置"].waitForExistence(timeout: 5))
    app.buttons["aiSettingsLink"].tap()
    XCTAssertTrue(app.navigationBars["AI 设置"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    app.navigationBars.buttons.firstMatch.tap()
    for _ in 0..<3 {
      if app.buttons["homeThoughtfulReply"].isHittable { break }
      app.swipeUp()
    }
    app.buttons["homeThoughtfulReply"].tap()
    XCTAssertTrue(app.navigationBars["试用键盘"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["keyboardTryoutField"].exists)
    app.navigationBars.buttons.firstMatch.tap()
    for _ in 0..<3 {
      if app.buttons["inputSettingsLink"].isHittable { break }
      app.swipeDown()
    }
    app.buttons["inputSettingsLink"].tap()
    XCTAssertEqual(app.buttons["inputScheme_thoughtfulReply"].value as? String, "已选择")
    app.buttons["inputScheme_quanpin"].tap()
  }

  @MainActor
  private func openKeyboardSettingsIfNeeded(_ app: XCUIApplication) {
    let settings = app.buttons["keyboardSettingsLink"]
    guard settings.exists else { return }
    for _ in 0..<4 { if settings.isHittable { break }; app.swipeUp() }
    settings.tap()
  }

  @MainActor
  func testMainTabsKeepIndependentNavigation() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["键盘"].isSelected)
    app.buttons["inputSettingsLink"].tap()
    app.tabBars.buttons["社区"].tap()
    XCTAssertTrue(app.navigationBars["社区"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.tabBars.buttons.count, 4)
    app.tabBars.buttons["统计"].tap()
    XCTAssertTrue(app.navigationBars["打字统计"].waitForExistence(timeout: 5))
    app.tabBars.buttons["我的"].tap()
    XCTAssertTrue(app.buttons["accountLocalDesigns"].waitForExistence(timeout: 5))
    app.tabBars.buttons["键盘"].tap()
    XCTAssertTrue(app.navigationBars["输入设置"].exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Independent bottom tabs"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testSkinDiscoveryUsesCommunityTabAndReturnsToOrigin() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-communityPreview"]
    app.launch()
    app.tabBars.buttons["社区"].tap()
    app.buttons["communitySkinCard-20000000-0000-4000-8000-000000000001"].tap()
    XCTAssertTrue(app.navigationBars["皮肤详情"].waitForExistence(timeout: 5))
    app.tabBars.buttons["键盘"].tap()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["skinCommunityLink"].tap()
    XCTAssertTrue(app.tabBars.buttons["社区"].isSelected)
    XCTAssertTrue(app.navigationBars["社区"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.navigationBars["皮肤详情"].exists)
    app.buttons["communityCategory-2"].tap()
    app.tabBars.buttons["键盘"].tap()
    XCTAssertTrue(app.navigationBars["皮肤"].exists)
    app.buttons["skinCommunityLink"].tap()
    XCTAssertTrue(app.buttons["communitySkinCard-20000000-0000-4000-8000-000000000001"].exists)
    app.tabBars.buttons["键盘"].tap()
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["水杉输入法"].exists)
    app.tabBars.buttons["我的"].tap()
    let replay = app.buttons["replayOnboardingLink"]
    for _ in 0..<6 { if replay.isHittable { break }; app.swipeUp() }
    replay.tap()
    XCTAssertTrue(app.buttons["skipOnboardingButton"].waitForExistence(timeout: 5))
    app.buttons["skipOnboardingButton"].tap()
    XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["我的"].isSelected)
  }

  @MainActor
  func testChatLoginIsFocusedAndCancelReturnsToTryout() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["keyboardTryoutLink"].tap()
    let login = app.buttons["登录使用 AI"]
    XCTAssertTrue(login.waitForExistence(timeout: 8))
    login.tap()
    XCTAssertTrue(app.navigationBars["登录水杉"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["accountLocalDesigns"].exists)
    XCTAssertFalse(app.buttons["aboutSettingsLink"].exists)
    app.navigationBars["登录水杉"].buttons["取消"].tap()
    XCTAssertTrue(app.navigationBars["试用键盘"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["水杉输入法"].exists)
  }

  @MainActor
  func testCancellingPublicationPreservesCommunitySearch() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-communityPreview"]
    app.launch()
    app.tabBars.buttons["社区"].tap()
    app.buttons["communityCategory-2"].tap()
    let search = app.textFields.firstMatch
    search.tap(); search.typeText("reply\n")
    app.buttons["publishCommunityWork"].tap()
    XCTAssertTrue(app.navigationBars["发布回复"].waitForExistence(timeout: 5))
    app.buttons["取消"].tap()
    XCTAssertTrue(app.navigationBars["社区"].waitForExistence(timeout: 5))
    XCTAssertEqual(search.value as? String, "reply")
    XCTAssertTrue(app.buttons["communityCategory-2"].isSelected)
  }

  @MainActor
  func testBrandedLaunchScreenResource() {
    let app = XCUIApplication()
    app.launchArguments = ["-launchScreenPreview"]
    app.launch()
    XCTAssertTrue(app.staticTexts["水杉输入法"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["让输入更自然"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "System launch storyboard"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testWelcomeFlowSelectsSchemeAndCompletesOnce() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-onboarding-for-ui-tests"]
    app.launch()
    XCTAssertTrue(app.navigationBars["欢迎使用水杉"].waitForExistence(timeout: 5))
    let welcome = XCTAttachment(screenshot: app.screenshot())
    welcome.name = "Welcome onboarding"
    welcome.lifetime = .keepAlways
    add(welcome)
    app.buttons["nextOnboardingButton"].tap()
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].exists)
    app.buttons["nextOnboardingButton"].tap()
    app.buttons["welcomeScheme_nineKey"].tap()
    XCTAssertEqual(app.buttons["welcomeScheme_nineKey"].value as? String, "已选择")
    app.buttons["nextOnboardingButton"].tap()
    XCTAssertTrue(app.buttons["welcomeTryoutLink"].exists)
    app.buttons["finishOnboardingButton"].tap()
    XCTAssertTrue(app.tabBars.buttons["键盘"].waitForExistence(timeout: 5))
    app.terminate()
    app.launchArguments = []
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["键盘"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["nextOnboardingButton"].exists)
    app.buttons["inputSettingsLink"].tap()
    XCTAssertEqual(app.buttons["inputScheme_nineKey"].value as? String, "已选择")
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
    grid.lifetime = .keepAlways
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
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testVoiceResultIsExplicitlyTransferredAndClaimedOnce() {
    let app = XCUIApplication()
    let isolation = ["-voiceHandoffTestID", UUID().uuidString]
    app.launchArguments = isolation + ["-hasCompletedOnboarding", "YES", "-voiceResultFixture"]
    app.launch()
    openKeyboardSettingsIfNeeded(app)
    app.buttons["voiceSettingsLink"].tap()
    XCTAssertFalse(app.staticTexts["等待键盘插入"].exists)
    for _ in 0..<8 {
      if app.buttons["sendVoiceToKeyboard"].isHittable { break }
      app.swipeUp()
    }
    app.buttons["sendVoiceToKeyboard"].tap()
    XCTAssertTrue(app.staticTexts["等待键盘插入"].waitForExistence(timeout: 5))
    app.terminate()
    app.launchArguments = isolation + ["-keyboardVoicePreview"]
    app.launch()
    XCTAssertTrue(app.staticTexts["语音交接测试。"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Keyboard voice result preview"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    XCTAssertGreaterThanOrEqual(app.buttons["keyboardVoiceInsert"].frame.height, 44)
    app.buttons["keyboardVoiceInsert"].tap()
    XCTAssertTrue(app.staticTexts["插入验证：语音交接测试。"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["请在水杉 App 的“语音设置”中录音识别，点击“发送到键盘”，再返回这里插入。"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["keyboardVoiceInsert"].exists)
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
    screenshot.lifetime = .keepAlways
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
    screenshot.lifetime = .keepAlways
    add(screenshot)
    toggle.switches.firstMatch.tap()
    app.terminate()
    app.launch()
    openAI()
    XCTAssertEqual(toggle.value as? String, "0")
  }

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
    importScreen.lifetime = .keepAlways
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
    screenshot.lifetime = .keepAlways
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
    pending.lifetime = .keepAlways
    add(pending)
  }

  @MainActor
  func testCuratedSkinCollectionShowsFullPreviewsAndUndo() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    app.buttons["skinEditorTemplates"].tap()
    let gallery = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
    for (index, name) in ["苔庭晨雾", "竹影青瓷", "月下银砂", "黑金刻度", "樱雪糯米", "落日陶土", "冰川薄荷", "奶咖手账"].enumerated() {
      let template = app.buttons["skinTemplate_" + name]
      for _ in 0..<6 { if template.isHittable { break }; gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05, thenDragTo: gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))) }
      XCTAssertTrue(template.isHittable, name)
      template.tap()
      app.segmentedControls["skinEditorPreviewLayout"].buttons[index % 2 == 0 ? "26 键" : "9 键"].tap()
      XCTAssertTrue(app.buttons["undoSkinDesign"].isEnabled)
      let shot = XCTAttachment(screenshot: app.screenshot())
      shot.name = "Curated skin " + name; shot.lifetime = .keepAlways; add(shot)
    }
    for _ in 0..<8 {
      if !app.buttons["undoSkinDesign"].isEnabled { break }
      app.buttons["undoSkinDesign"].tap()
    }
    XCTAssertFalse(app.buttons["undoSkinDesign"].isEnabled)
  }

  @MainActor
  func testCustomSkinDesignPersistsAndApplies() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    func openEditor() {
      app.buttons["skinSettingsLink"].tap()
      app.buttons["customSkinEditorLink"].tap()
      app.buttons["skinEditorTab_按键"].tap()
    }
    app.launch()
    openEditor()
    let radius = app.sliders["customSkinCornerRadius"]
    func revealRadius() {
      let controls = app.descendants(matching: .any)["skinEditorControls"].firstMatch
      for _ in 0..<12 {
        let top = app.buttons["skinEditorTab_按键"].frame.maxY + 28
        let bottom = app.buttons["applyCustomSkin"].frame.minY - 28
        if radius.exists && radius.isHittable && radius.frame.minY > top && radius.frame.maxY < bottom { return }
        let down = radius.exists && radius.frame.midY < top
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
          .press(forDuration: 0.05, thenDragTo: controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.3)))
      }
    }
    revealRadius()
    XCTAssertTrue(radius.isHittable)
    // XCTest's normalized drag is approximate, and Slider.value can be a
    // percentage on one runtime and a domain value on another. Verify the
    // actual displayed setting changes, then survives a process restart.
    let radiusLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "圆角 · ")).firstMatch
    XCTAssertTrue(radiusLabel.exists)
    let before = radiusLabel.label
    let initial = Int(before.replacingOccurrences(of: "圆角 · ", with: "")) ?? 0
    radius.adjust(toNormalizedSliderPosition: initial < 10 ? 0.9 : 0.1)
    let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: radiusLabel)
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    let edited = radiusLabel.label
    let editedRadius = Int(edited.replacingOccurrences(of: "圆角 · ", with: ""))
    XCTAssertNotNil(editedRadius)
    XCTAssertTrue((0...20).contains(editedRadius ?? -1))
    app.terminate()
    app.launch()
    openEditor()
    revealRadius()
    XCTAssertEqual(radiusLabel.label, edited, "The edited corner radius must survive restarting the app")
    for _ in 0..<5 {
      if app.buttons["applyCustomSkin"].isHittable { break }
      app.descendants(matching: .any)["skinEditorControls"].firstMatch.swipeDown()
    }
    app.buttons["applyCustomSkin"].tap()
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Custom skin editor"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertTrue(app.buttons["applyCustomSkin"].label.contains("正在使用"))
    // Reset lives in the editor tools menu, independent of the selected category.
    app.buttons["skinEditorTools"].tap()
    app.buttons["重置我的皮肤"].tap()
    app.buttons["重置"].tap()
    app.buttons["skinEditorTab_按键"].tap()
    revealRadius()
    XCTAssertEqual(radiusLabel.label, "圆角 · 8")
  }

  @MainActor
  func testCustomSkinTemplatesLibraryAndUndo() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    app.buttons["skinEditorTemplates"].tap()
    app.buttons["skinTemplate_紫夜星光"].tap()
    XCTAssertTrue(app.buttons["undoSkinDesign"].isEnabled)
    app.buttons["saveCustomSkin"].tap()
    let name = "夜色测试-" + String(UUID().uuidString.prefix(4))
    let field = app.textFields["customSkinName"]
    field.tap()
    if let current = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
    field.typeText(name)
    app.buttons["confirmSaveCustomSkin"].tap()
    XCTAssertTrue(app.buttons["savedSkin_" + name].waitForExistence(timeout: 5))
    app.buttons["skinEditorTools"].tap(); app.buttons["设计模板"].tap()
    app.buttons["skinTemplate_水杉留白"].tap()
    app.buttons["undoSkinDesign"].tap()
    app.buttons["skinEditorTab_背景"].tap()
    for _ in 0..<12 {
      if app.switches["customSkinGradient"].exists && app.switches["customSkinGradient"].isHittable { break }
      let controls = app.collectionViews.firstMatch
      controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
    }
    XCTAssertEqual(app.switches["customSkinGradient"].value as? String, "1")
    XCTAssertTrue(app.buttons["skinEditorTab_背景"].exists)
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Skin studio gradient and fixed preview"
    image.lifetime = .keepAlways
    add(image)
    app.terminate()
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    app.buttons["skinEditorTools"].tap(); app.buttons["我的皮肤"].tap()
    XCTAssertTrue(app.buttons["savedSkin_" + name].exists)
    app.buttons["skinEditorTools"].tap(); app.buttons["设计模板"].tap()
    app.buttons["skinTemplate_水杉留白"].tap()
    app.buttons["skinEditorTools"].tap(); app.buttons["我的皮肤"].tap()
    app.buttons["管理" + name].tap()
    app.buttons["用当前设计更新"].tap()
    app.buttons["更新已保存的皮肤"].tap()
    app.buttons["skinEditorTools"].tap(); app.buttons["设计模板"].tap()
    app.buttons["skinTemplate_紫夜星光"].tap()
    app.buttons["skinEditorTools"].tap(); app.buttons["我的皮肤"].tap()
    app.buttons["savedSkin_" + name].tap()
    app.buttons["skinEditorTab_背景"].tap()
    for _ in 0..<12 {
      if app.switches["customSkinGradient"].exists && app.switches["customSkinGradient"].isHittable { break }
      let controls = app.collectionViews.firstMatch
      controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
    }
    XCTAssertEqual(app.switches["customSkinGradient"].value as? String, "0")
    app.buttons["skinEditorTools"].tap(); app.buttons["我的皮肤"].tap()
    app.buttons["管理" + name].tap()
    app.buttons["删除"].tap()
    app.buttons["删除"].tap()
    XCTAssertFalse(app.buttons["savedSkin_" + name].exists)
  }

  @MainActor
  func testSkinEditorKeepsFullPreviewBelowMaterialGrid() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    let preview = app.otherElements["fullKeyboardSkinPreview"]
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["skinBackgroundPreset_0"].isHittable)
    XCTAssertTrue(app.buttons["saveCustomSkin"].isHittable)
    let frame = preview.frame
    XCTAssertGreaterThan(frame.width, app.frame.width * 0.9)
    XCTAssertGreaterThan(frame.minY, app.buttons["skinEditorTab_背景"].frame.maxY)
    app.buttons["skinBackgroundPreset_5"].tap()
    XCTAssertEqual(preview.frame.minY, frame.minY, accuracy: 1)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Reference skin editor with pinned keyboard"
    attachment.lifetime = .keepAlways
    add(attachment)
    for tab in ["按键", "文本", "音效", "背景"] {
      app.buttons["skinEditorTab_" + tab].tap()
      XCTAssertEqual(preview.frame.minY, frame.minY, accuracy: 1)
      XCTAssertTrue(preview.isHittable)
    }
    app.segmentedControls["skinEditorPreviewLayout"].buttons["9 键"].tap()
    XCTAssertTrue(preview.label.contains("9 键"))
    XCTAssertEqual(preview.frame.height, frame.height, accuracy: 1)
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
      failure.lifetime = .keepAlways
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
    attachment.lifetime = .keepAlways
    add(attachment)
    picker.buttons[previous].tap()
    if !initiallyEnabled { toggle.switches.firstMatch.tap() }
  }

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
  func testStatisticsChartsAndPeriodSelection() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.tabBars.buttons["统计"].tap()
    let period = app.segmentedControls["statisticsPeriod"]
    XCTAssertTrue(period.waitForExistence(timeout: 5))
    period.buttons["30 天"].tap()
    period.buttons["累计"].tap()
    period.buttons["7 天"].tap()
    let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "statisticsDay_")).firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 3), app.debugDescription)
    day.tap()
    XCTAssertTrue(app.buttons["返回整个时间范围"].exists)
    app.buttons["返回整个时间范围"].tap()
    let top = XCTAttachment(screenshot: app.screenshot())
    top.name = "统计趋势与字符分布"
    top.lifetime = .keepAlways
    add(top)
    app.swipeUp()
    app.swipeUp()
    let detail = XCTAttachment(screenshot: app.screenshot())
    detail.name = "统计语言与输入方案"
    detail.lifetime = .keepAlways
    add(detail)
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
    openKeyboardSettingsIfNeeded(app)
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
    openKeyboardSettingsIfNeeded(app)
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
    image.lifetime = .keepAlways
    add(image)
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
      if app.buttons["desktopDownloadLink"].isHittable { break }
      app.swipeUp()
    }
    app.buttons["desktopDownloadLink"].tap()
    for platform in ["macOS", "Windows", "Linux"] {
      app.segmentedControls["desktopPlatformPicker"].buttons[platform].tap()
      XCTAssertTrue(app.staticTexts[platform + " 安装指南"].exists)
      XCTAssertTrue(app.buttons["desktopReleaseLink"].exists)
    }
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Desktop download guide"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["aboutSettingsLink"].tap()
    XCTAssertTrue(app.staticTexts["aboutAppVersion"].exists)
    XCTAssertTrue(app.navigationBars["关于水杉"].exists)
  }

  @MainActor
  func testInputSchemeVisibilityPersistsAndFallsBack() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["inputSettingsLink"].tap()
    let full = app.switches["enabledInputScheme_quanpin"]
    let nine = app.switches["enabledInputScheme_nineKey"]
    if full.value as? String == "0" { full.tap() }
    if nine.value as? String == "0" { nine.tap() }
    app.buttons["inputScheme_nineKey"].tap()
    nine.tap()
    XCTAssertEqual(nine.value as? String, "0")
    XCTAssertEqual(app.buttons["inputScheme_quanpin"].value as? String, "已选择")
    app.terminate()
    app.launch()
    app.buttons["inputSettingsLink"].tap()
    XCTAssertEqual(nine.value as? String, "0")
    XCTAssertFalse(app.buttons["inputScheme_nineKey"].isEnabled)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Input scheme visibility settings"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    nine.tap()
    XCTAssertTrue(app.buttons["inputScheme_nineKey"].isEnabled)
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

    XCTAssertTrue(app.staticTexts["水杉输入法"].waitForExistence(timeout: 10))

    XCTAssertTrue(app.navigationBars["水杉输入法"].waitForExistence(timeout: 5))
    app.buttons["inputSettingsLink"].tap()
    XCTAssertTrue(app.buttons["inputScheme_quanpin"].exists)
    XCTAssertTrue(app.buttons["inputScheme_shuangpin"].exists)
    let nineKey = app.buttons["inputScheme_nineKey"]
    XCTAssertTrue(nineKey.exists)
    nineKey.tap()
    XCTAssertEqual(nineKey.value as? String, "已选择")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.navigationBars["水杉输入法"].waitForExistence(timeout: 5))
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
      ("aiSettingsLink", "AI 设置"), ("voiceSettingsLink", "语音设置"),
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
    if !app.buttons["keyboardTryoutLink"].exists { app.navigationBars.buttons.firstMatch.tap() }
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
    XCTAssertFalse(app.buttons["keyboardGuideLink"].exists)
    openKeyboardSettingsIfNeeded(app)
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].exists)
  }
}
