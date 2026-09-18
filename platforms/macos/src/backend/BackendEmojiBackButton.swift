import SwiftUI

struct MacEmojiBackButton: View {
  let palette: MacEmojiPalette
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: "chevron.left")
        .font(.system(size: 16 * 2 / 3, weight: .medium))
        .frame(width: 36 * 2 / 3, height: 36 * 2 / 3)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(MacEmojiPalette.color(palette.text))
    .accessibilityLabel("返回首页")
    .help("返回首页")
  }
}
