import XCTest
import UIKit
import Darwin

@MainActor
final class NineKeyKeyboardTests: XCTestCase {
  // Claims every scheme so an assignment to InputSchemePreference.scheme is not downgraded to
  // whatever the app group was left holding. See InputSchemeTestSupport.
  private var savedKeyboardPreferences: [String: Any] = [:]
  private let preferenceKeys = [KeyboardLayoutPreference.key, KeyboardLayoutPreference.keySpacingKey,
    KeyboardLayoutPreference.rowSpacingKey, KeyboardLayoutPreference.voiceShortcutKey]
  override func tearDown() {
    for key in preferenceKeys {
      if let value = savedKeyboardPreferences[key] { KeyboardLayoutPreference.defaults.set(value, forKey: key) }
      else { KeyboardLayoutPreference.defaults.removeObject(forKey: key) }
    }
    super.tearDown()
  }
  override func setUp() {
    super.setUp()
    enableAllInputSchemes()
    savedKeyboardPreferences = [:]
    for key in preferenceKeys {
      savedKeyboardPreferences[key] = KeyboardLayoutPreference.defaults.object(forKey: key)
      if key != KeyboardLayoutPreference.key { KeyboardLayoutPreference.defaults.removeObject(forKey: key) }
    }
  }

  func testLayoutPresetsKeepKeysInBoundsAcrossBothKeyboards() throws {
    let previousLayout = KeyboardLayoutPreference.selected
    let previousScheme = InputSchemePreference.scheme
    let previousEnabled = InputSchemePreference.enabledSchemes
    defer {
      KeyboardLayoutPreference.selected = previousLayout
      InputSchemePreference.enabledSchemes = previousEnabled
      InputSchemePreference.scheme = previousScheme
    }
    InputSchemePreference.enabledSchemes = ChineseInputScheme.allCases
    for preset in KeyboardLayoutPreset.allCases {
      KeyboardLayoutPreference.selected = preset
      for scheme in [ChineseInputScheme.quanpin, .nineKey] {
        InputSchemePreference.scheme = scheme
        for width in [320.0, 414.0] {
          let controller = KeyboardViewController()
          controller.loadViewIfNeeded()
          controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
          controller.view.layoutIfNeeded()
          let space = try button("spaceKey", in: controller)
          let enter = try button("returnKey", in: controller)
          XCTAssertGreaterThanOrEqual(space.bounds.width, 43.5, "\(preset) / \(scheme) / \(width)")
          XCTAssertEqual(
            controller.view.bounds.height, 260 + KeyboardViewController.compositionRowHeight,
            accuracy: 0.5)
          XCTAssertLessThanOrEqual(enter.convert(enter.bounds, to: controller.view).maxX, width)
          let language = try button("bottomLanguageKey", in: controller)
          XCTAssertFalse(language.isHidden)
          if preset != .msime {
            XCTAssertGreaterThanOrEqual(language.convert(language.bounds, to: controller.view).minX,
              space.convert(space.bounds, to: controller.view).maxX)
          }
          if width == 414 {
            let renderer = UIGraphicsImageRenderer(bounds: controller.view.bounds)
            let screenshot = renderer.image { context in controller.view.layer.render(in: context.cgContext) }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "Layout-\(preset.rawValue)-\(scheme.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
          }
        }
      }
    }
  }

