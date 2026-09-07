import Foundation
import Security

enum CustomServiceKind: String {
  case ai, voice
  var title: String { self == .ai ? "AI 设置" : "语音设置" }
  var example: String {
    self == .ai ? "https://你的服务/v1/chat/completions" : "https://你的服务/v1/audio/transcriptions"
  }
}

// Official endpoint/model documentation, checked 2026-09-07. These presets use the
// providers' Chat Completions compatibility APIs; request codecs remain in Engine.
enum AIProviderPreset: String, CaseIterable {
  case openAI, anthropic, gemini, deepSeek, qwen, kimi, zhipu, siliconFlow, openRouter, custom

  var title: String {
    switch self {
    case .openAI: "OpenAI"
    case .anthropic: "Anthropic · Claude"
    case .gemini: "Google · Gemini"
    case .deepSeek: "DeepSeek"
    case .qwen: "通义千问 · 阿里云百炼"
    case .kimi: "Kimi · 月之暗面"
    case .zhipu: "智谱 · GLM"
    case .siliconFlow: "硅基流动"
    case .openRouter: "OpenRouter"
    case .custom: "自定义"
    }
  }
  var endpoint: String {
    switch self {
    case .openAI: "https://api.openai.com/v1/chat/completions"
    case .anthropic: "https://api.anthropic.com/v1/chat/completions"
    case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    case .deepSeek: "https://api.deepseek.com/chat/completions"
    case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    case .kimi: "https://api.moonshot.cn/v1/chat/completions"
    case .zhipu: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    case .siliconFlow: "https://api.siliconflow.cn/v1/chat/completions"
    case .openRouter: "https://openrouter.ai/api/v1/chat/completions"
    case .custom: ""
    }
  }
  var models: [String] {
    switch self {
    case .openAI: ["gpt-4.1-mini"]
    case .anthropic: ["claude-sonnet-4-6", "claude-opus-5"]
    case .gemini: ["gemini-3.8-flash", "gemini-2.5-flash"]
    case .deepSeek: ["deepseek-v4-flash", "deepseek-v4-pro"]
    case .qwen: ["qwen-plus"]
    case .kimi: ["kimi-k2.6", "kimi-k2.5"]
    case .zhipu: ["glm-4.7", "glm-4.7-flashx"]
    case .siliconFlow: ["Qwen/Qwen3.6-27B"]
    case .openRouter: ["openrouter/auto"]
    case .custom: []
    }
  }
  var documentation: URL? {
    let address: String
    switch self {
    case .openAI: address = "https://developers.openai.com/api/docs/models/gpt-4.1-mini"
    case .anthropic: address = "https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk"
    case .gemini: address = "https://ai.google.dev/gemini-api/docs/openai"
    case .deepSeek: address = "https://api-docs.deepseek.com/"
    case .qwen: address = "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope"
    case .kimi: address = "https://platform.kimi.com/docs/api/chat"
    case .zhipu: address = "https://docs.bigmodel.cn/cn/guide/models/text/glm-4.7"
    case .siliconFlow: address = "https://docs.siliconflow.cn/docs/userguide/capabilities/text-generation"
    case .openRouter: address = "https://openrouter.ai/docs/quickstart"
    case .custom: return nil
    }
    return URL(string: address)
  }
}

struct ServiceFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct CustomServiceConfiguration {
  var provider: AIProviderPreset = .custom
  var endpoint = ""
  var model = ""
  var prompt = "请润色以下文字，保持原意，只返回修改后的文字。"

  static func load(_ kind: CustomServiceKind, defaults: UserDefaults = .standard) -> Self {
    var result = Self()
    if kind == .ai {
      result.provider = AIProviderPreset(rawValue: defaults.string(forKey: "service.ai.provider") ?? "") ?? .custom
    }
    result.endpoint = defaults.string(forKey: "service.\(kind.rawValue).endpoint") ?? ""
    result.model = defaults.string(forKey: "service.\(kind.rawValue).model") ?? ""
    result.prompt = defaults.string(forKey: "service.\(kind.rawValue).prompt") ?? result.prompt
    return result
  }

