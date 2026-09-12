import AppKit
import SwiftUI

struct MacClipboardTooltipAnchor {
  let text: String
  let bounds: Anchor<CGRect>
}

struct MacClipboardTooltipPreference: PreferenceKey {
  static let defaultValue: [MacClipboardTooltipAnchor] = []
  static func reduce(value: inout [MacClipboardTooltipAnchor], nextValue: () -> [MacClipboardTooltipAnchor]) {
    value.append(contentsOf: nextValue())
  }
}

enum MacClipboardTooltipLayout {
  static let fontSize: CGFloat = 13
  static let maxTextHeight: CGFloat = 13 * 1.35 * 12

  static func frame(text: String, anchor: CGRect, panel: CGRect, contentTop: CGFloat) -> CGRect? {
    let top = panel.minY + contentTop
    let viewport = CGRect(x: panel.minX, y: top, width: panel.width, height: max(0, panel.maxY - top))
    guard !text.isEmpty, viewport.intersects(anchor), panel.width >= 80,
          viewport.height >= fontSize + 28 else { return nil }
    let maxWidth = panel.width - 24
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let metrics = (text as NSString).boundingRect(
      with: NSSize(width: maxWidth - 28, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: NSFont.systemFont(ofSize: fontSize), .paragraphStyle: paragraph])
    let width = min(maxWidth, max(72, ceil(metrics.width) + 28))
    let height = min(viewport.height - 8, min(maxTextHeight + 20, max(fontSize + 20, ceil(metrics.height) + 20)))
    let x = min(max(anchor.midX - width / 2, panel.minX + 12), panel.maxX - width - 12)
    var y = anchor.minY - height - 8
    if y < top { y = anchor.maxY + 8 }
    if y + height > panel.maxY - 8 { y = max(top, panel.maxY - height - 8) }
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

struct MacClipboardTooltipBubble: View {
  let text: String
  let light: Bool
  var body: some View {
    Text(text)
      .font(.system(size: MacClipboardTooltipLayout.fontSize))
      .lineLimit(12).truncationMode(.tail)
      .foregroundStyle(MacEmojiPalette.color(0xF5F5F7))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipped()
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(MacEmojiPalette.color(light ? 0x2B2B33 : 0x1C1C22).opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

struct MacClipboardTooltipOverlay: View {
  let anchors: [MacClipboardTooltipAnchor]
  let light: Bool
  var body: some View {
    GeometryReader { geometry in
      if let item = anchors.last {
        let text = MacClipboardPreview.tooltip(item.text)
        if let frame = MacClipboardTooltipLayout.frame(text: text, anchor: geometry[item.bounds],
          panel: CGRect(origin: .zero, size: geometry.size), contentTop: 28) {
          MacClipboardTooltipBubble(text: text, light: light)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
      }
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}
