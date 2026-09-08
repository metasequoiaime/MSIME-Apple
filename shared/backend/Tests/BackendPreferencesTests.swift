import XCTest
@testable import MSIMEBackend

final class BackendPreferencesTests: XCTestCase {
  func testMergePreservesOtherPlatformsAndReadRevision() throws {
    let base = BackendAccountClient.Preferences(revision: 42, settings: ["appearance.page_size": .integer(7), "input.schema": .string("quanpin")])
    let schema = BackendAccountClient.PreferenceSchema(fields: ["input.schema": .init(type: "string")], maximum_bytes: 65536, update_mode: "replace", revision_required: true)
    let merged = try BackendAccountClient.mergedPreferences(base, replacing: ["input.schema": .string("wubi")], schema: schema)
    XCTAssertEqual(merged.revision, 42)
    XCTAssertEqual(merged.settings["appearance.page_size"], .integer(7))
    XCTAssertEqual(merged.settings["input.schema"], .string("wubi"))
    XCTAssertThrowsError(try BackendAccountClient.mergedPreferences(base, replacing: ["platform.ios.nine_key": .boolean(true)], schema: schema))
  }
  func testPhotoSizedPrivateSettingsStayIntactWithinNegotiatedLimit() throws {
    let photo = String(repeating: "A", count: 4 * ((512000 + 2) / 3))
    let json = "{\"photo\":\"" + photo + "\"}"
    let base = BackendAccountClient.Preferences(revision: 1, settings: [:])
    let key = "platform.ios.custom_keyboard_skin"
    let schema = BackendAccountClient.PreferenceSchema(fields: [key: .init(type: "string")], maximum_bytes: 1024 * 1024, update_mode: "replace", revision_required: true)
    let merged = try BackendAccountClient.mergedPreferences(base, replacing: [key: .string(json)], schema: schema)
    XCTAssertEqual(merged.settings[key], .string(json))
    let old = BackendAccountClient.PreferenceSchema(fields: schema.fields, maximum_bytes: 65536, update_mode: "replace", revision_required: true)
    XCTAssertThrowsError(try BackendAccountClient.mergedPreferences(base, replacing: [key: .string(json)], schema: old))
  }
  func testUnsupportedCloudValuesFailBeforeAnApplicationPlanExists() throws {
    for settings: [String: BackendPreferenceValue] in [
      ["input.schema": .string("shuangpin"), "input.shuangpin_schema": .string("unsupported")],
      ["input.schema": .string("wubi"), "input.wubi_schema": .string("wubi98")],
      ["platform.ios.sound_enabled": .string("true")],
      ["platform.ios.haptic_strength": .string("unsafe")]
    ] { XCTAssertThrowsError(try IOSPreferencePlan(settings)) }
    let japanese = try IOSPreferencePlan(["input.schema": .string("japanese"), "platform.ios.nine_key": .boolean(true)])
    XCTAssertEqual(japanese.scheme, "japaneseNineKey")
    let roman = try IOSPreferencePlan(["input.schema": .string("japanese"), "platform.ios.nine_key": .boolean(false)])
    XCTAssertEqual(roman.scheme, "japanese")
    let nine = try IOSPreferencePlan(["input.schema": .string("quanpin"), "platform.ios.nine_key": .boolean(true)])
    XCTAssertEqual(nine.scheme, "nineKey")
    XCTAssertNil(nine.sound)
    let shuangpin = try IOSPreferencePlan(["input.schema": .string("shuangpin"), "input.shuangpin_schema": .string("ziranma"), "input.character_set": .string("traditional")])
    XCTAssertEqual(shuangpin.scheme, "ziranma")
    XCTAssertEqual(shuangpin.traditional, true)
  }
}
