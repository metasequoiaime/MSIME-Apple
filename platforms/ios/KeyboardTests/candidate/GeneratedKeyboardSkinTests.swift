import XCTest

final class GeneratedKeyboardSkinTests: XCTestCase {
  private let valid = ##"{"name":"青瓷庭院","design":{"background":"#E8F0EB","keyBackground":"#FFFFFF","keyForeground":"#17251D","accent":"#185C47","actionBackground":"#185C47","cornerRadius":12,"borderWidth":0.5,"shadow":0.1,"pattern":3}}"##
  func testGeneratedDesignIsParsedWithoutChangingActiveSkin() throws {
    let prior = CustomKeyboardSkinStore.current
    let item = try GeneratedKeyboardSkin.parse(valid)
    XCTAssertEqual(item.name, "青瓷庭院")
    XCTAssertEqual(item.design.cornerRadius, 12)
    XCTAssertTrue(item.design.hasReadableText)
    XCTAssertEqual(try GeneratedKeyboardSkin.parse("```json\n" + valid + "\n```").design, item.design)
    XCTAssertEqual(CustomKeyboardSkinStore.current, prior)
  }
  func testCompleteProviderResponseUsesSupportedFields() throws {
    let sample = ##"{"name":"雨后青竹","design":{"background":"#E8F1EB","keyBackground":"#F8FCF8","keyForeground":"#1A2B23","accent":"#185B45","actionBackground":"#185B45","gradientEnd":"#D7E7DC","customBorderColor":"#A6C2B3","cornerRadius":8,"borderWidth":0.6,"shadow":0.12,"pattern":3,"patternOpacity":0.04,"monospaced":false,"gradientHorizontal":false}}"##
    let item = try GeneratedKeyboardSkin.parse(sample)
    XCTAssertEqual(item.design.gradientEnd, 0xD7E7DC)
    XCTAssertEqual(item.design.customBorderColor, 0xA6C2B3)
    XCTAssertEqual(item.design.patternOpacity, 0.04)
    XCTAssertTrue(item.design.hasReadableText)
  }
  func testRejectsUnsafeIncompleteAndUnreadableDesigns() {
    for invalid in [
      valid.replacingOccurrences(of: "\"pattern\":3", with: "\"pattern\":3,\"photo\":\"https://example.com/image\""),
      valid.replacingOccurrences(of: "#E8F0EB", with: "red"),
      valid.replacingOccurrences(of: "#17251D", with: "#FFFFFF"),
      valid.replacingOccurrences(of: "\"cornerRadius\":12", with: "\"cornerRadius\":200"),
      valid.replacingOccurrences(of: "\"pattern\":3", with: "\"pattern\":9"),
      valid.replacingOccurrences(of: "\"pattern\":3", with: "\"pattern\":3,\"gradientEnd\":\"#185C47\""),
      "{}", String(repeating: "x", count: 16_385)
    ] { XCTAssertThrowsError(try GeneratedKeyboardSkin.parse(invalid)) }
  }
}
