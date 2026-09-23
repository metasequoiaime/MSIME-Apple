import XCTest

/// The expanded candidate panel lists the Engine's whole answer, so its entries are named by their index in that answer rather than by a slot on the visible page.
final class CandidatePanelSelectionTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-candidate-panel-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testAnEntryPastTheVisiblePageCommits() throws {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    _ = bridge.cancel()
    let visible = bridge.handleCharacter("y").candidates
    let (generation, entries) = try panel(bridge)
    let later = try XCTUnwrap(entries.first { $0.position >= visible.count && $0.position >= 9 },
                              "the answer for y should run past the first page")

    XCTAssertFalse(bridge.isOnCurrentPage(generation: generation, globalIndex: later.index))
    let refused = bridge.selectCandidate(generation: generation, globalIndex: later.index)
    XCTAssertNil(refused.commitText, "the page-bounded select still refuses an off-page entry")

    let selected = bridge.selectAnyCandidate(generation: generation, globalIndex: later.index)
    XCTAssertEqual(selected.commitText, later.text)
  }

  func testAStaleGenerationIsRefused() throws {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    _ = bridge.cancel()
    _ = bridge.handleCharacter("y")
    let (generation, entries) = try panel(bridge)
    let first = try XCTUnwrap(entries.first)
    XCTAssertTrue(bridge.isOnCurrentPage(generation: generation, globalIndex: first.index))
    _ = bridge.handleCharacter("i")

    XCTAssertFalse(bridge.isOnCurrentPage(generation: generation, globalIndex: first.index))
    XCTAssertNil(bridge.selectAnyCandidate(generation: generation, globalIndex: first.index).commitText)
  }

  private func panel(_ bridge: MetasequoiaInputSessionBridge) throws -> (UInt64, [(position: Int, index: UInt64, text: String)]) {
    let answer = try bridge.allCandidates()
    let generation = try XCTUnwrap((answer["generation"] as? NSNumber)?.uint64Value)
    let rows = try XCTUnwrap(answer["candidates"] as? [[String: Any]])
    let entries = rows.enumerated().compactMap { position, row -> (position: Int, index: UInt64, text: String)? in
      guard let identity = row["id"] as? [String: Any], let index = (identity["index"] as? NSNumber)?.uint64Value,
            let text = row["text"] as? String else { return nil }
      return (position, index, text)
    }
    return (generation, entries)
  }
}
