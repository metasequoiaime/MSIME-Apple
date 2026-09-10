import AppKit
import SwiftUI
import Darwin

struct GeneratedCandidateSkin: Codable {
  struct Palette: Codable {
    let surface, border, text, number, selected, hover, accent: String
    var values: [(String, String)] { [("surface",surface),("border",border),("text",text),("number",number),("selected",selected),("hover",hover),("accent",accent)] }
  }
  let name: String
  let light, dark: Palette
  static let instruction = """
  为 macOS 输入法候选窗口设计深浅两套配色。仅返回 JSON，格式为 {"name":"名称","light":{"surface":"#RRGGBB","border":"#RRGGBB","text":"#RRGGBB","number":"#RRGGBB","selected":"#RRGGBB","hover":"#RRGGBB","accent":"#RRGGBB"},"dark":{相同字段}}。名称不超过24字，每个颜色必须为六位十六进制。文字与背景应具有清晰对比。不要添加图片、路径、代码或其他字段。
  """
  static func parse(_ text: String) throws -> Self {
    guard text.utf8.count <= 16000 else { throw ServiceFailure(message: "生成的皮肤过大，请重试。") }
    var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if json.hasPrefix("```json\n"), json.hasSuffix("```") { json = String(json.dropFirst(8).dropLast(3)) }
    let skin = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    guard !skin.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, skin.name.count <= 24,
          skin.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
          (skin.light.values + skin.dark.values).allSatisfy({ pair in
            pair.1.utf8.count == 7 && pair.1.first == "#" && pair.1.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit }
          }) else { throw ServiceFailure(message: "生成的名称或配色无效，请重试。") }
    return skin
  }
  func manifest(id: UUID, artwork: Bool = false) -> String {
    let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    var text = """
    schema_version = 1
    id = "\(id.uuidString.lowercased())"
    name = "\(escaped)"
    version = "1.0.0"
    base = "fluent"
    \(artwork ? "preview = \"artwork.png\"" : "")
    [supports]
    layouts = ["horizontal", "vertical"]
    themes = ["light", "dark"]
    [candidate_window]
    min_width_dip = \(artwork ? 240 : 0)
    [candidate_window.decoration]
    top_inset_dip = \(artwork ? 80 : 0)
    width_dip = \(artwork ? 240 : 0)
    """
    for (mode, palette) in [("light",light),("dark",dark)] {
      text += "\n[candidate.\(mode)]\n"
      text += palette.values.map { "\($0.0) = \"\($0.1)\"" }.joined(separator: "\n") + "\n"
    }
    return text
  }
}

@MainActor
final class MacGeneratedSkinDraft: ObservableObject {
  @Published var directory: URL?
  @Published var name = ""
  private var root: URL?
  private var manifest: Data?
  private var artwork: Data?
  @Published private(set) var installed = false
  private let validation: (URL) throws -> Void
  private let destination: () throws -> URL
  private let select: (String) throws -> Void
  init(validation: ((URL) throws -> Void)? = nil,
       destination: (() throws -> URL)? = nil,
       select: ((String) throws -> Void)? = nil) {
    self.validation = validation ?? { try Self.validate($0) }
    self.destination = destination ?? {
      guard let root = try Self.bridge().perform(NSSelectorFromString("candidateSkinsDirectory"))?.takeUnretainedValue() as? URL else { throw ServiceFailure(message: "无法打开皮肤目录。") }
      return root
    }
    self.select = select ?? { _ = try Self.bridge().perform(NSSelectorFromString("setStoredCandidateSkin:"), with: $0) }
  }
  static func bridge() throws -> NSObject.Type {
    guard let type = NSClassFromString("MetasequoiaPreferencesWindowController") as? NSObject.Type else { throw ServiceFailure(message: "无法访问候选窗皮肤。") }
    return type
  }
  static func validate(_ directory: URL) throws {
    guard let valid = try bridge().perform(NSSelectorFromString("validateCandidateSkinDirectory:"), with: directory)?.takeUnretainedValue() as? NSNumber,
          valid.boolValue else { throw ServiceFailure(message: "候选窗皮肤校验失败，请重新生成。") }
  }
  func prepare(_ text: String, artwork: Data? = nil) throws {
    clear()
    let skin = try GeneratedCandidateSkin.parse(text), id = UUID()
    let picture = try artwork.map(MacSkinArtwork.normalize)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("msime-skin-" + UUID().uuidString)
    let directory = root.appendingPathComponent(id.uuidString.lowercased())
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = Data(skin.manifest(id: id, artwork: picture != nil).utf8)
      try data.write(to: directory.appendingPathComponent("skin.toml"), options: .atomic)
      if let picture { try picture.write(to: directory.appendingPathComponent("artwork.png"), options: .atomic) }
      try validation(directory)
      self.root = root; self.directory = directory; self.manifest = data; self.artwork = picture; name = skin.name
    } catch { try? FileManager.default.removeItem(at: root); throw error }
  }
  func reviewedContents() throws -> (manifest: Data, artwork: Data?) {
    guard let directory, let manifest, !installed,
          try Data(contentsOf: directory.appendingPathComponent("skin.toml")) == manifest else {
      throw ServiceFailure(message: "预览已变化或已保存，请重新生成。")
    }
    if let artwork {
      guard try Data(contentsOf: directory.appendingPathComponent("artwork.png")) == artwork else {
        throw ServiceFailure(message: "预览图片已变化，请重新预览。")
      }
    }
    return (manifest, artwork)
  }
  func apply() throws {
    let contents = try reviewedContents()
    guard let directory else { throw ServiceFailure(message: "请重新预览。") }
    let manifest = contents.manifest, artwork = contents.artwork
    let root = try destination()
    let target = root.appendingPathComponent(directory.lastPathComponent)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // Create a new package, never overwrite another skin or copy unreviewed assets.
    guard mkdir(target.path, 0o700) == 0 else { throw ServiceFailure(message: "皮肤目录已存在或无法创建，请重新生成。") }
    do {
      try manifest.write(to: target.appendingPathComponent("skin.toml"), options: .atomic)
      if let artwork { try artwork.write(to: target.appendingPathComponent("artwork.png"), options: .atomic) }
      try validation(target)
      try select(target.lastPathComponent)
      installed = true
    } catch { try? FileManager.default.removeItem(at: target); throw error }
  }
  func clear() {
    if let root { try? FileManager.default.removeItem(at: root) }
    root = nil; directory = nil; manifest = nil; artwork = nil; name = ""; installed = false
  }
}

