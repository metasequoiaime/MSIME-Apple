import UIKit

/// Animate the key itself without changing the stack view's layout or input timing.
final class KeyboardKeyButton: UIButton {
  override var isHighlighted: Bool {
    didSet {
      guard isHighlighted != oldValue else { return }
      updatePressFeedback()
    }
  }

  private func updatePressFeedback() {
    let pressed = isHighlighted && isEnabled
    let target = pressed
      ? CGAffineTransform(translationX: 0, y: 1).scaledBy(x: 0.94, y: 0.94)
      : .identity
    guard !UIAccessibility.isReduceMotionEnabled, window != nil else {
      layer.removeAllAnimations()
      transform = .identity
      return
    }
    UIView.animate(
      withDuration: pressed ? 0.06 : 0.18,
      delay: 0,
      usingSpringWithDamping: pressed ? 1 : 0.72,
      initialSpringVelocity: 0,
      options: [.allowUserInteraction, .beginFromCurrentState]
    ) {
      self.transform = target
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      layer.removeAllAnimations()
      transform = .identity
    }
  }

  override var isEnabled: Bool {
    didSet {
      if !isEnabled { updatePressFeedback() }
    }
  }
}
