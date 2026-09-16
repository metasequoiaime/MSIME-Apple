import UIKit

/// Key spacing and keyboard height, set by dragging the keyboard itself.
///
/// This was three sliders filling the keyboard area. The values applied live, but the panel sat on
/// top of the thing they changed: moving the spacing sliders altered nothing anyone could see, and
/// only the height showed at all, because the panel resized with it.
///
/// It is transparent now. A slim bar across the top carries 恢复默认, whatever is being changed,
/// the 语音入口 switch and 完成; everything below it is the real keyboard, which is what the drag
/// moves. The bar drags the keyboard taller or shorter; dragging on the keys sets the spacing --
/// sideways between keys, up and down between rows.
final class KeyboardLayoutPickerView: UIView {
  /// How far a drag travels per unit. Height follows the finger; the two spacing ranges are only a
  /// few points wide, so following the finger there would hit the end at the first nudge.
  private static let spacingDragScale: Double = 18
  private static let barHeight: CGFloat = 52

  private enum Axis { case vertical, horizontal }

  private let onKeySpacing: (Double) -> Void
  private let onRowSpacing: (Double) -> Void
  private let onHeight: (Double) -> Void
  private var keySpacing: Double
  private var rowSpacing: Double
  private var height: Double
  private let hint = UILabel()
  private let grip = UIView()
  private var axis: Axis?
  private var base: (key: Double, row: Double, height: Double) = (0, 0, 0)

  init(keySpacing: Double, rowSpacing: Double, height: Double, voiceEnabled: Bool,
       onKeySpacing: @escaping (Double) -> Void,
       onRowSpacing: @escaping (Double) -> Void,
       onHeight: @escaping (Double) -> Void,
       onVoice: @escaping (Bool) -> Void,
       onReset: @escaping () -> Void,
       onClose: @escaping () -> Void) {
    self.keySpacing = keySpacing
    self.rowSpacing = rowSpacing
    self.height = height
    self.onKeySpacing = onKeySpacing
    self.onRowSpacing = onRowSpacing
    self.onHeight = onHeight
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardLayoutPicker"
    let skin = KeyboardSkinPreference.selected
    // Transparent on purpose: the keyboard has to be visible or what is being adjusted still is
    // not. Swallowing touches is only so that a drag does not type.
    backgroundColor = .clear

    let bar = UIView()
    bar.backgroundColor = skin.keyBackground
    bar.layer.cornerRadius = 10

    let close = UIButton(type: .system)
    close.setTitle("完成", for: .normal)
    close.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    close.setTitleColor(skin.accent, for: .normal)
    close.accessibilityIdentifier = "closeLayoutPicker"
    close.accessibilityLabel = "返回键盘"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)

    let reset = UIButton(type: .system)
    reset.setTitle("恢复默认", for: .normal)
    reset.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    reset.setTitleColor(.systemRed, for: .normal)
    reset.accessibilityIdentifier = "resetKeyboardSettings"
    reset.accessibilityLabel = "恢复默认"
    reset.accessibilityHint = "把间距、高度和语音入口恢复成默认值"
    reset.addAction(UIAction { _ in onReset() }, for: .primaryActionTriggered)

    // The voice entry is a switch rather than a drag, so it stays in the bar; the App's keyboard
    // settings page offers it too, but taking it off the in-keyboard surface would remove the only
    // place it can be reached without leaving the host app.
    let voiceSwitch = UISwitch()
    voiceSwitch.isOn = voiceEnabled
    voiceSwitch.onTintColor = skin.accent
    voiceSwitch.accessibilityIdentifier = "voiceShortcutSwitch"
    voiceSwitch.accessibilityLabel = "顶部语音入口"
    voiceSwitch.addAction(UIAction { action in
      guard let toggle = action.sender as? UISwitch else { return }
      onVoice(toggle.isOn)
    }, for: .valueChanged)

    hint.font = .systemFont(ofSize: 13)
    hint.textColor = skin.keyForeground.withAlphaComponent(0.75)
    hint.textAlignment = .center
    hint.adjustsFontSizeToFitWidth = true
    hint.minimumScaleFactor = 0.7
    hint.accessibilityIdentifier = "layoutAdjustHint"
    updateHint()

    // Pressed against the bar's lower edge: dragging it is dragging the keyboard's top.
    grip.backgroundColor = skin.accent.withAlphaComponent(0.45)
    grip.layer.cornerRadius = 2.5
    grip.isUserInteractionEnabled = false

