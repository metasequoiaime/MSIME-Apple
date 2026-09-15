import UIKit

/// Animate the key itself without changing the stack view's layout or input timing.
final class KeyboardKeyButton: UIButton {
  /// 标题写几行。候选词一行,底下每条释义各一行。
  ///
  /// 配置化按钮的标题标签是它自己管的:按钮刚建出来时 `titleLabel` 还是 nil,而每次更新配置又会重新配一遍,所以直接赋值时灵时不灵 —— 释义那几行会毫无规律地被截掉。这里在每次布局之后重申一次,标签无论什么时候建出来都会被纠正。
  var titleLines = 1 {
    didSet {
      guard titleLines != oldValue else { return }
      titleLabel?.numberOfLines = titleLines
      setNeedsLayout()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let label = titleLabel, label.numberOfLines != titleLines else { return }
    label.numberOfLines = titleLines
    // 这一趟是按旧行数量的,改完要再排一次。
    setNeedsLayout()
  }

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

/// Candidate chips highlight immediately, but a drag still belongs to the strip.
final class CandidateScrollView: UIScrollView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    delaysContentTouches = false
    disableEdgeEffects()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    delaysContentTouches = false
    disableEdgeEffects()
  }

  override func touchesShouldCancel(in view: UIView) -> Bool {
    if view is KeyboardKeyButton { return true }
    return super.touchesShouldCancel(in: view)
  }
}
