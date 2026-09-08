import Foundation

extension PersonalWord {
  var bridgeValue: [String: Any] {
    ["kind": kind.rawValue, "key": key, "value": value, "weight": weight]
  }
  init(bridgeValue: [String: Any]) throws {
    guard let raw = bridgeValue["kind"] as? String, let kind = PersonalWordKind(rawValue: raw),
          let key = bridgeValue["key"] as? String, let value = bridgeValue["value"] as? String,
          let weight = bridgeValue["weight"] as? NSNumber else { throw PersonalDictionaryStore.StoreError.invalidState }
    self.init(kind: kind, key: key, value: value, weight: weight.int64Value)
  }
  func validated() throws -> Self {
    try Self(bridgeValue: PersonalDictionaryBridge.validateEntry(bridgeValue))
  }
}
