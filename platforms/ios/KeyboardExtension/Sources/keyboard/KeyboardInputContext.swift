import UIKit

// A field's preferred keyboard temporarily overrides the language, not the user's input scheme.
// Track its identity as well as its type so typing callbacks do not undo a manual language choice.
struct KeyboardInputContext {
  private var documentIdentifier: UUID?
  private(set) var keyboardType: UIKeyboardType = .default
  private var languageBeforeLatinField: Bool?

  static func prefersLatin(_ type: UIKeyboardType) -> Bool {
    switch type {
    case .asciiCapable, .URL, .emailAddress: return true
    default: return false
    }
  }

  mutating func languageOverride(for type: UIKeyboardType, document: UUID, isChinese: Bool) -> Bool? {
    guard documentIdentifier != document || keyboardType != type else { return nil }
    documentIdentifier = document
    keyboardType = type
    if Self.prefersLatin(type) {
      if languageBeforeLatinField == nil { languageBeforeLatinField = isChinese }
      return false
    }
    defer { languageBeforeLatinField = nil }
    return languageBeforeLatinField
  }
}
