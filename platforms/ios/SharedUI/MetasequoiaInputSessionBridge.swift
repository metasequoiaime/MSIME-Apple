import Foundation

private typealias MSIMEByte = UInt8

@_silgen_name("msime_client_create")
private func msimeClientCreate(_ options: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_destroy")
private func msimeClientDestroy(_ session: UInt64) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_string_free")
private func msimeClientStringFree(_ value: UnsafeMutablePointer<CChar>?)
@_silgen_name("msime_client_character")
private func msimeClientCharacter(_ session: UInt64, _ value: MSIMEByte, _ shift: Bool) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_punctuation")
private func msimeClientPunctuation(_ session: UInt64, _ value: MSIMEByte) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_command")
private func msimeClientCommand(_ session: UInt64, _ command: UInt32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_select")
private func msimeClientSelect(_ session: UInt64, _ generation: UInt64, _ index: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_pin_candidate")
private func msimeClientPinCandidate(_ session: UInt64, _ generation: UInt64, _ index: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_remove_candidate")
private func msimeClientRemoveCandidate(_ session: UInt64, _ generation: UInt64, _ index: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_fix_candidate_position")
private func msimeClientFixCandidatePosition(_ session: UInt64, _ generation: UInt64, _ index: UInt, _ position: UInt8) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_clear_candidate_position")
private func msimeClientClearCandidatePosition(_ session: UInt64, _ generation: UInt64, _ index: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_choose_nine_key_spelling")
private func msimeClientChooseNineKeySpelling(_ session: UInt64, _ generation: UInt64, _ index: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_set_nine_key_mode")
private func msimeClientSetNineKeyMode(_ session: UInt64, _ enabled: Bool) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_update_preferences")
private func msimeClientUpdatePreferences(_ session: UInt64, _ snapshot: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_view")
private func msimeClientView(_ session: UInt64) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_dictionary")
private func msimeClientDictionary(_ request: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_snapshot_version")
private func msimeClientSnapshotVersion(_ options: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_snapshot_activate")
private func msimeClientSnapshotActivate(_ handle: UInt64, _ expected: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?

enum MetasequoiaCandidateAction: UInt8 {
  case promote, remove, fixFirst, clearPosition
}

enum MetasequoiaFrequencyAdjustmentMode: UInt8 {
  case pin, halve, linear, promote
}

struct MetasequoiaInputSnapshot: Equatable, Sendable {
  let isHandled: Bool
  let commitText: String?
  let preedit: String
  let candidates: [String]
  let candidateCodes: [String]
  let candidateGlosses: [String]
  let diagnosticText: String?

  init(isHandled: Bool = false, commitText: String? = nil, preedit: String = "",
       candidates: [String] = [], candidateCodes: [String] = [], candidateGlosses: [String] = [],
       diagnosticText: String? = nil) {
    self.isHandled = isHandled
    self.commitText = commitText
    self.preedit = preedit
    self.candidates = candidates
    self.candidateCodes = candidateCodes
    self.candidateGlosses = candidateGlosses
    self.diagnosticText = diagnosticText
  }
}

private enum InputBridgeFailure: LocalizedError {
  case response(String)
  case invalidResponse
  case unavailable

  var errorDescription: String? {
    switch self {
    case .response(let message): return message
    case .invalidResponse: return "输入运行时返回了无效响应。"
    case .unavailable: return "输入运行时尚未准备完成。"
    }
  }
}

/// Swift keyboard host for the shared Rust/C ABI. The extension owns one session
/// and never keeps Engine pointers or input text outside the returned snapshot.
final class MetasequoiaInputSessionBridge: @unchecked Sendable {
  private var handle: UInt64 = 0
  private var options: [String: Any]
  private var revision: UInt64 = 0
  private var suspended = false
  private var learningBeforeSuspension = true

  init() {
    options = Self.defaultOptions()
    do {
      let response = try Self.callCreate(options)
      handle = try Self.number(response["session"])
    } catch {
      handle = 0
    }
  }

  deinit {
    if handle != 0 { _ = try? Self.decode(msimeClientDestroy(handle)) }
  }

  var isInLocalMode: Bool { (try? localMode())?.isEmpty == false }
  var isInUnicodeMode: Bool { (try? localMode()) == "unicode" }

  func handleCharacter(_ character: String) -> MetasequoiaInputSnapshot {
    dispatch { pointer(for: character, shift: false) }
  }

  func handleCandidateKey(_ character: String) -> MetasequoiaInputSnapshot {
    guard let index = Int(character), (1...9).contains(index) else { return diagnostic("候选编号无效") }
    return selectCandidate(at: UInt(index - 1))
  }

  func handlePunctuation(_ character: String) -> MetasequoiaInputSnapshot {
    guard let byte = Self.ascii(character) else { return diagnostic("标点输入无效") }
    return dispatch { msimeClientPunctuation(handle, byte) }
  }

  func handleBackspace() -> MetasequoiaInputSnapshot { command(0) }
  func commitCandidate() -> MetasequoiaInputSnapshot { command(1) }
  func commitRaw() -> MetasequoiaInputSnapshot { command(2) }
  func cancel() -> MetasequoiaInputSnapshot { command(3) }
  func finishComposition() -> MetasequoiaInputSnapshot { command(9) }

  func selectCandidate(at index: UInt) -> MetasequoiaInputSnapshot {
    guard let rows = try? currentCandidates(), rows.indices.contains(Int(index)),
          let identity = rows[Int(index)]["id"] as? [String: Any],
          let generation = identity["generation"] as? NSNumber,
          let globalIndex = identity["index"] as? NSNumber else { return diagnostic("候选已失效") }
    return dispatch { msimeClientSelect(handle, generation.uint64Value, globalIndex.uintValue) }
  }

  func chooseNineKeySpelling(at index: UInt) -> MetasequoiaInputSnapshot {
    let generation = (try? view()["generation"] as? NSNumber)?.uint64Value ?? 0
    return dispatch { msimeClientChooseNineKeySpelling(handle, generation, index) }
  }

  @discardableResult func setLearningEnabled(_ enabled: Bool) -> Bool {
    updatePreferences { $0["learning"] = enabled }
  }

  @discardableResult func setFuzzyPinyinRules(_ rules: UInt32) -> Bool {
    let names = ["z-zh", "c-ch", "s-sh", "n-l", "f-h", "r-l", "an-ang", "en-eng", "in-ing", "ian-iang", "uan-uang"]
    return updatePreferences { prefs in
      prefs["fuzzy_pinyin"] = ["enabled": rules != 0, "seeded": true,
                                "rules": names.enumerated().compactMap { rules & (1 << $0.offset) == 0 ? nil : $0.element }]
    }
  }

  func setWubiMixedPinyin(_ enabled: Bool) {
    _ = updatePreferences { $0["wubi_mixed_pinyin"] = enabled }
  }

  @discardableResult func setFrequencyAdjustmentMode(_ mode: MetasequoiaFrequencyAdjustmentMode,
                                                      triggerCount: Int, linearStep: Int) -> Bool {
    let names = ["pin", "halve", "linear", "promote"]
    return updatePreferences { $0["frequency"] = ["mode": names[Int(mode.rawValue)],
                                                    "trigger_count": triggerCount,
                                                    "linear_step": linearStep] }
  }

  func `switch`(toShuangpin enabled: Bool) -> MetasequoiaInputSnapshot {
    switchScheme(enabled ? "shuangpin" : "quanpin", profile: nil)
  }
  func `switch`(toShuangpinProfile profile: String) -> MetasequoiaInputSnapshot {
    switchScheme("shuangpin", profile: profile)
  }
  func switchToNineKey() -> MetasequoiaInputSnapshot {
    let result = updatePreferences { $0["scheme"] = "quanpin" } ? dispatch { msimeClientSetNineKeyMode(handle, true) } : diagnostic("九键模式切换失败")
    return result
  }
  func switchToWubi() -> MetasequoiaInputSnapshot { switchScheme("wubi", profile: nil) }
  func switchToJapanese() -> MetasequoiaInputSnapshot { switchScheme("japanese", profile: nil) }

  func editCandidate(at index: UInt, expectedWord: String, action: MetasequoiaCandidateAction) -> MetasequoiaInputSnapshot {
    guard let row = (try? currentCandidates())?[safe: Int(index)],
          row["text"] as? String == expectedWord,
          let identity = row["id"] as? [String: Any],
          let generation = identity["generation"] as? NSNumber,
          let globalIndex = identity["index"] as? NSNumber else {
      return diagnostic("候选已失效")
    }
    let generationValue = generation.uint64Value
    let indexValue = globalIndex.uintValue
    switch action {
    case .promote:
      return dispatch { msimeClientPinCandidate(handle, generationValue, indexValue) }
    case .remove:
      return dispatch { msimeClientRemoveCandidate(handle, generationValue, indexValue) }
    case .fixFirst:
      return dispatch { msimeClientFixCandidatePosition(handle, generationValue, indexValue, 1) }
    case .clearPosition:
      return dispatch { msimeClientClearCandidatePosition(handle, generationValue, indexValue) }
    }
  }

  func openLocalMode(_ trigger: String) -> MetasequoiaInputSnapshot {
    guard let byte = Self.ascii(trigger) else { return diagnostic("本地输入模式无效") }
    return dispatch { pointer(for: String(UnicodeScalar(byte)), shift: true) }
  }

  func nineKeySpellings() -> [String] {
    ((try? view()["nine_key_spellings"] as? [String]) ?? [])
  }

  func shuangpinKeyHints() -> [String: String] {
    guard let profile = try? view()["shuangpin_profile"] as? String,
          ["xiaohe", "ziranma", "shoudao", "microsoft"].contains(profile) else { return [:] }
    return Self.shuangpinHints[profile] ?? [:]
  }

  func suspendDictionarySession() -> Bool {
    guard !suspended else { return true }
    guard !hasComposition else { return false }
    learningBeforeSuspension = (options["preferences"] as? [String: Any])?["learning"] as? Bool ?? true
    guard setLearningEnabled(false) else { return false }
    suspended = true
    return true
  }

  func resumeDictionarySession() throws {
    guard handle != 0 else { throw InputBridgeFailure.unavailable }
    guard suspended else { return }
    guard setLearningEnabled(learningBeforeSuspension) else {
      throw InputBridgeFailure.response("词库会话恢复失败")
    }
    suspended = false
  }

  func localDictionaryStateVersion() throws -> String {
    let result = try Self.callOptions(msimeClientSnapshotVersion, options)
    guard let version = result["version"] as? String else { throw InputBridgeFailure.invalidResponse }
    return version
  }

  func dictionarySnapshotContext() throws -> [String: Any] {
    guard let resources = options["resources"] as? String, let user = options["user_data"] as? String,
          let dictionaries = options["dictionaries"] as? String else { throw InputBridgeFailure.invalidResponse }
    return ["resources": URL(fileURLWithPath: resources), "user": URL(fileURLWithPath: user),
            "contentIdentifier": dictionaries]
  }

  func activateDictionarySnapshot(_ snapshot: MSIMEPreparedDictionarySnapshot,
                                  expectedVersion: String) throws {
    guard handle != 0 else { throw InputBridgeFailure.unavailable }
    let expected = Data(expectedVersion.utf8)
    // Release the shared dictionary lease before asking the host for its
    // exclusive activation lease, then recreate the session against the
    // published generation. If activation fails, restore the old session.
    let oldHandle = handle
    _ = try? Self.decode(msimeClientDestroy(oldHandle))
    handle = 0
    do {
      let response = try expected.withUnsafeBytes { bytes in
        try Self.decode(msimeClientSnapshotActivate(snapshot.handle,
                                                     bytes.bindMemory(to: MSIMEByte.self).baseAddress,
                                                     UInt(expected.count)))
      }
      _ = response
      handle = try Self.number(try Self.callCreate(options)["session"])
      DictionarySnapshotBridge.forget(snapshot.identifier)
      snapshot.markConsumed()
    } catch {
      handle = try Self.number(try Self.callCreate(options)["session"])
      throw error
    }
  }

  func applyPersonalPrevious(_ previous: [String: Any]?, replacement: [String: Any]?, requestID: String) throws {
    var action: [String: Any] = ["operation": "edit", "request_id": requestID]
    action["previous"] = previous ?? NSNull()
    action["replacement"] = replacement ?? NSNull()
    var request = options
    request["action"] = action
    let result = try Self.callOptions(msimeClientDictionary, request)
    guard (result["applied"] as? Bool) == true else { throw InputBridgeFailure.response("个人词条未能应用") }
  }

  func personalEntries(atOffset offset: UInt) throws -> [String: Any] {
    var request = options
    request["action"] = ["operation": "list", "offset": offset, "limit": 100]
    return try Self.callOptions(msimeClientDictionary, request)
  }

  private var hasComposition: Bool { (try? (view()["preedit"] as? String ?? "")).map { !$0.isEmpty } ?? false }

  private func localMode() throws -> String { try view()["local_mode"] as? String ?? "" }

  private func switchScheme(_ scheme: String, profile: String?) -> MetasequoiaInputSnapshot {
    let updated = updatePreferences { prefs in
      prefs["scheme"] = scheme
      if let profile { prefs["shuangpin_profile"] = profile }
    }
    return updated ? dispatch { msimeClientSetNineKeyMode(handle, false) } : diagnostic("输入方案切换失败")
  }

  private func command(_ value: UInt32) -> MetasequoiaInputSnapshot {
    dispatch { msimeClientCommand(handle, value) }
  }

  private func pointer(for character: String, shift: Bool) -> UnsafeMutablePointer<CChar>? {
    guard let byte = Self.ascii(character) else { return nil }
    return msimeClientCharacter(handle, byte, shift)
  }

  private func dispatch(_ operation: () -> UnsafeMutablePointer<CChar>?) -> MetasequoiaInputSnapshot {
    do {
      guard let value = try Self.decode(operation()) as? [String: Any] else { throw InputBridgeFailure.invalidResponse }
      return try Self.snapshot(value)
    }
    catch { return diagnostic(error.localizedDescription) }
  }

  private func diagnostic(_ message: String) -> MetasequoiaInputSnapshot {
    MetasequoiaInputSnapshot(diagnosticText: message)
  }

  private func view() throws -> [String: Any] {
    try Self.callHandle(msimeClientView, handle)
  }

  private func currentCandidates() throws -> [[String: Any]] {
    (try view()["candidates"] as? [[String: Any]]) ?? []
  }

  private static func makeShuangpinHints(initials: [String: String], finals: [String: [String]]) -> [String: String] {
    let keys = Array("QWERTYUIOPASDFGHJKLZXCVBNM;")
    return keys.reduce(into: [:]) { result, key in
      let name = String(key)
      var units = finals[name] ?? []
      if let initial = initials[name] { units.append(initial) }
      guard !units.isEmpty else { return }
      result[name] = units.map { $0.first == "v" ? "ü" + $0.dropFirst() : $0 }.sorted().joined(separator: " / ")
    }
  }

  private static let shuangpinHints: [String: [String: String]] = [
    "xiaohe": makeShuangpinHints(
      initials: ["U": "sh", "I": "ch", "V": "zh"],
      finals: ["Q": ["iu"], "W": ["ei"], "E": ["e"], "R": ["uan"], "T": ["ue", "ve"], "Y": ["un"], "U": ["u"], "I": ["i"], "O": ["uo", "o"], "P": ["ie"], "A": ["a"], "S": ["ong", "iong"], "D": ["ai"], "F": ["en"], "G": ["eng"], "H": ["ang"], "J": ["an"], "K": ["ing"], "L": ["uang", "iang"], "Z": ["ou"], "X": ["ua", "ia"], "C": ["ao"], "V": ["ui", "v"], "B": ["in"], "N": ["iao"], "M": ["ian"]]),
    "ziranma": makeShuangpinHints(
      initials: ["U": "sh", "I": "ch", "V": "zh"],
      finals: ["Q": ["iu"], "W": ["ia", "ua"], "E": ["e"], "R": ["uan"], "T": ["ue", "ve"], "Y": ["ing", "uai"], "U": ["u"], "I": ["i"], "O": ["o", "uo"], "P": ["un"], "A": ["a"], "S": ["iong", "ong"], "D": ["iang", "uang"], "F": ["en"], "G": ["eng"], "H": ["ang"], "J": ["an"], "K": ["ao"], "L": ["ai"], "Z": ["ei"], "X": ["ie"], "C": ["iao"], "V": ["ui", "v"], "B": ["ou"], "N": ["in"], "M": ["ian"]]),
    "shoudao": makeShuangpinHints(
      initials: ["E": "sh", "I": "ch", "V": "zh"],
      finals: ["Q": ["iu"], "W": ["ua"], "E": ["e"], "R": ["ie"], "T": ["uan"], "Y": ["ang"], "U": ["u"], "I": ["i"], "O": ["o", "uo"], "P": ["iao"], "A": ["a"], "S": ["ou"], "D": ["ao"], "F": ["eng"], "G": ["uai", "ing"], "H": ["ong", "iong"], "J": ["an"], "K": ["en", "ia"], "L": ["ai", "ue"], "Z": ["un"], "X": ["iang", "uang"], "C": ["in"], "V": ["v", "ui"], "B": ["ve"], "N": ["ian"], "M": ["ei"]]),
    "microsoft": makeShuangpinHints(
      initials: ["U": "sh", "I": "ch", "V": "zh"],
      finals: ["Q": ["iu"], "W": ["ia", "ua"], "E": ["e"], "R": ["uan"], "T": ["ue"], "V": ["ve", "ui"], "Y": ["uai", "v"], "U": ["u"], "I": ["i"], "O": ["o", "uo"], "P": ["un"], "A": ["a"], "S": ["iong", "ong"], "D": ["iang", "uang"], "F": ["en"], "G": ["eng"], "H": ["ang"], "J": ["an"], "K": ["ao"], "L": ["ai"], ";": ["ing"], "Z": ["ei"], "X": ["ie"], "C": ["iao"], "B": ["ou"], "N": ["in"], "M": ["ian"]])
  ]

  private func updatePreferences(_ mutate: (inout [String: Any]) -> Void) -> Bool {
    guard handle != 0 else { return false }
    let previous = (options["preferences"] as? [String: Any]) ?? [:]
    var prefs = previous
    mutate(&prefs)
    options["preferences"] = prefs
    revision &+= 1
    let snapshot: [String: Any] = ["format_version": 1, "revision": revision, "preferences": prefs]
    do {
      _ = try Self.callUpdate(msimeClientUpdatePreferences, handle, snapshot)
      return true
    } catch {
      options["preferences"] = previous
      revision &-= 1
      return false
    }
  }

  private static func defaultOptions() -> [String: Any] {
    let fm = FileManager.default
    let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.app.msime.ios")
      ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let root = group.appendingPathComponent("MSIME", isDirectory: true)
    let resources = Bundle.main.resourceURL?.appendingPathComponent("resources", isDirectory: true)
      ?? root.appendingPathComponent("resources", isDirectory: true)
    let user = root.appendingPathComponent("user", isDirectory: true)
    let cache = root.appendingPathComponent("cache", isDirectory: true)
    let dictionaries = root.appendingPathComponent("dictionaries", isDirectory: true)
    for path in [resources, user, cache, dictionaries] { try? fm.createDirectory(at: path, withIntermediateDirectories: true) }
    return ["api_version": 1, "resources": resources.path, "user_data": user.path,
            "cache": cache.path, "dictionaries": dictionaries.path,
            "preferences": ["scheme": "quanpin", "candidate_page_size": 9,
                             "learning": true, "chinese_punctuation": true]]
  }

  private static func ascii(_ value: String) -> MSIMEByte? {
    guard value.utf8.count == 1, let byte = value.utf8.first else { return nil }
    return byte
  }

  private static func number(_ value: Any?) throws -> UInt64 {
    guard let number = value as? NSNumber else { throw InputBridgeFailure.invalidResponse }
    return number.uint64Value
  }

  private static func snapshot(_ value: [String: Any]) throws -> MetasequoiaInputSnapshot {
    let view = value["view"] as? [String: Any] ?? [:]
    let rows = view["candidates"] as? [[String: Any]] ?? []
    return MetasequoiaInputSnapshot(isHandled: value["handled"] as? Bool ?? false,
      commitText: value["commit"] as? String, preedit: view["preedit"] as? String ?? "",
      candidates: rows.compactMap { $0["text"] as? String },
      candidateCodes: rows.compactMap { $0["code"] as? String },
      candidateGlosses: rows.map { $0["translation"] as? String ?? "" },
      diagnosticText: value["diagnostic"] as? String)
  }

  private static func decode(_ pointer: UnsafeMutablePointer<CChar>?) throws -> Any {
    guard let pointer else { throw InputBridgeFailure.unavailable }
    let string = String(cString: pointer)
    msimeClientStringFree(pointer)
    guard let data = string.data(using: .utf8),
          let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw InputBridgeFailure.invalidResponse }
    guard envelope["ok"] as? Bool == true else {
      throw InputBridgeFailure.response(envelope["error"] as? String ?? "输入运行时调用失败")
    }
    return envelope["value"] ?? NSNull()
  }

  private static func callCreate(_ options: [String: Any]) throws -> [String: Any] {
    try callOptions(msimeClientCreate, options)
  }

  private static func callOptions(_ function: (UnsafePointer<MSIMEByte>?, UInt) -> UnsafeMutablePointer<CChar>?,
                                  _ object: Any) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try data.withUnsafeBytes { bytes in
      let value = try decode(function(bytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(data.count)))
      guard let dictionary = value as? [String: Any] else { throw InputBridgeFailure.invalidResponse }
      return dictionary
    }
  }

  private static func callHandle(_ function: (UInt64) -> UnsafeMutablePointer<CChar>?,
                                 _ handle: UInt64) throws -> [String: Any] {
    let value = try decode(function(handle))
    guard let dictionary = value as? [String: Any] else { throw InputBridgeFailure.invalidResponse }
    return dictionary
  }

  private static func callUpdate(_ function: (UInt64, UnsafePointer<MSIMEByte>?, UInt) -> UnsafeMutablePointer<CChar>?,
                                 _ handle: UInt64, _ object: Any) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try data.withUnsafeBytes { bytes in
      let value = try decode(function(handle, bytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(data.count)))
      guard let dictionary = value as? [String: Any] else { throw InputBridgeFailure.invalidResponse }
      return dictionary
    }
  }
}

private extension Array {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
