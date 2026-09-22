import UIKit

/// Apple-style category browser backed by the shared paged Emoji catalog, with the kaomoji catalog as its last tab.
///
/// A kaomoji is a line of text, not a pictograph, so its tab lays out as many columns as fit its width: two on a phone, more on an iPad. Kaomoji stay out of 最近, whose eight-column grid is sized for Emoji.
final class KeyboardEmojiPickerView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
  typealias PageLoader = @Sendable (
    KeyboardEmojiCatalog.Category, Int
  ) throws -> KeyboardEmojiCatalog.Page

  private enum Tab: Equatable {
    case recent
    case category(KeyboardEmojiCatalog.Category)

    var title: String {
      switch self {
      case .recent: return "最近"
      case .category(let category): return category.title
      }
    }
  }

  private let onInsert: (String) -> Void
  private let onDelete: () -> Void
  private let onCatalogChange: (() -> Void)?
  private let loader: PageLoader
  private let loadQueue = DispatchQueue(label: "app.msime.ios.emoji-catalog", qos: .userInitiated)
  private let tabs = UIStackView()
  private let tabScroll = UIScrollView()
  private let status = UILabel()
  private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
  private var tabButtons: [UIButton] = []
  private var availableTabs: [Tab]
  private var selectedTab = -1
  private var items: [KeyboardEmojiCatalog.Item] = []
  private var nextOffset = 0
  private var complete = false
  private var loading = false
  private var loadGeneration: UInt64 = 0
  private let skin = KeyboardSkinPreference.selected

  init(
    resources: String,
    loader: PageLoader? = nil,
    onInsert: @escaping (String) -> Void,
    onDelete: @escaping () -> Void,
    onClose: @escaping () -> Void,
    onCatalogChange: (() -> Void)? = nil
  ) {
    self.onInsert = onInsert
    self.onDelete = onDelete
    self.onCatalogChange = onCatalogChange
    self.loader = loader ?? { category, offset in
      try KeyboardEmojiCatalog.loadPage(
        resources: resources, category: category, offset: offset)
    }
    let recents = KeyboardEmojiRecents.stored
    availableTabs = (recents.isEmpty ? [] : [.recent])
      + KeyboardEmojiCatalog.categories.map(Tab.category) + [.category(KeyboardEmojiCatalog.kaomoji)]
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardEmojiPicker"
    backgroundColor = skin.background

    let title = UILabel()
    title.text = "表情"
    title.font = .systemFont(ofSize: 17, weight: .semibold)
    title.textColor = skin.keyForeground

    let close = headerButton(symbol: "chevron.left", label: "返回键盘", id: "closeEmojiPicker")
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)
    let delete = headerButton(symbol: "delete.left", label: "删除", id: "emojiDeleteKey")
    delete.addAction(UIAction { [weak self] _ in self?.onDelete() }, for: .primaryActionTriggered)

    tabs.axis = .horizontal
    tabs.spacing = 4
    tabScroll.showsHorizontalScrollIndicator = false
    tabScroll.alwaysBounceHorizontal = false
    tabScroll.disableEdgeEffects()
    for (index, tab) in availableTabs.enumerated() {
      let button = UIButton(type: .system)
      button.configuration = Self.tabConfiguration(title: tab.title)
      button.accessibilityIdentifier = "emojiCategory-\(index)"
      button.accessibilityLabel = tab.title
      button.addAction(UIAction { [weak self] _ in self?.selectTab(index) },
                       for: .primaryActionTriggered)
      tabButtons.append(button)
      tabs.addArrangedSubview(button)
    }

    status.font = .systemFont(ofSize: 11)
    status.textColor = skin.keyForeground.withAlphaComponent(0.65)
    status.textAlignment = .center
    status.accessibilityIdentifier = "emojiCatalogStatus"

    grid.dataSource = self
    grid.delegate = self
    grid.backgroundColor = .clear
    grid.accessibilityIdentifier = "emojiGrid"
    grid.register(KeyboardEmojiCell.self, forCellWithReuseIdentifier: KeyboardEmojiCell.reuseIdentifier)
    grid.disableEdgeEffects()

    tabScroll.addSubview(tabs)
    for child in [title, close, delete, tabScroll, status, grid] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }
    tabs.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      close.topAnchor.constraint(equalTo: topAnchor),
      close.widthAnchor.constraint(equalToConstant: 44),
      close.heightAnchor.constraint(equalToConstant: 40),
      title.centerXAnchor.constraint(equalTo: centerXAnchor),
      title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
      delete.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      delete.centerYAnchor.constraint(equalTo: close.centerYAnchor),
      delete.widthAnchor.constraint(equalToConstant: 44),
      delete.heightAnchor.constraint(equalToConstant: 40),

      tabScroll.topAnchor.constraint(equalTo: close.bottomAnchor),
      tabScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      tabScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      tabScroll.heightAnchor.constraint(equalToConstant: 30),
      tabs.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor),
      tabs.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor),
      tabs.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor),
      tabs.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor),
      tabs.heightAnchor.constraint(equalTo: tabScroll.frameLayoutGuide.heightAnchor),

      status.topAnchor.constraint(equalTo: tabScroll.bottomAnchor),
      status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      status.heightAnchor.constraint(equalToConstant: 20),
      grid.topAnchor.constraint(equalTo: status.bottomAnchor),
      grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      grid.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    selectTab(0)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func headerButton(symbol: String, label: String, id: String) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: symbol), for: .normal)
    button.tintColor = skin.accent
    button.accessibilityIdentifier = id
    button.accessibilityLabel = label
    return button
  }

  private var showsKaomoji: Bool {
    guard availableTabs.indices.contains(selectedTab),
          case .category(let category) = availableTabs[selectedTab] else { return false }
    return category.isKaomoji
  }

  /// Columns for the kaomoji tab: as many 170-point columns as the width holds, and never fewer than two.
  static func kaomojiColumns(width: CGFloat) -> Int { max(2, Int(width / 170)) }

  private func makeLayout() -> UICollectionViewCompositionalLayout {
    UICollectionViewCompositionalLayout { [weak self] _, environment in
      let kaomoji = self?.showsKaomoji ?? false
      let columns = kaomoji
        ? Self.kaomojiColumns(width: environment.container.effectiveContentSize.width)
        : KeyboardEmojiCatalog.columns
      let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
        heightDimension: .fractionalHeight(1)))
      let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1),
        heightDimension: kaomoji ? .absolute(44) : .fractionalWidth(1.0 / CGFloat(columns))),
        subitems: [item])
      return NSCollectionLayoutSection(group: group)
    }
  }

  private static func tabConfiguration(title: String) -> UIButton.Configuration {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = .systemFont(ofSize: 13, weight: .medium)
      return attributes
    }
    return configuration
  }

  private func selectTab(_ index: Int) {
    guard availableTabs.indices.contains(index) else { return }
    loadGeneration &+= 1
    selectedTab = index
    items = []
    nextOffset = 0
    complete = false
    loading = false
    updateTabAppearance()
    switch availableTabs[index] {
    case .recent:
      items = KeyboardEmojiRecents.stored.map {
        KeyboardEmojiCatalog.Item(text: $0, annotation: "", group: "最近")
      }
      complete = true
      reloadCatalog()
    case .category:
      reloadCatalog()
      loadNextPage()
    }
  }

  private func updateTabAppearance() {
    for (index, button) in tabButtons.enumerated() {
      let selected = index == selectedTab
      button.configuration?.baseForegroundColor = selected
        ? skin.accent : skin.keyForeground.withAlphaComponent(0.6)
      button.accessibilityTraits = selected ? [.button, .selected] : .button
    }
    guard availableTabs.indices.contains(selectedTab) else { return }
    tabScroll.scrollRectToVisible(tabButtons[selectedTab].frame.insetBy(dx: -8, dy: 0), animated: false)
  }

  private func loadNextPage() {
    guard !loading, !complete, availableTabs.indices.contains(selectedTab),
          case .category(let category) = availableTabs[selectedTab],
          items.count < KeyboardEmojiCatalog.maximumItems else { return }
    loading = true
    updateStatus()
    let offset = nextOffset
    let generation = loadGeneration
    let targetLoader = loader
    loadQueue.async { [weak self] in
      let page = try? targetLoader(category, offset)
      DispatchQueue.main.async { [weak self] in
        self?.accept(page: page, category: category, offset: offset, generation: generation)
      }
    }
  }

  private func accept(
    page: KeyboardEmojiCatalog.Page?, category: KeyboardEmojiCatalog.Category,
    offset: Int, generation: UInt64
  ) {
    guard generation == loadGeneration, availableTabs.indices.contains(selectedTab),
          availableTabs[selectedTab] == .category(category), nextOffset == offset else { return }
    loading = false
    guard let page, items.count + page.items.count <= KeyboardEmojiCatalog.maximumItems else {
      complete = true
      status.text = "表情目录暂时不可用；点分类重试"
      onCatalogChange?()
      return
    }
    items.append(contentsOf: page.items)
    nextOffset = page.nextOffset
    complete = page.complete
    reloadCatalog()
    if page.items.isEmpty && !complete { loadNextPage() }
  }

  private func reloadCatalog() {
    grid.collectionViewLayout.invalidateLayout()
    grid.reloadData()
    updateStatus()
    onCatalogChange?()
  }

  private func updateStatus() {
    let noun = showsKaomoji ? "颜文字" : "表情"
    if loading && items.isEmpty { status.text = "正在加载\(noun)…" }
    else if items.isEmpty { status.text = selectedTab >= 0 && availableTabs[selectedTab] == .recent
      ? "暂无最近使用" : "暂无\(noun)" }
    else if complete { status.text = "\(items.count) 个\(noun)" }
    else { status.text = "\(items.count) 个\(noun) · 继续滚动加载" }
  }

  func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    items.count
  }

  func collectionView(
    _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: KeyboardEmojiCell.reuseIdentifier, for: indexPath)
    (cell as? KeyboardEmojiCell)?.show(items[indexPath.item], kaomoji: showsKaomoji)
    return cell
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard items.indices.contains(indexPath.item) else { return }
    collectionView.deselectItem(at: indexPath, animated: false)
    let emoji = items[indexPath.item].text
    if !showsKaomoji { KeyboardEmojiRecents.record(emoji) }
    onInsert(emoji)
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === grid, !complete,
          let last = grid.indexPathsForVisibleItems.map(\.item).max(),
          last >= max(0, items.count - 16) else { return }
    loadNextPage()
  }
}

private final class KeyboardEmojiCell: UICollectionViewCell {
  static let reuseIdentifier = "KeyboardEmojiCell"
  private let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    label.font = .systemFont(ofSize: 28)
    label.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      label.topAnchor.constraint(equalTo: contentView.topAnchor),
      label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show(_ item: KeyboardEmojiCatalog.Item, kaomoji: Bool = false) {
    label.font = .systemFont(ofSize: kaomoji ? 17 : 28)
    label.textColor = KeyboardSkinPreference.selected.keyForeground
    label.text = item.text
    accessibilityLabel = item.annotation.isEmpty ? item.text : "\(item.text)，\(item.annotation)"
  }
}
