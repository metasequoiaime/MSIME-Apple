import Foundation

@MainActor
enum FuzzyPinyinPreference {
  static let enabledKey = "fuzzyPinyin.enabled"
  static let rulesKey = "fuzzyPinyin.rules"
  /// Distinguishes first enable from an intentionally empty rule selection.
  static let seededKey = "fuzzyPinyin.seeded"
  static let ruleIDs = ["z-zh", "c-ch", "s-sh", "n-l", "f-h", "r-l", "an-ang", "en-eng", "in-ing", "ian-iang", "uan-uang"]
  static let defaults = UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard

  static func seededSelection(enabled: Bool, seeded: Bool, current: String) -> String {
    enabled && !seeded ? ruleIDs.joined(separator: ",") : current
  }

  static var activeRules: UInt32 {
    guard defaults.bool(forKey: enabledKey) else { return 0 }
    let seeded = defaults.bool(forKey: seededKey)
    let rules = seededSelection(enabled: true, seeded: seeded, current: defaults.string(forKey: rulesKey) ?? "")
    if !seeded {
      defaults.set(rules, forKey: rulesKey)
      defaults.set(true, forKey: seededKey)
    }
    let selected = Set(rules.split(separator: ",").map(String.init))
    return ruleIDs.enumerated().reduce(UInt32(0)) { value, entry in
      selected.contains(entry.element) ? value | (1 << entry.offset) : value
    }
  }
}
