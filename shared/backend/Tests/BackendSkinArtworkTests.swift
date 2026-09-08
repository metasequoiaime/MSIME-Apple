import Foundation
import XCTest
@testable import MSIMEBackend

private final class ArtworkStorage: BackendSessionStorage, @unchecked Sendable {
  func load() throws -> BackendSavedSession? {
    .init(tokens: .init(access_token: String(repeating: "a", count: 64), refresh_token: String(repeating: "b", count: 64), token_type: "Bearer", expires_in: 900,
      user: .init(id: "artwork-test", display_name: "测试", created_at: "")), expiresAt: Date().addingTimeInterval(900))
  }
  func save(_ session: BackendSavedSession) throws {}
  func clear() throws {}
}
private final class ArtworkProtocol: URLProtocol {
  static let lock = NSLock()
  nonisolated(unsafe) static var failed = false
  nonisolated(unsafe) static var methods: [String] = []
  nonisolated(unsafe) static var polled: XCTestExpectation?
  static func reset(failed: Bool, polled: XCTestExpectation? = nil) {
    lock.lock(); defer { lock.unlock() }; Self.failed = failed; Self.polled = polled; methods = []
  }
  static func calls() -> [String] { lock.lock(); defer { lock.unlock() }; return methods }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.lock(); Self.methods.append(request.httpMethod!); let failed = Self.failed; let polled = Self.polled; Self.lock.unlock()
    let id = String(repeating: "a", count: 48)
    let state = request.httpMethod == "GET" && failed ? "failed" : "running"
    let data = Data("{\"id\":\"\(id)\",\"state\":\"\(state)\"}".utf8)
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: request.httpMethod == "POST" ? 202 : 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
    if request.httpMethod == "GET" { polled?.fulfill() }
  }
  override func stopLoading() {}
}
final class BackendSkinArtworkTests: XCTestCase {
  private func setup() -> (BackendAccountClient, BackendAccountSession) {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ArtworkProtocol.self]
    let api = BackendAccountClient(configuration: config)
    return (api, BackendAccountSession(api: api, storage: ArtworkStorage()))
  }
  func testFailedGenerationIsReleasedWithoutCreatingAnotherJob() async throws {
    ArtworkProtocol.reset(failed: true)
    let (api, account) = setup()
    do {
      _ = try await api.skinArtwork(prompt: "test", account: account, userID: "artwork-test")
      XCTFail("Failed job returned a skin")
    } catch let error as BackendAccountClient.Failure { XCTAssertEqual(error.status, 502) }
    XCTAssertEqual(ArtworkProtocol.calls(), ["POST", "GET", "DELETE"])
  }
  func testCancellationDeletesRunningJobEvenWhenParentTaskIsCancelled() async throws {
    let polled = expectation(description: "polled running job")
    ArtworkProtocol.reset(failed: false, polled: polled)
    let (api, account) = setup()
    let task = Task { try await api.skinArtwork(prompt: "test", account: account, userID: "artwork-test") }
    await fulfillment(of: [polled], timeout: 2)
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled job returned") } catch is CancellationError {}
    XCTAssertEqual(ArtworkProtocol.calls(), ["POST", "GET", "DELETE"])
  }
}
