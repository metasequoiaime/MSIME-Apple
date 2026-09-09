import UIKit

// Every candidate the engine returned, laid out over the keys.
//
// The strip shows nine at a time and the arrows advanced by nine, so a query answering with 351
// candidates -- `yi` does -- put the tail thirty-nine taps away. Nobody reaches it, which reads as
// the word not being in the dictionary. This shows the whole list at once instead.
final class KeyboardCandidatePanelView: UIView {
  private let candidates: [String]
  private let display: (String) -> String
  private let onSelect: (Int) -> Void
  private let rows = UIStackView()
  private let scrollView = UIScrollView()
  private var laidOutWidth: CGFloat = 0

  init(candidates: [String], preedit: String, display: @escaping (String) -> String,
       onSelect: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
    self.candidates = candidates
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
      let chip = makeChip(candidate: candidate, number: offset + 1)
      let width = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
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
    row.alignment = .center
    return row
  }

  private func makeChip(candidate: String, number: Int) -> UIButton {
    let text = display(candidate)
    var configuration = UIButton.Configuration.plain()
    configuration.title = text
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.keyForeground
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
    chip.accessibilityIdentifier = "panelCandidate-\(number)"
    chip.accessibilityLabel = "候选词 \(number)：\(text)"
    return chip
  }
}
