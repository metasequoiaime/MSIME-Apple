import XCTest

/// 「候选栏 AI 候选」: the shared document says where to send, the Keychain key is handed over only for that endpoint.
final class AICandidatePreferenceTests: XCTestCase {
  func testTurningOnWritesTheSavedConfigurationButNoKey() {
    let existing: [String: Any] = ["prompt": "keep", "tokens": ["deepseek": "synced"]]
    let assistant = AICandidatePreference.assistant(
      existing, enabled: true, limit: 5, provider: "deepSeek",
      endpoint: " https://api.deepseek.com/chat/completions ", model: " deepseek-chat ")
    XCTAssertEqual(assistant["enabled"] as? Bool, true)
    XCTAssertEqual(assistant["provider"] as? String, "deepseek")
    XCTAssertEqual(assistant["endpoint"] as? String, "https://api.deepseek.com/chat/completions")
    XCTAssertEqual(assistant["model"] as? String, "deepseek-chat")
    XCTAssertEqual(assistant["candidate_limit"] as? Int, 5)
    XCTAssertEqual(assistant["prompt"] as? String, "keep")
    XCTAssertEqual(assistant["tokens"] as? [String: String], ["deepseek": "synced"], "a key from elsewhere is neither copied nor erased")
    XCTAssertNil(assistant["token"])
  }

  func testTurningOffKeepsWhereItPointedAndClampsTheLimit() {
    let on = AICandidatePreference.assistant(nil, enabled: true, limit: 3, provider: "openAI",
                                             endpoint: "https://api.openai.com/v1/chat/completions", model: "m")
    let off = AICandidatePreference.assistant(on, enabled: false, limit: 40, provider: "", endpoint: "", model: "")
    XCTAssertEqual(off["enabled"] as? Bool, false)
    XCTAssertEqual(off["endpoint"] as? String, "https://api.openai.com/v1/chat/completions")
    XCTAssertEqual(off["candidate_limit"] as? Int, 10)
    XCTAssertFalse(AICandidatePreference.isEnabled(["ai_assistant": off]))
    XCTAssertEqual(AICandidatePreference.limit(["ai_assistant": ["candidate_limit": 0]]), AICandidatePreference.defaultLimit)
    XCTAssertEqual(AICandidatePreference.limit(nil), 3)
  }

  func testTheKeyIsOnlyHandedOverForTheDocumentsOwnEndpoint() {
    let endpoint = "https://api.deepseek.com/chat/completions"
    let preferences: [String: Any] = ["ai_assistant": ["enabled": true, "endpoint": endpoint]]
    XCTAssertEqual(AICandidatePreference.credentialEndpoint(preferences, configuredEndpoint: endpoint + " "), endpoint)
    XCTAssertNil(AICandidatePreference.credentialEndpoint(preferences, configuredEndpoint: "https://evil.example/v1"))
    XCTAssertNil(AICandidatePreference.credentialEndpoint(preferences, configuredEndpoint: nil))
    XCTAssertNil(AICandidatePreference.credentialEndpoint(["ai_assistant": ["enabled": false, "endpoint": endpoint]],
                                                          configuredEndpoint: endpoint))
    XCTAssertNil(AICandidatePreference.credentialEndpoint(nil, configuredEndpoint: endpoint))
  }
}
