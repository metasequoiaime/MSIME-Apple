import XCTest
@testable import MSIMEBackend

final class BackendTelemetryClientTests: XCTestCase {
  func testCrashIsBoundedAndPersistedSynchronously() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("msime-telemetry-test-\(UUID().uuidString)")
    let queue = directory.appendingPathComponent("events.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    BackendTelemetryClient.persistCrash(message: String(repeating: "m", count: 3000),
                                        stack: String(repeating: "s", count: 20_000), queueURL: queue)
    let data = try Data(contentsOf: queue)
    let events = try JSONDecoder().decode([BackendTelemetryEvent].self, from: data)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].message?.count, 2048)
    XCTAssertEqual(events[0].stack?.count, 12_000)
  }

  func testManyLargeCrashesStayWithinBoundAndKeepNewest() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("msime-telemetry-test-\(UUID().uuidString)")
    let queue = directory.appendingPathComponent("events.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    for index in 0..<10 {
      BackendTelemetryClient.persistCrash(message: "crash \(index)", stack: String(repeating: "frame\n", count: 2_000), queueURL: queue)
    }
    let data = try Data(contentsOf: queue)
    XCTAssertLessThanOrEqual(data.count, BackendTelemetryClient.maxPayloadBytes)
    let events = try JSONDecoder().decode([BackendTelemetryEvent].self, from: data)
    XCTAssertGreaterThan(events.count, 1)
    XCTAssertEqual(events.last?.message, "crash 9")
    XCTAssertEqual(BackendTelemetryClient.readQueue(queue).last?.message, "crash 9")
  }

  func testOversizedSingleEventHasStackShortened() throws {
    // Control characters escape to \uXXXX, so 12 000 of them exceed 64 KiB on their own.
    let event = BackendTelemetryEvent(kind: "crash", platform: "test", version: "1", message: "big",
                                      stack: String(repeating: "\u{1}", count: 12_000))
    let data = try XCTUnwrap(BackendTelemetryClient.boundedEncode([event]))
    XCTAssertLessThanOrEqual(data.count, BackendTelemetryClient.maxPayloadBytes)
    let events = try JSONDecoder().decode([BackendTelemetryEvent].self, from: data)
    XCTAssertEqual(events.map(\.message), ["big"])
    XCTAssertLessThan(events[0].stack?.count ?? 0, 12_000)
  }

  func testQueueOverPayloadBoundIsReadNotDiscarded() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("msime-telemetry-test-\(UUID().uuidString)")
    let queue = directory.appendingPathComponent("events.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let events = (0..<10).map { BackendTelemetryEvent(kind: "crash", platform: "test", version: "1", message: "old \($0)",
                                                       stack: String(repeating: "s", count: 12_000)) }
    try JSONEncoder().encode(events).write(to: queue)
    BackendTelemetryClient.persistCrash(message: "new", queueURL: queue)
    let kept = try JSONDecoder().decode([BackendTelemetryEvent].self, from: Data(contentsOf: queue))
    XCTAssertEqual(kept.last?.message, "new")
    XCTAssertEqual(kept.dropLast().last?.message, "old 9")
  }
}
