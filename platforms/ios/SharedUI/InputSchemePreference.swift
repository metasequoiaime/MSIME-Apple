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
  private static let schemeKey = "chineseInputScheme"
  static var scheme: ChineseInputScheme {
    get {
      let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
      if let value = defaults.string(forKey: schemeKey), let scheme = ChineseInputScheme(rawValue: value) {
        return scheme
      }
      return usesShuangpin ? .shuangpin : .quanpin
    }
    set {
      let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
      defaults.set(newValue.shuangpinProfile != nil, forKey: key)
      defaults.set(newValue.rawValue, forKey: schemeKey)
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
