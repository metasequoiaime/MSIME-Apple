import XCTest
import UIKit
import Darwin

@MainActor
final class NineKeyKeyboardTests: XCTestCase {
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
    XCTAssertEqual(try button("scriptShortcut", in: controller).accessibilityIdentifier, "scriptShortcut")
    XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "replyKeyboard" })
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
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      let ordinary = UUID()
      controller.applyInputContext(keyboardType: .default, documentIdentifier: ordinary)
      for type in [UIKeyboardType.asciiCapable, .emailAddress, .URL] {
        // Any preedit left after a missed focus callback must not enter the new field.
        try button("nineKey6", in: controller).sendActions(for: .primaryActionTriggered)
        let field = UUID()
        controller.applyInputContext(keyboardType: type, documentIdentifier: field)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(try button("languageModeButton", in: controller).accessibilityValue, "英文输入")
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
        XCTAssertEqual(try button("languageModeButton", in: controller).accessibilityValue, "中文输入")
        XCTAssertFalse(try XCTUnwrap(button("nineKey6", in: controller).superview).isHidden)
        XCTAssertEqual(try button("schemeButton", in: controller).accessibilityValue, "全拼 9 键")
        XCTAssertEqual(controller.view.bounds.height, 260)
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
      try button("languageModeButton", in: controller).sendActions(for: .primaryActionTriggered)
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
      let candidate = try button("candidate-1", in: controller)
      XCTAssertEqual(candidate.menu?.children.map(\.title), ["优先显示", "固定到首位", "取消固定", "删除词条…"])
      XCTAssertEqual((candidate.menu?.children.last as? UIMenu)?.children.first?.title, "确认删除此词条")
    }
  }

  func testSkinCardsPreviewAndApplyWithoutChangingKeyboardHeight() throws {
    let previous = KeyboardSkinPreference.selected
    defer { KeyboardFeedbackPreference.defaults.set(previous.rawValue, forKey: KeyboardSkinPreference.key) }
    for width in [320.0, 414.0] {
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      controller.view.layoutIfNeeded()
      try button("skinShortcut", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      let picker = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardSkinPicker" })
      XCTAssertEqual(picker.bounds.height, 260)
      for skin in KeyboardSkin.allCases {
        let card = try button("skinCard-\(skin.rawValue)", in: controller)
        XCTAssertGreaterThan(card.bounds.width, 140)
        XCTAssertEqual(card.bounds.height, 100)
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
      XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260)
      try button("skinShortcut", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertEqual(try button("skinCard-ocean", in: controller).accessibilityValue, "已选中")
      try button("closeSkinPicker", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "keyboardSkinPicker" })
    }
  }

  func testBrandOpensMoreCardsAndUpdatesFeedbackState() throws {
    let previous = KeyboardFeedbackPreference.soundEnabled
    defer { KeyboardFeedbackPreference.defaults.set(previous, forKey: KeyboardFeedbackPreference.soundKey) }
    for width in [320.0, 414.0] {
      KeyboardFeedbackPreference.defaults.set(true, forKey: KeyboardFeedbackPreference.soundKey)
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      controller.view.layoutIfNeeded()
      let toolbar = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardShortcutBar" } as? UIStackView)
      let more = try button("moreShortcut", in: controller)
      XCTAssertTrue(toolbar.arrangedSubviews.first === more)
      XCTAssertNil(more.menu)
      XCTAssertNotNil(descendants(more).first { $0.accessibilityIdentifier == "keyboardBrandIcon" })
      more.sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      let panel = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardMorePicker" })
      XCTAssertEqual(panel.bounds.height, 260)
      for title in ["剪贴板历史", "AI 润色", "语音结果", "按键音", "按键振动", "日期时间", "Unicode 码点"] {
        let card = try button("moreCard-" + title, in: controller)
        XCTAssertGreaterThan(card.bounds.width, 140)
        XCTAssertEqual(card.bounds.height, 100)
      }
      let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
        controller.view.layer.render(in: context.cgContext)
      })
      attachment.name = "More cards \(Int(width))pt"
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
      XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260)
    }
  }

  func testSchemeCardsSelectAndKeepKeyboardHeight() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for width in [320.0, 414.0] {
      InputSchemePreference.scheme = .nineKey
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      controller.view.layoutIfNeeded()
      try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      let picker = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "keyboardSchemePicker" })
      XCTAssertEqual(picker.bounds.height, 260)
      for scheme in ChineseInputScheme.allCases {
        let card = try button("schemeCard-\(scheme.rawValue)", in: controller)
        XCTAssertGreaterThan(card.bounds.width, 140)
        XCTAssertEqual(card.bounds.height, 100)
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
      XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260)
      try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertEqual(try button("schemeCard-quanpin", in: controller).accessibilityValue, "已选中")
      try button("closeSchemePicker", in: controller).sendActions(for: .primaryActionTriggered)
      XCTAssertFalse(descendants(controller.view).contains { $0.accessibilityIdentifier == "keyboardSchemePicker" })
      XCTAssertEqual(InputSchemePreference.scheme, .quanpin)
    }
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
    controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260)
    controller.view.layoutIfNeeded()
    let shift = try button("shiftButton", in: controller)
    XCTAssertFalse(shift.isHidden)
    XCTAssertEqual(shift.accessibilityLabel, "切换到英文大写")
    XCTAssertEqual(try button("inputModeSwitchButton", in: controller).isHidden,
                   !controller.needsInputModeSwitchKey)
    shift.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(shift.accessibilityValue, "下一字母")
    XCTAssertEqual(try button("languageModeButton", in: controller).accessibilityValue, "英文输入")
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
      let brand = try XCTUnwrap(descendants(toolbar).first { $0.accessibilityIdentifier == "keyboardBrandIcon" } as? UIImageView)
      XCTAssertNotNil(brand.image)
      XCTAssertEqual(brand.bounds.width, 24, accuracy: 0.1)
      XCTAssertEqual(brand.bounds.height, 24, accuracy: 0.1)
      let brandSlot = try XCTUnwrap(brand.superview)
      XCTAssertGreaterThanOrEqual(brand.frame.minX, 6)
      XCTAssertGreaterThanOrEqual(brandSlot.bounds.width - brand.frame.maxX, 6)
      XCTAssertLessThan(brand.convert(brand.bounds, to: toolbar).maxX,
                        try button("languageModeButton", in: controller).convert(try button("languageModeButton", in: controller).bounds, to: toolbar).minX)
      for id in ["languageModeButton", "schemeButton", "scriptShortcut", "skinShortcut", "moreShortcut", "dismissShortcut"] {
        let control = try button(id, in: controller)
        XCTAssertGreaterThanOrEqual(control.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(control.bounds.height, 38)
      }
      XCTAssertNil(try button("skinShortcut", in: controller).menu)
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

  func testNewCandidatesAndPagesReturnToLeadingCandidate() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for scheme in [ChineseInputScheme.nineKey, .quanpin] {
      InputSchemePreference.scheme = scheme
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 260)
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
      let next = try button("nextCandidatePage", in: controller)
      XCTAssertFalse(next.isHidden)
      scroll.setContentOffset(CGPoint(x: 40, y: 0), animated: false)
      next.sendActions(for: .primaryActionTriggered)
      controller.view.layoutIfNeeded()
      XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 0.5)
      let leading = try button("candidate-1", in: controller)
      XCTAssertGreaterThanOrEqual(leading.convert(leading.bounds, to: scroll).minX, 0)
    }
  }

  func testAllLayoutsKeepNineKeyHeight() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }
    for width in [320.0, 414.0] {
      InputSchemePreference.scheme = .nineKey
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      controller.view.layoutIfNeeded()
      let reference = try button("nineKey6", in: controller).bounds.height
      for scheme in ChineseInputScheme.allCases {
        InputSchemePreference.scheme = scheme
        controller.viewWillAppear(false)
        for symbols in [false, true] {
          if symbols { try button("layoutToggleButton", in: controller).sendActions(for: .primaryActionTriggered) }
          controller.view.layoutIfNeeded()
          XCTAssertEqual(try button("returnKey", in: controller).bounds.height, reference, accuracy: 0.5)
          XCTAssertEqual(controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant, 260)
          if !symbols && [.nineKey, .quanpin].contains(scheme) {
            let selector = try button("schemeButton", in: controller)
            XCTAssertGreaterThanOrEqual(selector.bounds.width, 50)
            let label = try XCTUnwrap(selector.titleLabel)
            let insets = try XCTUnwrap(selector.configuration).contentInsets
            XCTAssertLessThanOrEqual(label.intrinsicContentSize.width + insets.leading + insets.trailing, selector.bounds.width)
            for id in ["languageModeButton", "scriptShortcut", "skinShortcut", "moreShortcut", "dismissShortcut"] {
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
          XCTAssertEqual(punctuation.isHidden, symbols || scheme == .nineKey)
          if !punctuation.isHidden {
            XCTAssertEqual(punctuation.configuration?.title, scheme == .japanese ? "、" : "，")
            XCTAssertEqual(punctuation.bounds.width, 44, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(try button("spaceKey", in: controller).bounds.width, 79.2)
            XCTAssertEqual(punctuation.menu?.children.count, 7)
          }
          XCTAssertEqual(try button("symbolDeleteKey", in: controller).isHidden, !symbols)
          if !symbols && scheme != .nineKey {
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
        controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260)
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
    controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260)
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
      controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260)
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
    controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 216)
    controller.view.layoutIfNeeded()

    let nine = try button("nineKey6", in: controller)
    XCTAssertFalse(try XCTUnwrap(nine.superview).isHidden)
    try button("schemeButton", in: controller).sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(descendants(controller.view).filter { $0.accessibilityIdentifier?.hasPrefix("schemeCard-") == true }.count, ChineseInputScheme.allCases.count)
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
