import Foundation

enum AppServicesBridge {
  static func polishBody(_ model: String, prompt: String, text: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "model": model,
      "messages": [["role": "system", "content": prompt], ["role": "user", "content": text]],
      "stream": false
    ])
  }

  static func transcriptionBody(_ wav: Data, model: String) throws -> [String: Any] {
    let boundary = "Boundary-\(UUID().uuidString)"
    var body = Data()
    func append(_ text: String) { body.append(contentsOf: text.utf8) }
    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n")
    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
    body.append(wav)
    append("\r\n--\(boundary)--\r\n")
    return ["body": body, "contentType": "multipart/form-data; boundary=\(boundary)"]
  }

  static func parseResponse(_ data: Data, voice: Bool) throws -> String {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ServiceFailure(message: "服务返回格式无效。")
    }
    if voice, let text = object["text"] as? String { return text }
    if let choices = object["choices"] as? [[String: Any]],
       let message = choices.first?["message"] as? [String: Any],
       let content = message["content"] as? String { return content }
    throw ServiceFailure(message: object["error"] as? String ?? "服务未返回可用文字。")
  }
}
