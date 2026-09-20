import XCTest

/// The two smart-punctuation follow-up gestures, across the Swift/ABI boundary.
///
/// The policies themselves are decided in `client-core` and tested there; what this covers is the
/// contract between the keyboard and that layer — that a real session answers with the shapes the
/// keyboard reads, and that the snapshots it hands back survive the round trip. A test host's
/// `textDocumentProxy` has no document, so the edit these decisions produce cannot be observed
/// here; the keyboard's own use of them is covered by the acceptance suite.
@MainActor
final class SmartPunctuationGestureTests: XCTestCase {
  /// JSON null arrives as `NSNull`, which is not `nil`. The keyboard reads these values through
  /// typed casts, which turn it into nothing; the assertions do the same rather than comparing
  /// against a sentinel the production code never sees.
  private func absent(_ value: Any?) -> Bool { value == nil || value is NSNull }

  /// Pressing the same mark again right after it landed replaces it with the Chinese one.
  func testRepeatedMarkIsOfferedTheChineseReplacement() {
    let bridge = MetasequoiaInputSessionBridge()
    _ = bridge.cancel()

    let armed = bridge.smartPunctuationArming(
      ascii: ",", commit: ",", timestampMilliseconds: 1_000, editorGeneration: 42,
      autoClosedPair: false)
    let snapshot = try? XCTUnwrap(armed["repeat"] as? [String: Any])
    XCTAssertNotNil(snapshot, "an ASCII comma the host committed should arm the repeat gesture")

    let decision = bridge.smartPunctuationDecision(
      character: ",", preceding: ",", timestampMilliseconds: 1_500, editorGeneration: 42,
      repeatSnapshot: snapshot, spaceSnapshot: nil)
    XCTAssertEqual(decision["replace_with"] as? String, "，")

    // Past the two-second window the press is an ordinary one again.
    let late = bridge.smartPunctuationDecision(
      character: ",", preceding: ",", timestampMilliseconds: 4_000, editorGeneration: 42,
      repeatSnapshot: snapshot, spaceSnapshot: nil)
    XCTAssertTrue(absent(late["replace_with"]))

    // A different editor is a different caret; the gesture does not follow the user there.
    let elsewhere = bridge.smartPunctuationDecision(
      character: ",", preceding: ",", timestampMilliseconds: 1_500, editorGeneration: 7,
      repeatSnapshot: snapshot, spaceSnapshot: nil)
    XCTAssertTrue(absent(elsewhere["replace_with"]))

    // The mark is no longer what is before the caret, so this press is about something else.
    let moved = bridge.smartPunctuationDecision(
      character: ",", preceding: "好", timestampMilliseconds: 1_500, editorGeneration: 42,
      repeatSnapshot: snapshot, spaceSnapshot: nil)
    XCTAssertTrue(absent(moved["replace_with"]))
  }

  /// The space conversion stays off until it is asked for, and says so through this boundary.
  ///
  /// It is off in the shipped preferences because it rewrites a character the user already
  /// watched land. Switching it on is the settings page's job, not this target's, so the enabled
  /// behaviour is covered where the switch can be set: `smart_punctuation_gestures_follow_their_own_switches`
  /// in the host-api tests. What matters here is that the default reaches the keyboard intact.
  func testSpaceConversionStaysOffUntilItIsAskedFor() {
    let bridge = MetasequoiaInputSessionBridge()
    _ = bridge.cancel()
    let armed = bridge.smartPunctuationArming(
      ascii: ".", commit: "。", timestampMilliseconds: 2_000, editorGeneration: 42,
      autoClosedPair: false)
    // The ASCII press never landed, so the repeat gesture has nothing to be about either.
    XCTAssertTrue(absent(armed["repeat"]))
    XCTAssertTrue(absent(armed["space"]), "space conversion is off in the shipped preferences")

    let decision = bridge.smartPunctuationDecision(
      character: " ", preceding: "。", timestampMilliseconds: 2_100, editorGeneration: 42,
      repeatSnapshot: nil, spaceSnapshot: nil)
    XCTAssertTrue(absent(decision["space_ascii"]), "nothing armed, so the space belongs to the editor")
  }

  /// Neither gesture arms without an editor to belong to.
  func testNothingArmsWithoutACommit() {
    let bridge = MetasequoiaInputSessionBridge()
    _ = bridge.cancel()
    let armed = bridge.smartPunctuationArming(
      ascii: ",", commit: "", timestampMilliseconds: 0, editorGeneration: 1,
      autoClosedPair: false)
    XCTAssertTrue(absent(armed["repeat"]))
    XCTAssertTrue(absent(armed["space"]))
  }
}
