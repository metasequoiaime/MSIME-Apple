import Foundation
import SQLite3

/// 表情目录与最近使用。
///
/// The engine already indexes these for pinyin search, and the same table carries a category and a
/// sort order, so browsing needs no data of its own -- `others.db` ships with the keyboard either
/// way. Read once and kept: 1935 rows is small, and the panel is reopened constantly.
enum EmojiCatalog {
  struct Section {
    let title: String
    let emoji: [String]
  }

  /// Unicode's own group order. Sorting the groups by their rows' sort_order would not reproduce it:
  /// Symbols spans 1420-1935 and Flags 1644-1913, so the two interleave.
  private static let groups = [
    ("Smileys and emotion", "笑脸"),
    ("People and body", "人物"),
    ("Animals and nature", "动物"),
    ("Food and drink", "食物"),
    ("Travel and places", "旅行"),
    ("Activities", "活动"),
    ("Objects", "物品"),
    ("Symbols", "符号"),
    ("Flags", "旗帜"),
  ]

  static let sections: [Section] = load()

  private static func load() -> [Section] {
    // Bundle(for:) rather than Bundle.main: in the extension the two agree, but under the unit
    // tests main is the host app and the database travels with the test bundle.
    let bundle = Bundle(for: KeyboardEmojiPickerView.self)
    guard let path = bundle.path(forResource: "others", ofType: "db") else { return [] }
    var handle: OpaquePointer?
    guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(handle)
      return []
    }
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, "SELECT category, emoji FROM emoji ORDER BY sort_order", -1,
                             &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    var byCategory: [String: [String]] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let category = sqlite3_column_text(statement, 0),
            let emoji = sqlite3_column_text(statement, 1) else { continue }
      byCategory[String(cString: category), default: []].append(String(cString: emoji))
    }
    return groups.compactMap { category, title in
      guard let emoji = byCategory[category], !emoji.isEmpty else { return nil }
      return Section(title: title, emoji: emoji)
    }
  }
}

/// 最近使用的表情，存在 App Group 里，和键盘的其他偏好放一起。
struct EmojiRecents {
  static let key = "emojiRecents"
  static let limit = 24
  private static var defaults: UserDefaults { KeyboardFeedbackPreference.defaults }

  static var stored: [String] {
    defaults.stringArray(forKey: key) ?? []
  }

  /// Most recent first, and an emoji already in the list moves rather than repeats.
  static func record(_ emoji: String) {
    var recents = stored.filter { $0 != emoji }
    recents.insert(emoji, at: 0)
    defaults.set(Array(recents.prefix(limit)), forKey: key)
  }
}
