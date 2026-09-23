import XCTest

final class VoicePolishTests: XCTestCase {
  func testPresetsComeFromTheSharedPromptHeader() {
    var settings = VoicePolishSettings()
    XCTAssertTrue(settings.systemPrompt.hasPrefix("你是语音转写整理助手。"))
    settings.promptID = "faithful"
    XCTAssertTrue(settings.systemPrompt.hasPrefix("你是语音转写校对助手。"))
    settings.promptID = "zh2en"
    XCTAssertTrue(settings.systemPrompt.hasPrefix("你是中文口述英译助手。"))
    settings.promptID = "casual"
    XCTAssertTrue(settings.systemPrompt.hasPrefix("你是口语整理助手。"))
  }

  func testCustomSlotsFallBackTheWayTheDesktopDoes() {
    var settings = VoicePolishSettings()
    let cleanup = settings.systemPrompt
    settings.promptID = "custom_2"
    XCTAssertEqual(settings.systemPrompt, cleanup)
    settings.customPrompts[1] = "只改错别字"
    XCTAssertEqual(settings.systemPrompt, "只改错别字")

    settings.promptID = "custom_1"
    settings.legacyPrompt = "旧的提示词"
    XCTAssertEqual(settings.systemPrompt, "旧的提示词")
    settings.customPrompts[0] = "第一槽"
    XCTAssertEqual(settings.systemPrompt, "第一槽")
  }

  func testReadsAndWritesTheSharedVoiceFieldsOnly() {
    var document: [String: Any] = ["voice_input": [
      "polish_enabled": true, "polish_prompt_id": "zh2en", "polish_prompt_custom_3": "三",
      "language": "en-US", "sound_enabled": false, "end_sound": false, "asr_provider": "doubao",
    ]]
    var settings = VoicePolishSettings(document)
    XCTAssertTrue(settings.polishEnabled)
    XCTAssertEqual(settings.promptID, "zh2en")
    XCTAssertEqual(settings.customPrompts, ["", "", "三"])
    XCTAssertEqual(settings.language, "en-us")
    XCTAssertFalse(settings.soundEnabled)
    XCTAssertTrue(settings.startSound)
    XCTAssertFalse(settings.endSound)

    settings.promptID = "custom_1"
    settings.customPrompts[0] = "  \n"
    settings.polishEnabled = false
    settings.startSound = false
    settings.endSound = true
    settings.write(into: &document)
    let voice = document["voice_input"] as? [String: Any]
    XCTAssertEqual(voice?["polish_text"] as? Bool, false)
    XCTAssertEqual(voice?["polish_enabled"] as? Bool, false)
    XCTAssertEqual(voice?["polish_prompt_id"] as? String, "custom_1")
    XCTAssertEqual(voice?["polish_prompt_custom_1"] as? String, "")
    XCTAssertEqual(voice?["polish_prompt_custom_3"] as? String, "三")
    XCTAssertEqual(voice?["asr_provider"] as? String, "doubao")
    XCTAssertEqual(voice?["start_sound"] as? Bool, false)
    XCTAssertEqual(voice?["end_sound"] as? Bool, true)
    XCTAssertEqual(voice?["sound_enabled"] as? Bool, false)
  }

  func testUnknownValuesFallBackToTheDefaults() {
    let settings = VoicePolishSettings(["voice_input": ["polish_prompt_id": "custom", "language": "fr"]])
    XCTAssertEqual(settings.promptID, "cleanup")
    XCTAssertEqual(settings.language, "zh-cn")
    XCTAssertFalse(settings.polishEnabled)
  }

  func testTranscriptionLanguageFollowsTheSharedNormalization() {
    var settings = VoicePolishSettings()
    XCTAssertEqual(settings.transcriptionLanguage(for: .openAI), "zh")
    XCTAssertNil(settings.transcriptionLanguage(for: .siliconFlow))
    XCTAssertNil(settings.transcriptionLanguage(for: .doubao))
    settings.language = "en-us"
    XCTAssertEqual(settings.transcriptionLanguage(for: .groq), "en")
    settings.language = "auto"
    XCTAssertNil(settings.transcriptionLanguage(for: .openAI))
  }

  func testTranscriptionBodyCarriesTheLanguageOnlyWhenGiven() throws {
    let with = try AppServicesBridge.transcriptionBody(Data([1, 2]), model: "whisper-1", language: "zh")
    let without = try AppServicesBridge.transcriptionBody(Data([1, 2]), model: "whisper-1")
    let withText = String(decoding: try XCTUnwrap(with["body"] as? Data), as: UTF8.self)
    let withoutText = String(decoding: try XCTUnwrap(without["body"] as? Data), as: UTF8.self)
    XCTAssertTrue(withText.contains("name=\"language\"\r\n\r\nzh\r\n"))
    XCTAssertFalse(withoutText.contains("name=\"language\""))
  }

  func testTheTranscriptIsFramedAsData() {
    XCTAssertEqual(VoicePolishSettings.userMessage("你好"), "<asr_text>\n你好\n</asr_text>")
  }
}
