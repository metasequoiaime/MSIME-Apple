import UIKit

/// 键位间距与键盘高度的键盘内设置面板。
///
/// This replaced a grid of layout preset cards. Key placement no longer derives from a preset --
/// presets survive only as upgrade defaults for the spacing values -- so picking one changed
/// nothing the user could see. The spacing the geometry actually reads is editable here instead.
final class KeyboardLayoutPickerView: UIView {
  init(keySpacing: Double, rowSpacing: Double, height: Double,
       onKeySpacing: @escaping (Double) -> Void,
       onRowSpacing: @escaping (Double) -> Void,
       onHeight: @escaping (Double) -> Void,
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

    // On the title row rather than under the controls. The panel is only as tall as the keyboard,
    // and the sliders already fill it: a fifth row pushed the stack past the space it had, and Auto
    // Layout answered by squeezing the sliders until they could not be dragged and the rows
    // overlapped each other.
    let reset = UIButton(type: .system)
    reset.setTitle("恢复默认", for: .normal)
    reset.setTitleColor(.systemRed, for: .normal)
    reset.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    reset.accessibilityIdentifier = "resetKeyboardSettings"
    reset.accessibilityHint = "把间距和高度恢复成默认值"
    reset.addAction(UIAction { _ in onReset() }, for: .primaryActionTriggered)

    let stack = UIStackView(arrangedSubviews: [keys, rows, tall]); stack.axis = .vertical; stack.spacing = 16
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
