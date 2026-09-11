import Foundation

extension BackendAccountClient.DictionaryEntry {
  func localWord() throws -> PersonalWord {
    let localKind: PersonalWordKind
    switch kind {
    case .pinyin: localKind = .pinyin
    case .wubi: localKind = .wubi
    case .quick: localKind = .quickPhrase
    case .english: localKind = .english
    }
    return try PersonalWord(kind: localKind, key: code, value: word, weight: weight).validated()
  }
}
