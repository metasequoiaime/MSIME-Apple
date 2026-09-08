import SwiftUI

struct SettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var scheme = InputSchemePreference.scheme
  @State private var skin = KeyboardSkinPreference.selected
  @State private var layout = KeyboardLayoutPreference.selected
  @State private var design = CustomKeyboardSkinStore.current
  @State private var replyActive = false
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
          HStack(spacing: 10) {
            NavigationLink(destination: SkinSettingsView()) {
              quickEntry("皮肤", subtitle: skinName, symbol: "paintpalette", color: MetasequoiaTheme.accent)
            }.accessibilityIdentifier("skinSettingsLink")
            NavigationLink(destination: InputSettingsView()) {
              quickEntry("输入方案", subtitle: scheme.title, symbol: "keyboard", color: MetasequoiaTheme.accent)
            }.accessibilityIdentifier("inputSettingsLink")
            NavigationLink(destination: KeyboardLayoutSettingsView()) {
              quickEntry("布局", subtitle: layout.title, symbol: "rectangle.3.group", color: MetasequoiaTheme.accent)
            }.accessibilityIdentifier("keyboardLayoutLink")
          }.buttonStyle(.plain)
          Button {
            if !InputSchemePreference.enabledSchemes.contains(.thoughtfulReply) {
              InputSchemePreference.enabledSchemes = InputSchemePreference.enabledSchemes + [.thoughtfulReply]
            }
            InputSchemePreference.scheme = .thoughtfulReply
            refresh(); replyActive = true
          } label: {
            HStack(spacing: 13) {
              Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 25)).foregroundStyle(MetasequoiaTheme.accent)
                .frame(width: 50, height: 50).background(MetasequoiaTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
              VStack(alignment: .leading, spacing: 5) {
                Text("高情商回复").font(.headline).foregroundStyle(.primary)
                Text("切换回复键盘，试试更合适的表达").font(.caption).foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)).foregroundStyle(MetasequoiaTheme.accent)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
              .background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 20))
          }.buttonStyle(.plain).accessibilityIdentifier("homeThoughtfulReply")
          NavigationLink(destination: KeyboardSettingsView()) {
            HStack(spacing: 12) {
              Image(systemName: "slider.horizontal.3").font(.system(size: 20)).foregroundStyle(MetasequoiaTheme.accent)
              VStack(alignment: .leading, spacing: 4) {
                Text("键盘设置").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text("输入偏好、词库、AI 与语音").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(16).background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 18))
          }.buttonStyle(.plain).accessibilityIdentifier("keyboardSettingsLink")
          NavigationLink(destination: KeyboardTryoutView(focusOnAppear: true), isActive: $replyActive) { EmptyView() }
            .hidden().accessibilityHidden(true)
        }.padding(.horizontal, 16).padding(.bottom, 20)
      }.background(MetasequoiaTheme.canvas)
        .navigationTitle("水杉输入法").navigationBarTitleDisplayMode(.inline)
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
      Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(color)
      Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
      Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
      .background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 17))
  }
  private func refresh() {
    scheme = InputSchemePreference.scheme; skin = KeyboardSkinPreference.selected
    layout = KeyboardLayoutPreference.selected; design = CustomKeyboardSkinStore.current
  }
}
