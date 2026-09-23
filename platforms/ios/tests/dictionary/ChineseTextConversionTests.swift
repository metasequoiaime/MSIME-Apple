import XCTest

final class ChineseTextConversionTests: XCTestCase {
  func testSimplifiedOutputIsUntouched() {
    XCTAssertEqual(ChineseTextConversion.outputString("水杉输入法", traditional: false), "水杉输入法")
  }

  func testTraditionalOutputUsesTheSharedPhraseTables() {
    XCTAssertEqual(ChineseTextConversion.outputString("水杉输入法", traditional: true), "水杉輸入法")
    // 发 is 發 or 髮 depending on the word; a character-by-character transform cannot tell.
    XCTAssertEqual(ChineseTextConversion.outputString("头发", traditional: true), "頭髮")
    XCTAssertEqual(ChineseTextConversion.outputString("发现", traditional: true), "發現")
  }

  func testTextWithoutSimplifiedCharactersPassesThrough() {
    XCTAssertEqual(ChineseTextConversion.outputString("", traditional: true), "")
    XCTAssertEqual(ChineseTextConversion.outputString("metasequoia", traditional: true), "metasequoia")
    XCTAssertEqual(ChineseTextConversion.outputString("，。！", traditional: true), "，。！")
    // Already-traditional and mixed text stays readable instead of being mangled.
    XCTAssertEqual(ChineseTextConversion.outputString("輸入法", traditional: true), "輸入法")
    XCTAssertEqual(ChineseTextConversion.outputString("输入 abc 法", traditional: true), "輸入 abc 法")
  }
}
