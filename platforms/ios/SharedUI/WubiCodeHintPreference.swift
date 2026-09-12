import Foundation

// Marks each wubi candidate with the keys that still single it out. An unfinished code answers with
// the codes it can still become, so without this the strip is a row of words with nothing to choose
// between them. On unless it was turned off, the way a wubi table is normally read. Lives in the app
// group because the keyboard extension reads what the host app writes.
@MainActor
enum WubiCodeHintPreference {
  static let enabledKey = "wubi.codeHint"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var isEnabled: Bool {
    get { defaults.object(forKey: enabledKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: enabledKey) }
  }

  // The part of a candidate's own code that has not been typed yet. A candidate reached by the code
  // in full has nothing left, and a candidate whose code does not extend what was typed -- what the
  // mixed-pinyin fallback answers with, keyed by spelling -- would send the user nowhere, so both
  // come back empty.
  static func hint(code: String, typed: String) -> String {
    guard !typed.isEmpty, code.count > typed.count, code.hasPrefix(typed) else { return "" }
    return String(code.dropFirst(typed.count))
  }
}
