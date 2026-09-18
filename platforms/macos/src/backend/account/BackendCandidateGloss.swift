import Foundation

// Candidate glosses use the account's bounded translation endpoint. The native input method
// already loads this Swift backend as a private dylib, so the Objective-C++ controller only needs a
// C entry point and a notification carrying display-safe strings back to the main thread.
private enum BackendCandidateGloss {
  static let notification = Notification.Name("MSIMEBackendCandidateTranslationsDidArrive")
  private static let account = BackendAccountSession()
  private static let anonymous = BackendAccountSession(storage: BackendAnonymousAccount.sessionStorage())
  private static let client = BackendAccountClient()

  private static func token() async throws -> String {
    if let value = try? await account.accessToken() { return value }
    if let value = try? await anonymous.accessToken() { return value }
    _ = try await BackendAnonymousAccount.ensureSignedIn(session: anonymous, client: client)
    return try await anonymous.accessToken()
  }

  static func fetch(words: [String], primary: String, secondary: String, generation: UInt64) {
    guard !words.isEmpty, !primary.isEmpty else { return }
    Task {
      guard let token = try? await token() else { return }
      await withTaskGroup(of: Void.self) { group in
        for (code, isSecondary) in [(primary, false), (secondary, true)] where !code.isEmpty {
          group.addTask {
            guard let values = try? await client.translate(texts: words, target: code, token: token) else { return }
            // Duplicate candidate text is valid. Keep the first response and reject empty or
            // unchanged values before crossing the bridge into the input method process.
            let table = Dictionary(zip(words, values).filter { !$0.1.isEmpty && $0.1 != $0.0 },
                                   uniquingKeysWith: { first, _ in first })
            guard !table.isEmpty else { return }
            await MainActor.run {
              NotificationCenter.default.post(name: notification, object: nil, userInfo: [
                "generation": generation,
                isSecondary ? "secondaryTranslations" : "translations": table,
              ])
            }
          }
        }
      }
    }
  }
}

@_cdecl("MSIMEFetchAccountCandidateGlosses")
func msimeFetchAccountCandidateGlosses(_ wordsJSON: UnsafePointer<CChar>, _ primary: UnsafePointer<CChar>,
                                       _ secondary: UnsafePointer<CChar>, _ generation: UInt64) {
  guard let data = String(cString: wordsJSON).data(using: .utf8),
        let words = try? JSONDecoder().decode([String].self, from: data),
        words.count <= 32 else { return }
  BackendCandidateGloss.fetch(words: words, primary: String(cString: primary),
                              secondary: String(cString: secondary), generation: generation)
}
