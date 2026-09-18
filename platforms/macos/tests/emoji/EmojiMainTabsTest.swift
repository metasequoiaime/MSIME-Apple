import AppKit
import SwiftUI

@main enum EmojiMainTabsTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let pages = MacEmojiMainPage.allCases
    assert(pages.map { MacEmojiTabIcons.codepoint($0) } == [0xF6B8, 0xE76E, 0xF4AA, 0xF4A9, 0xED59, 0xF6BA, 0xE77F])
    assert(pages.map { MacEmojiTabIcons.resolve($0, supports: { _, _ in false }).text } == ["最近", "表情", "贴纸", "GIF", "颜文字", "符号", "剪贴板"])
    for page in pages {
      let primary = MacEmojiTabIcons.resolve(page, supports: { _, _ in true })
      assert(primary.family == "Segoe Fluent Icons" && primary.text.utf16.first == MacEmojiTabIcons.codepoint(page))
      let secondary = MacEmojiTabIcons.resolve(page, supports: { family, _ in family == "Segoe MDL2 Assets" })
      assert(secondary.family == "Segoe MDL2 Assets")
      assert(MacEmojiTabIcons.resolve(page, supports: { _, _ in false }).family == nil)
    }
    assert(!MacEmojiTabIcons.supports("SyntheticMissingIconFont", 0xF6B8))
    assert(MacEmojiTabIcons.supports("Helvetica", 0x0041))
    let width = pages.reduce(CGFloat(0)) { $0 + MacEmojiTabIcons.width($1) } + CGFloat(pages.count - 1) * MacEmojiTabIcons.gap
    assert(abs(width - 312) < 0.001)
    for light in [false, true] {
      let palette = MacEmojiPalette(light: light)
      for selected in pages {
        let renderer = ImageRenderer(content: MacEmojiMainTabs(selected: selected, palette: palette, navigate: { _ in },
          resolve: { MacEmojiTabIcons.resolve($0, supports: { _, _ in false }) }).background(Color.white))
        renderer.scale = 3
        guard let image = renderer.cgImage else { fatalError("Main tabs rendering unavailable") }
        assert(image.width == 936 && image.height == 116, "Unexpected main-tab dimensions: \(image.width)x\(image.height)")
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
          let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var x: CGFloat = 0
        for page in pages {
          let center = x + MacEmojiTabIcons.width(page) / 2
          let pixel = (114 * image.width + Int((center * 3).rounded())) * 4
          let color: UInt32 = page == selected ? palette.accent : 0xFFFFFF
          for channel in 0..<3 {
            let expected = Int((color >> ((2 - channel) * 8)) & 255)
            assert(abs(Int(pixels[pixel + channel]) - expected) <= 2)
          }
          x += MacEmojiTabIcons.width(page) + MacEmojiTabIcons.gap
        }
      }
    }
    print("Main tab order, glyph resolution, fallback, dimensions and selection rendering passed")
  }
}
