import XCTest
import Security

final class KeyboardAITests: XCTestCase {
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
