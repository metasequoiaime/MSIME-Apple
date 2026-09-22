import Foundation

/// Whether the keyboard may ask the cloud candidate service while a composition is paused.
///
/// The shared preference document turns cloud candidates on by default, as Windows and Android do. On iOS the keyboard is offline by default and says so in the app, so this switch is the only source for the session's `cloud_candidates`: it lives in the App Group, starts off, and the bridge lays it over whatever the shared document holds. A document synced from a desktop where cloud candidates are on therefore never sends an iPhone's typing to a remote service by itself. The request also needs the keyboard's Full Access.
enum CloudCandidatePreference {
  static let key = "candidate.cloudCandidates"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var enabled: Bool {
    get { defaults.object(forKey: key) as? Bool ?? false }
    set { defaults.set(newValue, forKey: key) }
  }
}
