import Foundation
import CryptoKit
import SQLite3
import XCTest

final class CloudSnapshotStagingTests: XCTestCase {
  func testValidatedStreamStagesEngineStateAndRejectsTruncatedFooter() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let resources = root.appendingPathComponent("resources")
    let user = root.appendingPathComponent("user")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    for name in ["msime.db", "english.db"] {
      var db: OpaquePointer?
      XCTAssertEqual(sqlite3_open(resources.appendingPathComponent(name).path, &db), SQLITE_OK)
      let schema = name == "msime.db"
        ? "CREATE TABLE quick_parases(key TEXT,value TEXT,weight INTEGER); CREATE INDEX idx_quick_parases_key_weight ON quick_parases(key,weight DESC); CREATE TABLE tbl_2_h(key TEXT,jp TEXT,value TEXT,weight INTEGER); CREATE TABLE wubi86(key TEXT,value TEXT,weight INTEGER);"
        : "CREATE TABLE english_words(word TEXT COLLATE BINARY NOT NULL,display TEXT NOT NULL,weight INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(word,display)) WITHOUT ROWID;"
      XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)
      sqlite3_close(db)
    }
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
    let snapshot = try BackendPreparedSnapshot(copying: file)
    func stage(_ identifier: String) throws -> MSIMEPreparedDictionarySnapshot {
      let stream = try BackendSnapshotRecordStream(snapshot: snapshot)
      return try DictionarySnapshotBridge.prepare(resources: resources, user: user, identifier: identifier,
        contentIdentifier: String(repeating: "a", count: 128), maximumRecords: UInt(snapshot.envelope.records),
        nextRecord: { failure in
          do { return try stream.next() }
          catch { failure?.pointee = error as NSError; return nil }
        })
    }
    let identifier = UUID().uuidString
    let prepared = try stage(identifier)
    XCTAssertEqual(prepared.identifier, identifier)
    let generation = user.appendingPathComponent("snapshot-generations").appendingPathComponent(identifier)
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(generation.appendingPathComponent("user/msime_user.db").path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    defer { sqlite3_close(db) }
    for (table, field) in [("user_dictionary_operations", "weight"), ("fixed_candidate_positions", "position"), ("candidate_selection_state", "selection_count")] {
      var query: OpaquePointer?
      let filter = field == "weight" ? " WHERE dictionary='quick'" : ""
      XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT \(field) FROM \(table)" + filter, -1, &query, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(query), SQLITE_ROW)
      XCTAssertEqual(sqlite3_column_int(query, 0), field == "weight" ? 100000 : 2)
      XCTAssertEqual(sqlite3_step(query), SQLITE_DONE)
      sqlite3_finalize(query)
    }
    for (sql, expected) in [
      ("SELECT COUNT(*) FROM user_dictionary_operations", 5),
      ("SELECT COUNT(*) FROM user_dictionary_operations WHERE dictionary='english' AND display='Snapshot' AND user_inserted=1", 1),
      ("SELECT COUNT(*) FROM user_dictionary_operations WHERE operation='delete' AND user_inserted=0 AND weight=0", 1)] {
      var query: OpaquePointer?
      XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &query, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(query), SQLITE_ROW)
      XCTAssertEqual(Int(sqlite3_column_int(query, 0)), expected)
      sqlite3_finalize(query)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: user.appendingPathComponent("active-user-generation").path))
    // Simulate corruption after preview. Engine must roll back even though the
    // overlay and both candidate records arrive before the missing footer.
    try body.write(to: snapshot.url)
    let failedIdentifier = UUID().uuidString
    XCTAssertThrowsError(try stage(failedIdentifier))
    XCTAssertFalse(FileManager.default.fileExists(atPath: user.appendingPathComponent("snapshot-generations").appendingPathComponent(failedIdentifier).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: generation.path))
  }
}
