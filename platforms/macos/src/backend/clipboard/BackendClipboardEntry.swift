import Foundation

@MainActor
enum BackendClipboardEntry {
  static func open(account: BackendAccountSession,
                   present: (String) -> Void, signIn: () -> Void) async {
    do {
      let user = try await account.user()
      try Task.checkCancellation()
      guard let user else { signIn(); return }
      present(user.id)
    } catch is CancellationError {
    } catch {
      signIn()
    }
  }
}
