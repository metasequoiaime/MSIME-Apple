import XCTest

/// 繁体输出 goes through the shared OpenCC s2t tables in the Rust library, so iOS commits the same characters as the Windows, macOS, Linux, Android and HarmonyOS hosts.
final class ChineseTextConversionTests: XCTestCase {
  func testSimplifiedOutputIsUntouched() {
    XCTAssertEqual(ChineseTextConversion.outputString("水杉输入法", traditional: false), "水杉输入法")
    XCTAssertEqual(ChineseTextConversion.outputString("头发", traditional: false), "头发")
  }

  func testTraditionalOutputConvertsThroughTheSharedTables() {
    XCTAssertEqual(ChineseTextConversion.outputString("水杉输入法", traditional: true), "水杉輸入法")
  }

  /// A character transform turns both into 發; the phrase tables know 头发 is hair.
  func testOneToManyCharactersResolveByPhrase() {
    XCTAssertEqual(ChineseTextConversion.outputString("头发", traditional: true), "頭髮")
    XCTAssertEqual(ChineseTextConversion.outputString("发展", traditional: true), "發展")
  }

  func testTextWithoutATraditionalFormIsUnchanged() {
    XCTAssertEqual(ChineseTextConversion.outputString("", traditional: true), "")
    XCTAssertEqual(ChineseTextConversion.outputString("metasequoia", traditional: true), "metasequoia")
    XCTAssertEqual(ChineseTextConversion.outputString("，。！", traditional: true), "，。！")
    XCTAssertEqual(ChineseTextConversion.outputString("😀", traditional: true), "😀")
  }

  func testAlreadyTraditionalAndMixedTextStaysReadable() {
    XCTAssertEqual(ChineseTextConversion.outputString("輸入法", traditional: true), "輸入法")
    XCTAssertEqual(ChineseTextConversion.outputString("输入 abc 法", traditional: true), "輸入 abc 法")
  }

  /// The C ABI refuses text it cannot hand back as a C string; the keyboard keeps the original rather than dropping it.
  func testTextTheConverterRefusesIsKept() {
    XCTAssertEqual(ChineseTextConversion.outputString("输\u{0}入", traditional: true), "输\u{0}入")
  }
}
