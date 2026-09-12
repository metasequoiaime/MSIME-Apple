import AppKit
import SwiftUI

@main enum EmojiSymbolSectionsTest {
  static func items(_ group: String, _ count: Int) -> [MacEmojiCatalogItem] {
    (0..<count).map { .init(text: "fixture-\(group)-\($0)", annotation: "synthetic", group: group) }
  }
  @MainActor static func main() {
    let source = items("first", 7) + items("second", 2) + items("first", 1)
    let sections = MacEmojiSymbolSections.split(source)
    assert(sections.map(\.title) == ["first", "second", "first"])
    assert(sections.map(\.start) == [0, 7, 9])
    assert(Set(sections.map(\.id)).count == 3)
    assert(AnyHashable(sections[0].id) != AnyHashable(0)) // Section anchors must not collide with item scroll IDs.
    assert(sections.map { $0.items.count } == [7, 2, 1])
    assert(sections.flatMap(\.items) == source)
    assert(MacEmojiSymbolSections.split([]).isEmpty)
    assert(MacEmojiSymbolSections.height(sections[0]) == 156)
    for section in sections {
      for index in section.items.indices { assert(source[section.start + index] == section.items[index]) }
    }
    let searched = source.filter { $0.group == "second" }
    assert(MacEmojiSymbolSections.split(searched).map(\.start) == [0])
    assert(MacEmojiSymbolSections.split(Array(source.dropFirst(6))).map(\.start) == [0, 1, 3])
    // Windows non-flow arrows retain flat-index strides even across partial section rows.
    assert(MacEmojiGridCommand.down.destination(from: 1, count: source.count, columns: 6) == 7)
    assert(MacEmojiGridCommand.up.destination(from: 7, count: source.count, columns: 6) == 1)
    _ = NSApplication.shared
    for light in [false, true] {
      let palette = MacEmojiPalette(light: light)
      let renderer = ImageRenderer(content: MacEmojiSymbolSectionsView(items: Array(source.prefix(9)),
        palette: palette, selectedIndex: 7, copy: { _ in }).background(Color.white))
      renderer.scale = 3
      guard let image = renderer.cgImage else { fatalError("Symbol section rendering unavailable") }
      assert(image.width == 1008 && image.height == 768, "Unexpected section size \(image.width)x\(image.height)")
      var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
      pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      }
      let pixel = (594 * image.width + 30) * 4
      for channel in 0..<3 {
        let expected = Int((palette.selected >> ((2 - channel) * 8)) & 255)
        assert(abs(Int(pixels[pixel + channel]) - expected) <= 2)
      }
    }
    print("Symbol sections order, repeated titles, global indices, navigation and native rendering passed")
  }
}
