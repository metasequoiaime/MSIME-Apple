import XCTest
import UIKit

final class KeyboardSkinTests: XCTestCase {
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

  func testSkinTextContrastInBothAppearances() {
    for skin in KeyboardSkin.allCases {
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
