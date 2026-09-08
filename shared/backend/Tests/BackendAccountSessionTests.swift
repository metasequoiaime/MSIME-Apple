import Foundation
import XCTest
@testable import MSIMEBackend

private final class MemorySessions: BackendSessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var value: BackendSavedSession?
  init(_ value: BackendSavedSession?) { self.value = value }
  func load() throws -> BackendSavedSession? { lock.lock(); defer { lock.unlock() }; return value }
  func save(_ session: BackendSavedSession) throws { lock.lock(); defer { lock.unlock() }; value = session }
  func clear() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}
private actor RefreshAPI: BackendSessionAPI {
  var refreshCount = 0
  private var continuation: CheckedContinuation<BackendAccountClient.Tokens, Error>?
  private var started: CheckedContinuation<Void, Never>?
  static func tokens(_ character: String = "a") -> BackendAccountClient.Tokens {
    .init(access_token: String(repeating: character, count: 64), refresh_token: String(repeating: "f", count: 64),
          token_type: "Bearer", expires_in: 900,
          user: .init(id: "synthetic-user", display_name: "测试", created_at: "2026-09-08"))
  }
  func login(challenge: String, credential: String, linkToken: String?) async throws -> BackendAccountClient.Tokens { Self.tokens() }
  func logout(token: String, all: Bool) async throws { }
  func refresh(_ token: String) async throws -> BackendAccountClient.Tokens {
    refreshCount += 1
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation; started?.resume(); started = nil
    }
  }
  func waitUntilRefreshing() async {
    if continuation != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish() { continuation?.resume(returning: Self.tokens("b")); continuation = nil }
}
final class BackendAccountSessionTests: XCTestCase {
  func testConcurrentCallersShareOneRefreshAndPersistRotation() async throws {
    let storage = MemorySessions(.init(tokens: RefreshAPI.tokens(), expiresAt: .distantPast))
    let api = RefreshAPI()
    let session = BackendAccountSession(api: api, storage: storage)
    let first = Task { try await session.accessToken() }
    await api.waitUntilRefreshing()
    let second = Task { try await session.accessToken() }
    try await Task.sleep(nanoseconds: 20_000_000)
    await api.finish()
    let a = try await first.value, b = try await second.value
    XCTAssertEqual(a, b)
    let count = await api.refreshCount
    XCTAssertEqual(count, 1)
    XCTAssertEqual(try storage.load()?.tokens.access_token, a)
  }
  func testProfileCacheUpdatePreservesSessionAndRejectsLateResult() async throws {
    let original = BackendSavedSession(tokens: RefreshAPI.tokens(), expiresAt: Date().addingTimeInterval(600))
    let storage = MemorySessions(original)
    let session = BackendAccountSession(api: RefreshAPI(), storage: storage)
    let renamed = BackendAccountClient.User(id: "synthetic-user", display_name: "新昵称", created_at: "2026-09-08")
    try await session.updateUser(renamed, matching: original.tokens.access_token)
    XCTAssertEqual(try storage.load()?.tokens.user, renamed)
    XCTAssertEqual(try storage.load()?.expiresAt, original.expiresAt)
    try await session.forget()
    do { try await session.updateUser(renamed, matching: original.tokens.access_token); XCTFail("late profile resurrected logout") }
    catch is CancellationError { }
    XCTAssertNil(try storage.load())
  }
  func testRetryForDifferentAccountNeverRefreshesOrReturnsCurrentToken() async throws {
    let storage = MemorySessions(.init(tokens: RefreshAPI.tokens(), expiresAt: .distantPast))
    let api = RefreshAPI()
    let session = BackendAccountSession(api: api, storage: storage)
    do {
      _ = try await session.credentials(retrying: "old-account-token", matchingUserID: "previous-account")
      XCTFail("must not retry an old account request as the current account")
    } catch is CancellationError { }
    let count = await api.refreshCount
    XCTAssertEqual(count, 0)
  }
  func testBoundCredentialsRejectLogoutDuringRefresh() async throws {
    let storage = MemorySessions(.init(tokens: RefreshAPI.tokens(), expiresAt: .distantPast))
    let api = RefreshAPI()
    let session = BackendAccountSession(api: api, storage: storage)
    let pending = Task { try await session.credentials(matchingUserID: "synthetic-user") }
    await api.waitUntilRefreshing()
    try await session.forget()
    await api.finish()
    do { _ = try await pending.value; XCTFail("late credentials returned") }
    catch is CancellationError { }
  }
  func testLogoutGenerationRejectsLateRefresh() async throws {
    let storage = MemorySessions(.init(tokens: RefreshAPI.tokens(), expiresAt: .distantPast))
    let api = RefreshAPI()
    let session = BackendAccountSession(api: api, storage: storage)
    let pending = Task { try await session.accessToken() }
    await api.waitUntilRefreshing()
    try await session.forget()
    // Deliberately ignore task cancellation in the fake transport, as an already
    // delivered network response can race cancellation in a real application.
    await api.finish()
    do { _ = try await pending.value; XCTFail("must reject stale completion") }
    catch is CancellationError { }
    let user = try await session.user()
    XCTAssertNil(user)
    XCTAssertNil(try storage.load())
  }
}
