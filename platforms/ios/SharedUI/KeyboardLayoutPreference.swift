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
  static var defaults: UserDefaults { UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard }
  static let keySpacingKey = "keyboard.spacing.keys"
  static let rowSpacingKey = "keyboard.spacing.rows"
  static let voiceShortcutKey = "keyboard.shortcut.voice"
  static let heightAdjustmentKey = "keyboard.height.adjustment"
  // Old presets supply upgrade defaults only. Key placement no longer depends on them.
  static var keySpacing: Double {
    get { spacing(key: keySpacingKey, fallback: selected.keySpacing, range: 3...6) }
    set { defaults.set(min(6, max(3, newValue)), forKey: keySpacingKey) }
  }
  static var rowSpacing: Double {
    get { spacing(key: rowSpacingKey, fallback: selected.rowSpacing, range: 4...10) }
    set { defaults.set(min(10, max(4, newValue)), forKey: rowSpacingKey) }
  }
  /// 键盘整体高度相对默认值的增减,单位 pt。
  ///
  /// A keyboard extension states its own height, and the built-in one is the only reference a typist
  /// has for what is comfortable, so the useful range is around that rather than a free-for-all: too
  /// short leaves nothing to aim at, too tall eats the conversation above it. The value is added to
  /// whichever height the current orientation and panel already asked for.
  static var heightAdjustment: Double {
    get { spacing(key: heightAdjustmentKey, fallback: 0, range: -12...48) }
    set { defaults.set(min(48, max(-12, newValue)), forKey: heightAdjustmentKey) }
  }
  static var voiceShortcutEnabled: Bool {
    get { defaults.object(forKey: voiceShortcutKey) == nil ? selected == .doubao : defaults.bool(forKey: voiceShortcutKey) }
    set { defaults.set(newValue, forKey: voiceShortcutKey) }
  }

  /// 把键盘设置恢复成默认。
  ///
  /// Forget the stored values rather than writing defaults over them. Every one of these reads
  /// through a fallback already -- the preset's spacing, no height change, the voice entry the
  /// preset implies -- so removing the key is what "default" means, and a later change to any of
  /// those defaults reaches a reset keyboard without this having to be updated to match.
  static func resetToDefaults() {
    for stored in [keySpacingKey, rowSpacingKey, heightAdjustmentKey, voiceShortcutKey] {
      defaults.removeObject(forKey: stored)
    }
  }
  static var geometry: KeyboardGeometry { KeyboardGeometry(keySpacing: keySpacing, rowSpacing: rowSpacing) }
  private static func spacing(key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
    guard let value = defaults.object(forKey: key) as? NSNumber, value.doubleValue.isFinite else { return fallback }
    return min(range.upperBound, max(range.lowerBound, value.doubleValue))
  }
  static var selected: KeyboardLayoutPreset {
    get { KeyboardLayoutPreset(rawValue: defaults.string(forKey: key) ?? "") ?? .msime }
    set { defaults.set(newValue.rawValue, forKey: key) }
  }
}

struct KeyboardGeometry: Equatable {
  let keySpacing: Double
  let rowSpacing: Double
  var sidebarRatio: Double { 0.14 }
  var letterInsetRatio: Double { 0 }
  var centeredLetters: Bool { false }
  var showsBottomLanguage: Bool { true }
  var showsFullKeyboardSymbols: Bool { false }
}
