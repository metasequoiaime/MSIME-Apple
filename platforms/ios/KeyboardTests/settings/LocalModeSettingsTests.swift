import XCTest

/// The settings app's local-mode page merges single fields into `local_modes`; the session the keyboard already has must stop opening a mode turned off there.
final class LocalModeSettingsTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-local-modes-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testReloadTurnsAModeOffInTheLiveSession() async {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertTrue(opens(bridge, "T"), "date and time ship on")
    XCTAssertTrue(opens(bridge, "U"), "Unicode ships on")

    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      var modes = $0["local_modes"] as? [String: Any] ?? [:]
      modes["date_time"] = false
      $0["local_modes"] = modes
    })
    let reloaded = expectation(description: "reload")
    var accepted = false
    bridge.reloadSharedPreferences { accepted = $0; reloaded.fulfill() }
    await fulfillment(of: [reloaded], timeout: 15)
    XCTAssertTrue(accepted, "the reload was refused")

    XCTAssertFalse(opens(bridge, "T"))
    XCTAssertTrue(opens(bridge, "U"), "turning one mode off leaves the others")
    let stored = MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)?["local_modes"] as? [String: Any]
    XCTAssertEqual(stored?["unicode"] as? Bool, true, "the merge kept the object's other fields")
  }

  /// Whether the mode opened by `trigger` is running afterwards; the attempt is then abandoned.
  private func opens(_ bridge: MetasequoiaInputSessionBridge, _ trigger: String) -> Bool {
    _ = bridge.cancel()
    let opened = bridge.openLocalMode(trigger).isInLocalMode
    _ = bridge.cancel()
    return opened
  }
}
