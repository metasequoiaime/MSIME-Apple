import Foundation

/// Controls the optional offline annotation shown beside iOS candidates.
///
/// The keyboard and its containing app share this value through the App Group. It is deliberately
/// off by default: an annotation on every candidate changes the reading of the one-line strip.
enum CandidateGlossPreference {
  static let key = "candidate.englishGloss"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var enabled: Bool {
    get { defaults.object(forKey: key) as? Bool ?? false }
    set { defaults.set(newValue, forKey: key) }
  }
}
