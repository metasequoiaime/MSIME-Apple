import Foundation
import AppKit
import SwiftUI

@main enum EmojiHomeTest {
  static func items(_ group: String, _ count: Int) -> [MacEmojiCatalogItem] {
    (0..<count).map { .init(text: "synthetic-\(group)-\($0)", annotation: "fixture", group: group) }
  }
  @MainActor static func main() throws {
    assert(MacEmojiMainPage.allCases.map(\.rawValue) == ["home", "", "sticker", "gif", "kaomoji", "symbols", "clipboard"])
    for page in MacEmojiMainPage.allCases {
      assert(page.destination(hasRecents: false) == page.rawValue)
      assert(page.destination(hasRecents: true) == (page == .emoji ? "recent" : page.rawValue))
      assert(!page.title.isEmpty)
    }
    assert(MacEmojiMainPage.title(category: "recent") == "表情")
    assert(MacEmojiMainPage(rawValue: "recent") == nil)
    assert(MacEmojiSectionChoice.recent != .group("recent"))
    let fixtureGroups = ["fixture-first", "fixture-second"]
    assert(MacEmojiSectionChoice.resolvedGroup(requested: "", current: "fixture-second", groups: fixtureGroups) == "fixture-first")
    assert(MacEmojiSectionChoice.resolvedGroup(requested: "fixture-second", current: "", groups: fixtureGroups) == "fixture-second")
    assert(MacEmojiSectionChoice.resolvedGroup(requested: nil, current: "fixture-second", groups: fixtureGroups) == "fixture-second")
    assert(MacEmojiSectionChoice.resolvedGroup(requested: "missing", current: "", groups: fixtureGroups) == "fixture-first")
    assert(MacEmojiSectionChoice.resolvedGroup(requested: "missing", current: "", groups: []) == "")
    assert(MacEmojiMediaPage.allCases.map(\.rawValue) == ["sticker", "gif"])
    assert(MacEmojiMediaPage.sticker.title == "贴纸" && MacEmojiMediaPage.gif.title == "GIF")
    assert(MacEmojiMediaPage.sticker.message == "可在此接入贴纸")
    assert(MacEmojiMediaPage.gif.message == "可在此接入 GIF 内容源")
    assert(MacEmojiMediaPage(rawValue: "symbols") == nil && MacEmojiMediaPage(rawValue: "home") == nil)
    _ = NSApplication.shared
    for light in [false, true] {
      for page in MacEmojiMediaPage.allCases {
        let renderer = ImageRenderer(content: MacEmojiMediaPlaceholder(page: page, palette: MacEmojiPalette(light: light))
          .frame(width: 336, height: 200).background(Color.white))
        renderer.scale = 3
        guard let image = renderer.cgImage else { fatalError("Media placeholder render unavailable") }
        assert(image.width == 1008 && image.height == 600)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
          let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let painted = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 220 }.count
        assert(painted > 100) // The empty-source hint must actually render in both palettes.
      }
    }
    let navigationSections = [
      MacEmojiHomeSection(title: "fixture emoji", category: "", items: items("emoji", 8)),
      MacEmojiHomeSection(title: "fixture empty", category: "empty", items: []),
      MacEmojiHomeSection(title: "fixture kaomoji", category: "kaomoji", items: items("kaomoji", 7))
    ]
    let flowCells = (0..<7).map { MacEmojiFlowCell(rect: CGRect(x: ($0 % 5) * 60, y: ($0 / 5) * 60, width: 50, height: 56), row: $0 / 5, fontSize: 12) }
    let entries = MacEmojiHomeNavigation.entries(navigationSections, flowCells: flowCells)
    assert(entries.count == 15 && entries[8].row == 2 && entries[13].row == 3)
    func move(_ command: MacEmojiGridCommand, _ index: Int) -> MacEmojiHomeKey? {
      MacEmojiHomeNavigation.destination(command, selected: entries[index].key, entries: entries)?.key
    }
    assert(move(.right, 7) == entries[8].key)
    assert(move(.left, 8) == entries[7].key)
    assert(move(.down, 0) == entries[6].key)
    assert(move(.down, 7) == entries[13].key)
    assert(move(.up, 7) == entries[1].key)
    assert(move(.up, 12) == entries[12].key)
    assert(move(.down, 12) == entries[14].key)
    assert(move(.up, 14) == entries[9].key)
    assert(MacEmojiHomeNavigation.destination(.down, selected: nil, entries: entries)?.key == entries[0].key)
    assert(move(.home, 12) == entries.first?.key && move(.end, 0) == entries.last?.key)
    assert(move(.up, 0) == entries[0].key && move(.down, 14) == entries[14].key)
    assert(MacEmojiHomeNavigation.destination(.activate, selected: nil, entries: entries) == nil)
    let reordered = Array(entries.reversed())
    assert(MacEmojiHomeNavigation.destination(.activate, selected: entries[3].key, entries: reordered)?.item.text == entries[3].item.text)
    assert(MacEmojiHomeNavigation.destination(.activate, selected: entries[3].key, entries: Array(entries.prefix(2))) == nil)
    assert(MacEmojiHomeNavigation.destination(.home, selected: nil, entries: []) == nil)
    let flowTexts = ["aaaaa", "bbbbbb", "cccccccc", "ddddd", "eeeeeee", "fffff"]
    let flowSection = MacEmojiHomeSection(title: "fixture", category: "kaomoji", items: flowTexts.map {
      MacEmojiCatalogItem(text: $0, annotation: "fixture", group: "fixture")
    })
    for width: CGFloat in [150, 200, 400] {
      let layout = MacEmojiFlow.cells(texts: flowTexts, width: width, measure: { text, size in
        CGSize(width: CGFloat(text.count) * size, height: size)
      })
      let combined = MacEmojiHomeNavigation.entries([navigationSections[0], flowSection], flowCells: layout)
      for index in layout.indices {
        for direction in [-1, 1] {
          let expected = MacEmojiFlow.vertical(from: index, direction: direction, cells: layout)!
          let actual = MacEmojiHomeNavigation.destination(direction == -1 ? .up : .down,
            selected: combined[8 + index].key, entries: combined)
          assert(actual?.key == combined[8 + expected].key)
        }
      }
    }
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
