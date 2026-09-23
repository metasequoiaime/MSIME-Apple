import Foundation

@_silgen_name("msime_ios_voice_polish_prompt")
private func msimeIOSVoicePolishPrompt(_ id: UnsafePointer<CChar>?, _ legacy: UnsafePointer<CChar>?,
                                       _ custom1: UnsafePointer<CChar>?, _ custom2: UnsafePointer<CChar>?,
                                       _ custom3: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

/// The shared document's `voice_input` fields this app acts on: recognition language, the start and end cue, and the polish pass after recognition.
///
/// The desktop configures a separate polish provider and key. On iOS the polish pass goes to the AI service already saved under 「AI 设置」, whose key stays in the Keychain, so only the preset and the three custom prompts come from the document.
struct VoicePolishSettings: Equatable {
  static let presets: [(id: String, title: String)] = [
    ("cleanup", "精炼整理"), ("faithful", "忠实校对"), ("zh2en", "中翻英"), ("casual", "口语整理"),
    ("custom_1", "自定义一"), ("custom_2", "自定义二"), ("custom_3", "自定义三"),
  ]
  static let languages: [(id: String, title: String)] = [
    ("zh-cn", "中文（简体）"), ("en-us", "English"), ("auto", "自动识别"),
  ]
  static let customSlots = ["custom_1", "custom_2", "custom_3"]

  var polishEnabled = false
  var promptID = "cleanup"
  /// The single prompt box older configurations wrote; the shared resolver still honours it.
  var legacyPrompt = ""
  var customPrompts = ["", "", ""]
  var language = "zh-cn"
  var soundEnabled = true
  /// The desktop's per-cue switches; this page only shows the master switch, and a cue plays when both are on.
  var startSound = true
  var endSound = true

  init() {}

  init(_ preferences: [String: Any]?) {
    let voice = preferences?["voice_input"] as? [String: Any] ?? [:]
    // The shared settings page reads either flag as on and writes both.
    polishEnabled = voice["polish_text"] as? Bool == true || voice["polish_enabled"] as? Bool == true
    let id = voice["polish_prompt_id"] as? String ?? ""
    promptID = Self.presets.contains { $0.id == id } ? id : "cleanup"
    legacyPrompt = voice["polish_prompt"] as? String ?? ""
    customPrompts = Self.customSlots.map { voice["polish_prompt_\($0)"] as? String ?? "" }
    let language = (voice["language"] as? String ?? "").lowercased()
    self.language = Self.languages.contains { $0.id == language } ? language : "zh-cn"
    soundEnabled = voice["sound_enabled"] as? Bool ?? true
    startSound = voice["start_sound"] as? Bool ?? true
    endSound = voice["end_sound"] as? Bool ?? true
  }

  /// Writes the fields this page owns and keeps the rest of `voice_input` (desktop providers, hotkeys, Doubao settings) as it was.
  func write(into preferences: inout [String: Any]) {
    var voice = preferences["voice_input"] as? [String: Any] ?? [:]
    voice["polish_text"] = polishEnabled
    voice["polish_enabled"] = polishEnabled
    voice["polish_prompt_id"] = promptID
    for (slot, prompt) in zip(Self.customSlots, customPrompts) {
      voice["polish_prompt_\(slot)"] = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : prompt
    }
    voice["language"] = language
    voice["sound_enabled"] = soundEnabled
    preferences["voice_input"] = voice
  }

  /// The index of the selected custom slot, or nil for a built-in preset.
  var customSlot: Int? { Self.customSlots.firstIndex(of: promptID) }

  /// The system prompt the polish request carries, resolved by the shared header the desktop hosts use.
  var systemPrompt: String {
    let values = [promptID, legacyPrompt] + customPrompts
    let pointers = values.map { strdup($0) }
    defer { pointers.forEach { free($0) } }
    guard let result = msimeIOSVoicePolishPrompt(pointers[0], pointers[1], pointers[2], pointers[3], pointers[4])
    else { return "" }
    defer { free(result) }
    return String(cString: result)
  }

  /// The recognized text framed the way every host frames it, so the model treats it as data rather than instructions.
  static func userMessage(_ transcript: String) -> String { "<asr_text>\n\(transcript)\n</asr_text>" }

  /// The `language` field of a transcription request: the language part of the tag, or nothing to let the service detect it. SiliconFlow's SenseVoice rejects the field, so it never gets one; Doubao's streaming protocol does not take one either.
  func transcriptionLanguage(for provider: VoiceProviderPreset) -> String? {
    guard provider != .siliconFlow, provider != .doubao, language != "auto" else { return nil }
    return language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
  }
}
