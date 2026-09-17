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
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 414, height: 260 + KeyboardViewController.stripExtraHeight)
    controller.view.layoutIfNeeded()
    let panel = try XCTUnwrap(nodes(controller.view).compactMap { $0 as? JapaneseNineKeyView }.first)
    XCTAssertFalse(panel.isHidden)
    panel.select(4, direction: 1) // に
    panel.select(5, direction: 4) // ほ
    panel.select(9, direction: 2) // ん
    let first = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "candidate-1" } as? UIButton)
    // 只看第一行:开着释义时格子下面还有一行预留给释义的位置。
    let title = first.configuration?.title ?? ""
    XCTAssertTrue(title.split(separator: "\n").first?.hasSuffix("日本") == true, title)
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
        XCTAssertTrue(snapshot?.candidates.contains(kana) == true, "\(input) → \(kana): \(snapshot?.candidates ?? [])")
      }
    }
    let previous = KeyboardLayoutPreference.selected
    defer { KeyboardLayoutPreference.selected = previous }
    for layout in KeyboardLayoutPreset.allCases {
      KeyboardLayoutPreference.selected = layout
      for width in [320.0, 414.0] {
        let panel = JapaneseNineKeyView(makeKey: { title, _, action in
          var config = UIButton.Configuration.plain(); config.title = title
          return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        }, makeDelete: {
          var config = UIButton.Configuration.plain(); config.title = "⌫"
          return UIButton(configuration: config)
        })
        // 四行网格加右侧删除键。The grid used to be three rows with わ and 小゛゜ stacked in the side
        // column; the fourth row is where every Japanese keyboard puts 小゛゜, わ and 、。
        panel.frame = CGRect(x: 0, y: 0, width: width, height: 235)
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
  func testModeColumnGivesTheScriptKeyTwoRowsOfThree() throws {
    // 左列铺满网格的四行:123 一格、^_^ 一格、英 两格 —— 实机就是这个比例,三个键平分整列会让每个变成
    // 4/3 行高,和右列、和假名网格全对不上。
    let modes = ["123", "^_^", "英"].map { (title: String) -> UIButton in
      var config = UIButton.Configuration.plain(); config.title = title
      return UIButton(configuration: config)
    }
    let panel = JapaneseNineKeyView(makeKey: { title, _, action in
      var config = UIButton.Configuration.plain(); config.title = title
      return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }, makeDelete: {
      var config = UIButton.Configuration.plain(); config.title = "⌫"
      return UIButton(configuration: config)
    }, modeKeys: modes)
    panel.frame = CGRect(x: 0, y: 0, width: 414, height: 235)
    panel.applyLayout(); panel.layoutIfNeeded()

    let single = modes[0].bounds.height
    XCTAssertGreaterThan(single, 40, "模式键太矮")
    XCTAssertEqual(modes[1].bounds.height, single, accuracy: 1, "^_^ 应当和 123 一样高")
    // 两格 = 两行加它们之间的那道缝。
    XCTAssertEqual(modes[2].bounds.height, single * 2 + 7, accuracy: 1.5, "英 应当跨两格")

    // 三个键连同缝隙正好填满整列,没有多余空当。
    //
    // 容差按键数给,不是一个拍脑袋的常数:一格的理想高度带半点小数(列高 235 时是 53.5),而布局把每个键
    // 取到整点,于是每个键差不到一点,三个键累加起来能到两点多。钉死到 1.5 会让这条用例在某些 iOS 版本上
    // 红,而它想问的「有没有多余空当」并没有被破坏 —— 真正会破坏它的是漏掉一道缝或者某个键没参与分配,
    // 那种错是七点起步,这个容差拦得住。
    let column = try XCTUnwrap(nodes(panel).first { $0.accessibilityIdentifier == "japaneseModeColumn" })
    let used = modes.map { $0.bounds.height }.reduce(0, +) + 7 * 2
    XCTAssertEqual(used, column.bounds.height, accuracy: Double(modes.count), "左列应当被填满")
  }

  func testDigitLayerKeepsTheSameThreeColumnGrid() throws {
    var inserted: [String] = []
    let panel = JapaneseNineKeyView(makeKey: { title, _, action in
      var config = UIButton.Configuration.plain(); config.title = title
      return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }, makeDelete: {
      var config = UIButton.Configuration.plain(); config.title = "⌫"
      return UIButton(configuration: config)
    })
    panel.onSymbol = { inserted.append($0) }
    panel.frame = CGRect(x: 0, y: 0, width: 414, height: 235)
    panel.applyLayout(); panel.layoutIfNeeded()
    let kanaButtons = { self.nodes(panel).compactMap { $0 as? UIButton }
      .filter { ($0.accessibilityIdentifier ?? "").hasPrefix("japaneseKana") } }
    let before = kanaButtons().count

    panel.setDigits(true)
    panel.layoutIfNeeded()
    XCTAssertEqual(kanaButtons().count, before, "数字层不该换掉键盘,格子数应当不变")
    let faces = kanaButtons().compactMap { $0.configuration?.title }
    for digit in ["1", "5", "9", "0"] {
      XCTAssertTrue(faces.contains(digit), "数字层上没有 \(digit)")
    }
    // 三列:每一行最多三个格子,不能变成二十六键那种十列。
    let columns = Set(kanaButtons().map { $0.convert($0.bounds, to: panel).minX.rounded() })
    XCTAssertEqual(columns.count, 3, "数字层应当还是三列")

    panel.select(0, direction: 0)
    XCTAssertEqual(inserted, ["1"], "数字层的键应当直接上屏,不走罗马字转换")

    panel.setDigits(false)
    panel.layoutIfNeeded()
    let kana = kanaButtons().compactMap { $0.configuration?.title }
    XCTAssertTrue(kana.contains("あ"), "切回来之后键面应当恢复成假名")
  }

  func testVariantKeyIsDisabledUntilThereIsAKanaToModify() throws {
    let panel = JapaneseNineKeyView(makeKey: { title, _, action in
      var config = UIButton.Configuration.plain(); config.title = title
      let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
      return button
    }, makeDelete: {
      var config = UIButton.Configuration.plain(); config.title = "⌫"
      return UIButton(configuration: config)
    })
    let variants = nodes(panel).compactMap { $0 as? UIButton }
      .first { $0.accessibilityIdentifier == "japaneseVariants" }
    let key = try XCTUnwrap(variants, "没有找到 小゛゜ 键")
    XCTAssertFalse(key.isEnabled, "没组字时 小゛゜ 无事可做,应当是灰的")
    panel.setComposing(true)
    XCTAssertTrue(key.isEnabled)
    panel.setComposing(false)
    XCTAssertFalse(key.isEnabled)
  }

  func testExpandedCandidatesStayOnOneLineAndInsideTheirRow() throws {
    // 全屏候选面板排版乱且候选在 chip 内换行。The chip never set a line break mode, so a long
    // candidate wrapped -- and a wrapping title measures at its narrowest under a compressed fit,
    // so every chip was measured far thinner than it draws and each row was handed more than fit.
    let candidates = ["日本", "二本", "にほん", "ニホン", "日本語教育振興協会", "あ",
                      "とてもながいこうほごがここにはいります", "本", "ほん", "ホン", "翻", "反"]
    for width in [320.0, 414.0] {
      let panel = KeyboardCandidatePanelView(
        candidates: candidates, preedit: "にほん", display: { $0 }, onSelect: { _ in }, onClose: {})
      panel.frame = CGRect(x: 0, y: 0, width: width, height: 260)
      panel.layoutIfNeeded()
      let chips = nodes(panel).compactMap { $0 as? UIButton }
        .filter { ($0.accessibilityIdentifier ?? "").hasPrefix("panelCandidate-") }
      XCTAssertEqual(chips.count, candidates.count, "候选没有全部铺出来")
      guard let tallest = chips.map({ $0.bounds.height }).max(),
            let shortest = chips.map({ $0.bounds.height }).min() else { return XCTFail("没有候选") }
      // 一行的 chip 高度应当一致;有谁换行了,它就会比别人高出一整行。
      XCTAssertEqual(tallest, shortest, accuracy: 1, "有候选在 chip 内换行了")
      for chip in chips {
        let frame = chip.convert(chip.bounds, to: panel)
        XCTAssertLessThanOrEqual(frame.maxX, width + 0.5, "候选溢出了面板宽度")
        XCTAssertGreaterThanOrEqual(frame.minX, -0.5)
      }
    }
  }

  private func nodes(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { nodes($0) } }
}
