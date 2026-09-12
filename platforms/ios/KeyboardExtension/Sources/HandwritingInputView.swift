import UIKit
#if canImport(MLKitDigitalInkRecognition)
@preconcurrency import MLKitDigitalInkRecognition
@preconcurrency import MLKitCommon
#endif

private final class HandwritingDownloadFailure: @unchecked Sendable {
  private let lock = NSLock()
  private var storedError: Error?
  func record(_ error: Error) { lock.lock(); defer { lock.unlock() }; storedError = error }
  var error: Error? { lock.lock(); defer { lock.unlock() }; return storedError }
}

/// 手写识别。不含 Digital Ink SDK 的构建里，这里报告功能不可用。
///
/// The SDK has no arm64 simulator slice, so a simulator build on Apple Silicon leaves it out (see
/// the Podfile). Everything above this type -- the canvas, the panel, the scheme -- is unchanged
/// either way; the panel already drives itself off `isReady`, so a build without the SDK behaves
/// like one whose model was never downloaded, and says so when asked to download.
@MainActor
final class HandwritingRecognizer {
#if canImport(MLKitDigitalInkRecognition)
  init() {
    // ML Kit creates its download session while checking model availability, before download().
    _ = HandwritingDownloadSession.configureSharedContainer(InputSchemePreference.appGroupIdentifier)
  }
  private lazy var model = DigitalInkRecognitionModel(modelIdentifier:
    .zhHaniCn)
  private var engine: DigitalInkRecognizer?
  func release() { engine = nil }
  var isReady: Bool { ModelManager.modelManager().isModelDownloaded(model) }

  func download(onProgress: (Double) -> Void) async throws {
    if isReady { return }
    guard HandwritingDownloadSession.configureSharedContainer(InputSchemePreference.appGroupIdentifier) else {
      throw NSError(domain: "MSIMEHandwriting", code: 4,
        userInfo: [NSLocalizedDescriptionKey: "无法访问手写模型共享目录，请检查完全访问权限"])
    }
    let failure = HandwritingDownloadFailure()
    let languageTag = model.modelIdentifier.languageTag
    let observer = NotificationCenter.default.addObserver(forName: .mlkitModelDownloadDidFail,
      object: nil, queue: nil) { notification in
      guard let remote = notification.userInfo?[ModelDownloadUserInfoKey.remoteModel.rawValue] as? DigitalInkRecognitionModel,
        remote.modelIdentifier.languageTag == languageTag else { return }
      failure.record(notification.userInfo?[ModelDownloadUserInfoKey.error.rawValue] as? Error
        ?? NSError(domain: "MSIMEHandwriting", code: 3))
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    let progress = ModelManager.modelManager().download(model, conditions:
      ModelDownloadConditions(allowsCellularAccess: true, allowsBackgroundDownloading: false))
    defer { if !isReady { progress.cancel() } }
    for _ in 0..<600 {
      try Task.checkCancellation()
      if isReady { return }
      if let error = failure.error { throw error }
      onProgress(progress.fractionCompleted)
      if progress.isCancelled { throw CancellationError() }
      try await Task.sleep(nanoseconds: 300_000_000)
    }
    throw NSError(domain: "MSIMEHandwriting", code: 2,
      userInfo: [NSLocalizedDescriptionKey: "模型下载未完成，请检查网络后重试"])
  }

  func recognize(_ strokes: [[CGPoint]], width: Double, height: Double) async throws -> [String] {
    try Task.checkCancellation()
    guard isReady else {
      throw NSError(domain: "MSIMEHandwriting", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "请先下载中文手写模型"])
    }
    let ink = Ink(strokes: strokes.map { Stroke(points: $0.map { StrokePoint(x: Float($0.x), y: Float($0.y)) }) })
    let context = DigitalInkRecognitionContext(preContext: "", writingArea:
      WritingArea(width: Float(width), height: Float(height)))
    if engine == nil { engine = DigitalInkRecognizer.digitalInkRecognizer(options: DigitalInkRecognizerOptions(model: model)) }
    let recognizer = engine!
    let words: [String] = try await withCheckedThrowingContinuation { continuation in
      recognizer.recognize(ink: ink, context: context) { result, error in
        if let error { continuation.resume(throwing: error); return }
        var seen = Set<String>()
        continuation.resume(returning: (result?.candidates ?? []).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(12).map { $0 })
      }
    }
    try Task.checkCancellation()
    return words
  }
#else
  private static let unavailable = NSError(domain: "MSIMEHandwriting", code: 5,
    userInfo: [NSLocalizedDescriptionKey: "此版本不含手写识别，请使用真机版本"])

  init() {}
  func release() {}
  var isReady: Bool { false }

  func download(onProgress: (Double) -> Void) async throws { throw Self.unavailable }

  func recognize(_ strokes: [[CGPoint]], width: Double, height: Double) async throws -> [String] {
    throw Self.unavailable
  }
#endif
}

