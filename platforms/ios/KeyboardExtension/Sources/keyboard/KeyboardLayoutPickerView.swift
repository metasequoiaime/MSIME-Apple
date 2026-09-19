import UIKit

/// Keyboard spacing and height are adjusted over the live keyboard rather than in an opaque form.
///
/// The keyboard remains visible below the small toolbar: drag the grip to change height, drag
/// sideways on the keyboard to change key spacing, and drag vertically to change row spacing.
final class KeyboardLayoutPickerView: UIView {
  private static let spacingDragScale: Double = 18
  private static let barHeight: CGFloat = 52

  private enum Axis { case vertical, horizontal }

  private let onKeySpacing: (Double) -> Void
  private let onRowSpacing: (Double) -> Void
  private let onHeight: (Double) -> Void
  /// Called when a drag ends, so the value it settled on can be written somewhere slower than the
  /// live keyboard. The drags themselves report on every gesture frame.
  private let onCommit: () -> Void
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
       onCommit: @escaping () -> Void,
       onVoice: @escaping (Bool) -> Void,
       onReset: @escaping () -> Void,
       onClose: @escaping () -> Void) {
    self.keySpacing = keySpacing
    self.rowSpacing = rowSpacing
    self.height = height
    self.onKeySpacing = onKeySpacing
    self.onRowSpacing = onRowSpacing
    self.onHeight = onHeight
    self.onCommit = onCommit
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardLayoutPicker"
    let skin = KeyboardSkinPreference.selected
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
    reset.accessibilityHint = "把间距和高度恢复成默认值"
    reset.addAction(UIAction { _ in onReset() }, for: .primaryActionTriggered)

    hint.font = .systemFont(ofSize: 13)
    hint.textColor = skin.keyForeground.withAlphaComponent(0.75)
    hint.textAlignment = .center
    hint.adjustsFontSizeToFitWidth = true
    hint.minimumScaleFactor = 0.7
    hint.accessibilityIdentifier = "layoutAdjustHint"
    updateHint()

    let voiceLabel = UILabel()
    voiceLabel.text = "语音"
    voiceLabel.font = .systemFont(ofSize: 12, weight: .medium)
    voiceLabel.textColor = skin.keyForeground.withAlphaComponent(0.75)
    let voiceSwitch = UISwitch()
    voiceSwitch.isOn = voiceEnabled
    voiceSwitch.onTintColor = skin.accent
    voiceSwitch.accessibilityIdentifier = "voiceShortcutSwitch"
    voiceSwitch.accessibilityLabel = "顶部语音入口"
    voiceSwitch.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
    voiceSwitch.addAction(UIAction { action in
      guard let toggle = action.sender as? UISwitch else { return }
      onVoice(toggle.isOn)
    }, for: .valueChanged)
    let voice = UIStackView(arrangedSubviews: [voiceLabel, voiceSwitch])
    voice.axis = .horizontal
    voice.alignment = .center
    voice.spacing = 3

    grip.backgroundColor = skin.accent.withAlphaComponent(0.45)
    grip.layer.cornerRadius = 2.5
    grip.isUserInteractionEnabled = false

    let gripTarget = HeightGripView()
    gripTarget.backgroundColor = .clear
    gripTarget.accessibilityIdentifier = "keyboardHeightGrip"
    gripTarget.accessibilityLabel = "键盘高度"
    gripTarget.isAccessibilityElement = true
    gripTarget.accessibilityTraits = .adjustable
    gripTarget.onAdjust = { [weak self] delta in self?.adjustHeight(by: delta) }
    gripTarget.addGestureRecognizer(
      UIPanGestureRecognizer(target: self, action: #selector(dragHeight(_:))))

    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragSpacing(_:))))

    for item in [bar, close, reset, hint, voice, grip, gripTarget] {
      item.translatesAutoresizingMaskIntoConstraints = false
      addSubview(item)
    }
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      bar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
      close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
      close.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      reset.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
      reset.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      hint.leadingAnchor.constraint(equalTo: reset.trailingAnchor, constant: 8),
      hint.trailingAnchor.constraint(equalTo: voice.leadingAnchor, constant: -6),
      hint.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
      voice.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -7),
      voice.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      grip.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
      grip.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -6),
      grip.widthAnchor.constraint(equalToConstant: 46),
      grip.heightAnchor.constraint(equalToConstant: 5),
      gripTarget.leadingAnchor.constraint(equalTo: reset.trailingAnchor),
      gripTarget.trailingAnchor.constraint(equalTo: voice.leadingAnchor),
      gripTarget.topAnchor.constraint(equalTo: bar.topAnchor),
      gripTarget.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func accessibilityIncrement() { adjustHeight(by: 2) }
  override func accessibilityDecrement() { adjustHeight(by: -2) }

  private func adjustHeight(by delta: Double) {
    height = Self.clamp(height + delta, -12, 48)
    onHeight(height)
    onCommit()
    updateHint()
  }

  @objc private func dragHeight(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      base = (keySpacing, rowSpacing, height)
    case .changed:
      height = Self.clamp(base.height - Double(gesture.translation(in: self).y), -12, 48)
      onHeight(height)
      updateHint("键盘高度 \(height > 0 ? "+" : "")\(Int(height))")
    default:
      axis = nil
      onCommit()
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
      onCommit()
      updateHint()
    }
  }

  private func updateHint(_ value: String? = nil) {
    hint.text = value ?? "拖把手改高度，键盘上左右拖改键距、上下拖改行间距"
  }

  private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(upper, max(lower, value))
  }
}

private final class HeightGripView: UIView {
  var onAdjust: ((Double) -> Void)?

  override func accessibilityIncrement() { onAdjust?(2) }
  override func accessibilityDecrement() { onAdjust?(-2) }
}
