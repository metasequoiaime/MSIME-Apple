import XCTest
import Security

final class KeyboardAITests: XCTestCase {
  @MainActor
  func testReplyClearDropsLateResultsAndNeverInsertsAutomatically() async throws {
    let model = ReplyKeyboardModel()
    var inserted = 0
    model.setText("你睡了吗")
    model.generate(style: "高情商", request: { _, _ in
      try? await Task.sleep(nanoseconds: 30_000_000)
      return "还没有"
    }, insert: { _ in inserted += 1; return true })
    model.setText("")
    try await Task.sleep(nanoseconds: 80_000_000)
    XCTAssertTrue(model.replies.isEmpty)
    XCTAssertFalse(model.busy)
    XCTAssertEqual(inserted, 0)
    model.setText("你好")
    model.generate(style: "高情商", request: { _, _ in "你好呀" }, insert: { _ in inserted += 1; return true })
    while model.busy { await Task.yield() }
    XCTAssertEqual(model.replies, ["你好呀"])
    XCTAssertEqual(inserted, 0)
    model.invalidateContext()
    model.use("你好呀")
    XCTAssertEqual(inserted, 0)
  }

  func testAISelectionRejectsDocumentCaretAndTextChanges() {
    let id = UUID()
    let selection = KeyboardDocumentContext(document: id, before: "before", selected: "fixture", after: "after")
    XCTAssertTrue(selection.matches(document: id, before: "before", selected: "fixture", after: "after"))
    XCTAssertFalse(selection.matches(document: UUID(), before: "before", selected: "fixture", after: "after"))
    XCTAssertFalse(selection.matches(document: nil, before: "before", selected: "fixture", after: "after"))
    XCTAssertFalse(selection.matches(document: id, before: "changed", selected: "fixture", after: "after"))
    XCTAssertFalse(selection.matches(document: id, before: "before", selected: nil, after: "after"))
    XCTAssertFalse(selection.matches(document: id, before: "before", selected: "fixture", after: "changed"))
  }

  func testSharedAIKeysStayOriginScopedAndConfigurationRoundTrips() throws {
    let first = try XCTUnwrap(URL(string: "https://fixture.invalid/v1/chat/completions"))
    let otherPath = try XCTUnwrap(URL(string: "https://fixture.invalid/v2/chat/completions"))
    let otherHost = try XCTUnwrap(URL(string: "https://other.invalid/v1/chat/completions"))
    let otherPort = try XCTUnwrap(URL(string: "https://fixture.invalid:444/v1/chat/completions"))
    let query = KeyboardAIService.query(url: first)
    let account = kSecAttrAccount as String
    XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "group.app.msime.ios")
    XCTAssertEqual(query[account] as? String, KeyboardAIService.query(url: otherPath)[account] as? String)
    XCTAssertNotEqual(query[account] as? String, KeyboardAIService.query(url: otherHost)[account] as? String)
    XCTAssertNotEqual(query[account] as? String, KeyboardAIService.query(url: otherPort)[account] as? String)
    var config = CustomServiceConfiguration()
    config.endpoint = first.absoluteString
    config.model = "fixture"
    config.prompt = "保留换行\n保持原意"
    let encoded = try JSONEncoder().encode(config)
    XCTAssertEqual(try JSONDecoder().decode(CustomServiceConfiguration.self, from: encoded), config)
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), ["provider", "voiceProvider", "endpoint", "model", "prompt"])
  }
}
