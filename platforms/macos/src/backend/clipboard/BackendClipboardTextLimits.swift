import Foundation

/// The desktop clipboard contract is shared with the Windows history store: count UTF-16 units for user-visible length, and cap the UTF-8 transfer so persistence and panel transport stay bounded for non-ASCII text.
enum MacClipboardTextLimits {
  static let maxUTF16Units = 4_000
  static let maxUTF8Bytes = 12_000

  /// Mirrors the Windows NormalizeClipboardText and client-core `normalize_text`: strip trailing NUL/CR, then keep the first 4000 UTF-16 units without splitting a scalar. At most 3 UTF-8 bytes per UTF-16 unit keeps the result within `maxUTF8Bytes`.
  static func normalized(_ text: String) -> String {
    var scalars = Array(text.unicodeScalars)
    while let last = scalars.last, last == "\0" || last == "\r" { scalars.removeLast() }
    var units = 0
    var kept = String.UnicodeScalarView()
    for scalar in scalars {
      units += scalar.utf16.count
      if units > maxUTF16Units { break }
      kept.append(scalar)
    }
    return String(kept)
  }

  /// Control characters other than NUL are user content, as on Windows; NUL stays banned because the native bridges pass NUL-terminated text.
  static func valid(_ text: String) -> Bool {
    !text.isEmpty && text.utf16.count <= maxUTF16Units && text.utf8.count <= maxUTF8Bytes &&
      !text.unicodeScalars.contains("\0")
  }
}
