import Foundation

/// The desktop clipboard contract is shared with the Windows history store:
/// count UTF-16 units for user-visible length, and cap the UTF-8 transfer so
/// persistence and panel transport stay bounded for non-ASCII text.
enum MacClipboardTextLimits {
  static let maxUTF16Units = 4_000
  static let maxUTF8Bytes = 12_000

  static func valid(_ text: String) -> Bool {
    !text.isEmpty && text.utf16.count <= maxUTF16Units && text.utf8.count <= maxUTF8Bytes &&
      !text.unicodeScalars.contains { scalar in
        (scalar.value < 32 && ![9, 10, 13].contains(scalar.value)) || (127...159).contains(scalar.value)
      }
  }
}
