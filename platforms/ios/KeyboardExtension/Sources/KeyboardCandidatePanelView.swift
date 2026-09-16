import UIKit

// Every candidate the engine returned, laid out over the keys.
//
// The strip shows nine at a time and the arrows advanced by nine, so a query answering with 351
// candidates -- `yi` does -- put the tail thirty-nine taps away. Nobody reaches it, which reads as
// the word not being in the dictionary. This shows the whole list at once instead.
final class KeyboardCandidatePanelView: UIView {
  private let candidates: [String]
  // The keys still to press for each candidate, parallel to candidates and empty where none applies.
  private let hints: [String]
  /// 每个候选的释义,和 candidates 平行,最多两条。联网那份只覆盖候选条上的那一页,再往后是随包词库答的。
  private let glosses: [[String]]
  private let display: (String) -> String
  private let onSelect: (Int) -> Void
  /// 长按这个候选给什么。和候选条共用一份 —— 那边长按能拿到译文,展开之后不该就没有了。
  private let menuElements: (Int) -> [UIMenuElement]
  private let rows = UIStackView()
  private let scrollView = UIScrollView()
  private var laidOutWidth: CGFloat = 0

  init(candidates: [String], hints: [String] = [], glosses: [[String]] = [], preedit: String,
       display: @escaping (String) -> String,
       menuElements: @escaping (Int) -> [UIMenuElement] = { _ in [] },
       onSelect: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
    self.candidates = candidates
    self.hints = hints
    self.glosses = glosses
    self.display = display
    self.menuElements = menuElements
    self.onSelect = onSelect
    super.init(frame: .zero)
    accessibilityIdentifier = "candidatePanel"
    backgroundColor = KeyboardSkinPreference.selected.keyBackground.withAlphaComponent(0.98)

    let spelling = UILabel()
    spelling.text = preedit
    spelling.font = .preferredFont(forTextStyle: .subheadline)
    spelling.adjustsFontForContentSizeCategory = true
    spelling.textColor = KeyboardSkinPreference.selected.accent
    spelling.accessibilityIdentifier = "candidatePanelSpelling"

    let count = UILabel()
    count.text = "\(candidates.count) 个候选"
    count.font = .preferredFont(forTextStyle: .footnote)
    count.adjustsFontForContentSizeCategory = true
    count.textColor = KeyboardSkinPreference.selected.keyForeground.withAlphaComponent(0.6)

    var closeConfiguration = UIButton.Configuration.plain()
    closeConfiguration.image = UIImage(systemName: "chevron.up")
    closeConfiguration.baseForegroundColor = KeyboardSkinPreference.selected.keyForeground
    let close = UIButton(
      configuration: closeConfiguration,
      primaryAction: UIAction { _ in onClose() })
    close.accessibilityIdentifier = "closeCandidatePanel"
    close.accessibilityLabel = "收起候选"
    close.setContentHuggingPriority(.required, for: .horizontal)

    let header = UIStackView(arrangedSubviews: [spelling, count, UIView(), close])
    header.axis = .horizontal
    header.alignment = .center
    header.spacing = 8
    header.translatesAutoresizingMaskIntoConstraints = false
    addSubview(header)

    rows.axis = .vertical
    rows.spacing = 6
    rows.alignment = .leading
    rows.translatesAutoresizingMaskIntoConstraints = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.disableEdgeEffects()
    scrollView.addSubview(rows)
    addSubview(scrollView)

    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      header.heightAnchor.constraint(equalToConstant: 32),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      rows.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      rows.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      rows.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      rows.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      rows.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  // Rows are packed against a known width, so they are built here rather than in init.
  override func layoutSubviews() {
    super.layoutSubviews()
    let available = scrollView.bounds.width
    guard available > 0, available != laidOutWidth else { return }
    laidOutWidth = available
    rebuildRows(within: available)
  }

  private func rebuildRows(within available: CGFloat) {
    for row in rows.arrangedSubviews {
      rows.removeArrangedSubview(row)
      row.removeFromSuperview()
    }
    let spacing: CGFloat = 6
    // 开着释义时一行摆三个,和候选条同一个分法 —— 挤满一行会把释义截到看不出意思。
    let column = glosses.contains { !$0.isEmpty }
      ? KeyboardKeyButton.glossColumnWidth(
          visible: available, spacing: spacing,
          insets: NSDirectionalEdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11))
      : 0
    var row = makeRow(spacing: spacing)
    var used: CGFloat = 0
    for (offset, candidate) in candidates.enumerated() {
      let chip = makeChip(
        candidate: candidate, hint: hints.indices.contains(offset) ? hints[offset] : "",
        glosses: glosses.indices.contains(offset) ? glosses[offset] : [],
        column: column, number: offset + 1)
      // 按自然宽度量,并且不许超过一行的可用宽度。
      let width = min(
        naturalWidth(of: chip, glossLines: glosses.indices.contains(offset) ? glosses[offset].count : 0,
                     column: column),
        available)
      // 量出来的宽度直接钉在格子上。多行标题的固有宽度不可靠 —— 实测两行的格子只按第一行报宽,画出来 56pt,候选被截成「您…」;而排版的算术本来就按这个宽度走,钉上去两边才是同一个数。
      chip.widthAnchor.constraint(equalToConstant: width).isActive = true
      if used > 0, used + spacing + width > available {
        rows.addArrangedSubview(row)
        row = makeRow(spacing: spacing)
        used = 0
      }
      row.addArrangedSubview(chip)
      used += (used > 0 ? spacing : 0) + width
    }
    if !row.arrangedSubviews.isEmpty { rows.addArrangedSubview(row) }
  }

