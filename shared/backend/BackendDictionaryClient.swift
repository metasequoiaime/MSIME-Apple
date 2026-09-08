import Foundation

extension BackendAccountClient {
  enum DictionaryKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case pinyin, wubi, quick, english
    var id: String { rawValue }
    var title: String {
      switch self { case .pinyin: return "拼音"; case .wubi: return "五笔"; case .quick: return "快捷短语"; case .english: return "英文" }
    }
  }
  struct DictionaryEntry: Decodable, Identifiable, Sendable {
    let id: String
    let kind: DictionaryKind
    let code: String
    let word: String
    let weight: Int64
    let revision: Int64
  }
  struct DictionaryPage: Decodable, Sendable {
    let entries: [DictionaryEntry]
    let has_more: Bool
    let offset: Int
  }
  struct DictionaryChange: Decodable, Sendable {
    let revision: Int64
    let previous: DictionaryEntry?
    let replacement: DictionaryEntry?
  }
  struct DictionaryValue: Encodable, Sendable {
    let code: String
    let word: String
    let weight: Int64
  }
  func dictionary(_ kind: DictionaryKind, search: String = "", offset: Int = 0, token: String) async throws -> DictionaryPage {
    guard (0...1_000_000).contains(offset), search.utf8.count <= 1024, !search.contains("\0") else { throw Failure(status: 400) }
    var url = URLComponents()
    url.path = "/v1/users/me/dictionaries/" + kind.rawValue
    url.queryItems = [.init(name: "q", value: search), .init(name: "offset", value: String(offset)), .init(name: "limit", value: "100")]
    guard let path = url.string else { throw Failure(status: 400) }
    return try await json("GET", path, token: token)
  }
  func addDictionary(_ kind: DictionaryKind, value: DictionaryValue, token: String) async throws -> DictionaryChange {
    try await json("POST", "/v1/users/me/dictionaries/" + kind.rawValue, token: token, body: JSONEncoder().encode(value))
  }
  func updateDictionary(_ entry: DictionaryEntry, value: DictionaryValue, token: String) async throws -> DictionaryChange {
    struct Body: Encodable { let code: String; let word: String; let weight: Int64; let revision: Int64 }
    return try await json("PUT", dictionaryEntryPath(entry), token: token,
      body: JSONEncoder().encode(Body(code: value.code, word: value.word, weight: value.weight, revision: entry.revision)))
  }
  func deleteDictionary(_ entry: DictionaryEntry, token: String) async throws -> DictionaryChange {
    struct Body: Encodable { let revision: Int64 }
    return try await json("DELETE", dictionaryEntryPath(entry), token: token, body: JSONEncoder().encode(Body(revision: entry.revision)))
  }
  private func dictionaryEntryPath(_ entry: DictionaryEntry) throws -> String {
    guard entry.revision > 0, entry.id.utf8.count == 64,
          entry.id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure(status: 400) }
    return "/v1/users/me/dictionaries/" + entry.kind.rawValue + "/" + entry.id
  }
}
