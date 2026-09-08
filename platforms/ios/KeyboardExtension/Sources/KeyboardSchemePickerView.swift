import UIKit

final class KeyboardSchemePickerView: UIView {
  init(selected: ChineseInputScheme, onSelect: @escaping (ChineseInputScheme) -> Void, onClose: @escaping () -> Void) {
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardSchemePicker"
    backgroundColor = .secondarySystemBackground
    let skin = KeyboardSkinPreference.selected
    let header = UILabel()
    header.text = "选择输入方案"
    header.font = .systemFont(ofSize: 17, weight: .semibold)
    let close = UIButton(type: .system)
    close.setTitle("完成", for: .normal)
    close.accessibilityIdentifier = "closeSchemePicker"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)
    let scroll = UIScrollView()
    let rows = UIStackView()
    rows.axis = .vertical
    rows.spacing = 10
    let schemes = InputSchemePreference.enabledSchemes
    for index in stride(from: 0, to: schemes.count, by: 2) {
      let row = UIStackView()
      row.spacing = 10
      row.distribution = .fillEqually
      for scheme in schemes[index..<min(index + 2, schemes.count)] {
        let card = KeyboardKeyButton()
        card.accessibilityIdentifier = "schemeCard-\(scheme.rawValue)"
        card.accessibilityLabel = scheme.title
        card.accessibilityValue = scheme == selected ? "已选中" : ""
        if scheme == selected { card.accessibilityTraits.insert(.selected) }
        card.backgroundColor = skin.background
        card.layer.cornerRadius = 12
        card.layer.borderWidth = scheme == selected ? 2 : 1
        card.layer.borderColor = (scheme == selected ? UIColor.label : UIColor.separator).resolvedColor(with: traitCollection).cgColor
        card.clipsToBounds = true
        let title = UILabel()
        title.text = scheme.title + (scheme == selected ? "  ✓" : "")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = skin.keyForeground
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.75
        let preview = KeyboardSkinMiniature(skin: skin, nineKey: scheme == .nineKey)
        for child in [title, preview] {
          child.isUserInteractionEnabled = false
          child.translatesAutoresizingMaskIntoConstraints = false
          card.addSubview(child)
        }
        let preferredWidth = preview.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -14)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
          preferredWidth,
          preview.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
          preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: KeyboardSkinMiniature.heightToWidthRatio),
          preview.centerXAnchor.constraint(equalTo: card.centerXAnchor),
          title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
          title.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
          title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
          preview.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 7),
          preview.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -7),
          preview.topAnchor.constraint(equalTo: card.topAnchor, constant: 29),
          preview.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -7),
        ])
        card.addAction(UIAction { _ in onSelect(scheme) }, for: .primaryActionTriggered)
        row.addArrangedSubview(card)
      }
      if row.arrangedSubviews.count == 1 { row.addArrangedSubview(UIView()) }
      rows.addArrangedSubview(row)
    }
    for child in [header, close, scroll] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }
    rows.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(rows)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      header.topAnchor.constraint(equalTo: topAnchor),
      header.heightAnchor.constraint(equalToConstant: 40),
      close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      close.topAnchor.constraint(equalTo: topAnchor),
      close.heightAnchor.constraint(equalToConstant: 40),
      close.widthAnchor.constraint(equalToConstant: 56),
      scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
      rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
