import Foundation

struct ClipboardHistoryItem: Codable, Equatable, Identifiable {
  var id = UUID()
  var text: String
  var date = Date()
  var pinned = false
}

struct ClipboardHistoryStore {
  static let limit = 50
  let file: URL
  init(directory: URL? = nil) {
    #if os(macOS)
    let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MetasequoiaIME", isDirectory: true)
    #else
    let root = directory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: InputSchemePreference.appGroupIdentifier)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    #endif
    file = root.appendingPathComponent("Clipboard/history.json")
  }
  func load() throws -> [ClipboardHistoryItem] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 4_000_000 else { throw Failure.invalidFile }
    let items = try JSONDecoder().decode([ClipboardHistoryItem].self, from: Data(contentsOf: file))
    guard items.count <= Self.limit, items.allSatisfy({ $0.text.count <= 10_000 && $0.text.utf8.count <= 40_000 }) else { throw Failure.invalidFile }
    return items.sorted { $0.pinned != $1.pinned ? $0.pinned : $0.date > $1.date }
  }
  func save(_ items: [ClipboardHistoryItem]) throws {
    guard items.count <= Self.limit else { throw Failure.full }
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    #if os(macOS)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.deletingLastPathComponent().path)
    #endif
    var directory = file.deletingLastPathComponent()
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    #if os(macOS)
    try JSONEncoder().encode(items).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #else
    try JSONEncoder().encode(items).write(to: file, options: [.atomic, .completeFileProtection])
    #endif
  }
  func add(_ text: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
    guard text.count <= 10_000, text.utf8.count <= 40_000 else { throw Failure.tooLong }
    var items = try load()
    if let index = items.firstIndex(where: { $0.text == text }) {
      items[index].date = Date()
    } else {
      if items.count == Self.limit {
        guard let index = items.lastIndex(where: { !$0.pinned }) else { throw Failure.full }
        items.remove(at: index)
      }
      items.insert(ClipboardHistoryItem(text: text), at: 0)
    }
    try save(items)
  }
  enum Failure: Error, LocalizedError {
    case empty, tooLong, full, invalidFile
    var errorDescription: String? {
      switch self {
      case .empty: "剪贴板中没有可保存的文本，或尚未允许粘贴。"
      case .tooLong: "单条最多保存 10,000 字，请缩短后重试。"
      case .full: "50 条历史均已固定，请先取消固定或删除一条。"
      case .invalidFile: "历史记录无法读取，请清空后重试。"
      }
    }
  }
}
