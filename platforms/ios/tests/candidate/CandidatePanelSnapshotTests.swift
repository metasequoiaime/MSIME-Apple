import XCTest

final class CandidatePanelSnapshotTests: XCTestCase {
  func testDecodePreservesCompleteCandidateIdentityAndAnnotations() throws {
    let snapshot = try CandidatePanelSnapshot.decode([
      "generation": 7,
      "preedit": "wq",
      "candidates": [
        ["id": ["generation": 7, "index": 0], "text": "你", "code": "wq"],
        [
          "id": ["generation": 7, "index": 1], "text": "爷", "code": "wqb",
          "translation": "grandfather",
        ],
      ],
    ])
    XCTAssertEqual(snapshot.generation, 7)
    XCTAssertEqual(snapshot.preedit, "wq")
    XCTAssertEqual(snapshot.entries.map(\.index), [0, 1])
    XCTAssertEqual(snapshot.entries.map(\.code), ["wq", "wqb"])
    XCTAssertEqual(snapshot.entries.map(\.translation), ["", "grandfather"])
  }

  func testDecodeRejectsStaleOrDuplicateCandidateIdentity() {
    XCTAssertThrowsError(try CandidatePanelSnapshot.decode([
      "generation": 7,
      "preedit": "yi",
      "candidates": [
        ["id": ["generation": 6, "index": 0], "text": "一"],
      ],
    ]))
    XCTAssertThrowsError(try CandidatePanelSnapshot.decode([
      "generation": 7,
      "preedit": "yi",
      "candidates": [
        ["id": ["generation": 7, "index": 0], "text": "一"],
        ["id": ["generation": 7, "index": 0], "text": "乙"],
      ],
    ]))
  }
}
