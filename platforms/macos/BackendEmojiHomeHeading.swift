import SwiftUI

struct MacEmojiHomeChevron: Shape {
  func path(in rect: CGRect) -> Path {
    let arm = min(rect.width, rect.height) * 0.16
    var path = Path()
    path.move(to: CGPoint(x: rect.midX - arm * 0.35, y: rect.midY - arm))
    path.addLine(to: CGPoint(x: rect.midX + arm * 0.55, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.midX - arm * 0.35, y: rect.midY + arm))
    return path
  }
}

struct MacEmojiHomeHeading: View {
  static let height: CGFloat = 32
  static let bottomPadding: CGFloat = 12
  let title: String
  let palette: MacEmojiPalette
  var more: (() -> Void)?

  private var label: some View {
    HStack(spacing: 0) {
      Text(title).font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MacEmojiPalette.color(palette.text)).lineLimit(1)
        .padding(.leading, 4 * 2 / 3)
      Spacer(minLength: 0)
      if more != nil {
        MacEmojiHomeChevron().stroke(MacEmojiPalette.color(palette.muted), lineWidth: 1.44)
          .frame(width: 24, height: 24).padding(.trailing, 8 * 2 / 3)
      }
    }.frame(height: Self.height).contentShape(Rectangle())
  }

  var body: some View {
    if let more {
      Button(action: more) { label }.buttonStyle(MacEmojiHomeHeadingStyle(palette: palette))
        .accessibilityLabel("更多\(title)")
    } else { label }
  }
}

private struct MacEmojiHomeHeadingStyle: ButtonStyle {
  let palette: MacEmojiPalette
  func makeBody(configuration: Configuration) -> some View {
    Highlight(configuration: configuration, palette: palette)
  }
  private struct Highlight: View {
    let configuration: Configuration
    let palette: MacEmojiPalette
    @State private var hovered = false
    var body: some View {
      configuration.label.background(alignment: .trailing) {
        if hovered || configuration.isPressed {
          RoundedRectangle(cornerRadius: 8 * 2 / 3)
            .fill(MacEmojiPalette.color(configuration.isPressed ? palette.pressed :
              (palette.background == 0xF7F7FA ? 0xE9E7ED : 0x303038)))
            .frame(width: 24, height: 24).padding(.trailing, 8 * 2 / 3)
        }
      }.onHover { hovered = $0 }
    }
  }
}
