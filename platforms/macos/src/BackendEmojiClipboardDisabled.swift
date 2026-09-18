import SwiftUI

struct MacEmojiClipboardDisabledView: View {
  let palette: MacEmojiPalette
  let enabling: Bool
  let enable: () -> Void
  var body: some View {
    VStack(spacing: 0) {
      Text("开启剪贴板后").font(.system(size: 16))
        .foregroundStyle(MacEmojiPalette.color(palette.muted))
      Text("复制过的内容将在这里展示").font(.system(size: 16))
        .foregroundStyle(MacEmojiPalette.color(palette.muted))
        .padding(.top, 16 * 2 / 3)
      Button("开启剪贴板", action: enable)
        .font(.system(size: 22 * 2 / 3, weight: .semibold))
        .foregroundStyle(Color.white)
        .frame(width: 248 * 2 / 3, height: 56 * 2 / 3)
        .background(MacEmojiPalette.color(palette.accent))
        .clipShape(RoundedRectangle(cornerRadius: 12 * 2 / 3))
        .disabled(enabling).padding(.top, 36 * 2 / 3)
    }.frame(maxWidth: .infinity).padding(.top, 32)
  }
}
