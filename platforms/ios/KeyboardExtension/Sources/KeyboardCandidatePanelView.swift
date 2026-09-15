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
  private let rows = UIStackView()
  private let scrollView = UIScrollView()
  private var laidOutWidth: CGFloat = 0

  init(candidates: [String], hints: [String] = [], glosses: [[String]] = [], preedit: String,
       display: @escaping (String) -> String,
       onSelect: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
    self.candidates = candidates
    self.hints = hints
    self.glosses = glosses
    self.display = display
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
    var row = makeRow(spacing: spacing)
    var used: CGFloat = 0
    for (offset, candidate) in candidates.enumerated() {
      let chip = makeChip(
        candidate: candidate, hint: hints.indices.contains(offset) ? hints[offset] : "",
        glosses: glosses.indices.contains(offset) ? glosses[offset] : [],
        number: offset + 1)
      // 先排一次,让标题标签建出来并吃到行数 —— 三行的格子按一行量,量到的是三行接成一条长线的宽度,一行就只塞得下它一个。
      chip.layoutIfNeeded()
      // 按自然宽度量,并且不许超过一行的可用宽度。
      let natural = chip.systemLayoutSizeFitting(
        CGSize(width: available, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .fittingSizeLevel,
        verticalFittingPriority: .fittingSizeLevel).width
      let width = min(ceil(natural), available)
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

  private func makeRow(spacing: CGFloat) -> UIStackView {
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = spacing
    // 同一行里有的格子带释义、有的没有,按内容居中就参差不齐;拉到一样高。
    row.alignment = .fill
    return row
  }

  private func makeChip(candidate: String, hint: String, glosses: [String], number: Int) -> KeyboardKeyButton {
    let text = display(candidate)
    var configuration = UIButton.Configuration.plain()
    configuration.title = text
    if !hint.isEmpty || !glosses.isEmpty {
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
      // 释义自己一行,跟候选条上一样。面板一行排好几个格,挤在候选右边会把一行挤得只剩两三个词。
      for gloss in glosses {
        title += AttributedString(
          "\n" + gloss,
          attributes: AttributeContainer([
            .font: UIFont.preferredFont(forTextStyle: .caption2), .paragraphStyle: paragraph,
            .foregroundColor: KeyboardSkinPreference.selected.keyForeground.withAlphaComponent(0.55),
          ]))
      }
      configuration.attributedTitle = title
    }
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.keyForeground
    // 候选一行写完,写不下就截断。Leaving this unset let a long candidate wrap inside its own chip,
    // and it broke the packing as well: a wrapping title measures at its narrowest under a
    // compressed fit, so every chip was measured far thinner than it draws, each row was handed
    // more chips than fit, and the whole panel spilled past its width.
    configuration.titleLineBreakMode = .byTruncatingTail
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
    chip.titleLines = 1 + glosses.count
    chip.accessibilityIdentifier = "panelCandidate-\(number)"
    chip.accessibilityLabel =
      hint.isEmpty ? "候选词 \(number)：\(text)" : "候选词 \(number)：\(text)，还需输入 \(hint)"
    if !glosses.isEmpty {
      chip.accessibilityLabel? += "，释义 " + glosses.joined(separator: "，")
    }
    return chip
  }
}
