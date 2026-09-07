import XCTest

final class TypingStatisticsTests: XCTestCase {
  func testCountsCommittedCharactersAcrossDaysAndPreservesPauseOnReset() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TypingStatisticsStore(directory: directory)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    try store.record("你好 A1，👨‍👩‍👧‍👦e\u{301}\n\t", at: today, calendar: calendar)
    try store.record("次日", at: tomorrow, calendar: calendar)
    var snapshot = try store.load()
    XCTAssertEqual(snapshot.total, 9)
    XCTAssertEqual(snapshot.count(on: today, calendar: calendar), 7)
    XCTAssertEqual(snapshot.count(on: tomorrow, calendar: calendar), 2)
    try store.setEnabled(false)
    try store.record("不计入", at: today, calendar: calendar)
    XCTAssertEqual(try store.load().total, 9)
    try store.reset()
    snapshot = try store.load()
    XCTAssertEqual(snapshot.total, 0)
    XCTAssertTrue(snapshot.days.isEmpty)
    XCTAssertFalse(snapshot.enabled)
    try store.setEnabled(true)
    try store.record("重新开始", at: today, calendar: calendar)
    XCTAssertEqual(try TypingStatisticsStore(directory: directory).load().total, 4)
    let persisted = try String(contentsOf: directory.appendingPathComponent("typing-statistics.json"), encoding: .utf8)
    XCTAssertFalse(persisted.contains("重新开始"))
  }

  func testConcurrentWritersAndBoundedDailyHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    DispatchQueue.concurrentPerform(iterations: 100) { _ in
      try! TypingStatisticsStore(directory: directory).record("字")
    }
    let store = TypingStatisticsStore(directory: directory)
    XCTAssertEqual(try store.load().total, 100)
    for offset in 1...370 {
      try store.record("字", at: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }
    XCTAssertEqual(try store.load().days.count, 366)
    XCTAssertEqual(try store.load().total, 470)
  }
}
