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
