import UIKit

/// Animate the key itself without changing the stack view's layout or input timing.
final class KeyboardKeyButton: UIButton {
  /// 开着释义时,一屏摆几个候选。
  ///
  /// 宽度必须和释义到没到无关:联网那份是几百毫秒后陆续到的,让它决定宽度,格子就会一个接一个变宽,后面的候选一路右移 —— 和高度跳是同一件事的另一半。所以先按屏宽分格,答案回来往格子里填。
  ///
  /// 三个而不是四个:四个的时候一格只剩七十来点,「draft; draw up」这种就得截尾,而释义截了就等于没写。
  static let glossColumns = 3

  /// 一屏三格时,一格的正文有多宽。visible 是候选条看得见的那一段,spacing 是格与格之间的间距。
  static func glossColumnWidth(visible: CGFloat, spacing: CGFloat, insets: NSDirectionalEdgeInsets) -> CGFloat {
    guard visible > 0 else { return 0 }
    let columns = CGFloat(glossColumns)
    return (visible - spacing * (columns - 1)) / columns - insets.leading - insets.trailing
  }

  /// 格子里正文能用的宽度:一格的宽度,和候选词那一行,取大的那个 —— 候选词本身永远不截,比一格还长的词自己把格子撑开。
  static func chipContentWidth(titleLine: CGFloat, glossLines: Int, column: CGFloat) -> CGFloat {
    glossLines > 0 ? max(titleLine, column) : titleLine
  }

  /// 一个候选格该有多宽:正文宽度加上左右内边距。
  static func chipWidth(titleLine: CGFloat, glossLines: Int, column: CGFloat,
                        insets: NSDirectionalEdgeInsets) -> CGFloat {
    ceil(chipContentWidth(titleLine: titleLine, glossLines: glossLines, column: column)
      + insets.leading + insets.trailing)
  }

  /// 释义最小能缩到多少号。再小就只是一排看不清的灰点,不如截掉。
  static let minimumGlossFontSize: CGFloat = 9

  /// 让释义在给定宽度里写得下:先缩字号,缩到下限还放不下才截尾。
  ///
  /// 缩字号是为了尽量不截 —— 释义截了往往就看不出意思。截断这一步也不能交给段落样式:标签一旦允许多行,它不截而是折行,「draft; draw up」折成两行,那个格子就比同一行的别人高出一截。
  static func fittedGloss(_ text: String, font: UIFont, width: CGFloat) -> (text: String, font: UIFont) {
    func measure(_ string: String, _ font: UIFont) -> CGFloat {
      (string as NSString).size(withAttributes: [.font: font]).width
    }
    guard width > 0, !text.isEmpty else { return (text, font) }
    if measure(text, font) <= width { return (text, font) }

    var size = font.pointSize
    while size > minimumGlossFontSize {
      size = max(size - 0.5, minimumGlossFontSize)
      let smaller = font.withSize(size)
      if measure(text, smaller) <= width { return (text, smaller) }
    }

    let floorFont = font.withSize(minimumGlossFontSize)
    var characters = Array(text)
    while !characters.isEmpty {
      characters.removeLast()
      let shortened = String(characters) + "…"
      if measure(shortened, floorFont) <= width { return (shortened, floorFont) }
    }
    return ("", floorFont)
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
