import SwiftUI

struct MacEmojiSearchChrome: View {
  static let scale: CGFloat = 2 / 3
  static let height: CGFloat = 52 * scale
  static let radius: CGFloat = 10 * scale
  let palette: MacEmojiPalette
  let focused: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: Self.radius)
      .fill(MacEmojiPalette.color(palette.searchBackground))
      .overlay {
        RoundedRectangle(cornerRadius: Self.radius)
          .strokeBorder(MacEmojiPalette.color(focused ? palette.accent : palette.searchBorder)
            .opacity(focused ? palette.searchFocusOpacity : 1),
            lineWidth: (focused ? 2 : 1) * Self.scale)
      }
  }
}

struct MacEmojiSearchField: View {
  @Binding var text: String
  let placeholder: String
  let palette: MacEmojiPalette
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 0) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 16))
        .foregroundStyle(MacEmojiPalette.color(palette.muted))
        .frame(width: 40 * MacEmojiSearchChrome.scale)
        .accessibilityHidden(true)
      TextField("搜索", text: $text, prompt: Text(placeholder)
        .font(.system(size: 12)).foregroundColor(MacEmojiPalette.color(palette.muted)))
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(MacEmojiPalette.color(palette.text))
        .focused($focused)
        .accessibilityLabel(placeholder)
    }
    .padding(.leading, 6 * MacEmojiSearchChrome.scale)
    .padding(.trailing, 12 * MacEmojiSearchChrome.scale)
    .frame(height: MacEmojiSearchChrome.height)
    .background(MacEmojiSearchChrome(palette: palette, focused: focused))
  }
}
