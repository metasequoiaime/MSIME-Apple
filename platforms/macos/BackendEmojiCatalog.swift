import Foundation

struct MacEmojiCatalogItem: Equatable, Sendable {
  let text: String
  let annotation: String
  let group: String
}

enum MacEmojiCatalog {
  static func decode(_ response: NSDictionary) throws -> [MacEmojiCatalogItem] {
    guard response["error"] == nil, let rows = response["items"] as? [[String: Any]] else {
      throw NSError(domain: "MSIMEEmojiCatalog", code: 1)
    }
    return try rows.map { row in
      guard let text = row["text"] as? String, !text.isEmpty,
            let annotation = row["annotation"] as? String,
            let group = row["group"] as? String else {
        throw NSError(domain: "MSIMEEmojiCatalog", code: 2)
      }
      return MacEmojiCatalogItem(text: text, annotation: annotation, group: group)
    }
  }

  static func load(resources: String, search: String, category: String = "") throws -> [MacEmojiCatalogItem] {
    let selector = NSSelectorFromString("emojiCatalogRequest:")
    guard NSString(string: resources).isAbsolutePath,
          FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: resources).appendingPathComponent("others.db").path),
          let type = NSClassFromString("MSIMEClientSession") as? NSObject.Type,
          type.responds(to: selector),
          let response = type.perform(selector, with: ["resources": resources, "search": search,
              "category": category, "limit": 255] as NSDictionary)?.takeUnretainedValue() as? NSDictionary else {
      throw NSError(domain: "MSIMEEmojiCatalog", code: 3)
    }
    return try decode(response)
  }
}
