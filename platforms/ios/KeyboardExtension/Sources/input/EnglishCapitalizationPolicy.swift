import Foundation

enum EnglishCapitalizationMode {
  case none
  case words
  case sentences
  case allCharacters
}

enum EnglishCapitalizationPolicy {
  private static let apostrophes: Set<Character> = ["'", "’"]
  private static let sentenceTerminators: Set<Character> = [".", "!", "?", "。", "！", "？"]
  private static let closingCharacters: Set<Character> = ["'", "\"", "’", "”", ")", "]", "}"]

  static func shouldShift(
    for mode: EnglishCapitalizationMode,
    contextBeforeInput: String?
  ) -> Bool {
    switch mode {
    case .none:
      return false
    case .allCharacters:
      return true
    case .words:
      guard let contextBeforeInput else { return false }
      guard let lastCharacter = contextBeforeInput.last else { return true }
      if apostrophes.contains(lastCharacter) {
        return false
      }
      let continuesWord = lastCharacter.unicodeScalars.contains {
        CharacterSet.alphanumerics.contains($0)
      }
      return !continuesWord
    case .sentences:
      guard let contextBeforeInput else { return false }
      guard !contextBeforeInput.isEmpty else { return true }
      for character in contextBeforeInput.reversed() {
        if character == "\n" || character == "\r" {
          return true
        }
        if character.isWhitespace || closingCharacters.contains(character) {
          continue
        }
        return sentenceTerminators.contains(character)
      }
      return true
    }
  }
}
