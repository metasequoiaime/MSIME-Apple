import Foundation
import CryptoKit
import XCTest

final class CloudSnapshotStagingTests: XCTestCase {
  func testValidatedStreamStagesEngineStateAndRejectsTruncatedFooter() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let resources = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("EngineResources", isDirectory: true))
    let session = MetasequoiaInputSessionBridge(resources: resources,
                                                 stateRoot: root.appendingPathComponent("EngineState"))
    let context = try session.dictionarySnapshotContext()
    let user = try XCTUnwrap(context["user"] as? URL)
    let preparedOptions = try XCTUnwrap(context["preparedOptions"] as? Data)
    let originalVersion = try session.localDictionaryStateVersion()
    let entry = #"{"id":"synthetic","kind":"quick","code":"snapshot","word":"合成词条","weight":100000,"revision":1,"updated_at":"2026-09-08T00:00:00Z"}"#
    let entries = [entry,
      entry.replacingOccurrences(of: "synthetic", with: "pinyin-fixture").replacingOccurrences(of: "quick", with: "pinyin").replacingOccurrences(of: "snapshot", with: "he'cheng").replacingOccurrences(of: "合成词条", with: "合成"),
      entry.replacingOccurrences(of: "synthetic", with: "wubi-fixture").replacingOccurrences(of: "quick", with: "wubi").replacingOccurrences(of: "snapshot", with: "wgk").replacingOccurrences(of: "合成词条", with: "合"),
      entry.replacingOccurrences(of: "synthetic", with: "english-fixture").replacingOccurrences(of: "quick", with: "english").replacingOccurrences(of: "合成词条", with: "Snapshot")]
    var lines = [#"{"type":"header","format":"msime-dictionary-snapshot","version":1,"revision":1}"#]
    lines += entries.map { "{\"type\":\"entry\",\"data\":\($0)}" }
    lines += entries.map { "{\"type\":\"overlay\",\"deleted\":false,\"data\":\($0)}" }
    lines += [
      #"{"type":"overlay","deleted":true,"data":{"id":"","kind":"pinyin","code":"he'cheng","word":"合成旧词","weight":0,"revision":1,"updated_at":"2026-09-08T00:00:00Z","user_inserted":false}}"#,
      #"{"type":"position","data":{"context":"quick:snapshot","code":"snapshot","word":"合成词条","position":2}}"#,
      #"{"type":"selection","data":{"context":"quick:snapshot","code":"snapshot","word":"合成词条","count":2}}"#
    ]
    let body = Data((lines.joined(separator: "\n") + "\n").utf8)
    let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    let footer = try JSONSerialization.data(withJSONObject: ["type": "footer", "records": lines.count, "sha256": digest])
    let file = root.appendingPathComponent("source.ndjson")
    try (body + footer + Data([10])).write(to: file)
    var snapshot = try BackendPreparedSnapshot(copying: file)
    func stage(_ identifier: String) throws -> MSIMEPreparedDictionarySnapshot {
      let stream = try BackendSnapshotRecordStream(snapshot: snapshot)
      let recordCount = snapshot.envelope.overlays + snapshot.envelope.positions + snapshot.envelope.selections
      return try DictionarySnapshotBridge.prepare(resources: resources, user: user, identifier: identifier,
        contentIdentifier: String(repeating: "a", count: 128), maximumRecords: UInt(recordCount),
        preparedOptions: preparedOptions,
        nextRecord: { failure in
          do { return try stream.next() }
          catch { failure?.pointee = error as NSError; return nil }
        })
    }
    let identifier = UUID().uuidString
    let prepared = try stage(identifier)
    XCTAssertEqual(prepared.identifier, identifier)
    let revision = try prepared.stateRevision()
    XCTAssertEqual(revision.count, 64)
    XCTAssertEqual(try prepared.stateRevision(), revision)
    let identical = try stage(UUID().uuidString)
    XCTAssertEqual(try identical.stateRevision(), revision)
    try DictionarySnapshotBridge.discardInactive(identifier: identical.identifier, user: user)
    try session.activateDictionarySnapshot(prepared, expectedVersion: originalVersion)
    let activatedVersion = try session.localDictionaryStateVersion()
    XCTAssertNotEqual(activatedVersion, originalVersion)
    XCTAssertTrue(activatedVersion.hasPrefix("local-v1:" + identifier + ":"))
    let page = try session.personalEntries(atOffset: 0)
    let stagedEntries = try XCTUnwrap(page["entries"] as? [[String: Any]])
    XCTAssertEqual(stagedEntries.count, 4)
    XCTAssertTrue(stagedEntries.contains { $0["kind"] as? String == "english" && $0["value"] as? String == "Snapshot" })
    let countedBody = Data(String(decoding: body, as: UTF8.self).replacingOccurrences(of: "\"count\":2", with: "\"count\":3").utf8)
    let countedDigest = SHA256.hash(data: countedBody).map { String(format: "%02x", $0) }.joined()
    let countedFooter = try JSONSerialization.data(withJSONObject: ["type": "footer", "records": lines.count, "sha256": countedDigest])
    try (countedBody + countedFooter + Data([10])).write(to: file)
    snapshot = try BackendPreparedSnapshot(copying: file)
    let counted = try stage(UUID().uuidString)
    XCTAssertEqual(try counted.stateRevision(), activatedVersion.split(separator: ":").last.map(String.init))
    try session.activateDictionarySnapshot(counted, expectedVersion: activatedVersion)
    let countedVersion = try session.localDictionaryStateVersion()
    XCTAssertNotEqual(countedVersion, activatedVersion, "Selection-only changes must invalidate the local version")
    // Simulate corruption after preview. Engine must roll back even though the
    // overlay and both candidate records arrive before the missing footer.
    try body.write(to: snapshot.url)
    let failedIdentifier = UUID().uuidString
    XCTAssertThrowsError(try stage(failedIdentifier))
    XCTAssertEqual(try session.localDictionaryStateVersion(), countedVersion)
  }
}
