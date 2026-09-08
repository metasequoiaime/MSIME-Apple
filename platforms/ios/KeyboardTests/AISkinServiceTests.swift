import Foundation
import XCTest

final class AISkinServiceTests: XCTestCase {
  private func response(_ transform: (inout [[String:Any]]) -> Void = { _ in }) throws -> String {
    var designs: [[String:Any]] = (0..<3).map { index in
      ["name":"测试设计 \(index)","description":"合成测试方案","background":"#FFFFFF","keyBackground":"#F0F0F0",
       "keyForeground":"#FFFFFF","accent":"#FFFFFF","actionBackground":"#185C47","gradientEnd":NSNull(),
       "gradientHorizontal":false,"cornerRadius":index * 5,"borderWidth":0,"shadow":0.1,"pattern":index,"monospaced":false]
    }
    transform(&designs)
    return String(data:try JSONSerialization.data(withJSONObject:["skins":designs]),encoding:.utf8)!
  }
  func testThreeEditableDesignsRepairContrastAndRoundTrip() throws {
    let proposals = try AISkinService.parse(response())
    XCTAssertEqual(proposals.count,3)
    XCTAssertEqual(Set(proposals.map(\.design)).count,3)
    for proposal in proposals {
      XCTAssertTrue(proposal.design.hasReadableText)
      XCTAssertNil(proposal.design.photo)
      let saved = SavedKeyboardSkin(name:proposal.name,design:proposal.design)
      let restored = try JSONDecoder().decode(SavedKeyboardSkin.self,from:JSONEncoder().encode(saved))
      XCTAssertEqual(restored.design,proposal.design)
    }
  }
  func testRecordedCloudResponseProducesThreeSaveableDesigns() throws {
    let file = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"AISkinReference",withExtension:"json"))
    let proposals = try AISkinService.parse(String(contentsOf:file,encoding:.utf8))
    XCTAssertEqual(proposals.count,3)
    XCTAssertEqual(proposals.first?.name,"静谧奶油")
    for proposal in proposals {
      XCTAssertTrue(proposal.design.hasReadableText)
      XCTAssertEqual(try JSONDecoder().decode(CustomKeyboardSkin.self,from:JSONEncoder().encode(proposal.design)),proposal.design)
    }
  }
  func testInvalidOrDuplicateDesignNeverBecomesASkin() throws {
    for text in ["```json\n{}\n```", "{}", try response { $0.removeLast() },
                 try response { $0[0]["background"] = "https://example.com/image.png" },
                 try response { $0[0]["cornerRadius"] = 100 },
                 try response { $0[1] = $0[0] },
                 try response { $0[0]["background"] = "#000000"; $0[0]["keyBackground"] = "#FFFFFF" }] {
      XCTAssertThrowsError(try AISkinService.parse(text))
    }
  }
}
