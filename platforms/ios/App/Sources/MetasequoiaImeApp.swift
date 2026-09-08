import SwiftUI

@main
struct MetasequoiaImeApp: App {
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

  init() {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--reset-onboarding-for-ui-tests") {
      UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }
    #endif
    _hasCompletedOnboarding = AppStorage(wrappedValue: false, "hasCompletedOnboarding")
  }

  var body: some Scene {
    WindowGroup {
      #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("-communityReplyEditorPreview") {
        CommunityResourceEditor(kind: .reply)
      } else if ProcessInfo.processInfo.arguments.contains("-launchScreenPreview") {
        LaunchScreenPreview().ignoresSafeArea()
      } else if ProcessInfo.processInfo.arguments.contains("-keyboardReplyPreview") {
        ReplyKeyboardPreview().frame(width: 390, height: 260)
      } else if ProcessInfo.processInfo.arguments.contains("-keyboardAIPreview") {
        KeyboardAIView(text: previewText,
          configuration: CustomServiceConfiguration(endpoint: "https://fixture.invalid/v1/chat/completions", model: "fixture"),
          canSend: { false }, insert: { _ in false }, close: {})
          .frame(width: 320, height: previewHeight)
          .environment(\.sizeCategory, previewSizeCategory)
      } else if ProcessInfo.processInfo.arguments.contains("-keyboardVoicePreview") {
        KeyboardVoicePreviewFixture().frame(width: 320, height: previewHeight)
          .environment(\.sizeCategory, previewSizeCategory)
      } else { applicationContent }
      #else
      applicationContent
      #endif
    }
  }

  #if DEBUG && targetEnvironment(simulator)
  private var previewHeight: CGFloat {
    ProcessInfo.processInfo.arguments.contains("-keyboardCompactPreview") ? 216 : 260
  }
  private var previewSizeCategory: ContentSizeCategory {
    ProcessInfo.processInfo.arguments.contains("-keyboardLargeType") ? .accessibilityExtraExtraExtraLarge : .large
  }
  private var previewText: String {
    ProcessInfo.processInfo.arguments.contains("-keyboardLongPreview")
      ? String(repeating: "用于检测滚动区的测试段落。", count: 50)
      : "这是一段待润色的测试文字。只有点击发送才会请求服务。"
  }
  #endif

  @ViewBuilder private var applicationContent: some View {
      if hasCompletedOnboarding {
        MainTabView()
      } else {
        NavigationView { WelcomeFlowView(onFinish: { hasCompletedOnboarding = true }) }
          .navigationViewStyle(.stack)
      }
  }
}

#if DEBUG && targetEnvironment(simulator)
private struct KeyboardVoicePreviewFixture: View {
  @State private var entry = try? VoiceTextHandoffStore().read()
  @State private var inserted = ""
  @State private var closed = false
  var body: some View {
    if closed { Text(inserted.isEmpty ? "已关闭" : "插入验证：" + inserted) }
    else {
      KeyboardVoiceView(entry: entry, insert: {
        guard let entry else { throw VoiceTextHandoffStore.Failure.stale }
        inserted = try VoiceTextHandoffStore().consume(entry.id)
      }, close: { closed = true })
    }
  }
}
#endif

private struct MainTabView: View {
  var body: some View {
    TabView {
      SettingsView()
        .tabItem { Label("键盘", systemImage: "keyboard") }
      NavigationView { CommunityHomeView() }
        .navigationViewStyle(.stack)
        .tabItem { Label("社区", systemImage: "square.grid.2x2.fill") }
      NavigationView { TypingStatisticsView() }
        .navigationViewStyle(.stack)
        .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
      NavigationView { AccountSettingsView() }
        .navigationViewStyle(.stack)
        .tabItem { Label("我的", systemImage: "person.crop.circle") }
    }
    .tint(MetasequoiaTheme.forest)
  }
}

#if DEBUG && targetEnvironment(simulator)
private struct LaunchScreenPreview: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> UIViewController {
    UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController()!
  }
  func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif

#if DEBUG && targetEnvironment(simulator)
private struct ReplyKeyboardPreview: View {
  @StateObject private var model = ReplyKeyboardModel()
  var body: some View {
    ReplyKeyboardView(model: model, paste: { model.setText("你睡了吗") }, generate: { style in
      model.generate(style: style, request: { _, _ in "还没呢，正好想和你聊聊。" }, insert: { _ in true })
    }, schemes: {}, skins: {}, dismiss: {})
  }
}
#endif
