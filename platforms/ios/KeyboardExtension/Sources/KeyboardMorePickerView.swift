import UIKit

final class KeyboardMorePickerView: UIView {
  private let rows = UIStackView()

  init(menu: UIMenu, title: String = "更多", onClose: @escaping () -> Void) {
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardMorePicker"
    backgroundColor = .secondarySystemBackground
    let header = UILabel()
    header.text = title
    header.font = .systemFont(ofSize: 17, weight: .semibold)
    let close = UIButton(type: .system)
    close.setTitle("完成", for: .normal)
    close.accessibilityIdentifier = "closeMorePicker"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)
    let scroll = UIScrollView()
    rows.axis = .vertical
    rows.spacing = 10
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
    update(menu: menu)
  }

  func update(menu: UIMenu) {
    rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
    append(menu: menu)
  }

  private func append(menu: UIMenu) {
    if !menu.title.isEmpty {
      let label = UILabel()
      label.text = menu.title
      label.font = .systemFont(ofSize: 13, weight: .semibold)
      label.textColor = .secondaryLabel
      rows.addArrangedSubview(label)
    }
    let actions = menu.children.compactMap { $0 as? UIAction }
    let skin = KeyboardSkinPreference.selected
    for index in stride(from: 0, to: actions.count, by: 2) {
      let row = UIStackView()
      row.spacing = 10
      row.distribution = .fillEqually
      for action in actions[index..<min(index + 2, actions.count)] {
        let active = action.state == .on
        let state = menu.title == "按键反馈" ? (active ? "已开启" : "已关闭")
          : (["振动强度", "键盘布局"].contains(menu.title) ? (active ? "已选中" : "点击选择") : "点击打开")
        let card = KeyboardKeyButton()
        var configuration = UIButton.Configuration.filled()
        configuration.title = action.title
        let descriptions = ["剪贴板历史": "最近保存的内容", "AI 润色": "润色选中的文字", "语音结果": "插入识别结果"]
        configuration.subtitle = KeyboardLayoutPreset.allCases.first { $0.title == action.title }?.detail ?? descriptions[action.title] ?? (menu.title == "本地输入" ? "离线输入工具" : state)
        configuration.image = action.image ?? UIImage(systemName: "keyboard")
        configuration.imagePlacement = .top
        configuration.imagePadding = 8
        configuration.preferredSymbolConfigurationForImage = .init(pointSize: 24)
        configuration.baseForegroundColor = skin.keyForeground
        configuration.baseBackgroundColor = skin.keyBackground
        configuration.background.cornerRadius = 12
        configuration.background.strokeWidth = active ? 2 : 1
        configuration.background.strokeColor = active ? skin.accent : .separator
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { value in
          var value = value; value.font = .systemFont(ofSize: 13, weight: .semibold); return value
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { value in
          var value = value; value.font = .systemFont(ofSize: 11); value.foregroundColor = skin.keyForeground.withAlphaComponent(0.7); return value
        }
        card.configuration = configuration
        card.heightAnchor.constraint(equalToConstant: 100).isActive = true
        card.accessibilityIdentifier = "moreCard-" + action.title
        card.accessibilityLabel = action.title
        card.accessibilityValue = state
        card.isEnabled = !action.attributes.contains(.disabled)
        if active { card.accessibilityTraits.insert(.selected) }
        card.addAction(action, for: .primaryActionTriggered)
        row.addArrangedSubview(card)
      }
      if row.arrangedSubviews.count == 1 { row.addArrangedSubview(UIView()) }
      rows.addArrangedSubview(row)
    }
    menu.children.compactMap { $0 as? UIMenu }.forEach { append(menu: $0) }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
