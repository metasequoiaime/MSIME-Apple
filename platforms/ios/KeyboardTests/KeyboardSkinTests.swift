import XCTest
import UIKit

final class KeyboardSkinTests: XCTestCase {
  func testCuratedDesignsRemainReadableAndRoundTrip() throws {
    for (name, design) in CustomKeyboardSkin.templates {
      XCTAssertTrue(design.hasReadableText, name)
      XCTAssertEqual(design, design.normalized, name)
      XCTAssertEqual(try JSONDecoder().decode(CustomKeyboardSkin.self, from: JSONEncoder().encode(design)), design)
      XCTAssertGreaterThanOrEqual(CustomKeyboardSkin.contrast(CustomKeyboardSkin.readableText(on: design.actionBackground), design.actionBackground), 4.5, name)
    }
  }

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
  func testLegacyDesignsAndLibraryRoundTrip() throws {
    let legacy = Data(#"{"background":15266027,"keyBackground":16777215,"keyForeground":1516829,"accent":1596487,"actionBackground":1596487,"cornerRadius":8,"borderWidth":0,"shadow":0,"pattern":0,"monospaced":false}"#.utf8)
    let old = try JSONDecoder().decode(CustomKeyboardSkin.self, from: legacy)
    XCTAssertNil(old.gradientEnd)
    XCTAssertNil(old.photo)
    let previous = CustomSkinLibrary.designs
    defer { CustomSkinLibrary.save(previous) }
    var design = CustomKeyboardSkin.templates[2].1
    design.photoShade = .infinity
    design.photoPosition = -4
    design.photo = Data(repeating: 0, count: 512_001)
    design.patternOpacity = 2
    let item = SavedKeyboardSkin(name: "  我的夜色  ", design: design)
    CustomSkinLibrary.save([item])
    let restored = try XCTUnwrap(CustomSkinLibrary.designs.first)
    XCTAssertEqual(restored.id, item.id)
    XCTAssertEqual(restored.name, "我的夜色")
    XCTAssertEqual(restored.design.gradientEnd, design.gradientEnd)
    XCTAssertEqual(restored.design.photoShade, 0.25)
    XCTAssertEqual(restored.design.photoPosition, 0)
    XCTAssertNil(restored.design.photo)
    XCTAssertEqual(restored.design.patternOpacity, 0.5)
    CustomSkinLibrary.save([])
    XCTAssertTrue(CustomSkinLibrary.designs.isEmpty)
  }

  @MainActor
  func testGradientAndPhotoRenderInKeyboardBackdrop() throws {
    let previous = KeyboardFeedbackPreference.defaults.object(forKey: CustomKeyboardSkinStore.key)
    defer {
      if let previous { KeyboardFeedbackPreference.defaults.set(previous, forKey: CustomKeyboardSkinStore.key) }
      else { KeyboardFeedbackPreference.defaults.removeObject(forKey: CustomKeyboardSkinStore.key) }
    }
    let view = KeyboardSkinBackgroundView(frame: CGRect(x: 0, y: 0, width: 320, height: 260))
    func render(_ design: CustomKeyboardSkin) -> UIImage {
      CustomKeyboardSkinStore.save(design)
      view.skin = .custom
      return UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
    }
    var design = CustomKeyboardSkin()
    let plain = render(design)
    design.gradientEnd = 0x224466
    let gradient = render(design)
    XCTAssertNotEqual(plain.pngData(), gradient.pngData())
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
      UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    }
    design.photo = try XCTUnwrap(photo.jpegData(compressionQuality: 0.8))
    let wallpaper = render(design)
    XCTAssertNotEqual(gradient.pngData(), wallpaper.pngData())
    design.photoShade = 0.8
    XCTAssertNotEqual(wallpaper.pngData(), render(design).pngData())
    design.photo = nil
    design.photoShade = nil
    XCTAssertEqual(gradient.pngData(), render(design).pngData())
  }

  @MainActor
  func testPhotoImportBoundsAndSavedKeyboardSelection() throws {
    let defaults = KeyboardFeedbackPreference.defaults
    let old = defaults.object(forKey: CustomKeyboardSkinStore.key)
    let library = CustomSkinLibrary.designs
    defer {
      if let old { defaults.set(old, forKey: CustomKeyboardSkinStore.key) } else { defaults.removeObject(forKey: CustomKeyboardSkinStore.key) }
      CustomSkinLibrary.save(library)
    }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let original = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 800), format: format).image {
      UIColor.blue.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 2400, height: 800))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: url) }
    try XCTUnwrap(original.pngData()).write(to: url)
    let data = try XCTUnwrap(SkinPhotoData.thumbnail(at: url))
    let image = try XCTUnwrap(UIImage(data: data))
    XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1024)
    XCTAssertLessThanOrEqual(data.count, 512_000)
    try Data("not an image".utf8).write(to: url)
    XCTAssertNil(SkinPhotoData.thumbnail(at: url))
    var design = CustomKeyboardSkin.templates[2].1
    design.photo = data; design.keyOpacity = 0.45
    let item = SavedKeyboardSkin(name: "照片夜色", design: design)
    CustomSkinLibrary.save([item])
    var selection: KeyboardSkin?
    let picker = KeyboardSkinPickerView(selected: .forest, onSelect: { selection = $0 }, onClose: {})
    func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
    let button = try XCTUnwrap(descendants(picker).first { $0.accessibilityIdentifier == "savedSkinCard-" + item.id.uuidString } as? UIButton)
    button.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(selection, .custom)
    XCTAssertEqual(CustomKeyboardSkinStore.current, design)
    XCTAssertEqual(KeyboardSkin.custom.keyBackground.cgColor.alpha, 0.45, accuracy: 0.001)
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
