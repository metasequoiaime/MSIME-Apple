import Foundation

private typealias MSIMEByte = UInt8

@_silgen_name("msime_client_prepare_host")
private func msimeClientPrepareHost(_ options: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_create")
private func msimeClientCreate(_ options: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_destroy")
private func msimeClientDestroy(_ session: UInt64) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_focus")
private func msimeClientFocus(_ session: UInt64, _ focused: Bool) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_string_free")
private func msimeClientStringFree(_ value: UnsafeMutablePointer<CChar>?)
@_silgen_name("msime_client_character")
private func msimeClientCharacter(_ session: UInt64, _ value: MSIMEByte, _ shift: Bool) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_punctuation")
private func msimeClientPunctuation(_ session: UInt64, _ value: MSIMEByte) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_punctuation_with_context")
private func msimeClientPunctuationWithContext(
  _ session: UInt64, _ value: MSIMEByte, _ preceding: UInt32
) -> UnsafeMutablePointer<CChar>?
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
@_silgen_name("msime_client_load_preferences")
private func msimeClientLoadPreferences(_ directory: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_view")
private func msimeClientView(_ session: UInt64) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_all_candidates")
private func msimeClientAllCandidates(_ session: UInt64) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_candidate_gloss_request")
private func msimeClientCandidateGlossRequest(
  _ request: UnsafePointer<MSIMEByte>?, _ requestLength: UInt,
  _ resources: UnsafePointer<MSIMEByte>?, _ resourcesLength: UInt
) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_emoji_catalog_request")
private func msimeClientEmojiCatalogRequest(
  _ request: UnsafePointer<MSIMEByte>?, _ requestLength: UInt,
  _ resources: UnsafePointer<MSIMEByte>?, _ resourcesLength: UInt
) -> UnsafeMutablePointer<CChar>?
@_silgen_name("msime_client_apply_translations")
private func msimeClientApplyTranslations(
  _ session: UInt64, _ generation: UInt64,
  _ translations: UnsafePointer<MSIMEByte>?, _ translationsLength: UInt
) -> UnsafeMutablePointer<CChar>?
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
  let candidatePageCount: Int
  let answeredByPinyinFallback: Bool
  let diagnosticText: String?

  init(isHandled: Bool = false, commitText: String? = nil, preedit: String = "",
       candidates: [String] = [], candidateCodes: [String] = [], candidateGlosses: [String] = [],
       candidatePageCount: Int = 0, answeredByPinyinFallback: Bool = false,
       diagnosticText: String? = nil) {
    self.isHandled = isHandled
    self.commitText = commitText
    self.preedit = preedit
    self.candidates = candidates
    self.candidateCodes = candidateCodes
    self.candidateGlosses = candidateGlosses
    self.candidatePageCount = candidatePageCount
    self.answeredByPinyinFallback = answeredByPinyinFallback
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
  private var stateRoot: String?
  private var initializationDiagnostic: String?
  private var revision: UInt64 = 0
  private var appliedFuzzyPinyinRules: UInt32?
  private var suspended = false
  // Nine-key lives on the session, not in the preferences the options carry, so a rebuilt session
  // starts back on the 26-key layout unless it is told again.
  private var nineKeyEnabled = false

  init(resources: URL? = nil, stateRoot: URL? = nil) {
    options = [:]
    self.stateRoot = nil
    self.appliedFuzzyPinyinRules = nil
    do {
      let bootstrap = Self.bootstrapOptions(resources: resources, stateRoot: stateRoot)
      if EnglishMixedCandidatesMigration.shouldMigrate(customStateRoot: stateRoot),
         let path = bootstrap["state_root"] as? String {
        EnglishMixedCandidatesMigration.migrateIfNeeded(
          stateRoot: URL(fileURLWithPath: path, isDirectory: true))
      }
      options = try Self.callOptions(msimeClientPrepareHost,
                                     bootstrap)
      self.stateRoot = options["preferences_directory"] as? String
        ?? bootstrap["state_root"] as? String
      var preferences = options["preferences"] as? [String: Any] ?? [:]
      preferences["candidate_page_size"] = 9
      // The shared preference default is English, and iOS has no setting that overrides it: the
      // 中/英 key switches modes instead. Without this the engine answers pinyin with English
      // completions while the keyboard is showing Chinese mode. macOS compensates the same way.
      preferences["default_ime_mode"] = "chinese"
      options["preferences"] = preferences
    } catch {
      initializationDiagnostic = "输入运行时准备失败。"
      return
    }
    do {
      handle = try Self.callCreateFocused(options)
    } catch {
      initializationDiagnostic = "输入运行时创建或激活失败。"
    }
  }

  deinit {
    if handle != 0 { _ = try? Self.decode(msimeClientDestroy(handle)) }
  }

  var isInLocalMode: Bool {
    guard let mode = try? localMode() else { return false }
    return !mode.isEmpty && mode != "none"
  }
  var isInUnicodeMode: Bool { (try? localMode()) == "unicode" }

  /// Reload the canonical PreferencesStore written by the Tauri settings host.
  /// Disk and lock work stays off the keyboard thread; the accepted snapshot is
  /// applied on the session's owning (main) thread before the callback returns.
  func reloadSharedPreferences(completion: @escaping (Bool) -> Void) {
    guard handle != 0, let stateRoot else { completion(false); return }
    let path = Data(stateRoot.utf8)
    DispatchQueue.global(qos: .utility).async { [weak self, path] in
      guard self != nil else { return }
      let snapshot: [String: Any]?
      do {
        snapshot = try path.withUnsafeBytes { bytes in
          try MetasequoiaInputSessionBridge.decode(msimeClientLoadPreferences(
            bytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(path.count))) as? [String: Any]
        }
      } catch {
        snapshot = nil
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, let snapshot,
              let preferences = snapshot["preferences"] as? [String: Any],
              let revision = snapshot["revision"] as? NSNumber else {
          completion(false)
          return
        }
        guard revision.uint64Value >= self.revision else {
          completion(false)
          return
        }
        // Keep the session's engine configuration stable while the keyboard is
        // visible; applyLearningPreferences will update only the fuzzy-pinyin
        // contract below. This avoids changing the selected scheme underneath
        // UIKit while a Tauri settings write is being observed.
        self.options["preferences"] = preferences
        self.revision = max(self.revision, revision.uint64Value)
        completion(true)
      }
    }
  }

  /// The active fuzzy-pinyin bitset from the shared PreferencesStore.
  /// `nil` is reserved for an unavailable/legacy session so the native
  /// compatibility preference can still be used by older hosts.
  var sharedFuzzyPinyinRules: UInt32? {
    guard let preferences = options["preferences"] as? [String: Any],
          let fuzzy = preferences["fuzzy_pinyin"] as? [String: Any],
          let enabled = fuzzy["enabled"] as? Bool,
          let names = fuzzy["rules"] as? [String] else { return nil }
    guard enabled else { return 0 }
    let ruleIDs = ["z-zh", "c-ch", "s-sh", "n-l", "f-h", "r-l",
                   "an-ang", "en-eng", "in-ing", "ian-iang", "uan-uang"]
    let selected = Set(names)
    return ruleIDs.enumerated().reduce(UInt32(0)) { value, entry in
      selected.contains(entry.element) ? value | (1 << entry.offset) : value
    }
  }

  var fuzzyPinyinRulesApplied: UInt32? { appliedFuzzyPinyinRules }

  /// The latest canonical PreferencesStore document, exposed as a read-only
  /// value for native UI settings that still use App Group compatibility keys.
  /// Callers must remain on the session's owning thread when reading it.
  var sharedPreferences: [String: Any]? {
    options["preferences"] as? [String: Any]
  }

  /// Persist touch keyboard geometry in the canonical PreferencesStore snapshot.
  /// Native App Group keys remain a compatibility layer for older hosts, but the
  /// shared snapshot is the source that is reloaded when the extension appears.
  @discardableResult
  func setTouchKeyboardGeometry(keySpacing: Double, rowSpacing: Double,
                                heightAdjustment: Double, voiceEnabled: Bool) -> Bool {
    guard keySpacing.isFinite, rowSpacing.isFinite, heightAdjustment.isFinite else { return false }
    let keySpacingTenths = Int((min(6, max(3, keySpacing)) * 10).rounded())
    let rowSpacingTenths = Int((min(10, max(4, rowSpacing)) * 10).rounded())
    let clampedHeight = Int(min(48, max(-12, heightAdjustment)).rounded())
    return updatePreferences { preferences in
      preferences["touch_key_spacing_tenths"] = keySpacingTenths
      preferences["touch_row_spacing_tenths"] = rowSpacingTenths
      preferences["touch_keyboard_height_adjustment"] = clampedHeight
      preferences["touch_voice_shortcut"] = voiceEnabled
    }
  }

  /// Remove touch geometry overrides so canonical defaults are used again.
  @discardableResult
  func resetTouchKeyboardGeometry() -> Bool {
    updatePreferences { preferences in
      preferences.removeValue(forKey: "touch_key_spacing_tenths")
      preferences.removeValue(forKey: "touch_row_spacing_tenths")
      preferences.removeValue(forKey: "touch_keyboard_height_adjustment")
      preferences.removeValue(forKey: "touch_voice_shortcut")
    }
  }

  /// Persist the selected touch scheme and its presentation mapping in one
  /// canonical snapshot. The App Group preference remains a compatibility
  /// mirror for the legacy SwiftUI settings host.
  @discardableResult
  func setTouchKeyboardScheme(_ scheme: ChineseInputScheme,
                              enabledSchemes: [ChineseInputScheme]) -> Bool {
    let enabled = ChineseInputScheme.allCases.filter { enabledSchemes.contains($0) }
    guard !enabled.isEmpty else { return false }
    let selected = enabled.contains(scheme) ? scheme : enabled[0]
    let engineScheme: String
    switch selected {
    case .wubi: engineScheme = "wubi"
    case .japanese, .japaneseNineKey: engineScheme = "japanese"
    case .shuangpin, .ziranma, .microsoft, .shoudao: engineScheme = "shuangpin"
    case .quanpin, .nineKey, .handwriting, .thoughtfulReply: engineScheme = "quanpin"
    }
    let layout: String
    switch selected {
    case .nineKey, .japaneseNineKey: layout = "nine_key"
    case .handwriting: layout = "handwriting"
    default: layout = "twenty_six_key"
    }
    let selectedID = selected.sharedIdentifier
    return updatePreferences { preferences in
      preferences["scheme"] = engineScheme
      if engineScheme != "japanese" {
        preferences["last_chinese_scheme"] = engineScheme
      }
      if let profile = selected.shuangpinProfile {
        preferences["shuangpin_profile"] = profile
      }
      preferences["touch_keyboard_layout"] = layout
      preferences["touch_keyboard_schemes"] = [
        "enabled": enabled.map(\.sharedIdentifier),
        "selected": selectedID,
      ]
    }
  }

  /// Persist a built-in touch-keyboard skin in the canonical PreferencesStore.
  /// The native App Group value remains a compatibility mirror for old hosts.
  @discardableResult
  func setTouchKeyboardSkin(_ skin: KeyboardSkin) -> Bool {
    updatePreferences { preferences in
      preferences["touch_keyboard_skin"] = skin.rawValue
    }
  }

  /// Persist the touch host's Chinese output mode in the canonical snapshot.
  @discardableResult
  func setTraditionalChineseOutput(_ enabled: Bool) -> Bool {
    updatePreferences { preferences in
      preferences["traditional_chinese_output"] = enabled
    }
  }

  func handleCharacter(_ character: String, shifted: Bool = false) -> MetasequoiaInputSnapshot {
    dispatch { pointer(for: character, shift: shifted) }
  }

  func handleCandidateKey(_ character: String) -> MetasequoiaInputSnapshot {
    guard let index = Int(character), (1...9).contains(index) else { return diagnostic("候选编号无效") }
    return selectCandidate(at: UInt(index - 1))
  }

  func handlePunctuation(_ character: String) -> MetasequoiaInputSnapshot {
    guard let byte = Self.ascii(character) else { return diagnostic("标点输入无效") }
    return dispatch { msimeClientPunctuation(handle, byte) }
  }

  func handlePunctuationWithContext(_ character: String,
                                    preceding: UInt32) -> MetasequoiaInputSnapshot {
    guard let byte = Self.ascii(character) else { return diagnostic("标点输入无效") }
    return dispatch { msimeClientPunctuationWithContext(handle, byte, preceding) }
  }

  func handleBackspace() -> MetasequoiaInputSnapshot { command(0) }
  func commitCandidate() -> MetasequoiaInputSnapshot { command(1) }
  func commitRaw() -> MetasequoiaInputSnapshot { command(2) }
  func cancel() -> MetasequoiaInputSnapshot { command(3) }
  func finishComposition() -> MetasequoiaInputSnapshot { command(9) }
  func cycleKanaVariant() -> MetasequoiaInputSnapshot { command(10) }

  func selectCandidate(at index: UInt) -> MetasequoiaInputSnapshot {
    guard let rows = try? currentCandidates(), rows.indices.contains(Int(index)),
          let identity = rows[Int(index)]["id"] as? [String: Any],
          let generation = identity["generation"] as? NSNumber,
          let globalIndex = identity["index"] as? NSNumber else { return diagnostic("候选已失效") }
    return selectCandidate(
      generation: generation.uint64Value, globalIndex: globalIndex.uint64Value)
  }

  func selectCandidate(generation: UInt64, globalIndex: UInt64) -> MetasequoiaInputSnapshot {
    guard let index = UInt(exactly: globalIndex) else { return diagnostic("候选已失效") }
    return dispatch { msimeClientSelect(handle, generation, index) }
  }

  func allCandidates() throws -> [String: Any] {
    try Self.callHandle(msimeClientAllCandidates, handle)
  }

  func candidateGlossResources() -> String? {
    options["resources"] as? String
  }

  static func candidateGlosses(request: Data, resources: String) throws -> [String: Any] {
    let resourceData = Data(resources.utf8)
    guard NSString(string: resources).isAbsolutePath, resourceData.count <= 4096 else {
      throw InputBridgeFailure.invalidResponse
    }
    return try request.withUnsafeBytes { requestBytes in
      try resourceData.withUnsafeBytes { resourceBytes in
        let value = try decode(msimeClientCandidateGlossRequest(
          requestBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(request.count),
          resourceBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(resourceData.count)))
        guard let dictionary = value as? [String: Any] else { throw InputBridgeFailure.invalidResponse }
        return dictionary
      }
    }
  }

  /// Reads one bounded page from the verified packaged Emoji catalog. This has no live-session
  /// dependency and is safe to invoke from the keyboard's serial catalog worker.
  static func emojiCatalog(request: Data, resources: String) throws -> [String: Any] {
    let resourceData = Data(resources.utf8)
    guard !request.isEmpty, request.count <= 16_384,
          NSString(string: resources).isAbsolutePath, resourceData.count <= 4096 else {
      throw InputBridgeFailure.invalidResponse
    }
    return try request.withUnsafeBytes { requestBytes in
      try resourceData.withUnsafeBytes { resourceBytes in
        let value = try decode(msimeClientEmojiCatalogRequest(
          requestBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(request.count),
          resourceBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(resourceData.count)))
        guard let dictionary = value as? [String: Any] else {
          throw InputBridgeFailure.invalidResponse
        }
        return dictionary
      }
    }
  }

  func applyTranslations(generation: UInt64, translations: Data) throws -> [String: Any] {
    try translations.withUnsafeBytes { bytes in
      let value = try Self.decode(msimeClientApplyTranslations(
        handle, generation, bytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(translations.count)))
      guard let dictionary = value as? [String: Any] else { throw InputBridgeFailure.invalidResponse }
      return dictionary
    }
  }

  func snapshot(from value: [String: Any]) throws -> MetasequoiaInputSnapshot {
    try Self.snapshot(value)
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
    let applied = updatePreferences { prefs in
      prefs["fuzzy_pinyin"] = ["enabled": rules != 0, "seeded": true,
                                "rules": names.enumerated().compactMap { rules & (1 << $0.offset) == 0 ? nil : $0.element }]
    }
    if applied { appliedFuzzyPinyinRules = rules }
    return applied
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
    guard updatePreferences({ $0["scheme"] = "quanpin" }) else { return diagnostic("九键模式切换失败") }
    nineKeyEnabled = true
    return dispatch { msimeClientSetNineKeyMode(handle, true) }
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
    return editCandidate(generation: generation.uint64Value, globalIndex: globalIndex.uint64Value,
                         action: action)
  }

  /// Edit a candidate the caller already holds an engine identity for.
  ///
  /// The expanded panel lists every candidate the engine returned, not the nine on the strip, so
  /// its positions are not the visible indexes the overload above resolves. It carries the
  /// generation and global index the snapshot gave it, which is what the engine wanted all along.
  func editCandidate(generation: UInt64, globalIndex: UInt64,
                     action: MetasequoiaCandidateAction) -> MetasequoiaInputSnapshot {
    guard let indexValue = UInt(exactly: globalIndex) else { return diagnostic("候选已失效") }
    switch action {
    case .promote:
      return dispatch { msimeClientPinCandidate(handle, generation, indexValue) }
    case .remove:
      return dispatch { msimeClientRemoveCandidate(handle, generation, indexValue) }
    case .fixFirst:
      return dispatch { msimeClientFixCandidatePosition(handle, generation, indexValue, 1) }
    case .clearPosition:
      return dispatch { msimeClientClearCandidatePosition(handle, generation, indexValue) }
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

  // The engine keeps its dictionary access from creation until destroy, and those lock files sit in
  // the App Group container. iOS terminates an extension that is suspended while holding a lock
  // there, which it reports as 0xdead10cc, so putting the keyboard away has to hand the access back
  // rather than only pause learning. Destroying also ends learning writes, which is what pausing
  // was for.
  func suspendDictionarySession() -> Bool {
    guard !suspended else { return true }
    guard !hasComposition else { return false }
    if handle != 0 {
      guard (try? Self.decode(msimeClientDestroy(handle))) != nil else { return false }
      handle = 0
    }
    suspended = true
    return true
  }

  // Recreated from the options prepared when this process started. Preparation streams every pinned
  // resource through SHA-256, so repeating it for each presentation would cost far more than the
  // session itself; the options stay valid for the life of the process.
  func resumeDictionarySession() throws {
    guard suspended else { return }
    guard !options.isEmpty else { throw InputBridgeFailure.unavailable }
    handle = try Self.callCreateFocused(options)
    if nineKeyEnabled { _ = dispatch { msimeClientSetNineKeyMode(handle, true) } }
    suspended = false
  }

  func localDictionaryStateVersion() throws -> String {
    let result = try Self.callOptions(msimeClientSnapshotVersion, options)
    guard let version = result["version"] as? String, version.utf8.count == 64,
          let generation = result["generation"] as? String,
          generation == "legacy" || UUID(uuidString: generation)?.uuidString == generation else {
      throw InputBridgeFailure.invalidResponse
    }
    return "local-v1:\(generation):\(version)"
  }

  func dictionarySnapshotContext() throws -> [String: Any] {
    guard let resources = options["resources"] as? String, let user = options["user_data"] as? String,
          let dictionaries = options["dictionaries"] as? String else { throw InputBridgeFailure.invalidResponse }
    return ["resources": URL(fileURLWithPath: resources), "user": URL(fileURLWithPath: user),
            "contentIdentifier": dictionaries,
            "preparedOptions": try JSONSerialization.data(withJSONObject: options)]
  }

  func activateDictionarySnapshot(_ snapshot: MSIMEPreparedDictionarySnapshot,
                                  expectedVersion: String) throws {
    guard handle != 0 else { throw InputBridgeFailure.unavailable }
    let fields = expectedVersion.split(separator: ":", omittingEmptySubsequences: false)
    guard fields.count == 3, fields[0] == "local-v1", fields[2].utf8.count == 64 else {
      throw InputBridgeFailure.invalidResponse
    }
    let expected = Data(fields[2].utf8)
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
      handle = try Self.callCreateFocused(options)
      DictionarySnapshotBridge.forget(snapshot.identifier)
      snapshot.markConsumed()
    } catch {
      handle = try Self.callCreateFocused(options)
      throw error
    }
  }

  func applyPersonalPrevious(_ previous: [String: Any]?, replacement: [String: Any]?, requestID: String) throws {
    var action: [String: Any] = ["operation": "edit", "request_id": requestID]
    action["previous"] = previous ?? NSNull()
    action["replacement"] = replacement ?? NSNull()
    let request: [String: Any] = ["options": options, "action": action]
    let result = try withDictionaryMaintenance {
      try Self.callOptions(msimeClientDictionary, request)
    }
    guard (result["applied"] as? Bool) == true else { throw InputBridgeFailure.response("个人词条未能应用") }
  }

  func personalEntries(atOffset offset: UInt) throws -> [String: Any] {
    let request: [String: Any] = ["options": options,
                                  "action": ["operation": "list", "offset": offset, "limit": 100]]
    var result = try withDictionaryMaintenance {
      try Self.callOptions(msimeClientDictionary, request)
    }
    if let hasMore = result.removeValue(forKey: "has_more") { result["hasMore"] = hasMore }
    return result
  }

  private func withDictionaryMaintenance<T>(_ operation: () throws -> T) throws -> T {
    guard handle != 0 else { throw InputBridgeFailure.unavailable }
    guard !hasComposition else { throw InputBridgeFailure.response("请先结束当前输入再同步个人词库") }
    let previousHandle = handle
    _ = try Self.decode(msimeClientDestroy(previousHandle))
    handle = 0
    let result = Result { try operation() }
    do {
      handle = try Self.callCreateFocused(options)
      initializationDiagnostic = nil
    } catch {
      initializationDiagnostic = "词库维护后输入运行时恢复失败。"
      throw error
    }
    return try result.get()
  }

  private var hasComposition: Bool { (try? (view()["preedit"] as? String ?? "")).map { !$0.isEmpty } ?? false }

  private func localMode() throws -> String { try view()["local_mode"] as? String ?? "" }

  private func switchScheme(_ scheme: String, profile: String?) -> MetasequoiaInputSnapshot {
    let updated = updatePreferences { prefs in
      prefs["scheme"] = scheme
      if let profile { prefs["shuangpin_profile"] = profile }
    }
    guard updated else { return diagnostic("输入方案切换失败") }
    nineKeyEnabled = false
    return dispatch { msimeClientSetNineKeyMode(handle, false) }
  }

  private func command(_ value: UInt32) -> MetasequoiaInputSnapshot {
    dispatch { msimeClientCommand(handle, value) }
  }

  private func pointer(for character: String, shift: Bool) -> UnsafeMutablePointer<CChar>? {
    guard let byte = Self.ascii(character) else { return nil }
    return msimeClientCharacter(handle, byte, shift)
  }

  private func dispatch(_ operation: () -> UnsafeMutablePointer<CChar>?) -> MetasequoiaInputSnapshot {
    guard handle != 0 else {
      return diagnostic(initializationDiagnostic ?? "输入运行时尚未准备完成。")
    }
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
      let response = try Self.callUpdate(msimeClientUpdatePreferences, handle, snapshot)
      return response["deferred"] as? Bool != true
    } catch {
      options["preferences"] = previous
      revision &-= 1
      return false
    }
  }

  private static func bootstrapOptions(resources resourceOverride: URL?, stateRoot stateOverride: URL?) -> [String: Any] {
    let fm = FileManager.default
    let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.app.msime.ios")
      ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let root = stateOverride ?? group.appendingPathComponent("MSIME", isDirectory: true)
    let resources = resourceOverride
      ?? Bundle.main.resourceURL?.appendingPathComponent("EngineResources", isDirectory: true)
      ?? root.appendingPathComponent("resources", isDirectory: true)
    return ["resources": resources.path, "state_root": root.path]
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
      candidateCodes: rows.map { $0["code"] as? String ?? "" },
      candidateGlosses: rows.map { $0["translation"] as? String ?? "" },
      candidatePageCount: max(0, (view["page_count"] as? NSNumber)?.intValue ?? 0),
      answeredByPinyinFallback: view["answered_by_pinyin_fallback"] as? Bool ?? false,
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

  private static func callCreateFocused(_ options: [String: Any]) throws -> UInt64 {
    let handle = try number(try callCreate(options)["session"])
    do {
      _ = try decode(msimeClientFocus(handle, true))
      return handle
    } catch {
      _ = try? decode(msimeClientDestroy(handle))
      throw error
    }
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
