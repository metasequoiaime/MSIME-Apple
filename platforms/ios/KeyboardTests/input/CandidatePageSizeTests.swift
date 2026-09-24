import XCTest

/// The page size is an iOS switch laid over the shared document, and the digits follow it.
@MainActor
final class CandidatePageSizeTests: XCTestCase {
  private var state: URL!
  private var storedPreference: Any?

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-page-size-\(UUID().uuidString)", isDirectory: true)
    storedPreference = CandidatePageSizePreference.defaults.object(forKey: CandidatePageSizePreference.key)
  }

  override func tearDown() {
    CandidatePageSizePreference.defaults.set(storedPreference, forKey: CandidatePageSizePreference.key)
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testOutOfRangeValuesFallBackToNine() {
    XCTAssertEqual(CandidatePageSizePreference.clamped(nil), 9)
    XCTAssertEqual(CandidatePageSizePreference.clamped(0), 9)
    XCTAssertEqual(CandidatePageSizePreference.clamped(12), 9)
    XCTAssertEqual(CandidatePageSizePreference.clamped(4), 4)
    CandidatePageSizePreference.defaults.set(20, forKey: CandidatePageSizePreference.key)
    XCTAssertEqual(CandidatePageSizePreference.size, 9)
  }

  func testTheSessionPagesByTheIOSValueAndADigitPastItPicksNothing() throws {
    CandidatePageSizePreference.size = 3
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertEqual(bridge.sharedPreferences?["candidate_page_size"] as? Int, 3)
    _ = bridge.cancel()
    var snapshot = bridge.cancel()
    for letter in "shi" { snapshot = bridge.handleCharacter(String(letter)) }
    // The snapshot carries the engine's page, so its length is the page size the engine was given.
    XCTAssertEqual(snapshot.candidates.count, 3)

    // The session refuses it with a diagnostic and keeps the composition, which the keyboard must not read as "nothing composing".
    let past = bridge.handleCandidateKey("4")
    XCTAssertFalse(past.isHandled)
    XCTAssertNil(past.commitText, "a digit with no chip on the page must not commit")
    XCTAssertTrue(KeyboardViewController.digitHasNoChip("4", chips: 3, composing: true))
    let third = snapshot.candidates[2]
    XCTAssertEqual(bridge.handleCandidateKey("3").commitText, third)
  }

  func testOnlyADigitPastTheChipsWhileComposingIsSwallowed() {
    XCTAssertFalse(KeyboardViewController.digitHasNoChip("3", chips: 3, composing: true))
    XCTAssertTrue(KeyboardViewController.digitHasNoChip("7", chips: 5, composing: true), "a short last page")
    XCTAssertTrue(KeyboardViewController.digitHasNoChip("1", chips: 0, composing: true), "a spelling with no candidates")
    XCTAssertFalse(KeyboardViewController.digitHasNoChip("7", chips: 0, composing: false), "with nothing composing a digit is typed")
  }

  func testAChangeReachesTheLiveSessionOnReload() throws {
    CandidatePageSizePreference.size = 9
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertEqual(bridge.sharedPreferences?["candidate_page_size"] as? Int, 9)
    // The settings app writes the switch and then the document; any newer document carries the switch to the session.
    CandidatePageSizePreference.size = 5
    XCTAssertTrue(bridge.setTouchKeyboardScheme(.quanpin, enabledSchemes: [.quanpin]))
    let reloaded = expectation(description: "shared preferences reloaded")
    bridge.reloadSharedPreferences { accepted in
      XCTAssertTrue(accepted)
      reloaded.fulfill()
    }
    wait(for: [reloaded], timeout: 10)
    XCTAssertEqual(bridge.sharedPreferences?["candidate_page_size"] as? Int, 5)
    var snapshot = bridge.cancel()
    for letter in "shi" { snapshot = bridge.handleCharacter(String(letter)) }
    XCTAssertEqual(snapshot.candidates.count, 5)
    XCTAssertNil(bridge.handleCandidateKey("6").commitText)
  }
}
