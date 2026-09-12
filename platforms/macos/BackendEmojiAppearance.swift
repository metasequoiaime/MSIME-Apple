import SwiftUI

/// Palette from the fixed Windows EmojiPanel reference (04a8df56).
struct MacEmojiPalette {
  let background: UInt32
  let text: UInt32
  let muted: UInt32
  let selected: UInt32
  let pressed: UInt32
  let accent: UInt32

  init(light: Bool) {
    background = light ? 0xF7F7FA : 0x202027
    text = light ? 0x202027 : 0xF5F5F7
    muted = light ? 0x686873 : 0xAFAFB7
    selected = light ? 0xE0D7E5 : 0x3B3B44
    pressed = light ? 0xD3C7D9 : 0x555560
    accent = light ? 0x9A62AD : 0xD88BDE
  }

  func cellFill(hovered: Bool, isPressed: Bool) -> UInt32? {
    isPressed ? pressed : hovered ? selected : nil
  }

  static func color(_ rgb: UInt32) -> Color {
    Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
      green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
  }
}

@MainActor final class MacEmojiAppearance: ObservableObject {
  static let shared = MacEmojiAppearance()
  @Published private(set) var colorScheme: ColorScheme? = .dark

  func apply(_ preferences: NSDictionary) {
    let resolved: ColorScheme?
    switch preferences["theme"] as? String {
    case "light": resolved = .light
    case "system": resolved = nil
    default: resolved = .dark
    }
    if colorScheme != resolved { colorScheme = resolved }
  }
}

struct MacEmojiCellStyle: ButtonStyle {
  let palette: MacEmojiPalette
  func makeBody(configuration: Configuration) -> some View {
    Cell(configuration: configuration, palette: palette)
  }

  private struct Cell: View {
    let configuration: ButtonStyleConfiguration
    let palette: MacEmojiPalette
    @State private var hovered = false
    var body: some View {
      configuration.label
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(fill, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovered = $0 }
    }
    private var fill: Color {
      palette.cellFill(hovered: hovered, isPressed: configuration.isPressed)
        .map(MacEmojiPalette.color) ?? .clear
    }
  }
}
