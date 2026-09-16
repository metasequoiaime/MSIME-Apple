import UIKit

/// Symbol panel: categories down the left, the symbols filling the rest, 返回 / 锁定 / ⌫ along the
/// bottom.
///
/// The 符 key used to open a menu of sixteen marks. A menu covers the keyboard, has to be aimed at
/// and dragged through, and gives one mark per press. Replacing the keyboard surface with a panel
/// is what every other IME does, and it is what a run of punctuation needs.
final class KeyboardSymbolPanelView: UIView {
  struct Category {
    let title: String
    let symbols: [String]
  }

  /// Ordered by how often a category is reached for while typing, most frequent first.
  static let categories: [Category] = [
    Category(title: "常用", symbols: [
      "，", "。", "？", "！", "、", "；", "：", "…", "—", "·",
      "“", "”", "‘", "’", "（", "）", "《", "》", "【", "】",
      "～", "￥", "＆", "＃", "＠", "％", "＋", "－", "＝", "／",
    ]),
    Category(title: "中文", symbols: [
      "〈", "〉", "「", "」", "『", "』", "〔", "〕", "〖", "〗",
      "＜", "＞", "｛", "｝", "［", "］", "︵", "︶", "﹁", "﹂",
      "￥", "〇", "※", "°", "℃", "±", "×", "÷", "≈", "≠",
      "≤", "≥", "√", "∞", "∵", "∴", "→", "←", "↑", "↓",
      "★", "☆", "●", "○", "■", "□", "◆", "◇", "▲", "△",
    ]),
    Category(title: "英文", symbols: [
      ",", ".", "?", "!", ";", ":", "'", "\"", "(", ")",
      "[", "]", "{", "}", "<", ">", "/", "\\", "|", "-",
      "_", "+", "=", "*", "&", "^", "%", "$", "#", "@",
      "~", "`", "·", "…", "–", "—", "§", "¶", "†", "‡",
    ]),
    Category(title: "数字", symbols: [
      "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
      "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
      "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
      "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ",
      "½", "⅓", "¼", "‰", "′", "″", "㎡", "㎏", "㎝", "№",
    ]),
    Category(title: "网络", symbols: [
      "@", "#", "/", "\\", ":", "_", "-", "+", "=", "&",
      "?", "%", "~", "^", "*", "|", "<", ">", "$", "€",
      "http://", "https://", "www.", ".com", ".cn", ".net", ".org", ".io", "@qq.com", "@gmail.com",
    ]),
  ]

  private let onInsert: (String) -> Void
  private let onDelete: () -> Void
  private let onClose: () -> Void
  private let skin = KeyboardSkinPreference.selected
  private let grid = UIStackView()
  private let scroll = UIScrollView()
  private var categoryButtons: [UIButton] = []
  private var selected = 0
  /// Locked keeps the panel up for a run of symbols. Unlocked is the default because most of the
  /// time this is one 、 and then back to writing.
  private var locked = false
  private var lockButton: UIButton!

  init(onInsert: @escaping (String) -> Void, onDelete: @escaping () -> Void,
       onClose: @escaping () -> Void) {
    self.onInsert = onInsert
    self.onDelete = onDelete
    self.onClose = onClose
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardSymbolPanel"
    backgroundColor = skin.background

    let categories = UIStackView()
    categories.axis = .vertical
    categories.distribution = .fillEqually
    categories.spacing = 1
    for (index, category) in Self.categories.enumerated() {
      let button = UIButton(type: .system)
      button.setTitle(category.title, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 15)
      button.accessibilityIdentifier = "symbolCategory_\(index)"
      button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .primaryActionTriggered)
      categoryButtons.append(button)
      categories.addArrangedSubview(button)
    }

    grid.axis = .vertical
    grid.spacing = 1
    scroll.showsVerticalScrollIndicator = true
    scroll.disableEdgeEffects()
    scroll.accessibilityIdentifier = "symbolGrid"
    grid.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(grid)

    let back = bar(title: "返回", symbol: nil, identifier: "closeSymbolPanel") { [weak self] in
      self?.onClose()
    }
    back.accessibilityLabel = "返回键盘"
    lockButton = bar(title: nil, symbol: "lock.open", identifier: "symbolLockKey") { [weak self] in
      guard let self else { return }
      locked.toggle()
      updateLock()
    }
    let delete = bar(title: nil, symbol: "delete.left", identifier: "symbolDeleteKey") { [weak self] in
      self?.onDelete()
    }
    delete.accessibilityLabel = "删除"
    updateLock()

