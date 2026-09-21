import XCTest
import UIKit

/// 键盘高度那个控件的两条契约。
///
/// 它原先是一根 46×5pt 的把手:当前值只在拖动过程中出现,而整个 −12…48 的范围只有 60pt 的手指行程,
/// 没有任何精调手段。这两条正是当时缺的那两件事,所以钉在这里。
final class KeyboardHeightControlTests: XCTestCase {
  private var previousHeight: Double = 0

  override func setUp() {
    super.setUp()
    previousHeight = KeyboardLayoutPreference.heightAdjustment
  }

  override func tearDown() {
    KeyboardLayoutPreference.heightAdjustment = previousHeight
    super.tearDown()
  }

  /// 打开面板、还没碰任何东西时,当前高度就已经写在上面。
  func testCurrentHeightIsReadableBeforeTouchingAnything() throws {
    KeyboardLayoutPreference.heightAdjustment = 12
    let controller = try openLayoutPicker()

    let value = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardHeightValue" }
        as? UILabel)
    XCTAssertEqual(value.text, "高度 +12")
  }

  /// 高度靠拖,而拖动在单测里没法模拟;可调节动作走的是同一个入口和同一档步长,所以用它来守这条路。
  func testAdjustingMovesOneNotchAndResizesTheKeyboard() throws {
    KeyboardLayoutPreference.heightAdjustment = 0
    let controller = try openLayoutPicker()
    controller.view.layoutIfNeeded()
    let start = try XCTUnwrap(
      controller.view.constraints.first { $0.identifier == "keyboardHeight" }).constant

    let control = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardHeightGrip" })
    for _ in 0..<3 { control.accessibilityIncrement() }
    controller.view.layoutIfNeeded()

    XCTAssertEqual(KeyboardLayoutPreference.heightAdjustment, 6)
    XCTAssertEqual(
      try XCTUnwrap(controller.view.constraints.first { $0.identifier == "keyboardHeight" }).constant,
      start + 6, accuracy: 0.5)

    control.accessibilityDecrement()
    XCTAssertEqual(KeyboardLayoutPreference.heightAdjustment, 4)
  }

  /// 下界之外不再动。范围两端靠 clamp 守着,而调用方不知道边界在哪。
  func testAdjustingStopsAtTheLowerBound() throws {
    KeyboardLayoutPreference.heightAdjustment = -12
    let controller = try openLayoutPicker()
    let control = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardHeightGrip" })

    for _ in 0..<3 { control.accessibilityDecrement() }

    XCTAssertEqual(KeyboardLayoutPreference.heightAdjustment, -12)
  }

  private func openLayoutPicker() throws -> KeyboardViewController {
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 440, height: 292)
    let shortcut = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "layoutShortcut" }
        as? UIButton)
    shortcut.sendActions(for: .primaryActionTriggered)
    return controller
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}
