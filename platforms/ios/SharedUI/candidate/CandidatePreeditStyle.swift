import Foundation

/// 「候选栏预编辑」: whether the candidate strip shows what is being spelled, from the shared `candidate_preedit_style`.
///
/// A keyboard extension has no composition in the document, so the strip is the only place the spelling is visible at all; `empty` gives that space back to the candidates. Two things that share the strip's title are deliberately not governed by it, the same as on Android. The already-chosen half of a phrase (`phrase_prefix`) stays, because the runtime keeps it out of the document so the user can spell the rest, and hiding it would leave characters the user has picked neither in the document nor on screen. A local input mode's name stays too: it says which mode is running rather than being composed text, and without it the user would be in a mode with nothing on screen to say so.
enum CandidatePreeditStyle: String, CaseIterable {
  case pinyin, empty

  static let key = "candidate_preedit_style"

  /// The stored value, with anything unrecognised reading as the shared default.
  init(in preferences: [String: Any]?) {
    self = preferences?[Self.key] as? String == Self.empty.rawValue ? .empty : .pinyin
  }

  var title: String {
    switch self {
    case .pinyin: "拼音分词"
    case .empty: "不显示"
    }
  }

  /// The strip's title while composing. `composition` is the phrase prefix followed by the spelling, as the strip already builds it; `localModeName` is set while a local mode is running.
  func title(composition: String, phrasePrefix: String, localModeName: String?) -> String {
    switch self {
    case .pinyin: composition
    case .empty: phrasePrefix + (localModeName ?? "")
    }
  }
}
