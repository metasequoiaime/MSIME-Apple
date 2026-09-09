import Foundation

// Answers a wubi code the table cannot spell with quanpin candidates for the same letters. A code
// the table does answer keeps its own candidates, so wubi as typed is unchanged. Lives in the app
// group because the keyboard extension reads what the host app writes.
@MainActor
enum WubiMixedPinyinPreference {
  static let enabledKey = "wubi.mixedPinyin"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var isEnabled: Bool {
    get { defaults.bool(forKey: enabledKey) }
    set { defaults.set(newValue, forKey: enabledKey) }
  }
}
