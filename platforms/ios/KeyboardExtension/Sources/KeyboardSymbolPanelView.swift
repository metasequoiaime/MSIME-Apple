import UIKit

/// 符号面板:左边分类,右边一整屏符号,底下返回 / 锁定 / 退格。
///
/// 「符」键原来是一颗弹菜单的键:按下去弹出一列十六个标点,要滑、要瞄,一次只给一个,而且盖在键盘上看不见自己在打什么。别家输入法的符号都是把键盘整块换成符号面板 —— 分类在左手边,符号铺满,连着点几个再回去。这个面板就是那一套。
final class KeyboardSymbolPanelView: UIView {
  /// 一个分类。
  struct Category {
    let title: String
    let symbols: [String]
  }

  /// 面板里的符号。分类和顺序照常用程度排:最上面那一类是打字时随手就要的。
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
  /// 锁上就连着打,不锁打一个就回键盘。默认不锁:多数时候是打一个顿号就接着写字。
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

  /// 符号铺成几列,每一行多高。
  ///
  /// 行高是定值而不是把可用高度分掉:分掉的话一类里符号多就压扁,多到一定程度就只能少收 —— 而符号本来就是「还有更多」的东西。定高之后放不下的往下滚。
  private static let columns = 5
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
      for symbol in symbols[start..<min(start + Self.columns, symbols.count)] {
        row.addArrangedSubview(key(symbol))
      }
      // 最后一行不满就补空位,否则剩下的几个会被拉宽。
      for _ in symbols[start..<min(start + Self.columns, symbols.count)].count..<Self.columns {
        row.addArrangedSubview(UIView())
      }
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
      // 不锁就是打一个回键盘 —— 顿号打完接着写字是常态,让人再点一次「返回」是多的。
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
