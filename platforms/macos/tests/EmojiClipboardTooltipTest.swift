import AppKit
import SwiftUI

@main enum EmojiClipboardTooltipTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let panel = CGRect(x: 0, y: 0, width: 420, height: 560)
    let middle = CGRect(x: 20, y: 300, width: 380, height: 53)
    let above = MacClipboardTooltipLayout.frame(text: "synthetic", anchor: middle, panel: panel, contentTop: 28)!
    assert(above.maxY == middle.minY - 8)
    let top = CGRect(x: 20, y: 28, width: 380, height: 53)
    let below = MacClipboardTooltipLayout.frame(text: "synthetic", anchor: top, panel: panel, contentTop: 28)!
    assert(below.minY == top.maxY + 8)
    let long = String(repeating: "synthetic\n", count: 20)
    let smallPanel = CGRect(x: 0, y: 0, width: 160, height: 140)
    for currentPanel in [panel, smallPanel] {
      for x: CGFloat in [-30, 0, 90] {
        let anchor = CGRect(x: x, y: 28, width: 90, height: 53)
        let frame = MacClipboardTooltipLayout.frame(text: long, anchor: anchor, panel: currentPanel, contentTop: 28)!
        assert(frame.minX >= 12 && frame.maxX <= currentPanel.maxX - 12)
        assert(frame.minY >= 28 && frame.maxY <= currentPanel.maxY - 8)
        assert(frame.height <= MacClipboardTooltipLayout.maxTextHeight + 20)
      }
    }
    assert(MacClipboardTooltipLayout.frame(text: "", anchor: middle, panel: panel, contentTop: 28) == nil)
    assert(MacClipboardTooltipLayout.frame(text: "synthetic", anchor: middle.offsetBy(dx: 0, dy: 800), panel: panel, contentTop: 28) == nil)
    assert(MacClipboardTooltipLayout.frame(text: "synthetic", anchor: top, panel: CGRect(x: 0, y: 0, width: 70, height: 40), contentTop: 28) == nil)
    for light in [false, true] {
      let renderer = ImageRenderer(content: MacClipboardTooltipBubble(text: "synthetic", light: light).frame(width: 120, height: 60))
      renderer.scale = 3
      guard let image = renderer.cgImage else { fatalError("Tooltip render unavailable") }
      assert(image.width == 360 && image.height == 180)
      var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
      pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      }
      let rgb: UInt32 = light ? 0x2B2B33 : 0x1C1C22
      let index = (90 * image.width + 20) * 4
      for channel in 0..<3 {
        let expected = Double((rgb >> ((2 - channel) * 8)) & 255) * 0.96
        assert(abs(Double(pixels[index + channel]) - expected) <= 2)
      }
      assert(abs(Double(pixels[index + 3]) - 255 * 0.96) <= 2)
      assert(pixels[3] == 0)
    }
    print("Clipboard tooltip placement, clipping bounds and theme pixel tests passed")
  }
}
