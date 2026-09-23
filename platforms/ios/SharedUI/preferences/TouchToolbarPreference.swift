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

  /// The switches in the order and wording of the shared settings page, keyed by the document name.
  static let options: [(name: String, title: String, keyPath: WritableKeyPath<TouchToolbarPreference, Bool>)] = [
    ("layout", "键盘设置", \.layout),
    ("emoji", "表情", \.emoji),
    ("skin", "切换皮肤", \.skin),
    ("clipboard", "剪贴板历史", \.clipboard),
    ("ai", "AI 润色", \.ai),
    ("character_set", "简繁切换", \.characterSet),
    ("fullwidth", "全角 / 半角", \.fullwidth),
    ("punctuation", "中英文标点", \.punctuation),
  ]

  /// The whole object, so a document holding only some switches is completed the same way the shared page completes it.
  var documentValue: [String: Bool] {
    Dictionary(uniqueKeysWithValues: Self.options.map { ($0.name, self[keyPath: $0.keyPath]) })
  }

  static func load(stateRoot: URL? = nil) -> TouchToolbarPreference {
    TouchToolbarPreference(in: MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: stateRoot))
  }

  /// Written into the shared document, which the keyboard reads each time it appears.
  static func save(_ toolbar: TouchToolbarPreference, stateRoot: URL? = nil) -> Bool {
    MetasequoiaInputSessionBridge.updateSharedPreferences(stateRoot: stateRoot) { $0[key] = toolbar.documentValue }
  }
}
