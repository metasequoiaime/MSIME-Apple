import XCTest
import UIKit

@MainActor
final class NineKeyKeyboardTests: XCTestCase {
  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func button(_ identifier: String, in controller: KeyboardViewController) throws -> UIButton {
    try XCTUnwrap(descendants(controller.view).first {
      $0.accessibilityIdentifier == identifier
    } as? UIButton)
  }

  func testShortcutsYieldToCandidatesWithoutMovingKeys() throws {
    let previousScheme = InputSchemePreference.scheme
    let previousScript = ChineseOutputPreference.usesTraditional
    InputSchemePreference.scheme = .nineKey
    ChineseOutputPreference.usesTraditional = false
    defer {
      InputSchemePreference.scheme = previousScheme
      ChineseOutputPreference.usesTraditional = previousScript
    }
    for width in [320.0, 414.0] {
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      controller.view.layoutIfNeeded()
      let toolbar = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardShortcutBar" })
      XCTAssertFalse(toolbar.isHidden)
      for id in ["languageModeButton", "schemeButton", "scriptShortcut", "skinShortcut", "moreShortcut", "dismissShortcut"] {
        let control = try button(id, in: controller)
        XCTAssertGreaterThanOrEqual(control.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(control.bounds.height, 38)
      }
      XCTAssertEqual(try button("skinShortcut", in: controller).menu?.children.count, 8)
      let script = try button("scriptShortcut", in: controller)
      script.sendActions(for: .primaryActionTriggered)
      XCTAssertTrue(ChineseOutputPreference.usesTraditional)
      XCTAssertEqual(script.accessibilityValue, "繁体")
      script.sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(ChineseOutputPreference.usesTraditional)
      let key = try button("nineKey6", in: controller)
      let frame = key.convert(key.bounds, to: controller.view)
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
        controller.view.layer.render(in: context.cgContext)
      })
      attachment.name = "Keyboard shortcuts \(Int(width))pt"
      attachment.lifetime = .keepAlways
      add(attachment)
      for digit in "64426" { try button("nineKey\(digit)", in: controller).sendActions(for: .primaryActionTriggered) }
      controller.view.layoutIfNeeded()
      XCTAssertTrue(toolbar.isHidden)
      XCTAssertTrue(try XCTUnwrap(button("candidate-1", in: controller).configuration?.title).contains("你好"))
      XCTAssertEqual(key.convert(key.bounds, to: controller.view), frame)
      try button("nineKeyClear", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      XCTAssertFalse(toolbar.isHidden)
      XCTAssertEqual(key.convert(key.bounds, to: controller.view), frame)
    }
  }

  func testNineKeyInputAndLayoutSwitches() throws {
    let previous = InputSchemePreference.scheme
    InputSchemePreference.scheme = .nineKey
    defer { InputSchemePreference.scheme = previous }
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 216)
    controller.view.layoutIfNeeded()

    let nine = try button("nineKey6", in: controller)
    XCTAssertFalse(try XCTUnwrap(nine.superview).isHidden)
    XCTAssertEqual(try button("schemeButton", in: controller).menu?.children.count, 3)
    for digit in "64426" {
      try button("nineKey\(digit)", in: controller).sendActions(for: .primaryActionTriggered)
    }
    XCTAssertTrue(try XCTUnwrap(button("candidate-1", in: controller).configuration?.title).contains("你好"))
    try button("nineKeySpelling_ni", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(try XCTUnwrap(button("candidate-1", in: controller).configuration?.title).contains("你好"))
    controller.view.layoutIfNeeded()
    XCTAssertGreaterThanOrEqual(nine.bounds.height, 30)
    XCTAssertGreaterThan(nine.bounds.width, 60)
    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
      controller.view.layer.render(in: context.cgContext)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = "Nine-key pinyin keyboard"
    attachment.lifetime = .keepAlways
    add(attachment)

    try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(try XCTUnwrap(nine.superview).isHidden)
    try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(try XCTUnwrap(nine.superview).isHidden)
    try button("languageModeButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(try XCTUnwrap(nine.superview).isHidden)
    try button("languageModeButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(try XCTUnwrap(nine.superview).isHidden)
    XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, "全拼 9 键")

    InputSchemePreference.scheme = .shuangpin
    controller.viewWillAppear(false)
    XCTAssertTrue(try XCTUnwrap(nine.superview).isHidden)
    XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, "小鹤双拼")
  }

  func testKeyPositionsStayFixedWhileComposingAndClearing() throws {
    let previous = InputSchemePreference.scheme
    InputSchemePreference.scheme = .nineKey
    defer { InputSchemePreference.scheme = previous }
    for width in [320.0, 414.0] {
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      controller.view.layoutIfNeeded()
      let keys = try (1...9).map { try button("nineKey\($0)", in: controller) }
      let frames = keys.map { $0.convert($0.bounds, to: controller.view) }
      let delete = try button("nineKeyDelete", in: controller)
      let deleteFrame = delete.convert(delete.bounds, to: controller.view)
      XCTAssertGreaterThan(deleteFrame.minX, frames[2].maxX)
      XCTAssertEqual(deleteFrame.minY, frames[2].minY, accuracy: 0.5)
      XCTAssertGreaterThanOrEqual(frames[0].height, 44)
      let sidebar = try XCTUnwrap(descendants(controller.view).first {
        $0.accessibilityIdentifier == "nineKeySidebar"
      })
      XCTAssertLessThan(sidebar.convert(sidebar.bounds, to: controller.view).maxX, frames[0].minX)

      for phase in ["idle", "composing", "cleared"] {
        if phase == "composing" {
          for digit in "64426" {
            try button("nineKey\(digit)", in: controller).sendActions(for: .primaryActionTriggered)
          }
          XCTAssertTrue(try XCTUnwrap(button("candidate-1", in: controller).configuration?.title).contains("你好"))
          // The hostless XCTest runner does not route target/action through UIApplication.
          // Invoke the registered release action to exercise the same callback as a key tap.
          let releaseAction = try XCTUnwrap(delete.actions(forTarget: controller, forControlEvent: .touchUpInside)?.first)
          controller.perform(NSSelectorFromString(releaseAction))
          try button("nineKey6", in: controller).sendActions(for: .primaryActionTriggered)
          XCTAssertTrue(try XCTUnwrap(button("candidate-1", in: controller).configuration?.title).contains("你好"))
        } else if phase == "cleared" {
          try button("nineKeyClear", in: controller).sendActions(for: .primaryActionTriggered)
          XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "candidate-1" })
        }
        controller.view.layoutIfNeeded()
        for (key, expected) in zip(keys, frames) {
          XCTAssertEqual(key.convert(key.bounds, to: controller.view), expected,
                         "Key moved during \(phase) at width \(width)")
        }
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
          controller.view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Nine-key \(Int(width))pt \(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }

}
