import SwiftUI

/// Fixed Windows 04a8df56 ordinary-grid geometry at the original 2/3 panel scale.
enum MacEmojiGridMetrics {
  static let columns = 6
  static let scale: CGFloat = 2 / 3
  static let stride: CGFloat = 84 * scale
  static let gap: CGFloat = min(10, 84 * 0.08) * scale
  static let cell: CGFloat = stride - gap
  static let width: CGFloat = CGFloat(columns) * stride
  // Native outer padding (20 each side) and scrollbar allowance (16).
  static let minimumPanelWidth: CGFloat = width + 40 + 16

  static func height(count: Int) -> CGFloat {
    CGFloat((max(0, count) + columns - 1) / columns) * stride
  }

  static func cells(_ items: [MacEmojiCatalogItem]) -> [MacEmojiFlowCell] {
    items.enumerated().map { index, item in
      MacEmojiFlowCell(rect: CGRect(x: CGFloat(index % columns) * stride,
        y: CGFloat(index / columns) * stride, width: cell, height: cell),
        row: index / columns, fontSize: fontSize(item.text))
    }
  }

  static func fontSize(_ text: String) -> CGFloat {
    if text.utf16.count <= 4 { return 42 * scale }
    let natural = MacEmojiFlow.measure(text, 18 * scale)
    if natural.width <= cell && natural.height <= cell { return 18 * scale }
    return MacEmojiFlow.fittedSize(text, width: cell, height: cell, measure: MacEmojiFlow.measure)
  }
}

struct MacEmojiGrid<ID: Hashable>: View {
  let items: [MacEmojiCatalogItem]
  let palette: MacEmojiPalette
  let selected: (Int) -> Bool
  let identity: (Int) -> ID
  let copy: (Int) -> Void

  var body: some View {
    let cells = MacEmojiGridMetrics.cells(items)
    // Explicit placement avoids LazyVGrid rounding each fractional-height row up.
    MacEmojiFlowPlacement(cells: cells, width: MacEmojiGridMetrics.width) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        Button { copy(index) } label: {
          Text(item.text).font(.system(size: cells[index].fontSize)).lineLimit(1)
            .frame(width: MacEmojiGridMetrics.cell, height: MacEmojiGridMetrics.cell).clipped()
        }
        .buttonStyle(MacEmojiCellStyle(palette: palette, selected: selected(index)))
        .frame(width: MacEmojiGridMetrics.cell, height: MacEmojiGridMetrics.cell)
        .id(identity(index))
        .help([item.group, item.annotation].filter { !$0.isEmpty }.joined(separator: " · "))
        .accessibilityLabel(item.annotation.isEmpty ? item.text : item.annotation)
      }
    }
    .frame(width: MacEmojiGridMetrics.width, height: MacEmojiGridMetrics.height(count: items.count), alignment: .topLeading)
  }
}
