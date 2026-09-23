import Foundation

@_silgen_name("msime_client_simplified_to_traditional")
private func msimeSimplifiedToTraditional(_ text: UnsafePointer<UInt8>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_string_free")
private func msimeChineseConversionStringFree(_ value: UnsafeMutablePointer<CChar>?)

// Renders engine output in the script the user chose. The engine and its dictionary keep their original simplified strings, so only visible candidates and committed text pass through here, matching the macOS render/commit boundary.
//
// The conversion is the shared OpenCC s2t one every other host uses, which works on phrases: whether 发 is 發 or 髮 is a property of the word, and the character-by-character CFStringTransform this used before wrote 头发 as 頭發. A failed conversion returns the original value, so input stays available.
enum ChineseTextConversion {
  static func outputString(_ text: String, traditional: Bool) -> String {
    guard traditional, !text.isEmpty else { return text }
    var bytes = Array(text.utf8)
    guard let converted = bytes.withUnsafeMutableBufferPointer({ buffer in
      msimeSimplifiedToTraditional(buffer.baseAddress, UInt(buffer.count))
    }) else {
      return text
    }
    defer { msimeChineseConversionStringFree(converted) }
    return String(cString: converted)
  }
}
