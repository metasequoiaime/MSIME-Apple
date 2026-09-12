import AppKit
import SwiftUI

@main enum EmojiAppearanceTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    for light in [false, true] {
      let palette = MacEmojiPalette(light: light)
      let expected: [UInt32] = light
        ? [0xF7F7FA, 0x202027, 0x686873, 0xE0D7E5, 0xD3C7D9, 0x9A62AD]
        : [0x202027, 0xF5F5F7, 0xAFAFB7, 0x3B3B44, 0x555560, 0xD88BDE]
      assert([palette.background, palette.text, palette.muted, palette.selected, palette.pressed, palette.accent] == expected)
      for rgb in expected {
        let renderer = ImageRenderer(content: Rectangle().fill(MacEmojiPalette.color(rgb)).frame(width: 8, height: 8))
        guard let image = renderer.cgImage else {
          fatalError("Palette rendering unavailable")
        }
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        pixels.withUnsafeMutableBytes { buffer in
          let context = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let center = (4 * 8 + 4) * 4
        let actual = pixels[center..<(center + 3)].map(Int.init)
        let channels = [Int((rgb >> 16) & 255), Int((rgb >> 8) & 255), Int(rgb & 255)]
        assert(zip(actual, channels).allSatisfy { abs($0 - $1) <= 1 })
      }
      assert(palette.cellFill(hovered: false, isPressed: false) == nil)
      assert(palette.cellFill(hovered: true, isPressed: false) == palette.selected)
      for hovered in [false, true] {
        assert(palette.cellFill(hovered: hovered, isPressed: true) == palette.pressed)
      }
    }
    let appearance = MacEmojiAppearance()
    assert(appearance.colorScheme == .dark)
    appearance.apply(["theme": "light"])
    assert(appearance.colorScheme == .light)
    appearance.apply(["theme": "system"])
    assert(appearance.colorScheme == nil)
    for invalid: NSDictionary in [[:], ["theme": "invalid"], ["theme": 123], ["theme": "dark"]] {
      appearance.apply(invalid)
      assert(appearance.colorScheme == .dark)
    }
    print("Emoji appearance checks passed")
  }
}
