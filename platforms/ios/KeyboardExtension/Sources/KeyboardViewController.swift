import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
  private enum LetterCaseState {
    case lowercase, shifted, capsLock
  }

  private let session = MetasequoiaInputSessionBridge()
  private let preeditButton = UIButton()
  private let candidateScrollView = UIScrollView()
  private let diagnosticLabel = UILabel()
  private let previousPageButton = UIButton()
  private let nextPageButton = UIButton()
  private let candidateStack = UIStackView()
  private let languageModeButton = UIButton()
  private let schemeButton = UIButton()
  private var letterButtons: [(button: UIButton, lowercase: String, hint: UILabel)] = []
  private var letterRowViews: [UIView] = []
  private var symbolRowViews: [UIView] = []
  private var layoutToggleButton: UIButton?
  private weak var shiftButton: UIButton?
  private weak var enterButton: UIButton?
  private var backspaceRepeatTimer: Timer?
  private var didRepeatBackspace = false
  private var hasComposition = false
  private var isChineseMode = true
  private var usesShuangpin = false
  private var usesTraditionalOutput = false
  private var visiblePreedit = ""
  private var visibleCandidates: [String] = []
  private var visibleDiagnostic: String?
  private var diagnosticDismissTimer: Timer?
  private var shuangpinKeyHints: [String: String] = [:]
  private var candidatePageStart = 0
  private var showsSymbols = false
  private var letterCaseState = LetterCaseState.lowercase
  private var isAutomaticShift = false
  private var lastShiftTapTime: TimeInterval?

  // The strip numbers its chips 1-9 to match the digits on the symbol layer, so a page is nine.
  private static let candidatePageSize = 9

  var enableInputClicksWhenVisible: Bool { true }

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

  override func viewDidLoad() {
    super.viewDidLoad()
    usesShuangpin = InputSchemePreference.usesShuangpin
    usesTraditionalOutput = ChineseOutputPreference.usesTraditional
    if usesShuangpin {
      _ = session.switch(toShuangpin: true)
    }
    view.backgroundColor = MetasequoiaTheme.keyboardBackground
    installKeyboard()
    updateReturnKey()
    // installKeyboard builds the candidate strip before the letter rows exist, so the hints the
    // scheme button gathered there have not reached any key yet.
    updateLetterCaseControls()
    updateCandidateStrip(preedit: "", candidates: [])
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    synchronizeInputSchemePreference()
    synchronizeChineseOutputPreference()
  }

  override func textWillChange(_ textInput: UITextInput?) {
    super.textWillChange(textInput)
    render(session.cancel())
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    updateReturnKey()
    updateAutomaticCapitalization()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
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
    for (index, row) in letterRows.enumerated() {
      let rowView = makeLetterRow(row, includesShift: index == letterRows.count - 1)
      letterRowViews.append(rowView)
      root.addArrangedSubview(rowView)
    }
    for row in symbolRows {
      let rowView = makeSymbolRow(row)
      rowView.isHidden = true
      symbolRowViews.append(rowView)
      root.addArrangedSubview(rowView)
    }
    root.addArrangedSubview(makeActionRow())
  }

  private func makeCandidateStrip() -> UIView {
    let container = UIView()
    container.backgroundColor = MetasequoiaTheme.keyBackground.withAlphaComponent(0.82)
    container.layer.cornerRadius = 12

    var preeditConfiguration = UIButton.Configuration.plain()
    preeditConfiguration.contentInsets = .zero
    preeditConfiguration.baseForegroundColor = MetasequoiaTheme.forestUIColor
    preeditConfiguration.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = .preferredFont(forTextStyle: .subheadline)
        return attributes
      }
    preeditButton.configuration = preeditConfiguration
    preeditButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    preeditButton.showsMenuAsPrimaryAction = true
    preeditButton.accessibilityIdentifier = "preeditButton"

    updateLanguageModeButton()
    languageModeButton.addAction(
      UIAction { [weak self] _ in self?.toggleInputMode() }, for: .primaryActionTriggered)
    languageModeButton.widthAnchor.constraint(equalToConstant: 36).isActive = true

    updateSchemeButton()
    schemeButton.addAction(
      UIAction { [weak self] _ in self?.toggleScheme() }, for: .primaryActionTriggered)
    schemeButton.widthAnchor.constraint(equalToConstant: 48).isActive = true

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
      languageModeButton, schemeButton, preeditButton, candidateScrollView, diagnosticLabel,
      previousPageButton, nextPageButton,
    ])
    content.axis = .horizontal
    content.alignment = .center
    content.spacing = 12
    content.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(content)

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

  private func makeLetterRow(_ letters: [Character], includesShift: Bool) -> UIStackView {
    let row = makeRow()
    if includesShift {
      let button = makeSymbolKey(symbol: "shift", accessibilityLabel: "大写") { [weak self] in
        self?.toggleLetterCase()
      }
      button.accessibilityIdentifier = "shiftButton"
      button.isHidden = isChineseMode
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
    return row
  }

  // A key is about 36pt wide and the longest Xiaohe mapping is nine characters, so the hint has to
  // be one line that shrinks rather than a subtitle that wraps: wrapping pushed the letter itself
  // out of the top of the key.
  private func attachHintLabel(to button: UIButton) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: 9, weight: .regular)
    label.textColor = MetasequoiaTheme.forestUIColor.withAlphaComponent(0.8)
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
    layoutToggleButton = layoutToggle
    row.addArrangedSubview(layoutToggle)

    let globe = makeSymbolKey(symbol: "globe", accessibilityLabel: "选择下一个键盘")
    globe.addTarget(
      self, action: #selector(handleInputModeButton(_:event:)), for: .allTouchEvents)
    row.addArrangedSubview(globe)

    let delete = makeSymbolKey(symbol: "delete.left", accessibilityLabel: "删除")
    delete.addTarget(self, action: #selector(beginBackspacePress), for: .touchDown)
    delete.addTarget(self, action: #selector(finishBackspacePress), for: .touchUpInside)
    delete.addTarget(
      self,
      action: #selector(cancelBackspacePress),
      for: [.touchUpOutside, .touchCancel, .touchDragExit])
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

    NSLayoutConstraint.activate([
      layoutToggle.widthAnchor.constraint(equalTo: globe.widthAnchor, multiplier: 1.1),
      delete.widthAnchor.constraint(equalTo: globe.widthAnchor),
      space.widthAnchor.constraint(equalTo: globe.widthAnchor, multiplier: 1.8),
      enter.widthAnchor.constraint(equalTo: globe.widthAnchor, multiplier: 1.35),
      globe.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    return row
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
      render(session.handleCharacter(character))
    } else {
      let output = letterCaseState == .lowercase ? character : character.uppercased()
      textDocumentProxy.insertText(output)
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
      textDocumentProxy.insertText(symbol)
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
        textDocumentProxy.insertText(symbol)
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

    render(session.commitRaw())
    textDocumentProxy.insertText(symbol)
  }

  private func toggleInputMode() {
    playInputClick()
    let snapshot = isChineseMode ? session.finishComposition() : session.cancel()
    isChineseMode.toggle()
    letterCaseState = .lowercase
    isAutomaticShift = false
    lastShiftTapTime = nil
    updateLanguageModeButton()
    updateAutomaticCapitalization()
    render(snapshot)
  }

  private func toggleLetterCase() {
    guard !isChineseMode else { return }

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
      let hint = isChineseMode ? shuangpinKeyHints[lowercase.uppercased()] : nil
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

    shiftButton?.isHidden = isChineseMode
    guard let button = shiftButton, var configuration = button.configuration else { return }
    switch letterCaseState {
    case .lowercase:
      configuration.image = UIImage(systemName: "shift")
      configuration.background.backgroundColor = MetasequoiaTheme.keyBackground
      button.accessibilityLabel = "大写"
      button.accessibilityValue = "关闭"
    case .shifted:
      configuration.image = UIImage(systemName: "shift.fill")
      configuration.background.backgroundColor =
        MetasequoiaTheme.forestUIColor.withAlphaComponent(0.22)
      button.accessibilityLabel = "大写"
      button.accessibilityValue = isAutomaticShift ? "自动开启" : "下一字母"
    case .capsLock:
      configuration.image = UIImage(systemName: "capslock.fill")
      configuration.background.backgroundColor =
        MetasequoiaTheme.forestUIColor.withAlphaComponent(0.32)
      button.accessibilityLabel = "大写锁定"
      button.accessibilityValue = "开启"
    }
    button.configuration = configuration
  }

  private func updateLanguageModeButton() {
    var configuration = UIButton.Configuration.filled()
    configuration.title = isChineseMode ? "中" : "英"
    configuration.baseForegroundColor = .white
    configuration.baseBackgroundColor = MetasequoiaTheme.forestUIColor
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 3, leading: 5, bottom: 3, trailing: 5)
    configuration.background.cornerRadius = 8
    languageModeButton.configuration = configuration
    languageModeButton.accessibilityIdentifier = "languageModeButton"
    languageModeButton.accessibilityLabel =
      isChineseMode ? "切换到英文输入" : "切换到中文输入"
    languageModeButton.accessibilityValue = isChineseMode ? "中文输入" : "英文输入"
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

  private func toggleScheme() {
    playInputClick()
    usesShuangpin.toggle()
    let snapshot = session.switch(toShuangpin: usesShuangpin)
    InputSchemePreference.usesShuangpin = usesShuangpin
    updateSchemeButton()
    render(snapshot)
  }

  private func synchronizeInputSchemePreference() {
    guard !hasComposition else { return }
    let sharedValue = InputSchemePreference.usesShuangpin
    guard sharedValue != usesShuangpin else { return }

    usesShuangpin = sharedValue
    let snapshot = session.switch(toShuangpin: usesShuangpin)
    updateSchemeButton()
    render(snapshot)
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
    configuration.baseForegroundColor = MetasequoiaTheme.forestUIColor
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
  ]

  private func updatePreeditButton() {
    let idle = visiblePreedit.isEmpty
    let title = idle ? (isChineseMode ? "水杉输入法" : "英文输入") : visiblePreedit
    if var configuration = preeditButton.configuration {
      configuration.title = title
      preeditButton.configuration = configuration
    }

    let offersModes = idle && isChineseMode
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

  private func openLocalInputMode(_ trigger: String) {
    playInputClick()
    render(session.openLocalMode(trigger))
  }

  private func chineseOutput(_ text: String) -> String {
    ChineseTextConversion.outputString(text, traditional: usesTraditionalOutput)
  }

  private func updateSchemeButton() {
    // The hints come from the engine's own profile for the scheme the session is running, so they
    // are refreshed wherever the scheme is, and cannot drift from what the keys actually produce.
    shuangpinKeyHints = session.shuangpinKeyHints()
    updateLetterCaseControls()

    var configuration = UIButton.Configuration.plain()
    configuration.title = usesShuangpin ? "小鹤" : "全拼"
    configuration.baseForegroundColor = MetasequoiaTheme.forestUIColor
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 3, leading: 4, bottom: 3, trailing: 4)
    configuration.background.strokeColor = MetasequoiaTheme.forestUIColor.withAlphaComponent(0.35)
    configuration.background.strokeWidth = 1
    configuration.background.cornerRadius = 8
    schemeButton.configuration = configuration
    schemeButton.accessibilityIdentifier = "schemeButton"
    schemeButton.accessibilityLabel = usesShuangpin ? "切换到全拼" : "切换到小鹤双拼"
    schemeButton.accessibilityValue = usesShuangpin ? "小鹤双拼" : "全拼"
  }

  private func toggleLayout() {
    playInputClick()
    showsSymbols.toggle()
    letterRowViews.forEach { $0.isHidden = showsSymbols }
    symbolRowViews.forEach { $0.isHidden = !showsSymbols }
    if var configuration = layoutToggleButton?.configuration {
      configuration.title = showsSymbols ? "ABC" : "123"
      layoutToggleButton?.configuration = configuration
    }
    layoutToggleButton?.accessibilityLabel =
      showsSymbols ? "切换到字母" : "切换到数字和符号"
  }

  private func handleBackspace() {
    playInputClick()
    let snapshot = session.handleBackspace()
    if !snapshot.isHandled {
      textDocumentProxy.deleteBackward()
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
      textDocumentProxy.insertText(" ")
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
      textDocumentProxy.insertText("\n")
    }
    render(snapshot)
  }

  @objc private func handleInputModeButton(_ sender: UIButton, event: UIEvent) {
    if event.allTouches?.contains(where: { touch in touch.phase == .began }) == true {
      render(session.commitRaw())
    }
    handleInputModeList(from: sender, with: event)
  }

  private func render(_ snapshot: MetasequoiaInputSnapshot) {
    if let commitText = snapshot.commitText {
      textDocumentProxy.insertText(chineseOutput(commitText))
    }
    hasComposition = !snapshot.preedit.isEmpty
    showDiagnostic(snapshot.diagnosticText)
    updateCandidateStrip(preedit: snapshot.preedit, candidates: snapshot.candidates)
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
  }

  // The number is the key the chip answers to on the visible page; the index is the engine position
  // it selects. They only coincide on the first page.
  private func makeCandidateButton(candidate: String, number: Int, index: Int) -> UIButton {
    let display = chineseOutput(candidate)
    var configuration = UIButton.Configuration.plain()
    configuration.title = "\(number)  \(display)"
    configuration.baseForegroundColor = .label
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 4, leading: 9, bottom: 4, trailing: 9)
    configuration.background.backgroundColor = MetasequoiaTheme.keyBackground
    configuration.background.strokeColor = MetasequoiaTheme.forestUIColor.withAlphaComponent(0.22)
    configuration.background.strokeWidth = 1
    configuration.background.cornerRadius = 9

    let button = UIButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        self.playInputClick()
        self.render(self.session.selectCandidate(at: UInt(index)))
      })
    button.accessibilityLabel = "候选词 \(number)：\(display)"
    button.accessibilityIdentifier = "candidate-\(number)"
    return button
  }

  private func makeSymbolKey(
    symbol: String, accessibilityLabel: String, action: (() -> Void)? = nil
  ) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: symbol)
    configuration.baseForegroundColor = .label
    configuration.background.backgroundColor = MetasequoiaTheme.keyBackground
    configuration.background.cornerRadius = 8
    let button = UIButton(configuration: configuration)
    if let action {
      button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
    }
    button.accessibilityLabel = accessibilityLabel
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
    configuration.baseForegroundColor = emphasized ? .white : .label
    configuration.background.backgroundColor =
      emphasized
      ? UIColor(red: 167 / 255, green: 103 / 255, blue: 59 / 255, alpha: 1)
      : MetasequoiaTheme.keyBackground
    configuration.background.cornerRadius = 8
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .title3)
      return attributes
    }
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.accessibilityLabel = accessibilityLabel
    return button
  }

  private func playInputClick() {
    UIDevice.current.playInputClick()
  }
}
