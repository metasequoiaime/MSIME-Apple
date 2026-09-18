import Foundation

enum KeyboardPunctuationContext {
  private static let chineseInputs = [
    "，": ",", "。": ".", "？": "?", "！": "!", "、": "\\", "；": ";", "：": ":",
  ]
  private static let japaneseInputs = [
    "、": "\\", "。": ".", "？": "?", "！": "!", "「": "[", "」": "]", "・": "/",
  ]

  static func precedingScalar(_ contextBeforeInput: String?) -> UInt32 {
    contextBeforeInput?.unicodeScalars.last?.value ?? 0
  }

  static func engineInput(for symbol: String, japanese: Bool) -> String? {
    if symbol.utf8.count == 1, let value = symbol.utf8.first,
       (33...47).contains(value) || (58...64).contains(value)
        || (91...96).contains(value) || (123...126).contains(value) {
      return symbol
    }
    return (japanese ? japaneseInputs : chineseInputs)[symbol]
  }
}
