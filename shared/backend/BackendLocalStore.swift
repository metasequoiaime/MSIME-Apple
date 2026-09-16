import Foundation

/// App-Group file storage for the anonymous account shared by the app and keyboard extension.
struct BackendLocalStore: BackendSessionStorage {
  private let fileName: String
  init(fileName: String = "backend-session.json") { self.fileName = fileName }
  private static var directory: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.msime.ios")
  }
  private var url: URL? { Self.directory?.appendingPathComponent(fileName, isDirectory: false) }
  func load() throws -> BackendSavedSession? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    do { return try JSONDecoder().decode(BackendSavedSession.self, from: data) }
    catch { throw BackendAccountClient.Failure(status: 0) }
  }
  func save(_ session: BackendSavedSession) throws {
    guard let url, let directory = Self.directory else { throw BackendAccountClient.Failure(status: 0) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(session).write(to: url, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  func clear() throws { if let url { try? FileManager.default.removeItem(at: url) } }
  static func read(_ fileName: String) -> Data? {
    guard let url = directory?.appendingPathComponent(fileName, isDirectory: false) else { return nil }
    return try? Data(contentsOf: url)
  }
  @discardableResult static func write(_ data: Data, to fileName: String) -> Bool {
    guard let directory else { return false }
    let url = directory.appendingPathComponent(fileName, isDirectory: false)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try data.write(to: url, options: [.atomic])
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      return true
    } catch { return false }
  }
}
