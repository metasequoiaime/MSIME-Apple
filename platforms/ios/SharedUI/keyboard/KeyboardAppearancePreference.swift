import UIKit

/// 「键盘明暗」: the shared `screen_keyboard_theme`, and the handwriting, emoji and voice panels' own themes, as the interface style the keyboard draws in.
///
/// Every keyboard skin colour is a dynamic colour, so overriding the interface style is all it takes to draw a skin in its light or dark form, whatever the host app looks like. `follow` falls back to the shared `theme`, and when that is `system` too, to nothing: the keyboard then takes the host's appearance as before. The panels differ from Android in one respect that suits iOS: a panel left on `follow` with the global theme on `system` follows the keyboard rather than the host, because it sits inside the keyboard and would otherwise be the one light rectangle in a dark keyboard.
enum KeyboardAppearancePreference {
  static let keyboardKey = "screen_keyboard_theme"
  static let handwritingKey = "handwriting_theme"
  static let emojiKey = "emoji_theme"
  static let voiceKey = "voice_theme"
  static let options: [(id: String, title: String)] = [("follow", "跟随系统"), ("light", "浅色"), ("dark", "深色")]
  /// A panel's `follow` ends at the keyboard, so it says so.
  static let panelOptions: [(id: String, title: String)] = [("follow", "跟随键盘"), ("light", "浅色"), ("dark", "深色")]
  static let panels: [(key: String, title: String)] = [(handwritingKey, "手写面板"), (emojiKey, "表情面板"), (voiceKey, "语音面板")]

  /// The style `key` asks for: its own value, then the global `theme`, then `.unspecified` to inherit.
  static func style(_ key: String, in preferences: [String: Any]?) -> UIUserInterfaceStyle {
    switch preferences?[key] as? String {
    case "dark": return .dark
    case "light": return .light
    default: break
    }
    switch preferences?["theme"] as? String {
    case "dark": return .dark
    case "light": return .light
    default: return .unspecified
    }
  }
}
