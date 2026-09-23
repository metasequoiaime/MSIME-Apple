import XCTest

/// Leaving a composition through the 中/英 switch or Return keeps the letters typed, as Windows does; 「中文标点」 and 标点锁定 reach the runtime.
final class CompositionBoundaryTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-composition-boundary-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testPolicyCommitsRawLettersExceptWhereTheKeysAreNotLetters() {
    XCTAssertEqual(CompositionBoundaryPolicy.action(composing: false, scheme: .quanpin, boundary: .modeSwitch), .none)
    for boundary in [CompositionBoundary.modeSwitch, .returnKey] {
      XCTAssertEqual(CompositionBoundaryPolicy.action(composing: true, scheme: .quanpin, boundary: boundary), .commitRaw)
      XCTAssertEqual(CompositionBoundaryPolicy.action(composing: true, scheme: .wubi, boundary: boundary), .commitRaw)
      XCTAssertEqual(CompositionBoundaryPolicy.action(composing: true, scheme: .nineKey, boundary: boundary), .finishComposition,
                     "nine-key raw keys are digits")
      XCTAssertEqual(CompositionBoundaryPolicy.action(composing: true, scheme: .japanese, boundary: boundary), .finishComposition,
                     "Japanese confirms the kana")
    }
    XCTAssertEqual(CompositionBoundaryPolicy.action(composing: true, scheme: .quanpin, boundary: .deactivate), .finishComposition)
  }

  func testCommitRawKeepsTheTypedLetters() {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    for letter in "nihao" { _ = bridge.handleCharacter(String(letter)) }
    let snapshot = bridge.commitRaw()
    XCTAssertTrue(snapshot.isHandled)
    XCTAssertEqual(snapshot.commitText, "nihao")
    XCTAssertTrue(snapshot.preedit.isEmpty)

    _ = bridge.switchToWubi()
    for letter in "wqvb" { _ = bridge.handleCharacter(String(letter)) }
    XCTAssertEqual(bridge.commitRaw().commitText, "wqvb")
  }

  func testChinesePunctuationSwitchReachesTheRuntime() {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertEqual(bridge.handlePunctuationWithContext(",", preceding: 0).commitText, "，")
    bridge.setChinesePunctuation(false)
    XCTAssertNotEqual(bridge.handlePunctuationWithContext(",", preceding: 0).commitText, "，")
    bridge.setChinesePunctuation(true)
    XCTAssertEqual(bridge.handlePunctuationWithContext(",", preceding: 0).commitText, "，")
  }

  /// English mode asks the runtime only under 标点锁定为中文, and the runtime answers with the Chinese mark whatever the switch says.
  func testChineseLockOverridesTheSwitch() {
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      $0["punctuation_lock"] = "chinese"
    })
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    bridge.setChinesePunctuation(false)
    XCTAssertEqual(bridge.handlePunctuationWithContext(",", preceding: 0).commitText, "，")
  }
}
