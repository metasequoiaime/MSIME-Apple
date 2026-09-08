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
}
