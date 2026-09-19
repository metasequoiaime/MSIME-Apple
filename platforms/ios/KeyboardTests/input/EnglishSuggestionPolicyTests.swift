import XCTest

final class EnglishSuggestionPolicyTests: XCTestCase {
  func testWordStopsAtNonAsciiLettersAndBoundaries() {
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "我用iph"), "iph")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "こんにちはhel"), "hel")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "hello wor"), "wor")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "done. "), "")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "version2be"), "be")
  }

  func testWordNormalizesFullWidthLatinLetters() {
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "中文ｉｐｈ"), "iph")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "中文Ｈｅ"), "He")
  }

  func testReplacesTypedPrefixAndRestoresInitialCapital() {
    XCTAssertEqual(
      EnglishSuggestionPolicy.replacement(typed: "He", candidate: "hello", startedCapitalized: true),
      .init(deleteCount: 2, insert: "Hello"))
  }

  func testIdenticalCandidateDoesNotCreateAnEdit() {
    XCTAssertNil(EnglishSuggestionPolicy.replacement(typed: "hello", candidate: "hello", startedCapitalized: false))
  }

  func testLowercasePrefixStaysLowercase() {
    XCTAssertEqual(
      EnglishSuggestionPolicy.replacement(typed: "he", candidate: "hello", startedCapitalized: false),
      .init(deleteCount: 2, insert: "hello"))
  }

  func testFullWidthPrefixKeepsInitialCapitalSemanticsAndCharacterCount() {
    let typed = EnglishSuggestionPolicy.currentWord(before: "中文Ｈｅ")
    XCTAssertEqual(
      EnglishSuggestionPolicy.replacement(typed: typed, candidate: "hello", startedCapitalized: typed.first?.isUppercase ?? false),
      .init(deleteCount: 2, insert: "Hello"))
  }
}
