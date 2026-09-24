import XCTest

/// The settings app writes `default_ime_mode` into the shared document; a new keyboard has to see the value it wrote rather than one the bridge laid over it.
@MainActor
final class DefaultImeModeTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-default-ime-mode-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testOnlyAnExplicitEnglishStartsInEnglish() {
    XCTAssertTrue(KeyboardViewController.startsInChinese(nil))
    XCTAssertTrue(KeyboardViewController.startsInChinese([:]))
    XCTAssertTrue(KeyboardViewController.startsInChinese(["default_ime_mode": "chinese"]))
    XCTAssertTrue(KeyboardViewController.startsInChinese(["default_ime_mode": "klingon"]))
    XCTAssertFalse(KeyboardViewController.startsInChinese(["default_ime_mode": "english"]))
  }

  func testANewSessionSeesTheModeTheSettingsAppWrote() async throws {
    XCTAssertTrue(KeyboardViewController.startsInChinese(
      MetasequoiaInputSessionBridge(stateRoot: state).sharedPreferences), "the shared default is Chinese")
    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      $0["default_ime_mode"] = "english"
    })
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertFalse(KeyboardViewController.startsInChinese(bridge.sharedPreferences))

    let reloaded = expectation(description: "reload")
    var accepted = false
    bridge.reloadSharedPreferences { accepted = $0; reloaded.fulfill() }
    await fulfillment(of: [reloaded], timeout: 15)
    XCTAssertTrue(accepted, "the reload was refused")
    XCTAssertFalse(KeyboardViewController.startsInChinese(bridge.sharedPreferences), "a reload keeps the stored mode too")
  }
}
