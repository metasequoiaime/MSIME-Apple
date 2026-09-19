import XCTest

final class SmartPunctuationTests: XCTestCase {
  func testDocumentAdapterReturnsOnlyTheImmediatelyPrecedingScalar() {
    XCTAssertEqual(KeyboardPunctuationContext.precedingScalar(nil), 0)
    XCTAssertEqual(KeyboardPunctuationContext.precedingScalar(""), 0)
    XCTAssertEqual(KeyboardPunctuationContext.precedingScalar("fixture7"), UInt32(ascii: "7"))
    XCTAssertEqual(KeyboardPunctuationContext.precedingScalar("fixtureZ"), UInt32(ascii: "Z"))
    XCTAssertEqual(KeyboardPunctuationContext.precedingScalar("fixture中"), 0x4e2d)
    XCTAssertEqual(KeyboardPunctuationContext.precedingScalar("fixture🌲"), 0x1f332)
  }

  func testDisplayedPunctuationMapsToEngineAsciiInputs() {
    XCTAssertEqual(KeyboardPunctuationContext.engineInput(for: "，", japanese: false), ",")
    XCTAssertEqual(KeyboardPunctuationContext.engineInput(for: "。", japanese: false), ".")
    XCTAssertEqual(KeyboardPunctuationContext.engineInput(for: "：", japanese: false), ":")
    XCTAssertEqual(KeyboardPunctuationContext.engineInput(for: "「", japanese: true), "[")
    XCTAssertEqual(KeyboardPunctuationContext.engineInput(for: "・", japanese: true), "/")
    XCTAssertEqual(KeyboardPunctuationContext.engineInput(for: "@", japanese: false), "@")
    XCTAssertNil(KeyboardPunctuationContext.engineInput(for: "……", japanese: false))
  }

  func testBridgeUsesSmartContextOnlyWhileEngineIsIdle() throws {
    let state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-smart-punctuation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: state) }
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)

    // Keeping ASCII after a letter is the shared rule's `smart_punctuation_direct_letter`
    // branch, and that preference ships disabled -- `punctuation.rs` covers the branch itself
    // with the toggle on. What the bridge owes is the context: the preceding scalar reaches the
    // shared layer, and with the shipped defaults both of these follow Chinese punctuation.
    let afterLetter = bridge.handlePunctuationWithContext(",", preceding: UInt32(ascii: "a"))
    XCTAssertEqual(afterLetter.commitText, "，")
    XCTAssertEqual(bridge.handlePunctuationWithContext(",", preceding: 0x4e2d).commitText, "，")

    _ = bridge.handleCharacter("n")
    _ = bridge.handleCharacter("i")
    let composed = try XCTUnwrap(
      bridge.handlePunctuationWithContext(",", preceding: UInt32(ascii: "a")).commitText)
    XCTAssertTrue(composed.hasSuffix("，"))
  }
}

private extension UInt32 {
  init(ascii character: Character) {
    self = UInt32(character.asciiValue!)
  }
}
