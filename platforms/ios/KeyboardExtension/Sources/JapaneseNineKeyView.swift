import UIKit

/// Physical key labels and keystrokes only; composition and conversion stay in Engine.
@MainActor
final class JapaneseNineKeyView: UIStackView {
  struct Key {
    let kana: [String]
    let strokes: [String]
  }
  static let keys: [Key] = [
    Key(kana: ["あ", "い", "う", "え", "お"], strokes: ["a", "i", "u", "e", "o"]),
    Key(kana: ["か", "き", "く", "け", "こ"], strokes: ["ka", "ki", "ku", "ke", "ko"]),
    Key(kana: ["さ", "し", "す", "せ", "そ"], strokes: ["sa", "shi", "su", "se", "so"]),
    Key(kana: ["た", "ち", "つ", "て", "と"], strokes: ["ta", "chi", "tsu", "te", "to"]),
    Key(kana: ["な", "に", "ぬ", "ね", "の"], strokes: ["na", "ni", "nu", "ne", "no"]),
    Key(kana: ["は", "ひ", "ふ", "へ", "ほ"], strokes: ["ha", "hi", "fu", "he", "ho"]),
    Key(kana: ["ま", "み", "む", "め", "も"], strokes: ["ma", "mi", "mu", "me", "mo"]),
    Key(kana: ["や", "（", "ゆ", "）", "よ"], strokes: ["ya", "", "yu", "", "yo"]),
    Key(kana: ["ら", "り", "る", "れ", "ろ"], strokes: ["ra", "ri", "ru", "re", "ro"]),
    Key(kana: ["わ", "を", "ん", "ー", "〜"], strokes: ["wa", "wo", "n'", "", ""]),
  ]
  var onInput: ((String) -> Void)?
  var onSymbol: ((String) -> Void)?
  var onDelete: (() -> Void)?
  private var rows: [UIStackView] = []
  private var keyButtons: [UIButton] = []

  init(makeKey: (String, String, @escaping () -> Void) -> UIButton) {
    super.init(frame: .zero)
    axis = .horizontal
    spacing = 6
    accessibilityIdentifier = "japaneseNineKey"
    let grid = UIStackView()
    grid.axis = .vertical; grid.distribution = .fillEqually; grid.spacing = 7
    addArrangedSubview(grid)
    for rowIndex in 0..<3 {
      let row = UIStackView(); row.distribution = .fillEqually; row.spacing = 6
      rows.append(row); grid.addArrangedSubview(row)
      for column in 0..<3 {
        let index = rowIndex * 3 + column
        row.addArrangedSubview(makeKanaKey(index, factory: makeKey))
      }
    }
    let side = UIStackView()
    side.axis = .vertical; side.distribution = .fillEqually; side.spacing = 7
    rows.append(side)
    addArrangedSubview(side)
    side.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.19).isActive = true
    side.addArrangedSubview(makeKanaKey(9, factory: makeKey))
    let variants = makeKey("小゛゜", "小假名、浊音和半浊音", {})
    variants.accessibilityIdentifier = "japaneseVariants"
    variants.configuration?.contentInsets = .zero
    variants.titleLabel?.adjustsFontSizeToFitWidth = true
    variants.titleLabel?.minimumScaleFactor = 0.6
    let groups: [(String, [String], [String])] = [
      ("小假名", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゃ", "ゅ", "ょ", "っ", "ゎ"], ["xa", "xi", "xu", "xe", "xo", "xya", "xyu", "xyo", "xtsu", "xwa"]),
      ("浊音", ["が", "ぎ", "ぐ", "げ", "ご", "ざ", "じ", "ず", "ぜ", "ぞ", "だ", "ぢ", "づ", "で", "ど", "ば", "び", "ぶ", "べ", "ぼ", "ゔ"], ["ga", "gi", "gu", "ge", "go", "za", "ji", "zu", "ze", "zo", "da", "di", "du", "de", "do", "ba", "bi", "bu", "be", "bo", "vu"]),
      ("半浊音", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"], ["pa", "pi", "pu", "pe", "po"]),
    ]
    variants.menu = UIMenu(children: groups.map { title, kana, strokes in
      UIMenu(title: title, children: zip(kana, strokes).map { label, input in
        UIAction(title: label) { [weak self] _ in self?.onInput?(input) }
      })
    })
    variants.showsMenuAsPrimaryAction = true
    side.addArrangedSubview(variants)
    let delete = makeKey("⌫", "删除", { [weak self] in self?.onDelete?() })
    delete.accessibilityIdentifier = "japaneseDelete"
    side.addArrangedSubview(delete)
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func makeKanaKey(_ index: Int, factory: (String, String, @escaping () -> Void) -> UIButton) -> UIButton {
    let key = Self.keys[index]
    let button = factory(key.kana[0], key.kana.joined(separator: "、"), { [weak self] in self?.select(index, direction: 0) })
    button.accessibilityIdentifier = "japaneseKana\(index)"
    button.accessibilityHint = "轻点输入\(key.kana[0])；左、上、右、下滑动选择其他假名；长按显示全部选项"
    button.configuration?.subtitle = key.kana.dropFirst().joined(separator: " ")
    button.configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0; attributes.font = .systemFont(ofSize: 10); return attributes
    }
    button.configuration?.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
    button.menu = UIMenu(children: key.kana.enumerated().map { direction, kana in
      UIAction(title: kana) { [weak self] _ in self?.select(index, direction: direction) }
    })
    let pan = KanaFlickGesture { [weak self, weak button] direction, ended in
      if ended { self?.select(index, direction: direction) }
      button?.configuration?.title = key.kana[ended ? 0 : direction]
    }
    button.addGestureRecognizer(pan)
    keyButtons.append(button)
    return button
  }
  func select(_ index: Int, direction: Int) {
    guard Self.keys.indices.contains(index), Self.keys[index].kana.indices.contains(direction) else { return }
    let key = Self.keys[index]
    if key.strokes[direction].isEmpty { onSymbol?(key.kana[direction]) }
    else { onInput?(key.strokes[direction]) }
  }
  func applyLayout() {
    let layout = KeyboardLayoutPreference.geometry
    spacing = layout.keySpacing
    for row in rows { row.spacing = row.axis == .vertical ? layout.rowSpacing : layout.keySpacing }
    (arrangedSubviews.first as? UIStackView)?.spacing = layout.rowSpacing
  }
}

@MainActor
private final class KanaFlickGesture: UIPanGestureRecognizer {
  private let feedback: (Int, Bool) -> Void
  init(feedback: @escaping (Int, Bool) -> Void) {
    self.feedback = feedback
    super.init(target: nil, action: nil)
    addTarget(self, action: #selector(update))
    maximumNumberOfTouches = 1
    cancelsTouchesInView = true
  }
  @objc private func update() {
    let offset = translation(in: view)
    let direction: Int
    if max(abs(offset.x), abs(offset.y)) < 12 { direction = 0 }
    else if abs(offset.x) > abs(offset.y) { direction = offset.x < 0 ? 1 : 3 }
    else { direction = offset.y < 0 ? 2 : 4 }
    if state == .cancelled || state == .failed { feedback(0, false) }
    else { feedback(direction, state == .ended) }
  }
}
