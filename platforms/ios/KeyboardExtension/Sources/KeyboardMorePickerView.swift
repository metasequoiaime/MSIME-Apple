import UIKit

final class KeyboardMorePickerView: UIView {
  private let rows = UIStackView()

  init(menu: UIMenu, title: String = "工具", onClose: @escaping () -> Void) {
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardMorePicker"
    let skin = KeyboardSkinPreference.selected
    backgroundColor = MetasequoiaTheme.keyboardBackground
    let header = UILabel()
    header.text = title
    header.font = .systemFont(ofSize: 14, weight: .semibold)
    header.textColor = .secondaryLabel
    let close = UIButton(type: .system)
    var back = UIButton.Configuration.plain()
    back.title = "返回"
    back.image = UIImage(systemName: "chevron.left")
    back.preferredSymbolConfigurationForImage = .init(pointSize: 14, weight: .semibold)
    back.imagePadding = 5
    back.baseForegroundColor = skin.accent
    back.contentInsets = .init(top: 0, leading: 6, bottom: 0, trailing: 10)
    close.configuration = back
    close.accessibilityLabel = "返回键盘"
    close.accessibilityIdentifier = "closeMorePicker"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)
    let scroll = UIScrollView()
    rows.axis = .vertical
    rows.spacing = 6
    scroll.showsVerticalScrollIndicator = false
    scroll.alwaysBounceVertical = false
    // This panel already sits below its own header; a system edge veil obscures the first tool.
    scroll.disableEdgeEffects()
    for child in [header, close, scroll] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }
    rows.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(rows)
    NSLayoutConstraint.activate([
      header.centerXAnchor.constraint(equalTo: centerXAnchor),
      header.topAnchor.constraint(equalTo: topAnchor),
      header.heightAnchor.constraint(equalToConstant: 44),
      close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      close.topAnchor.constraint(equalTo: topAnchor),
      close.heightAnchor.constraint(equalToConstant: 44),
      close.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
      scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
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
      label.font = .systemFont(ofSize: 11, weight: .medium)
      label.textColor = .secondaryLabel
      label.heightAnchor.constraint(equalToConstant: 20).isActive = true
      rows.addArrangedSubview(label)
    }
    let actions = menu.children.compactMap { $0 as? UIAction }
    let skin = KeyboardSkinPreference.selected
    let columns = menu.title.isEmpty ? 1 : (menu.title == "振动强度" ? 3 : 2)
    for index in stride(from: 0, to: actions.count, by: columns) {
      let row = UIStackView()
      row.spacing = 8
      row.distribution = .fillEqually
      for action in actions[index..<min(index + columns, actions.count)] {
        let active = action.state == .on
        let state = menu.title == "按键反馈" ? (active ? "已开启" : "已关闭")
          : (["振动强度", "键盘布局", "输出字形"].contains(menu.title)
            ? (active ? "已选中" : "点击选择") : "点击打开")
        let card = KeyboardKeyButton()
        var configuration = UIButton.Configuration.filled()
        configuration.title = action.title
        configuration.subtitle = menu.title == "按键反馈" ? state : nil
        configuration.image = action.image
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .medium)
        configuration.contentInsets = .init(top: 6, leading: 12, bottom: 6, trailing: menu.title.isEmpty ? 32 : 12)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleAlignment = .leading
        configuration.baseForegroundColor = skin.keyForeground
        configuration.baseBackgroundColor = active ? skin.accent.withAlphaComponent(0.12) : skin.keyBackground
        configuration.background.cornerRadius = 10
        configuration.background.strokeWidth = 0
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { value in
          var value = value; value.font = .systemFont(ofSize: 14, weight: .medium); return value
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { value in
          var value = value; value.font = .systemFont(ofSize: 11); value.foregroundColor = skin.keyForeground.withAlphaComponent(0.7); return value
        }
        card.configuration = configuration
        card.contentHorizontalAlignment = menu.title.isEmpty ? .leading : .center
        card.heightAnchor.constraint(equalToConstant: 48).isActive = true
        if menu.title.isEmpty {
          let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
          chevron.preferredSymbolConfiguration = .init(pointSize: 11, weight: .semibold)
          chevron.tintColor = skin.keyForeground.withAlphaComponent(0.35)
          chevron.contentMode = .scaleAspectFit
          chevron.translatesAutoresizingMaskIntoConstraints = false
          card.addSubview(chevron)
          NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 14),
          ])
        }
        card.accessibilityIdentifier = "moreCard-" + action.title
        card.accessibilityLabel = action.title
        card.accessibilityValue = state
        card.isEnabled = !action.attributes.contains(.disabled)
        if active { card.accessibilityTraits.insert(.selected) }
        card.addAction(action, for: .primaryActionTriggered)
        row.addArrangedSubview(card)
      }
      while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
      rows.addArrangedSubview(row)
    }
    menu.children.compactMap { $0 as? UIMenu }.forEach { append(menu: $0) }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
