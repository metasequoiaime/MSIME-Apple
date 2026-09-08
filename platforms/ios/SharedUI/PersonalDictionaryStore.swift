import Foundation
import Darwin

enum PersonalWordKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case pinyin, wubi, quickPhrase, english
  var id: String { rawValue }
  var title: String {
    switch self {
    case .pinyin: return "拼音"
    case .wubi: return "五笔"
    case .quickPhrase: return "快捷短语"
    case .english: return "英文"
    }
  }
}

struct PersonalWord: Codable, Hashable, Sendable, Identifiable {
  var kind: PersonalWordKind = .pinyin
  var key: String
  var value: String
  var weight: Int64 = 100_000
  // Length prefixes keep arbitrary phrase text from colliding with an input-code separator.
  var id: String { "\(kind.rawValue):\(key.utf8.count):\(key)\(value)" }
}

struct PersonalWordRequest: Codable, Identifiable, Sendable {
  enum Status: String, Codable, Sendable { case pending, applied, failed }
  var id = UUID()
  var previous: PersonalWord?
  var replacement: PersonalWord?
  var status: Status = .pending
  var error: String?
  var createdAt = Date()
}

struct PersonalDictionaryState: Codable, Sendable {
  var version = 1
  var requests: [PersonalWordRequest] = []
  var entries: [PersonalWord] = []
  var hasMore = false
  var snapshotDate: Date?
  var snapshotError: String?
  var pageOffset = 0
  var requestedPageOffset = 0
  var refreshID = UUID()
  var completedRefreshID: UUID?
  var pendingCount: Int { requests.filter { $0.status == .pending }.count }
}

struct PersonalWordPage: Sendable {
  var entries: [PersonalWord]
  var hasMore: Bool
}

// This file is local host/keyboard transport, not the dictionary database. The Engine owns
// validation, candidate changes and durable edit receipts. Call keyboard synchronization only
// with Full Access and with no active input session touching the dictionaries.
final class PersonalDictionaryStore: @unchecked Sendable {
  enum StoreError: LocalizedError {
    case unavailable, invalidState, busy, tooManyRequests, conflict
    var errorDescription: String? {
      switch self {
      case .unavailable: return "无法访问个人词库共享目录。"
      case .invalidState: return "个人词库同步文件无法读取，已保留原文件。"
      case .busy: return "个人词库正在同步，请稍后重试。"
      case .tooManyRequests: return "等待同步的操作过多，请先打开键盘完成同步。"
      case .conflict: return "这个词条已有等待同步的操作，请同步后再编辑。"
      }
    }
  }
  private let directory: URL?
  private static let processLock = NSLock()
  private let maximumBytes = 8 * 1024 * 1024

  init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.msime.ios")) {
    self.directory = directory?.appendingPathComponent("PersonalDictionary", isDirectory: true)
  }

  func read() throws -> PersonalDictionaryState {
    guard let directory else { throw StoreError.unavailable }
    return try readFile(at: directory.appendingPathComponent("sync.json"))
  }

  private func readFile(at file: URL) throws -> PersonalDictionaryState {
    guard FileManager.default.fileExists(atPath: file.path) else { return PersonalDictionaryState() }
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= maximumBytes else { throw StoreError.invalidState }
    let data = try Data(contentsOf: file)
    guard data.count <= maximumBytes,
          let state = try? JSONDecoder().decode(PersonalDictionaryState.self, from: data),
          state.version == 1, state.requests.count <= 160, state.entries.count <= 100,
          state.pageOffset >= 0, state.pageOffset <= 1_000_000,
          state.requestedPageOffset >= 0, state.requestedPageOffset <= 1_000_000,
          Set(state.requests.map(\.id)).count == state.requests.count
    else { throw StoreError.invalidState }
    return state
  }

  private func update(_ action: (inout PersonalDictionaryState) throws -> Void) throws {
    guard let directory else { throw StoreError.unavailable }
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let descriptor = open(directory.appendingPathComponent("sync.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw StoreError.unavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw StoreError.busy }
    defer { flock(descriptor, LOCK_UN) }
    let file = directory.appendingPathComponent("sync.json")
    var state = try readFile(at: file)
    try action(&state)
    let data = try JSONEncoder().encode(state)
    guard data.count <= maximumBytes else { throw StoreError.invalidState }
    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  @discardableResult
  func enqueue(previous: PersonalWord?, replacement: PersonalWord?) throws -> UUID {
    let request = PersonalWordRequest(previous: previous, replacement: replacement)
    try update { state in
      guard previous != nil || replacement != nil else { throw StoreError.invalidState }
      guard state.requests.filter({ $0.status != .applied }).count < 128 else { throw StoreError.tooManyRequests }
      let identities = Set([previous?.id, replacement?.id].compactMap { $0 })
      guard !state.requests.contains(where: {
        $0.status == .pending && !identities.isDisjoint(with: [$0.previous?.id, $0.replacement?.id].compactMap { $0 })
      }) else { throw StoreError.conflict }
      let finished = Set(state.requests.filter { $0.status == .applied }.suffix(31).map(\.id))
      state.requests.removeAll { $0.status == .applied && !finished.contains($0.id) }
      state.requests.append(request)
      state.refreshID = UUID()
    }
    return request.id
  }

  func retry(_ id: UUID) throws {
    try update { state in
      guard let index = state.requests.firstIndex(where: { $0.id == id && $0.status == .failed }) else { return }
      let request = state.requests[index]
      let identities = Set([request.previous?.id, request.replacement?.id].compactMap { $0 })
      guard !state.requests.contains(where: {
        $0.status == .pending && !identities.isDisjoint(with: [$0.previous?.id, $0.replacement?.id].compactMap { $0 })
      }) else { throw StoreError.conflict }
      state.requests[index].status = .pending
      state.requests[index].error = nil
      state.refreshID = UUID()
    }
  }

  func dismissFailure(_ id: UUID) throws {
    try update { $0.requests.removeAll { $0.id == id && $0.status == .failed } }
  }

  func requestPage(offset: Int) throws {
    guard (0...1_000_000).contains(offset) else { throw StoreError.invalidState }
    try update { $0.requestedPageOffset = offset; $0.refreshID = UUID() }
  }

  // Keep the queue lock through apply and acknowledgement. If writing sync.json is interrupted,
  // the same UUID is retried; Engine's transaction receipt makes that retry a no-op success.
  func synchronize(apply: (PersonalWordRequest) throws -> Void,
                   page: (Int) throws -> PersonalWordPage) throws {
    try update { state in
      for index in state.requests.indices where state.requests[index].status == .pending {
        do {
          try apply(state.requests[index])
          state.requests[index].status = .applied
          state.requests[index].error = nil
      state.refreshID = UUID()
        } catch {
          state.requests[index].status = .failed
          state.requests[index].error = String(error.localizedDescription.prefix(500))
        }
      }
      state.completedRefreshID = state.refreshID
      do {
        let snapshot = try page(state.requestedPageOffset)
        guard snapshot.entries.count <= 100 else { throw StoreError.invalidState }
        state.entries = snapshot.entries
        state.hasMore = snapshot.hasMore
        state.pageOffset = state.requestedPageOffset
        state.snapshotDate = Date()
        state.snapshotError = nil
      } catch {
        // Preserve the last confirmed list and every edit acknowledgement even if refresh fails.
        state.snapshotError = String(error.localizedDescription.prefix(500))
      }
    }
  }
}
