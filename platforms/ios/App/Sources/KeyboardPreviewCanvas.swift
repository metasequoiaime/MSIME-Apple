import SwiftUI

// Render a complete keyboard at its reference size, then scale every dimension together.
// Callers can constrain width or available space without flattening rows or clipping keys.
struct KeyboardPreviewCanvas<Content: View>: View {
  private let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / 390, geometry.size.height / 260)
      content.frame(width: 390, height: 260)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }.aspectRatio(390.0 / 260.0, contentMode: .fit)
  }
}
