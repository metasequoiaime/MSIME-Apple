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
      if ProcessInfo.processInfo.arguments.contains("-keyboardAIPreview") {
        KeyboardAIView(text: "这是一段待润色的测试文字。只有点击发送才会请求服务。",
          configuration: CustomServiceConfiguration(endpoint: "https://fixture.invalid/v1/chat/completions", model: "fixture"),
          canSend: { false }, insert: { _ in false }, close: {})
          .frame(width: 320, height: 260)
      } else if ProcessInfo.processInfo.arguments.contains("-keyboardVoicePreview") {
        KeyboardVoicePreviewFixture().frame(width: 320, height: 260)
      } else { applicationContent }
      #else
      applicationContent
      #endif
    }
  }

  @ViewBuilder private var applicationContent: some View {
      if hasCompletedOnboarding {
        SettingsView()
      } else {
        OnboardingView(onFinish: { hasCompletedOnboarding = true })
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
