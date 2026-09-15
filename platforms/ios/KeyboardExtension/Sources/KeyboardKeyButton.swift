import UIKit

/// Animate the key itself without changing the stack view's layout or input timing.
final class KeyboardKeyButton: UIButton {
  /// 释义那一行预留多宽。
  ///
  /// 宽度必须和释义到没到无关。联网那份是几百毫秒后陆续到的,格子跟着一个一个变宽,后面的候选就一路右移 —— 和高度跳是同一件事的另一半。所以宽度在答案回来之前就定下来:候选词更宽就按候选词,否则按这个预留值,释义比它长就截断。
  ///
  /// 取值是在「释义看得完」和「一屏能看见几个候选」之间选的:64pt 放得下 hello、mud 这类单词和「こんにちは」,放不下的会截尾;再宽下去一屏就只剩三四个候选了。要调就调这一个数。
  static let glossReservedWidth: CGFloat = 64

  /// 格子里正文能用的宽度:候选词那一行,和释义预留的宽度,取大的那个。
  static func chipContentWidth(titleLine: CGFloat, glossLines: Int) -> CGFloat {
    glossLines > 0 ? max(titleLine, glossReservedWidth) : titleLine
  }

  /// 一个候选格该有多宽:正文宽度加上左右内边距。
  static func chipWidth(titleLine: CGFloat, glossLines: Int, insets: NSDirectionalEdgeInsets) -> CGFloat {
    ceil(chipContentWidth(titleLine: titleLine, glossLines: glossLines) + insets.leading + insets.trailing)
  }

  /// 把释义截到给定宽度以内,超出的用省略号收尾。
  ///
  /// 不能指望段落样式的截断:标签一旦允许多行,它照样折行 —— 「draft; draw up」于是折成两行,那个格子比同一行的别人高出一截。自己截就没有折行的可能。
  static func fittedGloss(_ text: String, font: UIFont, width: CGFloat) -> String {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    guard width > 0, (text as NSString).size(withAttributes: attributes).width > width else { return text }
    var characters = Array(text)
    while !characters.isEmpty {
      characters.removeLast()
      let shortened = String(characters) + "…"
      if (shortened as NSString).size(withAttributes: attributes).width <= width { return shortened }
    }
    return ""
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
