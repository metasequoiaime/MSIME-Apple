import SwiftUI
import CoreImage
import UIKit

private final class KeyboardBrandButton: UIButton {
  let brandImageView = UIImageView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    brandImageView.contentMode = .scaleAspectFit
    brandImageView.accessibilityIdentifier = "keyboardBrandIcon"
    addSubview(brandImageView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    brandImageView.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
    brandImageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
  }
}

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
  private var sharedKeyboardHeightAdjustment: CGFloat = 0
  private let session = MetasequoiaInputSessionBridge()
  private lazy var snapshotWorker: DictionarySnapshotWorker = {
    let worker = DictionarySnapshotWorker(session: session)
    worker.report = { [weak self] in self?.showDiagnostic($0) }
    worker.applied = { [weak self] in self?.synchronizePersonalDictionary(force: true) }
    return worker
  }()
  private let candidateGlossQueue = DispatchQueue(
    label: "app.msime.ios.candidate-gloss", qos: .utility)
  private var candidateGlossEpoch: UInt64 = 0
  private var candidateGlossRequestedGeneration: UInt64?
  private let translations = CandidateTranslationStore()
  private var servicePanel: UIViewController?
  private var replyPanel: UIHostingController<ReplyKeyboardView>?
  private weak var compositionContainer: UIView?
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
  private let emojiShortcut = UIButton()
  private let skinShortcut = UIButton()
  private let layoutShortcut = UIButton()
  private var clipboardPanel: KeyboardClipboardView?
  private var skinPicker: KeyboardSkinPickerView?
  private var schemePicker: KeyboardSchemePickerView?
  private let moreShortcut = KeyboardBrandButton()
  private var morePicker: KeyboardMorePickerView?
  private let handwriting = HandwritingInputView()
  private var handwritingResults: [String] = []
  private var handwritingActionHeight: NSLayoutConstraint?
  private var layoutPicker: KeyboardLayoutPickerView?
  private var candidatePanel: KeyboardCandidatePanelView?
  private var candidatePanelGeneration: UInt64?
  private var emojiPicker: KeyboardEmojiPickerView?
  private enum MoreToolsPage { case root, localInput, keyboardSettings }
  private var moreTools: [KeyboardToolSection] = []
  private var moreToolsPage: MoreToolsPage = .root
  private let dismissShortcut = UIButton()
  private var letterButtons: [(button: UIButton, lowercase: String, hint: UILabel)] = []
  private var microsoftFinalKey: UIButton?
  private var letterRowViews: [UIView] = []
  private var symbolRowViews: [UIView] = []
  // Symbol keys show the punctuation they actually emit in Chinese mode.
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
  // In an active Quanpin or Shuangpin composition, Shift marks the next letter as Engine helpcode.
  // Idle Chinese input keeps the existing shortcut that switches to English capitalization.
  private var helpcodeCompositionEligible: Bool {
    !visiblePreedit.isEmpty && !session.isInLocalMode
      && (inputScheme == .quanpin || usesShuangpin)
  }
  private var entersHelpcode: Bool {
    isChineseMode && letterCaseState != .lowercase && helpcodeCompositionEligible
  }
  private var supportsLocalTools: Bool { isChineseMode && inputScheme != .wubi && !inputScheme.isJapanese }
  private var nineKeyRows: [UIView] = []
  private var actionRow: UIStackView!
  private var actionDeleteButton: UIButton!
  private var actionGlobeButton: UIButton!
  private var globeWidthConstraint: NSLayoutConstraint?
  private var japaneseKeys: JapaneseNineKeyView!
  private weak var japaneseGlobeButton: UIButton?
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
  private var visibleCandidateCodes: [String] = []
  private var visibleCandidateGlosses: [String] = []
  private var visibleCandidatePageCount = 0
  private var visibleCandidatesAnsweredByPinyinFallback = false
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
  private static let candidateRowHeight: CGFloat = 38
  static let glossLineHeight: CGFloat = 14
  static func glossHeight(lines: Int) -> CGFloat { CGFloat(max(lines, 0)) * glossLineHeight }
  static func candidateStripHeight(glossLines: Int) -> CGFloat {
    compositionRowHeight + candidateRowHeight + glossHeight(lines: glossLines)
  }
  /// Height reserved below the candidate row for composition and configured gloss lines.
  /// Tests and host layout consumers use this contract so the default gloss row stays accounted for.
  static var stripExtraHeight: CGFloat {
    compositionRowHeight + glossHeight(lines: configuredGlossLines(fullAccess: false))
  }

  static func canFillGloss(_ language: CandidateTranslationLanguage, fullAccess: Bool) -> Bool {
    !CandidateTranslationPreference.needsNetwork(language)
      || (CandidateTranslationPreference.onlineEnabled && fullAccess)
  }

  static func configuredGlossLines(fullAccess: Bool) -> Int {
    guard CandidateGlossPreference.enabled else { return 0 }
    var lines = canFillGloss(CandidateTranslationPreference.primary, fullAccess: fullAccess) ? 1 : 0
    if let secondary = CandidateTranslationPreference.secondary,
       canFillGloss(secondary, fullAccess: fullAccess) {
      lines += 1
    }
    return lines
  }
  private var glossLineCount = 0
  private var candidateStripHeightConstraint: NSLayoutConstraint?

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

  /// Chinese punctuation faces copied from the Engine's punctuation contract.
  ///
  /// The key input remains ASCII so the Engine owns paired punctuation and smart punctuation;
  /// only the visible face changes. English and local-input modes keep the literal ASCII face.
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
    translations.onArrival = { [weak self] in self?.renderCandidateStrip() }
    inputScheme = InputSchemePreference.scheme
    glossLineCount = currentGlossLines()
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
    let height = view.heightAnchor.constraint(equalToConstant:
      260 + Self.compositionRowHeight + Self.glossHeight(lines: glossLineCount)
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
    // The Tauri settings app writes the shared PreferencesStore rather than the
    // legacy App Group UserDefaults used by the old SwiftUI settings page.
    // Reload it off-thread so a fuzzy-pinyin change is visible the next time
    // the keyboard appears without blocking UIKit's input lifecycle.
    session.reloadSharedPreferences { [weak self] loaded in
      guard let self, loaded else { return }
      self.synchronizeSharedTouchPreferences()
      self.applyLearningPreferences()
    }
    candidateGlossEpoch &+= 1
    candidateGlossRequestedGeneration = nil
    translations.cancel()
    renderCandidateStrip()
    scheduleCandidateGlosses()
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
    candidateGlossEpoch &+= 1
    candidateGlossRequestedGeneration = nil
    translations.cancel()
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
    let japaneseSymbols = makeKey(title: "123", accessibilityLabel: "切换到数字和符号") { [weak self] in
      self?.toggleLayout()
    }
    japaneseSymbols.accessibilityIdentifier = "japaneseSymbols"
    let japaneseEmoji = makeKey(title: "^_^", accessibilityLabel: "顔文字と絵文字") { [weak self] in
      self?.showEmojiPicker()
    }
    japaneseEmoji.accessibilityIdentifier = "japaneseEmoji"
    let japaneseLanguage = makeKey(title: "英", accessibilityLabel: "切换中英文") { [weak self] in
      self?.toggleInputMode()
    }
    japaneseLanguage.accessibilityIdentifier = "japaneseLanguage"
    let japaneseGlobe = makeSymbolKey(symbol: "globe", accessibilityLabel: "选择下一个键盘")
    japaneseGlobe.accessibilityIdentifier = "japaneseGlobe"
    japaneseGlobe.addTarget(
      self, action: #selector(handleInputModeButton(_:event:)), for: .allTouchEvents)
    let japaneseSpace = makeKey(title: "空格", accessibilityLabel: "空格") { [weak self] in
      self?.handleSpace()
    }
    japaneseSpace.accessibilityIdentifier = "japaneseSpace"
    let japaneseReturn = makeKey(title: "改行", accessibilityLabel: "改行", emphasized: true) { [weak self] in
      self?.handleReturn()
    }
    japaneseReturn.accessibilityIdentifier = "japaneseReturn"
    japaneseKeys = JapaneseNineKeyView(makeKey: { [unowned self] title, label, action in
      makeKey(title: title, accessibilityLabel: label, action: action)
    }, makeDelete: { [unowned self] in makeDeleteKey() },
       sideKeys: [japaneseSpace, japaneseReturn],
       modeKeys: [japaneseSymbols, japaneseEmoji, japaneseLanguage, japaneseGlobe])
    japaneseGlobeButton = japaneseGlobe
    japaneseKeys.onInput = { [weak self] input in
      guard let self, isChineseMode, inputScheme.isJapanese else { return }
      playInputClick()
      for character in input { render(session.handleCharacter(String(character))) }
    }
    japaneseKeys.onSymbol = { [weak self] symbol in self?.handleSymbol(symbol) }
    japaneseKeys.onDelete = { [weak self] in self?.handleBackspace() }
    japaneseKeys.onVariant = { [weak self] in
      guard let self, isChineseMode, inputScheme.isJapanese else { return }
      playInputClick()
      render(session.cycleKanaVariant())
    }
    root.addArrangedSubview(japaneseKeys)
    handwriting.isHidden = true
    handwriting.onInsert = { [weak self] text in
      guard let self, inputScheme == .handwriting, isChineseMode else { return }
      render(session.finishComposition())
      insertOwnText(ChineseTextConversion.outputString(text, traditional: usesTraditionalOutput), source: .handwriting)
      playInputClick()
    }
    handwriting.onResults = { [weak self] words in
      guard let self, inputScheme == .handwriting, isChineseMode else { return }
      handwritingResults = words
      updateCandidateStrip(preedit: "", candidates: words)
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
    // The kana surface now has a dedicated punctuation row beneath the three kana rows.
    japaneseHeight = japaneseKeys.heightAnchor.constraint(
      equalToConstant: KeyboardLayoutPreference.rowSpacing * 3 + 4 * 44)
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

  private func makeCandidateStrip() -> UIView {
    let container = UIView()
    compositionContainer = container
    container.accessibilityIdentifier = "candidateStrip"
    container.backgroundColor = KeyboardSkinPreference.selected.keyBackground.withAlphaComponent(0.82)
    container.layer.cornerRadius = 12

    // The composition gets its own line. Sharing the candidate row cost it up to 28% of the width
    // and left the candidates that much narrower, on the one row where width is worth most.
    let compositionRow = UIView()
    compositionRow.accessibilityIdentifier = "compositionRow"
    compositionRow.translatesAutoresizingMaskIntoConstraints = false
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
        attributes.font = .preferredFont(forTextStyle: .subheadline)
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

    let stripHeight = container.heightAnchor.constraint(
      equalToConstant: Self.candidateStripHeight(glossLines: glossLineCount))
    candidateStripHeightConstraint = stripHeight
    NSLayoutConstraint.activate([
      stripHeight,
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
    brand.brandImageView.image = Self.brandTemplate() ?? UIImage(systemName: "leaf.fill")
    brand.brandImageView.tintColor = KeyboardSkinPreference.selected.accent
    shortcutBar.addArrangedSubview(brand)
    brand.widthAnchor.constraint(equalToConstant: 44).isActive = true
    let shortcuts = [layoutShortcut, scriptShortcut, emojiShortcut, skinShortcut, schemeButton, dismissShortcut]
    for button in shortcuts {
      shortcutBar.addArrangedSubview(button)
    }
    for button in shortcuts where button !== schemeButton {
      button.widthAnchor.constraint(equalTo: schemeButton.widthAnchor).isActive = true
    }
    container.addSubview(shortcutBar)
    NSLayoutConstraint.activate([
      shortcutBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      shortcutBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      // The shortcut bar stands in for the candidates, so it takes their row rather than the
      // composition's; the composition line stays reserved either way and nothing shifts when a
      // composition starts.
      shortcutBar.topAnchor.constraint(
        equalTo: container.topAnchor, constant: Self.compositionRowHeight),
      shortcutBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    scriptShortcut.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      if inputScheme == .thoughtfulReply { showKeyboardAI(); return }
      if KeyboardLayoutPreference.voiceShortcutEnabled { showKeyboardVoice(); return }
      usesTraditionalOutput.toggle()
      ChineseOutputPreference.usesTraditional = usesTraditionalOutput
      renderCandidateStrip()
      updateShortcutButtons()
    }, for: .primaryActionTriggered)
    emojiShortcut.addAction(UIAction { [weak self] _ in self?.showEmojiPicker() },
                            for: .primaryActionTriggered)
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
    configure(scriptShortcut, title: usesTraditionalOutput ? "繁" : "简", symbol: nil,
      label: usesTraditionalOutput ? "切换到简体" : "切换到繁体", id: "scriptShortcut")
    scriptShortcut.isEnabled = !(isChineseMode && inputScheme.isJapanese)
    scriptShortcut.accessibilityValue = scriptShortcut.isEnabled ? (usesTraditionalOutput ? "繁体" : "简体") : "日语不使用简繁转换"
    if KeyboardLayoutPreference.voiceShortcutEnabled {
      configure(scriptShortcut, title: nil, symbol: "waveform", label: "语音结果", id: "layoutVoiceShortcut")
      scriptShortcut.isEnabled = true
      scriptShortcut.accessibilityValue = nil
    }
    if inputScheme == .thoughtfulReply {
      configure(scriptShortcut, title: nil, symbol: "bubble.left.and.text.bubble.right",
        label: "生成高情商回复", id: "replyShortcut")
      scriptShortcut.isEnabled = true
      scriptShortcut.accessibilityValue = nil
    }
    configure(emojiShortcut, title: nil, symbol: "face.smiling", label: "表情", id: "emojiShortcut")
    configure(skinShortcut, title: nil, symbol: "tshirt", label: "切换皮肤", id: "skinShortcut")
    skinShortcut.accessibilityValue = KeyboardSkinPreference.selected.title
    configure(layoutShortcut, title: nil, symbol: "slider.horizontal.3", label: "键盘设置", id: "layoutShortcut")
    layoutShortcut.accessibilityValue = "默认键位"
    configure(moreShortcut, title: nil, symbol: nil, label: "更多快捷设置", id: "moreShortcut")
    moreTools = makeToolSections()
    updateMorePickerPage()
    configure(dismissShortcut, title: nil, symbol: "chevron.down", label: "收起键盘", id: "dismissShortcut")
  }

  private func makeToolSections() -> [KeyboardToolSection] {
    [KeyboardToolSection(title: nil, kind: .opens, columns: 2, tools: [
      KeyboardTool(title: "表情", symbol: "face.smiling") { [weak self] in self?.showEmojiPicker() },
      KeyboardTool(title: "剪贴板历史", symbol: "doc.on.clipboard") { [weak self] in self?.showClipboardHistory() },
      KeyboardTool(title: "AI 润色", symbol: "sparkles") { [weak self] in
        self?.closeKeyboardPicker(); self?.showKeyboardAI()
      },
      KeyboardTool(title: "语音结果", symbol: "waveform") { [weak self] in
        self?.closeKeyboardPicker(); self?.showKeyboardVoice()
      },
      KeyboardTool(title: "本地输入", symbol: "textformat.123", enabled: supportsLocalTools) { [weak self] in
        self?.showMoreToolsPage(.localInput)
      },
      KeyboardTool(title: "键盘设置", symbol: "gearshape") { [weak self] in
        self?.showMoreToolsPage(.keyboardSettings)
      },
    ])]
  }

  private func makeKeyboardSettingsSections() -> [KeyboardToolSection] {
    [
      backToToolsSection(),
      KeyboardToolSection(title: "键盘设置", kind: .toggle, columns: 2, tools: [
        KeyboardTool(title: "按键音", symbol: "speaker.wave.2",
                     selected: KeyboardFeedbackPreference.soundEnabled) { [weak self] in
          KeyboardFeedbackPreference.defaults.set(!KeyboardFeedbackPreference.soundEnabled,
                                                   forKey: KeyboardFeedbackPreference.soundKey)
          if KeyboardFeedbackPreference.soundEnabled { UIDevice.current.playInputClick() }
          self?.updateShortcutButtons()
        },
        KeyboardTool(title: "按键振动", symbol: "iphone.radiowaves.left.and.right",
                     selected: KeyboardFeedbackPreference.hapticsEnabled) { [weak self] in
          KeyboardFeedbackPreference.defaults.set(!KeyboardFeedbackPreference.hapticsEnabled,
                                                   forKey: KeyboardFeedbackPreference.hapticsKey)
          if KeyboardFeedbackPreference.hapticsEnabled {
            self?.keyFeedback.impactOccurred(intensity: KeyboardFeedbackPreference.hapticStrength.intensity)
            self?.prepareKeyFeedback()
          }
          self?.updateShortcutButtons()
        },
        KeyboardTool(title: "全角输入", symbol: "character.cursor.ibeam",
                     selected: KeyboardLayoutPreference.fullWidthInputEnabled) { [weak self] in
          KeyboardLayoutPreference.fullWidthInputEnabled = !KeyboardLayoutPreference.fullWidthInputEnabled
          self?.updateShortcutButtons()
        },
        KeyboardTool(title: "振动强度", symbol: "waveform",
                     enabled: KeyboardFeedbackPreference.hapticsEnabled,
                     caption: KeyboardFeedbackPreference.hapticStrength.title) { [weak self] in
          guard let self else { return }
          let strengths = KeyboardHapticStrength.allCases
          let current = strengths.firstIndex(of: KeyboardFeedbackPreference.hapticStrength) ?? 0
          let next = strengths[(current + 1) % strengths.count]
          KeyboardFeedbackPreference.defaults.set(next.rawValue,
                                                   forKey: KeyboardFeedbackPreference.strengthKey)
          keyFeedback.impactOccurred(intensity: next.intensity)
          prepareKeyFeedback()
          updateShortcutButtons()
        },
      ]),
    ]
  }

  private func makeLocalModeSections() -> [KeyboardToolSection] {
    [
      backToToolsSection(),
      KeyboardToolSection(title: "本地输入", kind: .opens, columns: 2,
                          tools: Self.localInputModes.map { mode in
        KeyboardTool(title: mode.title, enabled: supportsLocalTools) { [weak self] in
          self?.closeKeyboardPicker()
          self?.openLocalInputMode(mode.trigger)
        }
      }),
    ]
  }

  private func backToToolsSection() -> KeyboardToolSection {
    KeyboardToolSection(title: nil, kind: .opens, columns: 1, tools: [
      KeyboardTool(title: "返回工具", symbol: "chevron.left") { [weak self] in
        self?.showMoreToolsPage(.root)
      },
    ])
  }

  private func showMoreToolsPage(_ page: MoreToolsPage) {
    moreToolsPage = page
    updateMorePickerPage()
  }

  private func updateMorePickerPage() {
    let sections: [KeyboardToolSection]
    switch moreToolsPage {
    case .root: sections = moreTools
    case .localInput: sections = makeLocalModeSections()
    case .keyboardSettings: sections = makeKeyboardSettingsSections()
    }
    morePicker?.update(sections: sections)
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
      if entersHelpcode, let letter = character.first, letter.isLetter {
        render(session.handleCharacter(character.uppercased(), shifted: true))
        if letterCaseState == .shifted {
          letterCaseState = .lowercase
          lastShiftTapTime = nil
          updateLetterCaseControls()
        }
        return
      }
      render(session.handleCharacter(character))
    } else {
      let output = letterCaseState == .lowercase ? character : character.uppercased()
      insertDirectText(output)
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
      insertDirectText(symbol)
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
        insertDirectText(symbol)
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

    guard let punctuation = KeyboardPunctuationContext.engineInput(
      for: symbol, japanese: inputScheme.isJapanese) else {
      render(session.finishComposition())
      insertDirectText(symbol)
      return
    }
    let preceding = KeyboardPunctuationContext.precedingScalar(
      textDocumentProxy.documentContextBeforeInput)
    let snapshot = session.handlePunctuationWithContext(punctuation, preceding: preceding)
    if snapshot.isHandled {
      render(snapshot)
      return
    }

    // A symbol the session declines is an automatic commit, and macOS resolves those with
    // finish_composition — the leading candidate. commitRaw committed the raw pinyin letters
    // instead, so typing "nihao" then "@" produced "nihao@" rather than "你好@".
    render(session.finishComposition())
    insertDirectText(punctuation)
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
    if isChineseMode && !helpcodeCompositionEligible {
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
    // 拼音和罗马字的键面用大写，切到英文才回小写。键面大小写通常只是外观；组合中的
    // Shift 通过无障碍标签显示辅码状态，并把下一字母作为大写辅码交给 Engine。
    // 本地模式除外：那里敲入的就是键面上的字面字符，保持小写才不会误导用户。
    let shifted = letterCaseState != .lowercase && (!isChineseMode || entersHelpcode)
    let usesUppercase = (isChineseMode && !session.isInLocalMode) || shifted
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
        shifted
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
    let legacyFuzzyPreferenceExists = FuzzyPinyinPreference.defaults.object(
      forKey: FuzzyPinyinPreference.enabledKey) != nil
    let fuzzyRules = legacyFuzzyPreferenceExists
      ? FuzzyPinyinPreference.activeRules
      : (session.sharedFuzzyPinyinRules ?? FuzzyPinyinPreference.activeRules)
    if session.fuzzyPinyinRulesApplied != fuzzyRules {
      _ = session.setFuzzyPinyinRules(fuzzyRules)
    }
    session.setWubiMixedPinyin(WubiMixedPinyinPreference.isEnabled)
    applyCandidateGlossLayout()
  }

  private func currentGlossLines() -> Int {
    Self.configuredGlossLines(fullAccess: hasFullAccess)
  }

  private func applyCandidateGlossLayout() {
    let lines = currentGlossLines()
    guard lines != glossLineCount else { return }
    glossLineCount = lines
    candidateStripHeightConstraint?.constant = Self.candidateStripHeight(glossLines: lines)
    updatePreferredKeyboardHeight()
    renderCandidateStrip()
  }

  private func applyInputScheme() -> MetasequoiaInputSnapshot {
    switch inputScheme {
    case .nineKey: session.switchToNineKey()
    case .ziranma, .microsoft, .shoudao: session.switch(toShuangpinProfile: inputScheme.rawValue)
    case .wubi: session.switchToWubi()
    case .japanese, .japaneseNineKey: session.switchToJapanese()
    case .handwriting: session.switch(toShuangpin: false)
    case .quanpin, .thoughtfulReply: session.switch(toShuangpin: usesShuangpin)
    case .shuangpin: session.switch(toShuangpinProfile: "xiaohe")
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
      }, generate: { [weak self] style in self?.generateReply(style: style) }))
    replyPanel = panel
    addChild(panel)
    panel.view.accessibilityIdentifier = "replyKeyboard"
    panel.view.accessibilityViewIsModal = true
    panel.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(panel.view)
    NSLayoutConstraint.activate([
      panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      panel.view.topAnchor.constraint(equalTo: compositionContainer?.bottomAnchor ?? view.topAnchor),
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

  private static func sharedInputScheme(_ value: String) -> ChineseInputScheme? {
    switch value {
    case "quanpin": return .quanpin
    case "nine_key": return .nineKey
    case "xiaohe": return .shuangpin
    case "ziranma": return .ziranma
    case "microsoft": return .microsoft
    case "shoudao": return .shoudao
    case "wubi": return .wubi
    case "japanese_nine_key": return .japaneseNineKey
    case "japanese": return .japanese
    case "handwriting": return .handwriting
    case "thoughtful_reply": return .thoughtfulReply
    default: return nil
    }
  }

  /// Apply settings written by the Tauri iOS host to the native keyboard's
  /// legacy App Group preferences. Scheme changes are intentionally deferred
  /// while composing so a settings reload cannot interrupt Engine state.
  private func synchronizeSharedTouchPreferences() {
    guard let preferences = session.sharedPreferences else { return }
    if let glossEnabled = preferences["candidate_english_gloss"] as? Bool,
       glossEnabled != CandidateGlossPreference.enabled {
      CandidateGlossPreference.enabled = glossEnabled
      candidateGlossEpoch &+= 1
      candidateGlossRequestedGeneration = nil
      visibleCandidateGlosses = []
    }
    if let translationsEnabled = preferences["candidate_translations"] as? Bool {
      CandidateTranslationPreference.onlineEnabled = translationsEnabled
    }
    if let target = preferences["translation_target_language"] as? String,
       let index = CandidateTranslationPreference.languages.firstIndex(where: { $0.code == target.uppercased() }) {
      CandidateTranslationPreference.primaryIndex = index
    }
    var skinChanged = false
    var customSkinChanged = false
    let rawSkin = preferences["touch_keyboard_skin"] as? String
    if let rawSkin,
       let skin = KeyboardSkin(rawValue: rawSkin), skin != .custom,
       skin != KeyboardSkinPreference.selected {
      KeyboardFeedbackPreference.defaults.set(skin.rawValue, forKey: KeyboardSkinPreference.key)
      skinChanged = true
    }
    if let design = preferences["custom_touch_keyboard_skin"] as? [String: Any],
       JSONSerialization.isValidJSONObject(design),
       let data = try? JSONSerialization.data(withJSONObject: design),
       let decoded = try? JSONDecoder().decode(CustomKeyboardSkin.self, from: data) {
      let normalized = decoded.normalized
      if normalized != CustomKeyboardSkinStore.current {
        CustomKeyboardSkinStore.save(normalized)
        customSkinChanged = true
      }
      if rawSkin == KeyboardSkin.custom.rawValue,
         KeyboardSkinPreference.selected != .custom {
        KeyboardFeedbackPreference.defaults.set(KeyboardSkin.custom.rawValue, forKey: KeyboardSkinPreference.key)
        skinChanged = true
      }
    }
    if let spacing = (preferences["touch_key_spacing_tenths"] as? NSNumber)?.doubleValue {
      KeyboardLayoutPreference.keySpacing = spacing / 10
    }
    if let spacing = (preferences["touch_row_spacing_tenths"] as? NSNumber)?.doubleValue {
      KeyboardLayoutPreference.rowSpacing = spacing / 10
    }
    if let voice = preferences["touch_voice_shortcut"] as? Bool {
      KeyboardLayoutPreference.voiceShortcutEnabled = voice
    }
    if let adjustment = (preferences["touch_keyboard_height_adjustment"] as? NSNumber)?.doubleValue,
       adjustment.isFinite {
      sharedKeyboardHeightAdjustment = CGFloat(min(48, max(-12, adjustment)))
    }

    var selectedScheme: ChineseInputScheme?
    if let schemes = preferences["touch_keyboard_schemes"] as? [String: Any] {
      let enabled = (schemes["enabled"] as? [String] ?? []).compactMap(Self.sharedInputScheme)
      if !enabled.isEmpty { InputSchemePreference.enabledSchemes = enabled }
      selectedScheme = (schemes["selected"] as? String).flatMap(Self.sharedInputScheme)
    }
    if !hasComposition, let selectedScheme, InputSchemePreference.enabledSchemes.contains(selectedScheme) {
      selectInputScheme(selectedScheme)
    }
    if skinChanged || customSkinChanged { applyKeyboardSkin() }
    applyLayoutPreferences()
    updateShortcutButtons()
    updatePreferredKeyboardHeight()
    scheduleCandidateGlosses()
    renderCandidateStrip()
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
    do {
      let snapshot = try CandidatePanelSnapshot.decode(session.allCandidates())
      guard !snapshot.entries.isEmpty else { return }
      let indexes = snapshot.entries.map(\.index)
      let generation = snapshot.generation
      let panel = KeyboardCandidatePanelView(
        candidates: snapshot.entries.map(\.text), preedit: snapshot.preedit,
        annotations: snapshot.entries.map {
          candidatePanelAnnotation(code: $0.code, gloss: $0.translation, word: $0.text,
                                   typed: snapshot.preedit)
        },
        display: { [weak self] in self?.chineseOutput($0) ?? $0 },
        onSelect: { [weak self] index in
          guard let self, indexes.indices.contains(index) else { return }
          closeKeyboardPicker()
          playInputClick()
          render(session.selectCandidate(generation: generation, globalIndex: indexes[index]))
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
      candidatePanelGeneration = generation
      UIAccessibility.post(notification: .screenChanged, argument: panel)
    } catch {
      showDiagnostic("候选列表暂不可用")
    }
  }

  private func updateExpandControl() {
    // Offered whenever the strip is not already showing everything. Paging by nine used to be the
    // only way past the ninth candidate, which left the tail of a 351-candidate answer thirty-nine
    // taps away; the panel shows the whole list at once instead.
    expandCandidatesButton.isHidden = visibleCandidatePageCount <= 1 || visibleDiagnostic != nil
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
    // The scheme shortcut uses the same unboxed treatment as the other shared shortcuts. The
    // current scheme is already exposed through accessibilityValue and the picker it opens.
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
    japaneseKeys?.isHidden = !kana
    japaneseKeys?.setDigits(showsSymbols)
    japaneseHeight?.constant = KeyboardLayoutPreference.rowSpacing * 3 + 4 * 44
    japaneseHeight?.isActive = kana
    japaneseKeys?.applyLayout()
    actionRow?.isHidden = kana
    japaneseGlobeButton?.isHidden = !needsInputModeSwitchKey
    let nineKey = isChineseMode && inputScheme == .nineKey && !session.isInLocalMode
    let writes = isChineseMode && inputScheme == .handwriting && !showsSymbols && !session.isInLocalMode
    if !writes && !handwriting.isHidden { handwriting.deactivate() }
    handwriting.isHidden = !writes
    if writes { handwriting.activate() }
    handwritingActionHeight?.isActive = writes
    letterRowViews.forEach { $0.isHidden = showsSymbols || nineKey || writes || kana }
    nineKeyContainer.isHidden = showsSymbols || !nineKey
    nineKeyRows.forEach { $0.isHidden = showsSymbols || !nineKey }
    let hasSpellings = !session.nineKeySpellings().isEmpty
    spellingScrollView.isHidden = !hasSpellings
    punctuationStack.isHidden = hasSpellings
    if actionRow != nil {
      let usesNineKeyLayout = nineKey && !showsSymbols
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
      nineKeySymbolsButton.isHidden = !(usesNineKeyLayout || kana || (layout.showsFullKeyboardSymbols && !showsSymbols))
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
      actionDeleteButton.isHidden = !showsSymbols || kana
      symbolDeleteWidth?.isActive = showsSymbols && !kana
      NSLayoutConstraint.activate(usesNineKeyLayout ? nineKeyActionWidths : standardActionWidths)
    }
    symbolRowViews.forEach { $0.isHidden = !showsSymbols || kana }
    // Chinese punctuation only appears in Chinese mode. Local utilities and dedicated English
    // input send the literal ASCII key value, so their labels must follow their insertion path.
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
    if kana {
      nineKeySymbolsButton?.menu = UIMenu(children: quickPunctuationSymbols.map { symbol in
        UIAction(title: symbol) { [weak self] _ in self?.handleSymbol(symbol) }
      })
    }
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
      insertDirectText(" ")
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

  private func insertDirectText(_ text: String, source: TypingSource? = nil) {
    insertOwnText(
      FullWidthInputPolicy.output(text, enabled: KeyboardLayoutPreference.fullWidthInputEnabled),
      source: source)
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
    japaneseKeys?.setComposing(hasComposition)
    if !hasComposition { applyLearningPreferences() }
    showDiagnostic(snapshot.diagnosticText)
    updateCandidateStrip(preedit: snapshot.preedit, candidates: snapshot.candidates,
                         candidateCodes: snapshot.candidateCodes,
                         candidateGlosses: snapshot.candidateGlosses,
                         candidatePageCount: snapshot.candidatePageCount,
                         answeredByPinyinFallback: snapshot.answeredByPinyinFallback)
    refreshCandidatePanelAnnotations()
    updateSpellingStrip()
    scheduleCandidateGlosses()
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

  private func updateCandidateStrip(preedit: String, candidates: [String],
                                    candidateCodes: [String] = [], candidateGlosses: [String] = [],
                                    candidatePageCount: Int = 0,
                                    answeredByPinyinFallback: Bool = false) {
    if visibleCandidates != candidates {
      candidateGlossRequestedGeneration = nil
    }
    visiblePreedit = preedit
    visibleCandidates = candidates
    visibleCandidateCodes = candidateCodes
    visibleCandidateGlosses = candidateGlosses
    visibleCandidatePageCount = candidatePageCount
    visibleCandidatesAnsweredByPinyinFallback = answeredByPinyinFallback
    requestCandidateTranslations()
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
    for view in candidateStack.arrangedSubviews {
      candidateStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    let page = visibleCandidates.prefix(Self.candidatePageSize)
    for (offset, candidate) in page.enumerated() {
      candidateStack.addArrangedSubview(
        makeCandidateButton(
          candidate: candidate, number: offset + 1, index: offset))
    }
    updateExpandControl()

    diagnosticLabel.text = visibleDiagnostic
    diagnosticLabel.accessibilityLabel = visibleDiagnostic.map { "提示：\($0)" }
    diagnosticLabel.isHidden = visibleDiagnostic == nil
    candidateScrollView.isHidden = visibleCandidates.isEmpty || visibleDiagnostic != nil
    candidateEmptySpacer.isHidden = !visibleCandidates.isEmpty || visibleDiagnostic != nil
  }

  private func candidateAnnotation(at index: Int) -> KeyboardCandidateAnnotation {
    let code = visibleCandidateCodes.indices.contains(index) ? visibleCandidateCodes[index] : ""
    let hint = wubiCodeHint(code: code, typed: visiblePreedit)
    return hint.isEmpty ? .none : KeyboardCandidateAnnotation(
      text: hint, accessibilityDescription: "还需输入 \(hint)")
  }

  private func candidateGlosses(at index: Int) -> [String] {
    guard CandidateGlossPreference.enabled, visibleCandidates.indices.contains(index) else { return [] }
    return glosses(word: visibleCandidates[index], offline: visibleCandidateGlosses.indices.contains(index) ? visibleCandidateGlosses[index] : "")
  }

  private func glosses(word: String, offline: String) -> [String] {
    var lines: [String] = []
    if let value = gloss(word: word, language: CandidateTranslationPreference.primary, offline: offline) { lines.append(value) }
    if let secondary = CandidateTranslationPreference.secondary,
       let value = gloss(word: word, language: secondary, offline: "") { lines.append(value) }
    return lines
  }

  private func gloss(word: String, language: CandidateTranslationLanguage, at index: Int) -> String? {
    gloss(word: word, language: language,
          offline: visibleCandidateGlosses.indices.contains(index) ? visibleCandidateGlosses[index] : "")
  }

  private func gloss(word: String, language: CandidateTranslationLanguage, offline: String) -> String? {
    if !CandidateTranslationPreference.needsNetwork(language), !inputScheme.isJapanese,
       !offline.isEmpty, offline != word { return offline }
    guard CandidateTranslationPreference.onlineEnabled else { return nil }
    return translations.gloss(word: word, code: language.code)
  }

  private func candidatePanelAnnotation(code: String, gloss: String, word: String,
                                        typed: String) -> KeyboardCandidateAnnotation {
    let hint = wubiCodeHint(code: code, typed: typed)
    let lines = glosses(word: word, offline: gloss)
    let text = ([hint] + lines).filter { !$0.isEmpty }.joined(separator: "\n")
    guard !text.isEmpty else { return .none }
    let description = ([hint.isEmpty ? "" : "还需输入 \(hint)", lines.isEmpty ? "" : "英文释义：\(lines.joined(separator: "，"))"])
      .filter { !$0.isEmpty }.joined(separator: "，")
    return KeyboardCandidateAnnotation(text: text, accessibilityDescription: description)
  }

  private func requestCandidateTranslations() {
    guard CandidateGlossPreference.enabled, CandidateTranslationPreference.onlineEnabled,
          hasFullAccess, !inputScheme.isJapanese, !session.isInLocalMode,
          !visibleCandidates.isEmpty else { translations.cancel(); return }
    var codes = [CandidateTranslationPreference.primary.code]
    if let secondary = CandidateTranslationPreference.secondary { codes.append(secondary.code) }
    translations.refresh(words: Array(visibleCandidates.prefix(Self.candidatePageSize)), codes: codes)
  }

  private func wubiCodeHint(code: String, typed: String) -> String {
    guard inputScheme == .wubi, !session.isInLocalMode,
          WubiCodeHintPreference.isEnabled else { return "" }
    return WubiCodeHintPreference.hint(
      code: code, typed: typed,
      answeredByPinyinFallback: visibleCandidatesAnsweredByPinyinFallback)
  }

  private func refreshCandidatePanelAnnotations() {
    guard let panel = candidatePanel, let generation = candidatePanelGeneration else { return }
    guard let value = try? session.allCandidates(),
          let snapshot = try? CandidatePanelSnapshot.decode(value),
          snapshot.generation == generation else {
      closeKeyboardPicker()
      return
    }
    panel.updateAnnotations(snapshot.entries.map {
      candidatePanelAnnotation(code: $0.code, gloss: $0.translation, word: $0.text,
                               typed: snapshot.preedit)
    })
  }

  /// Candidate gloss lookup is session-free disk work. Copy the complete candidate generation on
  /// the keyboard thread, then resolve it off-thread and apply only if the same composition is
  /// still visible. A failed or missing dictionary is intentionally silent.
  private func scheduleCandidateGlosses() {
    guard CandidateGlossPreference.enabled, !inputScheme.isJapanese,
          !session.isInLocalMode, !visibleCandidates.isEmpty,
          let resources = session.candidateGlossResources(), !resources.isEmpty else {
      let hadVisibleGlosses = !visibleCandidateGlosses.isEmpty
      if candidateGlossRequestedGeneration != nil || hadVisibleGlosses {
        candidateGlossEpoch &+= 1
        candidateGlossRequestedGeneration = nil
        visibleCandidateGlosses = []
        if hadVisibleGlosses { renderCandidateStrip() }
      }
      refreshCandidatePanelAnnotations()
      return
    }
    do {
      let allCandidates = try session.allCandidates()
      guard let value = allCandidates["generation"] as? NSNumber else { return }
      let generation = value.uint64Value
      if candidateGlossRequestedGeneration == generation { return }
      guard let candidates = allCandidates["candidates"] as? [[String: Any]] else { return }
      let request = try CandidateGlossModel.request(generation: generation, candidates: candidates)
      candidateGlossRequestedGeneration = generation
      let targetEpoch = candidateGlossEpoch
      let targetResources = resources
      let queue = candidateGlossQueue
      let applyOnMain: (UInt64, Data) -> Void = { [weak self] responseGeneration, translations in
        DispatchQueue.main.async { [weak self] in
          guard let self, self.candidateGlossEpoch == targetEpoch,
                CandidateGlossPreference.enabled,
                self.candidateGlossRequestedGeneration == responseGeneration else { return }
          do {
            let applied = try self.session.applyTranslations(
              generation: responseGeneration, translations: translations)
            guard applied["applied"] as? Bool == true else { return }
            let snapshot = try self.session.snapshot(from: applied)
            self.render(snapshot)
          } catch {
            // Optional display metadata must never interrupt input.
          }
        }
      }
      queue.async {
        do {
          let response = try MetasequoiaInputSessionBridge.candidateGlosses(
            request: request, resources: targetResources)
          let decoded = try CandidateGlossModel.decode(response)
          guard decoded.generation == generation else { return }
          applyOnMain(decoded.generation, decoded.translations)
        } catch {
          // Optional display metadata must never interrupt input.
        }
      }
    } catch {
      // Optional display metadata must never interrupt input.
    }
  }

  /// The source logo is white-backed and has no alpha, so use its luminance as a mask before
  /// tinting it with the current skin accent. This prevents a white square on dark skins.
  private static func brandTemplate() -> UIImage? {
    guard let path = Bundle(for: KeyboardViewController.self).path(forResource: "KeyboardBrand", ofType: "png"),
          let source = UIImage(contentsOfFile: path),
          let cgImage = source.cgImage else { return nil }
    let input = CIImage(cgImage: cgImage)
    guard let inverted = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: input])?.outputImage,
          let masked = CIFilter(name: "CIMaskToAlpha", parameters: [kCIInputImageKey: inverted])?.outputImage,
          let output = CIContext().createCGImage(masked, from: masked.extent) else { return nil }
    return UIImage(cgImage: output).withRenderingMode(.alwaysTemplate)
  }

  // A touch keyboard has no number row to answer with, so the ordinal is spoken rather than drawn;
  // the index is the engine position the chip selects. The expand panel already showed bare text.
  private func makeCandidateButton(candidate: String, number: Int, index: Int) -> UIButton {
    let display = chineseOutput(candidate)
    let annotation = candidateAnnotation(at: index)
    let glosses = candidateGlosses(at: index)
    var configuration = UIButton.Configuration.plain()
    configuration.title = display
    if !annotation.text.isEmpty || !glosses.isEmpty {
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineBreakMode = .byTruncatingTail
      var title = AttributedString(display, attributes: AttributeContainer([
        .font: UIFont.preferredFont(forTextStyle: .body), .paragraphStyle: paragraph,
      ]))
      if !annotation.text.isEmpty {
        title += AttributedString(" " + annotation.text, attributes: AttributeContainer([
          .font: UIFont.preferredFont(forTextStyle: .caption1), .paragraphStyle: paragraph,
          .foregroundColor: KeyboardSkinPreference.selected.keyForeground.withAlphaComponent(0.55),
        ]))
      }
      for gloss in glosses {
        title += AttributedString("\n" + gloss, attributes: AttributeContainer([
          .font: UIFont.preferredFont(forTextStyle: .caption2), .paragraphStyle: paragraph,
          .foregroundColor: KeyboardSkinPreference.selected.keyForeground.withAlphaComponent(0.55),
        ]))
      }
      configuration.attributedTitle = title
    }
    // Candidate chips live in a horizontal scroll view. Keep each title on a
    // single line and let the row scroll to wider candidates instead of
    // compressing a chip into a second line.
    configuration.titleLineBreakMode = .byTruncatingTail
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
        // Handwriting candidates are not Engine candidates, so their visible index must route back
        // through the handwriting panel rather than through session.selectCandidate.
        if self.inputScheme == .handwriting, !self.handwritingResults.isEmpty {
          if self.handwriting.use(at: index) { self.handwritingResults = [] }
          return
        }
        self.render(self.session.selectCandidate(at: UInt(index)))
      })
    button.titleLabel?.numberOfLines = 1 + glosses.count
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    button.accessibilityLabel = annotation.accessibilityDescription.isEmpty
      ? "候选词 \(number)：\(display)"
      : "候选词 \(number)：\(display)，\(annotation.accessibilityDescription)"
    if !glosses.isEmpty { button.accessibilityLabel? += "，释义 " + glosses.joined(separator: "，") }
    button.accessibilityIdentifier = "candidate-\(number)"
    if isChineseMode && !inputScheme.isJapanese && !session.isInLocalMode {
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
    let extra = Self.compositionRowHeight + Self.glossHeight(lines: glossLineCount)
    // Handwriting shares the candidate strip and therefore the common portrait height. Landscape
    // keeps a small allowance so the writing canvas remains usable in the shorter keyboard.
    let height: CGFloat = handwriting.isHidden || !landscape
      ? (landscape ? 216 + extra : 260 + extra)
      : 240 + extra
    let adjustedHeight = height + sharedKeyboardHeightAdjustment
    if keyboardHeightConstraint?.constant != adjustedHeight { keyboardHeightConstraint?.constant = adjustedHeight }
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
      voiceEnabled: KeyboardLayoutPreference.voiceShortcutEnabled,
      onKeySpacing: { [weak self] spacing in
        KeyboardLayoutPreference.keySpacing = spacing
        self?.applyLayoutPreferences()
        self?.persistTouchKeyboardGeometry()
      },
      onRowSpacing: { [weak self] spacing in
        KeyboardLayoutPreference.rowSpacing = spacing
        self?.applyLayoutPreferences()
        self?.persistTouchKeyboardGeometry()
      },
      onHeight: { [weak self] adjustment in
        KeyboardLayoutPreference.heightAdjustment = adjustment
        self?.sharedKeyboardHeightAdjustment = CGFloat(adjustment)
        self?.updatePreferredKeyboardHeight()
        self?.persistTouchKeyboardGeometry()
      },
      // Only the shortcut bar changes shape with this setting, so it is refreshed on its own. Going
      // through updateKeyboardLayout would rebuild the keys and drop a composition in progress.
      onVoice: { [weak self] enabled in
        KeyboardLayoutPreference.voiceShortcutEnabled = enabled
        self?.updateShortcutButtons()
        self?.persistTouchKeyboardGeometry()
      },
      onReset: { [weak self] in
        guard let self else { return }
        KeyboardLayoutPreference.resetToDefaults()
        sharedKeyboardHeightAdjustment = 0
        applyLayoutPreferences()
        updatePreferredKeyboardHeight()
        updateShortcutButtons()
        _ = session.resetTouchKeyboardGeometry()
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

  private func persistTouchKeyboardGeometry() {
    _ = session.setTouchKeyboardGeometry(
      keySpacing: KeyboardLayoutPreference.keySpacing,
      rowSpacing: KeyboardLayoutPreference.rowSpacing,
      heightAdjustment: KeyboardLayoutPreference.heightAdjustment,
      voiceEnabled: KeyboardLayoutPreference.voiceShortcutEnabled)
  }

  private func showMorePicker() {
    closeKeyboardService()
    closeKeyboardPicker()
    updateShortcutButtons()
    moreToolsPage = .root
    if moreTools.isEmpty { moreTools = makeToolSections() }
    let picker = KeyboardMorePickerView(sections: moreTools,
      onClose: { [weak self] in self?.closeKeyboardPicker() })
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

  private func showEmojiPicker() {
    closeKeyboardService()
    closeKeyboardPicker()
    guard let resources = session.candidateGlossResources(), !resources.isEmpty else {
      showDiagnostic("表情目录尚未就绪")
      return
    }
    // Browsing is a separate input surface. Finish any pinyin first so selecting an Emoji cannot
    // reorder it ahead of text that was already composed.
    render(session.finishComposition())
    let picker = KeyboardEmojiPickerView(
      resources: resources,
      onInsert: { [weak self] emoji in self?.insertOwnText(emoji, source: .local) },
      onDelete: { [weak self] in self?.deleteOwnBackward() },
      onClose: { [weak self] in self?.closeKeyboardPicker() })
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
    if let panel = candidatePanel {
      panel.removeFromSuperview()
      candidatePanel = nil
      candidatePanelGeneration = nil
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
    if let picker = emojiPicker {
      picker.removeFromSuperview()
      emojiPicker = nil
      UIAccessibility.post(notification: .screenChanged, argument: emojiShortcut)
    }
    if let picker = skinPicker {
      picker.removeFromSuperview()
      skinPicker = nil
      UIAccessibility.post(notification: .screenChanged, argument: skinShortcut)
    }
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
