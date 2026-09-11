import Foundation
import XCTest
@testable import MSIMEBackend

private final class CandidateProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var body = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var bytes = [UInt8](repeating: 0, count: 4096)
      while true { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; body.append(contentsOf: bytes.prefix(n)) }
    }
    let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    var status = 200
    let data: Data
    if request.url?.path.hasSuffix("ranking") == true {
      let action = object?["action"] as? [String: Any]
      if action?["code"] as? String != "ni'hao" || object?["revision"] as? Int != 42 { status = 400 }
      data = Data(#"{"revision":43,"changed":true,"selection":{"count":0}}"#.utf8)
    } else {
      if object?.keys.contains("position") != false || object?["context"] as? String != "server:context" || request.httpMethod != "DELETE" { status = 400 }
      data = Data(#"{"revision":43}"#.utf8)
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class BackendCandidateClientTests: XCTestCase {
  private func client() -> BackendAccountClient {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CandidateProtocol.self]
    return BackendAccountClient(configuration: config)
  }
  func testRankingUsesCanonicalPinyinInsteadOfDisplayCode() async throws {
    let candidate = BackendAccountClient.PersonalCandidate(code: "nihc", word: "你好", weight: 10, canonical_pinyin: "ni'hao")
    let query = BackendAccountClient.CandidateQuery(text: "nihc", kind: "pinyin", scheme: "shuangpin", profile: "xiaohe", limit: 100)
    let result = try await client().rankCandidate(candidate, query: query, revision: 42, mode: .pin, token: "session")
    XCTAssertTrue(result.changed)
    XCTAssertEqual(result.revision, 43)
  }
  func testUnfixPreservesServerContextAndOmitsPositionField() async throws {
    let result = try await client().setFixedPosition(context: "server:context", code: "ni'hao", word: "你好", position: nil, revision: 42, token: "session")
    XCTAssertEqual(result.revision, 43)
  }
}
