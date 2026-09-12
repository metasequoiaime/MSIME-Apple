import SwiftUI

struct KeyboardLayoutSettingsView: View {
  @State private var keySpacing = KeyboardLayoutPreference.keySpacing
  @State private var rowSpacing = KeyboardLayoutPreference.rowSpacing
  @State private var voice = KeyboardLayoutPreference.voiceShortcutEnabled
  var body: some View {
    Form {
      Section {
        spacingRow("按键间距", value: $keySpacing, range: 3...6, identifier: "appKeySpacingSlider") {
          KeyboardLayoutPreference.keySpacing = $0
        }
        spacingRow("行间距", value: $rowSpacing, range: 4...10, identifier: "appRowSpacingSlider") {
          KeyboardLayoutPreference.rowSpacing = $0
        }
      } header: {
        Text("按键间距")
      } footer: {
        // 布局预设只在键盘内切换,这里不再重复提供,避免让间距设置看起来像布局选择器。
        Text("间距只改变键位外观，不影响输入方案。键盘布局在键盘的布局按钮里切换。")
      }
      Section {
        Toggle("顶部语音入口", isOn: $voice).accessibilityIdentifier("appVoiceShortcutSwitch")
      } header: {
        Text("快捷入口")
      } footer: {
        Text("语音入口用于打开已识别的语音结果。")
      }
    }
    .tint(MetasequoiaTheme.accent)
    .navigationTitle("键盘设置").navigationBarTitleDisplayMode(.inline)
    .onChange(of: voice) { KeyboardLayoutPreference.voiceShortcutEnabled = $0 }
    .onAppear {
      keySpacing = KeyboardLayoutPreference.keySpacing
      rowSpacing = KeyboardLayoutPreference.rowSpacing
      voice = KeyboardLayoutPreference.voiceShortcutEnabled
    }
  }

  private func spacingRow(
    _ title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    identifier: String,
    store: @escaping (Double) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
        Spacer()
        Text(String(format: "%.1f", value.wrappedValue)).font(.callout).monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; store($0) }),
        in: range
      ).accessibilityIdentifier(identifier).accessibilityLabel(title)
    }
  }
}
