import AppKit
import SwiftUI

@main enum EmojiSearchChromeTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let placeholders = ["home": "Search emoji, kaomoji, and symbols", "": "Search emojis",
      "recent": "Search emojis", "kaomoji": "Search kaomoji", "symbols": "Search symbols",
      "clipboard": "搜索剪贴板", "sticker": "Search", "gif": "Search", "unknown": "Search"]
    for (category, placeholder) in placeholders {
      let presentation = MacEmojiSearchPresentation(category: category)
      assert(presentation.placeholder == placeholder)
      assert(presentation.textSize == (category == "clipboard" ? 16 : 14))
      assert(presentation.placeholderSize == (category == "clipboard" ? 16 : 12))
    }
    assert(abs(MacEmojiSearchChrome.height - 104 / 3) < 0.001)
    for light in [false, true] {
      let palette = MacEmojiPalette(light: light)
      assert(palette.searchBackground == (light ? 0xFFFFFF : 0x2B2B33))
      assert(palette.searchBorder == (light ? 0xD0D0D8 : 0x3A3A44))
      assert(palette.searchFocusOpacity == (light ? 0.75 : 0.70))
      for focused in [false, true] {
        let renderer = ImageRenderer(content: MacEmojiSearchChrome(palette: palette, focused: focused)
          .frame(width: 120, height: MacEmojiSearchChrome.height))
        renderer.scale = 3
        guard let image = renderer.cgImage else { fatalError("Search chrome render unavailable") }
        assert(image.width == 360 && image.height == 104)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
          let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        func channels(_ rgb: UInt32) -> [Double] {
          [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)]
        }
        func check(x: Int, expected: [Double]) {
          let index = (52 * image.width + x) * 4
          for channel in 0..<3 { assert(abs(Double(pixels[index + channel]) - expected[channel]) <= 2) }
        }
        let fill = channels(palette.searchBackground)
        check(x: 180, expected: fill)
        let border = channels(focused ? palette.accent : palette.searchBorder)
        let alpha = focused ? palette.searchFocusOpacity : 1
        let blended = zip(border, fill).map { $0 * alpha + $1 * (1 - alpha) }
        check(x: 1, expected: blended)
        check(x: 3, expected: focused ? blended : fill)
        assert(pixels[3] == 0, "rounded corner should remain transparent")
      }
    }
    print("Emoji search chrome pixel checks passed")
  }
}
