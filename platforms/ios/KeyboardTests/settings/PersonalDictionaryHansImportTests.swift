import XCTest

/// Plain Chinese word lists are annotated by the shared Engine from the packaged dictionary, then previewed and queued like a JSON import.
final class PersonalDictionaryHansImportTests: XCTestCase {
  func testPackagedDictionaryAnnotatesWordsAndSkipsCommentsAndRepeats() throws {
    XCTAssertNotNil(PersonalDictionaryBridge.packagedResources, "the test host carries the Engine resources")
    let imported = try PersonalDictionaryImport.hans("你好\n# 注释\n\n世界\n你好\n")
    XCTAssertEqual(imported.entries.map(\.value), ["你好", "世界"])
    XCTAssertTrue(imported.entries.allSatisfy { $0.kind == .pinyin })
    XCTAssertEqual(imported.entries.map { $0.key.filter(\.isLetter) }, ["nihao", "shijie"])
    for word in imported.entries { XCTAssertEqual(try word.validated(), word) }
  }

  func testTextTheImportFormatRefusesSaysWhatToFix() {
    for text in ["hello", "你好 世界", "你好\t世界"] {
      XCTAssertThrowsError(try PersonalDictionaryBridge.hansEntries(text), text) {
        XCTAssertEqual($0 as? HansImportFailure, .invalidText)
      }
    }
  }

  func testMissingDictionaryIsReportedAsUnavailable() throws {
    let empty = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-hans-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }
    XCTAssertThrowsError(try PersonalDictionaryBridge.hansEntries("你好", resources: empty)) {
      XCTAssertEqual($0 as? HansImportFailure, .dictionaryUnavailable)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: empty.path), [])
  }

  func testImportKeepsToTheQueueLimit() {
    let words = (0..<129).map { PersonalWord(key: "a\($0)", value: "词\($0)") }
    XCTAssertThrowsError(try PersonalDictionaryImport.hans("fixture") { _ in words })
    XCTAssertThrowsError(try PersonalDictionaryImport.hans("fixture") { _ in [] })
    XCTAssertEqual(try PersonalDictionaryImport.hans("fixture") { _ in Array(words.prefix(128)) }.entries.count, 128)
  }

  func testEditedWeightIsQueuedAsWritten() throws {
    XCTAssertEqual(PersonalWord.weightRange, 1...100_000_000)
    XCTAssertEqual(PersonalWord(key: "ni hao", value: "你好").weight, PersonalWord.defaultWeight)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-weight-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PersonalDictionaryStore(directory: directory)
    let previous = PersonalWord(key: "ni hao", value: "你好", weight: 100_000)
    var replacement = previous
    replacement.weight = 7
    try store.enqueue(previous: previous, replacement: try replacement.validated())
    let request = try XCTUnwrap(store.read().requests.first)
    XCTAssertEqual(request.previous?.weight, 100_000)
    XCTAssertEqual(request.replacement?.weight, 7)
  }
}
