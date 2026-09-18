import UIKit

enum KeyboardHapticStrength: String, CaseIterable {
  case light, medium, strong
  var title: String {
    switch self { case .light: "轻"; case .medium: "中"; case .strong: "强" }
  }
  var style: UIImpactFeedbackGenerator.FeedbackStyle {
    switch self { case .light: .light; case .medium: .medium; case .strong: .heavy }
  }
  var intensity: CGFloat { self == .light ? 0.7 : 1.0 }
}

enum KeyboardFeedbackPreference {
  static let soundKey = "keyboardSoundEnabled"
  static let hapticsKey = "keyboardHapticsEnabled"
  static let strengthKey = "keyboardHapticStrength"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var soundEnabled: Bool {
    defaults.object(forKey: soundKey) as? Bool ?? true
  }

  static var hapticsEnabled: Bool {
    defaults.bool(forKey: hapticsKey)
  }
  static var hapticStrength: KeyboardHapticStrength {
    KeyboardHapticStrength(rawValue: defaults.string(forKey: strengthKey) ?? "") ?? .medium
  }
}
