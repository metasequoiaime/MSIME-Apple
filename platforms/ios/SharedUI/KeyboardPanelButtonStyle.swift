import SwiftUI

// Put the minimum hit target inside the button label, not around its containing row.
// Controls stay compact in the fixed-height keyboard; the scrollable text uses the
// user's full Dynamic Type size, including accessibility categories.
struct KeyboardPanelButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
      .foregroundStyle(.tint)
      .background(configuration.isPressed ? Color.accentColor.opacity(0.12) : .clear)
      .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}
