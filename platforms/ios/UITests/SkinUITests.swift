import XCTest

final class SkinUITests: KeyboardInterfaceTests {
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
    deck.name = "AI 皮肤抽卡入口"; deck.lifetime = .deleteOnSuccess; add(deck)
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
    shot.name = "AI 生成皮肤的发布预览"; shot.lifetime = .deleteOnSuccess; add(shot)
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
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Community word packs"; shot.lifetime = .deleteOnSuccess; add(shot)
    first.tap()
    XCTAssertTrue(app.buttons["communityImportLocal"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["communityCategory-2"].tap()
    app.buttons["communityResource-10000000-0000-4000-8000-000000000003"].tap()
    XCTAssertTrue(app.buttons["添加到回复键盘"].waitForExistence(timeout: 5))
    let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Community reply preview"; detail.lifetime = .deleteOnSuccess; add(detail)
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
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Skin trial with undo"; shot.lifetime = .deleteOnSuccess; add(shot)
    app.buttons["restoreTrialSkin"].tap()
    XCTAssertTrue(app.navigationBars["皮肤详情"].waitForExistence(timeout: 5))
    app.tabBars.buttons["我的"].tap()
    for _ in 0..<5 {
      if app.buttons["aboutSettingsLink"].isHittable { break }
      app.swipeUp()
    }
    app.buttons["aboutSettingsLink"].tap()
    XCTAssertTrue(app.navigationBars["关于水杉"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["desktopDownloadLink"].exists)
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
    XCTAssertTrue(app.buttons["communityCategory-0"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.navigationBars["皮肤详情"].exists)
    app.buttons["communityCategory-2"].tap()
    app.tabBars.buttons["键盘"].tap()
    XCTAssertTrue(app.navigationBars["皮肤"].exists)
    app.buttons["skinCommunityLink"].tap()
    XCTAssertTrue(app.buttons["communitySkinCard-20000000-0000-4000-8000-000000000001"].exists)
    app.tabBars.buttons["键盘"].tap()
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["skinSettingsLink"].exists)
    app.tabBars.buttons["我的"].tap()
    let replay = app.buttons["replayOnboardingLink"]
    for _ in 0..<6 { if replay.isHittable { break }; app.swipeUp() }
    replay.tap()
    XCTAssertTrue(app.buttons["skipOnboardingButton"].waitForExistence(timeout: 5))
    app.buttons["skipOnboardingButton"].tap()
    XCTAssertTrue(app.buttons["accountProfileCard"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["我的"].isSelected)
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
    XCTAssertTrue(app.buttons["communityCategory-0"].waitForExistence(timeout: 5))
    XCTAssertEqual(search.value as? String, "reply")
    XCTAssertTrue(app.buttons["communityCategory-2"].isSelected)
  }

  @MainActor
  func testCancelledSkinGenerationDoesNotShowLateResult() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES", "-aiSkinPreview", "-skinGenerationSlowFixture"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    app.buttons["openAISkinDesigner"].tap()
    XCTAssertTrue(app.buttons["generateAISkins"].waitForExistence(timeout: 5))
    app.buttons["generateAISkins"].tap()
    XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3))
    app.buttons["取消"].tap()
    let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.buttons["saveAISkin_AI 测试 1"])
    late.isInverted = true
    XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 6), .completed)
    XCTAssertTrue(app.buttons["generateAISkins"].isEnabled)
  }

  @MainActor
  func testCuratedSkinCollectionShowsFullPreviewsAndUndo() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    app.buttons["skinEditorTab_模板"].tap()
    let gallery = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
    // Three of the eight curated designs. Walking all of them cost four minutes and asserted the
    // same three things each time; what every design contains is checked in KeyboardSkinTests,
    // which reads them directly instead of driving a Simulator. The first is above the fold and the
    // last two need scrolling, so the gallery is still exercised in both states.
    for (index, name) in ["苔庭晨雾", "冰川薄荷", "奶咖手账"].enumerated() {
      let template = app.buttons["skinTemplate_" + name]
      for _ in 0..<6 { if template.isHittable { break }; gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05, thenDragTo: gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))) }
      XCTAssertTrue(template.isHittable, name)
      template.tap()
      app.segmentedControls["skinEditorPreviewLayout"].buttons[index % 2 == 0 ? "26 键" : "9 键"].tap()
      XCTAssertTrue(app.buttons["undoSkinDesign"].isEnabled)
    }
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Curated skin gallery"; shot.lifetime = .deleteOnSuccess; add(shot)
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
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
    XCTAssertTrue(app.buttons["applyCustomSkin"].label.contains("正在使用"))
    // Reset sits with the other ways to replace a whole design, on the 模板 tab, below the gallery.
    app.buttons["skinEditorTab_模板"].tap()
    let reset = app.buttons["resetCustomSkin"]
    for _ in 0..<6 {
      if reset.isHittable { break }
      app.swipeUp()
    }
    reset.tap()
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
    app.buttons["skinEditorTab_模板"].tap()
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
    app.buttons["skinEditorTab_模板"].tap()
    app.buttons["skinTemplate_水杉留白"].tap()
    app.buttons["undoSkinDesign"].tap()
    // The editor's own gradient state was asserted here by scrolling the control into view a second
    // time. What a design renders is covered by KeyboardSkinTests without a Simulator; the reload
    // below still reads the switch, which is the part this case is about.
    app.terminate()
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    app.buttons["skinEditorTab_我的"].tap()
    XCTAssertTrue(app.buttons["savedSkin_" + name].exists)
    app.buttons["skinEditorTab_模板"].tap()
    app.buttons["skinTemplate_水杉留白"].tap()
    app.buttons["skinEditorTab_我的"].tap()
    app.buttons["管理" + name].tap()
    app.buttons["用当前设计更新"].tap()
    app.buttons["更新已保存的皮肤"].tap()
    app.buttons["skinEditorTab_模板"].tap()
    app.buttons["skinTemplate_紫夜星光"].tap()
    app.buttons["skinEditorTab_我的"].tap()
    app.buttons["savedSkin_" + name].tap()
    app.buttons["skinEditorTab_背景"].tap()
    for _ in 0..<12 {
      if app.switches["customSkinGradient"].exists && app.switches["customSkinGradient"].isHittable { break }
      let controls = app.collectionViews.firstMatch
      controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
    }
    XCTAssertEqual(app.switches["customSkinGradient"].value as? String, "0")
    app.buttons["skinEditorTab_我的"].tap()
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
    XCTAssertEqual(frame.height / frame.width, 260.0 / 390.0, accuracy: 0.01)
    XCTAssertGreaterThan(frame.width, app.frame.width * 0.9)
    XCTAssertGreaterThan(frame.minY, app.buttons["skinEditorTab_背景"].frame.maxY)
    app.buttons["skinBackgroundPreset_5"].tap()
    XCTAssertEqual(preview.frame.minY, frame.minY, accuracy: 1)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Reference skin editor with pinned keyboard"
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
    for tab in ["按键", "文本", "模板", "我的", "背景"] {
      app.buttons["skinEditorTab_" + tab].tap()
      XCTAssertEqual(preview.frame.minY, frame.minY, accuracy: 1)
      XCTAssertTrue(preview.isHittable)
    }
    app.segmentedControls["skinEditorPreviewLayout"].buttons["9 键"].tap()
    XCTAssertTrue(preview.label.contains("9 键"))
    XCTAssertEqual(preview.frame.height, frame.height, accuracy: 1)
  }

  @MainActor
  func testSkinEditorLandscapePreservesFullKeyboardAspectRatio() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.buttons["skinSettingsLink"].tap()
    app.buttons["customSkinEditorLink"].tap()
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      let frame = app.windows.firstMatch.frame
      return frame.width > frame.height
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 15), .completed)
    let preview = app.otherElements["fullKeyboardSkinPreview"]
    for title in ["26 键", "9 键"] {
      app.segmentedControls["skinEditorPreviewLayout"].buttons[title].tap()
      XCTAssertEqual(preview.frame.height / preview.frame.width, 260.0 / 390.0, accuracy: 0.01)
      XCTAssertLessThanOrEqual(preview.frame.maxY, app.frame.maxY)
      XCTAssertTrue(app.buttons["applyCustomSkin"].isHittable)
    }
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Landscape proportional preview"; shot.lifetime = .deleteOnSuccess; add(shot)
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
    light.lifetime = .deleteOnSuccess
    add(light)
    layout.buttons["9 键"].tap()
    app.switches["skinPreviewDark"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertEqual(app.switches["skinPreviewDark"].value as? String, "1")
    XCTAssertTrue(preview.label.contains("9 键"))
    let dark = XCTAttachment(screenshot: app.screenshot())
    dark.name = "完整 9 键深色皮肤预览"
    dark.lifetime = .deleteOnSuccess
    add(dark)
  }
}
