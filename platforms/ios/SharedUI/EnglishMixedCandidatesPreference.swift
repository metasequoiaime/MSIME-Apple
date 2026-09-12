import Foundation

/// 中文输入时是否把英文词混进候选。
///
/// On by default: typing latin letters on the Chinese keyboard and getting only Chinese back reads
/// as the keyboard being unable to produce English at all. The Engine keeps the cost low on its own
/// -- it only consults the English dictionary for an all-lowercase prefix of at least two letters,
/// under Quanpin or Shuangpin -- so a Chinese composition that happens to be spelled in letters is
/// unaffected unless the dictionary actually holds the word.
enum EnglishMixedCandidatesPreference {
  static let enabledKey = "english.mixedCandidates"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var isEnabled: Bool {
    get { defaults.object(forKey: enabledKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: enabledKey) }
  }
}
