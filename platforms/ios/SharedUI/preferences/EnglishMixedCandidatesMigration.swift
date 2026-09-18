import Foundation

private typealias EnglishMixedByte = UInt8

@_silgen_name("msime_client_load_preferences")
private func msimeEnglishMixedLoadPreferences(
  _ directory: UnsafePointer<EnglishMixedByte>?, _ length: UInt
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_save_preferences")
private func msimeEnglishMixedSavePreferences(
  _ directory: UnsafePointer<EnglishMixedByte>?, _ directoryLength: UInt,
  _ expectedRevision: UInt64,
  _ snapshot: UnsafePointer<EnglishMixedByte>?, _ snapshotLength: UInt
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_string_free")
private func msimeEnglishMixedStringFree(_ value: UnsafeMutablePointer<CChar>?)

/// Moves the Apple client's legacy boolean into the shared preference document exactly once.
///
/// The shared `mixed_input` object remains the only current source of truth. A failed compare-and-
/// swap leaves the legacy key intact so a later keyboard session can retry without losing the user's
/// choice.
enum EnglishMixedCandidatesMigration {
  static let legacyKey = "english.mixedCandidates"

  private enum MigrationError: Error {
    case invalidDirectory
    case invalidResponse
    case response(String)
  }

  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static func shouldMigrate(customStateRoot: URL?, store: UserDefaults = defaults) -> Bool {
    customStateRoot == nil && store.object(forKey: legacyKey) != nil
  }

  static func migrateIfNeeded(stateRoot: URL) {
    guard defaults.object(forKey: legacyKey) != nil else { return }
    _ = try? migrateIfNeeded(
      defaults: defaults,
      load: { try loadSnapshot(from: stateRoot) },
      save: { revision, snapshot in
        try saveSnapshot(snapshot, expectedRevision: revision, to: stateRoot)
      })
  }

  @discardableResult
  static func migrateIfNeeded(
    defaults: UserDefaults,
    load: () throws -> [String: Any],
    save: (UInt64, [String: Any]) throws -> Void
  ) throws -> Bool {
    guard let enabled = defaults.object(forKey: legacyKey) as? Bool else { return false }
    var snapshot = try load()
    guard let revision = snapshot["revision"] as? NSNumber,
          var preferences = snapshot["preferences"] as? [String: Any]
    else { throw MigrationError.invalidResponse }

    var mixedInput = preferences["mixed_input"] as? [String: Any] ?? [:]
    if mixedInput["english"] as? Bool != enabled {
      mixedInput["english"] = enabled
      preferences["mixed_input"] = mixedInput
      snapshot["preferences"] = preferences
      try save(revision.uint64Value, snapshot)
    }

    defaults.removeObject(forKey: legacyKey)
    return true
  }

  private static func loadSnapshot(from directory: URL) throws -> [String: Any] {
    let directoryData = try directoryData(for: directory)
    return try directoryData.withUnsafeBytes { bytes in
      let value = try decode(msimeEnglishMixedLoadPreferences(
        bytes.bindMemory(to: EnglishMixedByte.self).baseAddress, UInt(directoryData.count)))
      guard let snapshot = value as? [String: Any] else { throw MigrationError.invalidResponse }
      return snapshot
    }
  }

  private static func saveSnapshot(
    _ snapshot: [String: Any], expectedRevision: UInt64, to directory: URL
  ) throws {
    let directoryData = try directoryData(for: directory)
    let snapshotData = try JSONSerialization.data(withJSONObject: snapshot)
    guard snapshotData.count <= 16_384 else { throw MigrationError.invalidResponse }
    _ = try directoryData.withUnsafeBytes { directoryBytes in
      try snapshotData.withUnsafeBytes { snapshotBytes in
        try decode(msimeEnglishMixedSavePreferences(
          directoryBytes.bindMemory(to: EnglishMixedByte.self).baseAddress,
          UInt(directoryData.count), expectedRevision,
          snapshotBytes.bindMemory(to: EnglishMixedByte.self).baseAddress,
          UInt(snapshotData.count)))
      }
    }
  }

  private static func directoryData(for directory: URL) throws -> Data {
    guard directory.isFileURL, NSString(string: directory.path).isAbsolutePath else {
      throw MigrationError.invalidDirectory
    }
    let data = Data(directory.path.utf8)
    guard !data.isEmpty, data.count <= 16_384 else { throw MigrationError.invalidDirectory }
    return data
  }

  private static func decode(_ pointer: UnsafeMutablePointer<CChar>?) throws -> Any {
    guard let pointer else { throw MigrationError.invalidResponse }
    let string = String(cString: pointer)
    msimeEnglishMixedStringFree(pointer)
    guard let data = string.data(using: .utf8),
          let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw MigrationError.invalidResponse }
    guard envelope["ok"] as? Bool == true else {
      throw MigrationError.response(envelope["error"] as? String ?? "shared preference migration failed")
    }
    return envelope["value"] ?? NSNull()
  }
}
