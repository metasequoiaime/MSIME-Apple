import Foundation
import XCTest
@testable import MSIMEBackend

private final class DictionaryFileProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let chunk = Data(repeating: 65, count: 65536)
    let headers = request.url?.query == "truncated" ? ["Content-Type": "text/plain", "Content-Length": "3000000"] : ["Content-Type": "text/plain"]
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
    for _ in 0..<32 { client?.urlProtocol(self, didLoad: chunk) }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class BackendDictionaryFileTests: XCTestCase {
  private func client() -> BackendAccountClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DictionaryFileProtocol.self]
    return BackendAccountClient(configuration: config)
  }
  private func exports() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("msime-export-") })
  }
  func testExportStreamsPastOrdinaryJSONLimitIntoPrivateFile() async throws {
    let file = try await client().download("/v1/users/me/dictionaries/quick/export", token: "session", filename: "test.tsv", maximumBytes: 3 * 1024 * 1024)
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    XCTAssertEqual(attributes[.size] as? Int, 2 * 1024 * 1024)
    XCTAssertEqual((attributes[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
  }
  func testOversizedAndTruncatedDownloadsLeaveNoPartialExport() async throws {
    for (suffix, bound) in [("", 1_000_000), ("?truncated", 4_000_000)] {
      let before = try exports()
      do {
        _ = try await client().download("/v1/users/me/dictionaries/quick/export" + suffix, token: "session", filename: "test.tsv", maximumBytes: bound)
        XCTFail("invalid download accepted")
      } catch { }
      XCTAssertEqual(try exports(), before)
    }
  }
  func testImportChecksEscapedPayloadAndHanKindBeforeSending() async throws {
    for (kind, text, format) in [(BackendAccountClient.DictionaryKind.quick, "你好", BackendAccountClient.DictionaryFileFormat.hans), (.quick, String(repeating: "\t", count: 33000), .standard)] {
      do { _ = try await client().importDictionary(kind, text: text, format: format, token: "session"); XCTFail("invalid import sent") }
      catch let error as BackendAccountClient.Failure { XCTAssertEqual(error.status, 400) }
    }
  }
}
