import XCTest

/// 工具栏按钮 read from the shared `touch_toolbar`.
final class TouchToolbarPreferenceTests: XCTestCase {
  func testAnUntouchedDocumentKeepsTheBarTheKeyboardAlwaysHad() {
    for preferences in [nil, [:], ["touch_toolbar": "not an object"]] as [[String: Any]?] {
      XCTAssertEqual(TouchToolbarPreference(in: preferences), TouchToolbarPreference())
    }
    let defaults = TouchToolbarPreference()
    XCTAssertTrue(defaults.layout && defaults.emoji && defaults.skin)
    XCTAssertFalse(defaults.clipboard || defaults.ai || defaults.characterSet || defaults.fullwidth || defaults.punctuation)
  }

  func testStoredSwitchesWinAndMissingOnesKeepTheirDefault() {
    let pinned = TouchToolbarPreference(in: ["touch_toolbar": [
      "skin": false, "clipboard": true, "character_set": true, "punctuation": "yes",
    ]])
    XCTAssertFalse(pinned.skin)
    XCTAssertTrue(pinned.clipboard)
    XCTAssertTrue(pinned.characterSet)
    XCTAssertTrue(pinned.layout, "absent, so on by default")
    XCTAssertFalse(pinned.punctuation, "a value that is not a Bool reads as the default")
  }

  func testTheNativePageWritesTheWholeObjectTheSharedValidatorAccepts() throws {
    let state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-toolbar-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: state) }
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertEqual(TouchToolbarPreference.load(stateRoot: state), TouchToolbarPreference())

    var toolbar = TouchToolbarPreference()
    toolbar.skin = false
    toolbar.clipboard = true
    toolbar.punctuation = true
    XCTAssertTrue(TouchToolbarPreference.save(toolbar, stateRoot: state))
    XCTAssertEqual(TouchToolbarPreference.load(stateRoot: state), toolbar)
    let stored = try XCTUnwrap(
      MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)?["touch_toolbar"] as? [String: Any])
    XCTAssertEqual(Set(stored.keys), Set(TouchToolbarPreference.options.map(\.name)))
  }
}