final class HandwritingCanvas: UIView {
  private(set) var strokes: [[CGPoint]] = []
  var onChange: (() -> Void)?
  var onStrokeBegan: (() -> Void)?
  var acceptsInk = true
  private var drawing = false
  private var previousSize = CGSize.zero
  override func layoutSubviews() {
    super.layoutSubviews()
    if previousSize != .zero && previousSize != bounds.size && hasInk { clear() }
    previousSize = bounds.size
  }
  var hasInk: Bool { !strokes.isEmpty }
  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "handwritingCanvas"
    accessibilityLabel = "手写区域"
    accessibilityHint = "用手指书写，停笔后选择上方候选文字"
    isMultipleTouchEnabled = false
    isOpaque = false
    layer.cornerRadius = 10
    clipsToBounds = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func clear() { strokes = []; drawing = false; setNeedsDisplay(); onChange?() }
  func undo() { if !strokes.isEmpty { strokes.removeLast() }; drawing = false; setNeedsDisplay(); onChange?() }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard acceptsInk, strokes.count < 64, let touch = touches.first else { return }
    drawing = true
    strokes.append([touch.location(in: self)])
    onStrokeBegan?()
    setNeedsDisplay()
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard drawing, let touch = touches.first, !strokes.isEmpty else { return }
    for point in (event?.coalescedTouches(for: touch) ?? [touch]).map({ $0.location(in: self) }) {
      guard strokes[strokes.count - 1].count < 512 else { break }
      let bounded = CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
      if let last = strokes.last?.last, hypot(last.x - bounded.x, last.y - bounded.y) < 1 { continue }
      strokes[strokes.count - 1].append(bounded)
    }
    setNeedsDisplay()
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard drawing else { return }; touchesMoved(touches, with: event); drawing = false; onChange?()
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { if drawing { undo() } }
  private func drawInk(_ context: CGContext, color: UIColor, width: CGFloat) {
    context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
    context.setLineWidth(width); context.setLineCap(.round); context.setLineJoin(.round)
    for stroke in strokes {
      guard let first = stroke.first else { continue }
      if stroke.count == 1 { context.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width)); continue }
      context.beginPath(); context.move(to: first)
      for point in stroke.dropFirst() { context.addLine(to: point) }
      context.strokePath()
    }
  }
  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    let skin = KeyboardSkinPreference.selected
    skin.keyBackground.setFill(); context.fill(bounds)
    context.setStrokeColor(skin.accent.withAlphaComponent(0.12).cgColor)
    context.setLineDash(phase: 0, lengths: [4, 4]); context.setLineWidth(1)
    context.move(to: CGPoint(x: bounds.midX, y: 0)); context.addLine(to: CGPoint(x: bounds.midX, y: bounds.height))
    context.move(to: CGPoint(x: 0, y: bounds.midY)); context.addLine(to: CGPoint(x: bounds.width, y: bounds.midY)); context.strokePath()
    context.setLineDash(phase: 0, lengths: [])
    drawInk(context, color: skin.keyForeground, width: 3)
    if strokes.isEmpty {
      let text = "在此手写"
      let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 21), .foregroundColor: skin.keyForeground.withAlphaComponent(0.3)]
      let size = (text as NSString).size(withAttributes: attrs)
      (text as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
  }
  func setTestStrokes(_ values: [[CGPoint]]) { strokes = values; setNeedsDisplay(); onChange?() }
}

