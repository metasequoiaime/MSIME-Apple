import XCTest

final class PersonalDictionaryStoreTests: XCTestCase {
  func testQueueAcknowledgementFailureAndPaging() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let host = PersonalDictionaryStore(directory: root)
    let keyboard = PersonalDictionaryStore(directory: root)
    let word = PersonalWord(key: "ni'hao", value: "拟好")
    let id = try host.enqueue(previous: nil, replacement: word)
    XCTAssertEqual(try host.read().pendingCount, 1)
    XCTAssertTrue(try host.read().entries.isEmpty)
    XCTAssertThrowsError(try host.enqueue(previous: nil, replacement: word))
    var calls = [UUID]()
    try keyboard.synchronize(apply: { calls.append($0.id) }, page: { _ in .init(entries: [word], hasMore: true) })
    XCTAssertEqual(calls, [id])
    XCTAssertEqual(try host.read().requests.first?.status, .applied)
    XCTAssertEqual(try host.read().entries, [word])
    try keyboard.synchronize(apply: { _ in XCTFail("Acknowledged edit was applied twice") },
                             page: { _ in .init(entries: [word], hasMore: true) })
    let removal = try host.enqueue(previous: word, replacement: nil)
    enum Failure: Error { case injected }
    try keyboard.synchronize(apply: { _ in throw Failure.injected }, page: { _ in throw Failure.injected })
    XCTAssertEqual(try host.read().requests.last?.status, .failed)
    XCTAssertEqual(try host.read().entries, [word])
    XCTAssertNotNil(try host.read().snapshotError)
    try host.retry(removal)
    try host.requestPage(offset: 100)
    try keyboard.synchronize(apply: { XCTAssertEqual($0.id, removal) }, page: {
      XCTAssertEqual($0, 100)
      return .init(entries: [], hasMore: false)
    })
    XCTAssertEqual(try host.read().pageOffset, 100)
    XCTAssertEqual(try host.read().pendingCount, 0)
    XCTAssertTrue(try host.read().entries.isEmpty)
    XCTAssertNil(try host.read().snapshotError)
  }

  @MainActor
  func testQueueRetryReachesActualKeyboardEngine() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let host = PersonalDictionaryStore(directory: root)
    let keyboard = PersonalDictionaryStore(directory: root)
    let session = MetasequoiaInputSessionBridge()
    let word = try PersonalWord(kind: .quickPhrase, key: "msimefixture", value: "private fixture text").validated()
    let id = try host.enqueue(previous: nil, replacement: word)
    defer {
      _ = session.cancel()
      try? session.applyPersonalPrevious(word.bridgeValue, replacement: nil, requestID: UUID().uuidString)
    }
    // Simulate a committed edit followed by process interruption before its shared acknowledgement.
    try session.applyPersonalPrevious(nil, replacement: word.bridgeValue, requestID: id.uuidString)
    func synchronize() throws {
      try keyboard.synchronize(apply: {
        try session.applyPersonalPrevious($0.previous?.bridgeValue, replacement: $0.replacement?.bridgeValue,
                                          requestID: $0.id.uuidString)
      }, page: {
        let result = try session.personalEntries(atOffset: UInt($0))
        let entries = try XCTUnwrap(result["entries"] as? [[String: Any]])
        return .init(entries: try entries.map { try PersonalWord(bridgeValue: $0) },
                     hasMore: try XCTUnwrap(result["hasMore"] as? Bool))
      })
    }
    try synchronize()
    XCTAssertEqual(try host.read().requests.first?.status, .applied)
    XCTAssertTrue(try host.read().entries.contains(word))
    _ = session.openLocalMode("K")
    var snapshot = session.handleCharacter("m")
    for letter in word.key.dropFirst() { snapshot = session.handleCharacter(String(letter)) }
    XCTAssertTrue(snapshot.candidates.contains(word.value))
    _ = session.cancel()
    try host.enqueue(previous: word, replacement: nil)
    try synchronize()
    XCTAssertEqual(try host.read().requests.last?.status, .applied)
    XCTAssertFalse(try host.read().entries.contains { $0.id == word.id })
  }

  func testEngineValidationAndBridgePayload() throws {
    let word = try PersonalWord(key: "NI HAO", value: "拟好").validated()
    XCTAssertEqual(word.key, "ni'hao")
    XCTAssertEqual(try PersonalWord(bridgeValue: word.bridgeValue), word)
    XCTAssertThrowsError(try PersonalWord(key: "nihao", value: "你好").validated())
    XCTAssertThrowsError(try PersonalWord(key: "ni'hao", value: "你").validated())
    XCTAssertThrowsError(try PersonalWord(kind: .wubi, key: "abcde", value: "词").validated())
    XCTAssertThrowsError(try PersonalWord(kind: .english, key: "wrong", value: "Word").validated())
    XCTAssertThrowsError(try PersonalWord(key: "ni", value: "a\0b").validated())
    XCTAssertEqual(try PersonalWord(kind: .quickPhrase, key: "HELLO1", value: "第一行\n第二行").validated().key, "hello1")
  }

  func testImportValidatesAllEntriesAndRejectsMalformedOrDuplicateData() throws {
    let example = try PersonalDictionaryImport.decode(PersonalDictionaryImport.example.encoded())
    XCTAssertEqual(example.entries.count, 4)
    XCTAssertEqual(example.entries[0].key, "ni'hao")
    XCTAssertEqual(example.entries[3].value, "你好！\n很高兴认识你。")
    var invalid = example
    invalid.entries.append(.init(key: "nihao", value: "你好"))
    XCTAssertThrowsError(try PersonalDictionaryImport.decode(invalid.encoded())) { error in
      XCTAssertTrue(error.localizedDescription.contains("第 5 条"))
    }
    invalid = example
    invalid.entries.append(.init(key: "NI HAO", value: "你好"))
    XCTAssertThrowsError(try PersonalDictionaryImport.decode(invalid.encoded())) { error in
      XCTAssertTrue(error.localizedDescription.contains("重复"))
    }
    invalid = example
    invalid.version = 2
    XCTAssertThrowsError(try PersonalDictionaryImport.decode(invalid.encoded()))
    XCTAssertThrowsError(try PersonalDictionaryImport.decode(Data("{}".utf8)))
    XCTAssertThrowsError(try PersonalDictionaryImport.decode(Data(repeating: 32, count: 1_048_577)))
    XCTAssertThrowsError(try PersonalDictionaryImport.decode(PersonalDictionaryImport(entries: []).encoded()))
    let oversized = PersonalDictionaryImport(entries: Array(repeating: example.entries[0], count: 129))
    XCTAssertThrowsError(try PersonalDictionaryImport.decode(oversized.encoded()))
  }

  func testImportQueueIsAtomicOnValidationConflictAndCapacityFailure() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PersonalDictionaryStore(directory: root)
    let words = try PersonalDictionaryImport.decode(PersonalDictionaryImport.example.encoded()).entries
    try store.enqueueImport(words)
    let file = root.appendingPathComponent("PersonalDictionary/sync.json")
    let original = try Data(contentsOf: file)
    XCTAssertEqual(try store.read().pendingCount, 4)
    let fresh = PersonalWord(kind: .quickPhrase, key: "newfixture", value: "fixture")
    XCTAssertThrowsError(try store.enqueueImport([fresh, words[0]]))
    XCTAssertEqual(try Data(contentsOf: file), original)
    XCTAssertThrowsError(try store.enqueueImport([fresh, .init(key: "nihao", value: "你好")]))
    XCTAssertEqual(try Data(contentsOf: file), original)
    let tooMany = (0..<125).map { PersonalWord(kind: .quickPhrase, key: "fixture\($0)", value: "fixture") }
    XCTAssertThrowsError(try store.enqueueImport(tooMany))
    XCTAssertEqual(try Data(contentsOf: file), original)
    try store.synchronize(apply: { _ in }, page: { _ in .init(entries: [], hasMore: false) })
    try store.enqueueImport(tooMany)
    XCTAssertEqual(try store.read().pendingCount, 125)
    XCTAssertEqual(Set(try store.read().requests.map(\.id)).count, 129)
  }

  func testLargeImportYieldsBetweenSyncBatchesAndPreservesReceipts() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PersonalDictionaryStore(directory: root)
    try store.enqueueImport((0..<9).map { .init(kind: .quickPhrase, key: "batch\($0)", value: "fixture") })
    let ids = try store.read().requests.map(\.id)
    var applied = [UUID]()
    try store.synchronize(apply: { applied.append($0.id) }, page: { _ in .init(entries: [], hasMore: false) })
    XCTAssertEqual(applied, Array(ids.prefix(4)))
    XCTAssertEqual(try store.read().pendingCount, 5)
    XCTAssertNotEqual(try store.read().refreshID, try store.read().completedRefreshID)
    try store.synchronize(apply: { applied.append($0.id) }, page: { _ in .init(entries: [], hasMore: false) })
    XCTAssertEqual(applied, Array(ids.prefix(8)))
    try store.synchronize(apply: { applied.append($0.id) }, page: { _ in .init(entries: [], hasMore: false) })
    XCTAssertEqual(applied, ids)
    XCTAssertEqual(try store.read().pendingCount, 0)
    XCTAssertEqual(try store.read().refreshID, try store.read().completedRefreshID)
  }

  func testCoordinatedFileImportReadsCompleteContentAndRejectsOversizedFiles() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: file) }
    // Multiple read chunks, including escaped newlines and multibyte text.
    let words = (0..<40).map {
      PersonalWord(kind: .quickPhrase, key: "file\($0)", value: String(repeating: "你好\n", count: 300))
    }
    let data = try PersonalDictionaryImport(entries: words).encoded()
    XCTAssertGreaterThan(data.count, 65_536)
    try data.write(to: file)
    XCTAssertEqual(try PersonalDictionaryImport.read(from: file).entries, words)
    try Data(repeating: 32, count: PersonalDictionaryImport.maximumBytes + 1).write(to: file)
    XCTAssertThrowsError(try PersonalDictionaryImport.read(from: file)) { error in
      XCTAssertTrue(error.localizedDescription.contains("1 MB"))
    }
    try FileManager.default.removeItem(at: file)
    XCTAssertThrowsError(try PersonalDictionaryImport.read(from: file))
  }

  func testMalformedStateIsPreservedAndReadDoesNotCreateFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PersonalDictionaryStore(directory: root)
    XCTAssertTrue(try store.read().entries.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    let directory = root.appendingPathComponent("PersonalDictionary")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("sync.json")
    let original = Data("broken fixture".utf8)
    try original.write(to: file)
    XCTAssertThrowsError(try store.enqueue(previous: nil, replacement: .init(key: "ni", value: "拟")))
    XCTAssertEqual(try Data(contentsOf: file), original)
    XCTAssertThrowsError(try PersonalDictionaryStore(directory: nil).read())
  }
}
