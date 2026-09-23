import Foundation

// Output script shared by the host app and the keyboard extension. The key is new in the App Group,
// so unlike the input scheme there is no standard-defaults value to migrate.
enum ChineseOutputPreference {
  private static let key = "chineseOutputUsesTraditional"

  static var usesTraditional: Bool {
    get { defaults.bool(forKey: key) }
    set { defaults.set(newValue, forKey: key) }
  }

  /// Save the output form where the keyboard reads it: the keyboard copies the shared document's `traditional_chinese_output` over the App Group every time it appears.
  @discardableResult
  static func save(_ traditional: Bool, stateRoot: URL? = nil) -> Bool {
    guard MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: stateRoot, { $0[documentKey] = traditional })
    else { return false }
    usesTraditional = traditional
    return true
  }

  static let documentKey = "traditional_chinese_output"

  private static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }
}
