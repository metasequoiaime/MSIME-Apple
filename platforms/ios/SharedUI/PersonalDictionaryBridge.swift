import Foundation

enum PersonalDictionaryBridge {
  static func validateEntry(_ entry: [String: Any]) throws -> [String: Any] {
    guard let kind = entry["kind"] as? String,
          ["pinyin", "wubi", "quickPhrase", "quick_phrase", "english"].contains(kind),
          let key = entry["key"] as? String, !key.isEmpty,
          let value = entry["value"] as? String, !value.isEmpty,
          let weight = entry["weight"] as? NSNumber else {
      throw PersonalDictionaryBridgeFailure.invalid
    }
    let normalizedKind = kind == "quickPhrase" || kind == "quick_phrase" ? "quick_phrase" : kind
    let keyValid: Bool
    switch normalizedKind {
    case "pinyin":
      keyValid = key.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || $0 == 39 || $0 == 32 } && key.utf8.count <= 256
    case "wubi":
      keyValid = key.utf8.allSatisfy { $0 >= 97 && $0 <= 122 } && key.utf8.count <= 4
    case "quick_phrase":
      keyValid = key.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) } && key.utf8.count <= 32
    case "english":
      keyValid = key.utf8.allSatisfy { ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) } && key.utf8.count <= 64
    default:
      keyValid = false
    }
    guard keyValid, !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
      throw PersonalDictionaryBridgeFailure.invalid
    }
    if normalizedKind == "quick_phrase" && value.utf16.count > 199 {
      throw PersonalDictionaryBridgeFailure.invalid
    }
    return ["kind": normalizedKind, "key": key, "value": value, "weight": weight.int64Value]
  }
}

private enum PersonalDictionaryBridgeFailure: LocalizedError {
  case invalid
  var errorDescription: String? { "个人词条格式无效。" }
}
