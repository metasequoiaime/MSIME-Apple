import XCTest

/// The app's scheme and output-form choices reach the shared document, which the keyboard copies over the App Group every time it appears.
final class SchemeDocumentSettingsTests: XCTestCase {
  private var state: URL!
  private var previousScheme = ChineseInputScheme.quanpin
  private var previousEnabled: [ChineseInputScheme] = []
  private var previousTraditional = false

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-scheme-document-\(UUID().uuidString)", isDirectory: true)
    previousEnabled = InputSchemePreference.enabledSchemes
    previousScheme = InputSchemePreference.scheme
    previousTraditional = ChineseOutputPreference.usesTraditional
  }

  override func tearDown() {
    InputSchemePreference.enabledSchemes = previousEnabled
    InputSchemePreference.scheme = previousScheme
    ChineseOutputPreference.usesTraditional = previousTraditional
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  /// The keyboard's own switch wrote `touch_keyboard_schemes` first; a later choice in the app has to replace it there, not only in the App Group.
  func testAppSchemeChoiceReplacesTheKeyboardsEarlierSelection() throws {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertTrue(bridge.setTouchKeyboardScheme(.nineKey, enabledSchemes: [.quanpin, .nineKey]))

    XCTAssertTrue(InputSchemePreference.save(scheme: .wubi, enabled: [.quanpin, .nineKey, .wubi], stateRoot: state))

    let document = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state))
    let schemes = try XCTUnwrap(document["touch_keyboard_schemes"] as? [String: Any])
    XCTAssertEqual(schemes["selected"] as? String, ChineseInputScheme.wubi.sharedIdentifier)
    XCTAssertEqual(schemes["enabled"] as? [String], [ChineseInputScheme.quanpin, .nineKey, .wubi].map(\.sharedIdentifier))
    XCTAssertEqual(document["scheme"] as? String, "wubi")
    XCTAssertEqual(document["touch_keyboard_layout"] as? String, "twenty_six_key")
    XCTAssertEqual(InputSchemePreference.scheme, .wubi)
  }

  func testTraditionalOutputReachesTheDocument() throws {
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertTrue(ChineseOutputPreference.save(true, stateRoot: state))
    let document = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state))
    XCTAssertEqual(document["traditional_chinese_output"] as? Bool, true)
    XCTAssertTrue(ChineseOutputPreference.usesTraditional)
  }
}
