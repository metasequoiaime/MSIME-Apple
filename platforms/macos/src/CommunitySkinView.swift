import AppKit
import SwiftUI

extension GeneratedCandidateSkin {
  static func community(name: String, design: CustomKeyboardSkin) throws -> Self {
    let value = design.normalized
    func hex(_ color: UInt32) -> String { String(format: "#%06X", color) }
    // The community's single keyboard palette maps to both native appearances.
    // Native selection contrast and layout remain owned by the candidate renderer.
    let palette: [String: String] = ["surface": hex(value.background), "border": hex(value.customBorderColor ?? value.keyBackground),
      "text": hex(value.keyForeground), "number": hex(value.accent), "selected": hex(value.actionBackground),
      "hover": hex(value.keyBackground), "accent": hex(value.accent)]
    let data = try JSONSerialization.data(withJSONObject: ["name": String(name.prefix(24)), "light": palette, "dark": palette])
    return try parse(String(decoding: data, as: UTF8.self))
  }
}

@MainActor
final class MacCommunitySkinModel: ObservableObject {
  struct PreviewKey: Equatable { let id: UUID; let name: String; let design: CustomKeyboardSkin }
  var previewKey: PreviewKey? { selected.map { .init(id: $0.id, name: $0.name, design: $0.design) } }
  @Published var onlyMine = false { didSet { if onlyMine != oldValue { selected = nil } } }
  var visibleItems: [BackendAccountClient.CommunitySkin] { onlyMine ? items.filter(\.owned) : items }
  @Published var items: [BackendAccountClient.CommunitySkin] = []
  @Published var selected: BackendAccountClient.CommunitySkin?
  @Published var search = ""
  @Published var more = false
  @Published var busy = false
  @Published var message: String?
  private let accountID: String
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private var pending: Task<Void, Never>?
  private var generation = 0
  private var offset = 0
  private var loadedSearch = ""
  init(accountID: String, client: BackendAccountClient = BackendAccountClient(), account: BackendAccountSession = .shared) {
    self.accountID = accountID; self.client = client; self.account = account
  }
  private func authorize() async throws -> String {
    let identity = try await account.credentials(matchingUserID: accountID)
    try Task.checkCancellation(); return identity.token
  }
  private func run(_ action: @escaping @MainActor (String) async throws -> Void) {
    guard !busy else { return }
    generation += 1; let version = generation
    busy = true; message = nil
    pending = Task {
      defer { if version == generation { busy = false; pending = nil } }
      do {
        let token = try await authorize()
        do { try await action(token) }
        catch let error as BackendAccountClient.Failure where error.status == 401 {
          let fresh = try await account.credentials(retrying: token, matchingUserID: accountID)
          try Task.checkCancellation()
          try await action(fresh.token)
        }
      }
      catch is CancellationError {} catch { if version == generation && !Task.isCancelled { message = error.localizedDescription } }
    }
  }
  func load(append: Bool = false) {
    let query = append ? loadedSearch : search
    let next = append ? offset : 0
    run { token in
      let page = try await self.client.communitySkins(search: query, offset: next, token: token)
      _ = try await self.authorize()
      let previous = append ? self.items : []
      let existing = Set(previous.map(\.id))
      self.items = previous + page.skins.filter { !existing.contains($0.id) }
      self.offset = next + page.skins.count; self.loadedSearch = query; self.more = page.has_more
    }
  }
  func detail(_ id: UUID) {
    run { token in
      let skin = try await self.client.communitySkin(id, token: token)
      _ = try await self.authorize(); self.selected = skin
    }
  }
  func download(reviewed: BackendAccountClient.CommunitySkin, install: @escaping @MainActor () throws -> Void) {
    run { token in
      let latest = try await self.client.communitySkin(reviewed.id, token: token)
      _ = try await self.authorize()
      guard latest.name == reviewed.name, latest.design == reviewed.design else { throw ServiceFailure(message: "作品已更新，请重新打开预览。") }
      let design = try await self.client.downloadCommunitySkin(reviewed.id, token: token)
      _ = try await self.authorize()
      guard design == reviewed.design.normalized else { throw ServiceFailure(message: "下载内容已更新，请重新预览。") }
      try install()
      self.message = "已下载并应用到本机候选窗。"
    }
  }
  func rate(_ skin: BackendAccountClient.CommunitySkin, stars: Int) {
    run { token in
      try await self.client.rateCommunitySkin(skin.id, stars: stars, token: token)
      _ = try await self.authorize()
      let updated = try await self.client.communitySkin(skin.id, token: token)
      _ = try await self.authorize(); self.selected = updated; self.message = "评分已保存。"
    }
  }
  func unpublish(_ skin: BackendAccountClient.CommunitySkin) {
    guard skin.owned else { return }
    run { token in
      try await self.client.unpublishCommunitySkin(skin.id, token: token)
      _ = try await self.authorize()
      self.items.removeAll { $0.id == skin.id }; self.selected = nil; self.message = "作品已下架。"
    }
  }
  func close() { generation += 1; pending?.cancel(); pending = nil; busy = false; items = []; selected = nil; message = nil }
}

