import Foundation

/// Product key placement only; never changes the Engine scheme or composing session.
enum KeyboardLayoutPreset: String, CaseIterable {
  case msime, sogou, wechat, doubao
  var title: String {
    switch self {
    case .msime: "水杉默认"
    case .sogou: "符号增强"
    case .wechat: "简洁布局"
    case .doubao: "紧凑语音"
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
  var keySpacing: Double { switch self { case .msime, .sogou: 6; case .wechat: 4; case .doubao: 3 } }
  var rowSpacing: Double { switch self { case .msime: 7; case .sogou: 10; case .wechat: 8; case .doubao: 4 } }
  var sidebarRatio: Double { switch self { case .msime: 0.14; case .sogou: 0.17; case .wechat: 0.11; case .doubao: 0.13 } }
  var letterInsetRatio: Double { switch self { case .msime: 0; case .sogou: 0.07; case .wechat: 0.05; case .doubao: 0.025 } }
  var centeredLetters: Bool { self != .msime }
  var showsBottomLanguage: Bool { true }
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
