import Foundation
import XCTest

final class CandidateGlossModelTests: XCTestCase {
  func testRequestPreservesGenerationAndCandidateSources() throws {
    let data = try CandidateGlossModel.request(generation: 7, candidates: [
      ["text": "你好", "source": 0],
      ["text": "hello", "source": 1],
    ])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual((object["generation"] as? NSNumber)?.uint64Value, 7)
    let candidates = try XCTUnwrap(object["candidates"] as? [[String: Any]])
    XCTAssertEqual(candidates[0]["text"] as? String, "你好")
    XCTAssertEqual((candidates[1]["source"] as? NSNumber)?.intValue, 1)
  }

  func testDecodeRejectsUnboundedTranslationEntries() throws {
    let value: [String: Any] = [
      "generation": 7,
      "translations": [["text": "你好", "translation": String(repeating: "x", count: 4097)]],
    ]
    XCTAssertThrowsError(try CandidateGlossModel.decode(value))
  }

  func testDecodeRejectsNegativeGeneration() {
    let value: [String: Any] = [
      "generation": -1,
      "translations": [["text": "你好", "translation": "hello"]],
    ]
    XCTAssertThrowsError(try CandidateGlossModel.decode(value))
  }
}
