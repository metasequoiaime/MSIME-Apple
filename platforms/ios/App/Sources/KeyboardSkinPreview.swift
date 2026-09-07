import SwiftUI

// A display-only keyboard: no Engine session, document access, or input side effects.
struct KeyboardSkinPreview: View {
  let skin: KeyboardSkin
  let nineKey: Bool
  @Environment(\.colorScheme) private var colorScheme

  private func color(_ value: UIColor) -> Color {
    Color(uiColor: value.resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)))
  }

  var body: some View {
    VStack(spacing: 7) {
      HStack(spacing: 10) {
        Text("ni hao").font(.caption).foregroundStyle(color(skin.accent))
        Text("你好").font(.subheadline.weight(.medium))
        Text("你号").font(.subheadline)
        Spacer(minLength: 0)
        Text(nineKey ? "九键" : "全拼").font(.caption)
        Text("中").font(.caption.weight(.semibold)).padding(6)
          .foregroundStyle(color(skin.actionForeground)).background(color(skin.actionBackground), in: RoundedRectangle(cornerRadius: 6))
      }.padding(.horizontal, 6).frame(height: 32)
        .background(color(skin.keyBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
      if nineKey {
        HStack(spacing: 6) {
          VStack(spacing: 5) {
            ForEach(["，", "。", "？", "！"], id: \.self) { value in key(value) }
          }.frame(width: 38)
          VStack(spacing: 7) {
            row(["分词", "ABC", "DEF"])
            row(["GHI", "JKL", "MNO"])
            row(["PQRS", "TUV", "WXYZ"])
          }
          VStack(spacing: 7) {
            key("⌫")
            key("重输")
            key("0")
          }.frame(width: 38)
        }.frame(height: 137)
      } else {
        VStack(spacing: 7) {
          row(Array("qwertyuiop").map(String.init))
          row(Array("asdfghjkl").map(String.init))
          row(Array("zxcvbnm").map(String.init))
        }.frame(height: 137)
      }
      HStack(spacing: 6) {
        if nineKey { key("符").frame(width: 38) }
        key("123").frame(width: 38)
        Image(systemName: "globe").frame(width: 34, height: 40)
          .background(color(skin.keyBackground), in: RoundedRectangle(cornerRadius: 7))
        if !nineKey { key("⌫").frame(width: 38) }
        key("空格")
        key("换行", emphasized: true).frame(width: 52)
      }.frame(height: 40)
    }
    .foregroundStyle(color(skin.keyForeground))
    .padding(7).background(color(skin.background), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(skin.title)，\(nineKey ? "9 键" : "26 键")完整键盘预览")
    .accessibilityIdentifier("fullKeyboardSkinPreview")
  }

  private func row(_ titles: [String]) -> some View {
    HStack(spacing: 5) {
      ForEach(titles, id: \.self) { key($0) }
    }
  }

  private func key(_ title: String, emphasized: Bool = false) -> some View {
    Text(title).font(.system(size: nineKey ? 13 : 15, weight: .medium))
      .lineLimit(1).minimumScaleFactor(0.7)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .foregroundStyle(color(emphasized ? skin.actionForeground : skin.keyForeground))
      .background(color(emphasized ? skin.actionBackground : skin.keyBackground), in: RoundedRectangle(cornerRadius: 7))
  }
}
