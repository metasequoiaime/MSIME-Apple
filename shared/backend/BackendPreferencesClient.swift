import Foundation

enum BackendPreferenceValue: Codable, Equatable, Sendable {
  case boolean(Bool), integer(Int64), number(Double), string(String)
  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let bool = try? value.decode(Bool.self) { self = .boolean(bool) }
    else if let integer = try? value.decode(Int64.self) { self = .integer(integer) }
    else if let number = try? value.decode(Double.self) { self = .number(number) }
    else { self = .string(try value.decode(String.self)) }
  }
  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .boolean(let v): try value.encode(v)
    case .integer(let v): try value.encode(v)
    case .number(let v): try value.encode(v)
    case .string(let v): try value.encode(v)
    }
  }
  var kind: String {
    switch self { case .boolean: return "boolean"; case .integer: return "integer"; case .number: return "number"; case .string: return "string" }
  }
}
extension BackendAccountClient {
  struct Preferences: Codable, Sendable {
    let revision: Int64
    let settings: [String: BackendPreferenceValue]
  }
  struct PreferenceSchema: Decodable, Sendable {
    struct Field: Decodable, Sendable { let type: String }
    let fields: [String: Field]
    let maximum_bytes: Int
    let update_mode: String
    let revision_required: Bool
  }
  func preferences(token: String) async throws -> Preferences {
    try await json("GET", "/v1/users/me/preferences", token: token)
  }
  func preferenceSchema(token: String) async throws -> PreferenceSchema {
    try await json("GET", "/v1/users/me/preferences/schema", token: token)
  }
  static func mergedPreferences(_ base: Preferences, replacing values: [String: BackendPreferenceValue], schema: PreferenceSchema) throws -> Preferences {
    guard base.revision >= 0, schema.update_mode == "replace", schema.revision_required else { throw Failure(status: 0) }
    for (key, value) in values {
      guard let field = schema.fields[key], field.type == value.kind || (field.type == "number" && value.kind == "integer") else { throw Failure(status: 503) }
    }
    // Preserve every other platform's fields. A revision conflict is returned to
    // the user, never resolved by an automatic last-writer-wins retry.
    let merged = Preferences(revision: base.revision, settings: base.settings.merging(values) { _, new in new })
    guard try JSONEncoder().encode(merged).count <= min(schema.maximum_bytes, 1024 * 1024) else { throw Failure(status: 400) }
    return merged
  }
  func putPreferences(_ preferences: Preferences, token: String) async throws -> Preferences {
    try await json("PUT", "/v1/users/me/preferences", token: token, body: JSONEncoder().encode(preferences))
  }
}

