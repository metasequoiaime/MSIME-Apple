import Foundation

extension PersonalWordKind {
  /// The name the Engine's dictionary requests use, which spells the quick-phrase kind in snake case.
  var bridgeName: String { self == .quickPhrase ? "quick_phrase" : rawValue }
  init?(bridgeName: String) { self.init(rawValue: bridgeName == "quick_phrase" ? "quickPhrase" : bridgeName) }
}

extension PersonalWord {
  var bridgeValue: [String: Any] {
    ["kind": kind.bridgeName, "key": key, "value": value, "weight": weight]
  }
  init(bridgeValue: [String: Any]) throws {
    guard let raw = bridgeValue["kind"] as? String,
          let kind = PersonalWordKind(bridgeName: raw),
          let key = bridgeValue["key"] as? String, let value = bridgeValue["value"] as? String,
          let weight = bridgeValue["weight"] as? NSNumber else { throw PersonalDictionaryStore.StoreError.invalidState }
    self.init(kind: kind, key: key, value: value, weight: weight.int64Value)
  }
  func validated() throws -> Self {
    try Self(bridgeValue: PersonalDictionaryBridge.validateEntry(bridgeValue))
  }
}
