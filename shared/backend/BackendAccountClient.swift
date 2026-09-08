import Foundation

/// Shared account transport. Platform UI owns consent and Keychain persistence.
struct BackendAccountClient: Sendable {
  struct User: Codable, Equatable, Sendable {
    let id: String
    let display_name: String
    let created_at: String
  }
  struct Tokens: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let token_type: String
    let expires_in: Int
    let user: User
  }
  struct Challenge: Decodable, Sendable {
    let challenge_id: String
    let expires_in: Int
    let nonce: String?
    let authorization_url: String?
  }
  struct Profile: Decodable, Sendable {
    struct Identity: Decodable, Sendable { let provider: String; let subject: String }
    let user: User
    let identities: [Identity]
  }
  struct Failure: Error, LocalizedError, Sendable {
    let status: Int
    var errorDescription: String? {
      switch status {
      case 401: return "登录已失效，请重新登录。"
      case 403: return "此操作需要重新登录或开启相应权限。"
      case 409: return "内容已在其他设备更新，请刷新后重试。"
      case 429: return "操作过于频繁，请稍后再试。"
      case 503: return "此服务暂不可用，请稍后再试。"
      default: return "请求未完成，请稍后重试。"
      }
    }
  }
  private final class Redirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
      completionHandler(nil)
    }
  }
  private let session: URLSession
  private let origin = URL(string: "https://api.msime.app")!

  init(configuration: URLSessionConfiguration = .ephemeral) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration, delegate: Redirects(), delegateQueue: nil)
  }

  func providers() async throws -> [String: Bool] {
    struct Response: Decodable { let providers: [String: Bool] }
    let response: Response = try await json("GET", "/v1/auth/providers")
    return response.providers
  }
  func challenge(provider: String, target: String = "", linkToken: String? = nil) async throws -> Challenge {
    struct Body: Encodable { let provider: String; let target: String; let purpose: String }
    return try await json("POST", "/v1/auth/challenges", token: linkToken,
                          body: JSONEncoder().encode(Body(provider: provider, target: target,
                                                        purpose: linkToken == nil ? "login" : "link")))
  }
  func login(challenge: String, credential: String, linkToken: String? = nil) async throws -> Tokens {
    struct Body: Encodable { let challenge_id: String; let credential: String }
    let tokens: Tokens = try await json("POST", "/v1/auth/login", token: linkToken,
      body: JSONEncoder().encode(Body(challenge_id: challenge, credential: credential)))
    return try validated(tokens)
  }
  func refresh(_ token: String) async throws -> Tokens {
    struct Body: Encodable { let refresh_token: String }
    let tokens: Tokens = try await json("POST", "/v1/auth/refresh",
      body: JSONEncoder().encode(Body(refresh_token: token)))
    return try validated(tokens)
  }
  func profile(token: String) async throws -> Profile {
    try await json("GET", "/v1/users/me", token: token)
  }
  func rename(_ name: String, token: String) async throws {
    struct Body: Encodable { let display_name: String }
    _ = try await request("PATCH", "/v1/users/me", token: token,
                         body: JSONEncoder().encode(Body(display_name: name)))
  }
  func logout(token: String, all: Bool = false) async throws {
    struct Body: Encodable { let all: Bool }
    _ = try await request("POST", "/v1/auth/logout", token: token,
                          body: JSONEncoder().encode(Body(all: all)))
  }
  func deleteAccount(token: String) async throws {
    _ = try await request("DELETE", "/v1/users/me", token: token)
  }

  // Used by the explicit user-data screens as well as account operations. No redirects,
  // cookies, cached private data, arbitrary origins, or server error text are exposed.
  func request(_ method: String, _ path: String, token: String? = nil,
               body: Data? = nil) async throws -> Data {
    guard path.hasPrefix("/v1/"), !path.contains("\\"),
          let url = URL(string: path, relativeTo: origin)?.absoluteURL,
          url.scheme == "https", url.host == origin.host, url.port == nil,
          url.user == nil, url.password == nil, url.fragment == nil,
          body == nil || body!.count <= 1024 * 1024,
          token == nil || (!token!.isEmpty && !token!.contains(where: { $0.isWhitespace || $0.isNewline }))
    else { throw Failure(status: 0) }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.httpBody = body
    request.setValue("MSIME/Apple", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse else { throw Failure(status: 0) }
    guard (200..<300).contains(response.statusCode) else { throw Failure(status: response.statusCode) }
    guard response.expectedContentLength <= 1024 * 1024 else { throw Failure(status: 0) }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 1024 * 1024 else { throw Failure(status: 0) }
      data.append(byte)
    }
    try Task.checkCancellation()
    return data
  }
  func json<T: Decodable>(_ method: String, _ path: String, token: String? = nil,
                                  body: Data? = nil) async throws -> T {
    let data = try await request(method, path, token: token, body: body)
    do { return try JSONDecoder().decode(T.self, from: data) }
    catch { throw Failure(status: 0) }
  }
  private func validated(_ tokens: Tokens) throws -> Tokens {
    let hex = CharacterSet(charactersIn: "0123456789abcdef")
    guard tokens.token_type == "Bearer", tokens.expires_in > 0,
          !tokens.user.id.isEmpty,
          [tokens.access_token, tokens.refresh_token].allSatisfy({ token in
            token.utf8.count == 64 && token.unicodeScalars.allSatisfy(hex.contains)
          }) else { throw Failure(status: 0) }
    return tokens
  }
}
