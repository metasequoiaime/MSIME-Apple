import Foundation

/// A closing mark the keyboard writes after the Engine commits the opening one, for 成对标点自动补全.
struct PairedPunctuationCompletion: Equatable {
  /// The ASCII key that opened the pair.
  let opening: String
  let closing: String
}

/// Host-side completion for punctuation pairs that the Engine opens one mark at a time. The Harmony keyboard's `PairedPunctuationPolicy` does the same.
enum PairedPunctuationPolicy {
  private static let completions: [(opening: String, openingMark: String, closing: String)] = [
    ("\"", "“", "”"), ("'", "‘", "’"), ("(", "（", "）"),
    ("<", "《", "》"), ("<", "〈", "〉"), ("[", "【", "】"),
  ]

  /// With pairing on, every quote press opens a fresh pair, as the reference's `KeyHandler.cpp` does. The Engine alternates the quote keys (“ then ”) because a host without pairing needs that, but a host that supplies the closing half itself never sends the press that would have produced it, so the next quote would otherwise arrive as a lone ”. A closing quote at the end of the commit is therefore rewritten to the opening one before the pair is completed; with pairing off the commit is left to the Engine's alternation.
  static func reopenQuote(_ commit: String?, ascii: String, enabled: Bool) -> String? {
    guard enabled, let commit else { return commit }
    if ascii == "\"", commit.hasSuffix("”") { return String(commit.dropLast()) + "“" }
    if ascii == "'", commit.hasSuffix("’") { return String(commit.dropLast()) + "‘" }
    return commit
  }

  /// A closing mark only when the Engine's commit ends in a known opening mark.
  static func completion(_ commit: String?, enabled: Bool) -> PairedPunctuationCompletion? {
    guard enabled, let commit, !commit.isEmpty else { return nil }
    return completions.first { commit.hasSuffix($0.openingMark) }
      .map { PairedPunctuationCompletion(opening: $0.opening, closing: $0.closing) }
  }
}

extension MetasequoiaInputSnapshot {
  /// The same snapshot committing `text` instead.
  func replacingCommit(_ text: String?) -> MetasequoiaInputSnapshot {
    MetasequoiaInputSnapshot(
      isHandled: isHandled, commitText: text, preedit: preedit, reading: reading, phrasePrefix: phrasePrefix,
      candidates: candidates, candidateCodes: candidateCodes, candidateGlosses: candidateGlosses,
      candidateAnnotations: candidateAnnotations, candidatePageCount: candidatePageCount,
      answeredByPinyinFallback: answeredByPinyinFallback, diagnosticText: diagnosticText, localMode: localMode,
      nineKeySpellings: nineKeySpellings)
  }
}
