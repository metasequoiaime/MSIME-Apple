import XCTest
import UIKit

@MainActor
final class KeyboardEmojiCatalogTests: XCTestCase {
  private var savedRecents: Any?

  override func setUp() {
    super.setUp()
    savedRecents = KeyboardFeedbackPreference.defaults.object(forKey: KeyboardEmojiRecents.key)
    KeyboardFeedbackPreference.defaults.removeObject(forKey: KeyboardEmojiRecents.key)
  }

  override func tearDown() {
    if let savedRecents {
      KeyboardFeedbackPreference.defaults.set(savedRecents, forKey: KeyboardEmojiRecents.key)
    } else {
      KeyboardFeedbackPreference.defaults.removeObject(forKey: KeyboardEmojiRecents.key)
    }
    super.tearDown()
  }

  func testCategoryOrderPageValidationAndBounds() throws {
    XCTAssertEqual(KeyboardEmojiCatalog.categories.map(\.title),
                   ["笑脸", "人物", "动物", "食物", "旅行", "活动", "物品", "符号", "旗帜"])
    XCTAssertEqual(KeyboardEmojiCatalog.columns, 8)
    let category = try XCTUnwrap(KeyboardEmojiCatalog.categories.first)
    let value: [String: Any] = [
      "items": [["text": "😀", "annotation": "fixture", "group": category.group]],
      "next_offset": 64,
      "complete": false,
    ]
    XCTAssertEqual(
      try KeyboardEmojiCatalog.decodePage(value, category: category, requestedOffset: 0),
      KeyboardEmojiCatalog.Page(items: [
        .init(text: "😀", annotation: "fixture", group: category.group),
      ], nextOffset: 64, complete: false))

    var invalid = value
    invalid["next_offset"] = 0
    XCTAssertThrowsError(
      try KeyboardEmojiCatalog.decodePage(invalid, category: category, requestedOffset: 0))
    invalid = value
    invalid["items"] = [["text": "😀", "annotation": "fixture", "group": "wrong"]]
    XCTAssertThrowsError(
      try KeyboardEmojiCatalog.decodePage(invalid, category: category, requestedOffset: 0))
    invalid = value
    invalid["items"] = [["text": "", "annotation": "fixture", "group": category.group]]
    XCTAssertThrowsError(
      try KeyboardEmojiCatalog.decodePage(invalid, category: category, requestedOffset: 0))
  }

  func testRecentsAreDeduplicatedValidatedAndBounded() {
    let oversized = String(repeating: "x", count: 33)
    let values = ["😀", "😀", "", oversized, "🌲"]
      + (0..<30).map { "fixture-\($0)" }
    let normalized = KeyboardEmojiRecents.normalize(values)
    XCTAssertEqual(Array(normalized.prefix(2)), ["😀", "🌲"])
    XCTAssertEqual(normalized.count, KeyboardEmojiCatalog.recentLimit)

    for value in normalized { KeyboardEmojiRecents.record(value) }
    KeyboardEmojiRecents.record("😀")
    XCTAssertEqual(KeyboardEmojiRecents.stored.first, "😀")
    XCTAssertEqual(KeyboardEmojiRecents.stored.count, KeyboardEmojiCatalog.recentLimit)
  }