  /// 一个格子要多宽。
  ///
  /// 不能问 `systemLayoutSizeFitting`:带释义的标题是多行的,而多行标签在压缩优先级下可以缩到任意窄 —— 量回来的「自然宽度」接近零,于是每个候选都被排成一丁点宽,画出来就是「您…」和整排的「…」。
  ///
  /// 也不能按最宽的那一行量:那样宽度就跟着释义走,答案一到格子就变宽。只量候选词那一行,剩下的交给 `chipWidth` 里的预留值。
  private func naturalWidth(of chip: UIButton, glossLines: Int, column: CGFloat) -> CGFloat {
    guard let title = chip.configuration?.attributedTitle.map({ NSAttributedString($0) }) else {
      return chip.intrinsicContentSize.width
    }
    let text = title.string as NSString
    let firstLine = text.range(of: "\n").location == NSNotFound
      ? NSRange(location: 0, length: text.length)
      : NSRange(location: 0, length: text.range(of: "\n").location)
    return KeyboardKeyButton.chipWidth(
      titleLine: title.attributedSubstring(from: firstLine).size().width,
      glossLines: glossLines, column: column, insets: chip.configuration?.contentInsets ?? .zero)
  }

  private func makeRow(spacing: CGFloat) -> UIStackView {
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = spacing
    // 同一行里有的格子带释义、有的没有,按内容居中就参差不齐;拉到一样高。
    row.alignment = .fill
    return row
  }

  private func makeChip(candidate: String, hint: String, glosses: [String], column: CGFloat,
                        number: Int) -> KeyboardKeyButton {
    let text = display(candidate)
    var configuration = UIButton.Configuration.plain()
    // 一律走 attributedTitle,哪怕只有候选词本身:排版要按最宽的一行量出格子宽度,而那个测量读的就是这个串。
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .natural
    paragraph.lineBreakMode = .byTruncatingTail
    var title = AttributedString(
      text,
      attributes: AttributeContainer([
        .font: UIFont.preferredFont(forTextStyle: .body), .paragraphStyle: paragraph,
      ]))
    if !hint.isEmpty {
      title += AttributedString(
        " " + hint,
        attributes: AttributeContainer([
          .font: UIFont.preferredFont(forTextStyle: .caption1), .paragraphStyle: paragraph,
          .foregroundColor: KeyboardSkinPreference.selected.keyForeground.withAlphaComponent(0.55),
        ]))
    }
    // 释义自己一行,跟候选条上一样。面板一行排好几个格,挤在候选右边会把一行挤得只剩两三个词。先按格子的正文宽度截好再写进去 —— 靠段落样式截不住,它会折行,那个格子就比同一行的别人高出一截。
    let caption = UIFont.preferredFont(forTextStyle: .caption2)
    let content = KeyboardKeyButton.chipContentWidth(
      titleLine: NSAttributedString(title).size().width, glossLines: glosses.count, column: column)
    for gloss in glosses {
      let fitted = KeyboardKeyButton.fittedGloss(gloss, font: caption, width: content)
      title += AttributedString(
        "\n" + fitted.text,
        attributes: AttributeContainer([
          .font: fitted.font, .paragraphStyle: paragraph,
          .foregroundColor: KeyboardSkinPreference.selected.keyForeground.withAlphaComponent(0.55),
        ]))
    }
    configuration.attributedTitle = title
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.keyForeground
    // 没有释义的格子按老样子截断:那个模式顺带把标签钉成一行,长候选就截断而不是在格子里折行。有释义的格子必须放开这个限制,否则释义会被并进同一行 —— 它不折行靠的是宽度按最宽的一行给足,不是靠模式。
    configuration.titleLineBreakMode = glosses.isEmpty ? .byTruncatingTail : .byWordWrapping
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)
    configuration.background.backgroundColor = KeyboardSkinPreference.selected.keyBackground
    configuration.background.strokeColor =
      KeyboardSkinPreference.selected.accent.withAlphaComponent(0.22)
    configuration.background.strokeWidth = 1
    configuration.background.cornerRadius = 9
    let index = number - 1
    let chip = KeyboardKeyButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] _ in self?.onSelect(index) })
    // 和候选条一样,菜单等展开时才建 —— 面板一次可以铺出三百多个格子,每个都先建一遍菜单太贵。
    chip.menu = UIMenu(children: [
      UIDeferredMenuElement.uncached { [weak self] completion in
        completion(self?.menuElements(index) ?? [])
      }
    ])
    chip.accessibilityIdentifier = "panelCandidate-\(number)"
    chip.accessibilityLabel =
      hint.isEmpty ? "候选词 \(number)：\(text)" : "候选词 \(number)：\(text)，还需输入 \(hint)"
    // 占位的空行不念出来。
    let spoken = glosses.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    if !spoken.isEmpty {
      chip.accessibilityLabel? += "，释义 " + spoken.joined(separator: "，")
    }
    return chip
  }
}
