import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MacSkinEditorModel: ObservableObject {
  static let keys = ["surface", "border", "text", "number", "selected", "hover", "accent"]
  @Published var name = "我的候选窗配色"
  @Published var light: [String: String] = [:]
  @Published var dark: [String: String] = [:]
  @Published var message: String?
  @Published private(set) var artwork: Data?
  @Published private(set) var reviewed: String?
  @Published private(set) var sourceRevision: SkinPackageRevision?
  @Published private(set) var updatedOriginal = false
  let draft: MacGeneratedSkinDraft
  init(draft: MacGeneratedSkinDraft? = nil) { self.draft = draft ?? MacGeneratedSkinDraft() }
  var encoded: String? {
    guard let data = try? JSONSerialization.data(withJSONObject: ["name":name, "light":light, "dark":dark], options: .sortedKeys) else { return nil }
    let text = String(decoding: data, as: UTF8.self)
    guard (try? GeneratedCandidateSkin.parse(text)) != nil else { return nil }
    return text
  }
  private var reviewedArtwork: Data?
  var hasReviewedDesign: Bool { reviewedArtwork == artwork && reviewed != nil && reviewed == encoded && draft.directory != nil }
  var canApply: Bool { hasReviewedDesign && !draft.installed }
  func publication(dark: Bool) throws -> SkinPublicationSource {
    guard hasReviewedDesign, let reviewed else {
      throw ServiceFailure(message: "设计已变化，请更新预览后再分享。")
    }
    let palette = try GeneratedCandidateSkin.parse(reviewed)
    var design = try palette.communityDesign(dark: dark)
    design.photo = try artwork.map(MacSkinArtwork.communityPhoto)
    return SkinPublicationSource(name: palette.name, design: design)
  }
  var canUpdateOriginal: Bool { canApply && !updatedOriginal && sourceRevision != nil }
  func updateOriginal(validate: ((URL) throws -> Void)? = nil, notify: (() -> Void)? = nil) {
    do {
      guard canUpdateOriginal, let sourceRevision else { throw ServiceFailure(message: "请更新预览后再更新原皮肤。") }
      self.sourceRevision = try sourceRevision.replace(using: draft, validate: validate)
      updatedOriginal = true
      if let notify { notify() }
      else if let bridge = try? MacGeneratedSkinDraft.bridge(),
              let selected = bridge.perform(NSSelectorFromString("storedCandidateSkin"))?.takeUnretainedValue() as? String {
        _ = bridge.perform(NSSelectorFromString("setStoredCandidateSkin:"), with: selected)
      }
      message = "已更新原皮肤，保留原来的皮肤 ID。"
    } catch { message = error.localizedDescription }
  }
  func load(_ values: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: values)
    let parsed = try GeneratedCandidateSkin.parse(String(decoding: data, as: UTF8.self))
    name = parsed.name
    light = Dictionary(uniqueKeysWithValues: parsed.light.values)
    dark = Dictionary(uniqueKeysWithValues: parsed.dark.values)
    draft.clear(); reviewed = nil; artwork = nil; reviewedArtwork = nil; message = nil
    sourceRevision = nil; updatedOriginal = false
  }
  func loadPackage(_ directory: URL, read: ((URL) throws -> [String: Any])? = nil) throws {
    var revision = read == nil ? try SkinPackageRevision.capture(directory) : nil
    let values: [String: Any]
    if let read { values = try read(directory) }
    else {
      guard let result = try MacGeneratedSkinDraft.bridge().perform(NSSelectorFromString("editableCandidateSkinDirectory:"), with: directory)?.takeUnretainedValue() as? [String: Any] else {
        throw ServiceFailure(message: "无法读取这套皮肤的配色或插画。")
      }
      values = result
    }
    guard var palette = values["palette"] as? [String: Any], let name = palette["name"] as? String else {
      throw ServiceFailure(message: "皮肤配色不完整。")
    }
    palette["name"] = String(name.prefix(24))
    // Validate artwork before replacing any existing editor state.
    let photo = try (values["artwork"] as? Data).map(MacSkinArtwork.normalize)
    revision?.artworkURL = values["artworkURL"] as? URL
    revision?.artwork = values["artwork"] as? Data
    try revision?.verify()
    try load(palette)
    try setArtwork(photo)
    sourceRevision = revision
    preview()
  }
  func loadCurrent() {
    do {
      guard let values = try MacGeneratedSkinDraft.bridge().perform(NSSelectorFromString("editableCandidateSkin"))?.takeUnretainedValue() as? [String: Any] else {
        throw ServiceFailure(message: "无法读取当前候选窗配色。")
      }
      try load(values); preview()
    } catch { message = error.localizedDescription }
  }
  func preview() {
    do {
      guard let text = encoded else { throw ServiceFailure(message: "请输入 1–24 字名称和有效的六位颜色值。") }
      try draft.prepare(text, artwork: artwork); reviewed = text; reviewedArtwork = artwork; message = nil; updatedOriginal = false
    } catch { reviewed = nil; draft.clear(); message = error.localizedDescription }
  }
  func apply() {
    do {
      guard canApply else { throw ServiceFailure(message: "配色已变化或已保存，请先更新预览。") }
      try draft.apply(); message = "已保存并应用，可在皮肤设置中切换。"
    } catch { message = error.localizedDescription }
  }
  func setArtwork(_ data: Data?) throws {
    artwork = try data.map(MacSkinArtwork.normalize)
    reviewed = nil; reviewedArtwork = nil; draft.clear(); message = nil
  }
  func importArtwork() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false; panel.message = "选择候选窗顶部插画（居中裁切为 3:1）"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= MacSkinArtwork.maximumBytes else {
        throw ServiceFailure(message: "图片超过 10 MB，请选择较小的图片。")
      }
      try setArtwork(Data(contentsOf: url)); preview()
    } catch { message = error.localizedDescription }
  }
  func close() { draft.clear(); reviewed = nil; artwork = nil; reviewedArtwork = nil; sourceRevision = nil; updatedOriginal = false }
}

