import SwiftUI
import UIKit

/// Keyboard panels are too short for the system edge veil introduced in iOS 26.
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
