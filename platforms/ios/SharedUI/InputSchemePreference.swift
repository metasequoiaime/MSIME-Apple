import Foundation

enum ChineseInputScheme: String, CaseIterable {
  case quanpin, nineKey, shuangpin, ziranma, microsoft, shoudao, wubi, japaneseNineKey, japanese, handwriting, thoughtfulReply

  var isJapanese: Bool { self == .japanese || self == .japaneseNineKey }

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
    case .shoudao: "首道双拼"
    case .wubi: "86 五笔"
    case .japanese: "日语 26 键"
    case .japaneseNineKey: "日语 9 键"
    case .handwriting: "手写"
    case .thoughtfulReply: "高情商回复"
    }
  }
}

enum InputSchemePreference {
  static let enabledSchemesKey = "enabledInputSchemes"
  private static var defaults: UserDefaults { UserDefaults(suiteName: appGroupIdentifier) ?? .standard }

  // Split the previous Japanese layout setting into two independently visible schemes once.
  static func splitJapaneseSchemes(in store: UserDefaults) {
    guard !store.bool(forKey: "japaneseSchemesSplit") else { return }
    if var enabled = store.stringArray(forKey: enabledSchemesKey), enabled.contains("japanese") {
      if !enabled.contains("japaneseNineKey") { enabled.append("japaneseNineKey") }
      store.set(enabled, forKey: enabledSchemesKey)
    }
    if store.string(forKey: schemeKey) == "japanese", !store.bool(forKey: "japaneseRomanKeys") {
      store.set("japaneseNineKey", forKey: schemeKey)
    }
    store.set(true, forKey: "japaneseSchemesSplit")
  }

  static var enabledSchemes: [ChineseInputScheme] {
    get {
      splitJapaneseSchemes(in: defaults)
      guard let stored = defaults.stringArray(forKey: enabledSchemesKey) else { return ChineseInputScheme.allCases }
      let enabled = ChineseInputScheme.allCases.filter { stored.contains($0.rawValue) }
      return enabled.isEmpty ? [.quanpin] : enabled
    }
    set {
      splitJapaneseSchemes(in: defaults)
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
      splitJapaneseSchemes(in: defaults)
      if let value = defaults.string(forKey: schemeKey), let scheme = ChineseInputScheme(rawValue: value) {
        return enabledSchemes.contains(scheme) ? scheme : enabledSchemes[0]
      }
      // 迁移一次就写回,不要每次读都重算。
      //
      // The scheme was stored twice: this name, and an older usesShuangpin boolean that only
      // distinguishes shuangpin from everything else. Nine-key, wubi and handwriting all write
      // false into that boolean, so every read that missed the name resolved to 全拼 26 键 -- and
      // resolved that way again on the next read, because nothing recorded the answer. One lost
      // read of the name silently turned a nine-key keyboard into a 26-key one for good.
      let legacy: ChineseInputScheme = usesShuangpin ? .shuangpin : .quanpin
      let migrated = enabledSchemes.contains(legacy) ? legacy : enabledSchemes[0]
      // 两个键一起写,和 setter 保持一致;只写一个会让它们从此各说各话。
      defaults.set(migrated.shuangpinProfile != nil, forKey: key)
      defaults.set(migrated.rawValue, forKey: schemeKey)
      return migrated
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
