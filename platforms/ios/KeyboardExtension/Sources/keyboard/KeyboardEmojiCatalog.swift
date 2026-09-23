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
    /// The shared catalog the group belongs to: empty for Emoji, `kaomoji` for 颜文字.
    var catalog = ""

    var isKaomoji: Bool { catalog == "kaomoji" }
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

  /// The kaomoji catalog has no groups of its own; the shared catalog answers every row under `All`.
  static let kaomoji = Category(group: "All", title: "颜文字", catalog: "kaomoji")

  static func loadPage(resources: String, category: Category, offset: Int) throws -> Page {
    guard offset >= 0, offset <= maximumCursor else { throw KeyboardEmojiCatalogError.invalidPage }
    let request = try JSONSerialization.data(withJSONObject: [
      "category": category.catalog,
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
            validText(text, kaomoji: category.isKaomoji), validAnnotation(annotation),
            group == category.group else {
        throw KeyboardEmojiCatalogError.invalidPage
      }
      return Item(text: text, annotation: annotation, group: group)
    }
    return Page(items: items, nextOffset: Int(nextOffset64), complete: complete)
  }

  /// Chinese names for the Engine's symbol parents; a parent the catalog adds later shows under its own name.
  static let symbolParentTitles = [
    "Punctuation": "标点", "Math": "数学", "Currency": "货币", "Arrows and lines": "箭头",
    "Stars and shapes": "形状", "Hearts": "爱心", "Letters": "字母", "Games": "游戏",
    "Culture": "文化", "Animals and nature": "自然", "People and activity": "人物", "More": "更多",
  ]
  /// The most rows one parent may hold; the largest shipped parent, Letters, has 567.
  static let maximumSymbols = 2_048

  /// The Engine's symbol parents in catalog order, each once.
  static func symbolParents(resources: String) throws -> [String] {
    let request = try JSONSerialization.data(withJSONObject: ["list_symbol_groups": true, "limit": 1])
    let value = try MetasequoiaInputSessionBridge.emojiCatalog(request: request, resources: resources)
    return try decodeSymbolParents(value)
  }

  static func decodeSymbolParents(_ value: [String: Any]) throws -> [String] {
    guard let rows = value["symbol_groups"] as? [[String: Any]], rows.count <= 1_024 else {
      throw KeyboardEmojiCatalogError.invalidPage
    }
    var parents: [String] = []
    for row in rows {
      guard let parent = row["parent"] as? String, !parent.isEmpty, validAnnotation(parent) else { continue }
      if !parents.contains(parent) { parents.append(parent) }
    }
    return parents
  }

  /// Every symbol under one parent, in catalog order. A symbol filed under two of the parent's subgroups appears once.
  static func loadSymbols(resources: String, parent: String) throws -> [String] {
    try collectSymbols { offset in
      let request = try JSONSerialization.data(withJSONObject: [
        "category": "symbols", "parent": parent, "offset": offset, "limit": 255, "cursor": true,
      ])
      return try MetasequoiaInputSessionBridge.emojiCatalog(request: request, resources: resources)
    }
  }

  static func collectSymbols(page: (Int) throws -> [String: Any]) throws -> [String] {
    var symbols: [String] = []
    var seen = Set<String>()
    var offset = 0
    while true {
      let value = try page(offset)
      guard let rows = value["items"] as? [[String: Any]], rows.count <= 255,
            let next = (value["next_offset"] as? NSNumber)?.intValue,
            let complete = value["complete"] as? Bool,
            complete || next > offset else {
        throw KeyboardEmojiCatalogError.invalidPage
      }
      for row in rows {
        guard let text = row["text"] as? String, validText(text) else { throw KeyboardEmojiCatalogError.invalidPage }
        if seen.insert(text).inserted { symbols.append(text) }
      }
      if complete { return symbols }
      guard next <= maximumSymbols else { throw KeyboardEmojiCatalogError.invalidPage }
      offset = next
    }
  }

  static func validRecent(_ value: String) -> Bool {
    validText(value)
  }

  /// A kaomoji is a short line of text rather than one pictograph; the longest in the shipped catalog is 59 characters.
  private static func validText(_ value: String, kaomoji: Bool = false) -> Bool {
    let scalars = kaomoji ? 96 : 32
    return !value.isEmpty && value.unicodeScalars.count <= scalars && value.utf8.count <= scalars * 8
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
