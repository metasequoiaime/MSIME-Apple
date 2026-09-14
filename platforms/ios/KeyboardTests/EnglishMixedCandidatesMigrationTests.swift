import XCTest

final class EnglishMixedCandidatesMigrationTests: XCTestCase {
  private func defaults() throws -> (UserDefaults, String) {
    let suite = "app.msime.tests.english-mixed.\(UUID().uuidString)"
    return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
  }

  func testLegacyValueMovesIntoSharedMixedInputWithoutReplacingSiblingFields() throws {
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: EnglishMixedCandidatesMigration.legacyKey)
    let originalMixedInput: [String: Any] = [
      "english": true, "minimum_prefix": 5, "emoji": true, "kaomoji": false,
    ]
    var savedRevision: UInt64?
    var savedSnapshot: [String: Any]?

    let migrated = try EnglishMixedCandidatesMigration.migrateIfNeeded(
      defaults: defaults,
      load: {
        ["format_version": 1, "revision": 7,
         "preferences": ["scheme": "quanpin", "mixed_input": originalMixedInput]]
      },
      save: { revision, snapshot in
        savedRevision = revision
        savedSnapshot = snapshot
      })

    XCTAssertTrue(migrated)
    XCTAssertNil(defaults.object(forKey: EnglishMixedCandidatesMigration.legacyKey))
    XCTAssertEqual(savedRevision, 7)
    let preferences = try XCTUnwrap(savedSnapshot?["preferences"] as? [String: Any])
    XCTAssertEqual(preferences["scheme"] as? String, "quanpin")
    let mixedInput = try XCTUnwrap(preferences["mixed_input"] as? [String: Any])
    XCTAssertEqual(mixedInput["english"] as? Bool, false)
    XCTAssertEqual(mixedInput["minimum_prefix"] as? Int, 5)
    XCTAssertEqual(mixedInput["emoji"] as? Bool, true)
    XCTAssertEqual(mixedInput["kaomoji"] as? Bool, false)
  }

  func testMatchingSharedValueRemovesLegacyKeyWithoutWriting() throws {
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: EnglishMixedCandidatesMigration.legacyKey)
    var didSave = false

    let migrated = try EnglishMixedCandidatesMigration.migrateIfNeeded(
      defaults: defaults,
      load: {
        ["format_version": 1, "revision": 3,
         "preferences": ["mixed_input": ["english": true, "minimum_prefix": 5,
                                           "emoji": false, "kaomoji": false]]]
      },
      save: { _, _ in didSave = true })

    XCTAssertTrue(migrated)
    XCTAssertFalse(didSave)
    XCTAssertNil(defaults.object(forKey: EnglishMixedCandidatesMigration.legacyKey))
  }

  func testFailedSaveRetainsLegacyKeyForRetry() throws {
    enum ExpectedFailure: Error { case conflict }
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: EnglishMixedCandidatesMigration.legacyKey)

    XCTAssertThrowsError(try EnglishMixedCandidatesMigration.migrateIfNeeded(
      defaults: defaults,
      load: {
        ["format_version": 1, "revision": 4,
         "preferences": ["mixed_input": ["english": true, "minimum_prefix": 5,
                                           "emoji": false, "kaomoji": false]]]
      },
      save: { _, _ in throw ExpectedFailure.conflict }))
    XCTAssertEqual(
      defaults.object(forKey: EnglishMixedCandidatesMigration.legacyKey) as? Bool, false)
  }

  func testMissingLegacyKeyDoesNotLoadOrSave() throws {
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    var didLoad = false
    var didSave = false

    let migrated = try EnglishMixedCandidatesMigration.migrateIfNeeded(
      defaults: defaults,
      load: { didLoad = true; return [:] },
      save: { _, _ in didSave = true })

    XCTAssertFalse(migrated)
    XCTAssertFalse(didLoad)
    XCTAssertFalse(didSave)
  }

  func testCustomStateRootNeverConsumesTheAppGroupLegacyKey() throws {
    let (defaults, suite) = try defaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: EnglishMixedCandidatesMigration.legacyKey)

    XCTAssertTrue(EnglishMixedCandidatesMigration.shouldMigrate(
      customStateRoot: nil, store: defaults))
    XCTAssertFalse(EnglishMixedCandidatesMigration.shouldMigrate(
      customStateRoot: FileManager.default.temporaryDirectory, store: defaults))
    XCTAssertEqual(
      defaults.object(forKey: EnglishMixedCandidatesMigration.legacyKey) as? Bool, false)
  }
}
