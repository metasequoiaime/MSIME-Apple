import Foundation
import Darwin

enum TypingSource: String, CaseIterable {
  case quanpin, nineKey, shuangpin, ziranma, microsoft, shoudao, wubi, japanese, english, local, ai, reply, voice, unknown
  var title: String {
    switch self {
    case .quanpin: "全拼 26 键"
    case .nineKey: "全拼 9 键"
    case .shuangpin: "小鹤双拼"
    case .ziranma: "自然码双拼"
    case .microsoft: "微软双拼"
    case .shoudao: "Shoudao 双拼"
    case .wubi: "86 五笔"
    case .japanese: "日语罗马字"
    case .english: "英文键盘"
    case .local: "本地输入"
    case .ai: "AI 润色"
    case .reply: "高情商回复"
    case .voice: "语音输入"
    case .unknown: "历史未分类"
    }
  }
}

enum TypingCharacterKind: String, CaseIterable {
  case han, latin, otherLetter, number, punctuation, emoji, symbol, unknown
  var title: String {
    switch self {
    case .han: "汉字"
    case .latin: "拉丁字母"
    case .otherLetter: "其他文字"
    case .number: "数字"
    case .punctuation: "标点"
    case .emoji: "表情"
    case .symbol: "其他符号"
    case .unknown: "历史未分类"
    }
  }
  static func classify(_ character: Character) -> Self {
    let scalars = character.unicodeScalars
    guard let first = scalars.first else { return .symbol }
    let code = first.value
    if (0x3400...0x4DBF).contains(code) || (0x4E00...0x9FFF).contains(code)
      || (0xF900...0xFAFF).contains(code) || (0x20000...0x323AF).contains(code) { return .han }
    if scalars.contains(where: { $0.properties.isEmojiPresentation })
      || (scalars.contains(where: { $0.value == 0xFE0F || $0.value == 0x20E3 })
          && scalars.contains(where: { $0.properties.isEmoji })) { return .emoji }
    if first.properties.generalCategory == .decimalNumber { return .number }
    if character.isLetter {
      if (0x41...0x5A).contains(code) || (0x61...0x7A).contains(code)
        || (0xC0...0x24F).contains(code) || (0x1E00...0x1EFF).contains(code)
        || (0xAB30...0xAB6F).contains(code) || (0xFF21...0xFF3A).contains(code)
        || (0xFF41...0xFF5A).contains(code) { return .latin }
      return .otherLetter
    }
    return character.isPunctuation ? .punctuation : .symbol
  }
}

struct TypingBreakdown: Codable {
  var characters: [String: Int] = [:]
  var sources: [String: Int] = [:]
  mutating func merge(_ other: Self) {
    for (key, count) in other.characters { characters[key, default: 0] += count }
    for (key, count) in other.sources { sources[key, default: 0] += count }
  }
  func includingUnclassified(total: Int) -> Self {
    var result = self
    result.characters[TypingCharacterKind.unknown.rawValue, default: 0] += max(0, total - characters.values.reduce(0, +))
    result.sources[TypingSource.unknown.rawValue, default: 0] += max(0, total - sources.values.reduce(0, +))
    return result
  }
}

struct TypingStatistics: Codable {
  var enabled = true
  var total = 0
  var days: [String: Int] = [:]
  var detail = TypingBreakdown()
  var dailyDetails: [String: TypingBreakdown] = [:]

  init() {}
  private enum CodingKeys: String, CodingKey { case enabled, total, days, detail, dailyDetails }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    total = try values.decodeIfPresent(Int.self, forKey: .total) ?? 0
    days = try values.decodeIfPresent([String: Int].self, forKey: .days) ?? [:]
    detail = try values.decodeIfPresent(TypingBreakdown.self, forKey: .detail) ?? TypingBreakdown()
    dailyDetails = try values.decodeIfPresent([String: TypingBreakdown].self, forKey: .dailyDetails) ?? [:]
  }
  static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }
  func count(on date: Date, calendar: Calendar = .current) -> Int {
    days[Self.dayKey(date, calendar: calendar)] ?? 0
  }
  func breakdown(on dates: [Date]?, calendar: Calendar = .current) -> TypingBreakdown {
    guard let dates else { return detail.includingUnclassified(total: total) }
    var result = TypingBreakdown()
    for date in dates {
      let key = Self.dayKey(date, calendar: calendar)
      result.merge((dailyDetails[key] ?? TypingBreakdown()).includingUnclassified(total: days[key] ?? 0))
    }
    return result
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

  func record(_ text: String, source: TypingSource = .unknown, at date: Date = Date(), calendar: Calendar = .current) throws {
    var addition = TypingBreakdown()
    for character in text where !character.isWhitespace {
      addition.characters[TypingCharacterKind.classify(character).rawValue, default: 0] += 1
    }
    let count = addition.characters.values.reduce(0, +)
    addition.sources[source.rawValue] = count
    guard count > 0 else { return }
    try transaction(write: true) { value in
      guard value.enabled else { return }
      value.total += count
      let key = TypingStatistics.dayKey(date, calendar: calendar)
      value.days[key, default: 0] += count
      value.detail.merge(addition)
      value.dailyDetails[key, default: TypingBreakdown()].merge(addition)
      // Keep daily detail bounded; lifetime total is independent of retained history.
      for key in value.days.keys.sorted().dropLast(366) {
        value.days.removeValue(forKey: key)
        value.dailyDetails.removeValue(forKey: key)
      }
    }
  }

  func setEnabled(_ enabled: Bool) throws {
    try transaction(write: true) { $0.enabled = enabled }
  }

  func reset() throws {
    try transaction(write: true) { value in
      value.total = 0
      value.days = [:]
      value.detail = TypingBreakdown()
      value.dailyDetails = [:]
    }
  }
}
