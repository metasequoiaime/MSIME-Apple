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
  init(keySpacing: Double, rowSpacing: Double, height: Double, voiceEnabled: Bool,
       onKeySpacing: @escaping (Double) -> Void,
       onRowSpacing: @escaping (Double) -> Void,
       onHeight: @escaping (Double) -> Void,
       onVoice: @escaping (Bool) -> Void,
       onReset: @escaping () -> Void,
       onClose: @escaping () -> Void) {
    super.init(frame: .zero); accessibilityIdentifier = "keyboardLayoutPicker"
    let skin = KeyboardSkinPreference.selected; backgroundColor = skin.background
    let title = UILabel(); title.text = "键盘设置"; title.font = .systemFont(ofSize: 17, weight: .semibold); title.textColor = skin.keyForeground
    let close = UIButton(type: .system); close.setImage(UIImage(systemName: "chevron.left"), for: .normal); close.tintColor = skin.accent; close.accessibilityIdentifier = "closeLayoutPicker"; close.accessibilityLabel = "返回键盘"; close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)
    let reset = UIButton(type: .system); reset.setTitle("恢复默认", for: .normal); reset.setTitleColor(.systemRed, for: .normal); reset.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium); reset.accessibilityIdentifier = "resetKeyboardSettings"; reset.accessibilityLabel = "恢复默认"; reset.accessibilityHint = "把间距、高度和语音入口恢复成默认值"; reset.addAction(UIAction { _ in onReset() }, for: .primaryActionTriggered)

    let keys = Self.spacingRow(title: "按键间距", identifier: "keySpacingSlider", value: keySpacing,
                               range: 3...6, skin: skin, onChange: onKeySpacing)
    let rows = Self.spacingRow(title: "行间距", identifier: "rowSpacingSlider", value: rowSpacing,
                               range: 4...10, skin: skin, onChange: onRowSpacing)
    let tall = Self.spacingRow(title: "键盘高度", identifier: "keyboardHeightSlider", value: height,
                               range: -12...48, skin: skin,
                               format: { $0 > 0 ? "+\(Int($0))" : "\(Int($0))" }, onChange: onHeight)

    let voiceLabel = UILabel(); voiceLabel.text = "顶部语音入口"; voiceLabel.font = .systemFont(ofSize: 14, weight: .medium); voiceLabel.textColor = skin.keyForeground
    let voiceSwitch = UISwitch(); voiceSwitch.isOn = voiceEnabled; voiceSwitch.onTintColor = skin.accent; voiceSwitch.accessibilityIdentifier = "voiceShortcutSwitch"; voiceSwitch.accessibilityLabel = "顶部语音入口"
    voiceSwitch.addAction(UIAction { action in
      guard let toggle = action.sender as? UISwitch else { return }
      onVoice(toggle.isOn)
    }, for: .valueChanged)

    let stack = UIStackView(arrangedSubviews: [keys, rows, tall, voice]); stack.axis = .vertical; stack.spacing = 16
    for item in [title, close, reset, stack] { item.translatesAutoresizingMaskIntoConstraints = false; addSubview(item) }
    NSLayoutConstraint.activate([
      close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      close.topAnchor.constraint(equalTo: topAnchor),
      close.widthAnchor.constraint(equalToConstant: 44),
      close.heightAnchor.constraint(equalToConstant: 44),
      title.centerXAnchor.constraint(equalTo: centerXAnchor),
      title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
      reset.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      reset.centerYAnchor.constraint(equalTo: close.centerYAnchor),
      reset.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
      stack.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 12),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private static func spacingRow(title: String, identifier: String, value: Double,
                                 range: ClosedRange<Double>, skin: KeyboardSkin,
                                 format: @escaping (Double) -> String = { String(format: "%.1f", $0) },
                                 onChange: @escaping (Double) -> Void) -> UIStackView {
    let caption = UILabel(); caption.text = title; caption.font = .systemFont(ofSize: 14, weight: .medium); caption.textColor = skin.keyForeground
    let amount = UILabel(); amount.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular); amount.textColor = skin.keyForeground.withAlphaComponent(0.7)
    amount.text = format(value)
    let header = UIStackView(arrangedSubviews: [caption, UIView(), amount]); header.alignment = .firstBaseline; header.spacing = 8
    let slider = UISlider(); slider.minimumValue = Float(range.lowerBound); slider.maximumValue = Float(range.upperBound)
    slider.value = Float(value); slider.minimumTrackTintColor = skin.accent; slider.accessibilityIdentifier = identifier; slider.accessibilityLabel = title
    slider.addAction(UIAction { action in
      guard let slider = action.sender as? UISlider else { return }
      amount.text = format(Double(slider.value))
      onChange(Double(slider.value))
    }, for: .valueChanged)
    let row = UIStackView(arrangedSubviews: [header, slider]); row.axis = .vertical; row.spacing = 4
    return row
  }
}

/// The height grip. VoiceOver reaches the keyboard's height through this rather than the pan, so
/// the setting is not a gesture-only control.
private final class HeightGripView: UIView {
  var onAdjust: ((Double) -> Void)?

  override func accessibilityIncrement() { onAdjust?(2) }
  override func accessibilityDecrement() { onAdjust?(-2) }
}
