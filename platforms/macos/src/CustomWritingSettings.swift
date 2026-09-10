import AppKit
import SwiftUI

@MainActor
enum MacWritingService {
  static let revisionKey = "MetasequoiaWritingServiceRevision"
  static var configuration: CustomServiceConfiguration { .load(.ai) }
  static var revision: String { UserDefaults.standard.string(forKey: revisionKey) ?? "" }
  static func request(_ config: CustomServiceConfiguration, text: String) async throws -> String {
    let token = try ServiceTokenStore.read(.ai, url: config.validatedURL())
    return try await CustomServiceClient.request(kind: .ai, configuration: config, text: text, token: token)
  }
}

struct MacCustomWritingSettings: View {
  @Environment(\.dismiss) private var dismiss
  @State private var config = CustomServiceConfiguration.load(.ai)
  @State private var token = ""
  @State private var status = ""
  @State private var models: [String] = []
  @State private var loading = false
  @State private var operation: Task<Void, Never>?
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("自定义 AI 服务").font(.title2)
      Text("密钥仅保存在本机钥匙串。生成内容直接发送至所选 HTTPS 服务，不经水杉账户后端。")
        .font(.footnote).foregroundStyle(.secondary)
      Picker("服务商", selection: $config.provider) {
        ForEach(AIProviderPreset.allCases, id: \.rawValue) { Text($0.title).tag($0) }
      }.onChange(of: config.provider) { provider in
        operation?.cancel(); loading = false; token = ""; models = provider.models
        config = CustomServiceConfiguration.loadPreset(provider)
      }
      TextField("HTTPS Chat Completions 地址", text: $config.endpoint)
      TextField("模型名称", text: $config.model)
      if !models.isEmpty {
        Picker("选择模型", selection: $config.model) {
          Text(config.model).tag(config.model)
          ForEach(models.filter { $0 != config.model }, id: \.self) { Text($0).tag($0) }
        }
      }
      SecureField("API 密钥（留空保留已存密钥）", text: $token)
      HStack {
        Button("读取模型列表") {
          loading = true; status = ""
          let snapshot = config, enteredToken = token
          operation = Task { @MainActor in
            do {
              let secret = try enteredToken.isEmpty ? ServiceTokenStore.read(.ai, url: snapshot.validatedURL(requiresModel: false)) : enteredToken
              let catalog = try await ModelCatalogClient.fetch(configuration: snapshot, kind: .ai, token: secret)
              try Task.checkCancellation()
              if config == snapshot { models = catalog }
            } catch { if !Task.isCancelled { status = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
          }
        }.disabled(loading)
        if loading { ProgressView().controlSize(.small) }
        Button("删除此服务的密钥") {
          do {
            try ServiceTokenStore.write("", kind: .ai, url: config.validatedURL(requiresModel: false))
            UserDefaults.standard.set(UUID().uuidString, forKey: MacWritingService.revisionKey)
            token = ""; status = "已删除此地址的密钥。"
          } catch { status = error.localizedDescription }
        }
      }
      Text("润色附加要求").font(.headline)
      TextEditor(text: $config.prompt).frame(height: 90).border(Color.secondary.opacity(0.3))
      if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
      HStack {
        Spacer()
        Button("取消") { operation?.cancel(); token = ""; dismiss() }.keyboardShortcut(.cancelAction)
        Button("保存") {
          do {
            try config.save(.ai, token: token)
            UserDefaults.standard.set(UUID().uuidString, forKey: MacWritingService.revisionKey)
            token = ""; dismiss()
          } catch { status = error.localizedDescription }
        }.keyboardShortcut(.defaultAction)
      }
    }.textFieldStyle(.roundedBorder).padding(24).frame(width: 600)
      .onDisappear { operation?.cancel(); token = "" }
  }
}
