import SwiftUI
import UIKit

struct OnboardingView: View {
  @State private var sampleText = ""
  @FocusState private var tryoutFocused: Bool
  @State private var usesShuangpin = InputSchemePreference.usesShuangpin
  @State private var usesTraditionalOutput = ChineseOutputPreference.usesTraditional

  private let steps = [
    ("1", "打开键盘设置", "前往“设置 → 通用 → 键盘 → 键盘”。"),
    ("2", "添加水杉输入法", "选择“添加新键盘”，再选择水杉输入法。"),
    ("3", "切换并开始输入", "在输入框长按地球键，选择水杉输入法。"),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        header

        VStack(spacing: 0) {
          ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            stepRow(
              number: step.0, title: step.1, detail: step.2, drawsLine: index < steps.count - 1)
          }
        }
        .padding(.horizontal, 20)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

        Button(action: openSettings) {
          Label("打开系统设置", systemImage: "gearshape.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(
          MetasequoiaTheme.forest, in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityIdentifier("openKeyboardSettingsButton")
        .accessibilityHint("打开水杉输入法的系统设置页面")

        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 12) {
            // Decorative next to the row's own title and subtitle. Left visible to VoiceOver, a
            // symbol reads either its system name ("插入文本") or, when it has none, its raw
            // identifier, and neither says anything the row's text does not already say.
            Image(systemName: "character.cursor.ibeam")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(MetasequoiaTheme.forest)
              .frame(width: 38, height: 38)
              .background(MetasequoiaTheme.mist, in: Circle())
              .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
              Text("输入方案")
                .font(.headline)
                .foregroundStyle(MetasequoiaTheme.ink)
              Text("设置会同步到水杉键盘")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }

          Picker("输入方案", selection: $usesShuangpin) {
            Text("全拼").tag(false)
            Text("小鹤双拼").tag(true)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("inputSchemePicker")
          .onChange(of: usesShuangpin) { newValue in
            InputSchemePreference.usesShuangpin = newValue
          }

          Divider()

          HStack(spacing: 12) {
            Image(systemName: "character.book.closed")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(MetasequoiaTheme.forest)
              .frame(width: 38, height: 38)
              .background(MetasequoiaTheme.mist, in: Circle())
              .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
              Text("输出字形")
                .font(.headline)
                .foregroundStyle(MetasequoiaTheme.ink)
              Text("词库保持简体，仅转换候选和上屏文字")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }

          Picker("输出字形", selection: $usesTraditionalOutput) {
            Text("简体").tag(false)
            Text("繁体").tag(true)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("chineseOutputPicker")
          .onChange(of: usesTraditionalOutput) { newValue in
            ChineseOutputPreference.usesTraditional = newValue
          }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(MetasequoiaTheme.needle.opacity(0.12), lineWidth: 1)
        }
        .onAppear {
          usesShuangpin = InputSchemePreference.usesShuangpin
          usesTraditionalOutput = ChineseOutputPreference.usesTraditional
        }

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("启用后试一试")
              .font(.headline)
              .foregroundStyle(MetasequoiaTheme.ink)
            Spacer(minLength: 8)
            // The field had no way to put the keyboard away, which also meant the keyboard never
            // saw a dismissal while this app stayed in front.
            if tryoutFocused {
              Button("收起键盘") { tryoutFocused = false }
                .font(.subheadline)
                .foregroundStyle(MetasequoiaTheme.forest)
                .accessibilityIdentifier("dismissKeyboardButton")
            }
          }
          TextField("在这里试试水杉键盘", text: $sampleText)
            .focused($tryoutFocused)
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MetasequoiaTheme.needle.opacity(0.35), lineWidth: 1)
            }
            .accessibilityIdentifier("keyboardTryoutField")
        }

        Text("键盘扩展默认不请求“允许完全访问”。输入内容保留在设备上。")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 30)
    }
    .background(MetasequoiaTheme.mist.ignoresSafeArea())
    .tint(MetasequoiaTheme.forest)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 18) {
      MetasequoiaMark()
        .stroke(
          MetasequoiaTheme.forest,
          style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 58, height: 76)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text("水杉输入法")
          .font(.system(.largeTitle, design: .rounded).weight(.bold))
          .foregroundStyle(MetasequoiaTheme.ink)
        Text("同一颗引擎，原生 iOS 键盘")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(MetasequoiaTheme.needle)
      }
    }
  }

  private func stepRow(number: String, title: String, detail: String, drawsLine: Bool) -> some View
  {
    HStack(alignment: .top, spacing: 16) {
      VStack(spacing: 0) {
        Text(number)
          .font(.system(.headline, design: .rounded).weight(.bold))
          .foregroundStyle(.white)
          .frame(width: 34, height: 34)
          .background(MetasequoiaTheme.cone, in: Circle())
        if drawsLine {
          Rectangle()
            .fill(MetasequoiaTheme.needle.opacity(0.3))
            .frame(width: 2, height: 54)
        }
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.headline)
          .foregroundStyle(MetasequoiaTheme.ink)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 5)

      Spacer(minLength: 0)
    }
    .padding(.top, 18)
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}

#Preview {
  OnboardingView()
}
