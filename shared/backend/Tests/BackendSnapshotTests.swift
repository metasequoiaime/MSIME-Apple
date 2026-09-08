import Foundation
import CryptoKit
import XCTest
@testable import MSIMEBackend

final class BackendSnapshotTests: XCTestCase {
  private let header = #"{"type":"header","format":"msime-dictionary-snapshot","version":1,"revision":10000}"#
  private func framed(_ lines: [String]) throws -> Data {
    let body = Data((lines.joined(separator: "\n") + "\n").utf8)
    let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    let footer = try JSONSerialization.data(withJSONObject: ["type": "footer", "records": lines.count, "sha256": digest], options: [.sortedKeys])
    return body + footer + Data([10])
  }
  private func inspect(_ data: Data) throws -> BackendSnapshotEnvelope {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    try data.write(to: path)
    return try BackendSnapshotEnvelope.inspect(path)
  }
  func testHeaderOnlyAndMultiChunkUTF8SnapshotFraming() throws {
    let empty = try inspect(framed([header]))
    XCTAssertEqual(empty.records, 1)
    let lines: [String] = (0..<10000).map { index in
      """
      {"type":"entry","data":{"id":"\(index)","kind":"quick","code":"file\(index)","word":"合成备份样例","weight":100,"revision":1,"updated_at":"2026-09-08T00:00:00Z"}}
      """
    }
    let result = try inspect(framed([header] + lines))
    XCTAssertEqual(result.entries, 10000)
    XCTAssertEqual(result.records, 10001)
    XCTAssertEqual(result.revision, 10000)
  }
  func testTruncationTamperingTrailingDataAndCategoryRegressionAreRejected() throws {
    let valid = try framed([header])
    XCTAssertThrowsError(try inspect(Data(valid.dropLast(30))))
    var tampered = valid
    tampered[tampered.startIndex + 2] = 120
    XCTAssertThrowsError(try inspect(tampered))
    XCTAssertThrowsError(try inspect(valid + Data("{}\n".utf8)))
    XCTAssertThrowsError(try inspect(framed([header, #"{"type":"selection","data":{}}"#, #"{"type":"entry","data":{}}"#])))
    XCTAssertThrowsError(try inspect(framed([header.replacingOccurrences(of: "\"version\":1", with: "\"version\":true")])))
  }
  func testOversizedSingleLineIsRejected() throws {
    XCTAssertThrowsError(try inspect(Data(String(repeating: " ", count: 65536).utf8)))
  }
  func testDuplicateEscapedKeysAndNonIntegerNumbersAreRejected() throws {
    let malformed = [
      header.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"version\":1"),
      header.replacingOccurrences(of: "\"version\":1", with: #""version":1,"vers\u0069on":1"#),
      header.replacingOccurrences(of: "\"version\":1", with: "\"version\":1.0"),
      header.replacingOccurrences(of: "\"version\":1", with: "\"version\":1e0")
    ]
    for line in malformed { XCTAssertThrowsError(try inspect(framed([line])), line) }
  }
  func testRecordFieldsRejectInvalidDataEvenWithCorrectChecksum() throws {
    let entry = #"{"type":"entry","data":{"id":"synthetic","kind":"quick","code":"sample","word":"样例","weight":10,"revision":1,"updated_at":"2026-09-08T00:00:00Z"}}"#
    XCTAssertEqual(try inspect(framed([header, entry])).entries, 1)
    let invalid = [
      entry.replacingOccurrences(of: "\"weight\":10", with: "\"weight\":0"),
      entry.replacingOccurrences(of: "\"weight\":10", with: "\"weight\":true"),
      entry.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":10001"),
      entry.replacingOccurrences(of: "\"kind\":\"quick\"", with: "\"kind\":\"other\""),
      entry.replacingOccurrences(of: "\"id\":\"synthetic\"", with: "\"id\":null"),
      entry.replacingOccurrences(of: "\"weight\":10", with: "\"weight\":10,\"user_inserted\":false"),
      entry.replacingOccurrences(of: "\"weight\":10", with: "\"weight\":10,\"unexpected\":1"),
      entry.replacingOccurrences(of: "2026-09-08T00:00:00Z", with: "invalid"),
      entry.replacingOccurrences(of: "2026-09-08T00:00:00Z", with: "2026-02-30T00:00:00Z"),
      entry.replacingOccurrences(of: "2026-09-08T00:00:00Z", with: "2026-09-08T00:00:00Zjunk"),
      entry.replacingOccurrences(of: "\"weight\":10", with: #""weight":10,"we\u0069ght":10"#),
      #"{"type":"position","data":{"context":"pinyin:sample","code":"sample","word":"样例","position":6}}"#,
      #"{"type":"selection","data":{"context":"pinyin:sample","code":"sample","word":"样例","count":11}}"#
    ]
    for line in invalid { XCTAssertThrowsError(try inspect(framed([header, line])), line) }
    let tombstone = entry.replacingOccurrences(of: "\"type\":\"entry\"", with: "\"type\":\"overlay\",\"deleted\":true")
      .replacingOccurrences(of: "\"weight\":10", with: "\"weight\":0")
    XCTAssertEqual(try inspect(framed([header, tombstone])).overlays, 1)
  }

}
