import Foundation

enum CommunityResourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case dictionary, reply
  var id: String { rawValue }
  var title: String { self == .dictionary ? "词库" : "回复" }
  var icon: String { self == .dictionary ? "character.book.closed.fill" : "text.bubble.fill" }
}
struct CommunityWord: Codable, Sendable {
  var kind: String
  var code: String
  var word: String
  var weight: Int64
  init(_ value: PersonalWord) {
    kind = value.kind == .quickPhrase ? "quick" : value.kind.rawValue
    code = value.key; word = value.value; weight = value.weight
  }
  func localWord() throws -> PersonalWord {
    guard let kind = PersonalWordKind(rawValue: kind == "quick" ? "quickPhrase" : kind) else {
      throw PersonalDictionaryStore.StoreError.invalidState
    }
    return try PersonalWord(kind: kind, key: code, value: word, weight: weight).validated()
  }
}
struct CommunityResourceContent: Codable, Sendable {
  var entries: [CommunityWord]?
  var prompt: String?
}
struct CommunityResource: Codable, Identifiable, Sendable {
  var id: String
  var kind: CommunityResourceKind
  var name: String
  var description: String
  var author: String
  var content: CommunityResourceContent
  var revision: Int
  var saves: Int
  var saved: Bool
  var owned: Bool
  var rating_count: Int
  var rating_average: Double
  var my_rating: Int
}

// Only explicit downloads are shared with the keyboard; never credentials or source messages.
enum CommunityLibrary {
  private static var file: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: InputSchemePreference.appGroupIdentifier)?
      .appendingPathComponent("CommunityLibrary.json")
  }
  static func read() throws -> [CommunityResource] {
    guard let file else { throw PersonalDictionaryStore.StoreError.unavailable }
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4_000_000 else {
      throw PersonalDictionaryStore.StoreError.invalidState
    }
    return try JSONDecoder().decode([CommunityResource].self, from: Data(contentsOf: file))
  }
  static func save(_ item: CommunityResource) throws {
    var items = try read()
    items.removeAll { $0.id == item.id }
    guard items.count < 50 else { throw PersonalDictionaryStore.StoreError.tooManyRequests }
    items.append(item)
    try write(items)
  }
  static func remove(_ id: String) throws { try write(read().filter { $0.id != id }) }
  private static func write(_ items: [CommunityResource]) throws {
    guard let file else { throw PersonalDictionaryStore.StoreError.unavailable }
    let data = try JSONEncoder().encode(items)
    guard data.count <= 4_000_000 else { throw PersonalDictionaryStore.StoreError.tooManyRequests }
    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  static var replies: [CommunityResource] { ((try? read()) ?? []).filter { $0.kind == .reply } }
}
