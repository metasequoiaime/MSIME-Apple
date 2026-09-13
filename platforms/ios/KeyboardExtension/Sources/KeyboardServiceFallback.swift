import Foundation

enum CustomServiceKind { case ai, voice }

enum AIProviderPreset: String, Codable, Sendable {
  case everyAPI, openAI, anthropic, gemini, deepSeek, qwen, kimi, zhipu, siliconFlow, openRouter, custom
}

struct ServiceFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct CustomServiceConfiguration: Codable, Sendable, Equatable {
  var provider: AIProviderPreset = .custom
  var endpoint = ""
  var model = ""
  var prompt = "请润色以下文字，保持原意，只返回修改后的文字。"

  func validatedURL() throws -> URL {
    guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil, url.fragment == nil,
          !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ServiceFailure(message: "请填写完整的 HTTPS 接口地址和模型名称。")
    }
    return url
  }
}

enum CustomServiceClient {
  static func request(kind: CustomServiceKind, configuration: CustomServiceConfiguration,
                      text: String, token: String) async throws -> String {
    guard kind == .ai else { throw ServiceFailure(message: "键盘扩展不支持此服务类型。") }
    var request = URLRequest(url: try configuration.validatedURL())
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": configuration.model,
      "messages": [["role": "user", "content": configuration.prompt + "\n" + text]],
      "stream": false
    ])
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw ServiceFailure(message: "服务请求失败，请检查键盘 AI 配置。")
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = object["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let content = message["content"] as? String else {
      throw ServiceFailure(message: "服务返回格式无效。")
    }
    return content
  }
}