  static func loadPreset(_ provider: AIProviderPreset, defaults: UserDefaults = .standard) -> Self {
    let prefix = "service.ai.presets.\(provider.rawValue)"
    if defaults.string(forKey: prefix + ".endpoint") == nil,
       provider == .custom, load(.ai, defaults: defaults).provider == .custom {
      return load(.ai, defaults: defaults)
    }
    var result = Self()
    result.provider = provider
    result.endpoint = defaults.string(forKey: prefix + ".endpoint") ?? provider.endpoint
    result.model = defaults.string(forKey: prefix + ".model") ?? provider.models.first ?? ""
    result.prompt = defaults.string(forKey: prefix + ".prompt") ?? result.prompt
    return result
  }

  private func storePreset(in defaults: UserDefaults) {
    let prefix = "service.ai.presets.\(provider.rawValue)"
    defaults.set(endpoint, forKey: prefix + ".endpoint")
    defaults.set(model, forKey: prefix + ".model")
    defaults.set(prompt, forKey: prefix + ".prompt")
  }

  func validatedURL() throws -> URL {
    guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil, url.fragment == nil,
      !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw ServiceFailure(message: "请填写完整的 HTTPS 接口地址和模型名称。") }
    return url
  }

  func save(_ kind: CustomServiceKind, token: String, defaults: UserDefaults = .standard) throws {
    let url = try validatedURL()
    if !token.isEmpty { try ServiceTokenStore.write(token, kind: kind, url: url) }
    if kind == .ai {
      // Retain a previously saved custom endpoint when a user chooses their first preset.
      let previous = Self.load(.ai, defaults: defaults)
      if !previous.endpoint.isEmpty { previous.storePreset(in: defaults) }
      storePreset(in: defaults)
      defaults.set(provider.rawValue, forKey: "service.ai.provider")
    }
    defaults.set(url.absoluteString, forKey: "service.\(kind.rawValue).endpoint")
    defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "service.\(kind.rawValue).model")
    defaults.set(prompt, forKey: "service.\(kind.rawValue).prompt")
  }
}

enum ServiceTokenStore {
  private static func query(_ kind: CustomServiceKind, _ url: URL) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "app.msime.ios.custom-services",
     kSecAttrAccount as String: "\(kind.rawValue)|\(url.scheme ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? 443)"]
  }
  static func read(_ kind: CustomServiceKind, url: URL) throws -> String {
    var query = query(kind, url)
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return "" }
    guard status == errSecSuccess, let data = result as? Data,
      let text = String(data: data, encoding: .utf8)
    else { throw ServiceFailure(message: "无法读取钥匙串，请解锁设备后重试。") }
    return text
  }
  static func write(_ token: String, kind: CustomServiceKind, url: URL) throws {
    let query = query(kind, url)
    var status: OSStatus
    if token.isEmpty {
      status = SecItemDelete(query as CFDictionary)
      if status == errSecItemNotFound { return }
    } else {
      let attributes = [kSecValueData as String: Data(token.utf8)]
      status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        var item = query.merging(attributes) { _, new in new }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        status = SecItemAdd(item as CFDictionary, nil)
      }
    }
    guard status == errSecSuccess else { throw ServiceFailure(message: "无法保存钥匙串，请解锁设备后重试。") }
  }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}

enum CustomServiceClient {
  static func request(kind: CustomServiceKind, configuration: CustomServiceConfiguration,
                      text: String = "", wav: Data? = nil, token: String,
                      sessionConfiguration: URLSessionConfiguration = .ephemeral) async throws -> String {
    let url = try configuration.validatedURL()
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if kind == .voice {
      guard let wav else { throw ServiceFailure(message: "请先录音。") }
      let multipart = try AppServicesBridge.transcriptionBody(wav, model: configuration.model)
      request.httpBody = multipart["body"] as? Data
      request.setValue(multipart["contentType"] as? String, forHTTPHeaderField: "Content-Type")
    } else {
      guard text.count <= 10000 else { throw ServiceFailure(message: "每次最多处理一万字。") }
      request.httpBody = try AppServicesBridge.polishBody(configuration.model, prompt: configuration.prompt, text: text)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let session = URLSession(configuration: sessionConfiguration, delegate: NoRedirects(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw ServiceFailure(message: "服务请求失败（HTTP \(status)），请检查地址、模型和密钥。")
    }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 1024 * 1024 else { throw ServiceFailure(message: "服务响应过大。") }
      data.append(byte)
    }
    try Task.checkCancellation()
    return try AppServicesBridge.parseResponse(data, voice: kind == .voice)
  }
}
