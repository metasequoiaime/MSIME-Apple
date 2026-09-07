import Foundation
import Security

enum CustomServiceKind: String {
  case ai, voice
  var title: String { self == .ai ? "AI 设置" : "语音设置" }
  var example: String {
    self == .ai ? "https://你的服务/v1/chat/completions" : "https://你的服务/v1/audio/transcriptions"
  }
}

struct ServiceFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct CustomServiceConfiguration {
  var endpoint = ""
  var model = ""
  var prompt = "请润色以下文字，保持原意，只返回修改后的文字。"

  static func load(_ kind: CustomServiceKind) -> Self {
    let defaults = UserDefaults.standard
    var result = Self()
    result.endpoint = defaults.string(forKey: "service.\(kind.rawValue).endpoint") ?? ""
    result.model = defaults.string(forKey: "service.\(kind.rawValue).model") ?? ""
    result.prompt = defaults.string(forKey: "service.\(kind.rawValue).prompt") ?? result.prompt
    return result
  }

  func validatedURL() throws -> URL {
    guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil, url.fragment == nil,
      !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw ServiceFailure(message: "请填写完整的 HTTPS 接口地址和模型名称。") }
    return url
  }

  func save(_ kind: CustomServiceKind, token: String) throws {
    let url = try validatedURL()
    if !token.isEmpty { try ServiceTokenStore.write(token, kind: kind, url: url) }
    let defaults = UserDefaults.standard
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
