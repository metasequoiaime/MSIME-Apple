import Foundation

struct KeyboardSkinTrial: Codable, Identifiable {
  let id: UUID
  let name: String
  let previousSelection: String?
  let previousDesign: Data?
  let design: CustomKeyboardSkin
}

// Persist the undo record before applying a trial. A killed app restores it on next launch.
struct KeyboardSkinTrialStore {
  private let file: URL
  private let defaults: UserDefaults
  init(directory: URL? = nil, defaults: UserDefaults = KeyboardFeedbackPreference.defaults) throws {
    guard let directory = directory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: InputSchemePreference.appGroupIdentifier) else {
      throw PersonalDictionaryStore.StoreError.unavailable
    }
    self.file = directory.appendingPathComponent("KeyboardSkinTrial.json")
    self.defaults = defaults
  }
  func begin(name: String, design: CustomKeyboardSkin) throws -> KeyboardSkinTrial {
    try restorePending()
    let trial = KeyboardSkinTrial(id: UUID(), name: name,
      previousSelection: defaults.string(forKey: KeyboardSkinPreference.key),
      previousDesign: defaults.data(forKey: CustomKeyboardSkinStore.key), design: design.normalized)
    let data = try JSONEncoder().encode(trial)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    defaults.set(try JSONEncoder().encode(trial.design), forKey: CustomKeyboardSkinStore.key)
    defaults.set(KeyboardSkin.custom.rawValue, forKey: KeyboardSkinPreference.key)
    return trial
  }
  func finish(_ id: UUID, keep: Bool) throws {
    guard let trial = try pending(), trial.id == id else { return }
    if !keep { restore(trial) }
    try FileManager.default.removeItem(at: file)
  }
  func restorePending() throws {
    guard let trial = try pending() else { return }
    try finish(trial.id, keep: false)
  }
  private func pending() throws -> KeyboardSkinTrial? {
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000 else {
      throw PersonalDictionaryStore.StoreError.invalidState
    }
    return try JSONDecoder().decode(KeyboardSkinTrial.self, from: Data(contentsOf: file))
  }
  private func restore(_ trial: KeyboardSkinTrial) {
    // Do not undo a different skin explicitly selected while the trial was open.
    guard defaults.string(forKey: KeyboardSkinPreference.key) == KeyboardSkin.custom.rawValue,
          let data = defaults.data(forKey: CustomKeyboardSkinStore.key),
          (try? JSONDecoder().decode(CustomKeyboardSkin.self, from: data)) == trial.design else { return }
    if let previous = trial.previousDesign { defaults.set(previous, forKey: CustomKeyboardSkinStore.key) }
    else { defaults.removeObject(forKey: CustomKeyboardSkinStore.key) }
    if let previous = trial.previousSelection { defaults.set(previous, forKey: KeyboardSkinPreference.key) }
    else { defaults.removeObject(forKey: KeyboardSkinPreference.key) }
  }
}
