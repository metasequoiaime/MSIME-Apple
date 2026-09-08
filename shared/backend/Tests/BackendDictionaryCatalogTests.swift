import Foundation
import XCTest
@testable import MSIMEBackend

private final class DictionaryCatalogProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var status = 200
    var data = Data(#"{"entries":[{"kind":"pinyin","code":"ni'hao","word":"你好","weight":100000}],"offset":0,"has_more":false,"revision":42,"normalized":"ni'hao"}"#.utf8)
    if request.httpMethod == "POST" {
      var body = request.httpBody ?? Data()
      if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }
          body.append(contentsOf: buffer.prefix(count))
        }
      }
      let value = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
      if !(value?["replacement"] is NSNull) || value?["revision"] as? Int != 42 { status = 400 }
      data = Data(#"{"revision":43,"previous":null,"replacement":null}"#.utf8)
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class BackendDictionaryCatalogTests: XCTestCase {
  func testBaseCatalogHasNoPersonalIDAndDeletionRequiresExplicitNull() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DictionaryCatalogProtocol.self]
    let client = BackendAccountClient(configuration: config)
    let catalog = try await client.dictionaryCatalog(.pinyin, code: "nihc", scheme: "shuangpin", token: "session")
    XCTAssertEqual(catalog.revision, 42)
    XCTAssertEqual(catalog.normalized, "ni'hao")
    let entry = try XCTUnwrap(catalog.entries.first)
    XCTAssertEqual(entry.word, "你好")
    let deleted = try await client.editCatalog(entry, revision: catalog.revision, replacement: nil, token: "session")
    XCTAssertEqual(deleted.revision, 43)
  }
}
