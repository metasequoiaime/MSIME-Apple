import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// App-Group file storage for the anonymous account shared by the app and keyboard extension.
struct BackendLocalStore: BackendSessionStorage {
  private let fileName: String
  private let baseDirectory: URL?
  init(fileName: String = "backend-session.json", directory: URL? = nil) {
    self.fileName = fileName
    self.baseDirectory = directory ?? Self.directory
  }
  private static var directory: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.msime.ios")
  }
  private var url: URL? { baseDirectory?.appendingPathComponent(fileName, isDirectory: false) }
  private var lockURL: URL? { baseDirectory?.appendingPathComponent("backend-local-store.lock", isDirectory: false) }

  private func withLock<T>(_ body: () throws -> T) throws -> T {
    guard let directory = baseDirectory, let lockURL else { throw BackendAccountClient.Failure(status: 0) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    #if canImport(Darwin)
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw BackendAccountClient.Failure(status: 0) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw BackendAccountClient.Failure(status: 0) }
    defer { flock(descriptor, LOCK_UN) }
    #endif
    return try body()
  }

  func load() throws -> BackendSavedSession? {
    guard baseDirectory != nil else { return nil }
    return try withLock { () throws -> BackendSavedSession? in
      guard let url, let data = try? Data(contentsOf: url) else { return nil }
      do { return try JSONDecoder().decode(BackendSavedSession.self, from: data) }
      catch { throw BackendAccountClient.Failure(status: 0) }
    }
  }
  func save(_ session: BackendSavedSession) throws {
    let data = try JSONEncoder().encode(session)
    try withLock {
      guard let url else { throw BackendAccountClient.Failure(status: 0) }
      try data.write(to: url, options: [.atomic])
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
  }
  func clear() throws {
    guard baseDirectory != nil else { return }
    try withLock { if let url { try? FileManager.default.removeItem(at: url) } }
  }
  static func read(_ fileName: String) -> Data? {
    guard let directory else { return nil }
    let url = directory.appendingPathComponent(fileName, isDirectory: false)
    return try? BackendLocalStore(fileName: fileName, directory: directory).withLock { try? Data(contentsOf: url) }
  }
  @discardableResult static func write(_ data: Data, to fileName: String) -> Bool {
    guard let directory else { return false }
    do {
      try BackendLocalStore(fileName: fileName, directory: directory).withLock {
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      }
      return true
    } catch { return false }
  }
}
