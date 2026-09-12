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

  static func load(resources: String, search: String, category: String = "", offset: Int = 0, group: String = "", parent: String = "") throws -> [MacEmojiCatalogItem] {
    guard offset >= 0 else { throw NSError(domain: "MSIMEEmojiCatalog", code: 3) }
    return try decode(request(resources: resources, parameters: ["search": search,
      "category": category, "offset": offset, "group": group, "parent": parent, "limit": 255]))
  }

  static func loadSymbolGroups(resources: String) throws -> [MacEmojiSymbolGroup] {
    let response = try request(resources: resources, parameters: ["list_symbol_groups": true])
    guard response["error"] == nil, let rows = response["symbol_groups"] as? [[String: String]] else {
      throw NSError(domain: "MSIMEEmojiCatalog", code: 5)
    }
    let groups = try rows.map { row -> MacEmojiSymbolGroup in
      guard let parent = row["parent"], !parent.isEmpty, let title = row["title"], !title.isEmpty else {
        throw NSError(domain: "MSIMEEmojiCatalog", code: 5)
      }
      return MacEmojiSymbolGroup(parent: parent, title: title)
    }
    guard Set(groups).count == groups.count else { throw NSError(domain: "MSIMEEmojiCatalog", code: 5) }
    return groups
  }

  static func loadGroups(resources: String, category: String) throws -> [String] {
    let response = try request(resources: resources, parameters: ["category": category, "list_groups": true])
    guard response["error"] == nil, let groups = response["groups"] as? [String],
          groups.allSatisfy({ !$0.isEmpty }), Set(groups).count == groups.count else {
      throw NSError(domain: "MSIMEEmojiCatalog", code: 4)
    }
    return groups
  }

  private static func request(resources: String, parameters: [String: Any]) throws -> NSDictionary {
    let selector = NSSelectorFromString("emojiCatalogRequest:")
    var payload = parameters
    payload["resources"] = resources
    guard NSString(string: resources).isAbsolutePath,
          FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: resources).appendingPathComponent("others.db").path),
          let type = NSClassFromString("MSIMEClientSession") as? NSObject.Type,
          type.responds(to: selector),
          let response = type.perform(selector, with: payload as NSDictionary)?.takeUnretainedValue() as? NSDictionary else {
      throw NSError(domain: "MSIMEEmojiCatalog", code: 3)
    }
    return response
  }
}
