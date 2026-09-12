import Foundation

/// 候选词旁边显示英文释义。
///
/// macOS has carried this since the candidate panel learned to draw a second column; iOS had the
/// dictionary in its bundle the whole time and nothing that read it. Off by default: the strip is
/// one row on a phone, so an annotation on every candidate is a change to how the keyboard reads
/// rather than an addition to it, and that should be asked for.
enum CandidateGlossPreference {
  static let enabledKey = "candidate.englishGloss"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var enabled: Bool {
    get { defaults.object(forKey: enabledKey) as? Bool ?? false }
    set { defaults.set(newValue, forKey: enabledKey) }
  }
}
