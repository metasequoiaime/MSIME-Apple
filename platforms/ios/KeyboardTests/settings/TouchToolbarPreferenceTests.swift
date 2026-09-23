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
}
