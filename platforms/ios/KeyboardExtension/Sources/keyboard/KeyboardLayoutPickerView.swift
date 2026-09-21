import UIKit

/// Keyboard spacing and height are adjusted over the live keyboard rather than in an opaque form.
///
/// The keyboard remains visible below the small toolbar: step or drag the height control, drag
/// sideways on the keyboard to change key spacing, and drag vertically to change row spacing.
///
/// 高度原先只有一根 46×5pt 的把手可拖。它有两个毛病:当前值只在拖动过程中出现,想知道现在是多少就得先
/// 改一下;而且整个 −12…48 的范围只有 60pt 的手指行程,挤在一条 52pt 的工具条上,很容易冲过头,又没有
/// 任何精调手段(除了 VoiceOver 的 ±2)。现在数值常驻,两个按钮每次走 2,同一块区域仍可上下拖做粗调。
final class KeyboardLayoutPickerView: UIView {
  private static let spacingDragScale: Double = 18
  private static let barHeight: CGFloat = 52
  private static let heightRange: (lower: Double, upper: Double) = (-12, 48)
  /// 和 VoiceOver 的增减一步一致 —— 同一个控件不该因为用眼睛还是用手势而走不同的步长。
  private static let step: Double = 2

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
  private let heightValue = UILabel()
  private weak var heightControl: HeightGripView?
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

    heightValue.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
    heightValue.textColor = skin.keyForeground
    heightValue.textAlignment = .center
    heightValue.adjustsFontSizeToFitWidth = true
    heightValue.minimumScaleFactor = 0.7
    heightValue.accessibilityIdentifier = "keyboardHeightValue"

    let decrease = stepButton("minus", label: "降低键盘高度", skin: skin, delta: -Self.step)
    decrease.accessibilityIdentifier = "keyboardHeightDecrease"
    let increase = stepButton("plus", label: "升高键盘高度", skin: skin, delta: Self.step)
    increase.accessibilityIdentifier = "keyboardHeightIncrease"

    let heightControl = HeightGripView()
    self.heightControl = heightControl
    heightControl.backgroundColor = .clear
    heightControl.accessibilityIdentifier = "keyboardHeightGrip"
    heightControl.accessibilityLabel = "键盘高度"
    // 整块做成一个可调节元素,而不是让 VoiceOver 分别读到两个按钮:调节手势本来就是这类控件的惯用法,
    // 而两个按钮做的是同一件事的两个方向。± 仍然留给用眼睛的人。
    heightControl.isAccessibilityElement = true
    heightControl.accessibilityTraits = .adjustable
    heightControl.onAdjust = { [weak self] delta in self?.adjustHeight(by: delta) }
    heightControl.addGestureRecognizer(
      UIPanGestureRecognizer(target: self, action: #selector(dragHeight(_:))))

    let heightRow = UIStackView(arrangedSubviews: [decrease, heightValue, increase])
    heightRow.axis = .horizontal
    heightRow.alignment = .center
    heightRow.spacing = 8
    heightRow.translatesAutoresizingMaskIntoConstraints = false
    heightControl.addSubview(heightRow)
    // 点和拖共存:按钮照常收到点击,而落在它们身上的拖动一旦超过识别阈值,仍由 heightControl 上的
    // pan 接手 —— 手指从「+」上往下抹一把也该改高度,不该什么都没发生。
    NSLayoutConstraint.activate([
      heightRow.leadingAnchor.constraint(equalTo: heightControl.leadingAnchor),
      heightRow.trailingAnchor.constraint(equalTo: heightControl.trailingAnchor),
      heightRow.centerYAnchor.constraint(equalTo: heightControl.centerYAnchor),
    ])

    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragSpacing(_:))))

    for item in [bar, close, reset, hint, voice, heightControl] {
      item.translatesAutoresizingMaskIntoConstraints = false
      addSubview(item)
    }
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      bar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
      close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
      reset.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
      // 高度占第一行的中段,间距说明退到第二行 —— 高度的数值现在常驻,说明不再需要和它抢同一行。
      heightControl.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
      heightControl.centerYAnchor.constraint(equalTo: bar.topAnchor, constant: 18),
      heightControl.heightAnchor.constraint(equalToConstant: 32),
      heightControl.leadingAnchor.constraint(greaterThanOrEqualTo: reset.trailingAnchor, constant: 6),
      heightControl.trailingAnchor.constraint(lessThanOrEqualTo: voice.leadingAnchor, constant: -6),
      close.centerYAnchor.constraint(equalTo: heightControl.centerYAnchor),
      reset.centerYAnchor.constraint(equalTo: heightControl.centerYAnchor),
      voice.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -7),
      voice.centerYAnchor.constraint(equalTo: heightControl.centerYAnchor),
      hint.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
      hint.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
      hint.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -5),
    ])
    updateHeightValue()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func accessibilityIncrement() { adjustHeight(by: 2) }
  override func accessibilityDecrement() { adjustHeight(by: -2) }

  private func stepButton(_ symbol: String, label: String, skin: KeyboardSkin,
                          delta: Double) -> UIButton {
    let button = UIButton(type: .system)
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: symbol)
    configuration.preferredSymbolConfigurationForImage = .init(pointSize: 13, weight: .semibold)
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
    configuration.background.backgroundColor = skin.accent.withAlphaComponent(0.12)
    configuration.background.cornerRadius = 8
    configuration.baseForegroundColor = skin.accent
    button.configuration = configuration
    button.accessibilityLabel = label
    button.addAction(UIAction { [weak self] _ in self?.adjustHeight(by: delta) },
                     for: .primaryActionTriggered)
    return button
  }

  private func adjustHeight(by delta: Double) {
    height = Self.clamp(height + delta, Self.heightRange.lower, Self.heightRange.upper)
    onHeight(height)
    onCommit()
    updateHeightValue()
  }

  private func updateHeightValue() {
    heightValue.text = "高度 " + Self.format(height)
    // 可调节元素读出来的就是这一个数,不再需要用户先改一下才知道现在是多少。
    heightControl?.accessibilityValue = Self.format(height)
  }

  private static func format(_ value: Double) -> String {
    value > 0 ? "+\(Int(value))" : "\(Int(value))"
  }

  @objc private func dragHeight(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      base = (keySpacing, rowSpacing, height)
    case .changed:
      height = Self.clamp(base.height - Double(gesture.translation(in: self).y),
                          Self.heightRange.lower, Self.heightRange.upper)
      onHeight(height)
      updateHeightValue()
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
    hint.text = value ?? "键盘上左右拖改键距，上下拖改行间距"
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
