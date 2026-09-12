import AppKit
import SwiftUI

@main enum EmojiGridTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    assert(MacEmojiGridMetrics.columns == 6)
    assert(MacEmojiGridMetrics.stride == 56 && MacEmojiGridMetrics.width == 336)
    assert(abs(MacEmojiGridMetrics.gap - 4.48) < 0.0001)
    assert(abs(MacEmojiGridMetrics.cell - 51.52) < 0.0001)
    assert(MacEmojiGridMetrics.minimumPanelWidth - 40 - 16 == MacEmojiGridMetrics.width)
    for text in ["abcd", "😀😀", "a\u{301}b\u{301}"] {
      assert(MacEmojiGridMetrics.fontSize(text) == 28)
    }
    for text in ["abcde", "😀😀a", "a\u{301}b\u{301}c"] {
      assert(MacEmojiGridMetrics.fontSize(text) <= 12)
    }
    assert(MacEmojiGridMetrics.fontSize(String(repeating: "synthetic", count: 100)) == 6)
    for count in [1, 6, 7, 18, 28, 255] {
      for index in 0..<count {
        assert(MacEmojiGridCommand.down.destination(from: index, count: count,
          columns: MacEmojiGridMetrics.columns) == min(count - 1, index + 6))
        assert(MacEmojiGridCommand.up.destination(from: index, count: count,
          columns: MacEmojiGridMetrics.columns) == max(0, index - 6))
      }
    }
    for light in [false, true] {
      let palette = MacEmojiPalette(light: light)
      for count in [1, 6, 7, 18, 28] {
        let items = (0..<count).map { MacEmojiCatalogItem(text: "fixture-\($0)", annotation: "synthetic", group: "fixture") }
        let selected = count - 1
        let renderer = ImageRenderer(content: MacEmojiGrid(items: items, palette: palette,
          selected: { $0 == selected }, identity: { $0 }, copy: { _ in }).background(Color.white))
        renderer.scale = 3
        guard let image = renderer.cgImage else { fatalError("Grid rendering unavailable") }
        let rows = (count + 5) / 6
        assert(image.width == 1008 && image.height == rows * 168,
          "Grid fixture count=\(count) rendered \(image.width)x\(image.height), expected 1008x\(rows * 168)")
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
          let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        func check(_ x: Int, _ y: Int, _ color: UInt32) {
          let pixel = (y * image.width + x) * 4
          for channel in 0..<3 {
            let expected = Int((color >> ((2 - channel) * 8)) & 255)
            assert(abs(Int(pixels[pixel + channel]) - expected) <= 2)
          }
        }
        let x = (selected % 6) * 168
        let y = (selected / 6) * 168
        check(x + 30, y + 30, palette.selected)
        check(x + 2, y + 75, light ? palette.accent : 0xF0F0F4)
        check(x + 162, y + 75, 0xFFFFFF) // Horizontal gap is outside the hit/selection rectangle.
        check(x + 75, y + 162, 0xFFFFFF) // The final row retains the original bottom inset.
      }
    }
    print("Emoji six-column geometry, UTF-16 font sizing, navigation and native palette rendering passed")
  }
}
