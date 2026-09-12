import UIKit

/// 键位间距与语音入口的键盘内设置面板。
///
/// This replaced a grid of layout preset cards. Key placement no longer derives from a preset --
/// presets survive only as upgrade defaults for the spacing values -- so picking one changed
/// nothing the user could see. The spacing the geometry actually reads is editable here instead.
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

    let keys = Self.spacingRow(title: "按键间距", identifier: "keySpacingSlider", value: keySpacing,
                               range: 3...6, skin: skin, onChange: onKeySpacing)
    let rows = Self.spacingRow(title: "行间距", identifier: "rowSpacingSlider", value: rowSpacing,
                               range: 4...10, skin: skin, onChange: onRowSpacing)
    // Height belongs next to spacing: both answer "the keys are hard to hit", and sending someone
    // to the host app for one of them while the other is here would be arbitrary.
    let tall = Self.spacingRow(title: "键盘高度", identifier: "keyboardHeightSlider", value: height,
                               range: -12...48, skin: skin,
                               format: { $0 > 0 ? "+\(Int($0))" : "\(Int($0))" }, onChange: onHeight)

    let voiceLabel = UILabel(); voiceLabel.text = "顶部语音入口"; voiceLabel.font = .systemFont(ofSize: 14, weight: .medium); voiceLabel.textColor = skin.keyForeground
    let voiceSwitch = UISwitch(); voiceSwitch.isOn = voiceEnabled; voiceSwitch.onTintColor = skin.accent; voiceSwitch.accessibilityIdentifier = "voiceShortcutSwitch"; voiceSwitch.accessibilityLabel = "顶部语音入口"
    voiceSwitch.addAction(UIAction { action in
      guard let toggle = action.sender as? UISwitch else { return }
      onVoice(toggle.isOn)
    }, for: .valueChanged)
    let voice = UIStackView(arrangedSubviews: [voiceLabel, UIView(), voiceSwitch]); voice.alignment = .center; voice.spacing = 8

    let reset = UIButton(type: .system)
    reset.setTitle("恢复默认", for: .normal)
    reset.setTitleColor(.systemRed, for: .normal)
    reset.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    reset.contentHorizontalAlignment = .leading
    reset.accessibilityIdentifier = "resetKeyboardSettings"
    reset.accessibilityHint = "把间距、高度和语音入口恢复成默认值"
    reset.addAction(UIAction { _ in onReset() }, for: .primaryActionTriggered)

    let stack = UIStackView(arrangedSubviews: [keys, rows, tall, voice, reset]); stack.axis = .vertical; stack.spacing = 16
    for item in [title, close, stack] { item.translatesAutoresizingMaskIntoConstraints = false; addSubview(item) }
    NSLayoutConstraint.activate([
      close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      close.topAnchor.constraint(equalTo: topAnchor),
      close.widthAnchor.constraint(equalToConstant: 44),
      close.heightAnchor.constraint(equalToConstant: 44),
      title.centerXAnchor.constraint(equalTo: centerXAnchor),
      title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
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
