import XCTest

/// 成对标点自动补全: the keyboard writes the closing half of a pair the Engine opened.
final class PairedPunctuationTests: XCTestCase {
  func testCompletionFollowsTheOpeningMarkAtTheEndOfTheCommit() {
    XCTAssertEqual(PairedPunctuationPolicy.completion("你好（", enabled: true),
                   PairedPunctuationCompletion(opening: "(", closing: "）"))
    XCTAssertEqual(PairedPunctuationPolicy.completion("《", enabled: true)?.closing, "》")
    XCTAssertEqual(PairedPunctuationPolicy.completion("〈", enabled: true)?.opening, "<")
    XCTAssertEqual(PairedPunctuationPolicy.completion("【", enabled: true)?.closing, "】")
    XCTAssertEqual(PairedPunctuationPolicy.completion("“", enabled: true)?.closing, "”")
    XCTAssertNil(PairedPunctuationPolicy.completion("（", enabled: false))
    XCTAssertNil(PairedPunctuationPolicy.completion("）", enabled: true))
    XCTAssertNil(PairedPunctuationPolicy.completion("，", enabled: true))
    XCTAssertNil(PairedPunctuationPolicy.completion("", enabled: true))
    XCTAssertNil(PairedPunctuationPolicy.completion(nil, enabled: true))
  }

  func testAQuotePressAlwaysOpensAPairWhilePairingIsOn() {
    XCTAssertEqual(PairedPunctuationPolicy.reopenQuote("”", ascii: "\"", enabled: true), "“")
    XCTAssertEqual(PairedPunctuationPolicy.reopenQuote("好’", ascii: "'", enabled: true), "好‘")
    XCTAssertEqual(PairedPunctuationPolicy.reopenQuote("”", ascii: "\"", enabled: false), "”")
    XCTAssertEqual(PairedPunctuationPolicy.reopenQuote("）", ascii: ")", enabled: true), "）")
    XCTAssertNil(PairedPunctuationPolicy.reopenQuote(nil, ascii: "\"", enabled: true))
  }

  func testBalancedBookTitlesKeepOpeningTheOuterMark() {
    let state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-paired-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: state) }
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    _ = bridge.cancel()
    XCTAssertEqual(bridge.handlePunctuationWithContext("<", preceding: 0).commitText, "《")
    XCTAssertTrue(bridge.balancePairedPunctuationAfterAutoClose(opening: "<"))
    XCTAssertEqual(bridge.handlePunctuationWithContext("<", preceding: 0).commitText, "《",
                   "the auto-closed 》 ends the first title, so the next one is not nested")
    XCTAssertFalse(bridge.balancePairedPunctuationAfterAutoClose(opening: "("))
  }

  func testReplacingTheCommitKeepsTheRestOfTheSnapshot() {
    let snapshot = MetasequoiaInputSnapshot(isHandled: true, commitText: "”", preedit: "", candidates: ["a"])
    let reopened = snapshot.replacingCommit("“")
    XCTAssertEqual(reopened.commitText, "“")
    XCTAssertEqual(reopened, MetasequoiaInputSnapshot(isHandled: true, commitText: "“", preedit: "", candidates: ["a"]))
  }
}
