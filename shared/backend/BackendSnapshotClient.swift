import Foundation
import CoreFoundation
import CryptoKit

/// Validates transport framing and checksum, without claiming that every dictionary
/// operation is semantically valid. Engine staging must succeed before activation.
struct BackendSnapshotEnvelope: Sendable {
  let revision: Int64
  let sha256: String
  let records: Int
  let entries: Int
  let overlays: Int
  let positions: Int
  let selections: Int

  static func inspect(_ file: URL) throws -> Self {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hash = SHA256()
    var line = Data()
    var count = 0, bytes = 0, category = -1
    var totals = [Int](repeating: 0, count: 5)
    var revision: Int64?
    var finished = false
    var checksum: String?
    let bad = BackendAccountClient.Failure(status: 400)
    func integer(_ value: Any?) throws -> Int64 {
      guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            !["f", "d"].contains(String(cString: number.objCType)),
            let result = Int64(number.stringValue) else { throw bad }
      return result
    }
    func record(_ data: Data) throws {
      try Task.checkCancellation()
      guard !finished, !data.isEmpty, data.count < 65536, String(data: data, encoding: .utf8) != nil,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String else { throw bad }
      if type == "footer" {
        guard revision != nil, Set(object.keys) == ["type", "records", "sha256"],
              try integer(object["records"]) == Int64(count),
              let digest = object["sha256"] as? String,
              digest == hash.finalize().map({ String(format: "%02x", $0) }).joined() else { throw bad }
        checksum = digest; finished = true; return
      }
      let next: Int
      switch type {
      case "header":
        guard count == 0, Set(object.keys) == ["type", "format", "version", "revision"],
              object["format"] as? String == "msime-dictionary-snapshot",
              try integer(object["version"]) == 1 else { throw bad }
        let value = try integer(object["revision"])
        guard value >= 0 else { throw bad }
        revision = value; next = 0
      case "entry", "overlay", "position", "selection":
        guard revision != nil, object["data"] is [String: Any] else { throw bad }
        if type == "overlay" {
          guard Set(object.keys) == ["type", "data", "deleted"], let deleted = object["deleted"] as? NSNumber,
                CFGetTypeID(deleted) == CFBooleanGetTypeID() else { throw bad }
        } else { guard Set(object.keys) == ["type", "data"] else { throw bad } }
        next = ["entry": 1, "overlay": 2, "position": 3, "selection": 4][type]!
      default: throw bad
      }
      guard next >= category else { throw bad }
      category = next; totals[next] += 1; count += 1
      hash.update(data: data); hash.update(data: Data([10]))
    }
    while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
      bytes += chunk.count
      guard bytes <= 512 * 1024 * 1024 else { throw bad }
      var start = chunk.startIndex
      for index in chunk.indices where chunk[index] == 10 {
        line.append(chunk[start..<index])
        try record(line)
        line.removeAll(keepingCapacity: true)
        start = chunk.index(after: index)
      }
      line.append(chunk[start..<chunk.endIndex])
      guard line.count < 65536 else { throw bad }
    }
    if !line.isEmpty { try record(line) }
    guard finished, let revision, let checksum else { throw bad }
    return .init(revision: revision, sha256: checksum, records: count, entries: totals[1], overlays: totals[2], positions: totals[3], selections: totals[4])
  }
}

extension BackendAccountClient {
  struct DownloadedSnapshot: Sendable { let url: URL; let envelope: BackendSnapshotEnvelope }
  func dictionarySnapshot(token: String) async throws -> DownloadedSnapshot {
    let url = try await download("/v1/users/me/dictionary/snapshot", token: token,
      filename: "msime-dictionary-snapshot.ndjson", maximumBytes: 512 * 1024 * 1024, mediaType: "application/x-ndjson")
    do {
      let envelope = try BackendSnapshotEnvelope.inspect(url)
      return .init(url: url, envelope: envelope)
    } catch {
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
      throw error
    }
  }
}
