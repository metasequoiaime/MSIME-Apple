import UIKit

/// 表情面板：分类浏览加最近使用。
///
/// Emoji input already existed as a pinyin-searched local mode, reachable three taps deep in a menu
/// on the candidate strip's own name. That answers "I know the word for it"; this answers "show me
/// what there is", which is what people reach for a smiley key expecting.
final class KeyboardEmojiPickerView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
  private let onInsert: (String) -> Void
  private let onDelete: () -> Void
  private var sections: [EmojiCatalog.Section]
  private let tabs = UIStackView()
  private let tabScroll = UIScrollView()
  private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
  private var tabButtons: [UIButton] = []
  private var selectedSection = -1
  private let skin = KeyboardSkinPreference.selected

  init(onInsert: @escaping (String) -> Void, onDelete: @escaping () -> Void,
       onClose: @escaping () -> Void) {
    self.onInsert = onInsert
    self.onDelete = onDelete
    // Recents lead when there are any, so the common case is the first thing under the thumb.
    let recents = EmojiRecents.stored
    sections = (recents.isEmpty ? [] : [EmojiCatalog.Section(title: "最近", emoji: recents)])
      + EmojiCatalog.sections
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardEmojiPicker"
    backgroundColor = skin.background

    let title = UILabel()
    title.text = "表情"
    title.font = .systemFont(ofSize: 17, weight: .semibold)
    title.textColor = skin.keyForeground

    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "chevron.left"), for: .normal)
    close.tintColor = skin.accent
    close.accessibilityIdentifier = "closeEmojiPicker"
    close.accessibilityLabel = "返回键盘"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)

    let delete = UIButton(type: .system)
    delete.setImage(UIImage(systemName: "delete.left"), for: .normal)
    delete.tintColor = skin.accent
    delete.accessibilityIdentifier = "emojiDeleteKey"
    delete.accessibilityLabel = "删除"
    delete.addAction(UIAction { _ in onDelete() }, for: .primaryActionTriggered)

    tabs.axis = .horizontal
    tabs.spacing = 4
    tabScroll.showsHorizontalScrollIndicator = false
    tabScroll.disableEdgeEffects()
    for (index, section) in sections.enumerated() {
      let tab = UIButton(type: .system)
      tab.configuration = Self.tabConfiguration(title: section.title)
      tab.accessibilityIdentifier = "emojiCategory_\(index)"
      tab.accessibilityLabel = section.title
      tab.addAction(UIAction { [weak self] _ in self?.select(section: index, scroll: true) },
                    for: .primaryActionTriggered)
      tabButtons.append(tab)
      tabs.addArrangedSubview(tab)
    }

    grid.dataSource = self
    grid.delegate = self
    grid.backgroundColor = .clear
    grid.accessibilityIdentifier = "emojiGrid"
    grid.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseIdentifier)
    grid.disableEdgeEffects()

    tabScroll.addSubview(tabs)
    for item in [title, close, delete, tabScroll, grid] {
      item.translatesAutoresizingMaskIntoConstraints = false
      addSubview(item)
    }
    tabs.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      close.topAnchor.constraint(equalTo: topAnchor),
      close.widthAnchor.constraint(equalToConstant: 44),
      close.heightAnchor.constraint(equalToConstant: 40),
      title.centerXAnchor.constraint(equalTo: centerXAnchor),
      title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
      delete.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      delete.centerYAnchor.constraint(equalTo: close.centerYAnchor),
      delete.widthAnchor.constraint(equalToConstant: 44),

      tabScroll.topAnchor.constraint(equalTo: close.bottomAnchor),
      tabScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      tabScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      tabScroll.heightAnchor.constraint(equalToConstant: 30),
      tabs.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor),
      tabs.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor),
      tabs.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor),
      tabs.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor),
      tabs.heightAnchor.constraint(equalTo: tabScroll.frameLayoutGuide.heightAnchor),

      grid.topAnchor.constraint(equalTo: tabScroll.bottomAnchor, constant: 2),
      grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      grid.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    select(section: 0, scroll: false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Eight to a row at any width, so the cells grow with the keyboard rather than leaving a margin.
  private static func makeLayout() -> UICollectionViewCompositionalLayout {
    let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1.0 / 8.0), heightDimension: .fractionalHeight(1)))
    let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(1.0 / 8.0)),
      subitems: [item])
    return UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))
  }

  private static func tabConfiguration(title: String) -> UIButton.Configuration {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      attributes in
      var attributes = attributes
      attributes.font = .systemFont(ofSize: 13, weight: .medium)
      return attributes
    }
    return configuration
  }

  private func select(section: Int, scroll: Bool) {
    // 滚动时每帧都会调到这里。Rewriting a button's configuration re-renders it, so ten of them per
    // scroll callback is the same waste this panel was meant to avoid.
    guard section != selectedSection else {
      if scroll { scrollToSection(section) }
      return
    }
    selectedSection = section
    for (index, tab) in tabButtons.enumerated() {
      let selected = index == section
      tab.configuration?.baseForegroundColor =
        selected ? skin.accent : skin.keyForeground.withAlphaComponent(0.6)
      tab.accessibilityTraits = selected ? [.button, .selected] : .button
    }
    guard scroll else { return }
    scrollToSection(section)
  }

  private func scrollToSection(_ section: Int) {
    guard sections.indices.contains(section), !sections[section].emoji.isEmpty else { return }
    grid.scrollToItem(at: IndexPath(item: 0, section: section), at: .top, animated: false)
  }

  func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    sections[section].emoji.count
  }

  func collectionView(_ collectionView: UICollectionView,
                      cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: EmojiCell.reuseIdentifier, for: indexPath)
    (cell as? EmojiCell)?.show(sections[indexPath.section].emoji[indexPath.item])
    return cell
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: false)
    let emoji = sections[indexPath.section].emoji[indexPath.item]
    EmojiRecents.record(emoji)
    onInsert(emoji)
  }

  /// The tabs follow the grid, so scrolling past a category boundary is reflected without a tap.
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === grid,
          let top = grid.indexPathsForVisibleItems.min() else { return }
    select(section: top.section, scroll: false)
  }
}

private final class EmojiCell: UICollectionViewCell {
  static let reuseIdentifier = "EmojiCell"
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

  func show(_ emoji: String) {
    label.text = emoji
    accessibilityLabel = emoji
  }
}
