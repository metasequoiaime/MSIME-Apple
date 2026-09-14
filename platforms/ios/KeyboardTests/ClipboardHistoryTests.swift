import XCTest
import UIKit

final class ClipboardHistoryTests: XCTestCase {
  private func writeLegacy(_ items: [ClipboardHistoryItem], to file: URL) throws {
    let rows = items.map { item in
      [
        "id": UUID().uuidString,
        "text": item.text,
        "date": item.date.timeIntervalSinceReferenceDate,
        "pinned": item.pinned,
      ] as [String: Any]
    }
    try JSONSerialization.data(withJSONObject: rows).write(to: file)
  }

  private func temporaryStore() throws -> ClipboardHistoryStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return ClipboardHistoryStore(directory: directory)
  }
  func testDeduplicationPersistenceAndPinnedEviction() throws {
    let store = try temporaryStore()
    try store.add("  保留空格\n")
    try store.setPinned(true, text: "  保留空格\n")
    for number in 0..<60 { try store.add("记录 \(number)") }
    XCTAssertEqual(try store.load().count, 50)
    XCTAssertEqual(try store.load().first?.text, "  保留空格\n")
    XCTAssertEqual(try store.load().first?.pinned, true)
    XCTAssertFalse(try store.load().contains { $0.text == "记录 0" })
    try store.add("  保留空格\n")
    XCTAssertEqual(try store.load().first?.text, "  保留空格\n")
    XCTAssertEqual(try store.load().filter { $0.text == "  保留空格\n" }.count, 1)
    for item in try store.load() { try store.setPinned(true, text: item.text) }
    let items = try store.load()
    XCTAssertThrowsError(try store.add("满了"))
    XCTAssertEqual(try store.load(), items)
    try store.clear()
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
    try FileManager.default.removeItem(at: store.file)
    try store.clear()
    XCTAssertTrue(try store.load().isEmpty)
  }

  func testLegacyHistoryMigratesOnceWithMetadataPreserved() throws {
    let store = try temporaryStore()
    try FileManager.default.createDirectory(
      at: store.legacyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    let older = Date(timeIntervalSince1970: 1_700_000_000)
    let newer = Date(timeIntervalSince1970: 1_700_000_100)
    let legacy = [
      ClipboardHistoryItem(text: "synthetic older", date: older, pinned: false),
      ClipboardHistoryItem(text: "synthetic pinned", date: newer, pinned: true),
    ]
    try writeLegacy(legacy, to: store.legacyFile)

    let migrated = try store.load()
    XCTAssertEqual(migrated.map(\.text), ["synthetic pinned", "synthetic older"])
    XCTAssertEqual(migrated.map(\.pinned), [true, false])
    XCTAssertEqual(migrated[0].date.timeIntervalSince1970, newer.timeIntervalSince1970, accuracy: 0.001)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.file.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyFile.path))
    XCTAssertEqual(try store.load().map(\.text), migrated.map(\.text))
  }

  func testCorruptLegacyIsPreservedAndSharedHistoryWinsWithoutOverwrite() throws {
    let corrupt = try temporaryStore()
    try FileManager.default.createDirectory(
      at: corrupt.legacyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    let bytes = Data("invalid synthetic legacy".utf8)
    try bytes.write(to: corrupt.legacyFile)
    XCTAssertThrowsError(try corrupt.load())
    XCTAssertEqual(try Data(contentsOf: corrupt.legacyFile), bytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.file.path))

    let existing = try temporaryStore()
    try existing.add("synthetic shared")
    try FileManager.default.createDirectory(
      at: existing.legacyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    let legacy = [ClipboardHistoryItem(text: "synthetic legacy")]
    try writeLegacy(legacy, to: existing.legacyFile)
    XCTAssertEqual(try existing.load().map(\.text), ["synthetic shared"])
    XCTAssertTrue(FileManager.default.fileExists(atPath: existing.legacyFile.path))
  }

  func testConcurrentMigrationDoesNotDuplicateOrLoseRecords() throws {
    let store = try temporaryStore()
    try FileManager.default.createDirectory(
      at: store.legacyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    let legacy = (0..<20).map {
      ClipboardHistoryItem(text: "synthetic concurrent \($0)", date: Date(timeIntervalSince1970: Double($0)))
    }
    try writeLegacy(legacy, to: store.legacyFile)
    let group = DispatchGroup()
    let lock = NSLock()
    var failures = 0
    for _ in 0..<8 {
      group.enter()
      DispatchQueue.global().async {
        defer { group.leave() }
        do { _ = try store.load() }
        catch { lock.lock(); failures += 1; lock.unlock() }
      }
    }
    XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
    XCTAssertEqual(failures, 0)
    let loaded = try store.load()
    XCTAssertEqual(loaded.count, 20)
    XCTAssertEqual(Set(loaded.map(\.text)).count, 20)
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyFile.path))
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
