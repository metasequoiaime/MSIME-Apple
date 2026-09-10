import Foundation

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

