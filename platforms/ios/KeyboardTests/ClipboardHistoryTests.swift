import XCTest
import UIKit

final class ClipboardHistoryTests: XCTestCase {
  private func temporaryStore() throws -> ClipboardHistoryStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return ClipboardHistoryStore(directory: directory)
  }
  func testDeduplicationPersistenceAndPinnedEviction() throws {
    let store = try temporaryStore()
    try store.add("  保留空格\n")
    var items = try store.load()
    let id = items[0].id
    items[0].pinned = true
    try store.save(items)
    for number in 0..<60 { try store.add("记录 \(number)") }
    XCTAssertEqual(try store.load().count, 50)
    XCTAssertEqual(try store.load().first?.id, id)
    XCTAssertFalse(try store.load().contains { $0.text == "记录 0" })
    try store.add("  保留空格\n")
    XCTAssertEqual(try store.load().first?.text, "  保留空格\n")
    XCTAssertEqual(try store.load().filter { $0.id == id }.count, 1)
    items = try store.load().map { var item = $0; item.pinned = true; return item }
    try store.save(items)
    XCTAssertThrowsError(try store.add("满了"))
    XCTAssertEqual(try store.load(), items)
    try store.save([])
    XCTAssertTrue(try store.load().isEmpty)
  }
  func testInvalidInputAndCorruptHistoryDoNotOverwriteData() throws {
    let store = try temporaryStore()
    XCTAssertThrowsError(try store.add(" \n"))
    XCTAssertThrowsError(try store.add(String(repeating: "字", count: 10_001)))
    try store.add("原文")
    try Data("invalid".utf8).write(to: store.file)
    XCTAssertThrowsError(try store.add("新的"))
    XCTAssertEqual(try Data(contentsOf: store.file), Data("invalid".utf8))
    try store.save([])
    XCTAssertTrue(try store.load().isEmpty)
  }
  @MainActor func testPanelSelectionAccessGateAndNarrowLayout() throws {
    let store = try temporaryStore()
    try store.add("测试粘贴\n第二行")
    var inserted = ""
    let panel = KeyboardClipboardView(hasFullAccess: true, store: store, onInsert: { inserted = $0 }, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 320, height: 260)
    panel.layoutIfNeeded()
    let table = try XCTUnwrap(panel.subviews.compactMap { $0 as? UITableView }.first)
    XCTAssertEqual(table.numberOfRows(inSection: 0), 1)
    panel.tableView(table, didSelectRowAt: IndexPath(row: 0, section: 0))
    XCTAssertEqual(inserted, "测试粘贴\n第二行")
    XCTAssertGreaterThan(table.bounds.height, 60)
    let header = try XCTUnwrap(panel.subviews.compactMap { $0 as? UIStackView }.first)
    let clear = try XCTUnwrap(header.arrangedSubviews.compactMap { $0 as? UIButton }.first)
    clear.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(try store.load().count, 1)
    clear.sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(try store.load().isEmpty)
    let gated = KeyboardClipboardView(hasFullAccess: false, store: store, onInsert: { _ in XCTFail() }, onClose: {})
    let capture = try XCTUnwrap(gated.subviews.compactMap { $0 as? UIButton }.first)
    XCTAssertFalse(capture.isEnabled)
    let hidden = try XCTUnwrap(gated.subviews.compactMap { $0 as? UITableView }.first)
    XCTAssertEqual(hidden.numberOfRows(inSection: 0), 0)
  }
}
