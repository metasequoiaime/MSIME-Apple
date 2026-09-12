import SwiftUI

// Each tab owns its stack. Cross-tab discovery always opens the community root.
final class AppNavigation: ObservableObject {
  enum Tab: Hashable { case keyboard, community, statistics, account }
  @Published var tab: Tab = .keyboard
  @Published var communityCategory = 0
  @Published var communityRoot = UUID()
  /// Presented as a sheet rather than pushed: the keyboard can deep link here from any tab and any
  /// depth, and rebuilding the two-level push stack would depend on where the user already was.
  @Published var presentsVoiceRecording = false

  /// Handles the keyboard's deep link. Unknown hosts just open the app.
  func open(_ url: URL) {
    guard url.scheme == VoiceTextHandoffStore.recordingURL.scheme,
          url.host == VoiceTextHandoffStore.recordingURL.host else { return }
    presentsVoiceRecording = true
  }

  func discoverSkins() {
    communityRoot = UUID()
    communityCategory = 0
    tab = .community
  }
}

// Authentication is a task sheet, never another copy of the My tab.
struct AccountLoginSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var signedIn = false
  var body: some View {
    NavigationView {
      Form { AppleAccountSection(signedIn: $signedIn) }
        .navigationTitle("登录水杉").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        }
        .onChange(of: signedIn) { if $0 { dismiss() } }
    }.navigationViewStyle(.stack).tint(MetasequoiaTheme.accent)
  }
}
