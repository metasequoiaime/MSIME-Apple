import Foundation

// 自动生成的凭据不进钥匙串。匿名账号的 subject/secret 和它换来的会话 token 都是本机自动生成、用户
// 全程不知情的东西 —— 更接近设备标识而不是用户密钥。把它们锁进登录钥匙串,保护级别就和敏感度反了:
// 真正关于用户的东西(个人词库 msime_user.db、打字统计)就在同一个目录里,是普通文件。
//
// 而且输入法看得见每一个按键,任何「向你要登录钥匙串密码」的时刻都值得省掉 —— 用户没做任何操作就
// 被问密码,和一个恶意输入法的样子分不开。用户主动挂上去的身份(Apple 登录)仍然走钥匙串:那时候他
// 自己点了登录,弹窗是看得懂的。
//
// 代价说清楚:以该用户身份运行的任何进程都能读到这个文件,从而冒用这个匿名账号。它能拿到的只有服务端
// 的 AI 额度 —— 同步的词库就是旁边那个文件,那个进程本来就读得到。
struct BackendLocalStore: BackendSessionStorage {
  private let fileName: String

  init(fileName: String = "backend-session.json") {
    self.fileName = fileName
  }

  // 和引擎的用户数据同一个目录,所以清空数据目录就把账号一起清掉了,不会留下一个孤儿凭据。
  private static var directory: URL? {
    #if os(macOS)
      guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      else { return nil }
      return base.appendingPathComponent("metasequoiaime", isDirectory: true)
    #else
      return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.msime.ios")
    #endif
  }

  private var url: URL? {
    Self.directory?.appendingPathComponent(fileName, isDirectory: false)
  }

  func load() throws -> BackendSavedSession? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    do { return try JSONDecoder().decode(BackendSavedSession.self, from: data) }
    catch { throw BackendAccountClient.Failure(status: 0) }
  }

  func save(_ session: BackendSavedSession) throws {
    guard let url, let directory = Self.directory else { throw BackendAccountClient.Failure(status: 0) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let data = try JSONEncoder().encode(session)
    // 0600 而不是继承目录的默认权限:这是个 bearer token,同机器上的别的用户没有理由读到它。
    try data.write(to: url, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  func clear() throws {
    guard let url else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// 任意一段本机数据,和会话用同一个目录与权限。匿名凭据自己也走这里。
  static func read(_ fileName: String) -> Data? {
    guard let url = directory?.appendingPathComponent(fileName, isDirectory: false) else { return nil }
    return try? Data(contentsOf: url)
  }

  @discardableResult
  static func write(_ data: Data, to fileName: String) -> Bool {
    guard let directory, let url = Optional(directory.appendingPathComponent(fileName, isDirectory: false))
    else { return false }
    guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])) != nil,
          (try? data.write(to: url, options: [.atomic])) != nil
    else { return false }
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return true
  }
}
