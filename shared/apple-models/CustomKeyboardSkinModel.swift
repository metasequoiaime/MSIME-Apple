import Foundation

enum SkinKeyShape: String, Codable, CaseIterable, Sendable {
  case rounded, capsule, ticket, pebble
  var title: String { switch self { case .rounded: return "圆角"; case .capsule: return "胶囊"; case .ticket: return "票券"; case .pebble: return "卵石" } }
}
enum SkinKeyMaterial: String, Codable, CaseIterable, Sendable {
  case flat, raised, glass, paper
  var title: String { switch self { case .flat: return "哑光"; case .raised: return "立体"; case .glass: return "玻璃"; case .paper: return "纸张" } }
}

struct CustomKeyboardSkin: Codable, Equatable, Hashable, Sendable {
  var background: UInt32 = 0xE8F0EB
  var keyBackground: UInt32 = 0xFFFFFF
  var keyForeground: UInt32 = 0x17251D
  var accent: UInt32 = 0x185C47
  var actionBackground: UInt32 = 0x185C47
  var cornerRadius: Double = 8
  var borderWidth: Double = 0
  var shadow: Double = 0
  var pattern: Int = 0
  var monospaced = false
  // Optional fields preserve decoding of existing v1 designs.
  var keyShape: SkinKeyShape?
  var keyMaterial: SkinKeyMaterial?
  var keyOpacity: Double?
  var gradientEnd: UInt32?
  var gradientHorizontal: Bool?
  var patternOpacity: Double?
  var customBorderColor: UInt32?
  var photo: Data?
  var photoShade: Double?
  var photoPosition: Double?


  var normalized: Self {
    var result = self
    result.background &= 0xFFFFFF
    result.keyBackground &= 0xFFFFFF
    result.keyForeground &= 0xFFFFFF
    result.accent &= 0xFFFFFF
    result.actionBackground &= 0xFFFFFF
    result.cornerRadius = cornerRadius.isFinite ? min(20, max(0, cornerRadius)) : 8
    result.borderWidth = borderWidth.isFinite ? min(2, max(0, borderWidth)) : 0
    result.shadow = shadow.isFinite ? min(0.4, max(0, shadow)) : 0
    result.keyOpacity = keyOpacity.map { $0.isFinite ? min(1, max(0.25, $0)) : 1 }
    result.gradientEnd = gradientEnd.map { $0 & 0xFFFFFF }
    result.customBorderColor = customBorderColor.map { $0 & 0xFFFFFF }
    result.patternOpacity = patternOpacity.map { $0.isFinite ? min(0.5, max(0, $0)) : 0.15 }
    result.photoShade = photoShade.map { $0.isFinite ? min(0.8, max(0, $0)) : 0.25 }
    result.photoPosition = photoPosition.map { $0.isFinite ? min(1, max(0, $0)) : 0.5 }
    if let photo, photo.count > 512_000 { result.photo = nil }
    result.pattern = (0...3).contains(pattern) ? pattern : 0
    return result
  }

  static func luminance(_ rgb: UInt32) -> Double {
    func channel(_ value: UInt32) -> Double {
      let c = Double(value & 255) / 255
      return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(rgb >> 16) + 0.7152 * channel(rgb >> 8) + 0.0722 * channel(rgb)
  }

  static func readableText(on rgb: UInt32) -> UInt32 {
    luminance(rgb) > 0.179 ? 0x000000 : 0xFFFFFF
  }

  static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
    let a = luminance(first), b = luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }

  var hasReadableText: Bool {
    Self.contrast(keyForeground, keyBackground) >= 4.5
      && Self.contrast(accent, background) >= 4.5
      && Self.contrast(accent, keyBackground) >= 4.5
      && (gradientEnd.map { Self.contrast(accent, $0) >= 4.5 } ?? true)
  }
}

