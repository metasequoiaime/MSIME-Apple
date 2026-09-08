import SwiftUI

struct WelcomeFlowView: View {
  var onFinish: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var page = 0
  @State private var scheme = InputSchemePreference.scheme
  private let titles = ["欢迎使用水杉", "启用键盘", "选择输入方式", "让表达更轻松"]

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("\(page + 1) / 4").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        Spacer()
        Button("稍后设置") { finish() }.accessibilityIdentifier("skipOnboardingButton")
      }.padding(.horizontal, 24).padding(.vertical, 12)
      if page == 1 {
        OnboardingView()
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            if page == 0 { welcome }
            else if page == 2 { inputChoices }
            else { intelligence }
          }
          .frame(maxWidth: 560, alignment: .leading)
          .padding(24).frame(maxWidth: .infinity)
        }
      }
      VStack(spacing: 14) {
        HStack(spacing: 8) {
          ForEach(0..<4) { index in
            Capsule().fill(index == page ? MetasequoiaTheme.forest : Color.secondary.opacity(0.2))
              .frame(width: index == page ? 24 : 8, height: 8)
          }
        }.accessibilityElement(children: .ignore).accessibilityLabel("第 \(page + 1) 步，共 4 步")
        Button { if page == 3 { finish() } else { page += 1 } } label: {
          Text(page == 3 ? "开始使用水杉" : (page == 0 ? "开始设置" : "下一步"))
            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .background(MetasequoiaTheme.forest, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier(page == 3 ? "finishOnboardingButton" : "nextOnboardingButton")
        if page > 0 {
          Button("上一步") { page -= 1 }.accessibilityIdentifier("previousOnboardingButton")
        }
      }.frame(maxWidth: 560).padding(.horizontal, 24).padding(.vertical, 16)
    }
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    .tint(MetasequoiaTheme.forest)
    .navigationTitle(titles[page]).navigationBarTitleDisplayMode(.inline)
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 26) {
      Image("MSIMELogo").resizable().scaledToFit().frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 10) {
        Text("水杉输入法").font(.largeTitle.bold())
        Text("让输入更自然，\n让表达更自在。")
          .font(.title2.weight(.medium)).foregroundStyle(.secondary)
      }
      feature("keyboard", "熟悉的键盘，自由的选择", "全拼、九键、双拼、五笔与日语，按你的习惯开启。")
      feature("paintpalette", "把键盘变成你的风格", "挑选皮肤、设计配色，也可以去社区发现更多作品。")
      feature("bubble.left.and.text.bubble.right", "从打字到更好的表达", "AI 对话、高情商回复和语音服务，按需配置。")
      Label("日常输入无需登录", systemImage: "lock.shield")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private var inputChoices: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("从你熟悉的键盘开始").font(.title.bold())
      Text("先选一种，稍后可以在输入设置中调整全部方案。")
        .foregroundStyle(.secondary)
      ForEach([ChineseInputScheme.quanpin, .nineKey], id: \.self) { choice in
        Button {
          var enabled = InputSchemePreference.enabledSchemes
          if !enabled.contains(choice) { enabled.append(choice) }
          InputSchemePreference.enabledSchemes = enabled
          InputSchemePreference.scheme = choice
          scheme = choice
        } label: {
          HStack(spacing: 14) {
            Image(systemName: choice == .nineKey ? "square.grid.3x3" : "keyboard")
              .font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 5) {
              Text(choice.title).font(.headline)
              Text(choice == .nineKey ? "大按键，单手输入更方便" : "完整字母，熟悉的输入手感")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: scheme == choice ? "checkmark.circle.fill" : "circle")
          }.padding(20).foregroundStyle(.primary)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(scheme == choice ? MetasequoiaTheme.forest : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityIdentifier("welcomeScheme_\(choice.rawValue)")
          .accessibilityValue(scheme == choice ? "已选择" : "未选择")
      }
      NavigationLink(destination: KeyboardLayoutSettingsView()) {
        Label("选择适合你的键盘布局", systemImage: "rectangle.3.group")
      }
      NavigationLink(destination: InputSettingsView()) {
        Label("查看全部输入方案", systemImage: "slider.horizontal.3")
      }
    }.onAppear { scheme = InputSchemePreference.scheme }
  }

  private var intelligence: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("输入之外，多一点灵感").font(.title.bold())
      feature("sparkles", "高情商回复", "复制对方的话，在回复键盘中粘贴并选择回复风格，点选结果插入。")
      feature("bubble.left.and.bubble.right", "边试键盘，边聊 AI", "在试用键盘里登录账号，选择 EveryAPI 模型，开始对话。")
      NavigationLink(destination: ServiceSettingsView(kind: .ai)) {
        Label("配置键盘 AI", systemImage: "slider.horizontal.3")
      }
      NavigationLink(destination: KeyboardTryoutView()) {
        Label("先试试键盘", systemImage: "keyboard")
      }.accessibilityIdentifier("welcomeTryoutLink")
      Text("这些功能可以稍后设置。键盘联网功能需要“允许完全访问”，并由你主动发送内容；日常拼音输入保持离线。")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon).font(.title3).foregroundStyle(MetasequoiaTheme.forest)
        .frame(width: 42, height: 42)
        .background(MetasequoiaTheme.forest.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func finish() {
    if let onFinish { onFinish() } else { dismiss() }
  }
}
