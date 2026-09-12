import AppKit
import SwiftUI

@main enum EmojiClipboardPreviewTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let original = "synthetic\r\nline\tvalue\n\n"
    assert(MacClipboardPreview.line(original) == "synthetic  line value  ")
    assert(MacClipboardPreview.tooltip(original) == "synthetic \nline value")
    assert(MacClipboardPreview.tooltip("\n\n").isEmpty)
    assert(MacClipboardPreview.tooltip(String(repeating: "a", count: 200)).count == 200)
    assert(MacClipboardPreview.tooltip(String(repeating: "a", count: 201)) == String(repeating: "a", count: 200) + "...")
    assert(MacClipboardPreview.tooltip(String(repeating: "a", count: 199) + "😀") == String(repeating: "a", count: 199) + "...")
    assert(MacClipboardPreview.tooltip(String(repeating: "😀", count: 101)) == String(repeating: "😀", count: 100) + "...")
    assert(original == "synthetic\r\nline\tvalue\n\n")
    for light in [false, true] {
      let palette = MacEmojiPalette(light: light)
      for selected in [false, true] {
        let row = MacEmojiClipboardRow(text: original, palette: palette, selected: selected,
          deleting: false, copy: {}, remove: {}).frame(width: 300)
        let renderer = ImageRenderer(content: row)
        renderer.scale = 3
        guard let image = renderer.cgImage else { fatalError("Clipboard row render unavailable") }
        assert(image.width == 900 && image.height == 160)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
          let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        func check(x: Int, y: Int, color: UInt32) {
          let index = (y * image.width + x) * 4
          for channel in 0..<3 {
            let expected = Int((color >> ((2 - channel) * 8)) & 255)
            assert(abs(Int(pixels[index + channel]) - expected) <= 2)
          }
        }
        check(x: 450, y: 15, color: selected ? palette.selected : palette.searchBackground)
        if selected { check(x: 1, y: 80, color: light ? palette.accent : 0xF0F0F4) }
        assert(pixels[3] == 0)
      }
    }
    print("Clipboard preview text, UTF-16 boundaries, row size and palette pixel tests passed")
  }
}
