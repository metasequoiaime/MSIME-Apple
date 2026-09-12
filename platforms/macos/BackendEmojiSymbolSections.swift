import SwiftUI

struct MacEmojiSymbolSection {
  struct Identity: Hashable { let start: Int }
  let title: String
  let start: Int
  var items: [MacEmojiCatalogItem]
  var id: Identity { Identity(start: start) }
}

enum MacEmojiSymbolSections {
  static let titleHeight: CGFloat = 48 * 2 / 3
  static let bottomPadding: CGFloat = 18 * 2 / 3

  /// Preserve contiguous catalog runs and global indices, including repeated titles.
  static func split(_ items: [MacEmojiCatalogItem]) -> [MacEmojiSymbolSection] {
    var sections: [MacEmojiSymbolSection] = []
    for (index, item) in items.enumerated() {
      if sections.last?.title == item.group {
        sections[sections.count - 1].items.append(item)
      } else {
        sections.append(.init(title: item.group, start: index, items: [item]))
      }
    }
    return sections
  }

  static func height(_ section: MacEmojiSymbolSection) -> CGFloat {
    titleHeight + MacEmojiGridMetrics.height(count: section.items.count) + bottomPadding
  }
}

struct MacEmojiSymbolSectionsView: View {
  let items: [MacEmojiCatalogItem]
  let palette: MacEmojiPalette
  let selectedIndex: Int
  let copy: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(MacEmojiSymbolSections.split(items), id: \.id) { section in
        VStack(alignment: .leading, spacing: 0) {
          Text(section.title).font(.system(size: 18 * 2 / 3, weight: .semibold))
            .foregroundStyle(MacEmojiPalette.color(palette.text)).lineLimit(1)
            .frame(height: MacEmojiSymbolSections.titleHeight)
            .padding(.leading, 4 * 2 / 3)
            .frame(maxWidth: .infinity, alignment: .leading).clipped()
          MacEmojiGrid(items: section.items, palette: palette,
            selected: { selectedIndex == section.start + $0 },
            identity: { section.start + $0 }, copy: { copy(section.start + $0) })
        }.padding(.bottom, MacEmojiSymbolSections.bottomPadding)
      }
    }.frame(width: MacEmojiGridMetrics.width, alignment: .leading)
  }
}
