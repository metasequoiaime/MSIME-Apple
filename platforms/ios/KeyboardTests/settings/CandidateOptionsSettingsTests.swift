import XCTest

/// The settings app's candidate page merges single fields into nested objects of the shared document; the keyboard has to act on them.
final class CandidateOptionsSettingsTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-candidate-options-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  /// Writing one field of `mixed_input` leaves the object's other fields as stored.
  func testNestedWriteKeepsTheRestOfTheObject() throws {
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    let before = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)?["mixed_input"] as? [String: Any])

    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      var mixed = $0["mixed_input"] as? [String: Any] ?? [:]
      mixed["emoji"] = true
      $0["mixed_input"] = mixed
    })

    let after = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)?["mixed_input"] as? [String: Any])
    XCTAssertEqual(after["emoji"] as? Bool, true)
    XCTAssertEqual(after["english"] as? Bool, before["english"] as? Bool)
    XCTAssertEqual((after["minimum_prefix"] as? NSNumber)?.intValue, (before["minimum_prefix"] as? NSNumber)?.intValue)
  }

  /// Transposition correction turned on in the app reaches the session the keyboard already has.
  func testReloadHandsTypoCorrectionToTheLiveSession() {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    // The engine's own autocorrect check: with transposition on, gau leads with 挂 (gua).
    XCTAssertNotEqual(firstCandidates(bridge, "gau").first, "挂", "transposition correction ships off")

    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      var quanpin = $0["quanpin"] as? [String: Any] ?? [:]
      quanpin["autocorrect_transposition"] = true
      $0["quanpin"] = quanpin
    })
    let reloaded = expectation(description: "reload")
    var accepted = false
    bridge.reloadSharedPreferences { accepted = $0; reloaded.fulfill() }
    wait(for: [reloaded], timeout: 5)
    XCTAssertTrue(accepted, "the reload was refused")

    XCTAssertEqual(firstCandidates(bridge, "gau").first, "挂")
  }

  /// The first few candidate texts after typing `letters` from an empty composition, which is then abandoned.
  private func firstCandidates(_ bridge: MetasequoiaInputSessionBridge, _ letters: String) -> [String] {
    var snapshot = bridge.cancel()
    for letter in letters { snapshot = bridge.handleCharacter(String(letter)) }
    let texts = snapshot.candidates.prefix(5).map { String($0.split(separator: "\n").first ?? "") }
    _ = bridge.cancel()
    return texts
  }
}
