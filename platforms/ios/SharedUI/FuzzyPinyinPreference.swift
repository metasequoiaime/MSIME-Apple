import Foundation

@MainActor
enum FuzzyPinyinPreference {
  static let enabledKey = "fuzzyPinyin.enabled"
  static let rulesKey = "fuzzyPinyin.rules"
  static let defaults = UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  static var activeRules: UInt32 {
    guard defaults.bool(forKey: enabledKey) else { return 0 }
    let selected = Set((defaults.string(forKey: rulesKey) ?? "").split(separator: ",").map(String.init))
    let keys = ["z-zh", "c-ch", "s-sh", "n-l", "f-h", "r-l", "an-ang", "en-eng", "in-ing", "ian-iang", "uan-uang"]
    return keys.enumerated().reduce(UInt32(0)) { value, entry in
      selected.contains(entry.element) ? value | (1 << entry.offset) : value
    }
  }
}
