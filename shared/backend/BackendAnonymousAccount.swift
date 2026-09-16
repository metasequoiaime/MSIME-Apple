import Foundation
import Security

/// Lazily creates an anonymous backend account for keyboard-only services such as candidate glosses.
enum BackendAnonymousAccount {
  struct Credentials: Codable, Sendable { let subject: String; let secret: String }
  private static let fileName = "anonymous-account.json"
  private static func generated() -> Credentials {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    func random(_ count: Int) -> String {
      var bytes = [UInt8](repeating: 0, count: count)
      _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
      return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
    return Credentials(subject: "msime-" + random(16), secret: random(48))
  }
  static func stored() -> Credentials? {
    guard let data = BackendLocalStore.read(fileName) else { return nil }
    return try? JSONDecoder().decode(Credentials.self, from: data)
  }
  static func sessionStorage() -> any BackendSessionStorage {
    BackendLocalStore(fileName: "anonymous-session.json")
  }
  static func ensureSignedIn(session: BackendAccountSession,
                             client: BackendAccountClient) async throws -> Credentials {
    let credentials = stored() ?? generated()
    let challenge = try await client.challenge(provider: "anonymous", target: credentials.subject)
    try await session.signIn(challenge: challenge.challenge_id, credential: credentials.secret)
    if stored() == nil { _ = BackendLocalStore.write(try JSONEncoder().encode(credentials), to: fileName) }
    return credentials
  }
}
