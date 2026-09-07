import XCTest
import UIKit

final class KeyboardSkinTests: XCTestCase {
  func testCustomSkinPersistenceValidationAndContrast() throws {
    let defaults = KeyboardFeedbackPreference.defaults
    let previous = defaults.object(forKey: CustomKeyboardSkinStore.key)
    defer {
      if let previous { defaults.set(previous, forKey: CustomKeyboardSkinStore.key) }
      else { defaults.removeObject(forKey: CustomKeyboardSkinStore.key) }
    }
    var design = CustomKeyboardSkin()
    design.cornerRadius = 100
    design.borderWidth = -4
    design.pattern = 99
    design.keyBackground = 0x132536
    design.keyForeground = 0xFFFFFF
    design.actionBackground = 0xFFFFFF
    CustomKeyboardSkinStore.save(design)
    let stored = CustomKeyboardSkinStore.current
    XCTAssertEqual(stored.cornerRadius, 20)
    XCTAssertEqual(stored.borderWidth, 0)
    XCTAssertEqual(stored.pattern, 0)
    XCTAssertEqual(stored.keyBackground, 0x132536)
    XCTAssertEqual(CustomKeyboardSkin.rgb(KeyboardSkin.custom.actionForeground), 0)
    XCTAssertEqual(CustomKeyboardSkin.rgb(CustomKeyboardSkin.color(0x123456)), 0x123456)
    defaults.set(Data("invalid".utf8), forKey: CustomKeyboardSkinStore.key)
    XCTAssertEqual(CustomKeyboardSkinStore.current, CustomKeyboardSkin())
    XCTAssertTrue(CustomKeyboardSkinStore.current.hasReadableText)
    for background: UInt32 in [0, 0x808080, 0xFFFFFF, 0xFF8800] {
      XCTAssertGreaterThanOrEqual(CustomKeyboardSkin.contrast(CustomKeyboardSkin.readableText(on: background), background), 4.5)
    }
  }
  private func luminance(_ color: UIColor, style: UIUserInterfaceStyle) -> Double {
    let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    func linear(_ value: CGFloat) -> Double {
      let v = Double(value)
      return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
  }

  @MainActor
  func testChangingDesignUpdatesActualKeyboardKeys() throws {
    let previous = KeyboardSkinPreference.selected
    defer { KeyboardFeedbackPreference.defaults.set(previous.rawValue, forKey: KeyboardSkinPreference.key) }
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
    func descendants(_ node: UIView) -> [UIView] { [node] + node.subviews.flatMap { descendants($0) } }
    for skin in [KeyboardSkin.typewriter, .candy, .midnight, .blueprint, .forest, .custom] {
      KeyboardFeedbackPreference.defaults.set(skin.rawValue, forKey: KeyboardSkinPreference.key)
      controller.viewWillAppear(false)
      controller.view.layoutIfNeeded()
      let key = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "returnKey" } as? UIButton)
      XCTAssertEqual(key.configuration?.background.cornerRadius, skin.cornerRadius)
      XCTAssertEqual(key.configuration?.background.strokeWidth, skin.borderWidth)
      XCTAssertEqual(key.layer.shadowOpacity, skin.shadowOpacity)
      XCTAssertEqual(key.configuration?.background.backgroundColor?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
        skin.actionBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
    }
  }

  func testSkinTextContrastInBothAppearances() {
    for skin in KeyboardSkin.allCases where skin != .custom {
      for style in [UIUserInterfaceStyle.light, .dark] {
        for (foreground, background) in [(skin.keyForeground, skin.keyBackground),
          (skin.actionForeground, skin.actionBackground), (skin.accent, skin.keyBackground)] {
          let a = luminance(foreground, style: style), b = luminance(background, style: style)
          XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, "\(skin) \(style)")
        }
      }
    }
  }
}
