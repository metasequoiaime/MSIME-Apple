import Foundation
import Security

// 装完即有账号。Every other provider needs something the user already holds — an Apple or Google
// account, WeChat, a mailbox, a phone — so a fresh install has no identity, and candidate translation
// and cloud sync stay out of reach until someone goes looking for the sign-in and completes it.
//
// 凭据只在本机。The server keeps nothing but an HMAC of the secret, so clearing the keychain or moving
// to another machine loses the account and the dictionary synced into it. That is what this kind of
// account is rather than a defect, and the caller is expected to say so where the user can see it.
enum BackendAnonymousAccount {
  private static let service = "app.msime.backend.anonymous"
  private static let account = "https://api.msime.app"

  struct Credentials: Codable, Sendable {
    let subject: String
    let secret: String
  }

  // 后端把 subject 的字符集收紧到 [a-z0-9-],长度 8…64;这里生成的形状要落在里面。
  private static func generated() -> Credentials {
    func random(_ count: Int, from alphabet: String) -> String {
      let characters = Array(alphabet)
      var bytes = [UInt8](repeating: 0, count: count)
      // 账号名和口令都不能用可预测的随机源:口令就是这个账号唯一的凭据。
      _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
      return String(bytes.map { characters[Int($0) % characters.count] })
    }
    return Credentials(subject: "msime-" + random(16, from: "abcdefghijklmnopqrstuvwxyz0123456789"),
                       secret: random(48, from: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
  }

  private static let fileName = "anonymous-account.json"

  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  static func stored() -> Credentials? {
    if let data = BackendLocalStore.read(fileName),
       let credentials = try? JSONDecoder().decode(Credentials.self, from: data)
    {
      return credentials
    }
    // 早先的版本把它放在钥匙串里。读到就搬到文件并把钥匙串条目删掉,这样重装再也不会弹授权框。
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data,
          let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else { return nil }
    if BackendLocalStore.write(data, to: fileName) {
      SecItemDelete(query as CFDictionary)
    }
    return credentials
  }

  @discardableResult
  static func save(_ credentials: Credentials) -> Bool {
    guard let data = try? JSONEncoder().encode(credentials) else { return false }
    return BackendLocalStore.write(data, to: fileName)
  }

  /// 绑定到真实身份或注销之后,这份自动生成的凭据就没有用了。留着的后果是下次启动仍然把它当成一个
  /// 可用账号 —— 于是同一个人有两条并行的登录状态。
  static func discard() {
    try? BackendLocalStore(fileName: fileName).clear()
    try? sessionStorage().clear()
  }

  /// 匿名账号换来的会话也留在本机文件里。把自动生成的凭据锁进钥匙串、却让它换来的 token 也去问一次
  /// 登录密码,是把保护级别加在了错误的东西上 —— 真正关于用户的个人词库就在同一个目录,是普通文件。
  static func sessionStorage() -> any BackendSessionStorage {
    BackendLocalStore(fileName: "anonymous-session.json")
  }

  /// 已有凭据就用它登录,没有就先生成再登录。成功返回本次使用的凭据。
  ///
  /// 生成的凭据在**登录成功之后**才落钥匙串:先存会在服务端拒绝(限流、功能关闭)时留下一把永远登不上
  /// 的凭据,而下次启动会拿着它反复重试,再也不会换一对。
  static func ensureSignedIn(session: BackendAccountSession,
                             client: BackendAccountClient) async throws -> Credentials {
    if let existing = stored() {
      try await signIn(existing, session: session, client: client)
      return existing
    }
    let fresh = generated()
    try await signIn(fresh, session: session, client: client)
    save(fresh)
    return fresh
  }

  private static func signIn(_ credentials: Credentials,
                             session: BackendAccountSession,
                             client: BackendAccountClient) async throws {
    let challenge = try await client.challenge(provider: "anonymous", target: credentials.subject)
    try await session.signIn(challenge: challenge.challenge_id, credential: credentials.secret)
  }
}
