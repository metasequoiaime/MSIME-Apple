import XCTest

/// Editing inside the spelling, as the Windows composition does with ← / →: the caret the runtime moves is the one the strip draws, and a key then acts there.
final class CompositionCaretTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-composition-caret-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testTheCaretMovesThroughTheSpellingAndEditsHappenThere() {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    var snapshot = MetasequoiaInputSnapshot()
    for letter in "nihao" { snapshot = bridge.handleCharacter(String(letter)) }
    XCTAssertEqual(snapshot.editingText, "nihao")
    XCTAssertEqual(snapshot.caretPosition, 5)
    XCTAssertNil(snapshot.editingTextWithCaret, "a caret at the end leaves the segmented pinyin in place")

    for _ in 0..<3 { snapshot = bridge.moveCaretLeft() }
    XCTAssertTrue(snapshot.isHandled)
    XCTAssertEqual(snapshot.caretPosition, 2)
    XCTAssertEqual(snapshot.editingTextWithCaret, "ni|hao")

    snapshot = bridge.handleBackspace()
    XCTAssertEqual(snapshot.editingText, "nhao", "backspace deletes the letter before the caret, not the last one")
    XCTAssertEqual(snapshot.caretPosition, 1)

    snapshot = bridge.moveCaretRight()
    XCTAssertEqual(snapshot.caretPosition, 2)
    _ = bridge.cancel()
  }

  func testSegmentEditsTakeTheSpellingApartASyllableAtATime() {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    var snapshot = MetasequoiaInputSnapshot()
    for letter in "nihaoshijie" { snapshot = bridge.handleCharacter(String(letter)) }
    XCTAssertEqual(snapshot.caretPosition, 11)

    snapshot = bridge.moveCaretLeftBySegment()
    XCTAssertTrue(snapshot.isHandled)
    XCTAssertEqual(snapshot.caretPosition, 8, "one step lands on the boundary before jie")
    snapshot = bridge.moveCaretRightBySegment()
    XCTAssertEqual(snapshot.caretPosition, 11)

    snapshot = bridge.segmentBackspace()
    XCTAssertTrue(snapshot.isHandled)
    XCTAssertEqual(snapshot.editingText, "nihaoshi", "the whole last syllable goes, not one letter")
    for _ in 0..<3 { snapshot = bridge.segmentBackspace() }
    XCTAssertEqual(snapshot.editingText, "")
    XCTAssertTrue(snapshot.candidates.isEmpty)
    _ = bridge.cancel()
  }

  func testOnlyALetteredPinyinSpellingIsEditedBySyllable() {
    XCTAssertEqual(ChineseInputScheme.allCases.filter(\.editsBySyllable),
                   [.quanpin, .shuangpin, .ziranma, .microsoft, .shoudao])
  }

  func testOnlyAQuickFlickMovesBySyllable() {
    XCTAssertFalse(SpaceCursorMovement.movesBySegment(velocity: 300))
    XCTAssertTrue(SpaceCursorMovement.movesBySegment(velocity: -1200))
    XCTAssertFalse(SpaceCursorMovement.movesBySegment(velocity: .nan))
  }

  func testOnlyAnAsciiSpellingWithAnInnerCaretIsSplit() {
    XCTAssertEqual(MetasequoiaInputSnapshot(editingText: "nihao", caretPosition: 0).editingTextWithCaret, "|nihao")
    XCTAssertNil(MetasequoiaInputSnapshot(editingText: "nihao", caretPosition: 5).editingTextWithCaret)
    XCTAssertNil(MetasequoiaInputSnapshot(editingText: "nihao", caretPosition: 9).editingTextWithCaret)
    XCTAssertNil(MetasequoiaInputSnapshot(editingText: "にほ", caretPosition: 1).editingTextWithCaret)
  }
}
