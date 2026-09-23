import Foundation

/// 工具栏按钮: the optional buttons on the keyboard's shortcut bar, from the shared `touch_toolbar`, the touch counterpart of the Windows floating toolbar's component switches.
///
/// A missing document or a missing switch reads as its default, which is the bar the keyboard always had: settings, emoji and skin on, the rest off. The voice entry keeps its own `touch_voice_shortcut`, and the brand, scheme and dismiss buttons are not optional.
struct TouchToolbarPreference: Equatable {
  static let key = "touch_toolbar"

  var layout = true
  var emoji = true
  var skin = true
  var clipboard = false
  var ai = false
  var characterSet = false
  var fullwidth = false
  var punctuation = false

  init() {}

  init(in preferences: [String: Any]?) {
    let stored = preferences?[Self.key] as? [String: Any] ?? [:]
    func read(_ name: String, _ fallback: Bool) -> Bool { stored[name] as? Bool ?? fallback }
    layout = read("layout", layout)
    emoji = read("emoji", emoji)
    skin = read("skin", skin)
    clipboard = read("clipboard", clipboard)
    ai = read("ai", ai)
    characterSet = read("character_set", characterSet)
    fullwidth = read("fullwidth", fullwidth)
    punctuation = read("punctuation", punctuation)
  }
}
