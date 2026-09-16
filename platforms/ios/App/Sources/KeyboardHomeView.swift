import SwiftUI
import UIKit

/// 卡片按下去缩一点。`.plain` 的卡片按下时毫无反应,点没点上全靠下一屏出现与否来判断。
private struct CardPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .opacity(configuration.isPressed ? 0.88 : 1)
      .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

struct SettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var scheme = InputSchemePreference.scheme
  @State private var skin = KeyboardSkinPreference.selected
  @State private var layout = KeyboardLayoutPreference.geometry
  @State private var design = CustomKeyboardSkinStore.current
  private var skinName: String {
    skin == .custom ? (CustomSkinLibrary.designs.first { $0.design == design }?.name ?? "自定义皮肤") : skin.title
  }
  var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 5) {
            Text("让输入，更像你").font(.system(size: 27, weight: .bold))
            Text("从一次顺手的表达开始").font(.subheadline).foregroundStyle(.secondary)
          }.padding(.top, 5)
          keyboardCard
          // 原来这里是三张卡片加一条「键盘设置」,要用的东西都在那一条后面。现在那一页的项目全摊在首页上:六张卡片,少点一次。
          HStack(spacing: 10) {
            NavigationLink(destination: SkinSettingsView()) {
              quickEntry("皮肤", subtitle: skinName, symbol: "paintpalette.fill", color: .pink)
            }.accessibilityIdentifier("skinSettingsLink")
            NavigationLink(destination: InputSettingsView()) {
              quickEntry("输入方案", subtitle: scheme.title, symbol: "keyboard.fill", color: MetasequoiaTheme.accent)
            }.accessibilityIdentifier("inputSettingsLink")
            NavigationLink(destination: KeyboardLayoutSettingsView()) {
              quickEntry("按键", subtitle: "间距与高度", symbol: "slider.horizontal.3", color: .indigo)
            }.accessibilityIdentifier("keyboardLayoutLink")
          }.buttonStyle(CardPressStyle())
          HStack(spacing: 10) {
            NavigationLink(destination: DictionarySettingsView()) {
              quickEntry("词库", subtitle: "个人词与同步", symbol: "books.vertical.fill", color: .brown)
            }.accessibilityIdentifier("dictionarySettingsLink")
            NavigationLink(destination: ServiceSettingsView(kind: .ai)) {
              quickEntry("AI", subtitle: "回复与润色", symbol: "sparkles", color: .orange)
            }.accessibilityIdentifier("aiSettingsLink")
            Button {
              guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
              UIApplication.shared.open(url)
            } label: {
              quickEntry("系统设置", subtitle: "启用与完全访问", symbol: "gearshape.fill", color: .gray)
            }.accessibilityIdentifier("openKeyboardSettingsButton")
          }.buttonStyle(CardPressStyle())
        }.padding(.horizontal, 16).padding(.bottom, 20)
      }.background(MetasequoiaTheme.canvas)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onChange(of: scenePhase) { if $0 == .active { refresh() } }
      .tint(MetasequoiaTheme.accent)
  }
  private var keyboardCard: some View {
    NavigationLink(destination: KeyboardTryoutView(focusOnAppear: true)) {
      VStack(alignment: .leading, spacing: 13) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("我的键盘").font(.headline).foregroundStyle(.primary)
            Text("\(skinName) · \(scheme.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer(minLength: 5)
          Text("当前外观").font(.system(size: 10, weight: .medium)).foregroundStyle(MetasequoiaTheme.accent)
            .padding(.horizontal, 9).padding(.vertical, 5).background(MetasequoiaTheme.forest.opacity(0.08), in: Capsule())
        }
        Group {
          if scheme == .thoughtfulReply { replyPreview }
          else if scheme == .handwriting {
            KeyboardPreviewCanvas {
              VStack(spacing: 12) {
                Text("手写输入").font(.headline)
                Image(systemName: "hand.draw").font(.system(size: 48)).foregroundStyle(MetasequoiaTheme.forest)
                Text("在键盘上书写，停笔后选择候选文字").font(.subheadline)
                Text("撤销一笔 · 清空 · 选字上屏").font(.caption).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, maxHeight: .infinity).background(MetasequoiaTheme.canvas)
            }
          }
          else { KeyboardSkinPreview(skin: skin, nineKey: scheme == .nineKey, layout: layout).id(design) }
        }.clipShape(RoundedRectangle(cornerRadius: 13)).allowsHitTesting(false).accessibilityHidden(true)
        HStack(spacing: 7) {
          Image(systemName: "keyboard")
          Text("试用键盘").fontWeight(.semibold)
          Spacer()
          Image(systemName: "arrow.right")
        }.font(.subheadline).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 44)
          .background(MetasequoiaTheme.forest, in: RoundedRectangle(cornerRadius: 12))
      }.padding(14).background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }.buttonStyle(.plain).accessibilityIdentifier("keyboardTryoutLink")
  }
  private var replyPreview: some View {
    KeyboardPreviewCanvas {
    VStack(spacing: 5) {
      Text("帮你回 · 帮润色").font(.caption.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).padding(6)
      ForEach([["专属回复", "暖心关怀", "捧场王"], ["恋人", "幽默风趣", "成熟稳重"], ["土味情话", "高情商", "委婉拒绝"]], id: \.self) { row in
        HStack(spacing: 5) {
          ForEach(row, id: \.self) { text in
            Text(text).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(maxHeight: .infinity)
              .background(Color(uiColor: skin.keyBackground), in: RoundedRectangle(cornerRadius: 7))
          }
        }
      }
    }.padding(8).foregroundStyle(Color(uiColor: skin.keyForeground)).background(Color(uiColor: skin.background))
    }
  }
  private func quickEntry(_ title: String, subtitle: String, symbol: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      // 图标坐在自己颜色的方块里。六张卡片原来是同一个 accent 色的线条图标,一眼扫过去六个都一样,只能逐张读标题。
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 34, height: 34)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
      Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
      Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
      .background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 17))
  }
  private func refresh() {
    scheme = InputSchemePreference.scheme; skin = KeyboardSkinPreference.selected
    design = CustomKeyboardSkinStore.current
    layout = KeyboardLayoutPreference.geometry
  }
}
