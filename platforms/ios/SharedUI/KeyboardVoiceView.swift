import SwiftUI

struct KeyboardVoiceView: View {
  let entry: VoiceTextHandoff?
  let insert: () throws -> Void
  let close: () -> Void
  /// Returns whether the host agreed to open the app. Absent in previews and in the app itself,
  /// where there is nothing to jump to.
  var openRecording: (() async -> Bool)?
  @State private var error: String?
  @State private var errorID = UUID()

  var body: some View {
    VStack(spacing: 4) {
      HStack {
        Label("语音结果", systemImage: "waveform").font(.headline)
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge).accessibilityAddTraits(.isHeader)
        Spacer()
        Button("关闭", action: close).accessibilityIdentifier("keyboardServiceClose")
      }
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            if let error {
              Text(error).font(.footnote).foregroundStyle(.red)
                .id("status").accessibilityIdentifier("keyboardVoiceStatus")
            }
            if let entry {
              Text(entry.text).frame(maxWidth: .infinity, alignment: .leading)
              Text("\(entry.expiresAt.formatted(date: .omitted, time: .shortened)) 前可用；点击插入后清除待插入结果。")
                .font(.caption).foregroundStyle(.secondary)
            } else {
              Text("这里插入的是水杉 App 里已经识别好的文字。先去 App 录音识别，点击“发送到键盘”，再回到这里插入。")
              Text("iOS 不允许键盘直接录音，所以录音这一步必须在 App 里做。结果只保留最新一条，10 分钟内有效。")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        .disablingScrollEdgeEffects()
        .onChange(of: errorID) { _ in proxy.scrollTo("status", anchor: .top) }
      }
      if entry != nil {
        Button("插入语音结果") {
          do { try insert(); close() } catch { self.error = error.localizedDescription; errorID = UUID() }
        }.frame(minHeight: 44).accessibilityIdentifier("keyboardVoiceInsert")
      } else if let openRecording {
        Button("打开水杉 App 录音") {
          Task {
            guard await openRecording() else {
              error = "当前 App 不允许键盘跳转，请手动打开水杉 App 的“语音设置”。"
              errorID = UUID()
              return
            }
          }
        }.frame(minHeight: 44).accessibilityIdentifier("keyboardVoiceOpenRecording")
      }
    }
    .padding(.horizontal, 12)
    .buttonStyle(KeyboardPanelButtonStyle())
    // Into the bottom safe area as well: the panel is sized to the whole keyboard, and leaving the
    // inset unpainted let the host app's own tab bar show through under the last button.
    .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea(edges: .bottom))
  }
}
