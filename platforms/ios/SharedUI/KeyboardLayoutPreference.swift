import Foundation

/// Product key placement only; never changes the Engine scheme or composing session.
enum KeyboardLayoutPreset: String, CaseIterable {
  case msime, sogou, wechat, doubao
  var title: String {
    switch self {
    case .msime: "水杉默认"
    case .sogou: "搜狗习惯"
    case .wechat: "微信习惯"
    case .doubao: "豆包习惯"
    }
  }
  var detail: String {
    switch self {
    case .msime: "保留水杉原有键位与工具栏"
    case .sogou: "符号与数字分开，中英切换靠右"
    case .wechat: "简洁底栏，标点在空格左侧，中英在右侧"
    case .doubao: "紧凑键距，中英靠右，顶部直达语音结果"
    }
  }
  var keySpacing: Double { self == .sogou || self == .doubao ? 5 : 6 }
  var rowSpacing: Double { self == .sogou || self == .doubao ? 6 : 7 }
  var sidebarRatio: Double { self == .msime ? 0.14 : 0.12 }
  var centeredLetters: Bool { self != .msime }
  var showsBottomLanguage: Bool { self != .msime }
  var showsFullKeyboardSymbols: Bool { self == .sogou }
}

enum KeyboardLayoutPreference {
  static let key = "keyboard.layout.preset"
  private static var defaults: UserDefaults { UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard }
  static var selected: KeyboardLayoutPreset {
    get { KeyboardLayoutPreset(rawValue: defaults.string(forKey: key) ?? "") ?? .msime }
    set { defaults.set(newValue.rawValue, forKey: key) }
  }
}
