import Foundation

struct MacEmojiClipboardHistory: Equatable, Sendable {
  let enabled: Bool
  let entries: [String]

  // The caller owns this structured task: changing pages or closing the window
  // cancels polling. Reads are serial, and cancelled reads never publish.
  @MainActor static func observe(
    interval: UInt64 = 400_000_000,
    read: @escaping @Sendable () async throws -> Self,
    publish: (Self?) -> Void
  ) async {
    var previous: Self?
    var published = false
    while !Task.isCancelled {
      let snapshot: Self?
      do { snapshot = try await read() }
      catch { snapshot = nil }
      guard !Task.isCancelled else { return }
      if !published || snapshot != previous {
        publish(snapshot)
        previous = snapshot
        published = true
      }
      do { try await Task.sleep(nanoseconds: interval) }
      catch { return }
    }
  }

  static func decode(_ response: NSDictionary) throws -> Self {
    guard response["error"] == nil, let flag = response["enabled"] as? NSNumber,
          CFGetTypeID(flag) == CFBooleanGetTypeID(),
          let entries = response["entries"] as? [String], entries.count <= 50,
          entries.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 }),
          Set(entries).count == entries.count,
          flag.boolValue || entries.isEmpty else {
      throw NSError(domain: "MSIMEClipboardHistory", code: 1)
    }
    return Self(enabled: flag.boolValue, entries: entries)
  }

  func matching(_ search: String) -> [MacEmojiCatalogItem] {
    guard enabled else { return [] }
    return entries.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
      .map { MacEmojiCatalogItem(text: $0, annotation: "", group: "剪贴板") }
  }

  static func load(directory: String) throws -> Self {
    let selector = NSSelectorFromString("clipboardHistoryRequest:")
    guard NSString(string: directory).isAbsolutePath,
          let type = NSClassFromString("MSIMEClientSession") as? NSObject.Type,
          type.responds(to: selector),
          let response = type.perform(selector, with: directory)?.takeUnretainedValue() as? NSDictionary else {
      throw NSError(domain: "MSIMEClipboardHistory", code: 2)
    }
    return try decode(response)
  }

  static func remove(directory: String, text: String) throws -> Bool {
    let selector = NSSelectorFromString("removeClipboardHistoryRequest:")
    guard NSString(string: directory).isAbsolutePath, !text.isEmpty, text.utf8.count <= 4096,
          let type = NSClassFromString("MSIMEClientSession") as? NSObject.Type,
          type.responds(to: selector),
          let response = type.perform(selector, with: ["directory": directory, "text": text] as NSDictionary)?.takeUnretainedValue() as? NSDictionary,
          response["error"] == nil, let removed = response["removed"] as? NSNumber,
          CFGetTypeID(removed) == CFBooleanGetTypeID() else {
      throw NSError(domain: "MSIMEClipboardHistory", code: 3)
    }
    return removed.boolValue
  }
}