final class HandwritingInputView: UIView {
  let canvas = HandwritingCanvas()
  private let candidates = UIStackView()
  private let status = UILabel()
  private var recognizerStorage: HandwritingRecognizer?
  private var recognizer: HandwritingRecognizer {
    if recognizerStorage == nil { recognizerStorage = HandwritingRecognizer() }
    return recognizerStorage!
  }
  private let modelButton = UIButton(type: .system)
  private var downloadTask: Task<Void, Never>?
  var canDownload: () -> Bool = { false }
  func activate() {
    let ready = recognizer.isReady
    modelButton.isEnabled = true
    canvas.acceptsInk = ready
    modelButton.isHidden = ready
    if !ready && downloadTask == nil {
      modelButton.setTitle("下载中文手写模型", for: .normal)
      showStatus(canDownload() ? "首次下载后可离线手写" : "首次下载需在系统设置允许完全访问")
    }
  }
  func deactivate() {
    downloadTask?.cancel()
    clear(); recognizerStorage?.release()
  }
  private func toggleDownload() {
    if let downloadTask {
      downloadTask.cancel(); modelButton.isEnabled = false
      showStatus("正在取消下载…"); return
    }
    guard canDownload() else { showStatus("请在系统键盘设置中允许完全访问，再点下载"); return }
    modelButton.setTitle("取消下载", for: .normal)
    downloadTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.recognizer.download { [weak self] fraction in
          self?.showStatus(fraction > 0 ? "模型下载中 \(Int(fraction * 100))%" : "正在连接模型服务…")
        }
        try Task.checkCancellation()
        self.downloadTask = nil; self.activate(); self.showStatus("在此手写，停笔后选字")
      } catch is CancellationError {
        self.downloadTask = nil; self.activate()
      } catch {
        self.downloadTask = nil; self.activate(); self.showStatus("下载失败，请检查网络后重试")
      }
    }
  }
  private var task: Task<Void, Never>?
  private var revision = UUID()
  private(set) var results: [String] = []
  var onInsert: ((String) -> Void)?
  var onDelete: (() -> Void)?
  var hasInk: Bool { canvas.hasInk }
  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "handwritingInput"
    let column = UIStackView(); column.axis = .vertical; column.spacing = 4
    let scroll = UIScrollView(); scroll.showsHorizontalScrollIndicator = false
    scroll.disableEdgeEffects()
    candidates.axis = .horizontal; candidates.spacing = 8
    status.font = .systemFont(ofSize: 12); status.text = "一次写一个字，停笔后选字"; status.accessibilityIdentifier = "handwritingStatus"
    candidates.addArrangedSubview(status)
    scroll.addSubview(candidates)
    candidates.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      candidates.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      candidates.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      candidates.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      candidates.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      candidates.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
      scroll.heightAnchor.constraint(equalToConstant: 32),
    ])
    column.addArrangedSubview(scroll)
    let row = UIStackView(); row.spacing = 6; row.addArrangedSubview(canvas)
    let tools = UIStackView(); tools.axis = .vertical; tools.spacing = 4; tools.distribution = .fillEqually
    for (title, id, action) in [
      ("撤销", "handwritingUndo", { [weak self] in self?.canvas.undo() }),
      ("清空", "handwritingClear", { [weak self] in self?.clear() }),
      ("⌫", "handwritingDelete", { [weak self] in if self?.hasInk == true { self?.canvas.undo() } else { self?.onDelete?() } }),
    ] {
      let button = KeyboardKeyButton(type: .system); button.setTitle(title, for: .normal)
      button.accessibilityIdentifier = id; button.accessibilityLabel = title == "⌫" ? "删除" : title
      button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
      tools.addArrangedSubview(button)
    }
    tools.widthAnchor.constraint(equalToConstant: 44).isActive = true
    row.addArrangedSubview(tools); column.addArrangedSubview(row)
    addSubview(column); column.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor), column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor)])
    canvas.addSubview(modelButton)
    modelButton.translatesAutoresizingMaskIntoConstraints = false
    modelButton.backgroundColor = .secondarySystemBackground
    modelButton.layer.cornerRadius = 12
    modelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    modelButton.accessibilityIdentifier = "handwritingDownloadModel"
    modelButton.accessibilityHint = "联网下载 Google 中文手写模型，完成后可离线识别"
    modelButton.isHidden = true
    modelButton.addAction(UIAction { [weak self] _ in self?.toggleDownload() }, for: .primaryActionTriggered)
    NSLayoutConstraint.activate([
      modelButton.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
      modelButton.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
      modelButton.widthAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: 0.85),
      modelButton.heightAnchor.constraint(equalToConstant: 44),
    ])
    canvas.onStrokeBegan = { [weak self] in self?.invalidate(); self?.showStatus("书写中…") }
    canvas.onChange = { [weak self] in self?.scheduleRecognition() }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func invalidate() { revision = UUID(); task?.cancel(); task = nil; results = [] }
  func clear() { invalidate(); canvas.clear() }
  private func showStatus(_ text: String) {
    candidates.arrangedSubviews.forEach { candidates.removeArrangedSubview($0); $0.removeFromSuperview() }
    status.text = text; status.textColor = KeyboardSkinPreference.selected.keyForeground
    candidates.addArrangedSubview(status)
  }
  private func scheduleRecognition() {
    invalidate()
    guard hasInk else { showStatus("在此手写，停笔后选字"); if !modelButton.isHidden { activate() }; return }
    showStatus("停笔后识别…")
    let current = revision
    task = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: 550_000_000)
        guard let self, self.revision == current, self.canvas.hasInk else { return }
        self.showStatus("正在识别…")
        let words = try await self.recognizer.recognize(self.canvas.strokes, width: self.canvas.bounds.width, height: self.canvas.bounds.height)
        guard !Task.isCancelled, self.revision == current else { return }
        self.results = words
        self.showStatus(words.isEmpty ? "未识别，请撤销或重新书写" : "")
        for (index, word) in words.enumerated() {
          let button = KeyboardKeyButton(type: .system); button.setTitle(word, for: .normal)
          button.titleLabel?.font = .systemFont(ofSize: 21)
          button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
          button.accessibilityIdentifier = "handwritingCandidate-\(index)"
          button.addAction(UIAction { [weak self] _ in
            guard let self, self.revision == current, self.results.contains(word) else { return }
            self.clear(); self.onInsert?(word)
          }, for: .primaryActionTriggered)
          self.candidates.addArrangedSubview(button)
        }
      } catch is CancellationError { } catch {
        guard let self, self.revision == current else { return }
        self.showStatus("识别失败，请重写后重试")
      }
    }
  }
  @discardableResult func commitFirst() -> Bool {
    guard let word = results.first else { return false }; clear(); onInsert?(word); return true
  }
}
