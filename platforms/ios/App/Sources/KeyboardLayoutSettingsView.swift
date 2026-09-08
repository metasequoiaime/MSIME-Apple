import SwiftUI

struct KeyboardLayoutSettingsView: View {
  @State private var selected = KeyboardLayoutPreference.selected
  @State private var nineKey = InputSchemePreference.scheme == .nineKey
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("换输入法，不换打字习惯").font(.title2.bold())
        Text("选择熟悉的键位排列，颜色继续使用当前皮肤。")
          .foregroundStyle(.secondary)
        Picker("预览键盘", selection: $nineKey) {
          Text("26 键").tag(false)
          Text("9 键").tag(true)
        }.pickerStyle(.segmented).accessibilityIdentifier("layoutPreviewMode")
        ForEach(KeyboardLayoutPreset.allCases, id: \.self) { preset in
          Button {
            selected = preset
            KeyboardLayoutPreference.selected = preset
          } label: {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(preset.title).font(.headline)
                Spacer()
                Image(systemName: selected == preset ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(selected == preset ? MetasequoiaTheme.forest : .secondary)
              }
              Text(preset.detail).font(.caption).foregroundStyle(.secondary)
              KeyboardSkinPreview(skin: KeyboardSkinPreference.selected, nineKey: nineKey, compact: true, layout: preset)
            }.padding(14)
              .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
              .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected == preset ? MetasequoiaTheme.forest : .clear, lineWidth: 2))
          }.buttonStyle(.plain).accessibilityIdentifier("layoutPreset_\(preset.rawValue)")
            .accessibilityValue(selected == preset ? "已选择" : "未选择")
        }
        Text("习惯布局参考常用键位，不会切换输入引擎或改变皮肤。不同版本及个人设置可能有差异；语音入口使用水杉现有的语音结果功能。")
          .font(.footnote).foregroundStyle(.secondary)
      }.padding(20)
    }.background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("键盘布局").navigationBarTitleDisplayMode(.inline)
      .onAppear { selected = KeyboardLayoutPreference.selected }
  }
}
