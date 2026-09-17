import Foundation

/// 英文输入时是否在候选栏提示常用单词。
///
/// On by default: an empty strip above an English keyboard is a wasted row, and the English
/// dictionary that answers it is already packaged and opened for the Chinese side's mixed
/// candidates, so switching this on costs a prefix query per keystroke and nothing else.
///
/// The letters still reach the document as they are typed -- this is completion, not composition.
/// Turning it off restores exactly the previous behaviour: letters in, strip empty, shortcut bar
/// left where it was.
enum EnglishSuggestionsPreference {
  static let enabledKey = "english.suggestions"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var isEnabled: Bool {
    get { defaults.object(forKey: enabledKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: enabledKey) }
  }
}
