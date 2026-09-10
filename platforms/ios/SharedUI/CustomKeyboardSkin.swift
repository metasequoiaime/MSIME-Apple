import UIKit
import ImageIO

extension CustomKeyboardSkin {
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

struct SavedKeyboardSkin: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var design: CustomKeyboardSkin
}

enum CustomSkinLibrary {
  // Keep the multi-photo library out of preferences, which the keyboard reads on each key.
  private static var file: URL {
    let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: InputSchemePreference.appGroupIdentifier)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return root.appendingPathComponent("CustomSkins", isDirectory: true).appendingPathComponent("library.json")
  }
  static var designs: [SavedKeyboardSkin] {
    guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          size <= 9_000_000,
          let data = try? Data(contentsOf: file),
          let items = try? JSONDecoder().decode([SavedKeyboardSkin].self, from: data) else { return [] }
    return Array(items.prefix(12)).map { item in
      var item = item
      item.design = item.design.normalized
      return item
    }
  }
  @discardableResult
  static func save(_ items: [SavedKeyboardSkin]) -> Bool {
    let items = items.prefix(12).map { item in
      var item = item
      item.name = String(item.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
      item.design = item.design.normalized
      return item
    }
    do {
      let data = try JSONEncoder().encode(items)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
      return true
    } catch { return false }
  }
}

extension CustomKeyboardSkin {
  static var templates: [(String, CustomKeyboardSkin)] {
    var paper = Self()
    paper.background = 0xE3D6BD; paper.keyBackground = 0xFFF5DF; paper.keyForeground = 0x382A1C
    paper.accent = 0x53391F; paper.actionBackground = 0x53391F
    paper.cornerRadius = 4; paper.borderWidth = 1; paper.shadow = 0.3; paper.monospaced = true; paper.pattern = 1
    paper.keyShape = .ticket; paper.keyMaterial = .paper
    var night = Self()
    night.background = 0x151022; night.gradientEnd = 0x30224A; night.keyBackground = 0x291E40
    night.keyForeground = 0xFFFFFF; night.accent = 0xD4BBFF; night.actionBackground = 0x69469B
    night.borderWidth = 1; night.customBorderColor = 0xA987E8; night.pattern = 1
    night.keyShape = .rounded; night.keyMaterial = .glass
    var peach = Self()
    peach.background = 0xFFE0D0; peach.gradientEnd = 0xF9D6E5; peach.keyBackground = 0xFFF8EE
    peach.keyForeground = 0x51283A; peach.accent = 0x84334F; peach.actionBackground = 0x84334F
    peach.cornerRadius = 18; peach.shadow = 0.15; peach.pattern = 3
    peach.keyShape = .pebble; peach.keyMaterial = .raised
    var blue = Self()
    blue.background = 0xDCEAF8; blue.gradientEnd = 0xDDEFE9; blue.gradientHorizontal = true
    blue.accent = 0x224E75; blue.actionBackground = 0x224E75; blue.borderWidth = 0.5
    var grid = night
    grid.background = 0x102438; grid.gradientEnd = nil; grid.keyBackground = 0x17354F
    grid.accent = 0xA2D8FA; grid.actionBackground = 0x285D84; grid.cornerRadius = 2
    grid.monospaced = true; grid.pattern = 2; grid.customBorderColor = 0x548CAA
    return [("水杉留白", Self()), ("复古纸感", paper), ("紫夜星光", night), ("奶油桃桃", peach), ("海盐渐变", blue), ("工程蓝图", grid)] + curatedTemplates
  }
}

// Decode only a bounded thumbnail, even when the chosen original is a large panorama.
enum SkinPhotoData {
  static func thumbnail(at url: URL) -> Data? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else { return nil }
    let image = UIImage(cgImage: cg)
    for quality in [0.8, 0.6, 0.4, 0.2] {
      if let data = image.jpegData(compressionQuality: quality), data.count <= 512_000 { return data }
    }
    return nil
  }
}
