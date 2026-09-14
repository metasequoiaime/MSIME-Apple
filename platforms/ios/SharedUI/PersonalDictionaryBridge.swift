import Foundation

private typealias PersonalDictionaryByte = UInt8
@_silgen_name("msime_client_dictionary_validate")
private func msimeClientDictionaryValidate(_ request: UnsafePointer<PersonalDictionaryByte>?,
                                            _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_string_free")
private func msimeClientPersonalDictionaryStringFree(_ value: UnsafeMutablePointer<CChar>?)

enum PersonalDictionaryBridge {
  static func validateEntry(_ entry: [String: Any]) throws -> [String: Any] {
    var request = entry
    if request["kind"] as? String == "quickPhrase" { request["kind"] = "quick_phrase" }
    guard JSONSerialization.isValidJSONObject(request),
          let data = try? JSONSerialization.data(withJSONObject: request) else {
      throw PersonalDictionaryBridgeFailure.invalid
    }
    let pointer = data.withUnsafeBytes { bytes in
      msimeClientDictionaryValidate(bytes.bindMemory(to: PersonalDictionaryByte.self).baseAddress,
                                    UInt(data.count))
    }
    guard let pointer else { throw PersonalDictionaryBridgeFailure.invalid }
    let text = String(cString: pointer)
    msimeClientPersonalDictionaryStringFree(pointer)
    guard let response = text.data(using: .utf8),
          let envelope = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
          envelope["ok"] as? Bool == true,
          let value = envelope["value"] as? [String: Any] else {
      throw PersonalDictionaryBridgeFailure.invalid
    }
    return value
  }
}

private enum PersonalDictionaryBridgeFailure: LocalizedError {
  case invalid
  var errorDescription: String? { "个人词条格式无效。" }
}
