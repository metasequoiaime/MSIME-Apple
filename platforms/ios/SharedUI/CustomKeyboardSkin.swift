import UIKit

struct CustomKeyboardSkin: Codable, Equatable, Hashable {
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
    result.pattern = (0...3).contains(pattern) ? pattern : 0
    return result
  }

  static func color(_ rgb: UInt32) -> UIColor {
    UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }

  static func rgb(_ color: UIColor) -> UInt32 {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
    return UInt32((min(1, max(0, r)) * 255).rounded()) << 16
      | UInt32((min(1, max(0, g)) * 255).rounded()) << 8
      | UInt32((min(1, max(0, b)) * 255).rounded())
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
  }
}

enum CustomKeyboardSkinStore {
  static let key = "customKeyboardSkin.v1"
  private static let cache = Cache()
  static var current: CustomKeyboardSkin { cache.load() }
  static func save(_ skin: CustomKeyboardSkin) {
    guard let data = try? JSONEncoder().encode(skin.normalized) else { return }
    KeyboardFeedbackPreference.defaults.set(data, forKey: key)
  }

  private final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var previousData: Data?
    private var value = CustomKeyboardSkin()
    func load() -> CustomKeyboardSkin {
      let data = KeyboardFeedbackPreference.defaults.data(forKey: key)
      lock.lock()
      defer { lock.unlock() }
      if data != previousData {
        previousData = data
        value = data.flatMap { try? JSONDecoder().decode(CustomKeyboardSkin.self, from: $0) }?.normalized
          ?? CustomKeyboardSkin()
      }
      return value
    }
  }
}
