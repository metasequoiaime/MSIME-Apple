import UIKit

/// Categorized symbol surface used by the keyboard's punctuation shortcut.
///
/// The hand-picked phone categories come first; after them come the parents of the Engine's symbol catalog in `others.db`, the same catalog the desktop, macOS and Harmony panels browse, loaded a parent at a time off the main thread.
final class KeyboardSymbolPanelView: UIView {
  struct Category {
    let title: String
    let symbols: [String]
  }

  /// Where the Engine catalog comes from; tests substitute their own rows.
  struct Catalog {
    let parents: () throws -> [String]
    let symbols: @Sendable (String) throws -> [String]

    static func engine(resources: String) -> Catalog {
      Catalog(parents: { try KeyboardEmojiCatalog.symbolParents(resources: resources) },
              symbols: { try KeyboardEmojiCatalog.loadSymbols(resources: resources, parent: $0) })
    }
  }

  private enum Entry {
    case fixed(Category)
    case catalog(parent: String)

    var title: String {
      switch self {
      case .fixed(let category): return category.title
      case .catalog(let parent): return KeyboardEmojiCatalog.symbolParentTitles[parent] ?? parent
      }
    }
  }

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
  private let catalog: Catalog?
  private let loadQueue = DispatchQueue(label: "app.msime.ios.symbol-catalog", qos: .userInitiated)
  private var loadGeneration: UInt64 = 0
  private var entries: [Entry]
  private let skin = KeyboardSkinPreference.selected
  private let grid = UIStackView()
  private let scroll = UIScrollView()
  private var categoryButtons: [UIButton] = []
  private(set) var selected = 0
  private var locked = false
  private var lockButton: UIButton!

  init(catalog: Catalog? = nil, onInsert: @escaping (String) -> Void, onDelete: @escaping () -> Void,
       onClose: @escaping () -> Void) {
    self.onInsert = onInsert
    self.onDelete = onDelete
    self.onClose = onClose
    self.catalog = catalog
    // Listing the parents is one small grouped query; without a readable catalog the phone categories stand alone.
    let parents = (try? catalog?.parents()) ?? []
    entries = Self.categories.map(Entry.fixed) + parents.map { Entry.catalog(parent: $0) }
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardSymbolPanel"
    backgroundColor = skin.background

    let categories = UIStackView()
    categories.axis = .vertical
    categories.spacing = 1
    for (index, entry) in entries.enumerated() {
      let button = UIButton(type: .system)
      button.setTitle(entry.title, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 15)
      button.accessibilityIdentifier = "symbolCategory_\(index)"
      button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .primaryActionTriggered)
      button.heightAnchor.constraint(equalToConstant: Self.categoryHeight).isActive = true
      categoryButtons.append(button)
      categories.addArrangedSubview(button)
    }
    let categoryScroll = UIScrollView()
    categoryScroll.showsVerticalScrollIndicator = false
    categoryScroll.disableEdgeEffects()
    categoryScroll.accessibilityIdentifier = "symbolCategories"
    categories.translatesAutoresizingMaskIntoConstraints = false
    categoryScroll.addSubview(categories)

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

    for item in [categoryScroll, scroll, bottom] {
      item.translatesAutoresizingMaskIntoConstraints = false
      addSubview(item)
    }
    NSLayoutConstraint.activate([
      categoryScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      categoryScroll.topAnchor.constraint(equalTo: topAnchor),
      categoryScroll.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -1),
      categoryScroll.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.2),
      categories.leadingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.leadingAnchor),
      categories.trailingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.trailingAnchor),
      categories.topAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.topAnchor),
      categories.bottomAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.bottomAnchor),
      categories.widthAnchor.constraint(equalTo: categoryScroll.frameLayoutGuide.widthAnchor),
      scroll.leadingAnchor.constraint(equalTo: categoryScroll.trailingAnchor, constant: 1),
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
  private static let rowHeight: CGFloat = 46
  private static let categoryHeight: CGFloat = 40

  /// The number of categories on the left: the phone ones plus any catalog parents.
  var categoryCount: Int { entries.count }

  private func select(_ index: Int) {
    guard entries.indices.contains(index) else { return }
    selected = index
    loadGeneration &+= 1
    for (position, button) in categoryButtons.enumerated() {
      let active = position == index
      button.backgroundColor = active ? skin.background : skin.keyBackground
      button.setTitleColor(active ? skin.accent : skin.keyForeground, for: .normal)
      button.accessibilityTraits = active ? [.button, .selected] : [.button]
    }
    switch entries[index] {
    case .fixed(let category):
      show(category.symbols)
    case .catalog(let parent):
      guard let catalog else { return }
      show([])
      let generation = loadGeneration
      loadQueue.async { [weak self] in
        let symbols = (try? catalog.symbols(parent)) ?? []
        DispatchQueue.main.async {
          guard let self, self.loadGeneration == generation else { return }
          self.show(symbols)
        }
      }
    }
  }

  private func show(_ symbols: [String]) {
    for row in grid.arrangedSubviews {
      grid.removeArrangedSubview(row)
      row.removeFromSuperview()
    }
    scroll.setContentOffset(.zero, animated: false)
    for start in stride(from: 0, to: symbols.count, by: Self.columns) {
      let row = UIStackView()
      row.axis = .horizontal
      row.distribution = .fillEqually
      row.spacing = 1
      let end = min(start + Self.columns, symbols.count)
      for symbol in symbols[start..<end] { row.addArrangedSubview(key(symbol)) }
      for _ in (end - start)..<Self.columns { row.addArrangedSubview(UIView()) }
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
