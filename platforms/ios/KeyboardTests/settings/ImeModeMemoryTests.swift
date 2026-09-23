import UIKit
import XCTest

/// 「沿用上次的中英文」: a new keyboard starts where the user last switched, and only the user's own switches count.
final class ImeModeMemoryTests: XCTestCase {
  private var suite: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suite = "msime-ime-mode-memory-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  func testOffFollowsTheDefaultAndRecordsNothing() {
    ImeModeMemoryPreference.record(chinese: false, defaults: defaults)
    XCTAssertNil(defaults.object(forKey: ImeModeMemoryPreference.lastChineseKey))
    XCTAssertTrue(ImeModeMemoryPreference.startsInChinese(fallback: true, defaults: defaults))
    XCTAssertFalse(ImeModeMemoryPreference.startsInChinese(fallback: false, defaults: defaults))
  }

  func testOnStartsFromTheLastSwitchOnceThereIsOne() {
    ImeModeMemoryPreference.setEnabled(true, defaults: defaults)
    XCTAssertTrue(ImeModeMemoryPreference.startsInChinese(fallback: true, defaults: defaults), "nothing recorded yet")
    ImeModeMemoryPreference.record(chinese: false, defaults: defaults)
    XCTAssertFalse(ImeModeMemoryPreference.startsInChinese(fallback: true, defaults: defaults))
    ImeModeMemoryPreference.record(chinese: true, defaults: defaults)
    XCTAssertTrue(ImeModeMemoryPreference.startsInChinese(fallback: false, defaults: defaults))
  }

  func testTogglingForgetsTheRecordedMode() {
    ImeModeMemoryPreference.setEnabled(true, defaults: defaults)
    ImeModeMemoryPreference.record(chinese: false, defaults: defaults)
    ImeModeMemoryPreference.setEnabled(false, defaults: defaults)
    ImeModeMemoryPreference.setEnabled(true, defaults: defaults)
    XCTAssertTrue(ImeModeMemoryPreference.startsInChinese(fallback: true, defaults: defaults))
    // Setting the value it already has keeps the record.
    ImeModeMemoryPreference.record(chinese: false, defaults: defaults)
    ImeModeMemoryPreference.setEnabled(true, defaults: defaults)
    XCTAssertFalse(ImeModeMemoryPreference.startsInChinese(fallback: true, defaults: defaults))
  }

  func testLatinFieldIsReportedUntilTheUserLeavesIt() {
    var context = KeyboardInputContext()
    XCTAssertFalse(context.isInLatinField)
    XCTAssertEqual(context.languageOverride(for: .URL, document: UUID(), isChinese: true), false)
    XCTAssertTrue(context.isInLatinField)
    XCTAssertEqual(context.languageOverride(for: .default, document: UUID(), isChinese: false), true)
    XCTAssertFalse(context.isInLatinField)
  }
}
