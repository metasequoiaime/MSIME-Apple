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
