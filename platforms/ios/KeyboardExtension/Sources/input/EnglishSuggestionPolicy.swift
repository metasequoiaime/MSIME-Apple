import Foundation

/// 英文候选是补全,不是上屏:文档里已经有敲进去的那几个字母了,选中一个候选意味着把它们换成整词。
enum EnglishSuggestionPolicy {
  struct Replacement: Equatable {
    let deleteCount: Int
    let insert: String
  }

  /// Read only ASCII letters from the cursor backwards. Unicode letters such as Han or kana
  /// must be boundaries because the packaged English dictionary accepts a-z prefixes only.
  static func currentWord(before context: String) -> String {
    String(context.reversed().prefix { $0.isASCII && $0.isLetter }.reversed())
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
