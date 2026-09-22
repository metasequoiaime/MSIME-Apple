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
}
