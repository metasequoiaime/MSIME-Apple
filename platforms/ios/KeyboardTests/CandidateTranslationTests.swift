import XCTest
import UIKit

private struct StubTranslationService: CandidateTranslationService, Sendable {
  let answers: [String: [String: String]]
  func translate(words: [String], target: String) async throws -> [String] {
    words.map { answers[target]?[$0] ?? "" }
  }
}

@MainActor
final class CandidateTranslationTests: XCTestCase {
  func testCandidateGlossesAreEnabledByDefault() {
    let defaults = CandidateGlossPreference.defaults
    let previous = defaults.object(forKey: CandidateGlossPreference.key)
    defer {
      if let previous { defaults.set(previous, forKey: CandidateGlossPreference.key) }
      else { defaults.removeObject(forKey: CandidateGlossPreference.key) }
    }
    defaults.removeObject(forKey: CandidateGlossPreference.key)
    XCTAssertTrue(CandidateGlossPreference.enabled)
  }

  func testOnlyHanCandidatesAreTranslatable() {
    XCTAssertTrue(CandidateTranslationStore.translatable("你好"))
    XCTAssertFalse(CandidateTranslationStore.translatable("nihao"))
    XCTAssertFalse(CandidateTranslationStore.translatable("OpenAI"))
    XCTAssertFalse(CandidateTranslationStore.translatable("😀"))
  }

  func testBatchesEachLanguageAndCachesResults() async throws {
    let service = StubTranslationService(answers: ["EN": ["你好": "hello"], "JA": ["你好": "こんにちは"]])
    let store = CandidateTranslationStore(service: service)
    let arrived = expectation(description: "translations arrived")
    arrived.expectedFulfillmentCount = 2
    store.onArrival = { arrived.fulfill() }

    store.refresh(words: ["你好", "nihao"], codes: ["EN", "JA"])
    await fulfillment(of: [arrived], timeout: 3)
    XCTAssertEqual(store.gloss(word: "你好", code: "EN"), "hello")
    XCTAssertEqual(store.gloss(word: "你好", code: "JA"), "こんにちは")
    store.refresh(words: ["你好", "nihao"], codes: ["EN", "JA"])
    try await Task.sleep(nanoseconds: 600_000_000)
  }

  func testMismatchedBatchIsDiscarded() async throws {
    struct ShortService: CandidateTranslationService {
      func translate(words: [String], target: String) async throws -> [String] { ["only one"] }
    }
    let store = CandidateTranslationStore(service: ShortService())
    store.refresh(words: ["你好", "中国"], codes: ["EN"])
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertNil(store.gloss(word: "你好", code: "EN"))
    XCTAssertNil(store.gloss(word: "中国", code: "EN"))
  }

  func testGlossRowsOnlyReserveSpaceWhenTheyCanBeFilled() {
    let defaults = CandidateGlossPreference.defaults
    let previousGloss = defaults.object(forKey: CandidateGlossPreference.key)
    let previousSecondary = defaults.object(forKey: CandidateTranslationPreference.secondaryKey)
    defer {
      if let previousGloss { defaults.set(previousGloss, forKey: CandidateGlossPreference.key) }
      else { defaults.removeObject(forKey: CandidateGlossPreference.key) }
      if let previousSecondary { defaults.set(previousSecondary, forKey: CandidateTranslationPreference.secondaryKey) }
      else { defaults.removeObject(forKey: CandidateTranslationPreference.secondaryKey) }
    }
    CandidateGlossPreference.enabled = false
    CandidateTranslationPreference.secondaryIndex = -1
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: true), 0)
    CandidateGlossPreference.enabled = true
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: false), 1)
    CandidateTranslationPreference.secondaryIndex = 1
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: false), 1)
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: true), 2)
  }

  func testExpandedPanelChipFitsItsWidestAnnotationLine() {
    let panel = KeyboardCandidatePanelView(
      candidates: ["您好", "你好"], preedit: "nhao",
      annotations: [
        KeyboardCandidateAnnotation(text: "hello; how do you do", accessibilityDescription: "英文释义：hello; how do you do"),
        .none,
      ], display: { $0 }, onSelect: { _ in }, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 240)
    panel.layoutIfNeeded()
    let chip = panel.subviews
      .flatMap { descendants($0) }
      .compactMap { $0 as? UIButton }
      .first { $0.accessibilityIdentifier == "panelCandidate-1" }
    XCTAssertNotNil(chip)
    let gloss = NSAttributedString(string: "hello; how do you do",
                                   attributes: [.font: UIFont.preferredFont(forTextStyle: .caption2)])
    XCTAssertGreaterThanOrEqual(chip?.bounds.width ?? 0, gloss.size().width)
  }

  func testExpandedPanelChipsAnswerALongPress() throws {
    // The panel builds its own chips and used to give them no menu, so the press that manages an
    // entry on the strip did nothing once the list was expanded.
    let panel = KeyboardCandidatePanelView(
      candidates: ["你好", "泥嚎"], preedit: "nihao",
      display: { $0 },
      menuElements: { _ in [UIAction(title: "优先显示") { _ in }] },
      onSelect: { _ in }, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 240)
    panel.layoutIfNeeded()

    let chip = try XCTUnwrap(
      descendants(panel).first { $0.accessibilityIdentifier == "panelCandidate-1" } as? UIButton)
    // The elements are built when the press opens the menu, so only the placeholder is visible
    // here: the panel lays out the engine's whole answer, which can be several hundred chips.
    XCTAssertTrue(chip.menu?.children.first is UIDeferredMenuElement, "格子要挂上长按菜单")
    XCTAssertFalse(chip.showsMenuAsPrimaryAction, "轻点仍然是上屏，菜单走长按")
  }

  func testLanguageTableAnswersTheFirstEntryForAnIndexOutOfRange() {
    // The table has grown before and will again. An index written by a newer build must not decide
    // what an older one reads out of range.
    XCTAssertEqual(CandidateTranslationPreference.language(at: 0).code, "EN")
    XCTAssertEqual(CandidateTranslationPreference.language(at: 1).code, "JA")
    XCTAssertEqual(CandidateTranslationPreference.language(at: -1).code, "EN")
    XCTAssertEqual(
      CandidateTranslationPreference.language(at: CandidateTranslationPreference.languages.count).code,
      "EN")
  }
}

private func descendants(_ view: UIView) -> [UIView] {
  [view] + view.subviews.flatMap(descendants)
}
