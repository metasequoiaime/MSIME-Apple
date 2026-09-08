import AppKit
import Foundation

private final class MemoryCredentials: BackendSessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var saved: BackendSavedSession?
  func load() throws -> BackendSavedSession? { lock.lock(); defer { lock.unlock() }; return saved }
  func save(_ value: BackendSavedSession) throws { lock.lock(); defer { lock.unlock() }; saved = value }
  func clear() throws { lock.lock(); defer { lock.unlock() }; saved = nil }
}
private final class AccountFixture: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let body: String
    var status = 200
    switch (request.httpMethod!, request.url!.path) {
    case (_, "/v1/auth/providers"): body = #"{"providers":{"email":true,"phone":false,"apple":false}}"#
    case (_, "/v1/auth/challenges"): body = #"{"challenge_id":"synthetic","expires_in":300}"#
    case (_, "/v1/auth/login"):
      let token = String(repeating: "a", count: 64), refresh = String(repeating: "b", count: 64)
      body = "{\"access_token\":\"\(token)\",\"refresh_token\":\"\(refresh)\",\"token_type\":\"Bearer\",\"expires_in\":900,\"user\":{\"id\":\"synthetic-user\",\"display_name\":\"测试\",\"created_at\":\"2026-09-08\"}}"
    case ("PATCH", "/v1/users/me"), (_, "/v1/auth/logout"): body = ""; status = 204
    case ("GET", "/v1/users/me"): body = #"{"user":{"id":"synthetic-user","display_name":"新昵称","created_at":"2026-09-08"},"identities":[]}"#
    case ("DELETE", "/v1/users/me"): body = #"{"error":{"code":"recent_login_required"}}"#; status = 403
    default: body = "{}"; status = 404
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
@main struct AccountTests {
  struct Failure: Error {}
  @MainActor static func require(_ value: Bool) throws { if !value { throw Failure() } }
  @MainActor static func finished(_ model: MacAccountModel) async throws {
    let deadline = Date().addingTimeInterval(5)
    while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
    try require(!model.busy)
  }
  @MainActor static func main() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AccountFixture.self]
    let client = BackendAccountClient(configuration: configuration)
    let storage = MemoryCredentials()
    let session = BackendAccountSession(api: client, storage: storage)
    let model = MacAccountModel(client: client, account: session)
    model.load(); try await finished(model)
    try require(model.providers["email"] == true && model.user == nil)
    model.channel = "phone"; model.target = "+10000000000"
    model.requestCode(); try await finished(model)
    try require(model.challenge == nil && model.message != nil)
    model.channel = "email"; model.target = "synthetic@example.invalid"
    model.requestCode(); try await finished(model)
    try require(model.challenge != nil && model.resendAt > Date())
    model.code = "123456"; model.codeLogin(); try await finished(model)
    try require(model.user?.id == "synthetic-user" && model.code.isEmpty && model.target.isEmpty)
    model.name = "新昵称"; model.rename(); try await finished(model)
    try require(model.user?.display_name == "新昵称" && storage.load()?.tokens.user.display_name == "新昵称")
    model.logout(delete: true); try await finished(model)
    try require(model.user != nil && model.message != nil && storage.load() != nil)
    model.logout(all: true); try await finished(model)
    try require(model.user == nil && storage.load() == nil)
    model.code = "123456"; model.target = "synthetic@example.invalid"; model.close()
    try require(model.code.isEmpty && model.target.isEmpty && model.challenge == nil)
    print("PASS: native account model login, disabled provider, rename, failed deletion, logout and credential cleanup")
  }
}
