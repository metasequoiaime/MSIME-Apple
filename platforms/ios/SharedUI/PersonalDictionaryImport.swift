import Foundation

// A versioned envelope for user-entered records. Linguistic validation and normalization
// remain in the public Engine API; this is only the file transport used by the host UI.
struct PersonalDictionaryImport: Codable {
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

  static func read(from url: URL) throws -> Self {
    let granted = url.startAccessingSecurityScopedResource()
    defer { if granted { url.stopAccessingSecurityScopedResource() } }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    return try decode(handle.read(upToCount: maximumBytes + 1) ?? Data())
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
