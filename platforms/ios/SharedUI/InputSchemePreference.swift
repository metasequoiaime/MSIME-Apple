import Foundation

enum ChineseInputScheme: String, CaseIterable {
  case quanpin, nineKey, shuangpin, ziranma, microsoft, shoudao, wubi, japanese

  var shuangpinProfile: String? {
    switch self {
    case .shuangpin: "xiaohe"
    case .ziranma, .microsoft, .shoudao: rawValue
    default: nil
    }
  }
  var title: String {
    switch self {
    case .quanpin: "全拼 26 键"
    case .nineKey: "全拼 9 键"
    case .shuangpin: "小鹤双拼"
    case .ziranma: "自然码双拼"
    case .microsoft: "微软双拼"
    case .shoudao: "Shoudao 双拼"
    case .wubi: "86 五笔"
    case .japanese: "日语罗马字"
    }
  }
}

enum InputSchemePreference {
  static let enabledSchemesKey = "enabledInputSchemes"
  private static var defaults: UserDefaults { UserDefaults(suiteName: appGroupIdentifier) ?? .standard }

  static var enabledSchemes: [ChineseInputScheme] {
    get {
      guard let stored = defaults.stringArray(forKey: enabledSchemesKey) else { return ChineseInputScheme.allCases }
      let enabled = ChineseInputScheme.allCases.filter { stored.contains($0.rawValue) }
      return enabled.isEmpty ? [.quanpin] : enabled
    }
    set {
      let ordered = ChineseInputScheme.allCases.filter { newValue.contains($0) }
      let enabled = ordered.isEmpty ? [.quanpin] : ordered
      defaults.set(enabled.map(\.rawValue), forKey: enabledSchemesKey)
      scheme = scheme
    }
  }

  private static let schemeKey = "chineseInputScheme"
  static var scheme: ChineseInputScheme {
    get {
      let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
      if let value = defaults.string(forKey: schemeKey), let scheme = ChineseInputScheme(rawValue: value) {
        return enabledSchemes.contains(scheme) ? scheme : enabledSchemes[0]
      }
      let legacy: ChineseInputScheme = usesShuangpin ? .shuangpin : .quanpin
      return enabledSchemes.contains(legacy) ? legacy : enabledSchemes[0]
    }
    set {
      let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
      let selected = enabledSchemes.contains(newValue) ? newValue : enabledSchemes[0]
      defaults.set(selected.shuangpinProfile != nil, forKey: key)
      defaults.set(selected.rawValue, forKey: schemeKey)
    }
  }

  static let appGroupIdentifier = "group.app.msime.ios"
  private static let key = "inputSchemeUsesShuangpin"

  static var usesShuangpin: Bool {
    get {
      guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
        return UserDefaults.standard.bool(forKey: key)
      }
      if sharedDefaults.object(forKey: key) == nil,
        let legacyValue = UserDefaults.standard.object(forKey: key) as? Bool
      {
        sharedDefaults.set(legacyValue, forKey: key)
      }
      return sharedDefaults.bool(forKey: key)
    }
    set {
      let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
      defaults.set(newValue, forKey: key)
      defaults.set(newValue ? ChineseInputScheme.shuangpin.rawValue : ChineseInputScheme.quanpin.rawValue, forKey: schemeKey)
    }
  }
}
