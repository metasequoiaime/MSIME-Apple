import Foundation

enum FrequencyAdjustmentMode: String, CaseIterable {
  case pin, halve, linear, promote

  var title: String {
    switch self {
    case .pin: "一次置顶"
    case .halve: "折半调频"
    case .linear: "线性调频"
    case .promote: "一次置前"
    }
  }
}

enum FrequencyAdjustmentPreference {
  static let modeKey = "frequencyAdjustmentMode"
  static let triggerCountKey = "frequencyAdjustmentTriggerCount"
  static let linearStepKey = "frequencyAdjustmentLinearStep"

  static func resolvedMode(_ stored: String?) -> FrequencyAdjustmentMode {
    FrequencyAdjustmentMode(rawValue: stored ?? "") ?? .promote
  }

  static func resolvedCount(_ stored: Any?) -> Int {
    let value: Int?
    if let number = stored as? Int {
      value = number
    } else if let number = stored as? NSNumber {
      value = number.intValue
    } else {
      value = nil
    }
    guard let value, (1...6).contains(value) else { return 1 }
    return value
  }

  static var mode: FrequencyAdjustmentMode {
    get { resolvedMode(defaults.string(forKey: modeKey)) }
    set { defaults.set(newValue.rawValue, forKey: modeKey) }
  }

  static var triggerCount: Int {
    get { resolvedCount(defaults.object(forKey: triggerCountKey)) }
    set { defaults.set(resolvedCount(newValue), forKey: triggerCountKey) }
  }

  static var linearStep: Int {
    get { resolvedCount(defaults.object(forKey: linearStepKey)) }
    set { defaults.set(resolvedCount(newValue), forKey: linearStepKey) }
  }

  private static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }
}
