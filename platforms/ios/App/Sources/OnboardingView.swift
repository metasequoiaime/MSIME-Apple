import SwiftUI
import UIKit

struct SettingsView: View {
  var body: some View {
    NavigationView {
      Form {
        Section {
          HStack(spacing: 14) {
            Image(systemName: "leaf.fill")
              .font(.system(size: 28))
              .foregroundStyle(MetasequoiaTheme.forest)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
              Text("水杉输入法").font(.headline)
              Text("让输入更自然").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
          }
        }

        Section {
          NavigationLink(destination: AccountSettingsView()) {
            Label("我的 · 账号与作品", systemImage: "person.crop.circle")
          }.accessibilityIdentifier("accountSettingsLink")
        }

        Section("键盘与服务") {
          NavigationLink(destination: InputSettingsView()) {
            Label("输入设置", systemImage: "slider.horizontal.3")
          }.accessibilityIdentifier("inputSettingsLink")
          NavigationLink(destination: SkinSettingsView()) {
            Label("皮肤", systemImage: "paintpalette")
          }.accessibilityIdentifier("skinSettingsLink")
          NavigationLink(destination: DictionarySettingsView()) {
            Label("词库", systemImage: "books.vertical")
          }.accessibilityIdentifier("dictionarySettingsLink")
          NavigationLink(destination: ServiceSettingsView(kind: .ai)) {
            Label("AI 设置", systemImage: "sparkles")
          }.accessibilityIdentifier("aiSettingsLink")
          NavigationLink(destination: ServiceSettingsView(kind: .voice)) {
            Label("语音设置", systemImage: "waveform")
          }.accessibilityIdentifier("voiceSettingsLink")
        }

        Section("使用键盘") {
          NavigationLink(destination: TypingStatisticsView()) {
            Label("打字统计", systemImage: "chart.bar.xaxis")
          }.accessibilityIdentifier("typingStatisticsLink")
          NavigationLink(destination: KeyboardTryoutView()) {
            Label("试用键盘", systemImage: "keyboard")
          }
          .accessibilityIdentifier("keyboardTryoutLink")
          NavigationLink(destination: OnboardingView()) {
            Label("启用指南", systemImage: "list.number")
          }
          .accessibilityIdentifier("keyboardGuideLink")
          Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
          } label: {
            Label("系统键盘设置", systemImage: "gearshape")
          }
          .accessibilityIdentifier("openKeyboardSettingsButton")
        }

        Section("了解水杉") {
          NavigationLink(destination: DesktopDownloadView()) {
            Label("电脑版下载", systemImage: "desktopcomputer")
          }.accessibilityIdentifier("desktopDownloadLink")
          NavigationLink(destination: AboutView()) {
            Label("关于水杉", systemImage: "info.circle")
          }.accessibilityIdentifier("aboutSettingsLink")
        }
      }
      .navigationTitle("设置")
    }
    .navigationViewStyle(.stack)
    .tint(MetasequoiaTheme.forest)
  }

}

