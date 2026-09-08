import UIKit

final class KeyboardSchemePickerView: UIView {
  private var glyphBorders: [(UILabel, Bool)] = []
  private let accent = UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 1, green: 0.62, blue: 0.28, alpha: 1)
    : UIColor(red: 1, green: 0.47, blue: 0.10, alpha: 1) }

  init(selected: ChineseInputScheme, isChineseMode: Bool = true,
       onSelect: @escaping (ChineseInputScheme) -> Void,
       onSelectEnglish: (() -> Void)? = nil,
       onSelectSkin: ((KeyboardSkin) -> Void)? = nil,
       onSettings: (() -> Void)? = nil,
       onClose: @escaping () -> Void) {
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardSchemePicker"
    backgroundColor = .secondarySystemBackground

    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "chevron.left"), for: .normal)
    close.tintColor = .label
    close.accessibilityLabel = "返回键盘"
    close.accessibilityIdentifier = "closeSchemePicker"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)

    let keyboardTab = UIButton(type: .system)
    keyboardTab.setTitle("键盘", for: .normal)
    keyboardTab.accessibilityIdentifier = "schemePickerKeyboardTab"
    keyboardTab.accessibilityTraits.insert(.selected)
    let themeTab = UIButton(type: .system)
    themeTab.setTitle("主题", for: .normal)
    themeTab.accessibilityIdentifier = "schemePickerThemeTab"
    themeTab.isEnabled = onSelectSkin != nil
    let tabs = UIStackView(arrangedSubviews: [keyboardTab, themeTab])
    tabs.distribution = .fillEqually
    tabs.backgroundColor = .systemBackground
    tabs.layer.cornerRadius = 15
    for button in [keyboardTab, themeTab] {
      button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
      button.layer.cornerRadius = 15
      button.setTitleColor(.label, for: .normal)
    }
    keyboardTab.backgroundColor = accent
    keyboardTab.setTitleColor(.white, for: .normal)

    let settings = UIButton(type: .system)
    settings.setImage(UIImage(systemName: "gearshape"), for: .normal)
    settings.tintColor = .label
    settings.accessibilityLabel = "键盘设置"
    settings.accessibilityIdentifier = "schemePickerSettings"
    settings.isEnabled = onSettings != nil
    settings.addAction(UIAction { _ in onSettings?() }, for: .primaryActionTriggered)

    let content = UIView()
    let scroll = UIScrollView()
    scroll.accessibilityIdentifier = "schemePickerScroll"
    scroll.alwaysBounceVertical = false
    scroll.delaysContentTouches = false
    let panel = UIStackView()
    panel.axis = .vertical
    panel.spacing = 4
    panel.backgroundColor = .systemBackground
    panel.layer.cornerRadius = 18
    panel.isLayoutMarginsRelativeArrangement = true
    panel.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

    var cards: [UIView] = InputSchemePreference.enabledSchemes.map { scheme in
      let glyph: String
      let badge: String
      switch scheme {
      case .quanpin: glyph = "拼"; badge = "26"
      case .nineKey: glyph = "拼"; badge = "9"
      case .shuangpin: glyph = "鹤"; badge = "双"
      case .ziranma: glyph = "自"; badge = "双"
      case .microsoft: glyph = "微"; badge = "双"
      case .shoudao: glyph = "S"; badge = "双"
      case .wubi: glyph = "五"; badge = "86"
      case .japanese: glyph = "あ"; badge = "日"
      case .thoughtfulReply: glyph = "聊"; badge = "AI"
      }
      return makeCard(title: scheme.title, glyph: glyph, badge: badge,
        selected: isChineseMode && scheme == selected, identifier: "schemeCard-\(scheme.rawValue)") { onSelect(scheme) }
    }
    if let onSelectEnglish {
      // English is a platform text mode, not a second persisted Engine scheme.
      cards.insert(makeCard(title: "英文 26 键", glyph: "EN", badge: "26",
        selected: !isChineseMode, identifier: "schemeEnglishCard", action: onSelectEnglish), at: min(2, cards.count))
    }
    for start in stride(from: 0, to: cards.count, by: 4) {
      let row = UIStackView()
      row.spacing = 4
      row.distribution = .fillEqually
      for card in cards[start..<min(start + 4, cards.count)] { row.addArrangedSubview(card) }
      while row.arrangedSubviews.count < 4 { row.addArrangedSubview(UIView()) }
      panel.addArrangedSubview(row)
      row.heightAnchor.constraint(equalToConstant: 62).isActive = true
    }

    for child in [close, tabs, settings, content] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }
    scroll.translatesAutoresizingMaskIntoConstraints = false
    panel.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(scroll)
    scroll.addSubview(panel)
    NSLayoutConstraint.activate([
      close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      close.topAnchor.constraint(equalTo: topAnchor),
      close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
      settings.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      settings.topAnchor.constraint(equalTo: topAnchor),
      settings.widthAnchor.constraint(equalToConstant: 44), settings.heightAnchor.constraint(equalToConstant: 44),
      tabs.centerXAnchor.constraint(equalTo: centerXAnchor), tabs.centerYAnchor.constraint(equalTo: close.centerYAnchor),
      tabs.widthAnchor.constraint(equalToConstant: 150), tabs.heightAnchor.constraint(equalToConstant: 30),
      tabs.leadingAnchor.constraint(greaterThanOrEqualTo: close.trailingAnchor, constant: 8),
      tabs.trailingAnchor.constraint(lessThanOrEqualTo: settings.leadingAnchor, constant: -8),
      content.topAnchor.constraint(equalTo: close.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroll.topAnchor.constraint(equalTo: content.topAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      panel.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      panel.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
      panel.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      panel.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      panel.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
    let showTab: (Bool) -> Void = { [weak content, weak scroll, weak keyboardTab, weak themeTab, weak self] showThemes in
      guard let self, let content, let scroll, let keyboardTab, let themeTab else { return }
      scroll.isHidden = showThemes
      keyboardTab.backgroundColor = showThemes ? .clear : accent
      themeTab.backgroundColor = showThemes ? accent : .clear
      keyboardTab.setTitleColor(showThemes ? .label : .white, for: .normal)
      themeTab.setTitleColor(showThemes ? .white : .label, for: .normal)
      keyboardTab.accessibilityTraits = showThemes ? [.button] : [.button, .selected]
      themeTab.accessibilityTraits = showThemes ? [.button, .selected] : [.button]
      content.subviews.filter { $0 !== scroll }.forEach { $0.removeFromSuperview() }
      if showThemes, let onSelectSkin {
        let themes = KeyboardSkinPickerView(selected: KeyboardSkinPreference.selected,
          showsHeader: false, onSelect: onSelectSkin, onClose: onClose)
        themes.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(themes)
        NSLayoutConstraint.activate([
          themes.leadingAnchor.constraint(equalTo: content.leadingAnchor), themes.trailingAnchor.constraint(equalTo: content.trailingAnchor),
          themes.topAnchor.constraint(equalTo: content.topAnchor), themes.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
      }
    }
    keyboardTab.addAction(UIAction { _ in showTab(false) }, for: .primaryActionTriggered)
    themeTab.addAction(UIAction { _ in showTab(true) }, for: .primaryActionTriggered)
  }

  private func makeCard(title: String, glyph: String, badge: String, selected: Bool,
                        identifier: String, action: @escaping () -> Void) -> UIButton {
    let card = KeyboardKeyButton()
    card.accessibilityIdentifier = identifier
    card.accessibilityLabel = title
    card.accessibilityValue = selected ? "已选中" : ""
    if selected { card.accessibilityTraits.insert(.selected) }
    card.layer.cornerRadius = 13
    card.backgroundColor = selected ? accent.withAlphaComponent(0.10) : .clear
    let color: UIColor = selected ? accent : .label
    let symbol = UILabel()
    symbol.text = glyph
    symbol.textAlignment = .center
    symbol.font = .systemFont(ofSize: glyph.count > 1 ? 15 : 20, weight: .semibold)
    symbol.textColor = color
    symbol.layer.cornerRadius = 4
    symbol.layer.borderWidth = 1.7
    symbol.layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
    glyphBorders.append((symbol, selected))
    let suffix = UILabel()
    suffix.text = badge
    suffix.font = .systemFont(ofSize: 9, weight: .bold)
    suffix.textAlignment = .center
    suffix.textColor = color
    suffix.backgroundColor = .systemBackground
    let label = UILabel()
    label.text = title
    label.textAlignment = .center
    label.numberOfLines = 1
    label.font = .systemFont(ofSize: 12)
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.65
    label.textColor = color
    let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    check.tintColor = accent
    check.backgroundColor = .systemBackground
    check.layer.cornerRadius = 6
    check.isHidden = !selected
    for child in [symbol, suffix, label, check] {
      child.translatesAutoresizingMaskIntoConstraints = false
      child.isUserInteractionEnabled = false
      child.isAccessibilityElement = false
      card.addSubview(child)
    }
    NSLayoutConstraint.activate([
      symbol.topAnchor.constraint(equalTo: card.topAnchor, constant: 8), symbol.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      symbol.widthAnchor.constraint(equalToConstant: 27), symbol.heightAnchor.constraint(equalToConstant: 27),
      suffix.trailingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 4), suffix.bottomAnchor.constraint(equalTo: symbol.bottomAnchor, constant: 3),
      suffix.widthAnchor.constraint(equalToConstant: 16), suffix.heightAnchor.constraint(equalToConstant: 12),
      label.topAnchor.constraint(equalTo: symbol.bottomAnchor, constant: 6),
      label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 2), label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -2),
      label.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -4),
      check.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 1), check.topAnchor.constraint(equalTo: symbol.topAnchor, constant: -3),
      check.widthAnchor.constraint(equalToConstant: 12), check.heightAnchor.constraint(equalToConstant: 12),
    ])
    card.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
    return card
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    for (label, selected) in glyphBorders {
      label.layer.borderColor = (selected ? accent : UIColor.label).resolvedColor(with: traitCollection).cgColor
    }
  }
}
