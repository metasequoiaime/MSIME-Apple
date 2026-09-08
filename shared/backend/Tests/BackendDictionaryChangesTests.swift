import Foundation
import XCTest
@testable import MSIMEBackend

private final class ChangesProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "after" }?.value
    let body: String
    switch cursor {
    case "0":
      body = #"{"changes":[{"revision":2,"previous":null,"replacement":null,"ranking":[{"id":"","kind":"pinyin","code":"ni","word":"你","weight":8,"revision":2,"user_inserted":false}],"selection":{"context":"pinyin","code":"ni","word":"你","count":0}},{"revision":3,"position":{"context":"pinyin","code":"ni","word":"你","position":0}},{"revision":4,"reset":true}],"next":4,"has_more":true}"#
    case "4": body = #"{"changes":[],"next":4,"has_more":false}"#
    case "5": body = #"{"changes":[{"revision":5}],"next":5,"has_more":false}"#
    case "6": body = #"{"changes":[],"next":7,"has_more":false}"#
    default: body = #"{"changes":[],"next":7,"has_more":true}"#
    }
    let status = request.url?.path == "/v1/users/me/dictionary/changes" && request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic" ? 200 : 400
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class BackendDictionaryChangesTests: XCTestCase {
  private func client() -> BackendAccountClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ChangesProtocol.self]
    return BackendAccountClient(configuration: config)
  }
  func testPreservesRankingOwnershipCounterClearPositionRemovalAndReset() async throws {
    let page = try await client().dictionaryChanges(after: 0, token: "synthetic")
    XCTAssertEqual(page.changes.count, 3)
    XCTAssertEqual(page.changes[0].ranking?.first?.user_inserted, false)
    XCTAssertEqual(page.changes[0].selection?.count, 0)
    XCTAssertEqual(page.changes[1].position?.position, 0)
    XCTAssertEqual(page.changes[2].reset, true)
    XCTAssertTrue(page.has_more)
    let end = try await client().dictionaryChanges(after: page.next, token: "synthetic")
    XCTAssertTrue(end.changes.isEmpty)
    XCTAssertEqual(end.next, 4)
    XCTAssertFalse(end.has_more)
  }
  func testRejectsNonAdvancingAndInconsistentCursors() async throws {
    for cursor: Int64 in [5, 6, 7] {
      do {
        _ = try await client().dictionaryChanges(after: cursor, token: "synthetic")
        XCTFail("Invalid change cursor accepted")
      } catch let failure as BackendAccountClient.Failure { XCTAssertEqual(failure.status, 502) }
    }
  }
  func testRejectsInvalidRequestBounds() async throws {
    for (cursor, limit): (Int64, Int) in [(-1, 100), (0, 0), (0, 101)] {
      do {
        _ = try await client().dictionaryChanges(after: cursor, limit: limit, token: "synthetic")
        XCTFail("Invalid request accepted")
      } catch let failure as BackendAccountClient.Failure { XCTAssertEqual(failure.status, 400) }
    }
  }
}
