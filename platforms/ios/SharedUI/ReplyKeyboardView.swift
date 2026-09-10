import SwiftUI

@MainActor
final class ReplyKeyboardModel: ObservableObject {
  @Published var text = ""
  @Published var polish = false { didSet { if oldValue != polish { resetResults() } } }
  @Published var replies: [String] = []
  @Published var status = "粘贴 TA 的话，再选择回复方式"
  @Published var busy = false
  @Published var style = "高情商"
  private var operation: Task<Void, Never>?
  private var generation = UUID()
  var insertResult: ((String) -> Bool)?

  func setText(_ value: String) {
    resetResults()
    guard value.count <= 10_000 else { status = "每次最多粘贴一万字"; return }
    text = value
    status = value.isEmpty ? "剪贴板里没有文字" : "选择下方风格生成，内容仅在点击风格时发送"
  }
  func resetResults() {
    operation?.cancel(); operation = nil; generation = UUID()
    busy = false; replies = []; insertResult = nil
  }
  func invalidateContext() {
    resetResults()
    status = "输入位置已变化，请重新选择回复方式"
  }
  func generate(style: String, request: @escaping @MainActor (String, String) async throws -> String,
                insert: @escaping (String) -> Bool) {
    guard !busy else { return }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      status = "先点粘贴，放入 TA 的话"; return
    }
    if self.style != style { replies = [] }
    self.style = style
    let template = style.hasPrefix("community:") ? CommunityLibrary.replies.first { "community:\($0.id)" == style } : nil
    if style.hasPrefix("community:") && template == nil { status = "模板已移除，请重新选择"; return }
    busy = true; status = "正在生成 · \(template?.name ?? style)"
    let id = UUID(); generation = id
    let prompt = (polish ? WritingTask.polish : .reply).prompt(style: style, templatePrompt: template?.content.prompt)
    let source = text
    operation = Task { @MainActor in
      do {
        let result = try await request(source, prompt)
        try Task.checkCancellation()
        guard generation == id else { return }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.count <= 10_000 else {
          throw ServiceFailure(message: "回复为空或过长，请重试")
        }
        if !replies.contains(result) { replies.insert(result, at: 0); replies = Array(replies.prefix(3)) }
        insertResult = insert
        status = "点选回复插入输入框"
      } catch {
        guard generation == id, !Task.isCancelled else { return }
        status = error.localizedDescription
      }
      if generation == id { busy = false }
    }
  }
  func use(_ reply: String) {
    guard replies.contains(reply), insertResult?(reply) == true else {
      invalidateContext(); return
    }
    resetResults(); status = "已插入，请在聊天应用中确认发送"
  }
}

struct ReplyKeyboardView: View {
  @ObservedObject var model: ReplyKeyboardModel
  let paste: () -> Void
  let generate: (String) -> Void
  let schemes: () -> Void
  let skins: () -> Void
  let dismiss: () -> Void
  private let styles = zip(["😁", "🥰", "📣", "😍", "🌪", "👔", "💬", "🤩", "🙌"], WritingTask.replyStyles).map { "\($0.0) \($0.1)" }
  private var skin: KeyboardSkin { KeyboardSkinPreference.selected }

  var body: some View {
    VStack(spacing: 5) {
      HStack(spacing: 8) {
        Picker("操作", selection: $model.polish) {
          Text("帮你回").tag(false)
          Text("帮润色").tag(true)
        }.pickerStyle(.segmented).frame(maxWidth: 200).accessibilityIdentifier("replyMode")
        Button(action: schemes) {
          Image(systemName: "keyboard").font(.system(size: 22))
        }.accessibilityLabel("选择输入方案").accessibilityIdentifier("replySchemes")
        Spacer(minLength: 0)
        Menu {
          if CommunityLibrary.replies.isEmpty { Text("在 App 社区收藏并添加回复模板") }
          ForEach(CommunityLibrary.replies) { item in
            Button(item.name) { generate("community:\(item.id)") }
          }
        } label: { Image(systemName: "bookmark") }
          .accessibilityLabel("回复模板").accessibilityIdentifier("replyTemplates").disabled(model.busy)
        Button(action: skins) { Image(systemName: "tshirt") }.accessibilityLabel("切换皮肤")
        Button(action: dismiss) { Image(systemName: "chevron.down") }.accessibilityLabel("收起键盘")
      }.frame(height: 36)
      HStack(spacing: 6) {
        Button(action: paste) {
          Text(model.text.isEmpty ? "+ 粘贴 TA 的话帮你回" : model.text)
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("replySource")
        Button("粘贴", action: paste).accessibilityIdentifier("replyPaste")
          .padding(.horizontal, 10).foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9))
      }.frame(height: 38).padding(.horizontal, 10)
        .background(Color(uiColor: skin.keyBackground), in: RoundedRectangle(cornerRadius: 10))
      HStack(alignment: .top, spacing: 6) {
        if model.replies.isEmpty {
          VStack(spacing: 5) {
            ForEach(0..<3) { row in
              HStack(spacing: 5) {
                ForEach(0..<3) { column in
                  let label = styles[row * 3 + column]
                  Button { generate(String(label.dropFirst(2))) } label: {
                    Text(label).font(.system(size: 14, weight: .medium)).minimumScaleFactor(0.7).lineLimit(1)
                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                  }.disabled(model.busy).accessibilityIdentifier("replyStyle_\(row * 3 + column)")
                    .background(Color(uiColor: skin.keyBackground), in: RoundedRectangle(cornerRadius: 10))
                }
              }
            }
          }
        } else {
          ScrollView {
            VStack(spacing: 6) {
              ForEach(model.replies, id: \.self) { reply in
                Button { model.use(reply) } label: {
                  Text(reply).font(.system(size: 15)).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.accessibilityIdentifier("replyCandidate")
                  .background(Color(uiColor: skin.keyBackground), in: RoundedRectangle(cornerRadius: 10))
              }
            }
          }.accessibilityIdentifier("replyCandidates")
        }
        VStack(spacing: 5) {
          Button { if !model.text.isEmpty { model.setText(String(model.text.dropLast())) } } label: {
            Image(systemName: "delete.left")
          }.accessibilityLabel("删除源文字").accessibilityIdentifier("replyDelete")
          Button("清空") { model.setText("") }.accessibilityIdentifier("replyClear")
          if model.busy {
            Button("取消") { model.resetResults(); model.status = "已取消" }
          } else if model.replies.isEmpty {
            Button("生成") { generate(model.style) }.accessibilityIdentifier("replyGenerate")
          } else {
            Button("换一句") { generate(model.style) }.accessibilityIdentifier("replyRegenerate")
          }
        }.frame(width: 60)
          .buttonStyle(ReplyActionStyle(background: Color(uiColor: skin.keyBackground).opacity(0.7)))
      }.frame(maxHeight: .infinity)
      HStack(spacing: 4) {
        if model.busy { ProgressView().scaleEffect(0.7) }
        Text(model.status).font(.system(size: 11)).lineLimit(1).accessibilityIdentifier("replyStatus")
        Spacer(minLength: 0)
        if !model.replies.isEmpty { Button("选风格") { model.resetResults() }.font(.caption) }
      }.frame(height: 18)
    }
    .padding(.horizontal, 6).padding(.vertical, 5)
    .foregroundStyle(Color(uiColor: skin.keyForeground))
    .tint(Color(uiColor: skin.accent))
    .background(Color(uiColor: skin.background))
    .buttonStyle(.plain)
  }
}

private struct ReplyActionStyle: ButtonStyle {
  let background: Color
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 14, weight: .medium))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(background.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 10))
  }
}
