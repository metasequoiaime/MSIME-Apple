import UIKit
import XCTest

/// The candidate and composition sizes come from the shared document the desktop settings also write, so a size synced from a desktop has to fit the surface drawing it.
@MainActor
final class CandidateFontSizeTests: XCTestCase {
  private var state: URL!

  override func setUp() {
    super.setUp()
    state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-candidate-font-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: state)
    super.tearDown()
  }

  func testDefaultsDrawTheStylesTheKeyboardAlreadyUsed() {
    XCTAssertEqual(CandidateFontPreference.candidateScale(in: [:], tablet: false), 1)
    XCTAssertEqual(CandidateFontPreference.preeditScale(in: nil, tablet: true), 1)
    XCTAssertEqual(
      CandidateFontPreference.font(.body, scale: 1).pointSize,
      UIFont.preferredFont(forTextStyle: .body).pointSize)
    XCTAssertEqual(
      KeyboardViewController.stripExtraHeight(glossLines: 1),
      KeyboardViewController.compositionRowHeight + KeyboardViewController.glossHeight(lines: 1),
      "the default sizes leave the keyboard height where it was")
  }

  func testAPhoneClampsADesktopSizeThatAnIPadKeeps() {
    let synced: [String: Any] = [CandidateFontPreference.candidateKey: 30, CandidateFontPreference.preeditKey: 24]
    XCTAssertEqual(CandidateFontPreference.candidateSize(in: synced, tablet: false), 24)
    XCTAssertEqual(CandidateFontPreference.candidateSize(in: synced, tablet: true), 30)
    XCTAssertEqual(CandidateFontPreference.preeditSize(in: synced, tablet: false), 20)
    XCTAssertEqual(CandidateFontPreference.preeditSize(in: synced, tablet: true), 24)
    XCTAssertEqual(CandidateFontPreference.candidateSize(in: [CandidateFontPreference.candidateKey: 4], tablet: true), 12)
  }

  func testLargerTextGrowsTheStripButSmallerTextKeepsTheTouchTarget() {
    let base = KeyboardViewController.candidateStripHeight(glossLines: 0)
    let larger = KeyboardViewController.candidateStripHeight(
      glossLines: 0, candidateScale: 24.0 / 18.0, preeditScale: 20.0 / 15.0)
    let smaller = KeyboardViewController.candidateStripHeight(
      glossLines: 0, candidateScale: 12.0 / 18.0, preeditScale: 12.0 / 15.0)
    XCTAssertGreaterThan(larger, base)
    XCTAssertEqual(smaller, base)
    XCTAssertEqual(
      KeyboardViewController.stripExtraHeight(glossLines: 0, candidateScale: 24.0 / 18.0, preeditScale: 20.0 / 15.0)
        - KeyboardViewController.stripExtraHeight(glossLines: 0),
      larger - base, "the keyboard grows by what the strip grew instead of taking it out of the keys")
  }

  func testTheExpandedPanelDrawsCandidatesAtTheChosenSize() throws {
    let panel = KeyboardCandidatePanelView(
      candidates: ["水杉"], preedit: "shuishan", candidateScale: 24.0 / 18.0, preeditScale: 1,
      display: { $0 }, onSelect: { _ in }, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
    panel.layoutIfNeeded()
    let chip = try XCTUnwrap(find("panelCandidate-1", in: panel) as? UIButton)
    let title = try XCTUnwrap(chip.configuration?.attributedTitle)
    let font = try XCTUnwrap(NSAttributedString(title).attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    XCTAssertGreaterThan(font.pointSize, UIFont.preferredFont(forTextStyle: .body).pointSize)
  }

  func testTheLiveSessionSeesASizeTheSettingsAppWrote() {
    let bridge = MetasequoiaInputSessionBridge(stateRoot: state)
    XCTAssertTrue(MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: state) {
      $0[CandidateFontPreference.candidateKey] = 22
    })
    let reloaded = expectation(description: "reload")
    var accepted = false
    bridge.reloadSharedPreferences { accepted = $0; reloaded.fulfill() }
    wait(for: [reloaded], timeout: 5)
    XCTAssertTrue(accepted, "the reload was refused")
    XCTAssertEqual(CandidateFontPreference.candidateSize(in: bridge.sharedPreferences, tablet: false), 22)
  }

  private func find(_ identifier: String, in view: UIView) -> UIView? {
    if view.accessibilityIdentifier == identifier { return view }
    for subview in view.subviews {
      if let found = find(identifier, in: subview) { return found }
    }
    return nil
  }
}
