import Foundation

enum KeyboardFeedbackPreference {
  static let soundKey = "keyboardSoundEnabled"
  static let hapticsKey = "keyboardHapticsEnabled"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var soundEnabled: Bool {
    defaults.object(forKey: soundKey) as? Bool ?? true
  }

  static var hapticsEnabled: Bool {
    defaults.bool(forKey: hapticsKey)
  }
}
