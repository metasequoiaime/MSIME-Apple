import Foundation

extension BackendAccountClient {
  struct ClipboardItem: Decodable, Identifiable, Sendable {
    let id: String
    let text: String
    let updated_at: String
  }
  struct ClipboardPage: Decodable, Sendable {
    let enabled: Bool
    let items: [ClipboardItem]
  }
  func clipboard(token: String, search: String = "") async throws -> ClipboardPage {
    var components = URLComponents()
    components.path = "/v1/users/me/clipboard"
    components.queryItems = [URLQueryItem(name: "q", value: search)]
    guard let path = components.string else { throw Failure(status: 0) }
    return try await json("GET", path, token: token)
  }
  func setClipboardEnabled(_ enabled: Bool, token: String) async throws {
    struct Body: Encodable { let enabled: Bool }
    _ = try await request("PUT", "/v1/users/me/clipboard/settings", token: token,
                          body: JSONEncoder().encode(Body(enabled: enabled)))
  }
  func addClipboard(_ text: String, token: String) async throws -> ClipboardItem {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text.utf16.count <= 4000, !text.contains("\0") else { throw Failure(status: 400) }
    struct Body: Encodable { let text: String }
    return try await json("POST", "/v1/users/me/clipboard", token: token,
                          body: JSONEncoder().encode(Body(text: text)))
  }
  func deleteClipboard(id: String? = nil, token: String) async throws {
    if let id {
      guard id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure(status: 400) }
    }
    _ = try await request("DELETE", "/v1/users/me/clipboard" + (id.map { "/" + $0 } ?? ""), token: token)
  }
}
