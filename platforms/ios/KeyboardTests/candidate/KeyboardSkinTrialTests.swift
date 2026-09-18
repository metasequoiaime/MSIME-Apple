import XCTest

final class KeyboardSkinTrialTests: XCTestCase {
  func testTrialRestoresExactCustomDesignAndMissingSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "trial-tests-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let original = try JSONEncoder().encode(CustomKeyboardSkin(background: 0x123456))
    defaults.set(original, forKey: CustomKeyboardSkinStore.key)
    let store = try KeyboardSkinTrialStore(directory: directory, defaults: defaults)
    let trial = try store.begin(name: "新皮肤", design: CustomKeyboardSkin(background: 0xABCDEF))
    XCTAssertEqual(defaults.string(forKey: KeyboardSkinPreference.key), "custom")
    try store.finish(trial.id, keep: false)
    XCTAssertNil(defaults.string(forKey: KeyboardSkinPreference.key))
    XCTAssertEqual(defaults.data(forKey: CustomKeyboardSkinStore.key), original)
    let second = try store.begin(name: "保留", design: trial.design)
    try store.finish(second.id, keep: true)
    try store.restorePending()
    XCTAssertEqual(defaults.string(forKey: KeyboardSkinPreference.key), "custom")
    XCTAssertEqual(try JSONDecoder().decode(CustomKeyboardSkin.self, from: XCTUnwrap(defaults.data(forKey: CustomKeyboardSkinStore.key))), trial.design)
  }
  func testRestartRecoveryAndLaterExplicitSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "trial-tests-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    defaults.set("ocean", forKey: KeyboardSkinPreference.key)
    let store = try KeyboardSkinTrialStore(directory: directory, defaults: defaults)
    _ = try store.begin(name: "试用", design: CustomKeyboardSkin())
    try KeyboardSkinTrialStore(directory: directory, defaults: defaults).restorePending()
    XCTAssertEqual(defaults.string(forKey: KeyboardSkinPreference.key), "ocean")
    let next = try store.begin(name: "试用", design: CustomKeyboardSkin())
    defaults.set("rose", forKey: KeyboardSkinPreference.key)
    try store.finish(next.id, keep: false)
    XCTAssertEqual(defaults.string(forKey: KeyboardSkinPreference.key), "rose")
  }
}
