import Foundation

// Stored separately from the active engine session. The pinned Engine does not yet expose
// fuzzy-pinyin options; do not silently treat these preferences as an applied configuration.
@MainActor
enum FuzzyPinyinPreference {
  static let enabledKey = "fuzzyPinyin.enabled"
  static let rulesKey = "fuzzyPinyin.rules"
  static let defaults = UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
}
