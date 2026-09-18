import UIKit
import XCTest

private final class StubTranslationService: CandidateTranslationService, @unchecked Sendable {
  private let answers: [String: [String: String]]
  private let lock = NSLock()
  private var recorded: [(code: String, words: [String])] = []

  init(answers: [String: [String: String]]) { self.answers = answers }

  var calls: [(code: String, words: [String])] {
    lock.lock(); defer { lock.unlock() }
    return recorded
  }

  func translate(words: [String], target: String) async throws -> [String] {
    lock.lock()
    recorded.append((target, words))
    lock.unlock()
    return words.map { answers[target]?[$0] ?? "" }
  }
}

private struct TruncatingTranslationService: CandidateTranslationService {
  func translate(words: [String], target: String) async throws -> [String] {
    Array(words.dropLast()).map { $0 + "?" }
  }
}

@MainActor
final class CandidateTranslationTests: XCTestCase {
  func testOnlyCandidatesWithHanCharactersGoOutToTheNetwork() {
    XCTAssertTrue(CandidateTranslationStore.translatable("你好"))
    XCTAssertTrue(CandidateTranslationStore.translatable("啊"))
    XCTAssertFalse(CandidateTranslationStore.translatable("nihao"))
    XCTAssertFalse(CandidateTranslationStore.translatable("OpenAI"))
    XCTAssertFalse(CandidateTranslationStore.translatable("123"))
    XCTAssertFalse(CandidateTranslationStore.translatable("😀"))
  }

  func testEachLanguageIsAskedOnceAndTheAnswerIsKept() async throws {
    let service = StubTranslationService(
      answers: ["EN": ["你好": "hello"], "JA": ["你好": "こんにちは"]])
    let store = CandidateTranslationStore(service: service)
    let arrived = expectation(description: "gloss arrived")
    arrived.expectedFulfillmentCount = 2
    store.onArrival = { arrived.fulfill() }

    store.refresh(words: ["你好", "nihao"], codes: ["EN", "JA"])
    await fulfillment(of: [arrived], timeout: 5)
    XCTAssertEqual(store.gloss(word: "你好", code: "EN"), "hello")
    XCTAssertEqual(store.gloss(word: "你好", code: "JA"), "こんにちは")
    XCTAssertEqual(service.calls.count, 2)
    XCTAssertTrue(service.calls.allSatisfy { $0.words == ["你好"] })

    store.refresh(words: ["你好", "nihao"], codes: ["EN", "JA"])
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertEqual(service.calls.count, 2)
  }

  func testAResponseWithTheWrongCountIsDropped() async throws {
    let store = CandidateTranslationStore(service: TruncatingTranslationService())
    store.refresh(words: ["你好", "中国"], codes: ["EN"])
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertNil(store.gloss(word: "你好", code: "EN"))
    XCTAssertNil(store.gloss(word: "中国", code: "EN"))
  }

  func testQueuedRequestIsCancelledWhenCompositionEnds() async throws {
    let service = StubTranslationService(answers: ["EN": ["你好": "hello"]])
    let store = CandidateTranslationStore(service: service)
    store.refresh(words: ["你好"], codes: ["EN"])
    store.cancel()
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertTrue(service.calls.isEmpty)
  }

  func testExpandedPanelRendersAnnotationsAndDeferredMenus() throws {
    let panel = KeyboardCandidatePanelView(
      candidates: ["你好", "泥嚎"], preedit: "nihao",
      annotations: [
        KeyboardCandidateAnnotation(text: "hello\nこんにちは", accessibilityDescription: "释义"),
        .none,
      ], display: { $0 }, menuElements: { _ in [UIAction(title: "hello") { _ in }] },
      onSelect: { _ in }, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 240)
    panel.layoutIfNeeded()

    let glossed = try XCTUnwrap(
      descendants(panel).first { $0.accessibilityIdentifier == "panelCandidate-1" } as? UIButton)
    let title = try XCTUnwrap(glossed.configuration?.attributedTitle.map { String($0.characters) })
    XCTAssertEqual(title.split(separator: "\n", omittingEmptySubsequences: false),
                   ["你好", "hello", "こんにちは"])
    XCTAssertTrue(glossed.menu?.children.first is UIDeferredMenuElement)
    XCTAssertFalse(glossed.showsMenuAsPrimaryAction)

    let bare = try XCTUnwrap(
      descendants(panel).first { $0.accessibilityIdentifier == "panelCandidate-2" } as? UIButton)
    XCTAssertEqual(bare.configuration?.title, "泥嚎")
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}
