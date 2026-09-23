import XCTest

/// Fuzzy pinyin lives in the shared document, which the native page, the shared settings page and the keyboard all read.
@MainActor
final class FuzzyPinyinDocumentTests: XCTestCase {
  private var state: URL!
  private var previous: [String: Any?] = [:]
  private let keys = [FuzzyPinyinPreference.enabledKey, FuzzyPinyinPreference.rulesKey, FuzzyPinyinPreference.seededKey]

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-fuzzy-document-\(UUID().uuidString)", isDirectory: true)
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    for key in keys {
      previous[key] = FuzzyPinyinPreference.defaults.object(forKey: key)
      FuzzyPinyinPreference.defaults.removeObject(forKey: key)
    }
  }

  override func tearDown() {
    for key in keys {
      if let value = previous[key] ?? nil {
        FuzzyPinyinPreference.defaults.set(value, forKey: key)
      } else {
        FuzzyPinyinPreference.defaults.removeObject(forKey: key)
      }
    }
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  private func stored() throws -> FuzzyPinyinPreference.Settings {
    try XCTUnwrap(FuzzyPinyinPreference.settings(in: MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)))
  }

  func testFirstEnableKeepsTheChosenRulesInsteadOfReseedingEveryRule() throws {
    XCTAssertEqual(try stored(), .pristine)

    XCTAssertTrue(FuzzyPinyinPreference.save(.init(enabled: true, rules: ["n-l"], seeded: true), stateRoot: state))

    XCTAssertEqual(try stored(), .init(enabled: true, rules: ["n-l"], seeded: true))
    XCTAssertEqual(FuzzyPinyinPreference.defaults.string(forKey: FuzzyPinyinPreference.rulesKey), "n-l")
  }

  func testAnOlderAppGroupSelectionMovesIntoAnUntouchedDocument() throws {
    FuzzyPinyinPreference.defaults.set(true, forKey: FuzzyPinyinPreference.enabledKey)
    FuzzyPinyinPreference.defaults.set("s-sh,an-ang", forKey: FuzzyPinyinPreference.rulesKey)
    FuzzyPinyinPreference.defaults.set(true, forKey: FuzzyPinyinPreference.seededKey)
    let document = MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)

    let resolved = try XCTUnwrap(FuzzyPinyinPreference.resolve(document: document, stateRoot: state))

    XCTAssertEqual(resolved, .init(enabled: true, rules: ["s-sh", "an-ang"], seeded: true))
    XCTAssertEqual(try stored(), resolved)
    XCTAssertEqual(resolved.bits, 1 << 2 | 1 << 6)
  }

  func testTheDocumentWinsOnceItHasBeenTouched() throws {
    XCTAssertTrue(FuzzyPinyinPreference.save(.init(enabled: false, rules: [], seeded: true), stateRoot: state))
    FuzzyPinyinPreference.defaults.set(true, forKey: FuzzyPinyinPreference.enabledKey)
    FuzzyPinyinPreference.defaults.set("n-l", forKey: FuzzyPinyinPreference.rulesKey)
    let document = MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)

    let resolved = try XCTUnwrap(FuzzyPinyinPreference.resolve(document: document, stateRoot: state))

    XCTAssertEqual(resolved, .init(enabled: false, rules: [], seeded: true))
    XCTAssertEqual(resolved.bits, 0)
    XCTAssertEqual(try stored(), resolved)
  }
}
