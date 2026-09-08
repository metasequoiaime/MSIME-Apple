import Foundation
import XCTest
@testable import MSIMEBackend

private final class AccountProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url!.path
    let authenticated = request.value(forHTTPHeaderField: "Authorization") == "Bearer session"
    var status = 200
    var body = "{}"
    switch (request.httpMethod!, path) {
    case ("GET", "/v1/auth/providers"):
      body = #"{"providers":{"apple":true,"email":false}}"#
    case ("POST", "/v1/auth/challenges"):
      body = #"{"challenge_id":"challenge","expires_in":300,"nonce":"server-nonce"}"#
    case ("PATCH", "/v1/users/me"), ("POST", "/v1/auth/logout"), ("DELETE", "/v1/users/me"):
      status = authenticated ? 204 : 401; body = ""
    case ("GET", "/v1/users/me/clipboard"):
      let search = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
      let object: [String: Any] = ["enabled": true, "items": [["id": String(repeating: "a", count: 64), "text": search, "updated_at": "2026-09-08"]]]
      body = String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
      if !authenticated { status = 401 }
    case ("PUT", "/v1/users/me/clipboard/settings"), ("DELETE", "/v1/users/me/clipboard"):
      status = authenticated ? 204 : 401; body = ""
    case ("POST", "/v1/auth/login"):
      // A compromised/misconfigured endpoint must not persist malformed tokens.
      body = #"{"access_token":"invalid","refresh_token":"invalid","token_type":"Bearer","expires_in":900,"user":{"id":"synthetic","display_name":"","created_at":"2026-09-08"}}"#
    default:
      status = 401; body = "private credential and input must not be shown"
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if !body.isEmpty { client?.urlProtocol(self, didLoad: Data(body.utf8)) }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class BackendAccountClientTests: XCTestCase {
  private func client() -> BackendAccountClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AccountProtocol.self]
    return BackendAccountClient(configuration: config)
  }
  func testProvidersAndServerNonce() async throws {
    let client = client()
    let providers = try await client.providers()
    XCTAssertEqual(providers["apple"], true)
    XCTAssertEqual(providers["email"], false)
    let challenge = try await client.challenge(provider: "apple")
    XCTAssertEqual(challenge.nonce, "server-nonce")
  }
  func testAuthenticatedNoContentOperations() async throws {
    let client = client()
    try await client.rename("测试账号", token: "session")
    try await client.logout(token: "session")
    try await client.deleteAccount(token: "session")
  }
  func testFailuresDoNotExposeServerText() async throws {
    do { _ = try await client().profile(token: "wrong"); XCTFail("must reject") }
    catch let error as BackendAccountClient.Failure {
      XCTAssertEqual(error.status, 401)
      XCTAssertFalse(error.localizedDescription.contains("private"))
    }
  }
  func testMalformedTokensAreRejected() async throws {
    do { _ = try await client().login(challenge: "challenge", credential: "synthetic"); XCTFail("must reject") }
    catch let error as BackendAccountClient.Failure { XCTAssertEqual(error.status, 0) }
  }
  func testClipboardSearchIsEncodedAsOneQueryValue() async throws {
    let search = "学习 & q=other + % #"
    let page = try await client().clipboard(token: "session", search: search)
    XCTAssertTrue(page.enabled)
    XCTAssertEqual(page.items.first?.text, search)
    try await client().setClipboardEnabled(false, token: "session")
    try await client().deleteClipboard(token: "session")
  }
  func testClipboardRejectsOversizedUTF16AndUnsafeID() async throws {
    do { _ = try await client().addClipboard(String(repeating: "😀", count: 2001), token: "session"); XCTFail("too long") }
    catch let error as BackendAccountClient.Failure { XCTAssertEqual(error.status, 400) }
    do { try await client().deleteClipboard(id: "../auth/logout", token: "session"); XCTFail("unsafe id") }
    catch let error as BackendAccountClient.Failure { XCTAssertEqual(error.status, 400) }
  }
  func testCredentialsCannotGoToAnotherOrigin() async throws {
    for path in ["https://other.invalid/v1/users/me", "//other.invalid/v1/users/me", "/v1/\\other.invalid", "/v1/users/me#fragment"] {
      do { _ = try await client().request("GET", path, token: "session"); XCTFail(path) }
      catch let error as BackendAccountClient.Failure { XCTAssertEqual(error.status, 0) }
    }
  }
}
