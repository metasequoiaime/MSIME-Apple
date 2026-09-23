import XCTest

/// 行内预编辑 keeps the host's marked text equal to the composition, and context reads look past it.
final class InlineCompositionTests: XCTestCase {
  func testEditsOnlyWhenTheMarkedTextChanges() {
    XCTAssertNil(InlineCompositionPolicy.edit(showing: "", next: ""))
    XCTAssertNil(InlineCompositionPolicy.edit(showing: "ni", next: "ni"))
    XCTAssertEqual(InlineCompositionPolicy.edit(showing: "", next: "n"), .mark("n"))
    XCTAssertEqual(InlineCompositionPolicy.edit(showing: "ni", next: "ni'h"), .mark("ni'h"))
    XCTAssertEqual(InlineCompositionPolicy.edit(showing: "ni", next: ""), .clear)
  }

  func testContextBeforeCompositionDropsOnlyTheMarkedSuffix() {
    XCTAssertEqual(InlineCompositionPolicy.contextBefore("你好，ni'hao", marked: "ni'hao"), "你好，")
    XCTAssertEqual(InlineCompositionPolicy.contextBefore("你好，", marked: ""), "你好，")
    // A host that does not report the marked text before the caret is left as it is.
    XCTAssertEqual(InlineCompositionPolicy.contextBefore("你好，", marked: "ni"), "你好，")
    XCTAssertNil(InlineCompositionPolicy.contextBefore(nil, marked: "ni"))
  }

  func testTheSwitchIsOffUntilTheUserTurnsItOn() {
    let defaults = InlinePreeditPreference.defaults
    let previous = defaults.object(forKey: InlinePreeditPreference.key)
    defer { defaults.set(previous, forKey: InlinePreeditPreference.key) }
    defaults.removeObject(forKey: InlinePreeditPreference.key)
    XCTAssertFalse(InlinePreeditPreference.isEnabled)
    InlinePreeditPreference.isEnabled = true
    XCTAssertTrue(defaults.bool(forKey: InlinePreeditPreference.key))
  }
}