    let bottom = UIStackView(arrangedSubviews: [back, lockButton, delete])
    bottom.axis = .horizontal
    bottom.distribution = .fillEqually
    bottom.spacing = 1

    for item in [categories, scroll, bottom] {
      item.translatesAutoresizingMaskIntoConstraints = false
      addSubview(item)
    }
    NSLayoutConstraint.activate([
      categories.leadingAnchor.constraint(equalTo: leadingAnchor),
      categories.topAnchor.constraint(equalTo: topAnchor),
      categories.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -1),
      categories.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.2),
      scroll.leadingAnchor.constraint(equalTo: categories.trailingAnchor, constant: 1),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -1),
      grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      grid.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      bottom.leadingAnchor.constraint(equalTo: leadingAnchor),
      bottom.trailingAnchor.constraint(equalTo: trailingAnchor),
      bottom.bottomAnchor.constraint(equalTo: bottomAnchor),
      bottom.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.2),
    ])
    select(0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  private static let columns = 5
  /// Fixed rather than dividing the available height: dividing squeezes a category thinner as it
  /// grows, and a symbol panel is the one surface where "there is more" is the point. Anything that
  /// does not fit scrolls.
  private static let rowHeight: CGFloat = 46

  private func select(_ index: Int) {
    guard Self.categories.indices.contains(index) else { return }
    selected = index
    for (position, button) in categoryButtons.enumerated() {
      let active = position == index
      button.backgroundColor = active ? skin.background : skin.keyBackground
      button.setTitleColor(active ? skin.accent : skin.keyForeground, for: .normal)
      button.accessibilityTraits = active ? [.button, .selected] : [.button]
    }
    for row in grid.arrangedSubviews {
      grid.removeArrangedSubview(row)
      row.removeFromSuperview()
    }
    scroll.setContentOffset(.zero, animated: false)
    let symbols = Self.categories[index].symbols
    for start in stride(from: 0, to: symbols.count, by: Self.columns) {
      let row = UIStackView()
      row.axis = .horizontal
      row.distribution = .fillEqually
      row.spacing = 1
      let slice = symbols[start..<min(start + Self.columns, symbols.count)]
      for symbol in slice { row.addArrangedSubview(key(symbol)) }
      // Pad a short final row, otherwise the few keys left are stretched across the width.
      for _ in slice.count..<Self.columns { row.addArrangedSubview(UIView()) }
      row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
      grid.addArrangedSubview(row)
    }
  }

  private func key(_ symbol: String) -> UIButton {
    let button = KeyboardKeyButton(type: .system)
    button.setTitle(symbol, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 18)
    button.titleLabel?.adjustsFontSizeToFitWidth = true
    button.titleLabel?.minimumScaleFactor = 0.6
    button.setTitleColor(skin.keyForeground, for: .normal)
    button.backgroundColor = skin.keyBackground
    button.accessibilityIdentifier = "symbolKey_\(symbol)"
    button.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      onInsert(symbol)
      // Unlocked means one symbol and back to the keys; asking for another tap on 返回 is a step
      // nobody wants after a single 、.
      if !locked { onClose() }
    }, for: .primaryActionTriggered)
    return button
  }

  private func bar(title: String?, symbol: String?, identifier: String,
                   action: @escaping () -> Void) -> UIButton {
    let button = KeyboardKeyButton(type: .system)
    if let title {
      button.setTitle(title, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 15)
    }
    if let symbol { button.setImage(UIImage(systemName: symbol), for: .normal) }
    button.tintColor = skin.keyForeground
    button.setTitleColor(skin.keyForeground, for: .normal)
    button.backgroundColor = skin.keyBackground
    button.accessibilityIdentifier = identifier
    button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
    return button
  }

  private func updateLock() {
    lockButton.setImage(UIImage(systemName: locked ? "lock" : "lock.open"), for: .normal)
    lockButton.tintColor = locked ? skin.accent : skin.keyForeground
    lockButton.accessibilityLabel = locked ? "已锁定，连续输入符号" : "锁定，连续输入符号"
    lockButton.accessibilityTraits = locked ? [.button, .selected] : [.button]
  }
}
