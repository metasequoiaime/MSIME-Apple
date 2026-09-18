import Foundation

private typealias PersonalDictionaryByte = UInt8
@_silgen_name("msime_client_dictionary_validate")
private func msimeClientDictionaryValidate(_ request: UnsafePointer<PersonalDictionaryByte>?,
                                            _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_string_free")
private func msimeClientPersonalDictionaryStringFree(_ value: UnsafeMutablePointer<CChar>?)

enum PersonalDictionaryBridge {
  static func validateEntry(_ entry: [String: Any]) throws -> [String: Any] {
    // The native side answers with one internal reason for every rejection, so the guidance has to
    // come from here -- this is the layer that still knows which kind of code the user was typing.
    let kind = (entry["kind"] as? String).flatMap(PersonalWordKind.init(rawValue:))
    var request = entry
    if request["kind"] as? String == "quickPhrase" { request["kind"] = "quick_phrase" }
    guard JSONSerialization.isValidJSONObject(request),
          let data = try? JSONSerialization.data(withJSONObject: request) else {
      throw PersonalDictionaryBridgeFailure.invalid(kind)
    }
    let pointer = data.withUnsafeBytes { bytes in
      msimeClientDictionaryValidate(bytes.bindMemory(to: PersonalDictionaryByte.self).baseAddress,
                                    UInt(data.count))
    }
    guard let pointer else { throw PersonalDictionaryBridgeFailure.invalid(kind) }
    let text = String(cString: pointer)
    msimeClientPersonalDictionaryStringFree(pointer)
    guard let response = text.data(using: .utf8),
          let envelope = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
          envelope["ok"] as? Bool == true,
          let value = envelope["value"] as? [String: Any] else {
      throw PersonalDictionaryBridgeFailure.invalid(kind)
    }
    return value
  }
}

private enum PersonalDictionaryBridgeFailure: LocalizedError {
  case invalid(PersonalWordKind?)

  /// Says what to type instead. "格式无效" alone leaves the user to guess which of the code, the
  /// word or the separators the engine objected to.
  var errorDescription: String? {
    switch self {
    case .invalid(.pinyin): "请填写完整拼音，用空格或英文单引号分隔音节，例如 ni hao。"
    case .invalid(.wubi): "五笔编码使用 1–4 个字母。"
    case .invalid(.quickPhrase): "快捷短语编码只能使用字母或数字。"
    case .invalid(.english): "英文编码需与词条字母一致。"
    case .invalid(nil): "个人词条格式无效。"
    }
  }
}
