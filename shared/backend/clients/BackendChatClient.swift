import Foundation

extension BackendAccountClient {
  struct ChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
  }
  struct ChatModels: Decodable, Sendable {
    struct Model: Decodable, Identifiable, Sendable { let id: String }
    let data: [Model]
    let default_model: String
  }
  func chatModels(token: String) async throws -> ChatModels {
    let catalog: ChatModels = try await json("GET", "/v1/models", token: token)
    guard !catalog.data.isEmpty, catalog.data.count <= 33,
          catalog.data.contains(where: { $0.id == catalog.default_model }),
          catalog.data.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 200 }),
          Set(catalog.data.map(\.id)).count == catalog.data.count else { throw Failure(status: 0) }
    return catalog
  }
  func chat(messages: [ChatMessage], model: String, token: String) async throws -> String {
    struct Body: Encodable { let messages: [ChatMessage]; let model: String; let max_tokens = 2048; let stream = false }
    struct Response: Decodable {
      struct Choice: Decodable { let message: ChatMessage }
      let choices: [Choice]
    }
    guard !model.isEmpty, (1...16).contains(messages.count),
          messages.allSatisfy({ ["user", "assistant", "system"].contains($0.role) && !$0.content.isEmpty && $0.content.utf8.count <= 16384 })
    else { throw Failure(status: 400) }
    let body = try JSONEncoder().encode(Body(messages: messages, model: model))
    guard body.count <= 65536 else { throw Failure(status: 400) }
    let response: Response = try await json("POST", "/v1/chat/completions", token: token, body: body, timeout: 125)
    guard let reply = response.choices.first?.message, reply.role == "assistant",
          !reply.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          reply.content.utf8.count <= 16384 else { throw Failure(status: 502) }
    return reply.content
  }
}

extension BackendAccountClient {
  /// Translate one visible candidate page in order. The backend owns the provider and credentials;
  /// the keyboard only receives bounded display strings and never sends the user's raw keystrokes.
  func translate(texts: [String], target: String, token: String) async throws -> [String] {
    struct Body: Encodable { let texts: [String]; let source_lang = "ZH"; let target_lang: String }
    struct Response: Decodable { let code: Int; let data: [String] }
    guard (1...32).contains(texts.count), !target.isEmpty, target.utf8.count <= 16,
          texts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 2048 }) else {
      throw Failure(status: 400)
    }
    let body = try JSONEncoder().encode(Body(texts: texts, target_lang: target))
    let response: Response = try await json("POST", "/v1/translate", token: token,
      body: body, timeout: 30)
    guard response.code == 200, response.data.count == texts.count,
          response.data.allSatisfy({ $0.utf8.count <= 4096 && !$0.unicodeScalars.contains(where: { $0.value == 0x0A || $0.value == 0x0D || ($0.value < 0x20 && $0.value != 0x09) }) })
    else { throw Failure(status: 502) }
    return response.data
  }
}
