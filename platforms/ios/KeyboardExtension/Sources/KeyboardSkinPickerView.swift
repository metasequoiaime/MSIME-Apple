import UIKit

final class KeyboardSkinPickerView: UIView {
  init(selected: KeyboardSkin, onSelect: @escaping (KeyboardSkin) -> Void, onClose: @escaping () -> Void) {
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardSkinPicker"
    backgroundColor = .secondarySystemBackground
    let header = UILabel()
    header.text = "选择皮肤"
    header.font = .systemFont(ofSize: 17, weight: .semibold)
    let close = UIButton(type: .system)
    close.setTitle("完成", for: .normal)
    close.accessibilityIdentifier = "closeSkinPicker"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)
    let scroll = UIScrollView()
    let rows = UIStackView()
    rows.axis = .vertical
    rows.spacing = 10
    for index in stride(from: 0, to: KeyboardSkin.allCases.count, by: 2) {
      let row = UIStackView()
      row.spacing = 10
      row.distribution = .fillEqually
      for skin in KeyboardSkin.allCases[index..<min(index + 2, KeyboardSkin.allCases.count)] {
        let card = KeyboardKeyButton()
        card.accessibilityIdentifier = "skinCard-\(skin.rawValue)"
        card.accessibilityLabel = skin.title
        card.accessibilityValue = skin == selected ? "已选中" : ""
        if skin == selected { card.accessibilityTraits.insert(.selected) }
        card.backgroundColor = skin.background
        card.layer.cornerRadius = 12
        card.layer.borderWidth = skin == selected ? 2 : 1
        card.layer.borderColor = (skin == selected ? UIColor.label : UIColor.separator).resolvedColor(with: traitCollection).cgColor
        card.clipsToBounds = true
        let title = UILabel()
        title.text = skin.title + (skin == selected ? "  ✓" : "")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = skin.keyForeground
        let preview = KeyboardSkinMiniature(skin: skin)
        for child in [title, preview] {
          child.isUserInteractionEnabled = false
          child.translatesAutoresizingMaskIntoConstraints = false
          card.addSubview(child)
        }
        NSLayoutConstraint.activate([
          card.heightAnchor.constraint(equalToConstant: 100),
          title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
          title.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
          title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
          preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 7),
          preview.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -7),
          preview.topAnchor.constraint(equalTo: card.topAnchor, constant: 29),
          preview.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -7),
        ])
        card.addAction(UIAction { _ in onSelect(skin) }, for: .primaryActionTriggered)
        row.addArrangedSubview(card)
      }
      rows.addArrangedSubview(row)
    }
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
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class KeyboardSkinMiniature: UIView {
  let skin: KeyboardSkin
  init(skin: KeyboardSkin) {
    self.skin = skin
    super.init(frame: .zero)
    isOpaque = false
    contentMode = .redraw
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ rect: CGRect) {
    let backdrop = KeyboardSkinBackgroundView(frame: bounds)
    backdrop.skin = skin
    backdrop.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
    backdrop.draw(bounds)
    let top = "QWERTYUIOP".map { String($0) }
    let middle = "ASDFGHJKL".map { String($0) }
    let bottom = ["⇧"] + "ZXCVBNM".map { String($0) } + ["⌫"]
    let rows: [[String]] = [top, middle, bottom, ["123", "空格", "↵"]]
    let gap: CGFloat = 2
    let height = (bounds.height - gap * 3) / 4
    for (rowIndex, row) in rows.enumerated() {
      let inset: CGFloat = rowIndex == 1 ? bounds.width * 0.04 : 0
      let width = (bounds.width - inset * 2 - gap * CGFloat(row.count - 1)) / CGFloat(row.count)
      for (index, title) in row.enumerated() {
        let key = CGRect(x: inset + CGFloat(index) * (width + gap), y: CGFloat(rowIndex) * (height + gap), width: width, height: height)
        let path = UIBezierPath(roundedRect: key, cornerRadius: min(skin.cornerRadius * 0.3, height * 0.4))
        if skin.shadowOpacity > 0 {
          UIColor.black.withAlphaComponent(CGFloat(skin.shadowOpacity)).setFill()
          UIBezierPath(roundedRect: key.offsetBy(dx: 0, dy: 1), cornerRadius: 2).fill()
        }
        (title == "↵" ? skin.actionBackground : skin.keyBackground).setFill()
        path.fill()
        if skin.borderWidth > 0 { skin.borderColor.setStroke(); path.lineWidth = 0.5; path.stroke() }
        let font = skin.usesMonospacedFont ? UIFont.monospacedSystemFont(ofSize: 7, weight: .medium) : UIFont.systemFont(ofSize: 7, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: title == "↵" ? skin.actionForeground : skin.keyForeground]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: key.midX - size.width / 2, y: key.midY - size.height / 2), withAttributes: attributes)
      }
    }
  }
}