    // The adjustable trait and the increment/decrement have to live on the same object, or
    // VoiceOver announces a control it cannot then operate.
    let gripTarget = HeightGripView()
    gripTarget.onAdjust = { [weak self] delta in self?.adjustHeight(by: delta) }
    gripTarget.backgroundColor = .clear
    gripTarget.accessibilityIdentifier = "keyboardHeightGrip"
    gripTarget.accessibilityLabel = "键盘高度"
    gripTarget.isAccessibilityElement = true
    gripTarget.accessibilityTraits = .adjustable
    gripTarget.addGestureRecognizer(
      UIPanGestureRecognizer(target: self, action: #selector(dragHeight(_:))))

    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragSpacing(_:))))

    for item in [bar, close, reset, voiceSwitch, hint, grip, gripTarget] {
      item.translatesAutoresizingMaskIntoConstraints = false
      addSubview(item)
    }
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      bar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
      // All four share one centre line. The grip takes the last few points of the bar, so that line
      // sits above the bar's own centre rather than on it.
      close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
      close.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      voiceSwitch.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -10),
      voiceSwitch.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      reset.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
      reset.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      hint.leadingAnchor.constraint(equalTo: reset.trailingAnchor, constant: 8),
      hint.trailingAnchor.constraint(equalTo: voiceSwitch.leadingAnchor, constant: -8),
      hint.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
      // Drawn inside the bar's own lower edge so it does not sit on the shortcut row beneath. The
      // whole bar drags -- grabbing a thin rule is worse than grabbing the bar it is drawn on.
      grip.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
      grip.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -6),
      grip.widthAnchor.constraint(equalToConstant: 46),
      grip.heightAnchor.constraint(equalToConstant: 5),
      gripTarget.leadingAnchor.constraint(equalTo: reset.trailingAnchor),
      gripTarget.trailingAnchor.constraint(equalTo: voiceSwitch.leadingAnchor),
      gripTarget.topAnchor.constraint(equalTo: bar.topAnchor),
      gripTarget.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  fileprivate func adjustHeight(by delta: Double) {
    height = Self.clamp(height + delta, -12, 48)
    onHeight(height)
    updateHint()
  }

  @objc private func dragHeight(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      base = (keySpacing, rowSpacing, height)
    case .changed:
      // Dragging up makes it taller, and screen coordinates grow downwards, hence the negation.
      height = Self.clamp(base.height - Double(gesture.translation(in: self).y), -12, 48)
      onHeight(height)
      updateHint("键盘高度 \(height > 0 ? "+" : "")\(Int(height))")
    default:
      axis = nil
      updateHint()
    }
  }

  @objc private func dragSpacing(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: self)
    switch gesture.state {
    case .began:
      base = (keySpacing, rowSpacing, height)
      axis = nil
    case .changed:
      // Whichever way the first few points went is the only setting this drag touches, so a hand
      // that wanders cannot make the two swap.
      let direction = axis ?? (abs(translation.y) >= abs(translation.x) ? .vertical : .horizontal)
      axis = direction
      switch direction {
      case .vertical:
        rowSpacing = Self.clamp(base.row + Double(translation.y) / Self.spacingDragScale, 4, 10)
        onRowSpacing(rowSpacing)
        updateHint(String(format: "行间距 %.1f", rowSpacing))
      case .horizontal:
        keySpacing = Self.clamp(base.key + Double(translation.x) / Self.spacingDragScale, 3, 6)
        onKeySpacing(keySpacing)
        updateHint(String(format: "按键间距 %.1f", keySpacing))
      }
    default:
      axis = nil
      updateHint()
    }
  }

  /// Names the value while the finger is down, and goes back to the instruction on release.
  private func updateHint(_ value: String? = nil) {
    hint.text = value ?? "拖把手改高度，键盘上左右拖改键距、上下拖改行间距"
  }

  private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(upper, max(lower, value))
  }
}

/// The height grip. VoiceOver reaches the keyboard's height through this rather than the pan, so
/// the setting is not a gesture-only control.
private final class HeightGripView: UIView {
  var onAdjust: ((Double) -> Void)?

  override func accessibilityIncrement() { onAdjust?(2) }
  override func accessibilityDecrement() { onAdjust?(-2) }
}
