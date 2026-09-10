import AppKit
import SwiftUI

@MainActor
final class MacAISkinGalleryModel: ObservableObject {
  @Published var prompt = ""
  @Published private(set) var proposals: [AISkinProposal] = []
  @Published private(set) var busy = false
  @Published private(set) var completed = 0
  @Published var message: String?
  let accountID: String
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private var pending: Task<Void, Never>?
  private var generation = 0
  init(accountID: String, client: BackendAccountClient = BackendAccountClient(), account: BackendAccountSession = .shared) {
    self.accountID = accountID; self.client = client; self.account = account
  }
  func generate(random: Bool = false) {
    guard !busy else { return }
    if random { prompt = AISkinService.drawPrompt() }
    let request = prompt
    generation += 1; let version = generation
    proposals = []; message = nil; completed = 0; busy = true
    pending = Task {
      defer { if version == generation { busy = false; pending = nil } }
      do {
        let result = try await AISkinService.generate(request, client: client, account: account, expectedUserID: accountID) { [weak self] count in
          guard let self, self.generation == version else { return }
          self.completed = count
        }
        try Task.checkCancellation()
        guard generation == version else { return }
        proposals = result
      } catch {
        if generation == version, !Task.isCancelled { message = error.localizedDescription }
      }
    }
  }
  func cancel() { generation += 1; pending?.cancel(); pending = nil; busy = false; proposals = []; completed = 0 }
}

struct MacAISkinGalleryView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: MacAISkinGalleryModel
  @State private var selected: AISkinProposal?
  init(accountID: String) { _model = StateObject(wrappedValue: MacAISkinGalleryModel(accountID: accountID)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("AI 图片皮肤").font(.title2)
      Text("生成三套原创插画与配色。macOS 将插画裁切为候选窗顶部横幅，保留原生候选布局。").foregroundStyle(.secondary)
      TextField("描述想要的主题（最多 500 字）", text: $model.prompt).disabled(model.busy)
      HStack {
        Button("生成三套") { model.generate() }.disabled(model.busy || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.prompt.count > 500)
        Button("随机抽取三套") { model.generate(random: true) }.disabled(model.busy)
        if model.busy { Button("取消生成") { model.cancel() } }
      }
      if model.busy { ProgressView("已完成插画 \(model.completed)/3", value: Double(model.completed), total: 3) }
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(model.proposals) { proposal in
            VStack(alignment: .leading, spacing: 6) {
              if let photo = proposal.design.photo, let image = NSImage(data: photo) {
                Image(nsImage: image).resizable().aspectRatio(3, contentMode: .fit).frame(maxHeight: 160)
              }
              Text(proposal.name).font(.headline)
              Text(proposal.description)
              Button("预览、编辑与分享…") { selected = proposal }
            }.padding(12).background(Color.primary.opacity(0.04)).cornerRadius(8)
          }
        }
      }
      if let message = model.message { Text(message).foregroundStyle(.secondary) }
      HStack { Spacer(); Button("关闭") { model.cancel(); dismiss() } }
    }.padding(24).frame(width: 620, height: 700)
    .onDisappear { model.cancel() }
    .sheet(item: $selected) { proposal in MacAISkinReviewView(accountID: model.accountID, proposal: proposal) }
  }
}

private struct MacAISkinReviewView: View {
  @Environment(\.dismiss) private var dismiss
  let accountID: String
  let proposal: AISkinProposal
  @StateObject private var editor = MacSkinEditorModel()
  @State private var publication: SkinPublicationSource?
  var body: some View {
    VStack(spacing: 8) {
      MacSkinEditorView(model: editor, draft: editor.draft, accountID: accountID)
      HStack {
        Button("分享原始生成方案…") {
          publication = SkinPublicationSource(name: proposal.name, design: proposal.design)
        }
        Spacer()
        Button("关闭") { dismiss() }
      }.padding(.horizontal, 24).padding(.bottom, 16)
    }.frame(width: 620, height: 740)
    .task {
      do {
        _ = try await BackendAccountSession.shared.credentials(matchingUserID: accountID)
        try Task.checkCancellation()
        let palette = try GeneratedCandidateSkin.community(name: proposal.name, design: proposal.design)
        let data = try JSONEncoder().encode(palette)
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try editor.load(values)
        try editor.setArtwork(proposal.design.photo)
        editor.preview()
      } catch { editor.message = error.localizedDescription }
    }
    .onDisappear { editor.close() }
    .sheet(item: $publication) { source in MacSkinPublicationView(accountID: accountID, source: source) }
  }
}
