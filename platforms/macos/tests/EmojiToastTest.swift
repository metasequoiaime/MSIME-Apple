import AppKit
import SwiftUI

@main enum EmojiToastTest {
  @MainActor static func main() async {
    assert(MacEmojiToastState.preview("synthetic\r\nline") == "syntheticline")
    assert(MacEmojiToastState.preview(String(repeating: "a", count: 24)).count == 24)
    assert(MacEmojiToastState.preview(String(repeating: "a", count: 25)) == String(repeating: "a", count: 24) + "...")
    assert(MacEmojiToastState.preview(String(repeating: "a", count: 23) + "😀") == String(repeating: "a", count: 23) + "...")
    assert(MacEmojiToastState.preview(String(repeating: "😀", count: 13)) == String(repeating: "😀", count: 12) + "...")
    var state = MacEmojiToastState()
    assert(state.message == nil)
    state.copied("synthetic-first", success: true)
    let old = state.generation
    state.copied("synthetic-second", success: true)
    state.dismiss(ifGeneration: old)
    assert(state.message == "已复制  synthetic-second")
    state.dismiss()
    assert(state.message == nil)
    state.copied("synthetic-sensitive-fixture", success: false)
    assert(state.message == "无法访问剪贴板")
    await MacEmojiToastState.expire(generation: state.generation, sleep: { duration in
      assert(duration == 1_600_000_000)
    }, dismiss: { state.dismiss(ifGeneration: $0) })
    assert(state.message == nil)
    var expired = false
    state.show("剪贴板已开启")
    let enabled = state.generation
    state.show("无法开启剪贴板")
    state.dismiss(ifGeneration: enabled)
    assert(state.message == "无法开启剪贴板")
    state.dismiss()
    let cancelled = Task { @MainActor in
      await MacEmojiToastState.expire(generation: 0, sleep: { _ in }, dismiss: { _ in expired = true })
    }
    cancelled.cancel()
    await cancelled.value
    assert(!expired)
    _ = NSApplication.shared
    let viewport = CGSize(width: 392, height: 500)
    assert(MacEmojiToastGeometry.rect(message: "fixture", viewport: .zero) == nil)
    let minimum = MacEmojiToastGeometry.rect(message: "", viewport: viewport)!
    assert(minimum.width == 64)
    let bounded = MacEmojiToastGeometry.rect(message: String(repeating: "fixture", count: 100), viewport: viewport)!
    assert(abs(bounded.width - (392 - 40 * 2.0 / 3)) < 0.001)
    assert(abs(bounded.midX - 196) < 0.001 && abs(bounded.maxY - (500 - 28 * 2.0 / 3)) < 0.001)
    for light in [false, true] {
      let message = "synthetic toast"
      let rect = MacEmojiToastGeometry.rect(message: message, viewport: viewport)!
      let renderer = ImageRenderer(content: MacEmojiToastOverlay(message: message, light: light)
        .frame(width: viewport.width, height: viewport.height).background(Color.white))
      renderer.scale = 3
      guard let image = renderer.cgImage else { fatalError("Toast rendering unavailable") }
      assert(image.width == 1176 && image.height == 1500)
      var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
      pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      }
      let index = (Int((rect.minY + 5) * 3) * image.width + Int(rect.midX * 3)) * 4
      let color: UInt32 = light ? 0x2B2B33 : 0x3A3A44
      let alpha = light ? 0.94 : 0.96
      for channel in 0..<3 {
        let component = Double((color >> ((2 - channel) * 8)) & 255)
        let expected = Int((component * alpha + 255 * (1 - alpha)).rounded())
        assert(abs(Int(pixels[index + channel]) - expected) <= 2)
      }
    }
    print("Emoji toast preview, replacement, expiry, cancellation, geometry and rendering passed")
  }
}
