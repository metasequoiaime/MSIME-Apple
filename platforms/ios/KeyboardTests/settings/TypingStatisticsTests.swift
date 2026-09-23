import XCTest

final class TypingStatisticsTests: XCTestCase {
  func testCountsCommittedCharactersAcrossDaysAndPreservesPauseOnReset() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TypingStatisticsStore(directory: directory)
    try store.setEnabled(true)
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

  func testUnicodeCategoriesAndLegacyMigration() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TypingStatisticsStore(directory: directory)
    let date = Date()
    let key = TypingStatistics.dayKey(date)
    let old: [String: Any] = ["enabled": true, "total": 12, "days": [key: 12]]
    try JSONSerialization.data(withJSONObject: old).write(to: directory.appendingPathComponent("typing-statistics.json"))
    XCTAssertEqual(try store.load().breakdown(on: nil).characters["unknown"], 12)
    try store.record("汉𠮷Aée\u{301}９1，!👨‍👩‍👧‍👦1️⃣あЖ+ \n", source: .nineKey, at: date)
    var snapshot = try store.load()
    let detail = snapshot.breakdown(on: [date])
    XCTAssertEqual(detail.characters["han"], 2)
    XCTAssertEqual(detail.characters["latin"], 3)
    XCTAssertEqual(detail.characters["number"], 2)
    XCTAssertEqual(detail.characters["punctuation"], 2)
    XCTAssertEqual(detail.characters["emoji"], 2)
    XCTAssertEqual(detail.characters["otherLetter"], 2)
    XCTAssertEqual(detail.characters["symbol"], 1)
    XCTAssertEqual(detail.characters["unknown"], 12)
    XCTAssertEqual(detail.sources["nineKey"], 14)
    XCTAssertEqual(detail.sources["unknown"], 12)
    XCTAssertEqual(snapshot.total, 26)
    try store.record("abc", source: .english, at: date)
    try store.record("日期", source: .local, at: date)
    snapshot = try store.load()
    XCTAssertEqual(snapshot.detail.sources["english"], 3)
    XCTAssertEqual(snapshot.detail.sources["local"], 2)
    XCTAssertEqual(snapshot.breakdown(on: nil).characters.values.reduce(0, +), snapshot.total)
    XCTAssertEqual(snapshot.breakdown(on: nil).sources.values.reduce(0, +), snapshot.total)
    try store.setEnabled(false)
    try store.record("暂停", source: .shuangpin)
    XCTAssertEqual(try store.load().total, 31)
    try store.reset()
    snapshot = try store.load()
    XCTAssertTrue(snapshot.detail.characters.isEmpty)
    XCTAssertTrue(snapshot.dailyDetails.isEmpty)
    XCTAssertFalse(snapshot.enabled)
  }

  func testConcurrentWritersAndBoundedDailyHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try TypingStatisticsStore(directory: directory).setEnabled(true)
    DispatchQueue.concurrentPerform(iterations: 100) { _ in
      try! TypingStatisticsStore(directory: directory).record("字")
    }
    let store = TypingStatisticsStore(directory: directory)
    XCTAssertEqual(try store.load().total, 100)
    for offset in 1...370 {
      try store.record("字", at: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }
    XCTAssertEqual(try store.load().days.count, 366)
    let snapshot = try store.load()
    XCTAssertEqual(snapshot.total, 470)
    XCTAssertEqual(snapshot.dailyDetails.count, 366)
    XCTAssertEqual(snapshot.detail.characters["han"], 470)
    XCTAssertEqual(snapshot.detail.sources["unknown"], 470)
  }

  /// Retention prunes daily records older than the window and never the lifetime counts; it survives a reset like the pause does.
  func testRetentionPrunesDailyRecordsButNotTheLifetimeCounts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TypingStatisticsStore(directory: directory)
    try store.setEnabled(true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23))!
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    for offset in [-40, -30, -29, 0] { try store.record("字", at: day(offset), calendar: calendar) }

    try store.setRetention(30, today: today, calendar: calendar)
    var snapshot = try store.load()
    XCTAssertEqual(snapshot.retentionDays, 30)
    XCTAssertEqual(snapshot.days.keys.sorted(), ["2026-08-24", "2026-08-25", "2026-09-23"], "The shared store keeps the day 30 days back and everything after it")
    XCTAssertEqual(Set(snapshot.dailyDetails.keys), Set(snapshot.days.keys))
    XCTAssertEqual(snapshot.total, 4)
    XCTAssertEqual(snapshot.detail.characters["han"], 4)

    // Recording applies the window from the day being recorded.
    try store.record("字", at: day(30), calendar: calendar)
    XCTAssertEqual(try store.load().days.keys.sorted(), ["2026-09-23", "2026-10-23"])

    try store.reset()
    XCTAssertEqual(try store.load().retentionDays, 30)
    try store.setRetention(nil, today: today, calendar: calendar)
    for offset in [-100, 0] { try store.record("字", at: day(offset), calendar: calendar) }
    snapshot = try store.load()
    XCTAssertNil(snapshot.retentionDays)
    XCTAssertEqual(snapshot.days.count, 2)
  }

  func testActiveTimeAndHoursAreRecordedByTheSharedStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TypingStatisticsStore(directory: directory)
    try store.setEnabled(true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 14))!
    try store.record("水杉", source: .quanpin, at: date, calendar: calendar)
    Thread.sleep(forTimeInterval: 0.05)
    try store.record("输入法", source: .quanpin, at: date, calendar: calendar)
    let snapshot = try store.load()
    XCTAssertGreaterThan(snapshot.dailyActiveMs["2026-09-23"] ?? 0, 0, "间隔不到 10 秒的两次上屏算活跃时间")
    XCTAssertLessThan(snapshot.dailyActiveMs["2026-09-23"] ?? 0, 10_000)
    XCTAssertEqual(snapshot.dailyHours["2026-09-23"]?.count, 24)
    XCTAssertEqual(snapshot.dailyHours["2026-09-23"]?[14], 5)

    try store.reset()
    let cleared = try store.load()
    XCTAssertTrue(cleared.dailyActiveMs.isEmpty)
    XCTAssertTrue(cleared.dailyHours.isEmpty)
  }

  func testRetentionTheSwiftStoreWroteSurvivesTheSharedStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = TypingStatistics.dayKey(Date())
    let old: [String: Any] = ["enabled": true, "total": 3, "days": [key: 3], "retentionDays": 90]
    let url = directory.appendingPathComponent("typing-statistics.json")
    try JSONSerialization.data(withJSONObject: old).write(to: url)
    let store = TypingStatisticsStore(directory: directory)
    try store.record("字")
    let snapshot = try store.load()
    XCTAssertEqual(snapshot.retentionDays, 90)
    XCTAssertEqual(snapshot.total, 4)
    let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(document["retention"] as? String, "90d")
    XCTAssertNil(document["retentionDays"])
  }

  func testLongCommitsAreSplitOnCharacterBoundaries() throws {
    let family = "👨‍👩‍👧‍👦"
    let text = String(repeating: family, count: 1_000)
    let chunks = TypingStatisticsStore.chunks(text)
    XCTAssertGreaterThan(chunks.count, 1)
    XCTAssertEqual(chunks.joined(), text)
    XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 8_000 && $0.allSatisfy { $0 == Character(family) } })

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TypingStatisticsStore(directory: directory)
    try store.setEnabled(true)
    try store.record(String(repeating: "字", count: 20_000))
    XCTAssertEqual(try store.load().total, 20_000)
  }

  func testRhythmMatchesTheSharedPage() throws {
    let fixture: [String: Any] = [
      "total": 1_000,
      "days": ["2026-08-30": 100, "2026-08-31": 300, "2026-09-01": 200, "2026-09-03": 400],
      "dailyDetails": [
        "2026-08-31": ["characters": ["han": 200, "latin": 40, "otherLetter": 20, "number": 40]],
        "2026-09-01": ["characters": ["han": 100, "punctuation": 100]],
        "2026-09-03": ["characters": ["han": 300, "emoji": 100]],
      ],
      "dailyActiveMs": ["2026-08-31": 120_000, "2026-09-01": 30_000, "2026-09-03": 240_000],
      "dailyHours": ["2026-09-03": Array(repeating: 0, count: 23) + [400], "2026-09-01": [1]],
      "retention": "180d",
    ]
    let statistics = try JSONDecoder().decode(
      TypingStatistics.self, from: JSONSerialization.data(withJSONObject: fixture))
    XCTAssertEqual(statistics.retentionDays, 180)

    let today = statistics.activity(todayKey: "2026-09-03")
    XCTAssertEqual(today.recordedDays, 4)
    XCTAssertEqual(today.averagePerDay, 250)
    XCTAssertEqual(today.currentStreak, 1)
    XCTAssertEqual(today.longestStreak, 3, "跨月的连续天数不能按字符串数字比较")
    XCTAssertEqual(today.bestDay, "2026-09-03")
    XCTAssertEqual(today.bestDayCharacters, 400)
    XCTAssertEqual(today.todayActiveMs, 240_000)
    XCTAssertEqual(today.todaySpeed, 75, accuracy: 0.001, "表情不算进速度")
    XCTAssertEqual(today.averageSpeed, Double(260 + 100 + 300) / 6.5, accuracy: 0.001)
    XCTAssertEqual(today.fastestDay, "2026-08-31", "活跃不到一分钟的那天不参与最快")
    XCTAssertEqual(today.fastestSpeed, 130, accuracy: 0.001)
    XCTAssertEqual(today.todayHours?.last, 400)
    XCTAssertTrue(today.hasActivity)

    // Today with nothing typed yet keeps yesterday's streak; a malformed hour list is not drawn.
    XCTAssertEqual(statistics.activity(todayKey: "2026-09-04").currentStreak, 1)
    XCTAssertEqual(statistics.activity(todayKey: "2026-09-05").currentStreak, 0)
    XCTAssertEqual(statistics.activity(todayKey: "2026-09-02").currentStreak, 3)
    XCTAssertNil(statistics.activity(todayKey: "2026-09-01").todayHours)
    XCTAssertFalse(TypingStatistics().activity(todayKey: "2026-09-01").hasActivity)

    XCTAssertEqual(TypingStatistics.addDays("2028-02-28", 1), "2028-02-29")
    XCTAssertEqual(TypingStatistics.addDays("2026-02-28", 1), "2026-03-01")
    XCTAssertEqual(TypingStatistics.addDays("2026-01-01", -1), "2025-12-31")
    XCTAssertEqual(TypingStatistics.addDays("not-a-day", 1), "not-a-day")
    XCTAssertEqual(TypingActivity.formatActiveTime(0), "0分")
    XCTAssertEqual(TypingActivity.formatActiveTime(45_000), "45秒")
    XCTAssertEqual(TypingActivity.formatActiveTime(12 * 60_000), "12分")
    XCTAssertEqual(TypingActivity.formatActiveTime(60 * 60_000), "1小时")
    XCTAssertEqual(TypingActivity.formatActiveTime(83 * 60_000), "1小时23分")
  }

  func testAvailabilityTellsAnEmptyRunApartFromABrokenOne() throws {
    // The three answers to "why is this empty" are different actions for the reader, so the store
    // has to distinguish them rather than return one emptiness.
    XCTAssertEqual(TypingStatisticsStore(directory: nil).availability(), .containerUnavailable)

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("stats-availability-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = TypingStatisticsStore(directory: directory)
    XCTAssertEqual(store.availability(), .neverWritten)

    try store.setEnabled(true)
    try store.record("水杉")
    guard case .ready(let lastWritten) = store.availability() else {
      return XCTFail("A written store still reported that the keyboard had never written.")
    }
    XCTAssertNotNil(lastWritten)
  }

  func testMovesLegacyAppGroupStatisticsIntoTheSharedTauriStateDirectory() throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("stats-migration-\(UUID().uuidString)")
    let sharedState = container.appendingPathComponent("MSIME", isDirectory: true)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: container) }

    let legacy = TypingStatisticsStore(directory: container)
    try legacy.setEnabled(true)
    try legacy.record("迁移", source: .quanpin)
    let store = TypingStatisticsStore(directory: sharedState, legacyDirectory: container)
    guard case .ready = store.availability() else {
      return XCTFail("Legacy statistics should be reported before the first migration read.")
    }
    let snapshot = try store.load()

    XCTAssertEqual(snapshot.total, 2)
    XCTAssertEqual(snapshot.detail.sources["quanpin"], 2)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: sharedState.appendingPathComponent("typing-statistics.json").path))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: container.appendingPathComponent("typing-statistics.json").path))
  }
}
