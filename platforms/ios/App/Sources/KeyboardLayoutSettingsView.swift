import SwiftUI

struct KeyboardLayoutSettingsView: View {
  @State private var keySpacing = KeyboardLayoutPreference.keySpacing
  @State private var rowSpacing = KeyboardLayoutPreference.rowSpacing
  @State private var height = KeyboardLayoutPreference.heightAdjustment
  var body: some View {
    Form {
      Section {
        spacingRow("键盘高度", value: $height, range: -12...48, identifier: "appKeyboardHeightSlider",
                   format: { $0 > 0 ? "+\(Int($0))" : "\(Int($0))" }) {
          KeyboardLayoutPreference.heightAdjustment = $0
        }
      } header: {
        Text("键盘高度")
      } footer: {
        Text("在系统键盘高度的基础上增减，按键会跟着变高。调整后重新唤出键盘生效。")
      }
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
        Button("恢复默认", role: .destructive) {
          KeyboardLayoutPreference.resetToDefaults()
          readPreferences()
        }
        .accessibilityIdentifier("appResetKeyboardSettings")
      } footer: {
        Text("把这一页的间距和高度恢复成默认值。")
      }
    }
    .tint(MetasequoiaTheme.accent)
    .navigationTitle("键盘设置").navigationBarTitleDisplayMode(.inline)
    .onAppear { readPreferences() }
  }

  /// 把存储里的值读回控件。复位后也走这里,免得界面还停在旧数值上。
  private func readPreferences() {
    keySpacing = KeyboardLayoutPreference.keySpacing
    rowSpacing = KeyboardLayoutPreference.rowSpacing
    height = KeyboardLayoutPreference.heightAdjustment
  }

  private func spacingRow(
    _ title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    identifier: String,
    format: @escaping (Double) -> String = { String(format: "%.1f", $0) },
    store: @escaping (Double) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
        Spacer()
        Text(format(value.wrappedValue)).font(.callout).monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; store($0) }),
        in: range
      ).accessibilityIdentifier(identifier).accessibilityLabel(title)
    }
  }
}
