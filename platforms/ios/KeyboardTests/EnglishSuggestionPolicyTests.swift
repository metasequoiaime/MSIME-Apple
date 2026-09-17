import XCTest

final class EnglishSuggestionPolicyTests: XCTestCase {
  // 「我用iph」这种句子最常见:中文后面不空格直接打英文。取词时若把汉字也算作字母,整条前缀会被送去查,
  // 而英文词库只接受 a-z、一个字符不合就整条拒掉 —— 表现是候选一条都不出,而且不报错。
  func testTheWordStopsAtTheLastNonAsciiLetter() {
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "我用iph"), "iph")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "こんにちはhel"), "hel")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "我用"), "")
  }

  func testTheWordIsWhatWasTypedSinceTheLastBoundary() {
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "hello wor"), "wor")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "hello"), "hello")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: ""), "")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "done. "), "")
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "line\nnew"), "new")
    // 撇号断词是可以接受的:don't 之后补全的是 t,而不是一个查不到的 don't。
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "don't"), "t")
    // 数字也断词 —— version2be 里要补全的不是整串。
    XCTAssertEqual(EnglishSuggestionPolicy.currentWord(before: "version2be"), "be")
  }

  // 选中候选后要退掉几个字符、插入什么。少退一个,上一个词的尾巴会粘在新词前面;丢掉大小写,句首永远小写。
  // 两种都不会报错,只会让人觉得这个功能不对劲。
  func testReplacementDeletesExactlyWhatWasTyped() {
    let replacement = EnglishSuggestionPolicy.replacement(
      typed: "hel", candidate: "hello", startedCapitalized: false)
    XCTAssertEqual(replacement, EnglishSuggestionPolicy.Replacement(deleteCount: 3, insert: "hello"))
  }

  func testACapitalisedStartCarriesIntoTheSuggestion() {
    let replacement = EnglishSuggestionPolicy.replacement(
      typed: "Hel", candidate: "hello", startedCapitalized: true)
    XCTAssertEqual(replacement, EnglishSuggestionPolicy.Replacement(deleteCount: 3, insert: "Hello"))
  }

  // 候选和已敲的一模一样时不该动文档:退掉再原样插回去,在别的输入法看来是一次真实编辑,撤销栈也会多一步。
  func testAnIdenticalSuggestionLeavesTheDocumentAlone() {
    XCTAssertNil(EnglishSuggestionPolicy.replacement(
      typed: "hello", candidate: "hello", startedCapitalized: false))
    XCTAssertNil(EnglishSuggestionPolicy.replacement(
      typed: "Hello", candidate: "hello", startedCapitalized: true))
    XCTAssertNil(EnglishSuggestionPolicy.replacement(
      typed: "hel", candidate: "", startedCapitalized: false))
  }
}
