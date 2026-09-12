import Foundation
import CoreFoundation

struct MacEmojiCatalogSlice {
  let items: [MacEmojiCatalogItem]
  let nextOffset: Int
  let complete: Bool
}

enum MacEmojiCatalogCursor {
  static let batchSize = 255
  static func invalid() -> NSError { NSError(domain: "MSIMEEmojiCatalogCursor", code: 1) }

  static func decode(_ response: NSDictionary, offset: Int, limit: Int) throws -> MacEmojiCatalogSlice {
    guard offset >= 0, (1...batchSize).contains(limit),
          let next = response["next_offset"] as? NSNumber,
          CFGetTypeID(next) != CFBooleanGetTypeID(),
          ["i", "q", "l", "s", "I", "Q", "L", "S"].contains(String(cString: next.objCType)),
          next.int64Value >= 0, next.stringValue == String(next.int64Value),
          let complete = response["complete"] as? NSNumber,
          CFGetTypeID(complete) == CFBooleanGetTypeID() else { throw invalid() }
    let nextOffset = next.intValue
    guard nextOffset >= offset, nextOffset - offset <= limit,
          complete.boolValue == (nextOffset - offset < limit) else { throw invalid() }
    let items = try MacEmojiCatalog.decode(response)
    guard items.count <= nextOffset - offset else { throw invalid() }
    return .init(items: items, nextOffset: nextOffset, complete: complete.boolValue)
  }

  /// Only publish after explicit EOF. An empty batch can still advance the cursor.
  static func collect<Revision: Equatable>(revision: () throws -> Revision,
    page: (Int, Int) throws -> NSDictionary) throws -> [MacEmojiCatalogItem] {
    try Task.checkCancellation()
    let initial = try revision()
    var offset = 0
    var items: [MacEmojiCatalogItem] = []
    while true {
      try Task.checkCancellation()
      guard try revision() == initial else { throw invalid() }
      let slice = try decode(page(offset, batchSize), offset: offset, limit: batchSize)
      try Task.checkCancellation()
      guard try revision() == initial else { throw invalid() }
      items.append(contentsOf: slice.items)
      if slice.complete { return items }
      offset = slice.nextOffset
    }
  }
}

/// Detect ordinary replacement/writes during multi-request reads, including WAL changes.
/// This is a file-change guard, not a SQLite snapshot transaction.
struct MacEmojiCatalogRevision: Equatable {
  struct File: Equatable {
    let device: UInt64
    let inode: UInt64
    let size: UInt64
    let modified: Date
  }
  let database: File
  let wal: File?
  static func capture(resources: String) throws -> Self {
    guard NSString(string: resources).isAbsolutePath else { throw MacEmojiCatalogCursor.invalid() }
    let path = URL(fileURLWithPath: resources).appendingPathComponent("others.db").resolvingSymlinksInPath().path
    func mark(_ path: String) throws -> File {
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      guard let device = attributes[.systemNumber] as? NSNumber,
            let inode = attributes[.systemFileNumber] as? NSNumber,
            let size = attributes[.size] as? NSNumber,
            let modified = attributes[.modificationDate] as? Date else { throw MacEmojiCatalogCursor.invalid() }
      return File(device: device.uint64Value, inode: inode.uint64Value, size: size.uint64Value, modified: modified)
    }
    return try Self(database: mark(path), wal: FileManager.default.fileExists(atPath: path + "-wal") ? mark(path + "-wal") : nil)
  }
}

extension MacEmojiCatalog {
  static func loadAll(resources: String, search: String, category: String, group: String, parent: String) throws -> [MacEmojiCatalogItem] {
    try MacEmojiCatalogCursor.collect(revision: { try MacEmojiCatalogRevision.capture(resources: resources) }) { offset, limit in
      try request(resources: resources, parameters: ["cursor": true, "search": search, "category": category,
        "group": group, "parent": parent, "offset": offset, "limit": limit])
    }
  }
}
