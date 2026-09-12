import SwiftUI
import UIKit

/// 关闭 iOS 26 起默认开启的滚动边缘效果。
///
/// The effect fades and blurs content towards a scroll view's edges. It assumes a scroll view tall
/// enough that the edges hold empty space; a keyboard panel is a few rows tall, so the gradient
/// lands on the content itself. Candidate chips came out smudged along their top while the keys
/// beside them, which are not inside a scroll view, stayed sharp -- and the same band sat over the
/// first line of text in the service panels.
///
/// Two spellings of one fix: UIKit panels build their own scroll views, SwiftUI panels do not
/// expose theirs. Keep them together so a new panel has one obvious thing to call.
extension UIScrollView {
  func disableEdgeEffects() {
    guard #available(iOS 26.0, *) else { return }
    for effect in [topEdgeEffect, bottomEdgeEffect, leftEdgeEffect, rightEdgeEffect] {
      effect.isHidden = true
    }
  }
}

extension View {
  @ViewBuilder func disablingScrollEdgeEffects() -> some View {
    if #available(iOS 26.0, *) { scrollEdgeEffectHidden(true, for: .all) } else { self }
  }
}
