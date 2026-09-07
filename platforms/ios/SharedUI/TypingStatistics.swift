import Foundation
import Darwin

struct TypingStatistics: Codable {
  var enabled = true
  var total = 0
  var days: [String: Int] = [:]

  static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }

  func count(on date: Date, calendar: Calendar = .current) -> Int {
    days[Self.dayKey(date, calendar: calendar)] ?? 0
  }
}

// The keyboard writes only aggregate counts, never document text or preedit. A separate lock
// file serializes extension/app processes, including reset and enable/disable transactions.
struct TypingStatisticsStore {
  let directory: URL?

  init(directory: URL? = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.app.msime.ios")) {
    self.directory = directory
  }

  private func transaction<T>(write: Bool, _ body: (inout TypingStatistics) -> T) throws -> T {
    guard let directory else { throw CocoaError(.fileNoSuchFile) }
    let lockURL = directory.appendingPathComponent("typing-statistics.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
    defer { flock(descriptor, LOCK_UN) }
    let url = directory.appendingPathComponent("typing-statistics.json")
    var value = TypingStatistics()
    if FileManager.default.fileExists(atPath: url.path) {
      value = try JSONDecoder().decode(TypingStatistics.self, from: Data(contentsOf: url))
    }
    let result = body(&value)
    if write { try JSONEncoder().encode(value).write(to: url, options: .atomic) }
    return result
  }

  func load() throws -> TypingStatistics {
    try transaction(write: false) { $0 }
  }

  func record(_ text: String, at date: Date = Date(), calendar: Calendar = .current) throws {
    let count = text.filter { !$0.isWhitespace }.count
    guard count > 0 else { return }
    try transaction(write: true) { value in
      guard value.enabled else { return }
      value.total += count
      let key = TypingStatistics.dayKey(date, calendar: calendar)
      value.days[key, default: 0] += count
      // Keep daily detail bounded; lifetime total is independent of retained history.
      for key in value.days.keys.sorted().dropLast(366) { value.days.removeValue(forKey: key) }
    }
  }

  func setEnabled(_ enabled: Bool) throws {
    try transaction(write: true) { $0.enabled = enabled }
  }

  func reset() throws {
    try transaction(write: true) { value in
      value.total = 0
      value.days = [:]
    }
  }
}
