import SwiftUI

@main
struct MetasequoiaImeApp: App {
  @StateObject private var onboardingNavigation = AppNavigation()
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

  init() {
    try? KeyboardSkinTrialStore().restorePending()
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--reset-onboarding-for-ui-tests") {
      UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }
    // Scheme visibility lives in the app group and outlives the app, so a test that hides a scheme
    // would otherwise decide what later tests -- in this bundle and in the keyboard unit tests that
    // share the group -- can select. Restorable on its own so a test can undo the damage it did
    // without also throwing away onboarding state it still needs.
    if arguments.contains("--reset-onboarding-for-ui-tests") || arguments.contains("--reset-input-schemes-for-ui-tests") {
      UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier)?
        .removeObject(forKey: InputSchemePreference.enabledSchemesKey)
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
          .navigationViewStyle(.stack).environmentObject(onboardingNavigation)
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
  @StateObject private var navigation = AppNavigation()
  var body: some View {
    TabView(selection: $navigation.tab) {
      NavigationView { SettingsView() }.navigationViewStyle(.stack)
        .tabItem { Label("键盘", systemImage: "keyboard") }.tag(AppNavigation.Tab.keyboard)
      NavigationView { CommunityHomeView() }.navigationViewStyle(.stack).id(navigation.communityRoot)
        .tabItem { Label("社区", systemImage: "square.grid.2x2.fill") }.tag(AppNavigation.Tab.community)
      NavigationView { TypingStatisticsView() }.navigationViewStyle(.stack)
        .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(AppNavigation.Tab.statistics)
      NavigationView { AccountSettingsView() }.navigationViewStyle(.stack)
        .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(AppNavigation.Tab.account)
    }
    .environmentObject(navigation)
    .tint(MetasequoiaTheme.accent)
    .onOpenURL { navigation.open($0) }
    .sheet(isPresented: $navigation.presentsVoiceRecording) {
      NavigationView {
        ServiceSettingsView(kind: .voice).toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { navigation.presentsVoiceRecording = false }
              .accessibilityIdentifier("closeVoiceRecording")
          }
        }
      }.navigationViewStyle(.stack).tint(MetasequoiaTheme.accent)
    }
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
