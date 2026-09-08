import SwiftUI

struct KeyboardAISelection: Equatable {
  let document: UUID
  let before: String?
  let selected: String
  let after: String?

  func matches(document: UUID?, before: String?, selected: String?, after: String?) -> Bool {
    document == self.document && before == self.before && selected == self.selected && after == self.after
  }
}

struct KeyboardAIView: View {
  let text: String
  let configuration: CustomServiceConfiguration
  let canSend: () -> Bool
  let insert: (String) -> Bool
  let close: () -> Void
  @State private var output = ""
  @State private var error = ""
  @State private var busy = false
  @State private var operation: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 4) {
      HStack {
        Label("AI 润色", systemImage: "sparkles").font(.headline)
        Spacer()
        Button("关闭", action: close).frame(minHeight: 44)
      }
      Text("发送到 \((try? configuration.validatedURL().host) ?? "") · \(configuration.model)")
        .font(.caption).lineLimit(2).foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          Text(output.isEmpty ? "待发送的选中文字" : "润色结果").font(.caption).foregroundStyle(.secondary)
          Text(output.isEmpty ? text : output).font(.body).frame(maxWidth: .infinity, alignment: .leading)
          if !error.isEmpty { Text(error).foregroundStyle(.red).font(.footnote) }
        }
      }
      HStack {
        if busy {
          ProgressView()
          Button("取消请求") { operation?.cancel(); busy = false }
        } else if output.isEmpty {
          Button("发送选中文字") { send() }.accessibilityIdentifier("keyboardAISend")
        } else {
          Button("替换选中文字") {
            if insert(output) { close() }
            else { error = "输入位置已变化，请关闭后重新选择文字。" }
          }.accessibilityIdentifier("keyboardAIInsert")
        }
      }.frame(minHeight: 44)
    }
    .padding(.horizontal, 12)
    .background(Color(uiColor: .secondarySystemBackground))
    .onDisappear { operation?.cancel() }
  }

  private func send() {
    guard canSend(), KeyboardAIService.configuration() == configuration else {
      error = "输入位置或 AI 配置已变化，请关闭后重试。"
      return
    }
    busy = true
    error = ""
    operation = Task { @MainActor in
      do {
        let token = try KeyboardAIService.token(for: configuration)
        let result = try await CustomServiceClient.request(kind: .ai, configuration: configuration, text: text, token: token)
        try Task.checkCancellation()
        guard canSend(), KeyboardAIService.configuration() == configuration else {
          throw ServiceFailure(message: "输入位置或 AI 配置已变化，请关闭后重试。")
        }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.count <= 10_000 else {
          throw ServiceFailure(message: "服务返回的文字为空或超过一万字。")
        }
        output = result
      } catch {
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
      if !Task.isCancelled { busy = false }
    }
  }
}
