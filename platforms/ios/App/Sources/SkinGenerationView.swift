import SwiftUI

struct SkinGenerationView: View {
  var onEdit: (SavedKeyboardSkin) -> Void
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model = SkinGenerationModel()
  @State private var nineKey = false
  @State private var library = CustomSkinLibrary.designs
  @State private var showLogin = false
  @State private var deleting = false
  @State private var publishing: SavedKeyboardSkin?
  @State private var notice: String?
  private enum Field: Hashable { case prompt, name }
  @FocusState private var focusedField: Field?
  private var isSaved: Bool { model.result.map { library.contains($0) } ?? false }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("把灵感变成键盘").font(.title2.bold())
          Text("描述颜色、氛围和键帽风格，AI 会生成可继续编辑的设计。").font(.subheadline).foregroundStyle(.secondary)
          TextEditor(text: $model.prompt).focused($focusedField, equals: .prompt).disabled(model.generating).frame(height: 96).padding(8)
            .background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MetasequoiaTheme.accent.opacity(0.2)))
            .accessibilityLabel("描述想要的皮肤").accessibilityIdentifier("skinGenerationPrompt")
            .onChange(of: model.prompt) { if $0.count > 600 { model.prompt = String($0.prefix(600)) } }
          Text("例如：雨后的竹林，青瓷白键帽，细边框，安静清爽。").font(.caption).foregroundStyle(.secondary)
          if model.loginNeeded {
            Button("登录使用 AI") { showLogin = true }
          } else {
            HStack {
              Picker("模型", selection: $model.selectedModel) {
                if model.models.isEmpty { Text("尚未加载").tag("") }
                ForEach(model.models) { Text($0.id).tag($0.id) }
              }.pickerStyle(.menu).disabled(model.generating).accessibilityIdentifier("skinGenerationModel")
              Spacer()
              if model.loading { ProgressView() }
              else { Button { Task { await model.loadModels() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新模型") }
            }
          }
          if model.generating {
            HStack { ProgressView(); Text("正在设计…"); Spacer(); Button("取消生成") { model.cancel() } }
          } else {
            Button { focusedField = nil; model.generate() } label: {
              Label(model.result == nil ? "生成皮肤" : "再生成一款", systemImage: "sparkles")
                .font(.headline).frame(maxWidth: .infinity).padding(14)
            }.buttonStyle(.plain).foregroundStyle(.white).background(MetasequoiaTheme.forest, in: RoundedRectangle(cornerRadius: 14))
              .disabled(model.loginNeeded || model.selectedModel.isEmpty || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              .accessibilityIdentifier("generateSkinButton")
          }
          if let message = model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("skinGenerationError") }
          if let result = model.result { resultCard(result).disabled(model.generating) }
          Text("只发送你在此填写的描述。生成结果先作为草稿，不会替换当前皮肤；保存后可在“我的皮肤”管理。未保存的草稿关闭后不会保留。").font(.caption).foregroundStyle(.secondary)
        }.padding(18)
      }.background(MetasequoiaTheme.canvas)
        .navigationTitle("AI 生成皮肤").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { model.cancel(); dismiss() } } }
        .task { await model.loadModels() }
        .onDisappear { model.cancel() }
        .sheet(isPresented: $showLogin, onDismiss: { Task { await model.loadModels() } }) { AccountLoginSheet() }
        .sheet(item: $publishing) { item in SavedSkinPublishFlow(skinID: item.id) }
        .alert("皮肤设计", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("好") {} } message: { Text(notice ?? "") }
        .confirmationDialog("删除这款本地设计？已发布的社区作品不会下架。", isPresented: $deleting, titleVisibility: .visible) {
          Button("删除设计", role: .destructive) { removeResult() }
        }
    }.navigationViewStyle(.stack).tint(MetasequoiaTheme.accent)
  }
  private func resultCard(_ result: SavedKeyboardSkin) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("设计名称", text: Binding(get: { model.result?.name ?? "" }, set: { model.result?.name = String($0.prefix(32)) }))
          .focused($focusedField, equals: .name).font(.headline).accessibilityIdentifier("generatedSkinName")
        Text(isSaved ? "已保存" : "草稿").font(.caption).foregroundStyle(.secondary)
      }
      Picker("预览布局", selection: $nineKey) { Text("26 键").tag(false); Text("9 键").tag(true) }
        .pickerStyle(.segmented).accessibilityIdentifier("generatedSkinLayout")
      CommunityDesignPreview(design: result.design, nineKey: nineKey)
      HStack {
        Button(isSaved ? "已保存" : "保存到我的") { _ = persist() }.disabled(isSaved).accessibilityIdentifier("saveGeneratedSkin")
        Spacer()
        Button("继续编辑") { if let item = persist() { onEdit(item); dismiss() } }.accessibilityIdentifier("editGeneratedSkin")
      }.buttonStyle(.bordered)
      HStack {
        Button(isSaved ? "发布到社区" : "保存并发布") { if let item = persist() { publishing = item } }
          .accessibilityIdentifier("publishGeneratedSkin")
        Spacer()
        Button("删除", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteGeneratedSkin")
      }.font(.subheadline)
    }.padding(14).background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 18))
  }
  private func persist() -> SavedKeyboardSkin? {
    guard var item = model.result else { return nil }
    item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
    var items = CustomSkinLibrary.designs
    guard !item.name.isEmpty, !items.contains(where: { $0.id != item.id && $0.name == item.name }) else { notice = "请填写一个不重复的皮肤名称。"; return nil }
    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    else {
      guard items.count < 12 else { notice = "最多保存 12 款，请先删除不需要的本地皮肤。"; return nil }
      items.append(item)
    }
    guard CustomSkinLibrary.save(items) else { notice = "保存失败，请检查可用空间后重试。"; return nil }
    library = items; model.result = item
    return item
  }
  private func removeResult() {
    guard let result = model.result else { return }
    let items = CustomSkinLibrary.designs.filter { $0.id != result.id }
    guard CustomSkinLibrary.save(items) else { notice = "删除失败，请重试。"; return }
    library = items; model.result = nil
  }
}

struct SavedSkinPublishFlow: View {
  let skinID: UUID
  @State private var signedIn = false
  @State private var loading = true
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    Group {
      if loading { ProgressView("正在准备发布…") }
      else if signedIn { CommunityPublishView(onPublished: {}, selectedSkinID: skinID) }
      else {
        NavigationView {
          Form { AppleAccountSection(signedIn: $signedIn) }
            .navigationTitle("登录后发布").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.navigationViewStyle(.stack)
      }
    }.task {
      #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("-skinGenerationFixture") { signedIn = true; loading = false; return }
      #endif
      signedIn = (try? await SkinCommunityAPI.shared.signedIn()) == true
      loading = false
    }
  }
}