struct InputSettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(KeyboardFeedbackPreference.soundKey, store: KeyboardFeedbackPreference.defaults)
  private var soundEnabled = true
  @AppStorage(KeyboardFeedbackPreference.hapticsKey, store: KeyboardFeedbackPreference.defaults)
  private var hapticsEnabled = false
  @AppStorage(KeyboardFeedbackPreference.strengthKey, store: KeyboardFeedbackPreference.defaults)
  private var hapticStrength = KeyboardHapticStrength.medium.rawValue
  @State private var previewFeedback: UIImpactFeedbackGenerator?
  @State private var inputScheme = InputSchemePreference.scheme
  @State private var enabledSchemes = InputSchemePreference.enabledSchemes
  @State private var usesTraditionalOutput = ChineseOutputPreference.usesTraditional

  var body: some View {
    Form {
        Section {
          ForEach(ChineseInputScheme.allCases, id: \.self) { scheme in
            HStack {
              Button {
                inputScheme = scheme
                InputSchemePreference.scheme = scheme
              } label: {
                HStack {
                  Text(scheme.title).foregroundStyle(.primary)
                  Spacer()
                  if inputScheme == scheme {
                    Image(systemName: "checkmark")
                      .foregroundStyle(MetasequoiaTheme.forest)
                      .accessibilityHidden(true)
                  }
                }
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("inputScheme_\(scheme.rawValue)")
              .accessibilityValue(inputScheme == scheme ? "已选择" : "未选择")
              .accessibilityAddTraits(inputScheme == scheme ? [.isSelected] : [])
              .disabled(!enabledSchemes.contains(scheme))
              Toggle(scheme.title, isOn: Binding(get: { enabledSchemes.contains(scheme) }, set: { enabled in
                var selection = enabledSchemes
                if enabled { selection.append(scheme) } else { selection.removeAll { $0 == scheme } }
                InputSchemePreference.enabledSchemes = selection
                reloadPreferences()
              }))
              .labelsHidden()
              .disabled(enabledSchemes.count == 1 && enabledSchemes.contains(scheme))
              .accessibilityIdentifier("enabledInputScheme_\(scheme.rawValue)")
            }

          }
        } header: {
          Text("输入方案")
        } footer: {
          Text("开启的方案会显示在键盘快捷切换中，至少保留一种。点击名称设为当前方案。左右滑动空格可移动光标；滑动前会先完成当前输入。")
        }

        Section {
          NavigationLink(destination: FuzzyPinyinSettingsView()) {
            Label("模糊音", systemImage: "waveform.path")
          }.accessibilityIdentifier("fuzzyPinyinSettingsLink")
        }

        Section {
          Picker("输出字形", selection: $usesTraditionalOutput) {
            Text("简体").tag(false)
            Text("繁体").tag(true)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("chineseOutputPicker")
          .onChange(of: usesTraditionalOutput) { value in
            ChineseOutputPreference.usesTraditional = value
          }
        } header: {
          Text("简繁体")
        } footer: {
          Text("应用于候选词和输入的文字。")
        }

        Section {
          Toggle("按键音", isOn: $soundEnabled)
            .accessibilityIdentifier("keyboardSoundToggle")
          Toggle("按键振动", isOn: $hapticsEnabled)
            .accessibilityIdentifier("keyboardHapticsToggle")
            .onChange(of: hapticsEnabled) { enabled in if enabled { previewHaptics() } }
          if hapticsEnabled {
            Picker("振动强度", selection: $hapticStrength) {
              ForEach(KeyboardHapticStrength.allCases, id: \.rawValue) { strength in
                Text(strength.title).tag(strength.rawValue)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("keyboardHapticStrengthPicker")
            .onChange(of: hapticStrength) { _ in previewHaptics() }
            Button("试一下振动", action: previewHaptics)
              .accessibilityIdentifier("previewKeyboardHaptics")
          }
        } header: {
          Text("按键反馈")
        } footer: {
          Text("按键音受系统静音设置控制；振动效果取决于设备与系统支持。")
        }

    }
    .navigationTitle("输入设置")
    .navigationBarTitleDisplayMode(.inline)
      .onAppear(perform: reloadPreferences)
      .onChange(of: scenePhase) { phase in
        if phase == .active { reloadPreferences() }
      }
  }

  private func previewHaptics() {
    guard hapticsEnabled else { return }
    let strength = KeyboardHapticStrength(rawValue: hapticStrength) ?? .medium
    let generator = UIImpactFeedbackGenerator(style: strength.style)
    previewFeedback = generator
    generator.impactOccurred(intensity: strength.intensity)
    generator.prepare()
  }

  private func reloadPreferences() {
    inputScheme = InputSchemePreference.scheme
    enabledSchemes = InputSchemePreference.enabledSchemes
    usesTraditionalOutput = ChineseOutputPreference.usesTraditional
  }
}

struct KeyboardTryoutView: View {
  @State private var sampleText = ""
  @FocusState private var tryoutFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("长按键盘上的地球键，切换到水杉输入法。")
        .foregroundStyle(.secondary)
      TextField("在这里试试水杉键盘", text: $sampleText)
        .focused($tryoutFocused)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("keyboardTryoutField")
      if tryoutFocused {
        Button("收起键盘") { tryoutFocused = false }
          .accessibilityIdentifier("dismissKeyboardButton")
      }
      Spacer()
    }
    .padding(22)
    .background(MetasequoiaTheme.mist.ignoresSafeArea())
    .navigationTitle("试用键盘")
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear { tryoutFocused = false }
  }
}

struct OnboardingView: View {
  var onFinish: (() -> Void)? = nil

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

        if let onFinish {
          Button("已完成，进入设置", action: onFinish)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityIdentifier("finishOnboardingButton")
        }

        Text("键盘默认离线。打字统计需开启“允许完全访问”以保存本机字数；AI 和语音服务可在设置中单独配置。")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 30)
    }
    .background(MetasequoiaTheme.mist.ignoresSafeArea())
    .tint(MetasequoiaTheme.forest)
    .navigationTitle("启用指南")
    .navigationBarTitleDisplayMode(.inline)
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
        Text("添加键盘，开始使用水杉输入法")
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
