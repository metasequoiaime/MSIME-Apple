import Foundation

/// Controls the remaining-code hint beside Wubi candidates.
///
/// The preference is on by default and shared with the keyboard extension through the App Group.
/// A bounded pure helper keeps fallback or unrelated candidate codes from suggesting invalid keys.
@MainActor
enum WubiCodeHintPreference {
  static let enabledKey = "wubi.codeHint"
  nonisolated static let maxCodeLength = 64

  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var isEnabled: Bool {
    get { defaults.object(forKey: enabledKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: enabledKey) }
  }

  nonisolated static func hint(
    code: String, typed: String, answeredByPinyinFallback: Bool
  ) -> String {
    guard !answeredByPinyinFallback, !typed.isEmpty,
          code.count <= maxCodeLength, typed.count <= maxCodeLength,
          code.count > typed.count, code.hasPrefix(typed) else { return "" }
    return String(code.dropFirst(typed.count))
  }
}
