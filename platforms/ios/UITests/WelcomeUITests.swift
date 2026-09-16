import XCTest

final class WelcomeUITests: KeyboardInterfaceTests {
  @MainActor
  func testAppIconsAreAvailableFromMyTabAndPersist() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    func openIcons() {
      app.tabBars.buttons["我的"].tap()
      let loginAlert = app.alerts["账号与登录"]
      if loginAlert.waitForExistence(timeout: 5) { loginAlert.buttons["好"].tap() }
      app.buttons["accountAppIcon"].tap()
      XCTAssertTrue(app.buttons["appIcon_classic"].waitForExistence(timeout: 5))
    }
    openIcons()
    for style in ["classic", "forest", "sky", "dusk", "vermilion"] {
      XCTAssertTrue(app.buttons["appIcon_\(style)"].exists)
    }
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "App icon gallery"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    func select(_ style: String) {
      let button = app.buttons["appIcon_\(style)"]
      if button.value as? String == "使用中" { return }
      if !button.isHittable { app.swipeUp() }
      button.tap()
      // iOS 26 exposes its icon notification in the host app's hierarchy.
      let confirmation = app.buttons.matching(NSPredicate(format: "label IN %@", ["OK", "好"])).firstMatch
      if confirmation.waitForExistence(timeout: 10) {
        XCTAssertFalse(app.alerts["暂时无法更换图标"].exists, app.alerts.debugDescription)
        confirmation.tap()
      } else if springboard.alerts.firstMatch.exists {
        springboard.alerts.buttons.firstMatch.tap()
      }
      let selected = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == %@", "使用中"), object: button)
      XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
    }
    // One change only. A Simulator applies the first alternate icon it is given and then refuses
    // every later request, relaunching the app included, so asking for a second one would test the
    // Simulator rather than the app. A fresh CI runner always exercises a real change; a Simulator
    // reused locally may already hold this icon, in which case select returns and the assertion
    // below still describes what the system reports.
    select("sky")
    let selectedScreenshot = XCTAttachment(screenshot: app.screenshot())
    selectedScreenshot.name = "App icon selected"
    selectedScreenshot.lifetime = .deleteOnSuccess
    add(selectedScreenshot)
    app.terminate()
    app.launch()
    openIcons()
    XCTAssertEqual(app.buttons["appIcon_sky"].value as? String, "使用中")
  }

  @MainActor
  func testAccountEntryExplainsExplicitDataSharing() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    let account = app.tabBars.buttons["我的"]
    XCTAssertTrue(account.waitForExistence(timeout: 5))
    account.tap()
    XCTAssertTrue(app.buttons["accountProfileCard"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["accountAppIcon"].exists)
  }

  @MainActor
  func testMainTabsKeepIndependentNavigation() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["键盘"].isSelected)
    app.buttons["inputSettingsLink"].tap()
    app.tabBars.buttons["社区"].tap()
    XCTAssertTrue(app.buttons["communityCategory-0"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.tabBars.buttons.count, 4)
    app.tabBars.buttons["统计"].tap()
    XCTAssertTrue(app.segmentedControls["statisticsTab"].waitForExistence(timeout: 5))
    app.tabBars.buttons["我的"].tap()
    XCTAssertTrue(app.buttons["accountAppIcon"].waitForExistence(timeout: 5))
    app.tabBars.buttons["键盘"].tap()
    XCTAssertTrue(app.navigationBars["输入设置"].exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Independent bottom tabs"
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
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
    XCTAssertFalse(app.buttons["accountAppIcon"].exists)
    XCTAssertFalse(app.buttons["aboutSettingsLink"].exists)
    app.navigationBars["登录水杉"].buttons["取消"].tap()
    XCTAssertTrue(app.navigationBars["试用键盘"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["inputSettingsLink"].exists)
  }

  @MainActor
  func testBrandedLaunchScreenResource() {
    let app = XCUIApplication()
    app.launchArguments = ["-launchScreenPreview"]
    app.launch()
    XCTAssertTrue(app.staticTexts["让输入，更像你"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["让输入更自然"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "System launch storyboard"
    screenshot.lifetime = .deleteOnSuccess
    add(screenshot)
  }

  @MainActor
  func testWelcomePrimaryButtonsRespondAcrossTheirVisibleBackground() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-onboarding-for-ui-tests"]
    app.launch()
    let next = app.buttons["nextOnboardingButton"]
    XCTAssertTrue(next.waitForExistence(timeout: 5))
    // Tap the colored background, well outside the centered text.
    next.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
    let settings = app.buttons["openKeyboardSettingsButton"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    let systemSettings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    XCTAssertTrue(systemSettings.wait(for: .runningForeground, timeout: 5))
    app.activate()
    next.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["welcomeScheme_nineKey"].waitForExistence(timeout: 5))
    next.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
    let finish = app.buttons["finishOnboardingButton"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    finish.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
    XCTAssertTrue(app.tabBars.buttons["键盘"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testReplayedWelcomeStartRespondsOutsideText() {
    let app = XCUIApplication()
    app.launchArguments = ["-hasCompletedOnboarding", "YES"]
    app.launch()
    app.tabBars.buttons["我的"].tap()
    let loginAlert = app.alerts["账号与登录"]
    if loginAlert.waitForExistence(timeout: 5) { loginAlert.buttons["好"].tap() }
    let replay = app.buttons["replayOnboardingLink"]
    for _ in 0..<8 {
      if replay.isHittable { break }
      app.swipeUp()
    }
    replay.tap()
    let next = app.buttons["nextOnboardingButton"]
    XCTAssertTrue(next.waitForExistence(timeout: 5))
    next.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].waitForExistence(timeout: 5))
    app.buttons["skipOnboardingButton"].tap()
    XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testWelcomeFlowSelectsSchemeAndCompletesOnce() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-onboarding-for-ui-tests"]
    app.launch()
    XCTAssertTrue(app.navigationBars["欢迎使用水杉"].waitForExistence(timeout: 5))
    let welcome = XCTAttachment(screenshot: app.screenshot())
    welcome.name = "Welcome onboarding"
    welcome.lifetime = .deleteOnSuccess
    add(welcome)
    app.buttons["nextOnboardingButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["openKeyboardSettingsButton"].waitForExistence(timeout: 5))
    app.buttons["nextOnboardingButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    app.buttons["welcomeScheme_nineKey"].tap()
    XCTAssertEqual(app.buttons["welcomeScheme_nineKey"].value as? String, "已选择")
    app.buttons["nextOnboardingButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["welcomeTryoutLink"].exists)
    app.buttons["finishOnboardingButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
    XCTAssertTrue(app.tabBars.buttons["键盘"].waitForExistence(timeout: 5))
    app.terminate()
    app.launchArguments = []
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["键盘"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["nextOnboardingButton"].exists)
    app.buttons["inputSettingsLink"].tap()
    XCTAssertEqual(app.buttons["inputScheme_nineKey"].value as? String, "已选择")
  }
}
