import SwiftUI

// Render a complete keyboard at its reference size, then scale every dimension together.
// Callers can constrain width or available space without flattening rows or clipping keys.
struct KeyboardPreviewCanvas<Content: View>: View {
  private let content: Content
  /// 画出来的键盘有多高。默认是系统键盘的高度;调高度那一页把增减量加进来,预览就跟着长高变矮。
  private let referenceHeight: CGFloat
  init(referenceHeight: CGFloat = 260, @ViewBuilder content: () -> Content) {
    self.referenceHeight = referenceHeight
    self.content = content()
  }
  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / 390, geometry.size.height / referenceHeight)
      content.frame(width: 390, height: referenceHeight)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }.aspectRatio(390.0 / referenceHeight, contentMode: .fit)
  }
}
