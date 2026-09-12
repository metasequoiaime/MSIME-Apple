import SwiftUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
  private enum LetterCaseState {
    case lowercase, shifted, capsLock
  }

  private let skinBackdrop = KeyboardSkinBackgroundView()
  private var keyboardRoot: UIStackView?
  private var nineGrid: UIStackView?
  private var nineControls: UIStackView?
  private var nineSidebarWidth: NSLayoutConstraint?
  private var fullSymbolsWidth: NSLayoutConstraint?
  private var bottomLanguageWidth: NSLayoutConstraint?
  private var bottomLanguageButton: UIButton?
  private var appliedLayout: KeyboardGeometry?

  private var keyboardHeightConstraint: NSLayoutConstraint?
  private let session = MetasequoiaInputSessionBridge()
  private lazy var snapshotWorker: DictionarySnapshotWorker = {
    let worker = DictionarySnapshotWorker(session: session)
    worker.report = { [weak self] in self?.showDiagnostic($0) }
    worker.applied = { [weak self] in self?.synchronizePersonalDictionary(force: true) }
    return worker
  }()
  private var servicePanel: UIViewController?
  private var replyPanel: UIHostingController<ReplyKeyboardView>?
  private let replyModel = ReplyKeyboardModel()
  private var personalDictionaryTimer: Timer?
  private var synchronizingPersonalDictionary = false
  private let preeditButton = UIButton()
  private let exitLocalModeButton = UIButton()
  private var localModeTrigger: String?
  private var standardRowHeights: [(UIView, NSLayoutConstraint)] = []
  private let candidateScrollView = CandidateScrollView()
  private let diagnosticLabel = UILabel()
  private let expandCandidatesButton = UIButton()
  private let candidateStack = UIStackView()
  private let candidateEmptySpacer = UIView()
  private let schemeButton = UIButton()
  private let shortcutBar = UIStackView()
  private var candidateContent: UIStackView?
  private let scriptShortcut = UIButton()
  private let skinShortcut = UIButton()
  private let emojiShortcut = UIButton()
  private let layoutShortcut = UIButton()
  private var clipboardPanel: KeyboardClipboardView?
  private var skinPicker: KeyboardSkinPickerView?
  private var schemePicker: KeyboardSchemePickerView?
  private let moreShortcut = UIButton()
  private var morePicker: KeyboardMorePickerView?
  private let handwriting = HandwritingInputView()
  private var handwritingActionHeight: NSLayoutConstraint?
  private var layoutPicker: KeyboardLayoutPickerView?
  private var candidatePanel: KeyboardCandidatePanelView?
  private var emojiPicker: KeyboardEmojiPickerView?
  private var nineKeyHoldPopup: UIView?
  // 九键网格的按键。按 123 时同一批键改显数字,而不是换成 26 键那排符号。
  private struct NineKeyGridKey {
    let button: UIButton
    let digit: Int
    let letters: String?
    let numberHint: UILabel?
  }
  private var nineKeyGridKeys: [NineKeyGridKey] = []
  private var moreMenu: UIMenu?
  private let dismissShortcut = UIButton()
  private var letterButtons: [(button: UIButton, lowercase: String, hint: UILabel)] = []
  private var microsoftFinalKey: UIButton?
  private var letterRowViews: [UIView] = []
  private var symbolRowViews: [UIView] = []
  // 有中文对应标点的符号键,随中英模式换脸。
  private var symbolKeyFaces: [(key: UIButton, ascii: String, chinese: String)] = []
  private var layoutToggleButton: UIButton?
  private weak var shiftButton: UIButton?
  private weak var enterButton: UIButton?
  private weak var spaceButton: UIButton?
  private var cursorMovement = SpaceCursorMovement()
  private var backspaceRepeatTimer: Timer?
  private var didRepeatBackspace = false
  private var hasComposition = false
  private var isChineseMode = true
  private var inputContext = KeyboardInputContext()
  private var inputScheme: ChineseInputScheme = .quanpin
  private var usesShuangpin: Bool { inputScheme.shuangpinProfile != nil }
  private var supportsLocalTools: Bool { isChineseMode && inputScheme != .wubi && !inputScheme.isJapanese }
  private var nineKeyRows: [UIView] = []
  private var actionRow: UIStackView!
  private var actionDeleteButton: UIButton!
  private var actionGlobeButton: UIButton!
  private var globeWidthConstraint: NSLayoutConstraint?
  private var japaneseKeys: JapaneseNineKeyView!
  private var japaneseHeight: NSLayoutConstraint!
  private var nineKeyHeight: NSLayoutConstraint!
  private var nineKeySymbolsButton: UIButton!
  private let punctuationStack = UIStackView()
  private var quickPunctuationButton: UIButton!
  private var quickPunctuationWidth: NSLayoutConstraint?
  private var symbolDeleteWidth: NSLayoutConstraint?
  private var standardActionWidths: [NSLayoutConstraint] = []
  private var nineKeyActionWidths: [NSLayoutConstraint] = []
  private let nineKeyContainer = UIStackView()
  private let spellingScrollView = UIScrollView()
  private let spellingStack = UIStackView()
  private var usesTraditionalOutput = false
  private var replyPanelSuppressed = false
  private var reportedStatisticsFailure = false
  private var visiblePreedit = ""
  private var candidateRevision: UInt64 = 0
  private var visibleCandidates: [String] = []
  // The code each visible candidate was found by, parallel to visibleCandidates.
  private var visibleCandidateCodes: [String] = []
  private var visibleDiagnostic: String?
  private var diagnosticDismissTimer: Timer?
  private var shuangpinKeyHints: [String: String] = [:]
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
  // Not private: the expansion test asserts the panel reaches past what the strip shows.
  static let candidatePageSize = 9
  // The composition sits on its own line above the candidates. Both rows are reserved whether or
  // not anything is being composed, so no row appears or disappears mid-typing.
  // Not private: the height assertions derive from it rather than restating the sum.
  static let compositionRowHeight: CGFloat = 32
  private static let candidateStripHeight: CGFloat = compositionRowHeight + 38

  private var feedbackStrength: KeyboardHapticStrength?
  private var feedbackGenerator: UIImpactFeedbackGenerator?
  private var keyFeedback: UIImpactFeedbackGenerator {
    let strength = KeyboardFeedbackPreference.hapticStrength
    if let feedbackGenerator, feedbackStrength == strength { return feedbackGenerator }
    let generator: UIImpactFeedbackGenerator
    if #available(iOS 17.5, *) {
      if let feedbackGenerator { view.removeInteraction(feedbackGenerator) }
      generator = UIImpactFeedbackGenerator(style: strength.style, view: view)
    } else {
      generator = UIImpactFeedbackGenerator(style: strength.style)
    }
    feedbackStrength = strength
    feedbackGenerator = generator
    return generator
  }

  private let letterRows = [
    Array("qwertyuiop"),
    Array("asdfghjkl"),
    Array("zxcvbnm"),
  ]
  private let symbolRows = [
    Array("1234567890").map(String.init),
    [",", ".", "?", "!", ";", ":", "'", "\"", "@", "/"],
    ["(", ")", "[", "]", "<", ">", "\\", "-", "_", "="],
  ]

  /// 中文输入时这些键实际送出的标点,取自 Engine 的标点契约。
  ///
  /// The keys are labelled with the ASCII that produces them, so nothing on the keyboard says that
  /// a backslash is how you type a 、 -- which is what people ask. Showing what the key will
  /// actually produce answers it without spending a second key on it. Pairs show their opening
  /// half; the engine alternates on its own. Characters the contract leaves out, @ / - =, keep
  /// their own face because that is what they insert.
  /// ReleaseConfigurationTests holds this to the contract these values were read from.
  static let chineseSymbolFaces: [String: String] = [
    ",": "，", ".": "。", "?": "？", "!": "！", ";": "；", ":": "：",
    "(": "（", ")": "）", "[": "【", "]": "】", "\\": "、",
    "<": "《", ">": "》", "'": "‘", "\"": "“", "_": "——",
  ]

  override func loadView() {
    inputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    inputScheme = InputSchemePreference.scheme
    usesTraditionalOutput = ChineseOutputPreference.usesTraditional
    _ = applyInputScheme()
    applyLearningPreferences()
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
    // Start at the height the setting asks for. updatePreferredKeyboardHeight settles it once the
    // orientation is known; starting at the stock value would show one height and then jump.
    let height = view.heightAnchor.constraint(
      equalToConstant: 260 + Self.compositionRowHeight
        + CGFloat(KeyboardLayoutPreference.heightAdjustment))
    height.priority = .init(999)
    height.identifier = "keyboardHeight"
    height.isActive = true
    keyboardHeightConstraint = height
    updatePreferredKeyboardHeight()
    updateReturnKey()
    // installKeyboard builds the candidate strip before the letter rows exist, so the hints the
    // scheme button gathered there have not reached any key yet.
    updateLetterCaseControls()
    updateCandidateStrip(preedit: "", candidates: [])
    applyKeyboardSkin()
    synchronizeInputContext()
    synchronizeReplyKeyboard()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    synchronizeInputContext()
    prepareKeyFeedback()
    synchronizePersonalDictionary(force: true)
    snapshotWorker.tick(idle: !hasComposition && !session.isInLocalMode, fullAccess: hasFullAccess, force: true)
    personalDictionaryTimer?.invalidate()
    personalDictionaryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.synchronizePersonalDictionary(force: false)
        self.snapshotWorker.tick(idle: !self.hasComposition && !self.session.isInLocalMode, fullAccess: self.hasFullAccess)
      }
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    do { try session.resumeDictionarySession() }
    catch { showDiagnostic(error.localizedDescription) }
    // A fresh editing session owes us no callbacks. Clearing the count here bounds the damage if
    // UIKit ever skips the delegate pair for one of our own edits: the worst case is that a single
    // host-initiated change is treated as an echo, not a counter that stays raised forever.
    pendingOwnEdits = 0
    if schemePicker != nil { closeKeyboardPicker() }
    synchronizeInputContext()
    synchronizeInputSchemePreference()
    synchronizeChineseOutputPreference()
    applyLearningPreferences()
    applyKeyboardSkin()
    synchronizeReplyKeyboard()
  }

  override func selectionWillChange(_ textInput: UITextInput?) {
    super.selectionWillChange(textInput)
    replyModel.invalidateContext()
    handwriting.clear()
    closeKeyboardService()
  }

  override func textWillChange(_ textInput: UITextInput?) {
    super.textWillChange(textInput)
    replyModel.invalidateContext()
    handwriting.clear()
    closeKeyboardService()
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
    synchronizeInputContext()
    updateReturnKey()
    updateAutomaticCapitalization()
    synchronizeReplyKeyboard()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    replyModel.setText("")
    handwriting.deactivate()
    snapshotWorker.stop()
    closeKeyboardService()
    personalDictionaryTimer?.invalidate()
    personalDictionaryTimer = nil
    closeKeyboardPicker()
    cursorMovement.cancel()
    spaceButton?.configuration?.title = "空格"
    // Putting the keyboard away used to drop whatever was composed. macOS commits in
    // prepareForDeactivation: for the same reason: the user typed those letters and never asked to
    // throw them away.
    render(session.finishComposition())
    _ = session.suspendDictionarySession()
    pendingOwnEdits = 0
    cancelBackspacePress()
    diagnosticDismissTimer?.invalidate()
    diagnosticDismissTimer = nil
  }

  private func installKeyboard() {
    let root = UIStackView()
    keyboardRoot = root
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
    root.addArrangedSubview(makeNineKeyLayout())
    japaneseKeys = JapaneseNineKeyView { [unowned self] title, label, action in
      makeKey(title: title, accessibilityLabel: label, action: action)
    }
    japaneseKeys.onInput = { [weak self] input in
      guard let self, isChineseMode, inputScheme.isJapanese else { return }
      playInputClick()
      for character in input { render(session.handleCharacter(String(character))) }
    }
    japaneseKeys.onSymbol = { [weak self] symbol in self?.handleSymbol(symbol) }
    japaneseKeys.onDelete = { [weak self] in self?.handleBackspace() }
    root.addArrangedSubview(japaneseKeys)
    handwriting.isHidden = true
    handwriting.onInsert = { [weak self] text in
      guard let self, inputScheme == .handwriting, isChineseMode else { return }
      render(session.finishComposition())
      insertOwnText(ChineseTextConversion.outputString(text, traditional: usesTraditionalOutput), source: .handwriting)
      playInputClick()
    }
    handwriting.canDownload = { [weak self] in self?.hasFullAccess == true }
    handwriting.onDelete = { [weak self] in self?.handleBackspace() }
    root.addArrangedSubview(handwriting)
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
    japaneseHeight = japaneseKeys.heightAnchor.constraint(equalTo: actionRow.heightAnchor, multiplier: 3, constant: 14)
    // Extra handwriting space belongs to the canvas, not enlarged Space/Return keys.
    handwritingActionHeight = actionRow.heightAnchor.constraint(equalToConstant: 44)
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
      button.configuration?.background.customView = nil
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
    nineSidebarWidth = sidebar.widthAnchor.constraint(equalTo: nineKeyContainer.widthAnchor, multiplier: 0.14)
    nineSidebarWidth?.isActive = true
    let nineKeyGrid = UIStackView()
    nineGrid = nineKeyGrid
    nineKeyGrid.axis = .vertical
    nineKeyGrid.spacing = 7
    nineKeyGrid.distribution = .fillEqually
    nineKeyContainer.addArrangedSubview(nineKeyGrid)
    // Keys 2-9 read their letters from nineKeyLetters, which the hold gesture below also reads, so
    // the printed legend and what a hold offers cannot drift apart. Key 1 carries no letters.
    for rowIndex in 0..<3 {
      let row = makeRow()
      for column in 0..<3 {
        let digit = rowIndex * 3 + column + 1
        let letters = Self.nineKeyLetters[digit]
        let button = makeKey(
          title: letters ?? "分词",
          accessibilityLabel: letters.map { "\(digit) \($0)" } ?? "拼音分词"
        ) { [weak self] in
          guard let self else { return }
          // While the digit layer is up these keys are a numeric keypad, so they output the digit
          // instead of feeding it to the pinyin session.
          if showsSymbols { handleSymbol(String(digit)) }
          else if letters == nil { handleCharacter("'") }
          else { handleCharacter(String(digit)) }
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
        var numberHint: UILabel?
        if let letters {
          let number = UILabel()
          numberHint = number
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
          // 长按取这个键上印着的数字和字母。九键把 2-9 当拼音输入,单个字母和数字本身没有入口,
          // 长按是它们唯一的来路。
          button.tag = digit
          let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleNineKeyHold(_:)))
          hold.minimumPressDuration = 0.3
          button.addGestureRecognizer(hold)
          button.accessibilityHint = "长按输入 \(digit) 或 \(letters)"
        }
        nineKeyGridKeys.append(
          NineKeyGridKey(button: button, digit: digit, letters: letters, numberHint: numberHint))
        row.addArrangedSubview(button)
      }
      nineKeyGrid.addArrangedSubview(row)
      nineKeyRows.append(row)
    }
    let controls = UIStackView()
    nineControls = controls
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

  /// 九键网格在拼音键面与数字键面之间切换。
  ///
  /// The same buttons carry both layers: the grid geometry a nine-key user picked is what the digit
  /// layer should keep, and rebuilding a second grid would leave two sources for the key legends.
  private func applyNineKeyDigitLayer(_ digits: Bool) {
    for key in nineKeyGridKeys {
      key.button.configuration?.title = digits ? String(key.digit) : (key.letters ?? "分词")
      key.button.accessibilityLabel =
        digits
        ? "数字 \(key.digit)"
        : (key.letters.map { "\(key.digit) \($0)" } ?? "拼音分词")
      // The corner hint names the digit a letter key also types; on the digit layer the face is
      // already the digit, so it would just print it twice.
      key.numberHint?.isHidden = digits
      key.button.accessibilityHint = digits ? nil : key.letters.map { "长按输入 \(key.digit) 或 \($0)" }
    }
  }

  private static let nineKeyLetters: [Int: String] = [
    2: "ABC", 3: "DEF", 4: "GHI", 5: "JKL", 6: "MNO", 7: "PQRS", 8: "TUV", 9: "WXYZ",
  ]

  @objc private func handleNineKeyHold(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began, let key = gesture.view as? UIButton,
      let letters = Self.nineKeyLetters[key.tag]
    else { return }
    showNineKeyHoldOptions(from: key, digit: key.tag, letters: letters)
  }

  private func showNineKeyHoldOptions(from key: UIButton, digit: Int, letters: String) {
    dismissNineKeyHoldOptions()
    playInputClick()
    let skin = KeyboardSkinPreference.selected
    // A full-surface backdrop so a tap anywhere else dismisses the row instead of typing.
    let backdrop = UIView()
    backdrop.accessibilityIdentifier = "nineKeyHoldBackdrop"
    backdrop.backgroundColor = .clear
    backdrop.translatesAutoresizingMaskIntoConstraints = false
    backdrop.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(dismissNineKeyHoldOptionsGesture)))

    let options = UIStackView()
    options.axis = .horizontal
    options.spacing = 4
    options.distribution = .fillEqually
    options.accessibilityIdentifier = "nineKeyHoldOptions"
    options.backgroundColor = skin.background
    options.layer.cornerRadius = 10
    options.layer.borderWidth = 1
    options.layer.borderColor = skin.accent.withAlphaComponent(0.3).cgColor
    options.isLayoutMarginsRelativeArrangement = true
    options.layoutMargins = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
    options.translatesAutoresizingMaskIntoConstraints = false

    for option in [String(digit)] + letters.lowercased().map(String.init) {
      let item = makeKey(title: option, accessibilityLabel: "输入 \(option)") { [weak self] in
        self?.commitNineKeyHoldOption(option)
      }
      item.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
      item.accessibilityIdentifier = "nineKeyHoldOption-\(option)"
      item.widthAnchor.constraint(equalToConstant: 36).isActive = true
      item.heightAnchor.constraint(equalToConstant: 38).isActive = true
      options.addArrangedSubview(item)
    }

    view.addSubview(backdrop)
    backdrop.addSubview(options)
    // Centring on the key yields to the edge insets, so the row stays inside the keyboard when the
    // held key is in the first or last column.
    let centred = options.centerXAnchor.constraint(equalTo: key.centerXAnchor)
    centred.priority = .defaultHigh
    NSLayoutConstraint.activate([
      backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      backdrop.topAnchor.constraint(equalTo: view.topAnchor),
      backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      options.bottomAnchor.constraint(equalTo: key.topAnchor, constant: -6),
      centred,
      options.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 6),
      options.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -6),
    ])
    nineKeyHoldPopup = backdrop
    UIAccessibility.post(notification: .layoutChanged, argument: options)
  }

  private func commitNineKeyHoldOption(_ text: String) {
    playInputClick()
    // The letter or digit is output, not pinyin input, so an open composition is committed first
    // rather than having the character appended to it.
    render(session.finishComposition())
    insertOwnText(text)
    dismissNineKeyHoldOptions()
  }

  @objc private func dismissNineKeyHoldOptionsGesture() {
    dismissNineKeyHoldOptions()
  }

  private func dismissNineKeyHoldOptions() {
    nineKeyHoldPopup?.removeFromSuperview()
    nineKeyHoldPopup = nil
  }

  private func makeCandidateStrip() -> UIView {
    let container = UIView()
    container.accessibilityIdentifier = "candidateStrip"
    container.backgroundColor = KeyboardSkinPreference.selected.keyBackground.withAlphaComponent(0.82)
    container.layer.cornerRadius = 12

    // The composition gets its own line. Sharing the candidate row cost it up to 28% of the width
    // and left the candidates that much narrower, on the one row where width is worth most.
    let compositionRow = UIView()
    compositionRow.accessibilityIdentifier = "compositionRow"
    compositionRow.translatesAutoresizingMaskIntoConstraints = false
    // The preedit button is centred here with no height of its own, so anything that makes it taller
    // than this row lands on the candidates underneath. Keep whatever overflows inside the row.
    compositionRow.clipsToBounds = true
    container.addSubview(compositionRow)

    var preeditConfiguration = UIButton.Configuration.plain()
    preeditConfiguration.contentInsets = NSDirectionalEdgeInsets(
      top: 4, leading: 8, bottom: 4, trailing: 8)
    // Truncate the tail. The head of a spelling is what tells the typist where a long composition
    // went wrong, so dropping it is dropping the useful half.
    preeditConfiguration.titleLineBreakMode = .byTruncatingTail
    preeditConfiguration.baseForegroundColor = KeyboardSkinPreference.selected.accent
    preeditConfiguration.titleTextAttributesTransformer =
      UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        // Cap what Dynamic Type may do to this. The button is centred in a fixed-height row with no
        // bound on its own height, so at the larger text sizes it outgrew the row and painted down
        // over the candidates. 17pt plus the 8pt of insets stays inside compositionRowHeight.
        attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
          for: .systemFont(ofSize: 15), maximumPointSize: 17)
        return attributes
      }
    preeditButton.configuration = preeditConfiguration
    preeditButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    preeditButton.showsMenuAsPrimaryAction = true
    preeditButton.accessibilityIdentifier = "preeditButton"

    updateLanguageModeButton()


    updateSchemeButton()
    schemeButton.addAction(UIAction { [weak self] _ in self?.showSchemePicker() }, for: .primaryActionTriggered)


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

    configureStripButton(
      expandCandidatesButton, symbol: "chevron.down", label: "展开全部候选",
      identifier: "expandCandidates")
    expandCandidatesButton.addAction(
      UIAction { [weak self] _ in self?.showCandidatePanel() },
      for: .primaryActionTriggered)

    preeditButton.translatesAutoresizingMaskIntoConstraints = false
    compositionRow.addSubview(preeditButton)

    let content = UIStackView(arrangedSubviews: [
      candidateScrollView, diagnosticLabel,
      candidateEmptySpacer, expandCandidatesButton, exitLocalModeButton,
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
      container.heightAnchor.constraint(equalToConstant: Self.candidateStripHeight),
      compositionRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      compositionRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
      compositionRow.topAnchor.constraint(equalTo: container.topAnchor),
      compositionRow.heightAnchor.constraint(equalToConstant: Self.compositionRowHeight),
      preeditButton.leadingAnchor.constraint(equalTo: compositionRow.leadingAnchor),
      preeditButton.trailingAnchor.constraint(lessThanOrEqualTo: compositionRow.trailingAnchor),
      preeditButton.centerYAnchor.constraint(equalTo: compositionRow.centerYAnchor),
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
      content.topAnchor.constraint(equalTo: compositionRow.bottomAnchor),
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
    shortcutBar.spacing = 0
    shortcutBar.accessibilityIdentifier = "keyboardShortcutBar"
    shortcutBar.translatesAutoresizingMaskIntoConstraints = false
    let brand = moreShortcut
    let icon = UIImageView()
    if let path = Bundle(for: KeyboardViewController.self).path(forResource: "KeyboardBrand", ofType: "png") {
      icon.image = UIImage(contentsOfFile: path)?.preparingThumbnail(of: CGSize(width: 72, height: 72))
    }
    icon.accessibilityIdentifier = "keyboardBrandIcon"
    icon.contentMode = .scaleAspectFit
    icon.layer.cornerRadius = 5
    icon.clipsToBounds = true
    icon.translatesAutoresizingMaskIntoConstraints = false
    brand.addSubview(icon)
    shortcutBar.addArrangedSubview(brand)
    NSLayoutConstraint.activate([
      brand.widthAnchor.constraint(equalToConstant: 44),
      icon.widthAnchor.constraint(equalToConstant: 24),
      icon.heightAnchor.constraint(equalToConstant: 24),
      icon.centerXAnchor.constraint(equalTo: brand.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
    ])
    for button in [schemeButton, scriptShortcut, emojiShortcut, skinShortcut, layoutShortcut, dismissShortcut] {
      shortcutBar.addArrangedSubview(button)
      if button !== schemeButton {
        button.widthAnchor.constraint(equalTo: schemeButton.widthAnchor).isActive = true
      }
    }
    container.addSubview(shortcutBar)
    NSLayoutConstraint.activate([
      shortcutBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
      shortcutBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
      // The shortcut bar stands in for the candidates, so it takes their row rather than the
      // composition's; the composition line stays reserved either way and nothing shifts when a
      // composition starts.
      shortcutBar.topAnchor.constraint(
        equalTo: container.topAnchor, constant: Self.compositionRowHeight),
      shortcutBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    scriptShortcut.addAction(UIAction { [weak self] _ in self?.showKeyboardAI() },
      for: .primaryActionTriggered)
    emojiShortcut.addAction(UIAction { [weak self] _ in self?.showEmojiPicker() }, for: .primaryActionTriggered)
    layoutShortcut.addAction(UIAction { [weak self] _ in self?.showLayoutPicker() }, for: .primaryActionTriggered)
    skinShortcut.addAction(UIAction { [weak self] _ in self?.showSkinPicker() }, for: .primaryActionTriggered)
    moreShortcut.addAction(UIAction { [weak self] _ in self?.showMorePicker() }, for: .primaryActionTriggered)
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
    // 简繁是一次性设置,不占常驻工具位;这个位置只在高情商回复方案下作为生成按钮出现。
    //
    // Script choice is made once and then left alone -- the app's 输入设置 already carries it, and
    // the toolbar is the row you see whenever nothing is being composed. It moved into 更多, which
    // is where the other settings that are set once already live.
    configure(scriptShortcut, title: nil, symbol: "bubble.left.and.text.bubble.right",
      label: "生成高情商回复", id: "replyShortcut")
    scriptShortcut.isEnabled = true
    scriptShortcut.accessibilityValue = nil
    scriptShortcut.isHidden = inputScheme != .thoughtfulReply
    configure(emojiShortcut, title: nil, symbol: "face.smiling", label: "表情", id: "emojiShortcut")
    configure(skinShortcut, title: nil, symbol: "tshirt", label: "切换皮肤", id: "skinShortcut")
    skinShortcut.accessibilityValue = KeyboardSkinPreference.selected.title
    configure(layoutShortcut, title: nil, symbol: "slider.horizontal.3", label: "键盘设置", id: "layoutShortcut")
    layoutShortcut.accessibilityValue = "默认键位"
    configure(moreShortcut, title: nil, symbol: nil, label: "更多快捷设置", id: "moreShortcut")
    moreMenu = UIMenu(children: [
      UIAction(title: "剪贴板历史", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
        self?.showClipboardHistory()
      },
      UIAction(title: "表情", image: UIImage(systemName: "face.smiling")) { [weak self] _ in
        self?.closeKeyboardPicker()
        self?.showEmojiPicker()
      },
      UIAction(title: "AI 润色", image: UIImage(systemName: "sparkles")) { [weak self] _ in
        self?.closeKeyboardPicker()
        self?.showKeyboardAI()
      },
      UIMenu(title: "输出字形", options: .displayInline, children: [
        UIAction(title: "简体", image: UIImage(systemName: "character.textbox"),
          attributes: isChineseMode && inputScheme.isJapanese ? .disabled : [],
          state: usesTraditionalOutput ? .off : .on) { [weak self] _ in
          self?.selectTraditionalOutput(false)
        },
        UIAction(title: "繁体", image: UIImage(systemName: "character.textbox"),
          attributes: isChineseMode && inputScheme.isJapanese ? .disabled : [],
          state: usesTraditionalOutput ? .on : .off) { [weak self] _ in
          self?.selectTraditionalOutput(true)
        },
      ]),
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
            self?.keyFeedback.impactOccurred(intensity: KeyboardFeedbackPreference.hapticStrength.intensity)
            self?.prepareKeyFeedback()
          }
          self?.updateShortcutButtons()
        },
      ]),
      UIMenu(title: "振动强度", image: UIImage(systemName: "waveform"), children: KeyboardHapticStrength.allCases.map { strength in
        UIAction(title: strength.title, state: strength == KeyboardFeedbackPreference.hapticStrength ? .on : .off) { [weak self] _ in
          KeyboardFeedbackPreference.defaults.set(strength.rawValue, forKey: KeyboardFeedbackPreference.strengthKey)
          if KeyboardFeedbackPreference.hapticsEnabled {
            self?.keyFeedback.impactOccurred(intensity: strength.intensity)
            self?.prepareKeyFeedback()
          }
          self?.updateShortcutButtons()
        }
      }),
      UIMenu(title: "本地输入", children: Self.localInputModes.map { mode in
        UIAction(title: mode.title, attributes: supportsLocalTools ? [] : .disabled) { [weak self] _ in
          self?.closeKeyboardPicker()
          self?.openLocalInputMode(mode.trigger)
        }
      }),
    ])
    if let moreMenu { morePicker?.update(menu: moreMenu) }
    configure(dismissShortcut, title: nil, symbol: "chevron.down", label: "收起键盘", id: "dismissShortcut")
  }

  private func makeSpellingStrip() -> UIView {
    spellingScrollView.showsVerticalScrollIndicator = false
    spellingScrollView.disableEdgeEffects()
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
    if includesShift {
      let delete = makeDeleteKey()
      delete.accessibilityIdentifier = "letterDeleteKey"
      row.addArrangedSubview(delete)
      row.distribution = .fill
      // Keep Shift and Delete easy to hit; distribute the seven letters evenly between them.
      let shift = row.arrangedSubviews[0]
      let keys = Array(row.arrangedSubviews.dropFirst().dropLast())
      NSLayoutConstraint.activate([
        shift.widthAnchor.constraint(equalToConstant: 44),
        delete.widthAnchor.constraint(equalTo: shift.widthAnchor),
      ] + keys.dropFirst().map { $0.widthAnchor.constraint(equalTo: keys[0].widthAnchor) })
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
      let key = makeKey(title: symbol, accessibilityLabel: "符号 \(symbol)") { [weak self] in
        self?.handleSymbol(symbol)
      }
      if let chinese = Self.chineseSymbolFaces[symbol] {
        symbolKeyFaces.append((key, symbol, chinese))
      }
      // Ten keys to a row leave about 32pt each, and the plain configuration's default 12pt on each
      // side leaves 8pt for a glyph that needs 12. The title line break mode is byClipping, so the
      // shortfall took the right-hand third off every digit rather than shrinking it. The letter
      // rows already zero this; the symbol rows never did. Row spacing is fillEqually, so the keys
      // keep their size and only the glyph gains the room.
      key.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
      row.addArrangedSubview(key)
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
    delete.accessibilityIdentifier = "symbolDeleteKey"
    actionDeleteButton = delete
    row.addArrangedSubview(delete)

    let punctuation = makeKey(title: ",", accessibilityLabel: "常用标点") { [weak self] in
      guard let self else { return }
      handleSymbol(quickPunctuationSymbols[0])
    }
    punctuation.configuration?.contentInsets = .zero
    punctuation.accessibilityIdentifier = "quickPunctuationKey"
    punctuation.accessibilityHint = "轻点输入，长按选择常用标点"
    quickPunctuationButton = punctuation
    quickPunctuationWidth = punctuation.widthAnchor.constraint(equalToConstant: 44)
    row.addArrangedSubview(punctuation)

    let space = makeKey(title: "空格", accessibilityLabel: "空格") { [weak self] in
      self?.handleSpace()
    }
    space.accessibilityIdentifier = "spaceKey"
    space.accessibilityHint = "轻点输入空格或选词，左右滑动移动光标"
    space.accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: "光标左移") { [weak self] _ in self?.moveCursor(by: -1); return self != nil },
      UIAccessibilityCustomAction(name: "光标右移") { [weak self] _ in self?.moveCursor(by: 1); return self != nil },
    ]
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSpacePan(_:)))
    pan.name = "spaceCursorPan"
    pan.maximumNumberOfTouches = 1
    pan.cancelsTouchesInView = true
    pan.delegate = self
    space.addGestureRecognizer(pan)
    spaceButton = space
    row.addArrangedSubview(space)
    let language = makeKey(title: "中/英", accessibilityLabel: "切换中英文") { [weak self] in self?.toggleInputMode() }
    language.configuration?.contentInsets = .zero
    language.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = .systemFont(ofSize: 13, weight: .medium)
      return attributes
    }
    language.accessibilityIdentifier = "bottomLanguageKey"
    language.isHidden = false
    bottomLanguageButton = language
    bottomLanguageWidth = language.widthAnchor.constraint(equalToConstant: 34)
    fullSymbolsWidth = nineKeySymbolsButton.widthAnchor.constraint(equalToConstant: 34)
    row.addArrangedSubview(language)

    let enter = makeKey(title: "换行", accessibilityLabel: "换行", emphasized: true) { [weak self] in
      self?.handleReturn()
    }
    enter.accessibilityIdentifier = "returnKey"
    enter.titleLabel?.adjustsFontSizeToFitWidth = true
    enter.titleLabel?.minimumScaleFactor = 0.65
    enterButton = enter
    row.addArrangedSubview(enter)

    standardActionWidths = [
      layoutToggle.widthAnchor.constraint(equalToConstant: 48.4),
      space.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
      enter.widthAnchor.constraint(equalToConstant: 59.4),
    ]
    symbolDeleteWidth = delete.widthAnchor.constraint(equalToConstant: 44)
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

  private func synchronizeInputContext() {
    guard let document = KeyboardHostContext.documentIdentifier(for: textDocumentProxy) else { return }
    applyInputContext(keyboardType: textDocumentProxy.keyboardType ?? .default, documentIdentifier: document)
  }

  // Explicit UIKit-trait boundary also allows layout/state regression tests without a fake engine.
  func applyInputContext(keyboardType: UIKeyboardType, documentIdentifier: UUID) {
    guard let chinese = inputContext.languageOverride(for: keyboardType, document: documentIdentifier,
                                                      isChinese: isChineseMode) else { return }
    // textWillChange normally finishes in the old field. If UIKit skipped that boundary, never
    // insert its remaining preedit into the new field while changing the keyboard's presentation.
    render(session.cancel())
    isChineseMode = chinese
    showsSymbols = false
    letterCaseState = .lowercase
    isAutomaticShift = false
    lastShiftTapTime = nil
    updateLanguageModeButton()
    updateAutomaticCapitalization()
    updateCandidateStrip(preedit: "", candidates: [])
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
    let capitalization = (inputContext.keyboardType == .URL || inputContext.keyboardType == .emailAddress)
      ? UITextAutocapitalizationType.none : (textDocumentProxy.autocapitalizationType ?? .sentences)
    switch capitalization {
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
    decorateKey(button)
  }

  private func updateLanguageModeButton() {
    var configuration = UIButton.Configuration.filled()
    configuration.title = isChineseMode ? (inputScheme.isJapanese ? "日" : "中") : "英"
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.actionForeground
    configuration.baseBackgroundColor = KeyboardSkinPreference.selected.actionBackground
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 3, leading: 5, bottom: 3, trailing: 5)
    configuration.background.cornerRadius = 8
    configuration.background.backgroundColor = KeyboardSkinPreference.selected.actionBackground
    bottomLanguageButton?.configuration = configuration
    if let button = bottomLanguageButton { decorateKey(button) }
    bottomLanguageButton?.accessibilityIdentifier = "bottomLanguageKey"
    bottomLanguageButton?.accessibilityLabel =
      isChineseMode ? "切换到英文输入" : "切换到所选输入方案"
    bottomLanguageButton?.accessibilityValue = isChineseMode ? (inputScheme.isJapanese ? "日语输入" : "中文输入") : "英文输入"
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

  private func applyLearningPreferences() {
    let mode: MetasequoiaFrequencyAdjustmentMode
    switch FrequencyAdjustmentPreference.mode {
    case .pin: mode = .pin
    case .halve: mode = .halve
    case .linear: mode = .linear
    case .promote: mode = .promote
    }
    _ = session.setFrequencyAdjustmentMode(
      mode, triggerCount: FrequencyAdjustmentPreference.triggerCount,
      linearStep: FrequencyAdjustmentPreference.linearStep)
    _ = session.setLearningEnabled(DictionaryLearningPreference.enabled)
    _ = session.setFuzzyPinyinRules(FuzzyPinyinPreference.activeRules)
    session.setWubiMixedPinyin(WubiMixedPinyinPreference.isEnabled)
    _ = session.setEnglishMixedCandidates(EnglishMixedCandidatesPreference.isEnabled)
  }

  private func applyInputScheme() -> MetasequoiaInputSnapshot {
    switch inputScheme {
    case .nineKey: session.switchToNineKey()
    case .ziranma, .microsoft, .shoudao: session.switch(toShuangpinProfile: inputScheme.rawValue)
    case .wubi: session.switchToWubi()
    case .japanese, .japaneseNineKey: session.switchToJapanese()
    case .handwriting: session.switch(toShuangpin: false)
    case .quanpin, .shuangpin, .thoughtfulReply: session.switch(toShuangpin: usesShuangpin)
    }
  }

  private func selectInputScheme(_ scheme: ChineseInputScheme) {
    guard InputSchemePreference.enabledSchemes.contains(scheme) else { return }
    if scheme == inputScheme {
      if scheme == .thoughtfulReply { synchronizeReplyKeyboard() }
      return
    }
    playInputClick()
    let source = typingSource
    handwriting.clear()
    inputScheme = scheme
    let snapshot = applyInputScheme()
    InputSchemePreference.scheme = scheme
    showsSymbols = false
    updateSchemeButton()
    updateLanguageModeButton()
    render(snapshot, source: source)
    updateShortcutButtons()
    synchronizeReplyKeyboard()
  }

  private func synchronizeReplyKeyboard() {
    guard inputScheme == .thoughtfulReply, isChineseMode else {
      replyModel.resetResults()
      replyPanelSuppressed = false
      dismissReplyPanel()
      return
    }
    guard replyPanel == nil, !replyPanelSuppressed else { return }
    let panel = UIHostingController(rootView: ReplyKeyboardView(model: replyModel,
      paste: { [weak self] in
        guard let self else { return }
        guard hasFullAccess else { replyModel.status = "粘贴与 AI 需要允许完全访问"; return }
        replyModel.setText(UIPasteboard.general.string ?? "")
      }, generate: { [weak self] style in self?.generateReply(style: style) },
      schemes: { [weak self] in self?.showSchemePicker() },
      skins: { [weak self] in self?.showSkinPicker() },
      dismiss: { [weak self] in self?.dismissKeyboard() }))
    replyPanel = panel
    addChild(panel)
    panel.view.accessibilityIdentifier = "replyKeyboard"
    panel.view.accessibilityViewIsModal = true
    panel.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(panel.view)
    NSLayoutConstraint.activate([
      panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      panel.view.topAnchor.constraint(equalTo: view.topAnchor),
      panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    panel.didMove(toParent: self)
  }

  private func dismissReplyPanel() {
    guard let panel = replyPanel else { return }
    panel.willMove(toParent: nil)
    panel.view.removeFromSuperview()
    panel.removeFromParent()
    replyPanel = nil
  }

  private func generateReply(style: String) {
    guard hasFullAccess else { replyModel.status = "请在系统键盘设置中允许完全访问"; return }
    guard let configuration = KeyboardAIService.configuration() else {
      replyModel.status = "请在水杉 App → AI 设置中保存键盘 AI 配置"; return
    }
    guard !hasComposition, let document = KeyboardHostContext.documentIdentifier(for: textDocumentProxy) else {
      replyModel.status = "请先完成输入，再选择回复方式"; return
    }
    let context = KeyboardDocumentContext(document: document,
      before: textDocumentProxy.documentContextBeforeInput, selected: textDocumentProxy.selectedText,
      after: textDocumentProxy.documentContextAfterInput)
    let matches: () -> Bool = { [weak self] in
      guard let self, hasFullAccess, inputScheme == .thoughtfulReply,
            KeyboardAIService.configuration() == configuration else { return false }
      return context.matches(document: KeyboardHostContext.documentIdentifier(for: textDocumentProxy),
        before: textDocumentProxy.documentContextBeforeInput, selected: textDocumentProxy.selectedText,
        after: textDocumentProxy.documentContextAfterInput)
    }
    playInputClick()
    replyModel.generate(style: style, request: { text, prompt in
      guard matches() else { throw ServiceFailure(message: "输入位置已变化，请重试") }
      var requestConfiguration = configuration
      requestConfiguration.prompt = prompt
      let result = try await CustomServiceClient.request(kind: .ai, configuration: requestConfiguration,
        text: text, token: KeyboardAIService.token(for: configuration))
      guard matches() else { throw ServiceFailure(message: "输入位置已变化，请重试") }
      return result
    }, insert: { [weak self] result in
      guard let self, matches() else { return false }
      insertOwnText(result, source: .reply)
      // The panel is pinned to every edge, so it covers the text that was just inserted and the
      // backspace that would fix it -- the only delete it leaves on screen edits the pasted source
      // instead. Its own status asks the reader to go and check the chat app, so it gets out of the
      // way and behaves like the other pickers, which close once a choice is made. The reply
      // shortcut brings it back.
      replyPanelSuppressed = true
      dismissReplyPanel()
      return true
    })
  }

  private func showKeyboardAI() {
    if inputScheme == .thoughtfulReply {
      replyPanelSuppressed = false
      synchronizeReplyKeyboard()
      return
    }
    guard hasFullAccess else { showDiagnostic("AI 需要开启键盘的“允许完全访问”。"); return }
    guard let configuration = KeyboardAIService.configuration() else {
      showDiagnostic("请在水杉 App 的 AI 设置中启用键盘 AI 并保存配置。"); return
    }
    guard !hasComposition, let document = KeyboardHostContext.documentIdentifier(for: textDocumentProxy),
          let selected = textDocumentProxy.selectedText, !selected.isEmpty, selected.count <= 10_000 else {
      showDiagnostic("请先完成输入，再选中要润色的文字（最多一万字）。"); return
    }
    closeKeyboardPicker()
    closeKeyboardService()
    let selection = KeyboardDocumentContext(document: document, before: textDocumentProxy.documentContextBeforeInput,
                                         selected: selected, after: textDocumentProxy.documentContextAfterInput)
    let matches: () -> Bool = { [weak self] in
      guard let self, hasFullAccess, servicePanel != nil else { return false }
      return selection.matches(document: KeyboardHostContext.documentIdentifier(for: textDocumentProxy),
        before: textDocumentProxy.documentContextBeforeInput, selected: textDocumentProxy.selectedText,
        after: textDocumentProxy.documentContextAfterInput)
    }
    let panel = UIHostingController(rootView: KeyboardAIView(text: selected, configuration: configuration,
      canSend: matches, insert: { [weak self] result in
        guard let self, matches(), KeyboardAIService.configuration() == configuration else { return false }
        insertOwnText(result, source: .ai)
        return true
      }, close: { [weak self] in self?.closeKeyboardService() }))
    servicePanel = panel
    addChild(panel)
    panel.view.frame = view.bounds
    panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(panel.view)
    panel.didMove(toParent: self)
  }

  private func showKeyboardVoice() {
    guard hasFullAccess else { showDiagnostic("语音结果需要开启键盘的“允许完全访问”。"); return }
    guard !hasComposition, !session.isInLocalMode else { showDiagnostic("请先完成当前输入，再插入语音结果。"); return }
    do {
      let store = VoiceTextHandoffStore()
      let entry = try store.read()
      let document = KeyboardHostContext.documentIdentifier(for: textDocumentProxy)
      let context = document.map { KeyboardDocumentContext(document: $0,
        before: textDocumentProxy.documentContextBeforeInput, selected: textDocumentProxy.selectedText,
        after: textDocumentProxy.documentContextAfterInput) }
      closeKeyboardPicker()
      closeKeyboardService()
      let panel = UIHostingController(rootView: KeyboardVoiceView(entry: entry, insert: { [weak self] in
        guard let self, hasFullAccess, servicePanel != nil, let context, let entry,
              context.matches(document: KeyboardHostContext.documentIdentifier(for: textDocumentProxy),
                before: textDocumentProxy.documentContextBeforeInput, selected: textDocumentProxy.selectedText,
                after: textDocumentProxy.documentContextAfterInput) else {
          throw ServiceFailure(message: "输入位置已变化，请关闭后重新打开语音结果。")
        }
        let text = try store.consume(entry.id)
        insertOwnText(text, source: .voice)
      }, close: { [weak self] in self?.closeKeyboardService() }))
      servicePanel = panel
      addChild(panel)
      panel.view.frame = view.bounds
      panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(panel.view)
      panel.didMove(toParent: self)
    } catch { showDiagnostic(error.localizedDescription) }
  }

  private func closeKeyboardService() {
    guard let panel = servicePanel else { return }
    servicePanel = nil
    panel.willMove(toParent: nil)
    panel.view.removeFromSuperview()
    panel.removeFromParent()
  }

  private func synchronizePersonalDictionary(force: Bool) {
    guard hasFullAccess, !hasComposition, !session.isInLocalMode, !synchronizingPersonalDictionary else { return }
    let store = PersonalDictionaryStore()
    do {
      let state = try store.read()
      guard force || state.pendingCount > 0 || state.refreshID != state.completedRefreshID else { return }
      synchronizingPersonalDictionary = true
      defer { synchronizingPersonalDictionary = false }
      try store.synchronize(apply: { request in
        try session.applyPersonalPrevious(request.previous?.bridgeValue, replacement: request.replacement?.bridgeValue,
                                          requestID: request.id.uuidString)
      }, page: { offset in
        let result = try session.personalEntries(atOffset: UInt(offset))
        guard let rows = result["entries"] as? [[String: Any]], let hasMore = result["hasMore"] as? Bool else {
          throw PersonalDictionaryStore.StoreError.invalidState
        }
        return PersonalWordPage(entries: try rows.map { try PersonalWord(bridgeValue: $0) }, hasMore: hasMore)
      })
    } catch PersonalDictionaryStore.StoreError.busy {
      // Another process owns this short transaction; the timer retries without interrupting typing.
    } catch {
      showDiagnostic(error.localizedDescription)
    }
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
    synchronizeReplyKeyboard()
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

  private func configureStripButton(
    _ button: UIButton, symbol: String, label: String, identifier: String
  ) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: symbol)
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.accent
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 2, leading: 2, bottom: 2, trailing: 2)
    button.configuration = configuration
    button.accessibilityLabel = label
    button.accessibilityIdentifier = identifier
    button.isHidden = true
    button.widthAnchor.constraint(equalToConstant: 26).isActive = true
  }

  private func showCandidatePanel() {
    closeKeyboardService()
    closeKeyboardPicker()
    playInputClick()
    let panel = KeyboardCandidatePanelView(
      candidates: visibleCandidates,
      hints: visibleCandidates.indices.map { wubiCodeHint(at: $0) }, preedit: visiblePreedit,
      display: { [weak self] in self?.chineseOutput($0) ?? $0 },
      onSelect: { [weak self] index in
        guard let self else { return }
        closeKeyboardPicker()
        playInputClick()
        render(session.selectCandidate(at: UInt(index)))
      },
      onClose: { [weak self] in self?.closeKeyboardPicker() })
    panel.accessibilityViewIsModal = true
    panel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(panel)
    NSLayoutConstraint.activate([
      panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      panel.topAnchor.constraint(equalTo: view.topAnchor),
      panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    candidatePanel = panel
    UIAccessibility.post(notification: .screenChanged, argument: panel)
  }

  private func updateExpandControl() {
    // Offered whenever the strip is not already showing everything. Paging by nine used to be the
    // only way past the ninth candidate, which left the tail of a 351-candidate answer thirty-nine
    // taps away; the panel shows the whole list at once instead.
    expandCandidatesButton.isHidden =
      visibleCandidates.count <= Self.candidatePageSize || visibleDiagnostic != nil
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
    if inputScheme.isJapanese || localModeTrigger == "R" { return text }
    return ChineseTextConversion.outputString(text, traditional: usesTraditionalOutput)
  }

  private func updateSchemeButton() {
    // The hints come from the engine's own profile for the scheme the session is running, so they
    // are refreshed wherever the scheme is, and cannot drift from what the keys actually produce.
    shuangpinKeyHints = session.shuangpinKeyHints()
    updateLetterCaseControls()

    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "keyboard")
    configuration.baseForegroundColor = KeyboardSkinPreference.selected.accent
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 3, leading: 4, bottom: 3, trailing: 4)
    configuration.background.strokeColor = KeyboardSkinPreference.selected.accent.withAlphaComponent(0.35)
    configuration.background.strokeWidth = 1
    configuration.background.cornerRadius = 8
    configuration.background.backgroundInsets = NSDirectionalEdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = .systemFont(ofSize: 16, weight: .medium)
      return attributes
    }
    schemeButton.configuration = configuration
    schemeButton.accessibilityIdentifier = "schemeButton"
    schemeButton.accessibilityLabel = "选择输入方案"
    schemeButton.accessibilityValue = inputScheme.title
    updateKeyboardLayout()
  }

  private func toggleLayout() {
    playInputClick()
    showsSymbols.toggle()
    updateKeyboardLayout()
  }

  private var quickPunctuationSymbols: [String] {
    guard isChineseMode, !session.isInLocalMode else { return [",", ".", "?", "!", ":", ";", "@"] }
    if inputScheme.isJapanese { return ["、", "。", "？", "！", "「", "」", "・"] }
    return ["，", "。", "？", "！", "、", "；", "："]
  }

  private func updateLetterRowInsets() {
    guard letterRowViews.count > 1, let row = letterRowViews[1] as? UIStackView else { return }
    let inset: CGFloat = KeyboardLayoutPreference.geometry.centeredLetters && inputScheme != .microsoft
      ? max(0, view.bounds.width - 10) * CGFloat(KeyboardLayoutPreference.geometry.letterInsetRatio) : 0
    let margins = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
    if row.layoutMargins != margins {
      row.isLayoutMarginsRelativeArrangement = true
      row.layoutMargins = margins
    }
  }

  private func applyLayoutPreferences() {
    guard actionRow != nil else { return }
    let layout = KeyboardLayoutPreference.geometry
    updateLetterRowInsets()
    guard appliedLayout != layout else { return }
    appliedLayout = layout
    keyboardRoot?.spacing = layout.rowSpacing
    nineGrid?.spacing = layout.rowSpacing
    nineControls?.spacing = layout.rowSpacing
    nineKeyHeight.constant = layout.rowSpacing * 2
    for row in letterRowViews + symbolRowViews + nineKeyRows {
      (row as? UIStackView)?.spacing = layout.keySpacing
    }
    actionRow.spacing = layout.keySpacing
    nineKeyContainer.spacing = layout.keySpacing
    if let old = nineSidebarWidth, let sidebar = old.firstItem as? UIView {
      old.isActive = false
      nineSidebarWidth = sidebar.widthAnchor.constraint(equalTo: nineKeyContainer.widthAnchor, multiplier: layout.sidebarRatio)
      nineSidebarWidth?.isActive = true
    }
    nineKeyActionWidths[0].isActive = false
    nineKeyActionWidths[0] = nineKeySymbolsButton.widthAnchor.constraint(equalTo: nineKeyContainer.widthAnchor, multiplier: layout.sidebarRatio)
    standardActionWidths[0].constant = 48.4
    standardActionWidths[1].constant = 44
    standardActionWidths[2].constant = 59.4
    quickPunctuationWidth?.constant = 44
    updateShortcutButtons()
  }

  private func updateKeyboardLayout() {
    applyLayoutPreferences()
    standardRowHeights.forEach { $0.1.isActive = false }
    microsoftFinalKey?.isHidden = !(isChineseMode && inputScheme == .microsoft && !session.isInLocalMode)
    let kana = isChineseMode && inputScheme == .japaneseNineKey && !session.isInLocalMode
    japaneseKeys?.isHidden = !kana || showsSymbols
    japaneseHeight?.constant = KeyboardLayoutPreference.rowSpacing * 2
    japaneseHeight?.isActive = kana && !showsSymbols
    japaneseKeys?.applyLayout()
    let nineKey = isChineseMode && inputScheme == .nineKey && !session.isInLocalMode
    let writes = isChineseMode && inputScheme == .handwriting && !showsSymbols && !session.isInLocalMode
    if !writes && !handwriting.isHidden { handwriting.deactivate() }
    handwriting.isHidden = !writes
    if writes { handwriting.activate() }
    handwritingActionHeight?.isActive = writes
    letterRowViews.forEach { $0.isHidden = showsSymbols || nineKey || writes || kana }
    // Nine-key keeps its own grid for the digit layer rather than handing over to the 26-key symbol
    // rows, which would put a ten-across keypad under a keyboard the user chose for three columns.
    let nineKeyDigits = nineKey && showsSymbols
    nineKeyContainer.isHidden = !nineKey
    nineKeyRows.forEach { $0.isHidden = !nineKey }
    applyNineKeyDigitLayer(nineKeyDigits)
    let hasSpellings = !session.nineKeySpellings().isEmpty
    spellingScrollView.isHidden = !hasSpellings
    punctuationStack.isHidden = hasSpellings
    if actionRow != nil {
      // The digit layer keeps the same grid, so the action row keeps its nine-key arrangement and
      // the grid keeps its height; only the key legends change.
      let usesNineKeyLayout = nineKey
      nineKeyHeight.isActive = usesNineKeyLayout
      let globeIndex = usesNineKeyLayout ? 5 : 2
      if actionRow.arrangedSubviews.firstIndex(of: actionGlobeButton) != globeIndex {
        actionRow.removeArrangedSubview(actionGlobeButton)
        actionGlobeButton.removeFromSuperview()
        actionRow.insertArrangedSubview(actionGlobeButton, at: globeIndex)
      }
      NSLayoutConstraint.deactivate(standardActionWidths + nineKeyActionWidths)
      symbolDeleteWidth?.isActive = false
      quickPunctuationWidth?.isActive = false
      globeWidthConstraint?.isActive = false
      actionGlobeButton.isHidden = !needsInputModeSwitchKey
      if needsInputModeSwitchKey {
        globeWidthConstraint = actionGlobeButton.widthAnchor.constraint(equalToConstant: 44)
        globeWidthConstraint?.isActive = true
      }
      let layout = KeyboardLayoutPreference.geometry
      nineKeySymbolsButton.isHidden = !(usesNineKeyLayout || (layout.showsFullKeyboardSymbols && !showsSymbols))
      fullSymbolsWidth?.isActive = !nineKeySymbolsButton.isHidden && !usesNineKeyLayout
      bottomLanguageButton?.isHidden = false
      bottomLanguageWidth?.isActive = true
      quickPunctuationButton.isHidden = usesNineKeyLayout || showsSymbols || writes || kana
      quickPunctuationWidth?.isActive = !quickPunctuationButton.isHidden
      let punctuation = quickPunctuationSymbols
      quickPunctuationButton.configuration?.title = punctuation[0]
      quickPunctuationButton.accessibilityValue = punctuation[0]
      quickPunctuationButton.menu = UIMenu(children: punctuation.map { symbol in
        UIAction(title: symbol) { [weak self] _ in self?.handleSymbol(symbol) }
      })
      actionDeleteButton.isHidden = !showsSymbols
      symbolDeleteWidth?.isActive = showsSymbols
      NSLayoutConstraint.activate(usesNineKeyLayout ? nineKeyActionWidths : standardActionWidths)
    }
    symbolRowViews.forEach { $0.isHidden = !showsSymbols || (isChineseMode && inputScheme == .nineKey && !session.isInLocalMode) }
    // Chinese punctuation only comes out in Chinese mode, and a local utility mode takes the plain
    // character, so the face follows what the key is actually going to insert right now.
    let sendsChinesePunctuation = isChineseMode && !session.isInLocalMode
    for face in symbolKeyFaces {
      let title = sendsChinesePunctuation ? face.chinese : face.ascii
      guard face.key.configuration?.title != title else { continue }
      face.key.configuration?.title = title
      face.key.accessibilityLabel = "符号 \(title)"
    }
    for (row, height) in standardRowHeights { height.isActive = !row.isHidden }
    if var configuration = layoutToggleButton?.configuration {
      configuration.title = showsSymbols ? (kana ? "あいう" : (nineKey ? "九键" : "ABC")) : "123"
      layoutToggleButton?.configuration = configuration
    }
    layoutToggleButton?.accessibilityLabel =
      showsSymbols ? "切换到字母" : "切换到数字和符号"
    updatePreferredKeyboardHeight()
  }

  private func handleBackspace() {
    if !handwriting.isHidden && handwriting.hasInk { handwriting.canvas.undo(); return }
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

  // Space means "commit the leading candidate". The strip no longer pages, so the leading chip is
  // always the engine's first and commitCandidate is that candidate. It also reports itself
  // unhandled when there is nothing to commit, which is what tells the caller to insert its space.
  // Return and the language switch flush the whole composition through finishComposition instead.
  private func commitVisibleCandidate() -> MetasequoiaInputSnapshot {
    return session.commitCandidate()
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer.name == "spaceCursorPan", let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: view)
    return abs(velocity.x) > abs(velocity.y)
  }

  private func moveCursor(by offset: Int) {
    guard offset != 0 else { return }
    guard let document = KeyboardHostContext.documentIdentifier(for: textDocumentProxy) else { return }
    if hasComposition { render(session.finishComposition()) }
    guard KeyboardHostContext.documentIdentifier(for: textDocumentProxy) == document else { return }
    textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
  }

  @objc private func handleSpacePan(_ pan: UIPanGestureRecognizer) {
    guard let document = KeyboardHostContext.documentIdentifier(for: textDocumentProxy) else {
      cursorMovement.cancel()
      spaceButton?.configuration?.title = "空格"
      return
    }
    switch pan.state {
    case .began:
      cursorMovement.begin(at: pan.translation(in: view).x, document: document)
      if hasComposition { render(session.finishComposition()) }
      spaceButton?.configuration?.title = "移动光标"
      if KeyboardFeedbackPreference.hapticsEnabled {
        keyFeedback.impactOccurred(intensity: KeyboardFeedbackPreference.hapticStrength.intensity)
      }
    case .changed:
      moveCursor(by: cursorMovement.advance(to: pan.translation(in: view).x,
                                           document: document))
      if !cursorMovement.isActive { spaceButton?.configuration?.title = "空格" }
    case .ended, .cancelled, .failed:
      cursorMovement.cancel()
      spaceButton?.configuration?.title = "空格"
    default: break
    }
  }

  private func handleSpace() {
    if !handwriting.isHidden && handwriting.hasInk { _ = handwriting.commitFirst(); return }
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
    if !handwriting.isHidden && handwriting.hasInk { _ = handwriting.commitFirst(); return }
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
    if localModeTrigger == "R" || (isChineseMode && inputScheme.isJapanese) { return .japanese }
    if localModeTrigger != nil { return .local }
    if !isChineseMode { return .english }
    if inputScheme == .thoughtfulReply { return .quanpin }
    return TypingSource(rawValue: inputScheme.rawValue) ?? .unknown
  }

  private func insertOwnText(_ text: String, source: TypingSource? = nil) {
    pendingOwnEdits += 1
    textDocumentProxy.insertText(text)
    recordTypingStatistics(text, source: source ?? typingSource)
  }

  // Swallowing this left the settings screen showing zeros with nothing to explain them, which is
  // how it reached a bug report rather than the person typing. The reason does not change between
  // keystrokes and a banner on each one would bury the composition, so it is said once per session.
  private func recordTypingStatistics(_ text: String, source: TypingSource) {
    guard hasFullAccess else { return }
    do {
      try TypingStatisticsStore().record(text, source: source)
    } catch {
      guard !reportedStatisticsFailure else { return }
      reportedStatisticsFailure = true
      showDiagnostic("统计未能写入：\(error.localizedDescription)")
    }
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
    if !hasComposition { applyLearningPreferences() }
    showDiagnostic(snapshot.diagnosticText)
    updateCandidateStrip(
      preedit: snapshot.preedit, candidates: snapshot.candidates,
      candidateCodes: snapshot.candidateCodes)
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

  private func updateCandidateStrip(preedit: String, candidates: [String], candidateCodes: [String] = []) {
    visiblePreedit = preedit
    visibleCandidates = candidates
    visibleCandidateCodes = candidateCodes
    // Any new candidate list is a different composition or a different set of matches, so the page
    // it was showing no longer describes anything.
    // A horizontal offset belongs to the previous matches, just like the page index.
    // Cancel deceleration as well so it cannot hide the new leading candidate.
    candidateScrollView.setContentOffset(.zero, animated: false)
    renderCandidateStrip()
  }

  private func renderCandidateStrip() {
    exitLocalModeButton.isHidden = !session.isInLocalMode
    let showsCandidates = session.isInLocalMode || !visiblePreedit.isEmpty || !visibleCandidates.isEmpty || visibleDiagnostic != nil
    shortcutBar.isHidden = showsCandidates
    candidateContent?.isHidden = !showsCandidates
    updatePreeditButton()
    // The chips are reused rather than rebuilt. Rebuilding them was 80-90% of the time a keystroke
    // spent here -- measured at 8-11ms against 0.6-2.5ms for the engine query itself -- and most of
    // that was constructing a UIMenu, with its nested destructive submenu, for every chip on every
    // keystroke. A chip's position never changes, so only its text has to.
    let page = Array(visibleCandidates.prefix(Self.candidatePageSize))
    while candidateStack.arrangedSubviews.count < page.count {
      let index = candidateStack.arrangedSubviews.count
      candidateStack.addArrangedSubview(makeCandidateButton(index: index))
    }
    for (offset, chip) in candidateStack.arrangedSubviews.enumerated() {
      guard let chip = chip as? UIButton else { continue }
      chip.isHidden = offset >= page.count
      guard offset < page.count else { continue }
      updateCandidateButton(chip, candidate: page[offset], hint: wubiCodeHint(at: offset),
                            number: offset + 1)
    }
    updateExpandControl()

    diagnosticLabel.text = visibleDiagnostic
    diagnosticLabel.accessibilityLabel = visibleDiagnostic.map { "提示：\($0)" }
    diagnosticLabel.isHidden = visibleDiagnostic == nil
    candidateScrollView.isHidden = visibleCandidates.isEmpty || visibleDiagnostic != nil
    candidateEmptySpacer.isHidden = !visibleCandidates.isEmpty || visibleDiagnostic != nil
  }

  // A touch keyboard has no number row to answer with, so the ordinal is spoken rather than drawn;
  // the index is the engine position the chip selects. The expand panel already showed bare text.
  // The keys that still single this candidate out, for a wubi composition that asked for them. A
  // local mode synthesises its candidates and has no code behind them, and a candidate the
  // mixed-pinyin fallback answered is keyed by spelling, which the prefix check drops on its own.
  private func wubiCodeHint(at index: Int) -> String {
    guard inputScheme == .wubi, !session.isInLocalMode, WubiCodeHintPreference.isEnabled,
          visibleCandidateCodes.indices.contains(index) else { return "" }
    return WubiCodeHintPreference.hint(code: visibleCandidateCodes[index], typed: visiblePreedit)
  }

  /// 候选按钮的骨架。位置固定,只建一次,内容由 updateCandidateButton 每次刷新。
  private func makeCandidateButton(index: Int) -> UIButton {
    var configuration = UIButton.Configuration.plain()
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
    button.accessibilityIdentifier = "candidate-\(index + 1)"
    // Built when the menu is opened rather than on every keystroke. It reads the candidate standing
    // at this position at that moment, so a reused chip never offers an action for a word that has
    // since scrolled away.
    button.menu = UIMenu(children: [
      UIDeferredMenuElement.uncached { [weak self] completion in
        completion(self?.candidateMenuElements(at: index) ?? [])
      }
    ])
    decorateKey(button)
    return button
  }

  // Not private: the keyboard tests are compiled into this target and check the menu here,
  // since the button only holds a deferred placeholder until it is opened.
  func candidateMenuElements(at index: Int) -> [UIMenuElement] {
    guard isChineseMode, !inputScheme.isJapanese, !session.isInLocalMode,
      visibleCandidates.indices.contains(index)
    else { return [] }
    let candidate = visibleCandidates[index]
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
    return [
      action("优先显示", "arrow.up", .promote),
      action("固定到首位", "pin", .fixFirst),
      action("取消固定", "pin.slash", .clearPosition),
      UIMenu(title: "删除词条…", image: UIImage(systemName: "trash"), options: .destructive, children: [
        action("确认删除此词条", "trash", .remove, destructive: true),
      ]),
    ]
  }

  /// 刷新一个候选按钮的文字,位置和动作都不变。
  private func updateCandidateButton(_ button: UIButton, candidate: String, hint: String, number: Int) {
    let display = chineseOutput(candidate)
    guard var configuration = button.configuration else { return }
    if hint.isEmpty {
      configuration.attributedTitle = nil
      configuration.title = display
    } else {
      configuration.attributedTitle = AttributedString(
        display, attributes: AttributeContainer([.font: UIFont.preferredFont(forTextStyle: .body)]))
        + AttributedString(
          " " + hint,
          attributes: AttributeContainer([
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: KeyboardSkinPreference.selected.keyForeground.withAlphaComponent(0.55),
          ]))
    }
    button.configuration = configuration
    button.accessibilityLabel =
      hint.isEmpty ? "候选词 \(number)：\(display)" : "候选词 \(number)：\(display)，还需输入 \(hint)"
    button.accessibilityHint =
      isChineseMode && !inputScheme.isJapanese && !session.isInLocalMode ? "轻点输入，长按管理词条" : nil
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
    configuration.baseForegroundColor = emphasized ? KeyboardSkinPreference.selected.actionForeground : KeyboardSkinPreference.selected.keyForeground
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
    if skin == .custom {
      let surface = SkinKeySurfaceView()
      surface.design = CustomKeyboardSkinStore.current
      surface.fillColor = configuration.background.backgroundColor ?? skin.keyBackground
      configuration.background.customView = surface
      configuration.background.backgroundColor = .clear
      configuration.background.cornerRadius = 0
      configuration.background.strokeWidth = 0
      button.configuration = configuration
      button.layer.shadowOpacity = 0
      return
    }
    configuration.background.customView = nil
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
    updateLetterRowInsets()
    if let globe = actionGlobeButton, globe.isHidden != !needsInputModeSwitchKey {
      updateKeyboardLayout()
    }
    updatePreferredKeyboardHeight()
    func updateShadows(_ node: UIView) {
      if let button = node as? UIButton, button.layer.shadowOpacity > 0 {
        button.layer.shadowPath = UIBezierPath(roundedRect: button.bounds,
          cornerRadius: KeyboardSkinPreference.selected.cornerRadius).cgPath
      }
      node.subviews.forEach { updateShadows($0) }
    }
    updateShadows(view)
  }

  private func updatePreferredKeyboardHeight() {
    let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape
      ?? (traitCollection.verticalSizeClass == .compact)
    // The composition line added a row to the candidate strip; the keyboard grew by it rather than
    // taking the space out of the keys.
    let extra = Self.compositionRowHeight
    let base: CGFloat = handwriting.isHidden
      ? (landscape ? 216 + extra : 260 + extra)
      : (landscape ? 260 + extra : 360 + extra)
    // The rows divide whatever height the keyboard claims, so this reaches the key faces too --
    // which is the point, since a key too small to hit is what this setting answers.
    let height = base + CGFloat(KeyboardLayoutPreference.heightAdjustment)
    if keyboardHeightConstraint?.constant != height { keyboardHeightConstraint?.constant = height }
  }

  private func showClipboardHistory() {
    closeKeyboardService()
    closeKeyboardPicker()
    let panel = KeyboardClipboardView(hasFullAccess: hasFullAccess, onInsert: { [weak self] text in
      guard let self else { return }
      render(session.finishComposition())
      insertOwnText(text)
      closeKeyboardPicker()
    }, onClose: { [weak self] in self?.closeKeyboardPicker() })
    panel.accessibilityViewIsModal = true
    panel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(panel)
    NSLayoutConstraint.activate([
      panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      panel.topAnchor.constraint(equalTo: view.topAnchor),
      panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    clipboardPanel = panel
    UIAccessibility.post(notification: .screenChanged, argument: panel)
  }

  private func selectTraditionalOutput(_ traditional: Bool) {
    usesTraditionalOutput = traditional
    ChineseOutputPreference.usesTraditional = traditional
    renderCandidateStrip()
    updateShortcutButtons()
  }

  private func showEmojiPicker() {
    closeKeyboardService()
    closeKeyboardPicker()
    // The composition is finished rather than carried: an emoji is not a candidate for the pinyin
    // already typed, so leaving it open would commit the two in the wrong order.
    render(session.finishComposition())
    let picker = KeyboardEmojiPickerView(onInsert: { [weak self] emoji in
      self?.insertOwnText(emoji, source: .local)
    }, onDelete: { [weak self] in
      self?.deleteOwnBackward()
    }, onClose: { [weak self] in self?.closeKeyboardPicker() })
    picker.accessibilityViewIsModal = true
    picker.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      picker.topAnchor.constraint(equalTo: view.topAnchor),
      picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    emojiPicker = picker
    UIAccessibility.post(notification: .screenChanged, argument: picker)
  }

  private func showLayoutPicker() {
    closeKeyboardService()
    closeKeyboardPicker()
    // The settings screen occupies the whole keyboard surface. Keeping the shortcut bar visible
    // underneath makes the screen look like a translucent sheet and leaves a second toolbar at
    // the bottom of the settings controls.
    shortcutBar.isHidden = true
    let picker = KeyboardLayoutPickerView(
      keySpacing: KeyboardLayoutPreference.keySpacing,
      rowSpacing: KeyboardLayoutPreference.rowSpacing,
      height: KeyboardLayoutPreference.heightAdjustment,
      onKeySpacing: { [weak self] spacing in
        KeyboardLayoutPreference.keySpacing = spacing
        self?.applyLayoutPreferences()
      },
      onRowSpacing: { [weak self] spacing in
        KeyboardLayoutPreference.rowSpacing = spacing
        self?.applyLayoutPreferences()
      },
      // Applied live so the panel is being resized under the finger that is dragging the slider,
      // which is the only way to judge the height being picked.
      onHeight: { [weak self] adjustment in
        KeyboardLayoutPreference.heightAdjustment = adjustment
        self?.updatePreferredKeyboardHeight()
      },
      // The panel's controls take their values when it is built, so it is rebuilt rather than
      // reaching back into it to move a slider that has just been reset underneath the user.
      onReset: { [weak self] in
        guard let self else { return }
        KeyboardLayoutPreference.resetToDefaults()
        applyLayoutPreferences()
        updatePreferredKeyboardHeight()
        updateShortcutButtons()
        showLayoutPicker()
      },
      onClose: { [weak self] in
        guard let self else { return }
        updateKeyboardLayout()
        closeKeyboardPicker()
      })
    picker.accessibilityIdentifier = "keyboardLayoutPicker"
    picker.accessibilityViewIsModal = true
    picker.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      picker.topAnchor.constraint(equalTo: view.topAnchor),
      picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    layoutPicker = picker
    UIAccessibility.post(notification: .screenChanged, argument: picker)
  }

  private func showMorePicker() {
    closeKeyboardService()
    closeKeyboardPicker()
    updateShortcutButtons()
    guard let moreMenu else { return }
    let picker = KeyboardMorePickerView(menu: moreMenu, onClose: { [weak self] in self?.closeKeyboardPicker() })
    picker.accessibilityViewIsModal = true
    picker.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      picker.topAnchor.constraint(equalTo: view.topAnchor),
      picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    morePicker = picker
    UIAccessibility.post(notification: .screenChanged, argument: picker)
  }

  private func showSchemePicker() {
    closeKeyboardService()
    closeKeyboardPicker()
    let picker = KeyboardSchemePickerView(selected: inputScheme, isChineseMode: isChineseMode, onSelect: { [weak self] scheme in
      guard let self else { return }
      closeKeyboardPicker()
      if !isChineseMode { toggleInputMode() }
      selectInputScheme(scheme)
    }, onSelectEnglish: { [weak self] in
      guard let self else { return }
      closeKeyboardPicker()
      if isChineseMode { toggleInputMode() }
    }, onSettings: { [weak self] in
      self?.showMorePicker()
    }, onClose: { [weak self] in self?.closeKeyboardPicker() })
    picker.accessibilityViewIsModal = true
    picker.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      picker.topAnchor.constraint(equalTo: view.topAnchor),
      picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    schemePicker = picker
    UIAccessibility.post(notification: .screenChanged, argument: picker)
  }

  private func showSkinPicker() {
    guard skinPicker == nil else { return }
    closeKeyboardService()
    closeKeyboardPicker()
    let picker = KeyboardSkinPickerView(selected: KeyboardSkinPreference.selected, onSelect: { [weak self] skin in
      guard let self else { return }
      KeyboardFeedbackPreference.defaults.set(skin.rawValue, forKey: KeyboardSkinPreference.key)
      closeKeyboardPicker()
      applyKeyboardSkin()
      playInputClick()
    }, onClose: { [weak self] in self?.closeKeyboardPicker() })
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

  private func closeKeyboardPicker() {
    dismissNineKeyHoldOptions()
    if let panel = candidatePanel {
      panel.removeFromSuperview()
      candidatePanel = nil
      UIAccessibility.post(notification: .screenChanged, argument: expandCandidatesButton)
    }
    if let picker = layoutPicker {
      picker.removeFromSuperview()
      layoutPicker = nil
      shortcutBar.isHidden = false
      UIAccessibility.post(notification: .screenChanged, argument: layoutShortcut)
    }
    if let picker = morePicker {
      picker.removeFromSuperview()
      morePicker = nil
      UIAccessibility.post(notification: .screenChanged, argument: moreShortcut)
    }
    if let picker = emojiPicker {
      picker.removeFromSuperview()
      emojiPicker = nil
      UIAccessibility.post(notification: .screenChanged, argument: moreShortcut)
    }
    if let picker = schemePicker {
      picker.removeFromSuperview()
      schemePicker = nil
      UIAccessibility.post(notification: .screenChanged, argument: schemeButton)
    }
    if let panel = clipboardPanel {
      panel.removeFromSuperview()
      clipboardPanel = nil
      UIAccessibility.post(notification: .screenChanged, argument: moreShortcut)
    }
    guard let picker = skinPicker else { return }
    picker.removeFromSuperview()
    skinPicker = nil
    UIAccessibility.post(notification: .screenChanged, argument: skinShortcut)
  }

  private func applyKeyboardSkin() {
    handwriting.canvas.setNeedsDisplay()
    replyModel.objectWillChange.send()
    let skin = KeyboardSkinPreference.selected
    view.backgroundColor = skin.background
    skinBackdrop.skin = skin
    func recolor(_ node: UIView) {
      if let button = node as? UIButton, var configuration = button.configuration {
        if configuration.background.customView is SkinKeySurfaceView || (configuration.background.backgroundColor?.cgColor.alpha ?? 0) > 0 {
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
      if let enterButton { decorateKey(enterButton) }
    }
    updateLanguageModeButton()
    updateSchemeButton()
    updateShortcutButtons()
    renderCandidateStrip()
    updateSpellingStrip()
    exitLocalModeButton.configuration?.baseForegroundColor = skin.accent
    preeditButton.configuration?.baseForegroundColor = skin.accent
    expandCandidatesButton.configuration?.baseForegroundColor = skin.accent
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
      keyFeedback.impactOccurred(intensity: KeyboardFeedbackPreference.hapticStrength.intensity)
      keyFeedback.prepare()
    }
  }
}
