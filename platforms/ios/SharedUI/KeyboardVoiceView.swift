import SwiftUI

struct KeyboardVoiceView: View {
  let entry: VoiceTextHandoff?
  let insert: () throws -> Void
  let close: () -> Void
  @State private var error: String?

  var body: some View {
    VStack(spacing: 4) {
      HStack {
        Label("语音结果", systemImage: "waveform").font(.headline)
        Spacer()
        Button("关闭", action: close).frame(minHeight: 44)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          if let entry {
            Text(entry.text).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entry.expiresAt.formatted(date: .omitted, time: .shortened)) 前可用；点击插入后清除待插入结果。")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Text("请在水杉 App 的“语音设置”中录音识别，点击“发送到键盘”，再返回这里插入。")
            Text("iOS 键盘不能直接录音。结果只保留最新一条，10 分钟内有效。")
              .font(.footnote).foregroundStyle(.secondary)
          }
          if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
      }
      if entry != nil {
        Button("插入语音结果") {
          do { try insert(); close() } catch { self.error = error.localizedDescription }
        }.frame(minHeight: 44).accessibilityIdentifier("keyboardVoiceInsert")
      }
    }
    .padding(.horizontal, 12)
    .background(Color(uiColor: .secondarySystemBackground))
  }
}
