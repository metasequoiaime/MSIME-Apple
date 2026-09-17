import Foundation

/// 英文候选是补全,不是上屏:文档里已经有敲进去的那几个字母了,选中一个候选意味着把它们换成整词。
///
/// 这一段单独放在这里,是因为它算错的两种方式都很安静。退格数少一个,上一个词的尾巴会粘在新词前面;
/// 大小写丢掉,句首就永远是小写 —— 两样都不会报错,只会让人觉得这个功能不太对劲。
enum EnglishSuggestionPolicy {
  struct Replacement: Equatable {
    /// 要退掉的字符数,正好是已经敲进文档的那一截。
    let deleteCount: Int
    /// 退完之后插入的文本。
    let insert: String
  }

  /// typed 是已敲进文档的那一截,candidate 是引擎给的词(引擎按小写前缀查,所以它总是小写)。
  /// startedCapitalized 记的是这个词的第一个字母敲下去时是不是大写。
  static func replacement(typed: String, candidate: String, startedCapitalized: Bool) -> Replacement? {
    guard !candidate.isEmpty else { return nil }
    var word = candidate
    if startedCapitalized, let first = word.first {
      word = first.uppercased() + word.dropFirst()
    }
    // 候选和已敲的完全一样就不必动文档 —— 退掉再原样插回去会在别的输入法看来是一次真实编辑,
    // 也会让撤销栈多出一步没有意义的操作。
    if word == typed {
      return nil
    }
    return Replacement(deleteCount: typed.count, insert: word)
  }
}
