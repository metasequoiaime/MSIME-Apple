import SwiftUI

enum MacClipboardPreview {
  static let scale: CGFloat = 2.0 / 3.0
  static let height: CGFloat = 80 * scale
  static let gap: CGFloat = 8 * scale

  static func line(_ text: String) -> String {
    text.replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
  }

  static func tooltip(_ text: String) -> String {
    var tip = text.replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
    while tip.last == "\n" { tip.removeLast() }
    guard tip.utf16.count > 200 else { return tip }
    var units = Array(tip.utf16.prefix(200))
    // Windows truncates wchar_t units; do not emit a broken surrogate on macOS.
    if let last = units.last, (0xD800...0xDBFF).contains(last) { units.removeLast() }
    return String(decoding: units, as: UTF16.self) + "..."
  }
}

struct MacClipboardRowStyle: ButtonStyle {
  let palette: MacEmojiPalette
  let selected: Bool
  let hovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(MacEmojiPalette.color(configuration.isPressed ? palette.pressed : selected || hovered ? palette.selected : palette.searchBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12 * MacClipboardPreview.scale))
      .overlay {
        if selected {
          RoundedRectangle(cornerRadius: 12 * MacClipboardPreview.scale)
            .strokeBorder(MacEmojiPalette.color(palette.background == 0xF7F7FA ? palette.accent : 0xF0F0F4), lineWidth: 2 * MacClipboardPreview.scale)
        }
      }
  }
}

struct MacEmojiClipboardRow: View {
  let text: String
  let palette: MacEmojiPalette
  let selected: Bool
  let deleting: Bool
  let copy: () -> Void
  let remove: () -> Void
  @State private var hovered = false
  @State private var deleteHovered = false
  @FocusState private var deleteFocused: Bool

  var body: some View {
    Button(action: copy) {
      Text(MacClipboardPreview.line(text))
        .font(.system(size: 22 * MacClipboardPreview.scale))
        .lineLimit(1).truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16 * MacClipboardPreview.scale)
        .padding(.trailing, 42 * MacClipboardPreview.scale)
        .frame(height: MacClipboardPreview.height)
        .contentShape(Rectangle())
    }
    .buttonStyle(MacClipboardRowStyle(palette: palette, selected: selected, hovered: hovered))
    .accessibilityLabel(text)
    .anchorPreference(key: MacClipboardTooltipPreference.self, value: .bounds) {
      hovered && !deleteHovered ? [MacClipboardTooltipAnchor(text: text, bounds: $0)] : []
    }
    .overlay(alignment: .trailing) {
      Button(action: remove) { Image(systemName: "xmark").frame(width: 32 * MacClipboardPreview.scale, height: 32 * MacClipboardPreview.scale) }
        .buttonStyle(.plain)
        .foregroundStyle(MacEmojiPalette.color(palette.muted))
        .accessibilityLabel("删除此条历史记录")
        .help("删除此条历史记录，不会清空系统剪贴板")
        .disabled(deleting)
        .onHover { deleteHovered = $0 }
        .focused($deleteFocused)
        .opacity(hovered || deleteFocused ? 1 : 0)
        .padding(.trailing, 10 * MacClipboardPreview.scale)
    }
    .onHover { hovered = $0 }
  }
}
