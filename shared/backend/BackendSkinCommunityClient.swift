import Foundation

extension BackendAccountClient {
  struct CommunitySkin: Codable, Identifiable, Sendable {
    let id: UUID
    let name, description, author: String
    let design: CustomKeyboardSkin
    let downloads, rating_count: Int
    let rating_average: Double
    let owned: Bool
    let my_rating: Int
  }
  struct SkinPage: Decodable, Sendable { let skins: [CommunitySkin]; let has_more: Bool }
  func communitySkins(search: String = "", offset: Int = 0, token: String) async throws -> SkinPage {
    guard search.count <= 128, (0...100_000).contains(offset) else { throw Failure(status: 400) }
    var parts = URLComponents(); parts.path = "/v1/community/skins"
    parts.queryItems = [.init(name: "q", value: search), .init(name: "offset", value: String(offset))]
    parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    guard let path = parts.string else { throw Failure(status: 400) }
    let page: SkinPage = try await json("GET", path, token: token, maximumResponseBytes: 24 * 1024 * 1024)
    guard page.skins.count <= 20, !page.has_more || !page.skins.isEmpty,
          Set(page.skins.map(\.id)).count == page.skins.count else { throw Failure(status: 502) }
    return page
  }
  func communitySkin(_ id: UUID, token: String) async throws -> CommunitySkin {
    let skin: CommunitySkin = try await json("GET", "/v1/community/skins/\(id.uuidString.lowercased())", token: token)
    guard skin.id == id else { throw Failure(status: 502) }
    return skin
  }
  func downloadCommunitySkin(_ id: UUID, token: String) async throws -> CustomKeyboardSkin {
    struct Response: Decodable { let design: CustomKeyboardSkin }
    let result: Response = try await json("POST", "/v1/community/skins/\(id.uuidString.lowercased())/download", token: token, body: Data("{}".utf8))
    return result.design.normalized
  }
  func rateCommunitySkin(_ id: UUID, stars: Int, token: String) async throws {
    guard (1...5).contains(stars) else { throw Failure(status: 400) }
    _ = try await request("PUT", "/v1/community/skins/\(id.uuidString.lowercased())/rating", token: token,
      body: JSONSerialization.data(withJSONObject: ["stars": stars]))
  }
  struct SkinPublication: Encodable, Equatable, Sendable {
    let id: UUID
    let name, description: String
    let design: CustomKeyboardSkin
    var valid: Bool {
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.unicodeScalars.count <= 32 &&
      description.unicodeScalars.count <= 280 && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
  }
  func publishCommunitySkin(_ publication: SkinPublication, token: String) async throws -> UUID {
    guard publication.valid else { throw Failure(status: 400) }
    let data = try JSONEncoder().encode(publication)
    guard data.count <= 710000 else { throw Failure(status: 400) }
    struct Response: Decodable { let id: UUID }
    let response: Response = try await json("POST", "/v1/community/skins", token: token, body: data)
    guard response.id == publication.id else { throw Failure(status: 502) }
    return response.id
  }
  func unpublishCommunitySkin(_ id: UUID, token: String) async throws {
    _ = try await request("DELETE", "/v1/community/skins/\(id.uuidString.lowercased())", token: token)
  }
}
