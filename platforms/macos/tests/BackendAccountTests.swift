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
  private static var clipboardEnabled = false
  private static var clipboardText: String?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let body: String
    var status = 200
    var payload = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; payload.append(contentsOf: buffer.prefix(count)) }
    }
    let values = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    let itemID = String(repeating: "c", count: 64)
    func item(_ text: String) -> [String: String] { ["id": itemID, "text": text, "updated_at": "2026-09-08"] }
    func json(_ object: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)! }
    switch (request.httpMethod!, request.url!.path) {
    case ("PUT", "/v1/users/me/clipboard/settings"):
      Self.clipboardEnabled = values?["enabled"] as? Bool ?? false
      if !Self.clipboardEnabled { Self.clipboardText = nil }
      body = ""; status = 204
    case ("GET", "/v1/users/me/clipboard"):
      body = json(["enabled": Self.clipboardEnabled, "items": Self.clipboardText.map { [item($0)] } ?? []])
    case ("POST", "/v1/users/me/clipboard"):
      Self.clipboardText = values?["text"] as? String
      body = json(item(Self.clipboardText ?? ""))
    case ("DELETE", "/v1/users/me/clipboard"), ("DELETE", "/v1/users/me/clipboard/" + itemID):
      Self.clipboardText = nil; body = ""; status = 204
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
  @MainActor static func finished(_ model: MacClipboardModel) async throws {
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
    let clipboard = MacClipboardModel(accountID: "synthetic-user", client: client, account: session)
    clipboard.refresh(); try await finished(clipboard)
    try require(clipboard.loaded && !clipboard.enabled && clipboard.items.isEmpty)
    clipboard.setEnabled(true); try await finished(clipboard)
    clipboard.text = "合成剪贴板内容"; clipboard.upload(); try await finished(clipboard)
    try require(clipboard.items.first?.text == "合成剪贴板内容" && clipboard.text.isEmpty)
    clipboard.delete(id: clipboard.items.first!.id); try await finished(clipboard)
    try require(clipboard.items.isEmpty)
    clipboard.text = "合成清理内容"; clipboard.upload(); try await finished(clipboard)
    clipboard.setEnabled(false); try await finished(clipboard)
    try require(!clipboard.enabled && clipboard.items.isEmpty)
    let wrongAccount = MacClipboardModel(accountID: "previous-account", client: client, account: session)
    wrongAccount.refresh(); try await finished(wrongAccount)
    try require(!wrongAccount.loaded && wrongAccount.items.isEmpty)
    clipboard.text = "未上传的草稿"; clipboard.close()
    try require(clipboard.text.isEmpty && clipboard.items.isEmpty)
    model.logout(all: true); try await finished(model)
    try require(model.user == nil && storage.load() == nil)
    model.code = "123456"; model.target = "synthetic@example.invalid"; model.close()
    try require(model.code.isEmpty && model.target.isEmpty && model.challenge == nil)
    print("PASS: native account model login, disabled provider, rename, failed deletion, logout and credential cleanup")
  }
}
