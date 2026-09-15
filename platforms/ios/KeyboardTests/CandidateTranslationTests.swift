import XCTest

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
}
