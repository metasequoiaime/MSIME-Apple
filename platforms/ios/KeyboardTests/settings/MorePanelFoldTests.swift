import UIKit
import XCTest

/// Where the "更多" panel's first screen ends, and what is still on it.
///
/// Upstream moved the local input modes one level in because the last of them sat 360pt down a
/// 292pt panel "where nothing said they were there". That reason is about the *sign*, not the
/// fold: a scrolling panel is fine as long as something above the fold says there is more. This
/// holds the layout to that reading — the tools and the group heading that names the switches all
/// stay on the first screen, and the switches themselves are reachable by scrolling.
@MainActor
final class MorePanelFoldTests: XCTestCase {
  func testTheFirstScreenCarriesTheToolsAndSaysTheSwitchesAreThere() throws {
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(
      x: 0, y: 0, width: 390, height: 260 + KeyboardViewController.stripExtraHeight)
    controller.view.layoutIfNeeded()

    let more = try button("moreShortcut", in: controller)
    more.sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()

    let panel = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardMorePicker" })
    let fold = panel.bounds.height

    // Every tool entry is on the first screen: a tool nobody scrolls to is a tool nobody finds.
    for title in ["表情", "剪贴板历史", "AI 润色", "语音结果", "本地输入"] {
      let card = try button("moreCard-" + title, in: controller)
      XCTAssertLessThanOrEqual(
        card.convert(card.bounds, to: panel).maxY, fold,
        "\(title) was pushed off the first screen")
    }

    // And the heading that names the group below them is on it too. This is the whole reason the
    // switches are allowed to sit past the fold, so it is the thing to hold: without it they are
    // exactly the stranded list upstream moved out.
    let heading = try XCTUnwrap(
      descendants(panel).compactMap { $0 as? UILabel }.first { $0.text == "设置" },
      "the 设置 heading is missing, so nothing says the switches are below")
    XCTAssertLessThanOrEqual(
      heading.convert(heading.bounds, to: panel).maxY, fold,
      "the 设置 heading is itself below the fold, which says nothing to anyone")

    // The switches are inside the scrollable content, so scrolling reaches all of them.
    let scroll = try XCTUnwrap(descendants(panel).compactMap { $0 as? UIScrollView }.first)
    for title in ["繁体输出", "按键音", "按键振动", "全角输入", "振动强度"] {
      let card = try button("moreCard-" + title, in: controller)
      let frame = card.convert(card.bounds, to: scroll)
      XCTAssertGreaterThanOrEqual(frame.minY, -0.5, "\(title) is above the scrollable content")
      XCTAssertLessThanOrEqual(
        frame.maxY, scroll.contentSize.height + 0.5,
        "\(title) is below the scrollable content, so nothing can scroll to it")
    }
  }

  /// The Windows Ctrl+Shift+Alt+C chord has no key to press on iOS, so the panel carries it; the card closes the panel and says it worked.
  func testTheClearCacheCardClearsAndSaysSo() throws {
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(
      x: 0, y: 0, width: 390, height: 260 + KeyboardViewController.stripExtraHeight)
    controller.view.layoutIfNeeded()

    try button("moreShortcut", in: controller).sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()
    try button("moreCard-清除候选缓存", in: controller).sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()

    XCTAssertFalse(
      descendants(controller.view).contains { $0.accessibilityIdentifier == "keyboardMorePicker" },
      "the panel stayed open over the message")
    let label = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "diagnosticLabel" } as? UILabel)
    XCTAssertEqual(label.text, "已清除候选缓存")
    XCTAssertFalse(label.isHidden)
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func button(_ identifier: String, in controller: KeyboardViewController) throws -> UIButton {
    try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == identifier } as? UIButton,
      "No button with accessibility identifier \(identifier).")
  }
}
