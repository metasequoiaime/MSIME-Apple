import AppKit
import SwiftUI

struct MacEmojiToastState {
  static let durationNanoseconds: UInt64 = 1_600_000_000
  private(set) var message: String?
  private(set) var generation: UInt64 = 0

  static func preview(_ text: String) -> String {
    let line = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    let units = Array(line.utf16)
    guard units.count > 24 else { return line }
    var end = 24
    if (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
    return String(decoding: units.prefix(end), as: UTF16.self) + "..."
  }

  mutating func copied(_ text: String, success: Bool) {
    show(success ? "已复制  " + Self.preview(text) : "无法访问剪贴板")
  }

  mutating func show(_ text: String) {
    generation &+= 1
    message = text
  }

  mutating func dismiss(ifGeneration expected: UInt64? = nil) {
    guard expected == nil || expected == generation else { return }
    generation &+= 1
    message = nil
  }

  @MainActor static func expire(generation: UInt64,
    sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
    dismiss: (UInt64) -> Void) async {
    do {
      try await sleep(durationNanoseconds)
      try Task.checkCancellation()
      dismiss(generation)
    } catch { }
  }
}

enum MacEmojiToastGeometry {
  static let scale: CGFloat = 2 / 3
  static let height: CGFloat = 52 * scale
  static let bottom: CGFloat = 28 * scale
  static let fontSize: CGFloat = 20 * scale
  static func rect(message: String, viewport: CGSize) -> CGRect? {
    guard viewport.width.isFinite, viewport.height.isFinite,
          viewport.width > 40 * scale, viewport.height >= height + bottom else { return nil }
    let measured = (message as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]).width
    let width = min(max(measured + 56 * scale, 96 * scale), viewport.width - 40 * scale)
    return CGRect(x: (viewport.width - width) / 2, y: viewport.height - bottom - height, width: width, height: height)
  }
}

struct MacEmojiToastOverlay: View {
  let message: String?
  let light: Bool
  var body: some View {
    GeometryReader { geometry in
      if let message, let rect = MacEmojiToastGeometry.rect(message: message, viewport: geometry.size) {
        Text(message).font(.system(size: MacEmojiToastGeometry.fontSize, weight: .semibold))
          .lineLimit(1).foregroundStyle(MacEmojiPalette.color(0xF5F5F7))
          .frame(width: rect.width, height: rect.height).clipped()
          .background(MacEmojiPalette.color(light ? 0x2B2B33 : 0x3A3A44).opacity(light ? 0.94 : 0.96), in: Capsule())
          .position(x: rect.midX, y: rect.midY)
      }
    }.allowsHitTesting(false)
  }
}
