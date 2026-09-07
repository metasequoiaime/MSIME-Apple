import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
  private enum LetterCaseState {
    case lowercase, shifted, capsLock
  }

  private let skinBackdrop = KeyboardSkinBackgroundView()
  private var keyboardHeightConstraint: NSLayoutConstraint?
  private let session = MetasequoiaInputSessionBridge()
  private let preeditButton = UIButton()
  private let exitLocalModeButton = UIButton()
  private var localModeTrigger: String?
  private var standardRowHeights: [(UIView, NSLayoutConstraint)] = []
  private let candidateScrollView = UIScrollView()
  private let diagnosticLabel = UILabel()
  private let previousPageButton = UIButton()
  private let nextPageButton = UIButton()
  private let candidateStack = UIStackView()
  private let candidateEmptySpacer = UIView()
  private let languageModeButton = UIButton()
  private let schemeButton = UIButton()
  private let shortcutBar = UIStackView()
  private var candidateContent: UIStackView?
  private let scriptShortcut = UIButton()
  private let skinShortcut = UIButton()
  private var skinPicker: KeyboardSkinPickerView?
  private let moreShortcut = UIButton()
  private let dismissShortcut = UIButton()
  private var letterButtons: [(button: UIButton, lowercase: String, hint: UILabel)] = []
  private var microsoftFinalKey: UIButton?
  private var letterRowViews: [UIView] = []
  private var symbolRowViews: [UIView] = []
  private var layoutToggleButton: UIButton?
  private weak var shiftButton: UIButton?
  private weak var enterButton: UIButton?
  private var backspaceRepeatTimer: Timer?
  private var didRepeatBackspace = false
  private var hasComposition = false
  private var isChineseMode = true
  private var inputScheme: ChineseInputScheme = .quanpin
  private var usesShuangpin: Bool { inputScheme.shuangpinProfile != nil }
  private var supportsLocalTools: Bool { isChineseMode && inputScheme != .wubi && inputScheme != .japanese }
  private var nineKeyRows: [UIView] = []
  private var actionRow: UIStackView!
  private var actionDeleteButton: UIButton!
  private var actionGlobeButton: UIButton!
  private var globeWidthConstraint: NSLayoutConstraint?
  private var nineKeyHeight: NSLayoutConstraint!
  private var nineKeySymbolsButton: UIButton!
  private let punctuationStack = UIStackView()
  private var standardActionWidths: [NSLayoutConstraint] = []
  private var nineKeyActionWidths: [NSLayoutConstraint] = []
  private let nineKeyContainer = UIStackView()
  private let spellingScrollView = UIScrollView()
  private let spellingStack = UIStackView()
  private var usesTraditionalOutput = false
  private var visiblePreedit = ""
  private var candidateRevision: UInt64 = 0
  private var visibleCandidates: [String] = []
  private var visibleDiagnostic: String?
  private var diagnosticDismissTimer: Timer?
  private var shuangpinKeyHints: [String: String] = [:]
  private var candidatePageStart = 0
  private var showsSymbols = false
  private var letterCaseState = LetterCaseState.lowercase
  private var isAutomaticShift = false
  private var lastShiftTapTime: TimeInterval?
  // UIKit sends textWillChange/textDidChange for the keyboard's own edits too, not just for edits
  // the host makes. textWillChange cancels the composition, so every commit that was meant to leave
  // a residual composition running destroyed it a runloop turn later. The proxy is cross-process,
  // so the callback does not arrive inside insertText and a simple set/clear flag is already false
  // by the time it lands — the count has to stay raised until the callback consumes it.
  private var pendingOwnEdits = 0

  // The strip numbers its chips 1-9 to match the digits on the symbol layer, so a page is nine.
  private static let candidatePageSize = 9

  private lazy var keyFeedback: UIImpactFeedbackGenerator = {
    if #available(iOS 17.5, *) {
      return UIImpactFeedbackGenerator(style: .medium, view: view)
    }
    return UIImpactFeedbackGenerator(style: .medium)
  }()

  private let letterRows = [
    Array("qwertyuiop"),
    Array("asdfghjkl"),
    Array("zxcvbnm"),
  ]
  private let symbolRows = [
    Array("1234567890").map(String.init),
    [",", ".", "?", "!", ";", ":", "'", "\""],
    ["(", ")", "[", "]", "<", ">", "\\", "-"],
  ]

  override func loadView() {
    inputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    inputScheme = InputSchemePreference.scheme
    usesTraditionalOutput = ChineseOutputPreference.usesTraditional
    _ = applyInputScheme()
    view.backgroundColor = MetasequoiaTheme.keyboardBackground
    skinBackdrop.translatesAutoresizingMaskIntoConstraints = false
    view.insertSubview(skinBackdrop, at: 0)
    NSLayoutConstraint.activate([
      skinBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      skinBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      skinBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
      skinBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    installKeyboard()
    let height = view.heightAnchor.constraint(equalToConstant: 260)
    height.priority = .init(999)
    height.identifier = "keyboardHeight"
    height.isActive = true
    keyboardHeightConstraint = height
    updateReturnKey()
    // installKeyboard builds the candidate strip before the letter rows exist, so the hints the
    // scheme button gathered there have not reached any key yet.
    updateLetterCaseControls()
    updateCandidateStrip(preedit: "", candidates: [])
    applyKeyboardSkin()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    prepareKeyFeedback()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // A fresh editing session owes us no callbacks. Clearing the count here bounds the damage if
    // UIKit ever skips the delegate pair for one of our own edits: the worst case is that a single
    // host-initiated change is treated as an echo, not a counter that stays raised forever.
    pendingOwnEdits = 0
    synchronizeInputSchemePreference()
    synchronizeChineseOutputPreference()
    applyKeyboardSkin()
  }

  override func textWillChange(_ textInput: UITextInput?) {
    super.textWillChange(textInput)
    // Our own edit coming back to us: the composition it produced is still the live one.
    if pendingOwnEdits > 0 {
      pendingOwnEdits -= 1
      return
    }
    // A genuine host-initiated change — the caret moved, the field was cleared, the document was
    // swapped. Commit what is composed rather than discarding it, the way macOS commits on every
    // automatic boundary.
    render(session.finishComposition())
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    updateReturnKey()
    updateAutomaticCapitalization()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    closeSkinPicker()
    // Putting the keyboard away used to drop whatever was composed. macOS commits in
    // prepareForDeactivation: for the same reason: the user typed those letters and never asked to
    // throw them away.
    render(session.finishComposition())
    pendingOwnEdits = 0
    cancelBackspacePress()
    diagnosticDismissTimer?.invalidate()
    diagnosticDismissTimer = nil
  }

  private func installKeyboard() {
    let root = UIStackView()
    root.axis = .vertical
    root.spacing = 7
    root.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(root)

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
      root.topAnchor.constraint(equalTo: view.topAnchor, constant: 7),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -7),
    ])

    root.addArrangedSubview(makeCandidateStrip())
    preeditButton.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.28).isActive = true
    for (index, row) in letterRows.enumerated() {
      let rowView = makeLetterRow(row, includesShift: index == letterRows.count - 1)
      letterRowViews.append(rowView)
      root.addArrangedSubview(rowView)
    }
    root.addArrangedSubview(makeNineKeyLayout())
    for row in symbolRows {
      let rowView = makeSymbolRow(row)
      rowView.isHidden = true
      symbolRowViews.append(rowView)
      root.addArrangedSubview(rowView)
    }
    actionRow = makeActionRow()
    root.addArrangedSubview(actionRow)
    standardRowHeights = (letterRowViews + symbolRowViews).map {
      ($0, $0.heightAnchor.constraint(equalTo: actionRow.heightAnchor))
    }
    // Keep the three keypad rows the same height as the bottom controls.
    nineKeyHeight = nineKeyContainer.heightAnchor.constraint(
      equalTo: actionRow.heightAnchor, multiplier: 3, constant: 14)
    updateKeyboardLayout()
  }

  private func makeNineKeyLayout() -> UIView {
    nineKeyContainer.axis = .horizontal
    nineKeyContainer.spacing = 6
    let sidebar = UIView()
    sidebar.accessibilityIdentifier = "nineKeySidebar"
    sidebar.backgroundColor = KeyboardSkinPreference.selected.keyBackground.withAlphaComponent(0.5)
    sidebar.layer.cornerRadius = 8
    punctuationStack.axis = .vertical
    punctuationStack.distribution = .fillEqually
    for symbol in ["，", "。", "？", "！"] {
      let button = makeKey(title: symbol, accessibilityLabel: "符号 \(symbol)") { [weak self] in
        self?.handleSymbol(symbol)
      }
      button.configuration?.background.backgroundColor = .clear
      punctuationStack.addArrangedSubview(button)
    }
    for content in [punctuationStack, makeSpellingStrip()] {
      content.translatesAutoresizingMaskIntoConstraints = false
      sidebar.addSubview(content)
      NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
        content.topAnchor.constraint(equalTo: sidebar.topAnchor),
        content.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
      ])
    }
    nineKeyContainer.addArrangedSubview(sidebar)
    sidebar.widthAnchor.constraint(equalTo: nineKeyContainer.widthAnchor, multiplier: 0.14).isActive = true
    let nineKeyGrid = UIStackView()
    nineKeyGrid.axis = .vertical
    nineKeyGrid.spacing = 7
    nineKeyGrid.distribution = .fillEqually
    nineKeyContainer.addArrangedSubview(nineKeyGrid)
    let groups = [["1", "ABC", "DEF"], ["GHI", "JKL", "MNO"], ["PQRS", "TUV", "WXYZ"]]
    for (rowIndex, lettersInRow) in groups.enumerated() {
      let row = makeRow()
      for (column, letters) in lettersInRow.enumerated() {
        let digit = rowIndex * 3 + column + 1
        let button = makeKey(
          title: digit == 1 ? "分词" : letters,
          accessibilityLabel: digit == 1 ? "拼音分词" : "\(digit) \(letters)"
        ) { [weak self] in
          if digit == 1 { self?.handleCharacter("'") }
          else { self?.handleCharacter(String(digit)) }
        }
        button.accessibilityIdentifier = "nineKey\(digit)"
        if var configuration = button.configuration {
          configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0)
          configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = KeyboardSkinPreference.selected.usesMonospacedFont
              ? .monospacedSystemFont(ofSize: 21, weight: .medium) : .systemFont(ofSize: 21, weight: .medium)
            return attributes
          }
          button.configuration = configuration
        }
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        if digit != 1 {
          let number = UILabel()
          number.text = String(digit)
          number.font = .systemFont(ofSize: 10)
          number.textColor = KeyboardSkinPreference.selected.accent
          number.accessibilityIdentifier = "keyNumberHint"
          number.translatesAutoresizingMaskIntoConstraints = false
          number.isAccessibilityElement = false
          button.addSubview(number)
          NSLayoutConstraint.activate([
            number.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
            number.centerXAnchor.constraint(equalTo: button.centerXAnchor),
          ])
        }
        row.addArrangedSubview(button)
      }
      nineKeyGrid.addArrangedSubview(row)
      nineKeyRows.append(row)
    }
    let controls = UIStackView()
    controls.axis = .vertical
    controls.spacing = 7
    controls.distribution = .fillEqually
    let delete = makeDeleteKey()
    delete.accessibilityIdentifier = "nineKeyDelete"
    controls.addArrangedSubview(delete)
    let clear = makeKey(title: "重输", accessibilityLabel: "清空当前拼音重新输入") { [weak self] in
      guard let self else { return }
      self.playInputClick()
      self.render(self.session.cancel())
    }
    clear.configuration?.contentInsets = .zero
    clear.accessibilityIdentifier = "nineKeyClear"
    controls.addArrangedSubview(clear)
    let zero = makeKey(title: "0", accessibilityLabel: "数字 0") { [weak self] in
      self?.handleSymbol("0")
    }
    controls.addArrangedSubview(zero)
    nineKeyContainer.addArrangedSubview(controls)
    controls.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
    return nineKeyContainer
  }

  private func makeCandidateStrip() -> UIView {
    let container = UIView()
    container.accessibilityIdentifier = "candidateStrip"
    container.backgroundColor = KeyboardSkinPreference.selected.keyBackground.withAlphaComponent(0.82)
    container.layer.cornerRadius = 12

    var preeditConfiguration = UIButton.Configuration.plain()
    preeditConfiguration.contentInsets = .zero
    preeditConfiguration.titleLineBreakMode = .byTruncatingHead
    preeditConfiguration.baseForegroundColor = KeyboardSkinPreference.selected.accent
    preeditConfiguration.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = .preferredFont(forTextStyle: .subheadline)
        return attributes
      }
    preeditButton.configuration = preeditConfiguration
    preeditButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    preeditButton.showsMenuAsPrimaryAction = true
    preeditButton.accessibilityIdentifier = "preeditButton"

    updateLanguageModeButton()
    languageModeButton.addAction(
      UIAction { [weak self] _ in self?.toggleInputMode() }, for: .primaryActionTriggered)


    updateSchemeButton()
    schemeButton.showsMenuAsPrimaryAction = true


    candidateStack.axis = .horizontal
    candidateStack.spacing = 6
    candidateStack.translatesAutoresizingMaskIntoConstraints = false
    candidateScrollView.showsHorizontalScrollIndicator = false
    candidateScrollView.addSubview(candidateStack)

    diagnosticLabel.font = .preferredFont(forTextStyle: .footnote)
    diagnosticLabel.textColor = MetasequoiaTheme.coneUIColor
    diagnosticLabel.adjustsFontForContentSizeCategory = true
    diagnosticLabel.adjustsFontSizeToFitWidth = true
    diagnosticLabel.minimumScaleFactor = 0.7
    diagnosticLabel.isHidden = true
    diagnosticLabel.accessibilityIdentifier = "diagnosticLabel"

    configurePageButton(previousPageButton, symbol: "chevron.left", label: "上一页候选")
    previousPageButton.addAction(
      UIAction { [weak self] _ in self?.showCandidatePage(offset: -1) },
      for: .primaryActionTriggered)
    configurePageButton(nextPageButton, symbol: "chevron.right", label: "下一页候选")
    nextPageButton.addAction(
      UIAction { [weak self] _ in self?.showCandidatePage(offset: 1) },
      for: .primaryActionTriggered)

    let content = UIStackView(arrangedSubviews: [
      preeditButton, candidateScrollView, diagnosticLabel,
      candidateEmptySpacer, previousPageButton, nextPageButton, exitLocalModeButton,
    ])
    content.axis = .horizontal
    content.alignment = .center
    content.spacing = 12
    content.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(content)
    candidateContent = content
    var exitConfiguration = UIButton.Configuration.plain()
    exitConfiguration.image = UIImage(systemName: "xmark.circle.fill")
    exitConfiguration.contentInsets = .zero
    exitLocalModeButton.configuration = exitConfiguration
    exitLocalModeButton.accessibilityIdentifier = "exitLocalModeButton"
    exitLocalModeButton.accessibilityLabel = "退出本地模式"
    exitLocalModeButton.widthAnchor.constraint(equalToConstant: 38).isActive = true
    exitLocalModeButton.isHidden = true
    exitLocalModeButton.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      render(session.cancel())
    }, for: .primaryActionTriggered)
    installShortcutBar(in: container)

    NSLayoutConstraint.activate([
      container.heightAnchor.constraint(equalToConstant: 38),
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      candidateStack.leadingAnchor.constraint(
        equalTo: candidateScrollView.contentLayoutGuide.leadingAnchor),
      candidateStack.trailingAnchor.constraint(
        equalTo: candidateScrollView.contentLayoutGuide.trailingAnchor),
      candidateStack.topAnchor.constraint(
        equalTo: candidateScrollView.contentLayoutGuide.topAnchor),
      candidateStack.bottomAnchor.constraint(
        equalTo: candidateScrollView.contentLayoutGuide.bottomAnchor),
      candidateStack.heightAnchor.constraint(
        equalTo: candidateScrollView.frameLayoutGuide.heightAnchor),
    ])
    return container
  }

  private func installShortcutBar(in container: UIView) {
    shortcutBar.axis = .horizontal
    shortcutBar.distribution = .fill
    shortcutBar.spacing = 1
    shortcutBar.accessibilityIdentifier = "keyboardShortcutBar"
    shortcutBar.translatesAutoresizingMaskIntoConstraints = false
    let brand = UIView()
    let icon = UIImageView()
    if let path = Bundle(for: KeyboardViewController.self).path(forResource: "KeyboardBrand", ofType: "png") {
      icon.image = UIImage(contentsOfFile: path)?.preparingThumbnail(of: CGSize(width: 66, height: 66))
    }
    icon.accessibilityIdentifier = "keyboardBrandIcon"
    icon.contentMode = .scaleAspectFit
    icon.layer.cornerRadius = 5
    icon.clipsToBounds = true
    icon.translatesAutoresizingMaskIntoConstraints = false
    brand.addSubview(icon)
    shortcutBar.addArrangedSubview(brand)
    NSLayoutConstraint.activate([
      brand.widthAnchor.constraint(equalToConstant: 22),
      icon.widthAnchor.constraint(equalToConstant: 22),
      icon.heightAnchor.constraint(equalToConstant: 22),
      icon.centerXAnchor.constraint(equalTo: brand.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
    ])
    for button in [languageModeButton, schemeButton, scriptShortcut, skinShortcut, moreShortcut, dismissShortcut] {
      shortcutBar.addArrangedSubview(button)
      if button !== languageModeButton {
        button.widthAnchor.constraint(equalTo: languageModeButton.widthAnchor).isActive = true
      }
    }
    container.addSubview(shortcutBar)
    NSLayoutConstraint.activate([
      shortcutBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
      shortcutBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
      shortcutBar.topAnchor.constraint(equalTo: container.topAnchor),
      shortcutBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    scriptShortcut.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      usesTraditionalOutput.toggle()
      ChineseOutputPreference.usesTraditional = usesTraditionalOutput
      renderCandidateStrip()
      updateShortcutButtons()
    }, for: .primaryActionTriggered)
    skinShortcut.addAction(UIAction { [weak self] _ in self?.showSkinPicker() }, for: .primaryActionTriggered)
    moreShortcut.showsMenuAsPrimaryAction = true
    dismissShortcut.addAction(UIAction { [weak self] _ in self?.dismissKeyboard() }, for: .primaryActionTriggered)
    updateShortcutButtons()
  }

  private func updateShortcutButtons() {
    func configure(_ button: UIButton, title: String?, symbol: String?, label: String, id: String) {
      var configuration = UIButton.Configuration.plain()
      configuration.title = title
      configuration.image = symbol.flatMap { UIImage(systemName: $0) }
      configuration.baseForegroundColor = KeyboardSkinPreference.selected.accent
      configuration.contentInsets = .zero
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = .systemFont(ofSize: 16, weight: .medium)
        return attributes
      }
      button.configuration = configuration
      button.accessibilityLabel = label
      button.accessibilityIdentifier = id
    }
    configure(scriptShortcut, title: usesTraditionalOutput ? "繁" : "简", symbol: nil,
      label: usesTraditionalOutput ? "切换到简体" : "切换到繁体", id: "scriptShortcut")
    scriptShortcut.isEnabled = !(isChineseMode && inputScheme == .japanese)
    scriptShortcut.accessibilityValue = scriptShortcut.isEnabled ? (usesTraditionalOutput ? "繁体" : "简体") : "日语不使用简繁转换"
    configure(skinShortcut, title: nil, symbol: "tshirt", label: "切换皮肤", id: "skinShortcut")
    skinShortcut.accessibilityValue = KeyboardSkinPreference.selected.title
    configure(moreShortcut, title: nil, symbol: "ellipsis.circle", label: "更多快捷设置", id: "moreShortcut")
    moreShortcut.menu = UIMenu(children: [
      UIMenu(title: "按键反馈", options: .displayInline, children: [
        UIAction(title: "按键音", image: UIImage(systemName: "speaker.wave.2"),
          state: KeyboardFeedbackPreference.soundEnabled ? .on : .off) { [weak self] _ in
          KeyboardFeedbackPreference.defaults.set(!KeyboardFeedbackPreference.soundEnabled, forKey: KeyboardFeedbackPreference.soundKey)
          if KeyboardFeedbackPreference.soundEnabled { UIDevice.current.playInputClick() }
          self?.updateShortcutButtons()
        },
        UIAction(title: "按键振动", image: UIImage(systemName: "iphone.radiowaves.left.and.right"),
          state: KeyboardFeedbackPreference.hapticsEnabled ? .on : .off) { [weak self] _ in
          KeyboardFeedbackPreference.defaults.set(!KeyboardFeedbackPreference.hapticsEnabled, forKey: KeyboardFeedbackPreference.hapticsKey)
          if KeyboardFeedbackPreference.hapticsEnabled {
            self?.keyFeedback.impactOccurred(intensity: 1.0)
            self?.prepareKeyFeedback()
          }
          self?.updateShortcutButtons()
        },
      ]),
      UIMenu(title: "本地输入", children: Self.localInputModes.map { mode in
        UIAction(title: mode.title, attributes: supportsLocalTools ? [] : .disabled) { [weak self] _ in
          self?.openLocalInputMode(mode.trigger)
        }
      }),
    ])
    configure(dismissShortcut, title: nil, symbol: "keyboard.chevron.compact.down", label: "收起键盘", id: "dismissShortcut")
  }

  private func makeSpellingStrip() -> UIView {
    spellingScrollView.showsVerticalScrollIndicator = false
    spellingStack.axis = .vertical
    spellingStack.spacing = 6
    spellingStack.translatesAutoresizingMaskIntoConstraints = false
    spellingScrollView.addSubview(spellingStack)
    NSLayoutConstraint.activate([

      spellingStack.leadingAnchor.constraint(equalTo: spellingScrollView.contentLayoutGuide.leadingAnchor),
      spellingStack.trailingAnchor.constraint(equalTo: spellingScrollView.contentLayoutGuide.trailingAnchor),
      spellingStack.topAnchor.constraint(equalTo: spellingScrollView.contentLayoutGuide.topAnchor),
      spellingStack.bottomAnchor.constraint(equalTo: spellingScrollView.contentLayoutGuide.bottomAnchor),
      spellingStack.widthAnchor.constraint(equalTo: spellingScrollView.frameLayoutGuide.widthAnchor),
    ])
    return spellingScrollView
  }

  private func updateSpellingStrip() {
    spellingStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (index, spelling) in session.nineKeySpellings().enumerated() {
      let button = UIButton(type: .system)
      var configuration = UIButton.Configuration.tinted()
      configuration.title = spelling
      configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = .systemFont(ofSize: 14)
        return attributes
      }
      configuration.baseForegroundColor = KeyboardSkinPreference.selected.accent
      button.configuration = configuration
      button.accessibilityLabel = "选择拼音 \(spelling)"
      button.accessibilityIdentifier = "nineKeySpelling_\(spelling)"
      button.addAction(UIAction { [weak self] _ in
        guard let self else { return }
        self.playInputClick()
        self.render(self.session.chooseNineKeySpelling(at: UInt(index)))
      }, for: .primaryActionTriggered)
      spellingStack.addArrangedSubview(button)
    }
    spellingScrollView.setContentOffset(.zero, animated: false)
    updateKeyboardLayout()
  }

  private func makeLetterRow(_ letters: [Character], includesShift: Bool) -> UIStackView {
    let row = makeRow()
    if includesShift {
      let button = makeSymbolKey(symbol: "shift", accessibilityLabel: "大写") { [weak self] in
        self?.toggleLetterCase()
      }
      button.accessibilityIdentifier = "shiftButton"
      shiftButton = button
      row.addArrangedSubview(button)
    }
    for letter in letters {
      let text = String(letter)
      let button = makeKey(title: text, accessibilityLabel: text.uppercased()) { [weak self] in
        self?.handleCharacter(text)
      }
      letterButtons.append((button: button, lowercase: text, hint: attachHintLabel(to: button)))
      row.addArrangedSubview(button)
    }
    if letters == letterRows[1] {
      let key = makeKey(title: ";", accessibilityLabel: "微软双拼 ing") { [weak self] in self?.handleCharacter(";") }
      key.accessibilityIdentifier = "microsoftFinalKey"
      microsoftFinalKey = key
      letterButtons.append((button: key, lowercase: ";", hint: attachHintLabel(to: key)))
      row.addArrangedSubview(key)
    }
    return row
  }

  // A key is about 36pt wide and the longest Xiaohe mapping is nine characters, so the hint has to
  // be one line that shrinks rather than a subtitle that wraps: wrapping pushed the letter itself
  // out of the top of the key.
  private func attachHintLabel(to button: UIButton) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: 9, weight: .regular)
    label.textColor = KeyboardSkinPreference.selected.accent.withAlphaComponent(0.8)
    label.textAlignment = .center
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.6
    label.isHidden = true
    label.isAccessibilityElement = false
    label.translatesAutoresizingMaskIntoConstraints = false
    button.addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
      label.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -2),
    ])
    return label
  }

  private func makeSymbolRow(_ symbols: [String]) -> UIStackView {
    let row = makeRow()
    for symbol in symbols {
      row.addArrangedSubview(
        makeKey(title: symbol, accessibilityLabel: "符号 \(symbol)") { [weak self] in
          self?.handleSymbol(symbol)
        })
    }
    return row
  }

  private func makeActionRow() -> UIStackView {
    let row = UIStackView()
    row.axis = .horizontal
    row.alignment = .fill
    row.distribution = .fill
    row.spacing = 6

    let layoutToggle = makeKey(title: "123", accessibilityLabel: "切换到数字和符号") {
      [weak self] in self?.toggleLayout()
    }
    if var configuration = layoutToggle.configuration {
      configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 0, leading: 4, bottom: 0, trailing: 4)
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        attributes in
        var attributes = attributes
        attributes.font = .systemFont(ofSize: 17, weight: .medium)
        return attributes
      }
      layoutToggle.configuration = configuration
    }
    layoutToggle.titleLabel?.adjustsFontSizeToFitWidth = true
    layoutToggle.titleLabel?.minimumScaleFactor = 0.7
    layoutToggle.titleLabel?.lineBreakMode = .byClipping
    layoutToggle.accessibilityIdentifier = "layoutToggleButton"
    layoutToggleButton = layoutToggle
    nineKeySymbolsButton = makeKey(title: "符", accessibilityLabel: "常用符号") {}
    nineKeySymbolsButton.menu = UIMenu(children: [
      "，", "。", "？", "！", "、", "；", "：", "……", "——", "（", "）", "“", "”", "《", "》", "@",
    ].map { symbol in
      UIAction(title: symbol) { [weak self] _ in self?.handleSymbol(symbol) }
    })
    nineKeySymbolsButton.showsMenuAsPrimaryAction = true
    nineKeySymbolsButton.configuration?.contentInsets = .zero
    row.addArrangedSubview(nineKeySymbolsButton)
    row.addArrangedSubview(layoutToggle)

    let globe = makeSymbolKey(symbol: "globe", accessibilityLabel: "选择下一个键盘")
    globe.accessibilityIdentifier = "inputModeSwitchButton"
    globe.addTarget(
      self, action: #selector(handleInputModeButton(_:event:)), for: .allTouchEvents)
    row.addArrangedSubview(globe)

    let delete = makeDeleteKey()
    actionDeleteButton = delete
    row.addArrangedSubview(delete)

    let space = makeKey(title: "空格", accessibilityLabel: "空格") { [weak self] in
      self?.handleSpace()
    }
    row.addArrangedSubview(space)

    let enter = makeKey(title: "换行", accessibilityLabel: "换行", emphasized: true) { [weak self] in
      self?.handleReturn()
    }
    enter.accessibilityIdentifier = "returnKey"
    enter.titleLabel?.adjustsFontSizeToFitWidth = true
    enter.titleLabel?.minimumScaleFactor = 0.65
    enterButton = enter
    row.addArrangedSubview(enter)

    standardActionWidths = [
      layoutToggle.widthAnchor.constraint(equalTo: delete.widthAnchor, multiplier: 1.1),
      space.widthAnchor.constraint(greaterThanOrEqualTo: delete.widthAnchor, multiplier: 1.8),
      enter.widthAnchor.constraint(equalTo: delete.widthAnchor, multiplier: 1.35),
      delete.widthAnchor.constraint(equalToConstant: 44),
    ]
    nineKeyActionWidths = [
      nineKeySymbolsButton.widthAnchor.constraint(equalTo: nineKeyContainer.widthAnchor, multiplier: 0.14),
      layoutToggle.widthAnchor.constraint(equalTo: nineKeySymbolsButton.widthAnchor),
      enter.widthAnchor.constraint(equalTo: nineKeySymbolsButton.widthAnchor, multiplier: 1.3),
    ]
    actionGlobeButton = globe
    return row
  }

  private func makeDeleteKey() -> UIButton {
    let delete = makeSymbolKey(symbol: "delete.left", accessibilityLabel: "删除")
    delete.addTarget(self, action: #selector(beginBackspacePress), for: .touchDown)
    delete.addTarget(self, action: #selector(finishBackspacePress), for: .touchUpInside)
    delete.addTarget(
      self,
      action: #selector(cancelBackspacePress),
      for: [.touchUpOutside, .touchCancel, .touchDragExit])
    return delete
  }

  private func makeRow() -> UIStackView {
    let row = UIStackView()
    row.axis = .horizontal
    row.alignment = .fill
    row.distribution = .fillEqually
    row.spacing = 6
    return row
  }

  private func handleCharacter(_ character: String) {
    playInputClick()
    if isChineseMode {
      synchronizeInputSchemePreference()
      // A host setting can change while this view is open. Do not start an alphabetic composition
      // from a stale 26-key tap after switching to nine keys; local utilities still need letters.
      if inputScheme == .nineKey && !session.isInLocalMode
        && !("2"..."9").contains(character) && character != "'" {
        return
      }
      render(session.handleCharacter(character))
    } else {
      let output = letterCaseState == .lowercase ? character : character.uppercased()
      insertOwnText(output)
      if letterCaseState == .shifted {
        letterCaseState = .lowercase
        lastShiftTapTime = nil
        updateLetterCaseControls()
      }
    }
  }

  private func handleSymbol(_ symbol: String) {
    playInputClick()
    if !isChineseMode {
      insertOwnText(symbol)
      return
    }

    // Unicode mode reads a hexadecimal code point, so while it is open its digits are input rather
    // than candidate numbers. Its letters already reach the session through handleCharacter.
    if session.isInUnicodeMode, symbol.count == 1, symbol >= "0", symbol <= "9" {
      render(session.handleCharacter(symbol))
      return
    }

    if symbol.count == 1, symbol >= "1", symbol <= "9" {
      // handleCandidateKey numbers from the engine's first candidate, which stops matching the
      // strip as soon as it is showing a later page. Off the first page the digit has to select the
      // absolute index the chip with that number is actually displaying, and a digit with no chip
      // on this page has to do nothing: falling through would hand it to handleCandidateKey and
      // commit a first-page candidate the user cannot see.
      if candidatePageStart > 0, let digit = Int(symbol) {
        let index = candidatePageStart + digit - 1
        if index < visibleCandidates.count {
          render(session.selectCandidate(at: UInt(index)))
        }
        return
      }

      let snapshot = session.handleCandidateKey(symbol)
      if !snapshot.isHandled && snapshot.preedit.isEmpty {
        insertOwnText(symbol)
      }
      render(snapshot)
      return
    }

    if symbol == "'" {
      let separatorSnapshot = session.handleCharacter(symbol)
      if separatorSnapshot.isHandled {
        render(separatorSnapshot)
        return
      }
    }

    let snapshot = session.handlePunctuation(symbol)
    if snapshot.isHandled {
      render(snapshot)
      return
    }

    // A symbol the session declines is an automatic commit, and macOS resolves those with
    // finish_composition — the leading candidate. commitRaw committed the raw pinyin letters
    // instead, so typing "nihao" then "@" produced "nihao@" rather than "你好@".
    render(session.finishComposition())
    insertOwnText(symbol)
  }

  private func toggleInputMode() {
    playInputClick()
    let snapshot = isChineseMode ? session.finishComposition() : session.cancel()
    render(snapshot)
    isChineseMode.toggle()
    letterCaseState = .lowercase
    isAutomaticShift = false
    lastShiftTapTime = nil
    updateLanguageModeButton()
    updateAutomaticCapitalization()
  }

  private func toggleLetterCase() {
    if isChineseMode {
      toggleInputMode()
      letterCaseState = .lowercase
    }

    playInputClick()
    isAutomaticShift = false
    let now = ProcessInfo.processInfo.systemUptime
    if letterCaseState == .shifted,
      let lastShiftTapTime,
      now - lastShiftTapTime <= 0.35
    {
      letterCaseState = .capsLock
    } else {
      letterCaseState = letterCaseState == .lowercase ? .shifted : .lowercase
    }
    self.lastShiftTapTime = now
    updateLetterCaseControls()
  }

  private func updateAutomaticCapitalization() {
    guard !isChineseMode else {
      isAutomaticShift = false
      updateLetterCaseControls()
      return
    }
    guard letterCaseState != .capsLock else {
      updateLetterCaseControls()
      return
    }

    let mode: EnglishCapitalizationMode
    switch textDocumentProxy.autocapitalizationType ?? .sentences {
    case .none:
      mode = .none
    case .words:
      mode = .words
    case .sentences:
      mode = .sentences
    case .allCharacters:
      mode = .allCharacters
    @unknown default:
      mode = .sentences
    }

    isAutomaticShift = EnglishCapitalizationPolicy.shouldShift(
      for: mode,
      contextBeforeInput: textDocumentProxy.documentContextBeforeInput)
    letterCaseState = isAutomaticShift ? .shifted : .lowercase
    lastShiftTapTime = nil
    updateLetterCaseControls()
  }

  private func updateLetterCaseControls() {
    let usesUppercase = !isChineseMode && letterCaseState != .lowercase
    for (button, lowercase, hintLabel) in letterButtons {
      // A hint only means something while the key feeds a double-pinyin composition, so English
      // mode drops it even though the scheme underneath is unchanged.
      let hint = isChineseMode && !session.isInLocalMode ? shuangpinKeyHints[lowercase.uppercased()] : nil
      if var configuration = button.configuration {
        configuration.title = usesUppercase ? lowercase.uppercased() : lowercase
        // The hint sits along the bottom edge, so the letter is lifted clear of it instead of
        // staying centred in the whole key.
        configuration.contentInsets = NSDirectionalEdgeInsets(
          top: 0, leading: 0, bottom: hint == nil ? 0 : 11, trailing: 0)
        button.configuration = configuration
      }
      hintLabel.text = hint
      hintLabel.isHidden = hint == nil
      button.accessibilityLabel =
        usesUppercase
        ? "大写 \(lowercase.uppercased())" : "字母 \(lowercase.uppercased())"
      button.accessibilityValue = hint
    }

    guard let button = shiftButton, var configuration = button.configuration else { return }
    switch letterCaseState {
    case .lowercase:
      configuration.image = UIImage(systemName: "shift")
      configuration.background.backgroundColor = KeyboardSkinPreference.selected.keyBackground
      button.accessibilityLabel = isChineseMode ? "切换到英文大写" : "大写"
      button.accessibilityValue = "关闭"
    case .shifted:
      configuration.image = UIImage(systemName: "shift.fill")
      configuration.background.backgroundColor =
        KeyboardSkinPreference.selected.accent.withAlphaComponent(0.22)
      button.accessibilityLabel = "大写"
      button.accessibilityValue = isAutomaticShift ? "自动开启" : "下一字母"
    case .capsLock:
      configuration.image = UIImage(systemName: "capslock.fill")
      configuration.background.backgroundColor =
        KeyboardSkinPreference.selected.accent.withAlphaComponent(0.32)
      button.accessibilityLabel = "大写锁定"
      button.accessibilityValue = "开启"
    }
    button.configuration = configuration
  }

  private func updateLanguageModeButton() {
    var configuration = UIButton.Configuration.filled()
    configuration.title = isChineseMode ? (inputScheme == .japanese ? "日" : "中") : "英"
    configuration.baseForegroundColor = .white
    configuration.baseBackgroundColor = KeyboardSkinPreference.selected.actionBackground
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 3, leading: 5, bottom: 3, trailing: 5)
    configuration.background.cornerRadius = 8
    languageModeButton.configuration = configuration
    languageModeButton.accessibilityIdentifier = "languageModeButton"
    languageModeButton.accessibilityLabel =
      isChineseMode ? "切换到英文输入" : "切换到所选输入方案"
    languageModeButton.accessibilityValue = isChineseMode ? (inputScheme == .japanese ? "日语输入" : "中文输入") : "英文输入"
    updateShortcutButtons()
    updateKeyboardLayout()
  }

  private func updateReturnKey() {
    let title: String
    switch textDocumentProxy.returnKeyType ?? .default {
    case .default:
      title = "换行"
    case .go:
      title = "前往"
    case .google, .search, .yahoo:
      title = "搜索"
    case .join:
      title = "加入"
    case .next:
      title = "下一项"
    case .route:
      title = "路线"
    case .send:
      title = "发送"
    case .done:
      title = "完成"
    case .emergencyCall:
      title = "紧急呼叫"
    case .continue:
      title = "继续"
    @unknown default:
      title = "换行"
    }

    if var configuration = enterButton?.configuration {
      configuration.title = title
      enterButton?.configuration = configuration
    }
    enterButton?.accessibilityLabel = title
  }

  private func applyInputScheme() -> MetasequoiaInputSnapshot {
    switch inputScheme {
    case .nineKey: session.switchToNineKey()
    case .ziranma, .microsoft, .shoudao: session.switch(toShuangpinProfile: inputScheme.rawValue)
    case .wubi: session.switchToWubi()
    case .japanese: session.switchToJapanese()
    case .quanpin, .shuangpin: session.switch(toShuangpin: usesShuangpin)
    }
  }

  private func selectInputScheme(_ scheme: ChineseInputScheme) {
    guard scheme != inputScheme else { return }
    playInputClick()
    let source = typingSource
    inputScheme = scheme
    let snapshot = applyInputScheme()
    InputSchemePreference.scheme = scheme
    showsSymbols = false
    updateSchemeButton()
    updateLanguageModeButton()
    render(snapshot, source: source)
  }

  private func synchronizeInputSchemePreference() {
    guard !hasComposition else { return }
    let sharedValue = InputSchemePreference.scheme
    guard sharedValue != inputScheme else { return }
    let source = typingSource
    inputScheme = sharedValue
    let snapshot = applyInputScheme()
    updateSchemeButton()
    updateLanguageModeButton()
    render(snapshot, source: source)
  }

  // The output script may change in the host app while the keyboard is loaded, so it is re-read on
  // every appearance. Unlike the input scheme it never touches the session, so an active composition
  // only needs its visible candidates redrawn.
  private func synchronizeChineseOutputPreference() {
    let sharedValue = ChineseOutputPreference.usesTraditional
    guard sharedValue != usesTraditionalOutput else { return }

    usesTraditionalOutput = sharedValue
    renderCandidateStrip()
  }

  private func configurePageButton(_ button: UIButton, symbol: String, label: String) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: symbol)
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.accent
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 2, leading: 2, bottom: 2, trailing: 2)
    button.configuration = configuration
    button.accessibilityLabel = label
    button.accessibilityIdentifier =
      symbol == "chevron.left" ? "previousCandidatePage" : "nextCandidatePage"
    button.isHidden = true
    button.widthAnchor.constraint(equalToConstant: 26).isActive = true
  }

  private func showCandidatePage(offset: Int) {
    let target = candidatePageStart + offset * Self.candidatePageSize
    guard target >= 0, target < visibleCandidates.count else { return }

    playInputClick()
    candidatePageStart = target
    renderCandidateStrip()
  }

  private func updatePageControls() {
    // The strip scrolls, so paging is what makes the numbered keys reach past the ninth candidate
    // rather than a way to see them. It is only offered when there is somewhere to go.
    let pageable = visibleCandidates.count > Self.candidatePageSize && visibleDiagnostic == nil
    previousPageButton.isHidden = !pageable || candidatePageStart == 0
    nextPageButton.isHidden =
      !pageable || candidatePageStart + Self.candidatePageSize >= visibleCandidates.count
  }

  // The engine's local input modes open on a capital carried with a shift-only modifier, which this
  // keyboard has no key for. While nothing is being composed the strip's own name is dead space, so
  // it doubles as the way in; during a composition it goes back to showing the preedit and the menu
  // is withdrawn, because a mode cannot open on top of a composition anyway.
  private static let localInputModes = [
    (trigger: "U", title: "Unicode 码点"),
    (trigger: "T", title: "日期时间"),
    (trigger: "J", title: "超级简拼"),
    (trigger: "K", title: "快捷短语"),
    (trigger: "Y", title: "英文补全"),
    (trigger: "E", title: "表情"),
    (trigger: "M", title: "颜文字"),
    (trigger: "R", title: "临时日语"),
  ]

  private func updatePreeditButton() {
    let idle = visiblePreedit.isEmpty
    let modeName = Self.localInputModes.first { $0.trigger == localModeTrigger }?.title
    let title = session.isInLocalMode && visiblePreedit == localModeTrigger
      ? (modeName ?? visiblePreedit)
      : (idle ? (isChineseMode ? "水杉输入法" : "英文输入") : visiblePreedit)
    if var configuration = preeditButton.configuration {
      configuration.title = title
      preeditButton.configuration = configuration
    }

    let offersModes = idle && supportsLocalTools
    preeditButton.menu =
      offersModes
      ? UIMenu(
        title: "本地输入",
        children: Self.localInputModes.map { mode in
          UIAction(title: mode.title) { [weak self] _ in
            self?.openLocalInputMode(mode.trigger)
          }
        })
      : nil
    // Withdrawing the menu is what makes the button inert; disabling it would dim the title, and
    // this is the preedit, which has to keep reading as the text the user is composing.
    preeditButton.accessibilityLabel = offersModes ? "本地输入模式" : title
    preeditButton.accessibilityValue = offersModes ? nil : title
    preeditButton.accessibilityTraits = offersModes ? .button : .staticText
  }

  func openLocalInputMode(_ trigger: String) {
    playInputClick()
    localModeTrigger = trigger
    showsSymbols = false
    render(session.openLocalMode(trigger))
  }

  private func chineseOutput(_ text: String) -> String {
    if inputScheme == .japanese || localModeTrigger == "R" { return text }
    return ChineseTextConversion.outputString(text, traditional: usesTraditionalOutput)
  }

  private func updateSchemeButton() {
    // The hints come from the engine's own profile for the scheme the session is running, so they
    // are refreshed wherever the scheme is, and cannot drift from what the keys actually produce.
    shuangpinKeyHints = session.shuangpinKeyHints()
    updateLetterCaseControls()

    var configuration = UIButton.Configuration.plain()
    switch inputScheme {
    case .nineKey: configuration.title = "九键"
    case .shuangpin: configuration.title = "小鹤"
    case .quanpin: configuration.title = "全拼"
    case .ziranma: configuration.title = "自然"
    case .microsoft: configuration.title = "微软"
    case .shoudao: configuration.title = "SD"
    case .wubi: configuration.title = "五笔"
    case .japanese: configuration.title = "日语"
    }
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.accent
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 3, leading: 4, bottom: 3, trailing: 4)
    configuration.background.strokeColor = KeyboardSkinPreference.selected.accent.withAlphaComponent(0.35)
    configuration.background.strokeWidth = 1
    configuration.background.cornerRadius = 8
    schemeButton.configuration = configuration
    schemeButton.accessibilityIdentifier = "schemeButton"
    schemeButton.accessibilityLabel = "选择输入方案"
    schemeButton.accessibilityValue = inputScheme.title
    schemeButton.menu = UIMenu(children: ChineseInputScheme.allCases.map { scheme in
      UIAction(title: scheme.title, state: scheme == inputScheme ? .on : .off) { [weak self] _ in
        self?.selectInputScheme(scheme)
      }
    })
    updateKeyboardLayout()
  }

  private func toggleLayout() {
    playInputClick()
    showsSymbols.toggle()
    updateKeyboardLayout()
  }

  private func updateKeyboardLayout() {
    standardRowHeights.forEach { $0.1.isActive = false }
    microsoftFinalKey?.isHidden = !(isChineseMode && inputScheme == .microsoft && !session.isInLocalMode)
    let nineKey = isChineseMode && inputScheme == .nineKey && !session.isInLocalMode
    letterRowViews.forEach { $0.isHidden = showsSymbols || nineKey }
    nineKeyContainer.isHidden = showsSymbols || !nineKey
    nineKeyRows.forEach { $0.isHidden = showsSymbols || !nineKey }
    let hasSpellings = !session.nineKeySpellings().isEmpty
    spellingScrollView.isHidden = !hasSpellings
    punctuationStack.isHidden = hasSpellings
    if actionRow != nil {
      let usesNineKeyLayout = nineKey && !showsSymbols
      nineKeyHeight.isActive = usesNineKeyLayout
      let globeIndex = usesNineKeyLayout ? 4 : 2
      if actionRow.arrangedSubviews.firstIndex(of: actionGlobeButton) != globeIndex {
        actionRow.removeArrangedSubview(actionGlobeButton)
        actionGlobeButton.removeFromSuperview()
        actionRow.insertArrangedSubview(actionGlobeButton, at: globeIndex)
      }
      NSLayoutConstraint.deactivate(standardActionWidths + nineKeyActionWidths)
      globeWidthConstraint?.isActive = false
      actionGlobeButton.isHidden = !needsInputModeSwitchKey
      if needsInputModeSwitchKey {
        globeWidthConstraint = actionGlobeButton.widthAnchor.constraint(equalToConstant: 44)
        globeWidthConstraint?.isActive = true
      }
      nineKeySymbolsButton.isHidden = !usesNineKeyLayout
      actionDeleteButton.isHidden = usesNineKeyLayout
      NSLayoutConstraint.activate(usesNineKeyLayout ? nineKeyActionWidths : standardActionWidths)
    }
    symbolRowViews.forEach { $0.isHidden = !showsSymbols }
    for (row, height) in standardRowHeights { height.isActive = !row.isHidden }
    if var configuration = layoutToggleButton?.configuration {
      configuration.title = showsSymbols ? (nineKey ? "九键" : "ABC") : "123"
      layoutToggleButton?.configuration = configuration
    }
    layoutToggleButton?.accessibilityLabel =
      showsSymbols ? "切换到字母" : "切换到数字和符号"
  }

  private func handleBackspace() {
    playInputClick()
    let snapshot = session.handleBackspace()
    if !snapshot.isHandled {
      deleteOwnBackward()
    }
    render(snapshot)
  }

  @objc private func beginBackspacePress() {
    cancelBackspacePress()
    didRepeatBackspace = false

    let timer = Timer(
      timeInterval: 0.075,
      target: self,
      selector: #selector(repeatBackspace),
      userInfo: nil,
      repeats: true)
    timer.fireDate = Date(timeIntervalSinceNow: 0.4)
    RunLoop.main.add(timer, forMode: .common)
    backspaceRepeatTimer = timer
  }

  @objc private func finishBackspacePress() {
    let repeated = didRepeatBackspace
    cancelBackspacePress()
    if !repeated {
      handleBackspace()
    }
  }

  @objc private func cancelBackspacePress() {
    backspaceRepeatTimer?.invalidate()
    backspaceRepeatTimer = nil
    didRepeatBackspace = false
  }

  @objc private func repeatBackspace() {
    didRepeatBackspace = true
    handleBackspace()
  }

  // Space means "commit the leading candidate", and that has to be the leading candidate the strip
  // is showing. commitCandidate always takes the engine's first, which on a later page is off
  // screen, so the page's own first chip is selected by index instead. On the first page the two
  // are the same candidate, and only commitCandidate reports itself unhandled when there is
  // nothing to commit, which is what tells the caller to insert its space. Return and the
  // language switch flush the whole composition through finishComposition instead.
  private func commitVisibleCandidate() -> MetasequoiaInputSnapshot {
    if candidatePageStart > 0, candidatePageStart < visibleCandidates.count {
      return session.selectCandidate(at: UInt(candidatePageStart))
    }
    return session.commitCandidate()
  }

  private func handleSpace() {
    playInputClick()
    let snapshot = commitVisibleCandidate()
    if !snapshot.isHandled {
      insertOwnText(" ")
    }
    render(snapshot)
  }

  // Gated the same way as handleSpace: a Return that commits a composition has done its job, and
  // the newline is only the key's own character. Inserting it unconditionally appended a stray
  // newline after every committed word, and in a field whose return key is 发送 or 完成 it also
  // fired that field's primary action. macOS swallows Return during a composition for this reason.
  private func handleReturn() {
    playInputClick()
    let snapshot = session.finishComposition()
    if !snapshot.isHandled {
      insertOwnText("\n")
    }
    render(snapshot)
  }

  @objc private func handleInputModeButton(_ sender: UIButton, event: UIEvent) {
    if event.allTouches?.contains(where: { touch in touch.phase == .began }) == true {
      render(session.commitRaw())
    }
    handleInputModeList(from: sender, with: event)
  }

  // Every document mutation the keyboard makes goes through here so textWillChange can tell its own
  // echo apart from a genuine host-initiated change.
  private var typingSource: TypingSource {
    if localModeTrigger == "R" { return .japanese }
    if localModeTrigger != nil { return .local }
    if !isChineseMode { return .english }
    return TypingSource(rawValue: inputScheme.rawValue) ?? .unknown
  }

  private func insertOwnText(_ text: String, source: TypingSource? = nil) {
    pendingOwnEdits += 1
    textDocumentProxy.insertText(text)
    if hasFullAccess { try? TypingStatisticsStore().record(text, source: source ?? typingSource) }
  }

  private func deleteOwnBackward() {
    pendingOwnEdits += 1
    textDocumentProxy.deleteBackward()
  }

  private func render(_ snapshot: MetasequoiaInputSnapshot, source originalSource: TypingSource? = nil) {
    candidateRevision &+= 1
    let source = originalSource ?? typingSource
    if localModeTrigger != nil && !session.isInLocalMode {
      localModeTrigger = nil
      showsSymbols = false
    }
    updateLetterCaseControls()
    if let commitText = snapshot.commitText {
      insertOwnText(source == .japanese ? commitText : chineseOutput(commitText), source: source)
    }
    hasComposition = !snapshot.preedit.isEmpty
    showDiagnostic(snapshot.diagnosticText)
    updateCandidateStrip(preedit: snapshot.preedit, candidates: snapshot.candidates)
    updateSpellingStrip()
  }

  // A diagnostic means the key was handled but something behind it failed, so input keeps working
  // and the message is transient. It replaces the candidate strip, which is empty in exactly the
  // cases that produce one, and clears itself on the next key or after a few seconds.
  private func showDiagnostic(_ diagnostic: String?) {
    diagnosticDismissTimer?.invalidate()
    diagnosticDismissTimer = nil
    visibleDiagnostic = diagnostic
    guard diagnostic != nil else { return }

    let timer = Timer(timeInterval: 4, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.visibleDiagnostic = nil
        self.diagnosticDismissTimer = nil
        self.renderCandidateStrip()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    diagnosticDismissTimer = timer
  }

  private func updateCandidateStrip(preedit: String, candidates: [String]) {
    visiblePreedit = preedit
    visibleCandidates = candidates
    // Any new candidate list is a different composition or a different set of matches, so the page
    // it was showing no longer describes anything.
    candidatePageStart = 0
    renderCandidateStrip()
  }

  private func renderCandidateStrip() {
    exitLocalModeButton.isHidden = !session.isInLocalMode
    let showsCandidates = session.isInLocalMode || !visiblePreedit.isEmpty || !visibleCandidates.isEmpty || visibleDiagnostic != nil
    shortcutBar.isHidden = showsCandidates
    candidateContent?.isHidden = !showsCandidates
    updatePreeditButton()
    for view in candidateStack.arrangedSubviews {
      candidateStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    let page = visibleCandidates.dropFirst(candidatePageStart).prefix(Self.candidatePageSize)
    for (offset, candidate) in page.enumerated() {
      candidateStack.addArrangedSubview(
        makeCandidateButton(
          candidate: candidate, number: offset + 1, index: candidatePageStart + offset))
    }
    updatePageControls()

    diagnosticLabel.text = visibleDiagnostic
    diagnosticLabel.accessibilityLabel = visibleDiagnostic.map { "提示：\($0)" }
    diagnosticLabel.isHidden = visibleDiagnostic == nil
    candidateScrollView.isHidden = visibleCandidates.isEmpty || visibleDiagnostic != nil
    candidateEmptySpacer.isHidden = !visibleCandidates.isEmpty || visibleDiagnostic != nil
  }

  // The number is the key the chip answers to on the visible page; the index is the engine position
  // it selects. They only coincide on the first page.
  private func makeCandidateButton(candidate: String, number: Int, index: Int) -> UIButton {
    let display = chineseOutput(candidate)
    var configuration = UIButton.Configuration.plain()
    configuration.title = "\(number)  \(display)"
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.keyForeground
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 4, leading: 9, bottom: 4, trailing: 9)
    configuration.background.backgroundColor = KeyboardSkinPreference.selected.keyBackground
    configuration.background.strokeColor = KeyboardSkinPreference.selected.accent.withAlphaComponent(0.22)
    configuration.background.strokeWidth = 1
    configuration.background.cornerRadius = 9

    let button = KeyboardKeyButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        self.playInputClick()
        self.render(self.session.selectCandidate(at: UInt(index)))
      })
    button.accessibilityLabel = "候选词 \(number)：\(display)"
    button.accessibilityIdentifier = "candidate-\(number)"
    if isChineseMode && inputScheme != .nineKey && inputScheme != .japanese && !session.isInLocalMode {
      let revision = candidateRevision
      func action(_ title: String, _ symbol: String, _ operation: MetasequoiaCandidateAction,
                  destructive: Bool = false) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: symbol), attributes: destructive ? .destructive : []) { [weak self] _ in
          guard let self, candidateRevision == revision,
                visibleCandidates.indices.contains(index), visibleCandidates[index] == candidate else { return }
          let result = session.editCandidate(at: UInt(index), expectedWord: candidate, action: operation)
          render(result)
          if !result.isHandled { showDiagnostic("当前候选不支持此操作") }
          else if result.diagnosticText == nil {
            playInputClick()
            UIAccessibility.post(notification: .announcement, argument: "已\(title)")
          }
        }
      }
      button.menu = UIMenu(title: display, children: [
        action("优先显示", "arrow.up", .promote),
        action("固定到首位", "pin", .fixFirst),
        action("取消固定", "pin.slash", .clearPosition),
        UIMenu(title: "删除词条…", image: UIImage(systemName: "trash"), options: .destructive, children: [
          action("确认删除此词条", "trash", .remove, destructive: true),
        ]),
      ])
      button.accessibilityHint = "轻点输入，长按管理词条"
    }
    decorateKey(button)
    return button
  }

  private func makeSymbolKey(
    symbol: String, accessibilityLabel: String, action: (() -> Void)? = nil
  ) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: symbol)
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.keyForeground
    configuration.background.backgroundColor = KeyboardSkinPreference.selected.keyBackground
    configuration.background.cornerRadius = 8
    let button = KeyboardKeyButton(configuration: configuration)
    if let action {
      button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
    }
    button.accessibilityLabel = accessibilityLabel
    decorateKey(button)
    return button
  }

  private func makeKey(
    title: String,
    accessibilityLabel: String,
    emphasized: Bool = false,
    action: @escaping () -> Void
  ) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.titleLineBreakMode = .byClipping
    configuration.baseForegroundColor = emphasized ? .white : KeyboardSkinPreference.selected.keyForeground
    configuration.background.backgroundColor =
      emphasized
      ? KeyboardSkinPreference.selected.actionBackground
      : KeyboardSkinPreference.selected.keyBackground
    configuration.background.cornerRadius = 8
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      attributes in
      var attributes = attributes
      attributes.font = KeyboardSkinPreference.selected.usesMonospacedFont
        ? .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .medium)
        : .preferredFont(forTextStyle: .title3)
      return attributes
    }
    let button = KeyboardKeyButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.accessibilityLabel = accessibilityLabel
    decorateKey(button)
    return button
  }

  private func decorateKey(_ button: UIButton) {
    button.addTarget(self, action: #selector(prepareKeyFeedback), for: .touchDown)
    let skin = KeyboardSkinPreference.selected
    guard var configuration = button.configuration else { return }
    configuration.background.cornerRadius = skin.cornerRadius
    configuration.background.strokeWidth = skin.borderWidth
    configuration.background.strokeColor = skin.borderColor
    button.configuration = configuration
    button.layer.shadowColor = UIColor.black.cgColor
    button.layer.shadowOpacity = skin.shadowOpacity
    button.layer.shadowRadius = skin.shadowRadius
    button.layer.shadowOffset = CGSize(width: 0, height: skin.shadowOffset)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let globe = actionGlobeButton, globe.isHidden != !needsInputModeSwitchKey {
      updateKeyboardLayout()
    }
    // Use the same viewport for every input layout; content's intrinsic height must not shrink it.
    let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape
      ?? (traitCollection.verticalSizeClass == .compact)
    let height: CGFloat = landscape ? 216 : 260
    if keyboardHeightConstraint?.constant != height { keyboardHeightConstraint?.constant = height }
    func updateShadows(_ node: UIView) {
      if let button = node as? UIButton, button.layer.shadowOpacity > 0 {
        button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds,
          cornerRadius: KeyboardSkinPreference.selected.cornerRadius).cgPath
      }
      node.subviews.forEach { updateShadows($0) }
    }
    updateShadows(view)
  }

  private func showSkinPicker() {
    guard skinPicker == nil else { return }
    let picker = KeyboardSkinPickerView(selected: KeyboardSkinPreference.selected, onSelect: { [weak self] skin in
      guard let self else { return }
      KeyboardFeedbackPreference.defaults.set(skin.rawValue, forKey: KeyboardSkinPreference.key)
      closeSkinPicker()
      applyKeyboardSkin()
      playInputClick()
    }, onClose: { [weak self] in self?.closeSkinPicker() })
    picker.accessibilityViewIsModal = true
    picker.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      picker.topAnchor.constraint(equalTo: view.topAnchor),
      picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    skinPicker = picker
    UIAccessibility.post(notification: .screenChanged, argument: picker)
  }

  private func closeSkinPicker() {
    guard let picker = skinPicker else { return }
    picker.removeFromSuperview()
    skinPicker = nil
    UIAccessibility.post(notification: .screenChanged, argument: skinShortcut)
  }

  private func applyKeyboardSkin() {
    let skin = KeyboardSkinPreference.selected
    view.backgroundColor = skin.background
    skinBackdrop.skin = skin
    func recolor(_ node: UIView) {
      if let button = node as? UIButton, var configuration = button.configuration {
        if let color = configuration.background.backgroundColor, color.cgColor.alpha > 0 {
          configuration.background.backgroundColor = skin.keyBackground
          configuration.baseForegroundColor = skin.keyForeground
        }
        if configuration.background.strokeWidth > 0 {
          configuration.background.strokeColor = skin.accent.withAlphaComponent(0.3)
        }
        button.configuration = configuration
        if let color = configuration.background.backgroundColor, color.cgColor.alpha > 0 { decorateKey(button) }
      }
      if node.accessibilityIdentifier == "nineKeySidebar" || node.accessibilityIdentifier == "candidateStrip" {
        node.backgroundColor = skin.keyBackground.withAlphaComponent(0.6)
      }
      if let label = node as? UILabel, label.accessibilityIdentifier == "keyNumberHint" { label.textColor = skin.accent }
      node.subviews.forEach { recolor($0) }
    }
    recolor(view)
    if var configuration = enterButton?.configuration {
      configuration.background.backgroundColor = skin.actionBackground
      configuration.baseForegroundColor = skin.actionForeground
      enterButton?.configuration = configuration
    }
    updateLanguageModeButton()
    updateSchemeButton()
    updateShortcutButtons()
    renderCandidateStrip()
    updateSpellingStrip()
    exitLocalModeButton.configuration?.baseForegroundColor = skin.accent
    preeditButton.configuration?.baseForegroundColor = skin.accent
    previousPageButton.configuration?.baseForegroundColor = skin.accent
    nextPageButton.configuration?.baseForegroundColor = skin.accent
    for (_, _, hint) in letterButtons { hint.textColor = skin.accent }
    view.tintColor = skin.accent
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if isViewLoaded, actionRow != nil,
       previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
      applyKeyboardSkin()
    }
  }

  @objc private func prepareKeyFeedback() {
    if KeyboardFeedbackPreference.hapticsEnabled { keyFeedback.prepare() }
  }

  private func playInputClick() {
    if KeyboardFeedbackPreference.soundEnabled {
      UIDevice.current.playInputClick()
    }
    if KeyboardFeedbackPreference.hapticsEnabled {
      keyFeedback.impactOccurred(intensity: 1.0)
      keyFeedback.prepare()
    }
  }
}
