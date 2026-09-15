import XCTest
import UIKit

@MainActor
final class JapaneseNineKeyTests: XCTestCase {
  // Claims every scheme so an assignment to InputSchemePreference.scheme is not downgraded to
  // whatever the app group was left holding. See InputSchemeTestSupport.
  override func setUp() {
    super.setUp()
    enableAllInputSchemes()
  }

  func testKanaKeysFeedJapaneseEngineCandidates() throws {
    let previous = InputSchemePreference.scheme
    let enabled = InputSchemePreference.enabledSchemes
    defer {
      InputSchemePreference.enabledSchemes = enabled
      InputSchemePreference.scheme = previous
    }
    InputSchemePreference.enabledSchemes = ChineseInputScheme.allCases
    InputSchemePreference.scheme = .japaneseNineKey
    XCTAssertEqual(InputSchemePreference.scheme, .japaneseNineKey)
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260 + KeyboardViewController.stripExtraHeight)
    controller.view.layoutIfNeeded()
    let panel = try XCTUnwrap(nodes(controller.view).compactMap { $0 as? JapaneseNineKeyView }.first)
    XCTAssertFalse(panel.isHidden)
    let modeColumn = try XCTUnwrap(nodes(panel).first { $0.accessibilityIdentifier == "japaneseModeColumn" } as? UIStackView)
    XCTAssertEqual(modeColumn.arrangedSubviews.count, 4)
    let japaneseReturn = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "japaneseReturn" } as? UIButton)
    XCTAssertFalse(japaneseReturn.isHidden)
    let sharedReturn = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "returnKey" })
    XCTAssertTrue(sharedReturn.superview?.isHidden == true)
    panel.select(4, direction: 1) // に
    panel.select(5, direction: 4) // ほ
    panel.select(9, direction: 2) // ん
    let first = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "candidate-1" } as? UIButton)
    XCTAssertTrue(first.configuration?.title?.hasSuffix("日本") == true, first.configuration?.title ?? "No candidate")
    let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image {
      controller.view.layer.render(in: $0.cgContext)
    })
    screenshot.name = "Japanese nine-key candidates"; screenshot.lifetime = .keepAlways; add(screenshot)
    let picker = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "schemeButton" } as? UIButton)
    picker.sendActions(for: .primaryActionTriggered)
    for name in ["japanese", "japaneseNineKey"] {
      XCTAssertNotNil(nodes(controller.view).first { $0.accessibilityIdentifier == "schemeCard-\(name)" })
    }
    let roman = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "schemeCard-japanese" } as? UIButton)
    roman.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(InputSchemePreference.scheme, .japanese)
    XCTAssertTrue(panel.isHidden)
    controller.view.layoutIfNeeded()
    let letter = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityLabel == "字母 A" } as? UIButton)
    XCTAssertGreaterThan(letter.bounds.height, 40)
    picker.sendActions(for: .primaryActionTriggered)
    let nine = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "schemeCard-japaneseNineKey" } as? UIButton)
    nine.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(InputSchemePreference.scheme, .japaneseNineKey)
    XCTAssertFalse(panel.isHidden)
  }

  func testExistingJapaneseEnablesBothLayoutsOnlyOnce() throws {
    let name = "japanese-scheme-test-" + UUID().uuidString
    let store = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { store.removePersistentDomain(forName: name) }
    store.set(["quanpin", "japanese"], forKey: InputSchemePreference.enabledSchemesKey)
    store.set("japanese", forKey: "chineseInputScheme")
    InputSchemePreference.splitJapaneseSchemes(in: store)
    XCTAssertEqual(store.string(forKey: "chineseInputScheme"), "japaneseNineKey")
    XCTAssertEqual(store.stringArray(forKey: InputSchemePreference.enabledSchemesKey), ["quanpin", "japanese", "japaneseNineKey"])
    store.set(["quanpin", "japanese"], forKey: InputSchemePreference.enabledSchemesKey)
    InputSchemePreference.splitJapaneseSchemes(in: store)
    XCTAssertEqual(store.stringArray(forKey: InputSchemePreference.enabledSchemesKey), ["quanpin", "japanese"], "A user can disable nine keys after the split")
  }

  func testEveryKanaKeyConvertsAndLayoutsKeepFullHeight() throws {
    let bridge = MetasequoiaInputSessionBridge()
    _ = bridge.switchToJapanese()
    for key in JapaneseNineKeyView.keys {
      for (kana, input) in zip(key.kana, key.strokes) where !input.isEmpty {
        _ = bridge.cancel()
        var snapshot: MetasequoiaInputSnapshot?
        for letter in input { snapshot = bridge.handleCharacter(String(letter)) }
        XCTAssertTrue(snapshot?.candidates.contains(kana) == true,
                      "\(input) → \(kana): \(snapshot?.diagnosticText ?? String(describing: snapshot?.candidates ?? []))")
      }
    }
    let previous = KeyboardLayoutPreference.selected
    defer { KeyboardLayoutPreference.selected = previous }
    for layout in KeyboardLayoutPreset.allCases {
      KeyboardLayoutPreference.selected = layout
      for width in [320.0, 414.0] {
        let panel = JapaneseNineKeyView { title, _, action in
          var config = UIButton.Configuration.plain(); config.title = title
          return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        }
        panel.frame = CGRect(x: 0, y: 0, width: width, height: 176)
        panel.applyLayout(); panel.layoutIfNeeded()
        let buttons = nodes(panel).compactMap { $0 as? UIButton }
        XCTAssertEqual(buttons.count, 13)
        for button in buttons {
          XCTAssertGreaterThan(button.bounds.height, 45)
          XCTAssertGreaterThan(button.bounds.width, 44)
          XCTAssertLessThanOrEqual(button.convert(button.bounds, to: panel).maxX, width + 0.5)
        }
      }
    }
  }

  func testJapaneseNineKeyDigitLayerUsesSymbolsAndKeepsKanaPunctuation() throws {
    var symbols: [String] = []
    let panel = JapaneseNineKeyView { title, _, action in
      var config = UIButton.Configuration.plain(); config.title = title
      return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }
    panel.onSymbol = { symbols.append($0) }
    panel.setDigits(true)
    panel.select(0, direction: 0)
    panel.select(0, direction: 1)
    panel.select(0, direction: 4) // Empty fifth slot must not emit an empty symbol.
    panel.select(9, direction: 3)
    XCTAssertEqual(symbols, ["1", "☆", "ー"])
    panel.setDigits(false)
    panel.select(7, direction: 1)
    XCTAssertEqual(symbols.last, "「")
    panel.select(10, direction: 1)
    XCTAssertEqual(symbols.last, "。")
  }

  func testKanaVariantButtonDelegatesToEngineOnlyWhileComposing() throws {
    var variantActivations = 0
    let panel = JapaneseNineKeyView { title, _, action in
      var config = UIButton.Configuration.plain(); config.title = title
      return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }
    panel.onVariant = { variantActivations += 1 }
    let variants = try XCTUnwrap(nodes(panel).first { $0.accessibilityIdentifier == "japaneseVariants" } as? UIButton)
    variants.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(variantActivations, 0)
    panel.setComposing(true)
    variants.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(variantActivations, 1)
    panel.setDigits(true)
    variants.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(variantActivations, 1)
  }

  func testKanaKeysUseFlickPreviewInsteadOfLongPressMenus() throws {
    let panel = JapaneseNineKeyView { title, _, action in
      var config = UIButton.Configuration.plain(); config.title = title
      return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }
    let kana = try XCTUnwrap(nodes(panel).first { $0.accessibilityIdentifier == "japaneseKana0" } as? UIButton)
    XCTAssertNil(kana.menu)
    panel.setDigits(true)
    XCTAssertNotNil(kana.menu, "The numeric/symbol layer still exposes its alternate symbols")
    panel.setDigits(false)
    XCTAssertNil(kana.menu)
  }

  private func nodes(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { nodes($0) } }
}