struct MacSkinEditorView: View {
  @ObservedObject var model: MacSkinEditorModel
  @ObservedObject var draft: MacGeneratedSkinDraft
  var accountID: String? = nil
  @State private var editingDark = false
  @State private var sharing: EditorPublication?
  @State private var sharingTask: Task<Void, Never>?
  @State private var preparingShare = false
  @State private var confirmingUpdate = false
  private struct EditorPublication: Identifiable {
    let id = UUID()
    let accountID: String
    let source: SkinPublicationSource
  }
  private let titles = ["surface":"背景", "border":"边框", "text":"候选文字", "number":"序号", "selected":"选中背景", "hover":"悬停背景", "accent":"强调色"]
  var body: some View {
    ScrollView { VStack(alignment: .leading, spacing: 12) {
      Text("设计候选窗配色").font(.title2)
      Text("调整深浅配色，可选择图片作为候选窗顶部插画。图片会居中裁切为 3:1。更新预览后可保存到本机，或登录后主动分享到社区。")
        .font(.footnote).foregroundStyle(.secondary)
      TextField("名称（最多 24 字）", text: $model.name)
      Toggle("编辑深色配色", isOn: $editingDark)
      ForEach(MacSkinEditorModel.keys, id: \.self) { key in
        ColorPicker(titles[key] ?? key, selection: binding(key), supportsOpacity: false)
      }
      HStack {
        Button("选择插画…") { model.importArtwork() }
        if model.artwork != nil { Button("移除插画") { try? model.setArtwork(nil); model.preview() } }
      }
      HStack {
        Button("从当前皮肤读取配色") { model.loadCurrent() }
        Button("更新预览") { model.preview() }.disabled(model.encoded == nil)
      }
      if let directory = draft.directory {
        if model.reviewed != model.encoded { Text("配色已变化，请更新预览。") }
        GeneratedSkinNativePreview(directory: directory, dark: editingDark).id(directory).frame(height: model.artwork == nil ? 440 : 600)
        if model.sourceRevision != nil {
          Button("更新原皮肤…") { confirmingUpdate = true }.disabled(!model.canUpdateOriginal)
        }
        Button("保存新皮肤并应用") { model.apply() }.disabled(!model.canApply)
        Button(editingDark ? "分享深色设计…" : "分享浅色设计…") { prepareShare() }
          .disabled(!model.hasReviewedDesign || preparingShare)
        Text("社区使用单套配色；分享当前预览的深色或浅色设计及插画，发布前可再次确认。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let message = model.message { Text(message).foregroundStyle(.secondary) }
    }.padding(24) }.frame(minWidth: 540, minHeight: 540)
    .confirmationDialog("用当前预览更新原皮肤？", isPresented: $confirmingUpdate, titleVisibility: .visible) {
      Button("更新原皮肤") { model.updateOriginal() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("原皮肤将使用当前预览的名称、配色、插画和候选窗样式，皮肤 ID 保持不变。")
    }
    .sheet(item: $sharing) { item in MacSkinPublicationView(accountID: item.accountID, source: item.source) }
    .onDisappear { sharingTask?.cancel(); sharingTask = nil; preparingShare = false }
  }
  private func prepareShare() {
    do {
      // Freeze exactly the reviewed appearance before the asynchronous account lookup.
      let source = try model.publication(dark: editingDark)
      preparingShare = true
      sharingTask = Task { @MainActor in
        defer { preparingShare = false; sharingTask = nil }
        do {
          let identity = try await BackendAccountSession.shared.credentials(matchingUserID: accountID)
          try Task.checkCancellation()
          sharing = EditorPublication(accountID: identity.userID, source: source)
        } catch {
          if !Task.isCancelled { model.message = "无法打开分享，请先在账号窗口登录。\n" + error.localizedDescription }
        }
      }
    } catch { model.message = error.localizedDescription }
  }
  private func binding(_ key: String) -> Binding<Color> {
    Binding(get: {
      let value = UInt32(((editingDark ? model.dark[key] : model.light[key]) ?? "#000000").dropFirst(), radix: 16) ?? 0
      return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }, set: { value in
      guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
      let text = String(format: "#%02X%02X%02X", Int((min(1, max(0, color.redComponent)) * 255).rounded()), Int((min(1, max(0, color.greenComponent)) * 255).rounded()), Int((min(1, max(0, color.blueComponent)) * 255).rounded()))
      if editingDark { model.dark[key] = text } else { model.light[key] = text }
    })
  }
}

@MainActor
final class MacSkinEditorWindow: NSWindowController, NSWindowDelegate {
  static let shared = MacSkinEditorWindow()
  private static var packageWindows: [String: MacSkinEditorWindow] = [:]
  private var packageID: String?
  static func showPackage(_ id: String) {
    if let existing = packageWindows[id] {
      existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
      return
    }
    let controller = MacSkinEditorWindow()
    do {
      guard let root = try MacGeneratedSkinDraft.bridge().perform(NSSelectorFromString("candidateSkinsDirectory"))?.takeUnretainedValue() as? URL,
            !id.isEmpty, !id.contains("/"), !id.contains("\\"), id != ".", id != ".." else {
        throw ServiceFailure(message: "皮肤目录无效。")
      }
      try controller.model.loadPackage(root.appendingPathComponent(id))
    } catch { controller.model.message = error.localizedDescription }
    controller.packageID = id
    controller.window?.title = "编辑已保存皮肤"
    controller.window?.contentView = NSHostingView(rootView: MacSkinEditorView(model: controller.model, draft: controller.model.draft))
    packageWindows[id] = controller
    controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  private let model = MacSkinEditorModel()
  private init() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 740),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = "设计候选窗配色"; window.isReleasedWhenClosed = false; window.delegate = self; window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func showEditor() {
    if window?.isVisible != true {
      model.loadCurrent()
      window?.contentView = NSHostingView(rootView: MacSkinEditorView(model: model, draft: model.draft))
    }
    showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  func windowWillClose(_ notification: Notification) {
    window?.contentView = nil; model.close()
    if let packageID { Self.packageWindows.removeValue(forKey: packageID) }
  }
}

@_cdecl("MSIMEShowSkinEditor")
func showSkinEditor() { Task { @MainActor in MacSkinEditorWindow.shared.showEditor() } }

@_cdecl("MSIMEEditSavedSkin")
func editSavedSkin(_ id: UnsafePointer<CChar>?) {
  guard let id else { return }
  let value = String(cString: id)
  Task { @MainActor in MacSkinEditorWindow.showPackage(value) }
}