  func testLayoutPreferencePreservesActiveComposition() throws {
    let previousLayout = KeyboardLayoutPreference.selected
    let previousScheme = InputSchemePreference.scheme
    defer { KeyboardLayoutPreference.selected = previousLayout; InputSchemePreference.scheme = previousScheme }
    KeyboardLayoutPreference.selected = .msime
    InputSchemePreference.scheme = .quanpin
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    let key = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "字母 N" } as? UIButton)
    key.sendActions(for: .primaryActionTriggered)
    let before = try button("preeditButton", in: controller).configuration?.title
    KeyboardLayoutPreference.selected = .wechat
    controller.viewWillAppear(false)
    XCTAssertEqual(try button("preeditButton", in: controller).configuration?.title, before)
    XCTAssertFalse(try button("bottomLanguageKey", in: controller).isHidden)
  }

  func testFuzzyPreferencesWaitForIdleAndSurviveSchemeRebuild() {
    let bridge = MetasequoiaInputSessionBridge()
    XCTAssertTrue(bridge.setFuzzyPinyinRules(1))
    _ = bridge.handleCharacter("z")
    XCTAssertFalse(bridge.setFuzzyPinyinRules(0))
    _ = bridge.cancel()
    XCTAssertTrue(bridge.setFuzzyPinyinRules(0))
    XCTAssertTrue(bridge.setFuzzyPinyinRules(1))
    _ = bridge.switchToNineKey()
    _ = bridge.switch(toShuangpinProfile: "xiaohe")
    _ = bridge.handleCharacter("z")
    let view = bridge.handleCharacter("s")
    XCTAssertTrue(view.candidates.contains("中"))
    XCTAssertFalse(bridge.setFuzzyPinyinRules(0))
    _ = bridge.cancel()
    XCTAssertTrue(bridge.setFuzzyPinyinRules(0))
  }

  func testThoughtfulReplySchemeShowsDedicatedKeyboardAndCanBeDisabled() throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier))
    let previousEnabled = defaults.object(forKey: InputSchemePreference.enabledSchemesKey)
    let previous = InputSchemePreference.scheme
    defer {
      defaults.set(previousEnabled, forKey: InputSchemePreference.enabledSchemesKey)
      InputSchemePreference.scheme = previous
    }
    InputSchemePreference.enabledSchemes = [.quanpin, .thoughtfulReply]
    InputSchemePreference.scheme = .thoughtfulReply
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, "高情商回复")
    XCTAssertTrue(descendants(controller.view).contains { $0.accessibilityIdentifier == "replyKeyboard" })
    XCTAssertTrue(try XCTUnwrap(button("nineKey6", in: controller).superview).isHidden)
    InputSchemePreference.enabledSchemes = [.quanpin]
    controller.viewWillAppear(false)
    XCTAssertEqual(InputSchemePreference.scheme, .quanpin)
    XCTAssertTrue(try button("replyShortcut", in: controller).isHidden)
    XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "replyKeyboard" })

    // Inserting a reply takes the panel away so the text it just wrote, and the backspace that
    // edits it, are reachable. The reply shortcut is what brings it back, so that path has to work
    // even when the panel is already gone.
    InputSchemePreference.enabledSchemes = [.quanpin, .thoughtfulReply]
    InputSchemePreference.scheme = .thoughtfulReply
    controller.viewWillAppear(false)
    try button("replyShortcut", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(descendants(controller.view).contains { $0.accessibilityIdentifier == "replyKeyboard" })
  }

  func testDisabledSchemesAreHiddenAndCurrentSchemeFallsBack() throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier))
    let previousEnabled = defaults.object(forKey: InputSchemePreference.enabledSchemesKey)
    let previousScheme = InputSchemePreference.scheme
    defer {
      defaults.set(previousEnabled, forKey: InputSchemePreference.enabledSchemesKey)
      InputSchemePreference.scheme = previousScheme
    }
    defaults.removeObject(forKey: InputSchemePreference.enabledSchemesKey)
    XCTAssertEqual(InputSchemePreference.enabledSchemes, ChineseInputScheme.allCases)
    InputSchemePreference.scheme = .japanese
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    InputSchemePreference.enabledSchemes = [.nineKey, .wubi]
    XCTAssertEqual(InputSchemePreference.scheme, .nineKey)
    controller.viewWillAppear(false)
    XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, "全拼 9 键")
    try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
    let cards = descendants(controller.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("schemeCard-") }
    XCTAssertEqual(Set(cards), ["schemeCard-nineKey", "schemeCard-wubi"])
    try button("schemeCard-wubi", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(InputSchemePreference.scheme, .wubi)
    InputSchemePreference.enabledSchemes = []
    XCTAssertEqual(InputSchemePreference.enabledSchemes, [.quanpin])
    XCTAssertEqual(InputSchemePreference.scheme, .quanpin)
  }

  func testFieldLanguagePreferenceIsTemporaryAndRespectsManualChoice() {
    var context = KeyboardInputContext()
    let ordinary = UUID(), code = UUID(), url = UUID()
    XCTAssertNil(context.languageOverride(for: .default, document: ordinary, isChinese: true))
    XCTAssertEqual(context.languageOverride(for: .asciiCapable, document: code, isChinese: true), false)
    // A user explicitly switched to Chinese in this field; callbacks must not force English again.
    XCTAssertNil(context.languageOverride(for: .asciiCapable, document: code, isChinese: true))
    XCTAssertEqual(context.languageOverride(for: .URL, document: url, isChinese: true), false)
    XCTAssertEqual(context.languageOverride(for: .default, document: ordinary, isChinese: false), true)
    XCTAssertEqual(context.languageOverride(for: .emailAddress, document: code, isChinese: false), false)
    XCTAssertEqual(context.languageOverride(for: .default, document: ordinary, isChinese: false), false)
    XCTAssertNil(context.languageOverride(for: .webSearch, document: UUID(), isChinese: true))
    XCTAssertNil(context.languageOverride(for: .default, document: UUID(), isChinese: true))
  }

  func testLatinFieldsUseFullKeyboardAndRestoreNineKeyHeight() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    InputSchemePreference.scheme = .nineKey
    for width in [320.0, 414.0] {
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
      let ordinary = UUID()
      controller.applyInputContext(keyboardType: .default, documentIdentifier: ordinary)
      for type in [UIKeyboardType.asciiCapable, .emailAddress, .URL] {
        // Any preedit left after a missed focus callback must not enter the new field.
        try button("nineKey6", in: controller).sendActions(for: .primaryActionTriggered)
        let field = UUID()
        controller.applyInputContext(keyboardType: type, documentIdentifier: field)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(try button("bottomLanguageKey", in: controller).accessibilityValue, "英文输入")
        XCTAssertTrue(try XCTUnwrap(button("nineKey6", in: controller).superview).isHidden)
        XCTAssertFalse(try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardShortcutBar" }).isHidden)
        let q = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "字母 Q" } as? UIButton)
        XCTAssertFalse(try XCTUnwrap(q.superview).isHidden)
        XCTAssertEqual(q.bounds.height, try button("returnKey", in: controller).bounds.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(q.bounds.height, 44)
        if type != .asciiCapable { XCTAssertEqual(q.configuration?.title, "q") }
        XCTAssertEqual(try button("quickPunctuationKey", in: controller).configuration?.title, ",")
        q.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(try button("preeditButton", in: controller).configuration?.title, "英文输入")
        try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
        controller.view.layoutIfNeeded()
        for symbol in ["@", "/", "_", "="] {
          let key = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "符号 \(symbol)" } as? UIButton)
          XCTAssertFalse(try XCTUnwrap(key.superview).isHidden)
          XCTAssertGreaterThan(key.bounds.width, 20)
        }
        controller.applyInputContext(keyboardType: type, documentIdentifier: field)
        controller.applyInputContext(keyboardType: .default, documentIdentifier: ordinary)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(try button("bottomLanguageKey", in: controller).accessibilityValue, "中文输入")
        XCTAssertFalse(try XCTUnwrap(button("nineKey6", in: controller).superview).isHidden)
        XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, "全拼 9 键")
        XCTAssertEqual(controller.view.bounds.height, 260 + KeyboardViewController.compositionRowHeight)
      }
    }
  }

  func testCursorDragCannotResumeAfterDocumentChangeOrCancellation() {
    var movement = SpaceCursorMovement()
    let first = UUID(), second = UUID()
    movement.begin(at: 0, document: first)
    XCTAssertEqual(movement.advance(to: 24, document: first), 2)
    XCTAssertEqual(movement.advance(to: 48, document: second), 0)
    XCTAssertFalse(movement.isActive)
    XCTAssertEqual(movement.advance(to: 60, document: first), 0)
    movement.begin(at: 0, document: second)
    movement.cancel()
    XCTAssertEqual(movement.advance(to: 24, document: second), 0)
    movement.begin(at: 0, document: second)
    XCTAssertEqual(movement.advance(to: .greatestFiniteMagnitude, document: second), 0)
    XCTAssertFalse(movement.isActive)
    movement.begin(at: .nan, document: first)
    XCTAssertFalse(movement.isActive)
  }

  func testSpaceCursorMovementAccumulatesDistanceAndReverses() throws {
    var movement = SpaceCursorMovement()
    let document = UUID()
    movement.begin(at: 10, document: document)
    XCTAssertEqual(movement.advance(to: 15, document: document), 0)
    XCTAssertEqual(movement.advance(to: 34, document: document), 2)
    XCTAssertEqual(movement.advance(to: 30, document: document), 0)
    XCTAssertEqual(movement.advance(to: 22, document: document), -1)
    movement.begin(at: -20, document: document)
    XCTAssertEqual(movement.advance(to: -31, document: document), 0)
    XCTAssertEqual(movement.advance(to: -44, document: document), -2)
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    let space = try button("spaceKey", in: controller)
    XCTAssertEqual(space.accessibilityCustomActions?.map(\.name), ["光标左移", "光标右移"])
    let pan = try XCTUnwrap(space.gestureRecognizers?.first { $0.name == "spaceCursorPan" } as? UIPanGestureRecognizer)
    XCTAssertTrue(pan.cancelsTouchesInView)
    XCTAssertEqual(pan.maximumNumberOfTouches, 1)
  }

  func testChangingHapticStrengthReplacesTheViewGenerator() throws {
    guard #available(iOS 17.5, *) else { throw XCTSkip("View-bound haptics require iOS 17.5") }
    let defaults = KeyboardFeedbackPreference.defaults
    let keys = [KeyboardFeedbackPreference.hapticsKey, KeyboardFeedbackPreference.strengthKey]
    let previous = keys.map { defaults.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, previous) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
      }
    }
    defaults.set(true, forKey: KeyboardFeedbackPreference.hapticsKey)
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    var last: UIImpactFeedbackGenerator?
    for strength in KeyboardHapticStrength.allCases {
      defaults.set(strength.rawValue, forKey: KeyboardFeedbackPreference.strengthKey)
      try button("bottomLanguageKey", in: controller).sendActions(for: .primaryActionTriggered)
      let generators = controller.view.interactions.compactMap { $0 as? UIImpactFeedbackGenerator }
      XCTAssertEqual(generators.count, 1)
      let current = try XCTUnwrap(generators.first)
      if let last { XCTAssertFalse(last === current) }
      last = current
    }
  }

  func testCandidateManagementMenuUsesEngineSupportedLayouts() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for scheme in [ChineseInputScheme.quanpin, .nineKey] {
      InputSchemePreference.scheme = scheme
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      for character in (scheme == .nineKey ? "64426" : "nihao") {
        if scheme == .nineKey {
          try button("nineKey\(character)", in: controller).sendActions(for: .primaryActionTriggered)
        } else {
          let key = try XCTUnwrap(descendants(controller.view).first {
            $0.accessibilityLabel == "字母 \(String(character).uppercased())"
          } as? UIButton)
          key.sendActions(for: .primaryActionTriggered)
        }
      }
      // The chips are reused across keystrokes and build this menu only when it is opened, so the
      // button's static children are a placeholder. Ask for the elements the way the menu will.
      let candidate = try button("candidate-1", in: controller)
      XCTAssertTrue(candidate.menu?.children.first is UIDeferredMenuElement,
                    "候选菜单应延迟到展开时构建")
      let elements = controller.candidateMenuElements(at: 0)
      XCTAssertEqual(elements.map(\.title), ["优先显示", "固定到首位", "取消固定", "删除词条…"])
      XCTAssertEqual((elements.last as? UIMenu)?.children.first?.title, "确认删除此词条")
    }
  }

  func testSkinCardsPreviewAndApplyWithoutChangingKeyboardHeight() throws {
    let previous = KeyboardSkinPreference.selected
    defer { KeyboardFeedbackPreference.defaults.set(previous.rawValue, forKey: KeyboardSkinPreference.key) }
    for width in [320.0, 414.0] {
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
      controller.view.layoutIfNeeded()
      try button("skinShortcut", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      let picker = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardSkinPicker" })
      XCTAssertEqual(picker.bounds.height, 260 + KeyboardViewController.compositionRowHeight)
      for skin in KeyboardSkin.allCases {
        let card = try button("skinCard-\(skin.rawValue)", in: controller)
        XCTAssertGreaterThan(card.bounds.width, 140)
        let miniature = try XCTUnwrap(descendants(card).compactMap { $0 as? KeyboardSkinMiniature }.first)
        XCTAssertGreaterThan(miniature.bounds.height, 75)
        XCTAssertEqual(miniature.bounds.height / miniature.bounds.width, 0.6, accuracy: 0.01)
        XCTAssertEqual(card.bounds.height, miniature.bounds.height + 36, accuracy: 0.1)
      }
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
        controller.view.layer.render(in: context.cgContext)
      })
      attachment.name = "Skin cards \(Int(width))pt"
      attachment.lifetime = .keepAlways
      add(attachment)
      try button("skinCard-ocean", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertEqual(KeyboardSkinPreference.selected, .ocean)
      XCTAssertNil(picker.superview)
      XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260 + KeyboardViewController.compositionRowHeight)
      try button("skinShortcut", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertEqual(try button("skinCard-ocean", in: controller).accessibilityValue, "已选中")
      try button("closeSkinPicker", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "keyboardSkinPicker" })
    }
  }

  func testLegacyLayoutsMigrateIndependentSettings() {
    let defaults = KeyboardLayoutPreference.defaults
    for preset in KeyboardLayoutPreset.allCases {
      for key in [KeyboardLayoutPreference.keySpacingKey, KeyboardLayoutPreference.rowSpacingKey, KeyboardLayoutPreference.voiceShortcutKey] {
        defaults.removeObject(forKey: key)
      }
      KeyboardLayoutPreference.selected = preset
      XCTAssertEqual(KeyboardLayoutPreference.keySpacing, preset.keySpacing)
      XCTAssertEqual(KeyboardLayoutPreference.rowSpacing, preset.rowSpacing)
      XCTAssertEqual(KeyboardLayoutPreference.voiceShortcutEnabled, preset == .doubao)
      XCTAssertEqual(KeyboardLayoutPreference.geometry.sidebarRatio, 0.14)
      XCTAssertFalse(KeyboardLayoutPreference.geometry.showsFullKeyboardSymbols)
      KeyboardLayoutPreference.keySpacing = 5
      KeyboardLayoutPreference.voiceShortcutEnabled = !(preset == .doubao)
      XCTAssertEqual(KeyboardLayoutPreference.keySpacing, 5)
      XCTAssertEqual(KeyboardLayoutPreference.rowSpacing, preset.rowSpacing)
      XCTAssertEqual(KeyboardLayoutPreference.voiceShortcutEnabled, preset != .doubao)
      XCTAssertEqual(KeyboardLayoutPreference.selected, preset)
    }
    KeyboardLayoutPreference.keySpacing = 99
    KeyboardLayoutPreference.rowSpacing = -99
    XCTAssertEqual(KeyboardLayoutPreference.keySpacing, 6)
    XCTAssertEqual(KeyboardLayoutPreference.rowSpacing, 4)
  }

  func testSpacingChangesKeepDefaultKeyPlacementAndComposition() throws {
    let previousScheme = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previousScheme }
    for scheme in [ChineseInputScheme.quanpin, .nineKey] {
      InputSchemePreference.scheme = scheme
      for width in [320.0, 440.0] {
        let controller = KeyboardViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 292)
        for gap in [3.0, 6.0] {
          try button("layoutShortcut", in: controller).sendActions(for: .primaryActionTriggered)
          let slider = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keySpacingSlider" } as? UISlider)
          slider.value = Float(gap)
          slider.sendActions(for: .valueChanged)
          let row = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "rowSpacingSlider" } as? UISlider)
          row.value = gap == 3 ? 4 : 10
          row.sendActions(for: .valueChanged)
          try button("closeLayoutPicker", in: controller).sendActions(for: .primaryActionTriggered)
          controller.view.layoutIfNeeded()
          XCTAssertEqual(KeyboardLayoutPreference.geometry.keySpacing, gap)
          let enter = try button("returnKey", in: controller)
          let space = try button("spaceKey", in: controller)
          XCTAssertGreaterThanOrEqual(space.bounds.width, 43.5)
          XCTAssertLessThanOrEqual(enter.convert(enter.bounds, to: controller.view).maxX, width)
          XCTAssertEqual(controller.view.bounds.height, 292)
          XCTAssertFalse(try button("bottomLanguageKey", in: controller).isHidden)
        }
      }
    }
  }

  func testNineKeysCarryTheirLettersAndAHoldGesture() throws {
    let previousScheme = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previousScheme }
    InputSchemePreference.scheme = .nineKey
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)

    // Nine-key treats 2-9 as pinyin, so a bare letter or digit has no other way in than a hold.
    let expected = [2: "ABC", 3: "DEF", 4: "GHI", 5: "JKL", 6: "MNO", 7: "PQRS", 8: "TUV", 9: "WXYZ"]
    for (digit, letters) in expected {
      let key = try button("nineKey\(digit)", in: controller)
      XCTAssertEqual(key.configuration?.title, letters, "九键 \(digit) 的键面字母")
      XCTAssertEqual(key.tag, digit, "长按要靠 tag 认出是哪个键")
      let holds = (key.gestureRecognizers ?? []).compactMap { $0 as? UILongPressGestureRecognizer }
      XCTAssertEqual(holds.count, 1, "九键 \(digit) 需要且只需要一个长按手势")
    }

    // The word-split key carries no letters, so it offers nothing to hold for.
    let split = try button("nineKey1", in: controller)
    XCTAssertEqual(split.configuration?.title, "分词")
    XCTAssertTrue(
      (split.gestureRecognizers ?? []).compactMap { $0 as? UILongPressGestureRecognizer }.isEmpty,
      "分词键不该有长按手势")
  }

  func testResetForgetsTheStoredKeyboardSettings() throws {
    let defaults = KeyboardLayoutPreference.defaults
    let previous = (
      keys: defaults.object(forKey: KeyboardLayoutPreference.keySpacingKey),
      rows: defaults.object(forKey: KeyboardLayoutPreference.rowSpacingKey),
      height: defaults.object(forKey: KeyboardLayoutPreference.heightAdjustmentKey),
      voice: defaults.object(forKey: KeyboardLayoutPreference.voiceShortcutKey)
    )
    defer {
      defaults.set(previous.keys, forKey: KeyboardLayoutPreference.keySpacingKey)
      defaults.set(previous.rows, forKey: KeyboardLayoutPreference.rowSpacingKey)
      defaults.set(previous.height, forKey: KeyboardLayoutPreference.heightAdjustmentKey)
      defaults.set(previous.voice, forKey: KeyboardLayoutPreference.voiceShortcutKey)
    }

    KeyboardLayoutPreference.keySpacing = 4
    KeyboardLayoutPreference.rowSpacing = 9
    KeyboardLayoutPreference.heightAdjustment = 30
    KeyboardLayoutPreference.voiceShortcutEnabled = !KeyboardLayoutPreference.voiceShortcutEnabled

    KeyboardLayoutPreference.resetToDefaults()

    // Reset forgets the values rather than writing defaults over them, so each one reads through
    // its fallback again and a later change to those defaults still reaches this keyboard.
    for stored in [
      KeyboardLayoutPreference.keySpacingKey, KeyboardLayoutPreference.rowSpacingKey,
      KeyboardLayoutPreference.heightAdjustmentKey, KeyboardLayoutPreference.voiceShortcutKey,
    ] {
      XCTAssertNil(defaults.object(forKey: stored), "\(stored) 应被遗忘而不是写入默认值")
    }
    XCTAssertEqual(KeyboardLayoutPreference.heightAdjustment, 0)
    XCTAssertEqual(KeyboardLayoutPreference.keySpacing, KeyboardLayoutPreference.selected.keySpacing)
    XCTAssertEqual(KeyboardLayoutPreference.rowSpacing, KeyboardLayoutPreference.selected.rowSpacing)
  }

  func testKeyboardHeightFollowsTheSetting() throws {
    let previous = KeyboardLayoutPreference.heightAdjustment
    defer { KeyboardLayoutPreference.heightAdjustment = previous }

    func height(for adjustment: Double) -> CGFloat {
      KeyboardLayoutPreference.heightAdjustment = adjustment
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)
      controller.view.layoutIfNeeded()
      return controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant ?? 0
    }

    let standard = height(for: 0)
    XCTAssertGreaterThan(standard, 0)
    // The keys divide whatever the keyboard claims, so a taller keyboard is what makes them easier
    // to hit -- the setting exists for that, not for the strip.
    XCTAssertEqual(height(for: 24), standard + 24, accuracy: 0.5)
    XCTAssertEqual(height(for: -12), standard - 12, accuracy: 0.5)

    // Out-of-range values are clamped by the preference rather than reaching the constraint.
    KeyboardLayoutPreference.heightAdjustment = 500
    XCTAssertEqual(KeyboardLayoutPreference.heightAdjustment, 48)
    KeyboardLayoutPreference.heightAdjustment = -500
    XCTAssertEqual(KeyboardLayoutPreference.heightAdjustment, -12)
  }

  func testSymbolKeysShowThePunctuationTheyInsert() throws {
    let previousScheme = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previousScheme }
    InputSchemePreference.scheme = .quanpin
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)
    try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()

    func face(_ label: String) -> UIButton? {
      descendants(controller.view).first { $0.accessibilityLabel == "符号 \(label)" } as? UIButton
    }

    // Nothing on the keyboard said that a backslash is how you reach 、, which is what people ask.
    for (ascii, chinese) in [("\\", "、"), (",", "，"), ("[", "【"), ("<", "《")] {
      XCTAssertNotNil(face(chinese), "中文模式下应显示 \(chinese)")
      XCTAssertNil(face(ascii), "中文模式下不该再显示 \(ascii)")
    }

    // English mode inserts the plain character, so that is what it has to show.
    try button("bottomLanguageKey", in: controller).sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()
    XCTAssertNotNil(face("\\"), "英文模式下应显示反斜杠本身")
    XCTAssertNil(face("、"))
  }

  func testNineKeyDigitLayerKeepsTheGridInsteadOfTheTwentySixKeyRows() throws {
    let previousScheme = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previousScheme }
    InputSchemePreference.scheme = .nineKey
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)

    XCTAssertEqual(try button("nineKey2", in: controller).configuration?.title, "ABC")
    try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()

    // The grid stays and re-labels itself; handing over to the ten-across symbol rows is what this
    // guards against, because a nine-key user chose three columns.
    XCTAssertFalse(controller.view.subviews.isEmpty)
    for digit in 1...9 {
      XCTAssertEqual(try button("nineKey\(digit)", in: controller).configuration?.title, String(digit),
                     "数字键面上九键 \(digit) 应显示数字")
    }
    let symbolDigits = descendants(controller.view).filter {
      $0.accessibilityLabel == "符号 1" && !($0.superview?.isHidden ?? true)
    }
    XCTAssertTrue(symbolDigits.isEmpty, "九键的数字键面不应显示 26 键那排符号")

    try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
    controller.view.layoutIfNeeded()
    XCTAssertEqual(try button("nineKey2", in: controller).configuration?.title, "ABC", "退出数字键面要恢复字母")
  }

  func testKeyboardSettingsReplaceLayoutCardsAndKeepTheComposition() throws {
    let previousScheme = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previousScheme }
    InputSchemePreference.scheme = .quanpin
    KeyboardLayoutPreference.keySpacing = 5
    KeyboardLayoutPreference.rowSpacing = 8
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 440, height: 292)
    let letter = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "字母 N" } as? UIButton)
    letter.sendActions(for: .primaryActionTriggered)
    let preedit = try button("preeditButton", in: controller).configuration?.title
    try button("layoutShortcut", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier?.hasPrefix("layoutCard-") == true })
    XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "voiceShortcutSwitch" })
    XCTAssertEqual(KeyboardLayoutPreference.keySpacing, 5)
    XCTAssertEqual(KeyboardLayoutPreference.rowSpacing, 8)
    XCTAssertEqual(try button("preeditButton", in: controller).configuration?.title, preedit)
    try button("closeLayoutPicker", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertNotNil(try button("emojiShortcut", in: controller))
  }

  func testBrandOpensCompactToolsAndUpdatesFeedbackState() throws {
    let previous = KeyboardFeedbackPreference.soundEnabled
    defer { KeyboardFeedbackPreference.defaults.set(previous, forKey: KeyboardFeedbackPreference.soundKey) }
    for width in [320.0, 414.0] {
      KeyboardFeedbackPreference.defaults.set(true, forKey: KeyboardFeedbackPreference.soundKey)
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
      controller.view.layoutIfNeeded()
      let toolbar = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardShortcutBar" } as? UIStackView)
      let more = try button("moreShortcut", in: controller)
      XCTAssertTrue(toolbar.arrangedSubviews.first === more)
      let skinIndex = try XCTUnwrap(toolbar.arrangedSubviews.firstIndex(of: button("skinShortcut", in: controller)))
      XCTAssertTrue(toolbar.arrangedSubviews[skinIndex + 1] === (try button("layoutShortcut", in: controller)))
      for item in toolbar.arrangedSubviews {
        XCTAssertGreaterThanOrEqual(item.bounds.width, 42)
        XCTAssertLessThanOrEqual(item.frame.maxX, toolbar.bounds.width + 0.5)
      }
      XCTAssertNil(more.menu)
      XCTAssertNotNil(descendants(more).first { $0.accessibilityIdentifier == "keyboardBrandIcon" })
      more.sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      let panel = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardMorePicker" })
      XCTAssertEqual(panel.bounds.height, 260 + KeyboardViewController.compositionRowHeight)
      for title in ["剪贴板历史", "AI 润色", "表情", "本地输入", "繁体输出", "按键音", "按键振动"] {
        let card = try button("moreCard-" + title, in: controller)
        XCTAssertGreaterThan(card.bounds.width, 100)
        XCTAssertEqual(card.bounds.height, 48)
        XCTAssertEqual(card.configuration?.imagePlacement, .leading)
      }
      // 本地输入的八个模式收在二级,一级里不该出现。
      XCTAssertNil(descendants(controller.view).first { $0.accessibilityIdentifier == "moreCard-日期时间" })
      try button("moreCard-本地输入", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      XCTAssertNotNil(try button("moreCard-Unicode 码点", in: controller))
      try button("moreCard-返回工具", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      XCTAssertNotNil(try button("moreCard-表情", in: controller))
      let back = try button("closeMorePicker", in: controller)
      XCTAssertEqual(back.configuration?.title, "返回")
      XCTAssertEqual(back.accessibilityLabel, "返回键盘")
      XCTAssertGreaterThanOrEqual(back.bounds.height, 44)
      XCTAssertLessThan(back.frame.midX, panel.bounds.midX)
      // 每一张卡都要落在键盘高度以内。这条之前抓到过面板长到 360pt、末尾整段看不见。
      for card in descendants(panel) where card.accessibilityIdentifier?.hasPrefix("moreCard-") == true {
        XCTAssertLessThanOrEqual(card.convert(card.bounds, to: panel).maxY, panel.bounds.height,
                                 "\(card.accessibilityIdentifier ?? "?") 超出面板")
      }
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
        controller.view.layer.render(in: context.cgContext)
      })
      attachment.name = "Compact tools \(Int(width))pt"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertEqual(try button("moreCard-按键音", in: controller).accessibilityValue, "已开启")
      try button("moreCard-按键音", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(KeyboardFeedbackPreference.soundEnabled)
      XCTAssertEqual(try button("moreCard-按键音", in: controller).accessibilityValue, "已关闭")
      try button("closeMorePicker", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertNil(panel.superview)
      more.sendActions(for: .primaryActionTriggered)
      try button("moreCard-AI 润色", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "keyboardMorePicker" })
      XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260 + KeyboardViewController.compositionRowHeight)
    }
  }

  func testSchemePickerUsesCurrentSkinPalette() throws {
    let previous = KeyboardSkinPreference.selected
    defer { KeyboardFeedbackPreference.defaults.set(previous.rawValue, forKey: KeyboardSkinPreference.key) }
    for skin in [KeyboardSkin.forest, .ocean, .midnight] {
      KeyboardFeedbackPreference.defaults.set(skin.rawValue, forKey: KeyboardSkinPreference.key)
      for style in [UIUserInterfaceStyle.light, .dark] {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let picker = KeyboardSchemePickerView(selected: .nineKey, onSelect: { _ in }, onClose: {})
        picker.overrideUserInterfaceStyle = style
        picker.frame = CGRect(x: 0, y: 0, width: 414, height: 292)
        picker.layoutIfNeeded()
        func assertColor(_ actual: UIColor?, _ expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
          XCTAssertEqual(actual?.resolvedColor(with: traits), expected.resolvedColor(with: traits), file: file, line: line)
        }
        let buttons = descendants(picker).compactMap { $0 as? UIButton }
        XCTAssertFalse(buttons.contains { $0.accessibilityIdentifier == "schemePickerKeyboardTab" })
        XCTAssertFalse(buttons.contains { $0.accessibilityIdentifier == "schemePickerThemeTab" })
        let back = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "closeSchemePicker" })
        let selected = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "schemeCard-nineKey" })
        assertColor(picker.backgroundColor, skin.background)
        assertColor(back.tintColor, skin.accent)
        assertColor(selected.backgroundColor, skin.accent.withAlphaComponent(0.10))
        let labels = selected.subviews.compactMap { $0 as? UILabel }.filter { $0.text?.isEmpty == false }
        XCTAssertEqual(labels.count, 3)
        for label in labels {
          assertColor(label.textColor, skin.accent)
        }
      }
    }
  }

  func testSchemeGridHasFourColumnsAtNarrowAndWideSizes() throws {
    for width in [320.0, 414.0, 812.0] {
      let picker = KeyboardSchemePickerView(selected: .nineKey, onSelect: { _ in }, onClose: {})
      picker.frame = CGRect(x: 0, y: 0, width: width, height: width > 500 ? 216 : 260)
      picker.layoutIfNeeded()
      let cards = descendants(picker).filter { $0.accessibilityIdentifier?.hasPrefix("schemeCard-") == true }
      XCTAssertGreaterThanOrEqual(cards.count, 4)
      let firstRow = cards.prefix(4).map { $0.convert($0.bounds, to: picker) }
      for frame in firstRow {
        XCTAssertEqual(frame.minY, firstRow[0].minY, accuracy: 0.1)
        XCTAssertEqual(frame.width, firstRow[0].width, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(frame.width, 60)
        XCTAssertGreaterThanOrEqual(frame.height, 44)
        XCTAssertGreaterThanOrEqual(frame.minX, 14)
        XCTAssertLessThanOrEqual(frame.maxX, width - 14)
      }
      XCTAssertEqual(Set(firstRow.map { $0.minX }).count, 4)
      XCTAssertTrue(descendants(picker).compactMap { $0 as? KeyboardSkinMiniature }.isEmpty)
    }
  }

  func testSchemeCardsSelectAndKeepKeyboardHeight() throws {
    let enabled = InputSchemePreference.enabledSchemes
    defer { InputSchemePreference.enabledSchemes = enabled }
    InputSchemePreference.enabledSchemes = ChineseInputScheme.allCases
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for width in [320.0, 414.0] {
      InputSchemePreference.scheme = .nineKey
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
      controller.view.layoutIfNeeded()
      try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      let picker = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardSchemePicker" })
      XCTAssertEqual(picker.bounds.height, 260 + KeyboardViewController.compositionRowHeight)
      for scheme in ChineseInputScheme.allCases {
        let card = try button("schemeCard-\(scheme.rawValue)", in: controller)
        XCTAssertGreaterThanOrEqual(card.bounds.width, 60)
        XCTAssertEqual(card.bounds.height, 62, accuracy: 0.1)
      }
      XCTAssertEqual(try button("schemeCard-nineKey", in: controller).accessibilityValue, "已选中")
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
        controller.view.layer.render(in: context.cgContext)
      })
      attachment.name = "Input scheme cards \(Int(width))pt"
      attachment.lifetime = .keepAlways
      add(attachment)
      try button("schemeCard-quanpin", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertNil(picker.superview)
      XCTAssertEqual(InputSchemePreference.scheme, .quanpin)
      XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, ChineseInputScheme.quanpin.title)
      controller.view.layoutIfNeeded()
      XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260 + KeyboardViewController.compositionRowHeight)
      try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertEqual(try button("schemeCard-quanpin", in: controller).accessibilityValue, "已选中")
      try button("closeSchemePicker", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "keyboardSchemePicker" })
      XCTAssertEqual(InputSchemePreference.scheme, .quanpin)
    }
  }

  func testSchemePickerSwitchesEnglishAndSettingsWithSeparateThemeEntry() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    InputSchemePreference.scheme = .quanpin
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 260)
    controller.view.layoutIfNeeded()
    try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
    try button("schemeEnglishCard", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(try button("bottomLanguageKey", in: controller).accessibilityValue, "英文输入")
    try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(try button("schemeEnglishCard", in: controller).accessibilityValue, "已选中")
    XCTAssertEqual(try button("schemeCard-quanpin", in: controller).accessibilityValue, "")
    try button("schemeCard-quanpin", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(try button("bottomLanguageKey", in: controller).accessibilityValue, "中文输入")
    try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "schemePickerThemeTab" })
    XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "schemePickerKeyboardTab" })
    XCTAssertFalse(descendants(controller.view).contains { $0 is KeyboardSkinPickerView })
    XCTAssertEqual(try button("schemeCard-quanpin", in: controller).accessibilityValue, "已选中")
    try button("schemePickerSettings", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(descendants(controller.view).contains { $0 is KeyboardSchemePickerView })
    XCTAssertTrue(descendants(controller.view).contains { $0.accessibilityIdentifier == "keyboardMorePicker" })
    try button("closeMorePicker", in: controller).sendActions(for: .primaryActionTriggered)
    try button("skinShortcut", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(descendants(controller.view).contains { $0 is KeyboardSkinPickerView })
    try button("closeSkinPicker", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(descendants(controller.view).contains { $0 is KeyboardSkinPickerView })
  }

  func testVisibleInputViewReflectsSoundPreference() throws {
    let defaults = KeyboardFeedbackPreference.defaults
    let previous = defaults.object(forKey: KeyboardFeedbackPreference.soundKey)
    defer {
      if let previous { defaults.set(previous, forKey: KeyboardFeedbackPreference.soundKey) }
      else { defaults.removeObject(forKey: KeyboardFeedbackPreference.soundKey) }
    }
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    let inputView = try XCTUnwrap(controller.inputView as? KeyboardInputView)
    XCTAssertTrue(controller.view === inputView)
    defaults.set(true, forKey: KeyboardFeedbackPreference.soundKey)
    XCTAssertTrue(inputView.enableInputClicksWhenVisible)
    defaults.set(false, forKey: KeyboardFeedbackPreference.soundKey)
    XCTAssertFalse(inputView.enableInputClicksWhenVisible)
  }

  func testShiftIsDiscoverableAndSwitchesToEnglishCapitalization() throws {
    let previous = InputSchemePreference.scheme
    InputSchemePreference.scheme = .quanpin
    defer { InputSchemePreference.scheme = previous }
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260 + KeyboardViewController.compositionRowHeight)
    controller.view.layoutIfNeeded()
    let shift = try button("shiftButton", in: controller)
    XCTAssertFalse(shift.isHidden)
    XCTAssertEqual(shift.accessibilityLabel, "切换到英文大写")
    XCTAssertEqual(try button("inputModeSwitchButton", in: controller).isHidden,
                   !controller.needsInputModeSwitchKey)
    shift.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(shift.accessibilityValue, "下一字母")
    XCTAssertEqual(try button("bottomLanguageKey", in: controller).accessibilityValue, "英文输入")
    shift.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(shift.accessibilityValue, "开启")
    shift.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(shift.accessibilityValue, "关闭")
  }

  func testPressFeedbackPreservesLayoutAndResetsAfterInterruption() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 260))
    let controller = UIViewController()
    window.rootViewController = controller
    window.isHidden = false
    defer { window.isHidden = true }
    let key = KeyboardKeyButton(frame: CGRect(x: 20, y: 20, width: 44, height: 48))
    controller.view.addSubview(key)
    let bounds = key.bounds
    let center = key.center
    for _ in 0..<10 {
      key.isHighlighted = true
      XCTAssertEqual(key.bounds, bounds)
      XCTAssertEqual(key.center, center)
      XCTAssertEqual(key.transform.isIdentity, UIAccessibility.isReduceMotionEnabled)
      key.isHighlighted = false
      XCTAssertTrue(key.transform.isIdentity)
    }
    key.isHighlighted = true
    key.isEnabled = false
    XCTAssertTrue(key.transform.isIdentity)
    key.isEnabled = true
    key.isHighlighted = false
    key.isHighlighted = true
    key.removeFromSuperview()
    XCTAssertTrue(key.transform.isIdentity)
    XCTAssertTrue(key.layer.animationKeys()?.isEmpty ?? true)
  }

  func testEmojiShortcutOpensABrowsableCatalogAndInsertsWhatIsTapped() throws {
    let saved = EmojiRecents.stored
    defer { KeyboardFeedbackPreference.defaults.set(saved, forKey: EmojiRecents.key) }
    KeyboardFeedbackPreference.defaults.removeObject(forKey: EmojiRecents.key)

    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)
    try button("emojiShortcut", in: controller).sendActions(for: .primaryActionTriggered)

    let grid = try XCTUnwrap(descendants(controller.view).first {
      $0.accessibilityIdentifier == "emojiGrid"
    } as? UICollectionView)
    // Every Unicode group reaches the panel. Ordering the groups by their rows' sort_order would
    // drop or interleave them -- Symbols spans 1420-1935 and Flags 1644-1913 -- so the catalog
    // names them in order instead, and this is what notices if that list and the data diverge.
    XCTAssertEqual(EmojiCatalog.sections.count, 9)
    XCTAssertTrue(EmojiCatalog.sections.allSatisfy { !$0.emoji.isEmpty })
    XCTAssertEqual(grid.numberOfSections, EmojiCatalog.sections.count)

    let first = try XCTUnwrap(EmojiCatalog.sections.first?.emoji.first)
    grid.delegate?.collectionView?(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
    XCTAssertEqual(EmojiRecents.stored.first, first)

    // Reopening leads with what was just used, so the common case is not a scroll away.
    try button("closeEmojiPicker", in: controller).sendActions(for: .primaryActionTriggered)
    try button("emojiShortcut", in: controller).sendActions(for: .primaryActionTriggered)
    let reopened = try XCTUnwrap(descendants(controller.view).first {
      $0.accessibilityIdentifier == "emojiGrid"
    } as? UICollectionView)
    XCTAssertEqual(reopened.numberOfSections, EmojiCatalog.sections.count + 1)
    XCTAssertEqual(reopened.numberOfItems(inSection: 0), 1)
  }

  func testSchemeNameIsWrittenBackSoTheLegacyFlagCannotKeepResolvingToQuanpin() throws {
    let previous = InputSchemePreference.scheme
    let enabled = InputSchemePreference.enabledSchemes
    defer {
      InputSchemePreference.enabledSchemes = enabled
      InputSchemePreference.scheme = previous
    }
    let defaults = UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
    InputSchemePreference.enabledSchemes = [.quanpin, .nineKey, .shuangpin]
    InputSchemePreference.scheme = .nineKey

    // 名字丢了,只剩那个老布尔。以前这会永远读成全拼 26 键。
    defaults.removeObject(forKey: "chineseInputScheme")
    XCTAssertEqual(InputSchemePreference.scheme, .quanpin)
    // 但它只该发生一次:迁移的结果要写回,否则每次读都在重置。
    XCTAssertEqual(defaults.string(forKey: "chineseInputScheme"), "quanpin")

    InputSchemePreference.scheme = .nineKey
    XCTAssertEqual(InputSchemePreference.scheme, .nineKey)
    XCTAssertEqual(defaults.string(forKey: "chineseInputScheme"), "nineKey")
  }

  func testNineKeySurvivesTheKeyboardBeingTornDownAndRebuilt() throws {
    // 反馈 #419:切走一段时间再回来就变回 26 键。iOS 回收键盘扩展后重新加载它,所以这里
    // 的第二个控制器就是那次重新加载。
    let previous = InputSchemePreference.scheme
    let enabled = InputSchemePreference.enabledSchemes
    defer {
      InputSchemePreference.enabledSchemes = enabled
      InputSchemePreference.scheme = previous
    }
    InputSchemePreference.enabledSchemes = [.quanpin, .nineKey]
    InputSchemePreference.scheme = .quanpin

    let first = KeyboardViewController()
    first.loadViewIfNeeded()
    first.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)
    first.viewWillAppear(false)
    try button("schemeButton", in: first).sendActions(for: .primaryActionTriggered)
    try button("schemeCard-nineKey", in: first).sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(InputSchemePreference.scheme, .nineKey)
    XCTAssertFalse(try XCTUnwrap(button("nineKey6", in: first).superview).isHidden)

    let rebuilt = KeyboardViewController()
    rebuilt.loadViewIfNeeded()
    rebuilt.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)
    rebuilt.viewWillAppear(false)
    rebuilt.view.layoutIfNeeded()
    XCTAssertEqual(try button("schemeButton", in: rebuilt).accessibilityValue, "全拼 9 键")
    XCTAssertFalse(try XCTUnwrap(button("nineKey6", in: rebuilt).superview).isHidden)
  }

  func testSpellingStripReusesItsButtonsBetweenKeystrokes() throws {
    // 只有九键有这条带子,而它每敲一下都把整排按钮销毁重建,量出来是 13.76ms/键 对 26 键的 2ms。
    //
    // The strip still lays the keyboard out again on every keystroke: making that conditional on
    // the strip's own visibility broke the local input modes, which reach their layout through the
    // same call. Reuse is the part that stands, so reuse is what this pins.
    //
    // Timing is not asserted -- the shared CI simulator is too noisy for a millisecond budget.
    let previous = InputSchemePreference.scheme
    let enabled = InputSchemePreference.enabledSchemes
    defer { InputSchemePreference.enabledSchemes = enabled; InputSchemePreference.scheme = previous }
    InputSchemePreference.enabledSchemes = [.quanpin, .nineKey]
    InputSchemePreference.scheme = .nineKey
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 292)
    controller.viewWillAppear(false)
    controller.view.layoutIfNeeded()

    try button("nineKey6", in: controller).sendActions(for: .primaryActionTriggered)
    try button("nineKey4", in: controller).sendActions(for: .primaryActionTriggered)
    let strip = try XCTUnwrap(descendants(controller.view).first {
      $0.accessibilityIdentifier == "nineKeySpellingStrip"
    } as? UIScrollView)
    let first = descendants(strip).compactMap { $0 as? UIButton }.filter { !$0.isHidden }
    XCTAssertFalse(first.isEmpty, "九键应当给出拼音候选")

    try button("nineKey6", in: controller).sendActions(for: .primaryActionTriggered)
    let second = descendants(strip).compactMap { $0 as? UIButton }.filter { !$0.isHidden }
    XCTAssertFalse(second.isEmpty)
    for (before, after) in zip(first, second) {
      XCTAssertTrue(before === after, "拼音候选按钮在两次按键之间被重建了")
    }
    // 文字仍然跟着编码走,复用没有把内容冻住。
    XCTAssertNotNil(descendants(strip).first {
      ($0.accessibilityIdentifier ?? "").hasPrefix("nineKeySpelling_")
    })
  }

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
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
      controller.view.layoutIfNeeded()
      let toolbar = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardShortcutBar" })
      XCTAssertFalse(toolbar.isHidden)
      let brand = try XCTUnwrap(descendants(toolbar).first { $0.accessibilityIdentifier == "keyboardBrandIcon" } as? UIImageView)
      XCTAssertNotNil(brand.image)
      XCTAssertEqual(brand.bounds.width, 24, accuracy: 0.1)
      XCTAssertEqual(brand.bounds.height, 24, accuracy: 0.1)
      let brandSlot = try XCTUnwrap(brand.superview)
      XCTAssertGreaterThanOrEqual(brand.frame.minX, 6)
      XCTAssertGreaterThanOrEqual(brandSlot.bounds.width - brand.frame.maxX, 6)
      XCTAssertLessThan(brand.convert(brand.bounds, to: toolbar).maxX,
                        try button("schemeButton", in: controller).convert(try button("schemeButton", in: controller).bounds, to: toolbar).minX)
      for id in ["layoutShortcut", "schemeButton", "emojiShortcut", "skinShortcut", "moreShortcut", "dismissShortcut"] {
        let control = try button(id, in: controller)
        XCTAssertGreaterThanOrEqual(control.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(control.bounds.height, 38)
      }
      XCTAssertNil(try button("skinShortcut", in: controller).menu)
      // 简繁不再占常驻工具位,改从「更多」里切。
      XCTAssertTrue(try button("replyShortcut", in: controller).isHidden)
      try button("moreShortcut", in: controller).sendActions(for: .primaryActionTriggered)
      let script = try button("moreCard-繁体输出", in: controller)
      XCTAssertEqual(script.accessibilityValue, "已关闭")
      script.sendActions(for: .primaryActionTriggered)
      XCTAssertTrue(ChineseOutputPreference.usesTraditional)
      XCTAssertEqual(try button("moreCard-繁体输出", in: controller).accessibilityValue, "已开启")
      try button("moreCard-繁体输出", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(ChineseOutputPreference.usesTraditional)
      try button("closeMorePicker", in: controller).sendActions(for: .primaryActionTriggered)
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
      // The chip carries the candidate and nothing else: a touch keyboard has no number row, so a
      // leading ordinal is noise that reads as part of the word.
      let chip = try XCTUnwrap(button("candidate-1", in: controller).configuration?.title)
      XCTAssertTrue(chip.contains("你好"))
      XCTAssertFalse(chip.contains(where: \.isNumber), chip)
      XCTAssertEqual(chip, chip.trimmingCharacters(in: .whitespaces), chip)
      XCTAssertEqual(key.convert(key.bounds, to: controller.view), frame)
      try button("nineKeyClear", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      XCTAssertFalse(toolbar.isHidden)
      XCTAssertEqual(key.convert(key.bounds, to: controller.view), frame)
    }
  }

  func testNewCandidatesAndPagesReturnToLeadingCandidate() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for scheme in [ChineseInputScheme.nineKey, .quanpin] {
      InputSchemePreference.scheme = scheme
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 260 + KeyboardViewController.compositionRowHeight)
      func type(_ text: String) throws {
        for character in text {
          let key: UIButton
          if scheme == .nineKey {
            key = try button("nineKey\(character)", in: controller)
          } else {
            key = try XCTUnwrap(descendants(controller.view).first {
              $0.accessibilityLabel == "字母 \(String(character).uppercased())"
            } as? UIButton)
          }
          key.sendActions(for: .primaryActionTriggered)
        }
        controller.view.layoutIfNeeded()
      }
      try type(scheme == .nineKey ? "6" : "n")
      let candidate = try button("candidate-1", in: controller)
      var ancestor = candidate.superview
      while ancestor != nil && !(ancestor is UIScrollView) { ancestor = ancestor?.superview }
      let scroll = try XCTUnwrap(ancestor as? UIScrollView)
      XCTAssertFalse(scroll.delaysContentTouches)
      XCTAssertTrue(scroll.canCancelContentTouches)
      XCTAssertTrue(scroll.touchesShouldCancel(in: candidate))
      XCTAssertGreaterThan(scroll.contentSize.width, scroll.bounds.width + 40)
      scroll.setContentOffset(CGPoint(x: 40, y: 0), animated: false)
      try type(scheme == .nineKey ? "4" : "i")
      XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 0.5)
      let leading = try button("candidate-1", in: controller)
      XCTAssertGreaterThanOrEqual(leading.convert(leading.bounds, to: scroll).minX, 0)

      // The strip shows nine; everything past them is reached by expanding rather than by paging
      // nine at a time, which for a query answering with hundreds left the tail unreachable.
      let expand = try button("expandCandidates", in: controller)
      XCTAssertFalse(expand.isHidden)
      expand.sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      let panel = try XCTUnwrap(
        descendants(controller.view).first { $0.accessibilityIdentifier == "candidatePanel" })
      let chips = descendants(panel).compactMap { $0.accessibilityIdentifier }
        .filter { $0.hasPrefix("panelCandidate-") }
      XCTAssertGreaterThan(chips.count, KeyboardViewController.candidatePageSize)
      let close = try XCTUnwrap(
        descendants(panel).first { $0.accessibilityIdentifier == "closeCandidatePanel" } as? UIButton)
      close.sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      XCTAssertNil(descendants(controller.view).first { $0.accessibilityIdentifier == "candidatePanel" })
    }
  }

  func testKeyLayoutsKeepNineKeyHeight() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for width in [320.0, 414.0] {
      InputSchemePreference.scheme = .nineKey
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
      controller.view.layoutIfNeeded()
      let reference = try button("nineKey6", in: controller).bounds.height
      // Handwriting has a taller canvas, covered by HandwritingTests.
      for scheme in ChineseInputScheme.allCases where scheme != .handwriting {
        InputSchemePreference.scheme = scheme
        controller.viewWillAppear(false)
        for symbols in [false, true] {
          if symbols { try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered) }
          controller.view.layoutIfNeeded()
          XCTAssertEqual(try button("returnKey", in: controller).bounds.height, reference, accuracy: 0.5)
          XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260 + KeyboardViewController.compositionRowHeight)
          if !symbols && [.nineKey, .quanpin].contains(scheme) {
            let selector = try button("schemeButton", in: controller)
            XCTAssertGreaterThanOrEqual(selector.bounds.width, 50)
            XCTAssertNil(selector.configuration?.title)
            XCTAssertNotNil(selector.configuration?.image)
            XCTAssertEqual(selector.accessibilityLabel, "选择输入方案")
            for id in ["layoutShortcut", "emojiShortcut", "skinShortcut", "moreShortcut", "dismissShortcut"] {
              XCTAssertGreaterThanOrEqual(try button(id, in: controller).bounds.width, 44)
            }
            if width == 320 {
              let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
                controller.view.layer.render(in: context.cgContext)
              })
              attachment.name = "Narrow \(scheme.rawValue) keyboard and toolbar"
              attachment.lifetime = .keepAlways
              add(attachment)
            }
          }
          let punctuation = try button("quickPunctuationKey", in: controller)
          XCTAssertEqual(punctuation.isHidden, symbols || [.nineKey, .japaneseNineKey, .handwriting].contains(scheme))
          if !punctuation.isHidden {
            XCTAssertEqual(punctuation.configuration?.title, scheme.isJapanese ? "、" : "，")
            XCTAssertEqual(punctuation.bounds.width, 44, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(try button("spaceKey", in: controller).bounds.width, 79.2)
            XCTAssertEqual(punctuation.menu?.children.count, 7)
          }
          XCTAssertEqual(try button("symbolDeleteKey", in: controller).isHidden, !symbols)
          if !symbols && ![.nineKey, .japaneseNineKey, .handwriting].contains(scheme) {
            let delete = try button("letterDeleteKey", in: controller)
            let shift = try button("shiftButton", in: controller)
            let m = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "字母 M" } as? UIButton)
            XCTAssertEqual(delete.superview, m.superview)
            XCTAssertGreaterThan(delete.frame.minX, m.frame.maxX)
            XCTAssertEqual(delete.bounds.width, 44, accuracy: 0.5)
            XCTAssertEqual(shift.bounds.width, 44, accuracy: 0.5)
            XCTAssertEqual(delete.bounds.height, reference, accuracy: 0.5)
            XCTAssertLessThanOrEqual(delete.convert(delete.bounds, to: controller.view).maxX, width - 4.5)
            for label in ["Q", "A", "Z", "P", "L", "M"] {
              let key = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "字母 \(label)" } as? UIButton)
              XCTAssertEqual(key.bounds.height, reference, accuracy: 0.5)
              let frame = key.convert(key.bounds, to: controller.view)
              XCTAssertGreaterThanOrEqual(frame.minX, 4.5)
              XCTAssertLessThanOrEqual(frame.maxX, controller.view.bounds.width - 4.5, "\(scheme) \(label) frame \(frame)")
            }
          }
          if !symbols && scheme == .japaneseNineKey {
            XCTAssertEqual(try button("japaneseKana0", in: controller).bounds.height, reference, accuracy: 0.5)
          }
          if symbols { try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered) }
        }
      }
    }
  }

  func testLocalModeLayouts() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for scheme in [ChineseInputScheme.nineKey, .shuangpin] {
      InputSchemePreference.scheme = scheme
      for trigger in ["U", "T", "J"] {
        let controller = KeyboardViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260 + KeyboardViewController.compositionRowHeight)
        controller.openLocalInputMode(trigger)
        controller.view.layoutIfNeeded()
        let returnKey = try button("returnKey", in: controller)
        for label in ["Q", "A", "Z", "P", "L", "M"] {
          let key = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "字母 \(label)" } as? UIButton)
          XCTAssertEqual(key.bounds.height, returnKey.bounds.height, accuracy: 0.5)
          XCTAssertGreaterThanOrEqual(key.bounds.height, 44)
          XCTAssertTrue(key.subviews.compactMap { $0 as? UILabel }.filter { $0.font.pointSize == 9 }.allSatisfy { $0.isHidden })
        }
        XCTAssertFalse(try button("exitLocalModeButton", in: controller).isHidden)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
          controller.view.layer.render(in: context.cgContext)
        })
        attachment.name = "Local mode \(scheme) \(trigger)"
        attachment.lifetime = .keepAlways
        add(attachment)
        try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
        controller.view.layoutIfNeeded()
        try button("exitLocalModeButton", in: controller).sendActions(for: .primaryActionTriggered)
        controller.view.layoutIfNeeded()
        XCTAssertTrue(try button("exitLocalModeButton", in: controller).isHidden)
        XCTAssertFalse(try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardShortcutBar" }).isHidden)
        XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, scheme.title)
        XCTAssertEqual(try XCTUnwrap(button("nineKey6", in: controller).superview).isHidden, scheme != .nineKey)
      }
    }
  }

  func testJapaneseSentenceConversionAndMemory() throws {
    func residentBytes() -> UInt64 {
      var info = mach_task_basic_info_data_t()
      var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
      let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
      }
      return result == KERN_SUCCESS ? info.resident_size : 0
    }
    func footprint() -> UInt64 {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
      let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
    let footprintBefore = footprint()
    let before = residentBytes()
    let bridge = MetasequoiaInputSessionBridge()
    _ = bridge.switchToJapanese()
    var snapshot = bridge.cancel()
    for letter in "watashihanihonjindesu" { snapshot = bridge.handleCharacter(String(letter)) }
    print("Japanese sentence candidates: \(snapshot.candidates.prefix(5))")
    XCTAssertTrue(snapshot.candidates.contains { $0.contains("日本人") && $0.contains("です") })
    XCTAssertNil(snapshot.diagnosticText)
    let after = residentBytes()
    let footprintAfter = footprint()
    print("Japanese physical footprint: before=\(footprintBefore), after=\(footprintAfter) bytes")
    XCTAssertGreaterThan(footprintBefore, 0)
    XCTAssertLessThan(footprintAfter > footprintBefore ? footprintAfter - footprintBefore : 0, 16 * 1024 * 1024,
      "The keyboard must not copy the full sentence model into private memory")
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print("Japanese model memory: before=\(before), after=\(after), peak=\(usage.ru_maxrss) bytes")
    let index = try XCTUnwrap(snapshot.candidates.firstIndex { $0.contains("日本人") && $0.contains("です") })
    XCTAssertEqual(bridge.selectCandidate(at: UInt(index)).commitText, snapshot.candidates[index])
    _ = bridge.switch(toShuangpin: false)
    _ = bridge.openLocalMode("R")
    for letter in "nihon" { snapshot = bridge.handleCharacter(String(letter)) }
    XCTAssertTrue(snapshot.candidates.contains("日本"))
    _ = bridge.cancel()
    XCTAssertFalse(bridge.isInLocalMode)
  }

  func testJapaneseSentenceCandidateStrip() throws {
    let previousScheme = InputSchemePreference.scheme
    let previousScript = ChineseOutputPreference.usesTraditional
    InputSchemePreference.scheme = .japanese
    ChineseOutputPreference.usesTraditional = true
    defer {
      InputSchemePreference.scheme = previousScheme
      ChineseOutputPreference.usesTraditional = previousScript
    }
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260 + KeyboardViewController.compositionRowHeight)
    for letter in "watashihanihonjindesu" {
      let key = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == "字母 \(String(letter).uppercased())" } as? UIButton)
      key.sendActions(for: .primaryActionTriggered)
    }
    controller.view.layoutIfNeeded()
    XCTAssertTrue(try XCTUnwrap(button("candidate-1", in: controller).configuration?.title).contains("私は日本人です"))
    let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
      controller.view.layer.render(in: context.cgContext)
    })
    attachment.name = "Japanese full sentence keyboard"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testAdditionalShuangpinProfilesAndKeyHints() throws {
    let bridge = MetasequoiaInputSessionBridge()
    for (profile, input) in [("ziranma", "nihk"), ("microsoft", "nihk"), ("shoudao", "nihd"), ("xiaohe", "nihc")] {
      _ = bridge.switch(toShuangpinProfile: profile)
      var snapshot = bridge.cancel()
      for letter in input { snapshot = bridge.handleCharacter(String(letter)) }
      XCTAssertTrue(snapshot.candidates.contains("你好"), profile)
      _ = bridge.cancel()
    }
    _ = bridge.switch(toShuangpinProfile: "microsoft")
    XCTAssertTrue(bridge.shuangpinKeyHints()[";"]?.contains("ing") == true)
    _ = bridge.handleCharacter("n")
    XCTAssertFalse(bridge.handleCharacter(";").candidates.isEmpty)
    _ = bridge.cancel()
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for scheme in [ChineseInputScheme.wubi, .japanese, .microsoft] {
      InputSchemePreference.scheme = scheme
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260 + KeyboardViewController.compositionRowHeight)
      controller.view.layoutIfNeeded()
      XCTAssertEqual(try button("microsoftFinalKey", in: controller).isHidden, scheme != .microsoft)
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
        controller.view.layer.render(in: context.cgContext)
      })
      attachment.name = "Keyboard scheme \(scheme)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  // An unfinished wubi code answers with the codes it can still become, so the strip has to say
  // which keys single each candidate out. The code rides along the snapshot; the strip draws its
  // tail past what has been typed.
  func testWubiCandidatesCarryAndShowTheCodeLeftToType() throws {
    let bridge = MetasequoiaInputSessionBridge()
    _ = bridge.switchToWubi()
    _ = bridge.handleCharacter("w")
    let snapshot = bridge.handleCharacter("q")
    XCTAssertEqual(snapshot.candidateCodes.count, snapshot.candidates.count)
    let leading = try XCTUnwrap(snapshot.candidateCodes.first)
    XCTAssertEqual(leading, "wq", "The code that was typed in full did not lead the list.")
    XCTAssertTrue(
      snapshot.candidateCodes.contains { $0.count > 2 && $0.hasPrefix("wq") },
      "The snapshot carried no candidate reached by a longer code.")
    _ = bridge.cancel()

    XCTAssertEqual(WubiCodeHintPreference.hint(code: "wqb", typed: "wq"), "b")
    XCTAssertEqual(WubiCodeHintPreference.hint(code: "wq", typed: "wq"), "")
    XCTAssertEqual(WubiCodeHintPreference.hint(code: "wqb", typed: ""), "")
    // What the mixed-pinyin fallback produces: keyed by spelling, and those letters lead nowhere in
    // wubi, so the candidate is left unannotated.
    XCTAssertEqual(WubiCodeHintPreference.hint(code: "ni'hao", typed: "nihao"), "")

    let previous = InputSchemePreference.scheme
    let previousHint = WubiCodeHintPreference.isEnabled
    defer {
      InputSchemePreference.scheme = previous
      WubiCodeHintPreference.isEnabled = previousHint
    }
    XCTAssertTrue(previousHint, "The wubi code hint did not ship on.")
    InputSchemePreference.scheme = .wubi
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    func type(_ code: String) throws {
      for character in code {
        let key = try XCTUnwrap(descendants(controller.view).first {
          $0.accessibilityLabel == "字母 \(String(character).uppercased())"
        } as? UIButton)
        key.sendActions(for: .primaryActionTriggered)
      }
    }
    try type("wq")
    let annotated = try descendants(controller.view).compactMap { $0 as? UIButton }.filter {
      ($0.accessibilityIdentifier ?? "").hasPrefix("candidate-")
    }
    XCTAssertFalse(annotated.isEmpty, "Typing a wubi code produced no candidates.")
    XCTAssertTrue(
      annotated.contains { ($0.accessibilityLabel ?? "").contains("还需输入") },
      "No candidate on the strip said which keys were left to press.")
  }

  func testAdditionalEngineSchemesAndLocalProviders() throws {
    let bridge = MetasequoiaInputSessionBridge()
    _ = bridge.switchToWubi()
    var snapshot = bridge.handleCharacter("a")
    XCTAssertTrue(snapshot.candidates.contains("工"))
    XCTAssertEqual(bridge.selectCandidate(at: UInt(snapshot.candidates.firstIndex(of: "工")!)).commitText, "工")
    _ = bridge.switchToJapanese()
    for letter in "nihon" { snapshot = bridge.handleCharacter(String(letter)) }
    XCTAssertTrue(snapshot.candidates.contains("にほん"))
    XCTAssertTrue(snapshot.candidates.contains("ニホン"))
    _ = bridge.cancel()
    snapshot = bridge.handleCharacter("a")
    XCTAssertTrue(snapshot.candidates.contains("亜"))
    _ = bridge.cancel()
    _ = bridge.switch(toShuangpin: false)
    for letter in "nihao" { snapshot = bridge.handleCharacter(String(letter)) }
    XCTAssertTrue(snapshot.candidates.contains("你好"))
    _ = bridge.cancel()
    for (trigger, input) in [("K", "yyds"), ("Y", "hello"), ("E", "smile"), ("M", "kaixin"), ("R", "nihon")] {
      _ = bridge.openLocalMode(trigger)
      XCTAssertTrue(bridge.isInLocalMode)
      for letter in input { snapshot = bridge.handleCharacter(String(letter)) }
      XCTAssertNil(snapshot.diagnosticText, "Provider \(trigger)")
      XCTAssertFalse(snapshot.candidates.isEmpty, "Provider \(trigger)")
      if trigger == "Y" { XCTAssertGreaterThan(snapshot.candidates.count, 1) }
      if trigger == "K" { XCTAssertTrue(snapshot.candidates.contains("永远滴神")) }
      _ = bridge.cancel()
    }
  }

  func testNineKeyInputAndLayoutSwitches() throws {
    let previous = InputSchemePreference.scheme
    InputSchemePreference.scheme = .nineKey
    defer { InputSchemePreference.scheme = previous }
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 216 + KeyboardViewController.compositionRowHeight)
    controller.view.layoutIfNeeded()

    let nine = try button("nineKey6", in: controller)
    XCTAssertFalse(try XCTUnwrap(nine.superview).isHidden)
    try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(descendants(controller.view).filter { $0.accessibilityIdentifier?.hasPrefix("schemeCard-") == true }.count, InputSchemePreference.enabledSchemes.count)
    try button("closeSchemePicker", in: controller).sendActions(for: .primaryActionTriggered)
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

    // The digit layer keeps this grid rather than swapping in the 26-key rows, so the container stays
    // visible and only the faces change. testNineKeyDigitLayerKeepsTheGridInsteadOfTheTwentySixKeyRows
    // owns that contract; this case asserted the container hid, which was true before the digit layer
    // shared the grid and has contradicted the other case since.
    try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(try XCTUnwrap(nine.superview).isHidden)
    XCTAssertEqual(nine.configuration?.title, "6")
    try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(try XCTUnwrap(nine.superview).isHidden)
    XCTAssertEqual(nine.configuration?.title, "MNO")
    try button("bottomLanguageKey", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(try XCTUnwrap(nine.superview).isHidden)
    try button("bottomLanguageKey", in: controller).sendActions(for: .primaryActionTriggered)
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
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260 + KeyboardViewController.compositionRowHeight)
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
          // The chips are reused rather than rebuilt, so an emptied strip hides them instead of
          // removing them. What matters is that none of them is showing.
          XCTAssertTrue(descendants(controller.view).allSatisfy {
            $0.accessibilityIdentifier?.hasPrefix("candidate-") != true || $0.isHidden
          })
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
