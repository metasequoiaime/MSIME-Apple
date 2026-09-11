import Foundation
import CryptoKit
import XCTest

final class DictionarySnapshotQueueTests: XCTestCase {
  private let first = "local-v1:legacy:" + String(repeating: "a", count: 64)
  private let second = "local-v1:legacy:" + String(repeating: "b", count: 64)
  private func fixture(_ action: (DictionarySnapshotQueue, URL, String, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("selected.ndjson")
    let data = Data("synthetic opaque handoff file".utf8)
    try data.write(to: file)
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let queue = DictionarySnapshotQueue(directory: root)
    try queue.publishLocalVersion(first)
    try action(queue, file, hash, root)
  }
  private func enqueue(_ queue: DictionarySnapshotQueue, _ file: URL, _ hash: String) throws -> UUID {
    try queue.enqueue(file: file, accountID: "synthetic-account", cloudRevision: 7, expectedLocalVersion: first, fileSHA256: hash)
  }
  func testSingleWorkerAndResumeKeepsRequestIdentity() throws {
    try fixture { queue, file, hash, root in
      let id = try enqueue(queue, file, hash)
      var lease: DictionarySnapshotQueue.WorkerLease? = try queue.acquireWorkerLease()
      XCTAssertThrowsError(try DictionarySnapshotQueue(directory: root).acquireWorkerLease())
      XCTAssertEqual(try queue.claim(using: XCTUnwrap(lease))?.id, id)
      lease = nil
      let restarted = DictionarySnapshotQueue(directory: root)
      let newLease = try restarted.acquireWorkerLease()
      let request = try XCTUnwrap(restarted.claim(using: newLease))
      XCTAssertEqual(request.id, id)
      XCTAssertEqual(request.status, .preparing)
      XCTAssertTrue(try restarted.complete(id: id, using: newLease, currentVersion: first, alreadyApplied: false) { second })
      XCTAssertEqual(try restarted.read().request?.status, .applied)
      XCTAssertEqual(try restarted.read().localVersion, second)
      XCTAssertFalse(FileManager.default.fileExists(atPath: try restarted.fileURL(for: request).path))
    }
  }
  func testLocalChangesRejectApplicationAndRemoveTransferFile() throws {
    try fixture { queue, file, hash, _ in
      let id = try enqueue(queue, file, hash)
      let lease = try queue.acquireWorkerLease()
      let request = try XCTUnwrap(queue.claim(using: lease))
      XCTAssertFalse(try queue.complete(id: id, using: lease, currentVersion: second, alreadyApplied: false) {
        XCTFail("stale snapshot applied"); return self.second
      })
      XCTAssertEqual(try queue.read().request?.status, .conflict)
      XCTAssertFalse(FileManager.default.fileExists(atPath: try queue.fileURL(for: request).path))
    }
  }
  func testCancellationRejectsLateCompletionAndIsAccountScoped() throws {
    try fixture { queue, file, hash, _ in
      let id = try enqueue(queue, file, hash)
      let lease = try queue.acquireWorkerLease()
      _ = try queue.claim(using: lease)
      try queue.cancel(accountID: "different-account")
      XCTAssertEqual(try queue.read().request?.status, .preparing)
      try queue.cancel(accountID: "synthetic-account")
      XCTAssertThrowsError(try queue.complete(id: id, using: lease, currentVersion: first, alreadyApplied: false) {
        XCTFail("cancelled snapshot applied"); return self.second
      })
      XCTAssertEqual(try queue.read().request?.status, .cancelled)
    }
  }
  func testPublishedButUnacknowledgedRequestIsNotReapplied() throws {
    try fixture { queue, file, hash, _ in
      let id = try enqueue(queue, file, hash)
      let lease = try queue.acquireWorkerLease()
      _ = try queue.claim(using: lease)
      var applications = 0
      XCTAssertThrowsError(try queue.complete(id: id, using: lease, currentVersion: first, alreadyApplied: false) {
        applications += 1
        throw CocoaError(.fileWriteUnknown) // Simulate failure after durable Engine publication.
      })
      XCTAssertEqual(try queue.read().request?.status, .preparing)
      XCTAssertTrue(try queue.complete(id: id, using: lease, currentVersion: second, alreadyApplied: true) {
        applications += 1; return self.second
      })
      XCTAssertEqual(applications, 1)
      XCTAssertEqual(try queue.read().request?.status, .applied)
    }
  }
  func testDurableReceiptReconcilesCancellationAfterLostAcknowledgement() throws {
    try fixture { queue, file, hash, _ in
      let id = try enqueue(queue, file, hash)
      let lease = try queue.acquireWorkerLease()
      let request = try XCTUnwrap(queue.claim(using: lease))
      XCTAssertThrowsError(try queue.complete(id: id, using: lease, currentVersion: first, alreadyApplied: false) {
        throw CocoaError(.fileWriteUnknown)
      })
      try queue.cancel(accountID: "synthetic-account")
      let published = "local-v1:" + id.uuidString + ":" + String(repeating: "b", count: 64)
      try queue.publishLocalVersion(published)
      XCTAssertEqual(try queue.read().request?.status, .applied)
      XCTAssertEqual(try queue.read().localVersion, published)
      XCTAssertFalse(FileManager.default.fileExists(atPath: try queue.fileURL(for: request).path))
    }
  }
  func testChangedFileAndBusyQueueDoNotReplaceExistingRequest() throws {
    try fixture { queue, file, hash, _ in
      try Data("changed source".utf8).write(to: file)
      XCTAssertThrowsError(try enqueue(queue, file, hash))
      XCTAssertNil(try queue.read().request)
      let data = Data("synthetic opaque handoff file".utf8)
      try data.write(to: file)
      let id = try enqueue(queue, file, hash)
      XCTAssertThrowsError(try enqueue(queue, file, hash))
      XCTAssertEqual(try queue.read().request?.id, id)
      try queue.fail(id: id)
      XCTAssertEqual(try queue.read().request?.status, .failed)
    }
  }
}
