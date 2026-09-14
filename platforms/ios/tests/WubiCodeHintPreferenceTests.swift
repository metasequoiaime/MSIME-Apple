import XCTest

final class WubiCodeHintPreferenceTests: XCTestCase {
  func testHintReturnsOnlyUntypedSuffix() {
    XCTAssertEqual(
      WubiCodeHintPreference.hint(
        code: "wqb", typed: "wq", answeredByPinyinFallback: false),
      "b")
    XCTAssertEqual(
      WubiCodeHintPreference.hint(
        code: "wq", typed: "wq", answeredByPinyinFallback: false),
      "")
  }

  func testHintRejectsFallbackAndUnrelatedCodes() {
    XCTAssertEqual(
      WubiCodeHintPreference.hint(
        code: "wqb", typed: "wq", answeredByPinyinFallback: true),
      "")
    XCTAssertEqual(
      WubiCodeHintPreference.hint(
        code: "ni'hao", typed: "nihao", answeredByPinyinFallback: false),
      "")
    XCTAssertEqual(
      WubiCodeHintPreference.hint(
        code: String(repeating: "w", count: 65), typed: "w", answeredByPinyinFallback: false),
      "")
  }
}
