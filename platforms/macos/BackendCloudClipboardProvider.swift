import Foundation

protocol DesktopCloudClipboardAPI {
  func clipboard(token: String, search: String) async throws -> BackendAccountClient.ClipboardPage
  func addClipboard(_ text: String, token: String) async throws -> BackendAccountClient.ClipboardItem
  func deleteClipboard(id: String?, token: String) async throws
  func setClipboardEnabled(_ enabled: Bool, token: String) async throws
}
extension BackendAccountClient: DesktopCloudClipboardAPI {}

/// A panel can perform clipboard operations for one native account only. Tokens
/// stay inside the existing account actor; no credential is returned over IPC.
@MainActor @objc(MSIMEBackendCloudClipboardProvider)
final class BackendCloudClipboardProvider: NSObject {
  private let client: any DesktopCloudClipboardAPI
  private let credentials: () async throws -> String
  init(client: any DesktopCloudClipboardAPI, credentials: @escaping () async throws -> String) {
    self.client = client; self.credentials = credentials
  }

  @objc static func prepare(completion: @escaping (BackendCloudClipboardProvider?) -> Void) {
    Task {
      do {
        guard let user = try await BackendAccountSession.shared.user() else { completion(nil); return }
        completion(BackendCloudClipboardProvider(client: BackendAccountClient(), credentials: {
          try await BackendAccountSession.shared.credentials(matchingUserID: user.id).token
        }))
      } catch { completion(nil) }
    }
  }

  private enum Action {
    case list(String), add(String), delete(String), enabled(Bool)
    init(_ value: NSDictionary) throws {
      switch value["operation"] as? String {
      case "list":
        let search = value["search"] as? String ?? ""
        guard search.utf8.count <= 1024, !search.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw BackendAccountClient.Failure(status: 400) }
        self = .list(search)
      case "add":
        guard let text = value["text"] as? String, !text.isEmpty, text.utf16.count <= 4000,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && ![10, 13, 9].contains($0.value) }) else { throw BackendAccountClient.Failure(status: 400) }
        self = .add(text)
      case "delete":
        guard let id = value["id"] as? String, id.utf8.count == 64,
              id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw BackendAccountClient.Failure(status: 400) }
        self = .delete(id)
      case "set_enabled":
        guard let number = value["enabled"] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { throw BackendAccountClient.Failure(status: 400) }
        self = .enabled(number.boolValue)
      default: throw BackendAccountClient.Failure(status: 400)
      }
    }
  }

  private func item(_ value: BackendAccountClient.ClipboardItem) throws -> [String: Any] {
    guard !value.id.isEmpty, value.id.utf8.count <= 256, !value.text.isEmpty,
          value.text.utf16.count <= 4000, !value.text.contains("\0"), value.updated_at.utf8.count <= 128 else { throw BackendAccountClient.Failure(status: 0) }
    return ["id":value.id, "text":value.text, "updated_at":value.updated_at]
  }

  func execute(_ request: NSDictionary) async throws -> [String: Any] {
    let action = try Action(request)
    let token = try await credentials()
    try Task.checkCancellation()
    let result: [String: Any]
    switch action {
    case .list(let search):
      let page = try await client.clipboard(token: token, search: search)
      guard page.items.count <= 50 else { throw BackendAccountClient.Failure(status: 0) }
      result = ["enabled":page.enabled, "items":try page.items.map(item)]
    case .add(let text): result = try item(await client.addClipboard(text, token: token))
    case .delete(let id): try await client.deleteClipboard(id: id, token: token); result = [:]
    case .enabled(let enabled): try await client.setClipboardEnabled(enabled, token: token); result = ["enabled":enabled]
    }
    // An account switch/logout while I/O was pending cannot expose old data.
    _ = try await credentials()
    try Task.checkCancellation()
    return result
  }

  @objc func request(_ request: NSDictionary, completion: @escaping (NSDictionary) -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let task = Task {
      do { completion(["ok":true, "value":try await execute(request)]) }
      catch { completion(["ok":false, "error":"unavailable"]) }
      progress.completedUnitCount = 1
      progress.cancellationHandler = nil
    }
    progress.cancellationHandler = { task.cancel() }
    return progress
  }
}
