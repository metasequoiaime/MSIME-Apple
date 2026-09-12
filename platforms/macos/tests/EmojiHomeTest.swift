import Foundation

@main enum EmojiHomeTest {
  static func items(_ group: String, _ count: Int) -> [MacEmojiCatalogItem] {
    (0..<count).map { .init(text: "synthetic-\(group)-\($0)", annotation: "fixture", group: group) }
  }
  static func main() throws {
    let groups = [items("a", 3), items("b", 1), items("c", 2)]
    assert(MacEmojiHomeCatalog.preview(groups: groups, limit: 4, diverse: false).map(\.text) == ["synthetic-a-0", "synthetic-a-1", "synthetic-a-2", "synthetic-b-0"])
    assert(MacEmojiHomeCatalog.preview(groups: groups, limit: 5, diverse: true).map(\.text) == ["synthetic-a-0", "synthetic-b-0", "synthetic-c-0", "synthetic-a-1", "synthetic-c-1"])
    assert(MacEmojiHomeCatalog.preview(groups: groups, limit: 18, diverse: true).count == 6)
    assert(MacEmojiHomeCatalog.preview(groups: groups, limit: 0, diverse: true).isEmpty)
    let home = try MacEmojiHomeCatalog.load(search: "", groups: { _ in ["a", "b", "c"] }, page: { _, group, limit in items(group, limit) })
    assert(home.map(\.category) == ["", "kaomoji", "symbols"])
    assert(home.map { $0.items.count } == [18, 15, 18])
    assert(home[2].items.prefix(3).map(\.group) == ["a", "b", "c"])
    var calls: [Int] = []
    let search = try MacEmojiHomeCatalog.load(search: "synthetic", groups: { _ in assertionFailure("search should not load group metadata"); return [] }, page: { _, group, limit in
      assert(group.isEmpty); calls.append(limit); return items("search", 50)
    })
    assert(calls == [18, 15, 18] && search.map { $0.items.count } == calls)
    let empty = try MacEmojiHomeCatalog.load(search: "", groups: { _ in [] }, page: { _, _, _ in assertionFailure(); return [] })
    assert(empty.count == 3 && empty.allSatisfy { $0.items.isEmpty })
    do {
      _ = try MacEmojiHomeCatalog.load(search: "synthetic", groups: { _ in [] }, page: { _, _, _ in throw NSError(domain: "SyntheticCatalog", code: 1) })
      assertionFailure("catalog error ignored")
    } catch { }
    print("Emoji home preview order, limits, diverse symbols, search and failure tests passed")
  }
}
