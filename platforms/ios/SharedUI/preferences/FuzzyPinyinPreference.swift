import Foundation

@MainActor
enum FuzzyPinyinPreference {
  static let enabledKey = "fuzzyPinyin.enabled"
  static let rulesKey = "fuzzyPinyin.rules"
  /// Distinguishes first enable from an intentionally empty rule selection.
  static let seededKey = "fuzzyPinyin.seeded"
  static let ruleIDs = ["z-zh", "c-ch", "s-sh", "n-l", "f-h", "r-l", "an-ang", "en-eng", "in-ing", "ian-iang", "uan-uang"]
  static let defaults = UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  static let documentKey = "fuzzy_pinyin"

  /// The document's `fuzzy_pinyin` object, which the settings app, the shared Tauri settings page and the keyboard all read.
  struct Settings: Equatable {
    var enabled: Bool
    var rules: Set<String>
    var seeded: Bool

    static let pristine = Settings(enabled: false, rules: [], seeded: false)

    var bits: UInt32 {
      guard enabled else { return 0 }
      return FuzzyPinyinPreference.ruleIDs.enumerated().reduce(UInt32(0)) { value, entry in
        rules.contains(entry.element) ? value | (1 << entry.offset) : value
      }
    }
  }

  static func seededSelection(enabled: Bool, seeded: Bool, current: String) -> String {
    enabled && !seeded ? ruleIDs.joined(separator: ",") : current
  }

  static var activeRules: UInt32 {
    guard defaults.bool(forKey: enabledKey) else { return 0 }
    let seeded = defaults.bool(forKey: seededKey)
    let rules = seededSelection(enabled: true, seeded: seeded, current: defaults.string(forKey: rulesKey) ?? "")
    if !seeded {
      defaults.set(rules, forKey: rulesKey)
      defaults.set(true, forKey: seededKey)
    }
    let selected = Set(rules.split(separator: ",").map(String.init))
    return ruleIDs.enumerated().reduce(UInt32(0)) { value, entry in
      selected.contains(entry.element) ? value | (1 << entry.offset) : value
    }
  }

  /// `nil` when the document carries no readable `fuzzy_pinyin` object.
  static func settings(in preferences: [String: Any]?) -> Settings? {
    guard let fuzzy = preferences?[documentKey] as? [String: Any],
          let enabled = fuzzy["enabled"] as? Bool,
          let rules = fuzzy["rules"] as? [String] else { return nil }
    return Settings(enabled: enabled, rules: Set(rules).intersection(ruleIDs),
                    seeded: fuzzy["seeded"] as? Bool ?? false)
  }

  /// What the App Group held before the document became the source; `nil` when this device never saved one.
  static var legacySettings: Settings? {
    guard defaults.object(forKey: enabledKey) != nil else { return nil }
    let rules = (defaults.string(forKey: rulesKey) ?? "").split(separator: ",").map(String.init)
    return Settings(enabled: defaults.bool(forKey: enabledKey), rules: Set(rules).intersection(ruleIDs),
                    seeded: defaults.bool(forKey: seededKey))
  }

  /// Write the document first and mirror the App Group after it.
  ///
  /// PreferencesStore replaces the rules with every rule on the first disabled-to-enabled save of a document that is not yet seeded, judging by the stored document rather than the incoming one. A seeded selection therefore marks the document seeded in its own write before the selection is written, or the user's rules would be overwritten by all eleven.
  static func save(_ settings: Settings, stateRoot: URL? = nil) -> Bool {
    let stored = self.settings(in: MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: stateRoot))
    if settings.seeded, stored?.seeded != true {
      guard MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: stateRoot, { preferences in
        var fuzzy = preferences[documentKey] as? [String: Any] ?? ["enabled": false, "rules": [String]()]
        fuzzy["seeded"] = true
        preferences[documentKey] = fuzzy
      }) else { return false }
    }
    guard MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: stateRoot, { preferences in
      preferences[documentKey] = ["enabled": settings.enabled, "seeded": settings.seeded,
                                  "rules": ruleIDs.filter(settings.rules.contains)]
    }) else { return false }
    defaults.set(settings.enabled, forKey: enabledKey)
    defaults.set(ruleIDs.filter(settings.rules.contains).joined(separator: ","), forKey: rulesKey)
    defaults.set(settings.seeded, forKey: seededKey)
    return true
  }

  /// Carry an App Group selection into a document that has never been touched, once.
  ///
  /// Returns the settings the keyboard should apply: the document's own when it already has a say, the migrated legacy selection otherwise. A failed migration still applies the legacy selection so the keyboard behaves as it did before the document took over.
  static func resolve(document: [String: Any]?, stateRoot: URL? = nil) -> Settings? {
    let stored = settings(in: document)
    guard stored == nil || stored == .pristine, var legacy = legacySettings,
          legacy != .pristine else { return stored }
    if legacy.enabled && !legacy.seeded {
      legacy.rules = Set(ruleIDs)
      legacy.seeded = true
    }
    _ = save(legacy, stateRoot: stateRoot)
    return legacy
  }
}
