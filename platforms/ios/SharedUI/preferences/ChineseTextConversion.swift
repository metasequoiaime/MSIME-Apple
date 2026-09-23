import Foundation

@_silgen_name("msime_client_simplified_to_traditional")
private func msimeSimplifiedToTraditional(
  _ text: UnsafePointer<UInt8>?, _ length: UInt
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_string_free")
private func msimeChineseConversionStringFree(_ value: UnsafeMutablePointer<CChar>?)

// Renders engine output in the script the user chose. The engine and its dictionary keep their original simplified strings, so only visible candidates and committed text pass through here, matching the macOS render/commit boundary.
//
// The conversion is the shared phrase-level OpenCC s2t tables compiled into the Rust library, the one the Windows, macOS, Linux, Android and HarmonyOS hosts call, so 头发 becomes 頭髮 and 发展 becomes 發展 on every platform. A character transform cannot tell those apart. When the C ABI refuses the text (an embedded NUL) the original value is returned, so input stays available.
enum ChineseTextConversion {
  static func outputString(_ text: String, traditional: Bool) -> String {
    guard traditional, !text.isEmpty else { return text }

    var source = text
    let converted = source.withUTF8 { bytes in
      msimeSimplifiedToTraditional(bytes.baseAddress, UInt(bytes.count))
    }
    guard let converted else { return text }
    defer { msimeChineseConversionStringFree(converted) }
    return String(cString: converted)
  }
}