struct GeneratedSkinNativePreview: NSViewRepresentable {
  let directory: URL
  let dark: Bool
  func makeNSView(context: Context) -> NSView {
    guard let type = NSClassFromString("MetasequoiaCandidatePreviewView") as? NSView.Type else { return NSView() }
    let view = type.init(frame: .zero)
    _ = view.perform(NSSelectorFromString("setPreviewSkinsRoot:"), with: directory.deletingLastPathComponent().path)
    _ = view.perform(NSSelectorFromString("setPreviewSkinId:"), with: directory.lastPathComponent)
    view.setValue(true, forKey: "showsLayoutShowcase")
    let container = NSView()
    container.addSubview(view)
    NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      view.topAnchor.constraint(equalTo: container.topAnchor), view.widthAnchor.constraint(equalTo: container.widthAnchor)])
    return container
  }
  func updateNSView(_ view: NSView, context: Context) {
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    _ = view.subviews.first?.perform(NSSelectorFromString("reloadPreview"))
  }
}

struct MacSkinGenerationView: View {
  @StateObject private var chat: MacChatModel
  @StateObject private var draft = MacGeneratedSkinDraft()
  @State private var prompt = ""
  @State private var dark = false
  @State private var message: String?
  @State private var saving = false
  @State private var publication: SkinPublicationSource?
  private let accountID: String
  @State private var pending: Task<Void, Never>?
  @Environment(\.dismiss) private var dismiss
  init(accountID: String) { self.accountID = accountID; _chat = StateObject(wrappedValue: MacChatModel(accountID: accountID)) }
  var body: some View {
    ScrollView { VStack(alignment: .leading, spacing: 12) {
      HStack { Text("AI 候选窗皮肤").font(.title2); Spacer(); Button("关闭") { dismiss() } }
      Text("描述喜欢的配色，生成深浅两套候选窗皮肤。点击生成后，描述会经水杉后端交由 EveryAPI 处理。预览后保存到本机并应用。")
        .font(.footnote).foregroundStyle(.secondary)
      Picker("模型", selection: $chat.selectedModel) { ForEach(chat.models) { Text($0.id).tag($0.id) } }.disabled(chat.busy || saving)
      TextEditor(text: $prompt).frame(height: 65).border(Color.secondary.opacity(0.3)).disabled(saving)
      HStack {
        Text("\(prompt.count) / 600").font(.caption)
        Button("生成配色") { draft.clear(); message = nil; chat.generateSkin(description: prompt) }
          .disabled(chat.busy || saving || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.count > 600 || chat.models.isEmpty)
        Button("刷新模型") { chat.load() }.disabled(chat.busy || saving)
        if chat.busy { Button("停止") { chat.stop() }; ProgressView().controlSize(.small) }
      }
      if let directory = draft.directory {
        HStack { Text(draft.name); Spacer(); Toggle("深色预览", isOn: $dark) }
        GeneratedSkinNativePreview(directory: directory, dark: dark).id(directory).frame(height: 440)
        Button("保存到本机并应用") {
          saving = true
          pending = Task { @MainActor in
            defer { saving = false }
            do { try await chat.authorizeOutput(); try Task.checkCancellation(); try draft.apply(); message = "已保存并应用，可在设置的皮肤页切换。" }
            catch is CancellationError {} catch { message = error.localizedDescription }
          }
        }.disabled(saving || draft.installed)
        Button("分享当前配色到社区…") {
          do {
            guard let reply = chat.messages.last, reply.role == "assistant" else { return }
            let skin = try GeneratedCandidateSkin.parse(reply.text)
            publication = SkinPublicationSource(name: skin.name, design: try skin.communityDesign(dark: dark))
          } catch { message = error.localizedDescription }
        }.disabled(saving || chat.busy)
      }
      if let message = message ?? chat.error { Text(message).foregroundStyle(.secondary) }
      Spacer(minLength: 0)
    }.padding(20) }.frame(width: 620, height: 680)
      .sheet(item: $publication) { source in MacSkinPublicationView(accountID: accountID, source: source) }
      .onAppear { chat.load() }
      .onChange(of: chat.messages.last?.id) { _ in
        guard let reply = chat.messages.last, reply.role == "assistant" else { return }
        do { try draft.prepare(reply.text) } catch { message = error.localizedDescription }
      }
      .onChange(of: prompt) { _ in if !chat.messages.isEmpty { chat.clear() }; draft.clear(); message = nil }
      .onChange(of: chat.selectedModel) { _ in draft.clear(); message = nil }
      .onDisappear { pending?.cancel(); chat.close(); draft.clear() }
  }
}
