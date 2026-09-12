import AppKit
import CoreText
import SwiftUI

enum MacEmojiTabIcons {
  static let families = ["Segoe Fluent Icons", "Segoe MDL2 Assets"]
  static let scale: CGFloat = 2 / 3
  static let height: CGFloat = 58 * scale
  static let gap: CGFloat = 8 * scale
  static func width(_ page: MacEmojiMainPage) -> CGFloat {
    (page == .kaomoji ? 66 : page == .symbols ? 64 : 58) * scale
  }
  static func codepoint(_ page: MacEmojiMainPage) -> UInt16 {
    switch page {
    case .home: return 0xF6B8
    case .emoji: return 0xE76E
    case .sticker: return 0xF4AA
    case .gif: return 0xF4A9
    case .kaomoji: return 0xED59
    case .symbols: return 0xF6BA
    case .clipboard: return 0xE77F
    }
  }
  static func supports(_ family: String, _ codepoint: UInt16) -> Bool {
    guard let font = NSFont(name: family, size: 28 * scale) else { return false }
    let ctFont = CTFontCreateWithName(font.fontName as CFString, 28 * scale, nil)
    var character = codepoint
    var glyph: CGGlyph = 0
    return CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1) && glyph != 0
  }
  static func resolve(_ page: MacEmojiMainPage,
    supports: (String, UInt16) -> Bool = supports) -> (text: String, family: String?) {
    let code = codepoint(page)
    if let family = families.first(where: { supports($0, code) }) {
      return (String(UnicodeScalar(code)!), family)
    }
    return (page == .home ? "最近" : page.title, nil)
  }
}

struct MacEmojiMainTabs: View {
  let selected: MacEmojiMainPage
  let palette: MacEmojiPalette
  let navigate: (String) -> Void
  var resolve: (MacEmojiMainPage) -> (text: String, family: String?) = { MacEmojiTabIcons.resolve($0) }

  var body: some View {
    HStack(spacing: MacEmojiTabIcons.gap) {
      ForEach(MacEmojiMainPage.allCases, id: \.rawValue) { page in
        let icon = resolve(page)
        Button { navigate(page.rawValue) } label: {
          Text(icon.text)
            .font(icon.family.map { .custom($0, size: 28 * MacEmojiTabIcons.scale) }
              ?? .system(size: 14 * MacEmojiTabIcons.scale))
            .foregroundStyle(MacEmojiPalette.color(palette.background == 0xF7F7FA ? palette.muted : 0xFFFFFF))
            .lineLimit(1).frame(width: MacEmojiTabIcons.width(page), height: MacEmojiTabIcons.height).clipped()
        }
        .buttonStyle(MacEmojiMainTabStyle(selected: selected == page, palette: palette))
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(selected == page ? .isSelected : [])
        .help(page.title)
      }
    }.frame(height: MacEmojiTabIcons.height)
  }
}

private struct MacEmojiMainTabStyle: ButtonStyle {
  let selected: Bool
  let palette: MacEmojiPalette
  func makeBody(configuration: Configuration) -> some View {
    Cell(configuration: configuration, selected: selected, palette: palette)
  }
  private struct Cell: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let palette: MacEmojiPalette
    @State private var hovered = false
    var body: some View {
      configuration.label
        .background(!selected && (hovered || configuration.isPressed)
          ? MacEmojiPalette.color(palette.background == 0xF7F7FA ? 0xE9E7ED : 0x303038) : .clear,
          in: RoundedRectangle(cornerRadius: 6 * MacEmojiTabIcons.scale))
        .overlay(alignment: .bottom) {
          if selected {
            RoundedRectangle(cornerRadius: MacEmojiTabIcons.scale)
              .fill(MacEmojiPalette.color(palette.accent))
              .frame(width: 24 * MacEmojiTabIcons.scale, height: 2 * MacEmojiTabIcons.scale)
          }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
  }
}
