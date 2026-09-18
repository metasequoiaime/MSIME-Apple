import Foundation

// Output script shared by the host app and the keyboard extension. The key is new in the App Group,
// so unlike the input scheme there is no standard-defaults value to migrate.
enum ChineseOutputPreference {
  private static let key = "chineseOutputUsesTraditional"

  static var usesTraditional: Bool {
    get { defaults.bool(forKey: key) }
    set { defaults.set(newValue, forKey: key) }
  }

  private static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }
}
