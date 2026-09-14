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
    // 左右是「」。Apple かなキーボード, Gboard and ATOK all put the Japanese quotes here, and they
    // have no other home on a kana keyboard; the full-width parentheses that were here are rare in
    // Japanese and their empty strokes routed them through the punctuation path, which commits.
    Key(kana: ["や", "「", "ゆ", "」", "よ"], strokes: ["ya", "", "yu", "", "yo"]),
    Key(kana: ["ら", "り", "る", "れ", "ろ"], strokes: ["ra", "ri", "ru", "re", "ro"]),
    // ー 有 stroke。An empty one sent it down the punctuation path, which the bridge could not
    // carry (it takes single-byte ASCII) and which therefore committed the composition and dropped
    // a bare ー beside it -- so ラーメン came out as three separate pieces.
    Key(kana: ["わ", "を", "ん", "ー", "〜"], strokes: ["wa", "wo", "n'", "-", ""]),
    // 第四行右端的标点键。These had no home on the kana layout at all: the shared punctuation key is
    // hidden whenever the kana grid is up, so 、 and 。 -- which end every Japanese sentence -- could
    // only be reached by switching to the symbol page and back.
    Key(kana: ["、", "。", "？", "！", "…"], strokes: ["", "", "", "", ""]),
  ]
  /// 数字层同样是三列。A keyboard chosen for three columns should not hand over to a ten-across
  /// symbol page the moment 123 is pressed — the Chinese nine-key already keeps its own grid here.
  /// Empty strokes send every one of these down the punctuation path, which inserts them directly
  /// instead of feeding the romaji converter.
  static let digitKeys: [Key] = [
    Key(kana: ["1", "☆", "♪", "→", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["2", "¥", "$", "€", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["3", "%", "°", "#", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["4", "○", "*", "・", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["5", "+", "-", "=", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["6", "<", "^", ">", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["7", "「", "」", "：", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["8", "〒", "※", "♂", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["9", "（", "）", "／", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["0", "〜", "…", "ー", ""], strokes: ["", "", "", "", ""]),
    Key(kana: ["、", "。", "？", "！", "…"], strokes: ["", "", "", "", ""]),
  ]
  private var showsDigits = false
  private var activeKeys: [Key] { showsDigits ? Self.digitKeys : Self.keys }

  var onInput: ((String) -> Void)?
  var onSymbol: ((String) -> Void)?
  var onDelete: (() -> Void)?
  /// 小゛゜。一次点击把刚打的假名换成下一个变体,由 Engine 决定循环到哪一个。
  var onVariant: (() -> Void)?
  private var rows: [UIStackView] = []
  private var keyButtons: [UIButton] = []
  private var variantsKey: UIButton?
  private var scriptKeyOneRow: NSLayoutConstraint?
  private var scriptKeyTwoRows: NSLayoutConstraint?
  private let preview = KanaFlickPreview()

  private var isComposing = false

  /// 有假名可改时才点得动 小゛゜ —— 由控制器在每次 render 时告知。
  func setComposing(_ composing: Bool) {
    isComposing = composing
    // 数字层上那一格是括号键,和有没有在组字无关。
    variantsKey?.isEnabled = showsDigits || composing
  }

  /// 侧栏按钮由控制器提供 —— 它们要接系统的地球键行为、长按连删和宿主的回车动作,
  /// 这个视图只负责把它们摆到苹果假名键盘的位置上。
  ///
  /// Apple's kana keyboard is five columns: mode keys down the left, the kana grid in the middle,
  /// and ⌫ / 空白 / 改行 down the right. This used to be the grid plus one delete key stretched
  /// down the full height, with everything else in the shared bottom row.
  init(makeKey: (String, String, @escaping () -> Void) -> UIButton,
       makeDelete: () -> UIButton,
       sideKeys: [UIButton] = [],
       modeKeys: [UIButton] = []) {
    super.init(frame: .zero)
    axis = .horizontal
    spacing = 6
    accessibilityIdentifier = "japaneseNineKey"

    // 左列一格一行,和假名行对齐。Equal shares rather than a tall last key: switching script is a
    // once-a-session action and does not deserve the column's biggest target, and equal shares also
    // degrade cleanly — hide the globe where the host does not need it and the remaining keys
    // redistribute instead of leaving a hole.
    if !modeKeys.isEmpty {
      let modes = UIStackView()
      modes.axis = .vertical; modes.distribution = .fill; modes.spacing = 7
      rows.append(modes)
      addArrangedSubview(modes)
      modes.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.17).isActive = true
      modes.accessibilityIdentifier = "japaneseModeColumn"
      for key in modeKeys { modes.addArrangedSubview(key) }

      // 左列要正好铺满网格的四行。ABC 在实机上跨两格,所以三个键就填满了一列 —— 这也是为什么这一列
      // 从来不需要占位格。Sharing the height equally instead made each of three keys 4/3 of a row and
      // lined them up with nothing.
      //
      // 高度只引用本列自己,不引用假名行。Pinning a key to a row in the sibling grid looks equivalent
      // and is not: that constraint spans two stacks, and the engine settles it by handing every row
      // the whole panel height instead.
      //
      //   一格 = (H - 3×7) / 4          两格 = 2×(H - 3×7)/4 + 7
      // 优先级压到 999:UIStackView 用必需优先级把隐藏的 arranged subview 压成零高,地球键不出现时
      // 两条必需约束会当场打架。
      let pin = { (key: UIButton, span: CGFloat) -> NSLayoutConstraint in
        let constraint = key.heightAnchor.constraint(
          equalTo: modes.heightAnchor, multiplier: span / 4,
          constant: span == 2 ? -3.5 : -5.25)
        constraint.priority = .required - 1
        return constraint
      }
      let row = { (span: CGFloat) -> NSLayoutConstraint? in
        guard modeKeys.indices.contains(2) else { return nil }
        return pin(modeKeys[2], span)
      }
      for (index, key) in modeKeys.enumerated() where index != 2 {
        pin(key, 1).isActive = true
      }
      scriptKeyOneRow = row(1)
      scriptKeyTwoRows = row(2)
      // 地球键不出现时(系统在键盘下面自己画),ABC 跨两格补满;出现时四个键各占一格。
      scriptKeyTwoRows?.isActive = true
    }

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
    // 后置修饰键,不是选择器。Every Japanese keyboard modifies the kana just typed: か→が→か,
    // は→ば→ぱ→は, つ→っ→づ→つ. This was a three-level menu of 36 fresh kana, so か followed by
    // picking が produced かが, and one dakuten cost three taps and a visual search through a menu
    // that covered the candidate strip.
    let variants = makeKey("小゛゜", "小書き、濁点、半濁点", { [weak self] in
      guard let self else { return }
      showsDigits ? onSymbol?("（") : onVariant?()
    })
    variants.accessibilityIdentifier = "japaneseVariants"
    variants.accessibilityHint = "直前のかなを小書き・濁点・半濁点に切り替えます"
    variants.configuration?.contentInsets = .zero
    variants.titleLabel?.adjustsFontSizeToFitWidth = true
    variants.titleLabel?.minimumScaleFactor = 0.6
    // 后置修饰键在没有假名可改时无事可做。Dimmed rather than hidden or swapped for something else:
    // it says "type first" without the grid reshuffling under the thumb between keystrokes.
    variants.isEnabled = false
    variantsKey = variants
    // 第四行:小゛゜ / わ / 、。 —— 每块日语键盘十几年不变的位置。
    let fourth = UIStackView(); fourth.distribution = .fillEqually; fourth.spacing = 6
    rows.append(fourth); grid.addArrangedSubview(fourth)
    fourth.addArrangedSubview(variants)
    fourth.addArrangedSubview(makeKanaKey(9, factory: makeKey))
    fourth.addArrangedSubview(makeKanaKey(10, factory: makeKey))

    // 右列:⌫ / 空白 / 改行。A single delete stretched down four rows was the shape this had after
    // the grid grew its fourth row, and it is not what any Japanese keyboard looks like.
    // 右列:⌫ 一行、空白 一行、改行 跨两行 —— 苹果的比例。Sharing the height equally left 改行 the
    // same size as ⌫ and every one of them straddling the gap between two kana rows.
    let side = UIStackView()
    side.axis = .vertical; side.distribution = .fill; side.spacing = 7
    rows.append(side)
    addArrangedSubview(side)
    side.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.19).isActive = true
    side.accessibilityIdentifier = "japaneseSideColumn"
    let delete = makeDelete()
    delete.accessibilityIdentifier = "japaneseDelete"
    side.addArrangedSubview(delete)
    for key in sideKeys { side.addArrangedSubview(key) }
    // 每个侧键都按"几行高"钉住,单位就是假名行本身。
    if let firstKanaRow = grid.arrangedSubviews.first {
      var spans: [(UIView, CGFloat)] = [(delete, 1)]
      for (index, key) in sideKeys.enumerated() {
        spans.append((key, index == sideKeys.count - 1 ? 2 : 1))
      }
      for (key, rowsTall) in spans {
        key.heightAnchor.constraint(
          equalTo: firstKanaRow.heightAnchor, multiplier: rowsTall,
          constant: rowsTall > 1 ? 7 * (rowsTall - 1) : 0).isActive = true
      }
    }
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func makeKanaKey(_ index: Int, factory: (String, String, @escaping () -> Void) -> UIButton) -> UIButton {
    let button = factory(Self.keys[index].kana[0], "", { [weak self] in self?.select(index, direction: 0) })
    button.accessibilityIdentifier = "japaneseKana\(index)"
    button.configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0; attributes.font = .systemFont(ofSize: 10); return attributes
    }
    button.configuration?.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
    let pan = KanaFlickGesture { [weak self, weak button] direction, phase in
      guard let self, let button else { return }
      switch phase {
      case .ended:
        select(index, direction: direction)
        preview.hide()
      case .cancelled:
        preview.hide()
      case .moving:
        // 十字导览,而不是改键面。Writing the target onto the key the finger is covering meant the
        // one thing the user could not see was the thing they were choosing.
        preview.show(activeKeys[index].kana, highlighting: direction, over: button, in: self)
      }
    }
    button.addGestureRecognizer(pan)
    keyButtons.append(button)
    applyFace(index, to: button)
    return button
  }

  /// 键面跟着当前层走 —— 同一个按钮在假名层是 あ,在数字层是 1。
  private func applyFace(_ index: Int, to button: UIButton) {
    let key = activeKeys[index]
    button.configuration?.title = key.kana[0]
    button.configuration?.subtitle = key.kana.dropFirst().filter { !$0.isEmpty }.joined(separator: " ")
    button.accessibilityLabel = key.kana.filter { !$0.isEmpty }.joined(separator: "、")
    // 日语键面上的说明用日语。A Japanese typist reading 轻点输入 recognised none of it; these are
    // the terms their own keyboards use.
    button.accessibilityHint = "タップで\(key.kana[0])、左・上・右・下にフリックで他の文字"
    // 不挂长按菜单。It predates the flick guide and now fights it: the guide opens on touch down and
    // UIKit's menu covers it half a second later, for a list of exactly the five kana the cross is
    // already showing. The label below enumerates them for VoiceOver, which is what the menu was
    // actually earning its place for.
    button.menu = nil
  }

  /// 数字层第四行第一格。These have no other home on the layout, and the slot is free because the
  /// post-modifier has nothing to modify once the keys stop producing kana.
  private static let brackets = ["（", "）", "「", "」", "『", "』", "【", "】"]

  /// 左列满员(地球键也在)时每个键各占一格,否则 ABC 跨两格补满 —— 由控制器按地球键是否出现来告知。
  func setModeColumnFull(_ full: Bool) {
    scriptKeyTwoRows?.isActive = !full
    scriptKeyOneRow?.isActive = full
  }

  /// 切到数字层。九键还是九键,只是键面换成数字和符号。
  func setDigits(_ on: Bool) {
    guard on != showsDigits else { return }
    showsDigits = on
    for (index, button) in keyButtons.enumerated() where activeKeys.indices.contains(index) {
      applyFace(index, to: button)
    }
    guard let variants = variantsKey else { return }
    variants.configuration?.title = on ? "（）" : "小゛゜"
    variants.accessibilityLabel = on ? "括弧" : "小書き、濁点、半濁点"
    variants.accessibilityHint =
      on ? "長押しで他の括弧" : "直前のかなを小書き・濁点・半濁点に切り替えます"
    variants.isEnabled = on || isComposing
    variants.menu =
      on
      ? UIMenu(children: Self.brackets.map { bracket in
        UIAction(title: bracket) { [weak self] _ in self?.onSymbol?(bracket) }
      }) : nil
  }
  func select(_ index: Int, direction: Int) {
    let table = activeKeys
    guard table.indices.contains(index), table[index].kana.indices.contains(direction) else { return }
    let key = table[index]
    // 空键面是数字层留的占位(数字键只有四个方向有字),点上去不该发出空串。
    guard !key.kana[direction].isEmpty else { return }
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

/// 滑动时浮在键上方的十字导览。
///
/// Every Japanese flick keyboard shows one: the four directions around the centre, with the one the
/// finger is heading towards picked out. Without it the only feedback was the key's own title
/// changing underneath the finger covering it.
/// One floating tile of the flick cross. The shadow lives here rather than on a shared panel so the
/// four directions read as separate targets the finger can land on, not as one popup.
@MainActor
private final class KanaFlickChip: UIView {
  let label = UILabel()

  init() {
    super.init(frame: .zero)
    layer.cornerRadius = 8
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.25
    layer.shadowRadius = 6
    layer.shadowOffset = CGSize(width: 0, height: 2)
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 22, weight: .regular)
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.6
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      label.topAnchor.constraint(equalTo: topAnchor),
      label.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
private final class KanaFlickPreview: UIView {
  /// 中心、左、上、右、下 —— 和 Key.kana 的顺序一致。
  private static let offsets: [CGPoint] = [
    CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0),
    CGPoint(x: 0, y: 1),
  ]
  private static let gap: CGFloat = 6

  private let chips: [KanaFlickChip] = (0..<5).map { _ in KanaFlickChip() }
  private var cell = CGSize(width: 44, height: 44)

  init() {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    isHidden = true
    backgroundColor = .clear
    for chip in chips { addSubview(chip) }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let middle = CGPoint(x: bounds.midX, y: bounds.midY)
    let step = CGSize(width: cell.width + Self.gap, height: cell.height + Self.gap)
    for (index, chip) in chips.enumerated() {
      let offset = Self.offsets[index]
      chip.frame = CGRect(
        x: middle.x + offset.x * step.width - cell.width / 2,
        y: middle.y + offset.y * step.height - cell.height / 2,
        width: cell.width,
        height: cell.height)
    }
  }

  func show(_ kana: [String], highlighting direction: Int, over key: UIView, in host: UIView) {
    let skin = KeyboardSkinPreference.selected
    for (index, chip) in chips.enumerated() {
      let text = index < kana.count ? kana[index] : ""
      chip.label.text = text
      chip.isHidden = text.isEmpty
      let chosen = index == direction
      chip.label.textColor = chosen ? skin.actionForeground : skin.keyForeground
      chip.backgroundColor = chosen ? skin.accent : skin.keyBackground
    }
    // The cross is centred on the key itself, so the direction the finger moves is the direction the
    // highlight moves. That mapping is the whole point, and it only holds if the two share a centre.
    // It also means the upward tile overflows the keyboard, hence the top-most ancestor rather than
    // the nine-key view, whose bounds would clip it.
    var canvas = host
    while let parent = canvas.superview { canvas = parent }
    if superview !== canvas { canvas.addSubview(self) }
    canvas.bringSubviewToFront(self)
    translatesAutoresizingMaskIntoConstraints = true
    cell = CGSize(width: max(key.bounds.width, 40), height: max(key.bounds.height, 36))
    let step = CGSize(width: cell.width + Self.gap, height: cell.height + Self.gap)
    bounds = CGRect(origin: .zero, size: CGSize(width: step.width * 3, height: step.height * 3))
    center = key.convert(CGPoint(x: key.bounds.midX, y: key.bounds.midY), to: canvas)
    setNeedsLayout()
    isHidden = false
  }

  func hide() { isHidden = true }
}

@MainActor
private final class KanaFlickGesture: UIPanGestureRecognizer {
  /// 取消和结束必须分得开:取消时既不该上屏,也不该把导览留在屏幕上。
  enum Phase { case moving, ended, cancelled }
  private let feedback: (Int, Phase) -> Void
  init(feedback: @escaping (Int, Phase) -> Void) {
    self.feedback = feedback
    super.init(target: nil, action: nil)
    addTarget(self, action: #selector(update))
    maximumNumberOfTouches = 1
    cancelsTouchesInView = true
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    // 手指一落下就摊开四个方向。A pan recognizer stays silent until the touch has travelled about
    // 10pt, so a guide driven off its first callback only appears once the user has already
    // committed to a direction blind. The whole point is to be readable before the move, not after.
    feedback(0, .moving)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
    // 没滑动的纯点击不会走到 .ended,导览得自己收。The button's own action commits the centre kana.
    if state == .possible || state == .failed { feedback(0, .cancelled) }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
    if state == .possible || state == .failed { feedback(0, .cancelled) }
  }

  @objc private func update() {
    let offset = translation(in: view)
    let direction: Int
    if max(abs(offset.x), abs(offset.y)) < 12 { direction = 0 }
    else if abs(offset.x) > abs(offset.y) { direction = offset.x < 0 ? 1 : 3 }
    else { direction = offset.y < 0 ? 2 : 4 }
    if state == .cancelled || state == .failed { feedback(0, .cancelled) }
    else { feedback(direction, state == .ended ? .ended : .moving) }
  }
}
