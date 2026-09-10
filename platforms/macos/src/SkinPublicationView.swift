import SwiftUI

struct SkinPublicationSource: Identifiable {
  let id = UUID()
  let name: String
  let design: CustomKeyboardSkin
}

extension GeneratedCandidateSkin {
  func communityDesign(dark: Bool) throws -> CustomKeyboardSkin {
    let palette = dark ? self.dark : light
    func rgb(_ color: String) throws -> UInt32 {
      guard color.count == 7, color.first == "#", let value = UInt32(color.dropFirst(), radix: 16) else {
        throw ServiceFailure(message: "配色无效，请重新生成。")
      }
      return value
    }
    var design = CustomKeyboardSkin()
    design.background = try rgb(palette.surface)
    design.keyBackground = try rgb(palette.hover)
    design.keyForeground = try rgb(palette.text)
    design.accent = try rgb(palette.accent)
    design.actionBackground = try rgb(palette.selected)
    design.customBorderColor = try rgb(palette.border)
    return design
  }
}

@MainActor
final class MacSkinPublicationModel: ObservableObject {
  @Published var name: String
  @Published var description = ""
  @Published var busy = false
  @Published var publishedID: UUID?
  @Published var message: String?
  let design: CustomKeyboardSkin
  private let accountID: String
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private var attempted: BackendAccountClient.SkinPublication?
  private var pending: Task<Void, Never>?
  private var generation = 0
  init(accountID: String, source: SkinPublicationSource, client: BackendAccountClient = BackendAccountClient(), account: BackendAccountSession = .shared) {
    self.accountID = accountID; name = source.name; design = source.design.normalized; self.client = client; self.account = account
  }
  private var payload: BackendAccountClient.SkinPublication {
    .init(id: attempted?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
          description: description.trimmingCharacters(in: .whitespacesAndNewlines), design: design)
  }
  var canPublish: Bool { !busy && publishedID == nil && payload.valid }
  func publish() {
    guard canPublish else { return }
    let value = payload
    // Same payload retains its UUID after an ambiguous network failure. Editing
    // creates a new publication because the server does not overwrite designs.
    let outgoing = attempted == nil || attempted == value ? value : .init(id: UUID(), name: value.name, description: value.description, design: value.design)
    attempted = outgoing; busy = true; message = nil
    generation += 1; let version = generation
    pending = Task {
      defer { if version == generation { busy = false; pending = nil } }
      do {
        let identity = try await account.credentials(matchingUserID: accountID)
        try Task.checkCancellation()
        let id: UUID
        do { id = try await client.publishCommunitySkin(outgoing, token: identity.token) }
        catch let error as BackendAccountClient.Failure where error.status == 401 {
          let fresh = try await account.credentials(retrying: identity.token, matchingUserID: accountID)
          try Task.checkCancellation()
          id = try await client.publishCommunitySkin(outgoing, token: fresh.token)
        }
        _ = try await account.credentials(matchingUserID: accountID)
        try Task.checkCancellation()
        guard version == generation else { return }
        publishedID = id; message = "已公开发布，可在社区查看或下架。"
      } catch is CancellationError {} catch {
        if version == generation && !Task.isCancelled { message = error.localizedDescription }
      }
    }
  }
  func close() { generation += 1; pending?.cancel(); pending = nil; busy = false }
}

struct MacSkinPublicationView: View {
  @StateObject private var model: MacSkinPublicationModel
  @StateObject private var draft = MacGeneratedSkinDraft()
  @State private var previewError: String?
  @State private var confirming = false
  @Environment(\.dismiss) private var dismiss
  init(accountID: String, source: SkinPublicationSource) {
    _model = StateObject(wrappedValue: MacSkinPublicationModel(accountID: accountID, source: source))
  }
  var body: some View {
    ScrollView { VStack(alignment: .leading, spacing: 12) {
      HStack { Text("分享配色到社区").font(.title2); Spacer(); Button("关闭") { dismiss() } }
      Text("社区作品包含一套配色。下方是其他 macOS 用户下载后看到的候选窗效果，移动设备会将其用于键盘。发布后名称、说明、配色和作者昵称将公开。")
        .font(.footnote).foregroundStyle(.secondary)
      TextField("作品名称（最多 32 字符）", text: $model.name).disabled(model.busy || model.publishedID != nil)
      TextField("说明（最多 280 字符）", text: $model.description).disabled(model.busy || model.publishedID != nil)
      if let directory = draft.directory {
        GeneratedSkinNativePreview(directory: directory, dark: false).id(directory).frame(height: model.design.photo == nil ? 440 : 600)
      }
      if let message = previewError ?? model.message { Text(message).foregroundStyle(.secondary) }
      Button("公开发布…") { confirming = true }.disabled(!model.canPublish || draft.directory == nil)
      if model.busy { ProgressView().controlSize(.small) }
    }.padding(20) }.frame(width: 600, height: 680)
      .onAppear {
        do {
          let skin = try GeneratedCandidateSkin.community(name: model.name, design: model.design)
          try draft.prepare(String(decoding: JSONEncoder().encode(skin), as: UTF8.self), artwork: model.design.photo)
        } catch { previewError = error.localizedDescription }
      }
      .onDisappear { model.close(); draft.clear() }
      .alert("公开发布这款配色？", isPresented: $confirming) {
        Button("取消", role: .cancel) {}
        Button("发布") { model.publish() }
      } message: { Text("其他用户将能浏览和下载“\(model.name)”。这不会改变你当前使用的皮肤。") }
  }
}
