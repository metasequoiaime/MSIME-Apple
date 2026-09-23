import Foundation

// A versioned envelope for user-entered records. Linguistic validation and normalization
// remain in the public Engine API; this is only the file transport used by the host UI.
struct PersonalDictionaryImport: Codable, Sendable {
  var format = "msime-personal-dictionary"
  var version = 1
  var entries: [PersonalWord]
  static let maximumBytes = 1_048_576

  struct ImportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static func decode(_ data: Data) throws -> Self {
    guard data.count <= maximumBytes else { throw ImportError(message: "文件不能超过 1 MB。") }
    guard let file = try? JSONDecoder().decode(Self.self, from: data),
          file.format == "msime-personal-dictionary", file.version == 1 else {
      throw ImportError(message: "文件格式不支持，请按示例 JSON 文件填写。")
    }
    guard !file.entries.isEmpty, file.entries.count <= 128 else {
      throw ImportError(message: "每次导入需要 1–128 条词条，请将较大的词库拆分后导入。")
    }
    var entries: [PersonalWord] = []
    var identities = Set<String>()
    for (index, entry) in file.entries.enumerated() {
      let word: PersonalWord
      do { word = try entry.validated() } catch {
        throw ImportError(message: "第 \(index + 1) 条：\(error.localizedDescription)")
      }
      guard identities.insert(word.id).inserted else {
        throw ImportError(message: "第 \(index + 1) 条与前面的词条重复，请删除重复项后重试。")
      }
      entries.append(word)
    }
    return Self(entries: entries)
  }

  /// Plain Chinese words, one per line, annotated with pinyin by the shared Engine. Repeated words collapse to their first line; the queue takes at most 128 at a time, the same as a JSON import.
  static func hans(_ text: String,
                   annotate: (String) throws -> [PersonalWord] = { try PersonalDictionaryBridge.hansEntries($0) }) throws -> Self {
    guard text.utf8.count <= maximumBytes else { throw ImportError(message: "词表不能超过 1 MB。") }
    var identities = Set<String>()
    let entries = try annotate(text).filter { identities.insert($0.id).inserted }
    guard !entries.isEmpty, entries.count <= 128 else {
      throw ImportError(message: "每次导入需要 1–128 个词语，请将较大的词表拆分后导入。")
    }
    return Self(entries: entries)
  }

  static func read(from url: URL) throws -> Self {
    try decode(readData(from: url))
  }

  /// A UTF-8 word list from a file, for `hans`.
  static func readText(from url: URL) throws -> String {
    guard let text = String(data: try readData(from: url), encoding: .utf8) else {
      throw ImportError(message: "词表需要是 UTF-8 编码的文本文件。")
    }
    return text
  }

  private static func readData(from url: URL) throws -> Data {
    let granted = url.startAccessingSecurityScopedResource()
    defer { if granted { url.stopAccessingSecurityScopedResource() } }
    var coordinationError: NSError?
    var result: Result<Data, Error>?
    // File providers may need to materialize a cloud document before it can be read.
    // Create and use this coordinator on the worker thread, never on the UI thread.
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
      result = Result {
        let handle = try FileHandle(forReadingFrom: readableURL)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumBytes {
          let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)) ?? Data()
          if chunk.isEmpty { break }
          data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw ImportError(message: "文件不能超过 1 MB。") }
        return data
      }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw ImportError(message: "无法读取所选文件，请重新选择。") }
    return try result.get()
  }

  static let example = Self(entries: [
    PersonalWord(key: "ni hao", value: "你好"),
    PersonalWord(kind: .wubi, key: "wq", value: "你"),
    PersonalWord(kind: .english, key: "hello", value: "Hello"),
    PersonalWord(kind: .quickPhrase, key: "greeting", value: "你好！\n很高兴认识你。")
  ])

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