  func testSharedBridgeReadsVerifiedPackagedCatalog() throws {
    let state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-emoji-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: state) }
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    let resources = try XCTUnwrap(bridge.candidateGlossResources())
    let category = try XCTUnwrap(KeyboardEmojiCatalog.categories.first)
    let page = try KeyboardEmojiCatalog.loadPage(
      resources: resources, category: category, offset: 0)
    XCTAssertFalse(page.items.isEmpty)
    XCTAssertTrue(page.items.allSatisfy { $0.group == category.group })
    XCTAssertGreaterThan(page.nextOffset, 0)
  }

  func testSymbolParentsAndPagesAreValidatedAndDeduplicated() throws {
    XCTAssertEqual(try KeyboardEmojiCatalog.decodeSymbolParents(["symbol_groups": [
      ["parent": "Math", "title": "Operators"],
      ["parent": "Math", "title": "Fractions"],
      ["parent": "", "title": "Empty"],
      ["parent": "Hearts", "title": "Hearts"],
    ]]), ["Math", "Hearts"])
    XCTAssertThrowsError(try KeyboardEmojiCatalog.decodeSymbolParents(["items": []]))

    var offsets: [Int] = []
    let symbols = try KeyboardEmojiCatalog.collectSymbols { offset in
      offsets.append(offset)
      return offset == 0
        ? ["items": [["text": "+"], ["text": "−"]], "next_offset": 2, "complete": false]
        : ["items": [["text": "−"], ["text": "×"]], "next_offset": 4, "complete": true]
    }
    XCTAssertEqual(offsets, [0, 2])
    XCTAssertEqual(symbols, ["+", "−", "×"], "一个符号挂在两个子组下只出现一次")
    XCTAssertThrowsError(try KeyboardEmojiCatalog.collectSymbols { _ in
      ["items": [["text": "+"]], "next_offset": 0, "complete": false]
    }, "游标不前进时不能死循环")
    XCTAssertThrowsError(try KeyboardEmojiCatalog.collectSymbols { _ in
      ["items": [["text": ""]], "next_offset": 1, "complete": true]
    })
  }

  func testSharedBridgeReadsPackagedSymbolCatalog() throws {
    let state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-symbol-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: state) }
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    let resources = try XCTUnwrap(bridge.candidateGlossResources())
    let parents = try KeyboardEmojiCatalog.symbolParents(resources: resources)
    XCTAssertTrue(parents.contains("Punctuation"))
    XCTAssertTrue(parents.contains("Letters"))
    for parent in parents {
      XCTAssertNotNil(KeyboardEmojiCatalog.symbolParentTitles[parent], "\(parent) 要有中文标题")
    }
    let letters = try KeyboardEmojiCatalog.loadSymbols(resources: resources, parent: "Letters")
    XCTAssertGreaterThan(letters.count, 255, "最大的一类要翻过不止一页")
    XCTAssertEqual(Set(letters).count, letters.count)
  }

  func testSymbolPanelAppendsCatalogCategoriesAndLoadsThemOffTheMainThread() async throws {
    let panel = KeyboardSymbolPanelView(
      catalog: .init(parents: { ["Math", "Unlisted"] }, symbols: { parent in
        XCTAssertFalse(Thread.isMainThread)
        return parent == "Math" ? ["∑", "∞"] : []
      }),
      onInsert: { _ in }, onDelete: {}, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
    panel.layoutIfNeeded()
    let fixed = KeyboardSymbolPanelView.categories.count
    XCTAssertEqual(panel.categoryCount, fixed + 2)
    XCTAssertEqual(try button("symbolCategory_\(fixed)", in: panel).title(for: .normal), "数学")
    XCTAssertEqual(try button("symbolCategory_\(fixed + 1)", in: panel).title(for: .normal), "Unlisted",
                   "目录以后新增的类别按原名显示")

    try button("symbolCategory_\(fixed)", in: panel).sendActions(for: .primaryActionTriggered)
    for _ in 0..<100 where descendants(panel).first(where: { $0.accessibilityIdentifier == "symbolKey_∑" }) == nil {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertNotNil(descendants(panel).first { $0.accessibilityIdentifier == "symbolKey_∞" })

    let unreadable = KeyboardSymbolPanelView(
      catalog: .init(parents: { throw KeyboardEmojiCatalogError.invalidPage }, symbols: { _ in [] }),
      onInsert: { _ in }, onDelete: {}, onClose: {})
    XCTAssertEqual(unreadable.categoryCount, fixed, "目录读不出来时手机常用的几类照常可用")
  }

  func testPickerLoadsInBackgroundAndRoutesInsertDeleteAndClose() async throws {
    let category = try XCTUnwrap(KeyboardEmojiCatalog.categories.first)
    let changed = expectation(description: "initial state and loaded page")
    changed.expectedFulfillmentCount = 2
    var inserted: String?
    var deleted = false
    var closed = false
    let picker = KeyboardEmojiPickerView(
      resources: "/fixture",
      loader: { requested, offset in
        XCTAssertEqual(requested, category)
        XCTAssertEqual(offset, 0)
        return KeyboardEmojiCatalog.Page(items: [
          .init(text: "😀", annotation: "fixture", group: category.group),
          .init(text: "🌲", annotation: "fixture", group: category.group),
        ], nextOffset: 2, complete: true)
      },
      onInsert: { inserted = $0 },
      onDelete: { deleted = true },
      onClose: { closed = true },
      onCatalogChange: { changed.fulfill() })
    picker.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
    picker.layoutIfNeeded()
    await fulfillment(of: [changed], timeout: 2)

    let grid = try XCTUnwrap(descendants(picker).first {
      $0.accessibilityIdentifier == "emojiGrid"
    } as? UICollectionView)
    XCTAssertEqual(grid.numberOfItems(inSection: 0), 2)
    picker.collectionView(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
    XCTAssertEqual(inserted, "😀")
    XCTAssertEqual(KeyboardEmojiRecents.stored.first, "😀")
    try button("emojiDeleteKey", in: picker).sendActions(for: .primaryActionTriggered)
    try button("closeEmojiPicker", in: picker).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(deleted)
    XCTAssertTrue(closed)
  }

  func testKaomojiIsTheLastTabAndAcceptsLongerLines() throws {
    let kaomoji = KeyboardEmojiCatalog.kaomoji
    XCTAssertEqual(kaomoji.title, "颜文字")
    XCTAssertTrue(kaomoji.isKaomoji)
    XCTAssertFalse(KeyboardEmojiCatalog.categories.contains { $0.isKaomoji })
    let line = String(repeating: "ヽ", count: 59)
    let value: [String: Any] = [
      "items": [["text": line, "annotation": "fixture", "group": kaomoji.group]],
      "next_offset": 1,
      "complete": true,
    ]
    XCTAssertEqual(
      try KeyboardEmojiCatalog.decodePage(value, category: kaomoji, requestedOffset: 0).items.first?.text,
      line)
    let emoji = try XCTUnwrap(KeyboardEmojiCatalog.categories.first)
    var asEmoji = value
    asEmoji["items"] = [["text": line, "annotation": "fixture", "group": emoji.group]]
    XCTAssertThrowsError(
      try KeyboardEmojiCatalog.decodePage(asEmoji, category: emoji, requestedOffset: 0),
      "the Emoji limit still applies outside the kaomoji tab")
    XCTAssertEqual(KeyboardEmojiPickerView.kaomojiColumns(width: 378), 2)
    XCTAssertEqual(KeyboardEmojiPickerView.kaomojiColumns(width: 200), 2)
    XCTAssertEqual(KeyboardEmojiPickerView.kaomojiColumns(width: 1012), 5)
  }

  func testSharedBridgeReadsPackagedKaomoji() throws {
    let state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-kaomoji-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: state) }
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    let resources = try XCTUnwrap(bridge.candidateGlossResources())
    let page = try KeyboardEmojiCatalog.loadPage(
      resources: resources, category: KeyboardEmojiCatalog.kaomoji, offset: 0)
    XCTAssertFalse(page.items.isEmpty)
    XCTAssertFalse(page.complete)
    XCTAssertTrue(page.items.contains { $0.text.unicodeScalars.count > 1 })
  }

  func testPickerKaomojiTabInsertsWithoutTouchingRecents() async throws {
    let kaomoji = KeyboardEmojiCatalog.kaomoji
    let loaded = expectation(description: "kaomoji page")
    var inserted: String?
    let picker = KeyboardEmojiPickerView(
      resources: "/fixture",
      loader: { category, _ in
        if category == kaomoji { loaded.fulfill() }
        return KeyboardEmojiCatalog.Page(items: [
          .init(text: category == kaomoji ? "(*^▽^*)" : "😀", annotation: "fixture", group: category.group),
        ], nextOffset: 1, complete: true)
      },
      onInsert: { inserted = $0 },
      onDelete: {},
      onClose: {},
      onCatalogChange: nil)
    picker.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
    picker.layoutIfNeeded()
    let tabs = descendants(picker).compactMap { $0 as? UIButton }
      .filter { $0.accessibilityIdentifier?.hasPrefix("emojiCategory-") == true }
    let last = try XCTUnwrap(tabs.last)
    XCTAssertEqual(last.accessibilityLabel, "颜文字")
    last.sendActions(for: .primaryActionTriggered)
    await fulfillment(of: [loaded], timeout: 2)
    try await Task.sleep(nanoseconds: 100_000_000)

    let grid = try XCTUnwrap(descendants(picker).first {
      $0.accessibilityIdentifier == "emojiGrid"
    } as? UICollectionView)
    XCTAssertEqual(grid.numberOfItems(inSection: 0), 1)
    picker.collectionView(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
    XCTAssertEqual(inserted, "(*^▽^*)")
    XCTAssertTrue(KeyboardEmojiRecents.stored.isEmpty)
    let status = try XCTUnwrap(descendants(picker).first {
      $0.accessibilityIdentifier == "emojiCatalogStatus"
    } as? UILabel)
    XCTAssertEqual(status.text, "1 个颜文字")
  }

  func testControllerExposesToolbarAndMoreMenuEntries() throws {
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
    controller.view.layoutIfNeeded()

    try button("emojiShortcut", in: controller.view).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(descendants(controller.view).contains {
      $0.accessibilityIdentifier == "keyboardEmojiPicker"
    })
    try button("closeEmojiPicker", in: controller.view).sendActions(for: .primaryActionTriggered)
    try button("moreShortcut", in: controller.view).sendActions(for: .primaryActionTriggered)
    try button("moreCard-表情", in: controller.view).sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(descendants(controller.view).contains {
      $0.accessibilityIdentifier == "keyboardEmojiPicker"
    })
  }

  private func descendants(_ root: UIView) -> [UIView] {
    root.subviews + root.subviews.flatMap(descendants)
  }

  private func button(_ identifier: String, in root: UIView) throws -> UIButton {
    try XCTUnwrap(descendants(root).first {
      $0.accessibilityIdentifier == identifier
    } as? UIButton)
  }
}
