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

  /// 把元素滚进可见范围再用它。
  ///
  /// 列表是惰性渲染的:屏幕外的行不在无障碍层级里,`exists` 同样查不到,所以「找不到」既可能是它不存在,也可能是它还没被滚出来。CI 跑的是 iPhone 17 Pro,比开发机上常用的机型矮一截 —— 本地过、CI 红的差别往往只是这一屏的高度。
  ///
  /// 滚的是页面自己的滚动容器而不是整块屏幕:有些页面下半屏是钉住的预览,对着它滑动什么都不会发生。
  @MainActor
  @discardableResult
  func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) -> Bool {
    // 两个方向都试:要找的行既可能在下面,也可能在上面 —— 点过某一行之后列表往往已经不在顶上了,只往一个方向滚会越滚越远。
    for direction in [true, false] {
      for _ in 0..<attempts {
        if element.exists && element.isHittable { return true }
        let scrollers = [app.collectionViews.firstMatch, app.tables.firstMatch, app.scrollViews.firstMatch]
        let scroller = scrollers.first(where: { $0.exists }) ?? app
        if direction { scroller.swipeUp() } else { scroller.swipeDown() }
      }
    }
    return element.exists && element.isHittable
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
