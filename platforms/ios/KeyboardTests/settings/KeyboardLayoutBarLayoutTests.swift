import XCTest
import UIKit

/// 调整面板那条工具条上,谁都不许压住谁。
///
/// 它原先只有一行内容。高度控件加进去之后就是两行,而条高没跟着变 —— 这类错误不会让任何断言变红,
/// 只会在屏幕上糊成一团,所以这里直接量框。
final class KeyboardLayoutBarLayoutTests: XCTestCase {
  private var previousHeight: Double = 0

  override func setUp() {
    super.setUp()
    previousHeight = KeyboardLayoutPreference.heightAdjustment
  }

  override func tearDown() {
    KeyboardLayoutPreference.heightAdjustment = previousHeight
    super.tearDown()
  }

  func testNothingOnTheBarOverlapsAtPhoneWidth() throws {
    let controller = try openLayoutPicker(width: 390)
    let picker = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardLayoutPicker" })

    let named = ["keyboardHeightGrip", "layoutAdjustHint", "resetKeyboardSettings",
                 "voiceShortcutSwitch", "closeLayoutPicker"]
    let frames = try named.map { identifier -> (String, CGRect) in
      let view = try XCTUnwrap(
        descendants(picker).first { $0.accessibilityIdentifier == identifier },
        "\(identifier) 不在面板上")
      return (identifier, view.convert(view.bounds, to: picker))
    }

    for (leftName, left) in frames {
      for (rightName, right) in frames where leftName < rightName {
        XCTAssertFalse(left.intersects(right),
                       "\(leftName) 和 \(rightName) 压在一起了:\(left) / \(right)")
      }
    }
  }

  /// 竖着也要装得下 —— 控件可以不重叠却一起溢出条外。
  func testTheBarIsTallEnoughForEverythingOnIt() throws {
    let controller = try openLayoutPicker(width: 390)
    let picker = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardLayoutPicker" })
    let content = ["keyboardHeightGrip", "layoutAdjustHint"].map { identifier in
      let view = descendants(picker).first { $0.accessibilityIdentifier == identifier }!
      return view.convert(view.bounds, to: picker)
    }
    // 条本身没有标识,但它是面板里唯一一个圆角 10 的视图。
    let bar = try XCTUnwrap(descendants(picker).first { $0.layer.cornerRadius == 10 })
    let barFrame = bar.convert(bar.bounds, to: picker)

    for frame in content {
      XCTAssertTrue(barFrame.insetBy(dx: 0, dy: -0.5).contains(frame),
                    "有内容超出了工具条:\(frame) 不在 \(barFrame) 里")
    }
  }

  private func openLayoutPicker(width: CGFloat) throws -> KeyboardViewController {
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 292)
    let shortcut = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "layoutShortcut" }
        as? UIButton)
    shortcut.sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()
    return controller
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}
