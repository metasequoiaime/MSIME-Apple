import Foundation

// Renders engine output in the script the user chose. The engine and its dictionary keep their
// original simplified strings, so only visible candidates and committed text pass through here,
// matching the macOS render/commit boundary. An empty string or a failed transform returns the
// original value, so input stays available without a bundled conversion database.
enum ChineseTextConversion {
  static func outputString(_ text: String, traditional: Bool) -> String {
    guard traditional, !text.isEmpty else { return text }

    let buffer = NSMutableString(string: text)
    guard
      CFStringTransform(
        buffer as CFMutableString, nil, "Simplified-Traditional" as CFString, false)
    else {
      return text
    }
    return buffer as String
  }
}
