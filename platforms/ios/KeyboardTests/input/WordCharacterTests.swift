import XCTest

/// 以词定字 from a candidate's long-press menu: the Engine commits one Han character of the candidate and ends the composition.
final class WordCharacterTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-word-character-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testEdgesCommitOneCharacterOfTheCandidate() throws {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    let first = try select(bridge, "zhongguo", word: "中国", last: false)
    XCTAssertEqual(first.commitText, "中")
    XCTAssertEqual(first.preedit, "", "the composition ends with the character")

    let last = try select(bridge, "zhongguo", word: "中国", last: true)
    XCTAssertEqual(last.commitText, "国")
  }

  func testAStaleCandidateIsRefused() {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    _ = bridge.cancel()
    let snapshot = bridge.selectCandidateEdge(at: 0, last: false)
    XCTAssertNil(snapshot.commitText)
    XCTAssertNotNil(snapshot.diagnosticText)
  }

  private func select(_ bridge: MetasequoiaInputSessionBridge, _ letters: String, word: String, last: Bool) throws -> MetasequoiaInputSnapshot {
    var snapshot = bridge.cancel()
    for letter in letters { snapshot = bridge.handleCharacter(String(letter)) }
    let index = try XCTUnwrap(snapshot.candidates.firstIndex { $0.split(separator: "\n").first.map(String.init) == word },
                              "\(word) is not among \(snapshot.candidates.prefix(5))")
    return bridge.selectCandidateEdge(at: UInt(index), last: last)
  }
}
