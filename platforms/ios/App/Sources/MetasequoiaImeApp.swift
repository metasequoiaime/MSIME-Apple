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
      if hasCompletedOnboarding {
        SettingsView()
      } else {
        OnboardingView(onFinish: { hasCompletedOnboarding = true })
      }
    }
  }
}
