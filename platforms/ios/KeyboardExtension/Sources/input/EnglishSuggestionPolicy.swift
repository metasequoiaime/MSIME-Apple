import Foundation

/// 英文候选是补全,不是上屏:文档里已经有敲进去的那几个字母了,选中一个候选意味着把它们换成整词。
enum EnglishSuggestionPolicy {
  struct Replacement: Equatable {
    let deleteCount: Int
    let insert: String
  }

  /// Read Latin letters from the cursor backwards, normalizing full-width forms for the packaged
  /// English dictionary. Unicode letters such as Han or kana must be boundaries.
  static func currentWord(before context: String) -> String {
    var letters: [Character] = []
    for character in context.reversed() {
      let normalized: Character?
      if character.isASCII && character.isLetter {
        normalized = character
      } else if character.unicodeScalars.count == 1,
                let scalar = character.unicodeScalars.first,
                ((0xFF21...0xFF3A).contains(scalar.value) || (0xFF41...0xFF5A).contains(scalar.value)) {
        normalized = Character(String(UnicodeScalar(scalar.value - 0xFEE0)!))
      } else {
        normalized = nil
      }
      guard let normalized else { break }
      letters.append(normalized)
    }
    return String(letters.reversed())
  }

  static func replacement(typed: String, candidate: String, startedCapitalized: Bool) -> Replacement? {
    guard !candidate.isEmpty else { return nil }
    var word = candidate
    if startedCapitalized, let first = word.first {
      word = first.uppercased() + word.dropFirst()
    }
    guard word != typed else { return nil }
    return Replacement(deleteCount: typed.count, insert: word)
  }
}
