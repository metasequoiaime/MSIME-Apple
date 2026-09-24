import XCTest

/// The keyboard's light or dark form follows the shared surface themes, then the global theme, then the host.
final class KeyboardAppearancePreferenceTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-keyboard-appearance-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testSurfaceThemeThenGlobalThemeThenInherit() {
    let key = KeyboardAppearancePreference.keyboardKey
    XCTAssertEqual(KeyboardAppearancePreference.style(key, in: [key: "dark", "theme": "light"]), .dark)
    XCTAssertEqual(KeyboardAppearancePreference.style(key, in: [key: "light", "theme": "dark"]), .light)
    XCTAssertEqual(KeyboardAppearancePreference.style(key, in: [key: "follow", "theme": "dark"]), .dark)
    XCTAssertEqual(KeyboardAppearancePreference.style(key, in: [key: "follow", "theme": "system"]), .unspecified)
    XCTAssertEqual(KeyboardAppearancePreference.style(key, in: nil), .unspecified)
    XCTAssertEqual(KeyboardAppearancePreference.style(key, in: [key: "sepia"]), .unspecified)
  }

  /// Each panel reads its own field, not the keyboard's.
  func testPanelsReadTheirOwnFields() {
    let preferences: [String: Any] = [KeyboardAppearancePreference.keyboardKey: "dark",
                                      KeyboardAppearancePreference.emojiKey: "light"]
    XCTAssertEqual(KeyboardAppearancePreference.style(KeyboardAppearancePreference.emojiKey, in: preferences), .light)
    XCTAssertEqual(KeyboardAppearancePreference.style(KeyboardAppearancePreference.voiceKey, in: preferences), .unspecified)
  }

  /// What the skin page writes is what the shared document accepts and reads back.
  func testSkinPageWritesRoundTrip() {
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    let keys = [KeyboardAppearancePreference.keyboardKey] + KeyboardAppearancePreference.panels.map(\.key)
    for (key, value) in zip(keys, ["dark", "light", "follow", "dark"]) {
      XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) { $0[key] = value }, key)
    }
    let preferences = MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)
    XCTAssertEqual(KeyboardAppearancePreference.style(KeyboardAppearancePreference.keyboardKey, in: preferences), .dark)
    XCTAssertEqual(KeyboardAppearancePreference.style(KeyboardAppearancePreference.handwritingKey, in: preferences), .light)
    XCTAssertEqual(KeyboardAppearancePreference.style(KeyboardAppearancePreference.voiceKey, in: preferences), .dark)
  }

  func testTheSettingsThemeFallsBackToTheGlobalThemeThenTheDevice() {
    XCTAssertEqual(AppAppearancePreference.style(in: nil), .unspecified)
    XCTAssertEqual(AppAppearancePreference.style(in: ["settings_theme": "follow", "theme": "system"]), .unspecified)
    XCTAssertEqual(AppAppearancePreference.style(in: ["settings_theme": "follow", "theme": "dark"]), .dark)
    XCTAssertEqual(AppAppearancePreference.style(in: ["settings_theme": "light", "theme": "dark"]), .light)
    // The keyboard's own theme does not reach the app.
    XCTAssertEqual(AppAppearancePreference.style(in: ["screen_keyboard_theme": "dark"]), .unspecified)
  }
}
