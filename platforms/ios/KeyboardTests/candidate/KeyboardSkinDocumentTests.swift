import XCTest

/// A skin picked or designed in the app has to reach the shared document: the keyboard copies the document's skin over the App Group every time it appears.
final class KeyboardSkinDocumentTests: XCTestCase {
  private var state: URL!
  private var previousSkin: String?
  private var previousDesign: Data?

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-skin-document-\(UUID().uuidString)", isDirectory: true)
    previousSkin = KeyboardFeedbackPreference.defaults.string(forKey: KeyboardSkinPreference.key)
    previousDesign = KeyboardFeedbackPreference.defaults.data(forKey: CustomKeyboardSkinStore.key)
  }

  override func tearDown() {
    let defaults = KeyboardFeedbackPreference.defaults
    if let previousSkin { defaults.set(previousSkin, forKey: KeyboardSkinPreference.key) }
    else { defaults.removeObject(forKey: KeyboardSkinPreference.key) }
    if let previousDesign { defaults.set(previousDesign, forKey: CustomKeyboardSkinStore.key) }
    else { defaults.removeObject(forKey: CustomKeyboardSkinStore.key) }
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testBuiltInSelectionReachesTheDocument() throws {
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertTrue(KeyboardSkinPreference.save(.midnight, stateRoot: state))
    let document = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state))
    XCTAssertEqual(document["touch_keyboard_skin"] as? String, "midnight")
    XCTAssertEqual(KeyboardSkinPreference.selected, .midnight)
  }

  /// A photo design is far larger than the 16 KiB other buffers are held to; the document still takes it, and the keyboard reads back the same design.
  func testCustomDesignWithAPhotoRoundTripsThroughTheDocument() throws {
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    var design = CustomKeyboardSkin(background: 0x203040, keyShape: .capsule)
    design.photo = Data([0xFF, 0xD8, 0xFF]) + Data(count: 40_000)
    design.photoShade = 0.4

    XCTAssertTrue(KeyboardSkinPreference.save(.custom, design: design, stateRoot: state))

    let document = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state))
    XCTAssertEqual(document["touch_keyboard_skin"] as? String, "custom")
    let stored = try XCTUnwrap(document["custom_touch_keyboard_skin"] as? [String: Any])
    let decoded = try JSONDecoder().decode(
      CustomKeyboardSkin.self, from: JSONSerialization.data(withJSONObject: stored))
    XCTAssertEqual(decoded.normalized, design.normalized)
    XCTAssertEqual(CustomKeyboardSkinStore.current, design.normalized)
    XCTAssertEqual(KeyboardSkinPreference.selected, .custom)
  }
}