struct MacCommunitySkinView: View {
  @StateObject private var model: MacCommunitySkinModel
  @StateObject private var draft = MacGeneratedSkinDraft()
  @State private var dark = false
  @State private var previewError: String?
  @State private var confirmingRemoval = false
  @Environment(\.dismiss) private var dismiss
  init(accountID: String) { _model = StateObject(wrappedValue: MacCommunitySkinModel(accountID: accountID)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack { Text("社区皮肤").font(.title2); Spacer(); Button("关闭") { dismiss() } }
      HStack { TextField("搜索名称或设计", text: $model.search).onSubmit { model.load() }; Button("搜索 / 刷新") { model.load() } }.disabled(model.busy)
      Toggle("只看我发布的皮肤", isOn: $model.onlyMine).disabled(model.busy)
      HStack(alignment: .top) {
        VStack {
          if model.visibleItems.isEmpty && !model.busy {
            Text(model.onlyMine && model.more ? "当前页没有你的作品，可继续加载。" : "没有符合条件的皮肤。")
              .font(.caption).foregroundStyle(.secondary)
          }
          List(model.visibleItems) { skin in
            Button { model.detail(skin.id) } label: {
              VStack(alignment: .leading) { Text(skin.name); Text(skin.author).font(.caption).foregroundStyle(.secondary) }
            }.buttonStyle(.plain).disabled(model.busy)
          }.frame(width: 180)
          if model.more { Button("加载更多") { model.load(append: true) }.disabled(model.busy) }
        }
        ScrollView {
          if let skin = model.selected {
            VStack(alignment: .leading, spacing: 10) {
              Text(skin.name).font(.headline)
              Text(skin.description).font(.callout)
              Text("\(skin.downloads) 次下载 · \(skin.rating_average, specifier: "%.1f") 分 · \(skin.rating_count) 人评分").font(.caption)
              Text("将作品配色用于候选窗，图片显示在顶部插画区；按键造型属于移动键盘效果。")
                .font(.footnote).foregroundStyle(.secondary)
              if let directory = draft.directory {
                Toggle("深色预览", isOn: $dark)
                GeneratedSkinNativePreview(directory: directory, dark: dark).id(directory).frame(height: skin.design.photo == nil ? 440 : 600)
                Button(draft.installed ? "已应用" : "下载并应用此配色") { model.download(reviewed: skin) { try draft.apply() } }
                  .disabled(model.busy || draft.installed)
              }
              if !skin.owned {
                HStack { Text("评分"); ForEach(1...5, id: \.self) { stars in Button("\(stars)★") { model.rate(skin, stars: stars) } } }
                  .disabled(model.busy)
                Text("下载后可评分。").font(.caption).foregroundStyle(.secondary)
              } else { Button("下架作品…", role: .destructive) { confirmingRemoval = true }.disabled(model.busy) }
            }.frame(maxWidth: .infinity, alignment: .leading)
          } else { Text("选择作品查看候选窗预览").foregroundStyle(.secondary) }
        }
      }
      if model.busy { ProgressView().controlSize(.small) }
      if let message = previewError ?? model.message { Text(message).foregroundStyle(.secondary) }
    }.padding(20).frame(width: 800, height: 700)
      .onAppear { model.load() }
      .onChange(of: model.previewKey) { _ in prepare() }
      .onDisappear { model.close(); draft.clear() }
      .alert("下架这款社区皮肤？", isPresented: $confirmingRemoval) {
        Button("取消", role: .cancel) {}
        Button("下架", role: .destructive) { if let skin = model.selected { model.unpublish(skin) } }
      } message: { Text("作品将从社区移除，其他用户已经保存的本机副本会保留。") }
  }
  private func prepare() {
    draft.clear(); previewError = nil
    guard let skin = model.selected else { return }
    do {
      let value = try GeneratedCandidateSkin.community(name: skin.name, design: skin.design)
      // Reuse the native validated package and bounded header artwork preparation.
      let data = try JSONEncoder().encode(value)
      try draft.prepare(String(decoding: data, as: UTF8.self), artwork: skin.design.photo)
    } catch { previewError = error.localizedDescription }
  }
}
