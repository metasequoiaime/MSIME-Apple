import Foundation

/// 行内预编辑: whether the keyboard also writes the composition into the text field as marked text, the way Apple's own Chinese keyboards and the Android host do, instead of showing it only on the candidate strip.
///
/// Off by default. The shared `tsf_preedit_style` cannot carry it: every document holds its default `raw`, so honouring that would move every existing iPhone and iPad user to inline text at once, and third-party apps differ in how well they draw a keyboard extension's marked text. The switch lives in the App Group because the keyboard reads it on every keystroke.
enum InlinePreeditPreference {
  static let key = "keyboard.inline_preedit"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var isEnabled: Bool {
    get { defaults.bool(forKey: key) }
    set { defaults.set(newValue, forKey: key) }
  }
}
