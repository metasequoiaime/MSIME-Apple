import Foundation

enum KeyboardEmojiCatalogError: Error {
  case invalidPage
}

/// Bounded host model for the Engine-owned Emoji catalog.
///
/// Android, iOS and the desktop panel all read the same verified `others.db` through the shared
/// host API. The keyboard keeps only the currently visible category page and never opens SQLite.
enum KeyboardEmojiCatalog {
  static let columns = 8
  static let pageSize = 64
  static let recentLimit = 24
  static let maximumItems = 4_096
  static let maximumCursor = 8_192

  struct Category: Equatable, Sendable {
    let group: String
    let title: String
  }

  struct Item: Equatable, Sendable {
    let text: String
    let annotation: String
    let group: String
  }

  struct Page: Equatable, Sendable {
    let items: [Item]
    let nextOffset: Int
    let complete: Bool
  }

  /// Unicode group order. Database row order interleaves Symbols and Flags.
  static let categories = [
    Category(group: "Smileys and emotion", title: "笑脸"),
    Category(group: "People and body", title: "人物"),
    Category(group: "Animals and nature", title: "动物"),
    Category(group: "Food and drink", title: "食物"),
    Category(group: "Travel and places", title: "旅行"),
    Category(group: "Activities", title: "活动"),
    Category(group: "Objects", title: "物品"),
    Category(group: "Symbols", title: "符号"),
    Category(group: "Flags", title: "旗帜"),
  ]

  static func loadPage(resources: String, category: Category, offset: Int) throws -> Page {
    guard offset >= 0, offset <= maximumCursor else { throw KeyboardEmojiCatalogError.invalidPage }
    let request = try JSONSerialization.data(withJSONObject: [
      "category": "",
      "group": category.group,
      "offset": offset,
      "limit": pageSize,
      "cursor": true,
    ])
    return try decodePage(
      try MetasequoiaInputSessionBridge.emojiCatalog(request: request, resources: resources),
      category: category,
      requestedOffset: offset)
  }

  static func decodePage(
    _ value: [String: Any], category: Category, requestedOffset: Int
  ) throws -> Page {
    guard requestedOffset >= 0, requestedOffset <= maximumCursor,
          let rows = value["items"] as? [[String: Any]], rows.count <= pageSize,
          let nextNumber = value["next_offset"] as? NSNumber,
          let complete = value["complete"] as? Bool else {
      throw KeyboardEmojiCatalogError.invalidPage
    }
    let nextOffset64 = nextNumber.int64Value
    guard nextNumber.doubleValue == Double(nextOffset64),
          nextOffset64 >= Int64(requestedOffset),
          nextOffset64 <= Int64(requestedOffset + pageSize),
          nextOffset64 <= Int64(maximumCursor),
          complete || nextOffset64 > Int64(requestedOffset) else {
      throw KeyboardEmojiCatalogError.invalidPage
    }
    let items = try rows.map { row -> Item in
      guard let text = row["text"] as? String,
            let annotation = row["annotation"] as? String,
            let group = row["group"] as? String,
            validText(text), validAnnotation(annotation), group == category.group else {
        throw KeyboardEmojiCatalogError.invalidPage
      }
      return Item(text: text, annotation: annotation, group: group)
    }
    return Page(items: items, nextOffset: Int(nextOffset64), complete: complete)
  }

  static func validRecent(_ value: String) -> Bool {
    validText(value)
  }

  private static func validText(_ value: String) -> Bool {
    !value.isEmpty && value.unicodeScalars.count <= 32 && value.utf8.count <= 256
      && !value.unicodeScalars.contains { $0.value == 0 }
  }

  private static func validAnnotation(_ value: String) -> Bool {
    value.unicodeScalars.count <= 1_024 && value.utf8.count <= 4_096
      && !value.unicodeScalars.contains { $0.value == 0 }
  }
}

enum KeyboardEmojiRecents {
  static let key = "emojiRecents"
  private static var defaults: UserDefaults { KeyboardFeedbackPreference.defaults }

  static var stored: [String] {
    normalize(defaults.stringArray(forKey: key) ?? [])
  }

  static func record(_ emoji: String) {
    guard KeyboardEmojiCatalog.validRecent(emoji) else { return }
    var recents = stored.filter { $0 != emoji }
    recents.insert(emoji, at: 0)
    defaults.set(Array(recents.prefix(KeyboardEmojiCatalog.recentLimit)), forKey: key)
  }

  static func normalize(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values where KeyboardEmojiCatalog.validRecent(value) && seen.insert(value).inserted {
      output.append(value)
      if output.count == KeyboardEmojiCatalog.recentLimit { break }
    }
    return output
  }
}
