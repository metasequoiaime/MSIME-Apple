import Foundation

enum DictionaryLearningPreference {
  static let key = "dictionaryLearningEnabled"
  // Keep the previous no-learning behavior until the user opts in.
  static var enabled: Bool { KeyboardFeedbackPreference.defaults.bool(forKey: key) }
}
