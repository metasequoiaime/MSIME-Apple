import XCTest

/// The settings app's punctuation page writes the shared document; the keyboard has to act on it.
final class PunctuationSettingsTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-punctuation-settings-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  /// The app reads and writes the document without creating a session.
  func testSettingsAppRoundTripsTheSharedDocument() throws {
    // The keyboard prepares the state root; the app only ever reads one that exists.
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    let before = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state))
    XCTAssertEqual(before["paired_punctuation"] as? Bool, true)
    XCTAssertEqual(before["punctuation_lock"] as? String, "follow")

    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      $0["paired_punctuation"] = false
      $0["punctuation_lock"] = "english"
    })
    let after = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state))
    XCTAssertEqual(after["paired_punctuation"] as? Bool, false)
    XCTAssertEqual(after["punctuation_lock"] as? String, "english")
    // Nothing else moved.
    XCTAssertEqual(after["smart_punctuation"] as? Bool, before["smart_punctuation"] as? Bool)
  }

  /// A switch turned off in the app stops working the next time the keyboard appears, without waiting for a new session.
  ///
  /// The keyboard has already written its own preferences by then - it applies the learning switches every time it appears - so the document's revision is not what the session last counted to.
  func testReloadHandsPunctuationSwitchesToTheLiveSession() async {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertNotEqual(bridge.handlePunctuationWithContext(",", preceding: 0x61).commitText, "，",
                      "direct-after-letter ships on, so a comma after a letter stays ASCII")
    XCTAssertTrue(bridge.setFuzzyPinyinRules(1))
    XCTAssertTrue(bridge.setFuzzyPinyinRules(0))
    XCTAssertTrue(bridge.setTraditionalChineseOutput(false))

    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      $0["smart_punctuation_direct_letter"] = false
    })
    reload(bridge)

    XCTAssertEqual(bridge.handlePunctuationWithContext(",", preceding: 0x61).commitText, "，")
  }

  private func reload(_ bridge: MetasequoiaInputSessionBridge) {
    let reloaded = expectation(description: "reload")
    var accepted = false
    bridge.reloadSharedPreferences { loaded in
      accepted = loaded
      reloaded.fulfill()
    }
    await fulfillment(of: [reloaded], timeout: 15)
    XCTAssertTrue(accepted, "the reload was refused")
  }
}
