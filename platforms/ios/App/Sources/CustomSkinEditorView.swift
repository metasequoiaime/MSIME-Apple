import SwiftUI
import UIKit

struct CustomSkinEditorView: View {
  @State private var design = CustomKeyboardSkinStore.current
  @State private var nineKey = InputSchemePreference.scheme == .nineKey
  @State private var confirmReset = false
  @AppStorage(KeyboardSkinPreference.key, store: KeyboardFeedbackPreference.defaults)
  private var selected = KeyboardSkin.forest.rawValue

  private func update<T>(_ path: WritableKeyPath<CustomKeyboardSkin, T>, _ value: T) {
    var next = design
    next[keyPath: path] = value
    CustomKeyboardSkinStore.save(next)
    design = next.normalized
  }

  private func color(_ path: WritableKeyPath<CustomKeyboardSkin, UInt32>) -> Binding<Color> {
    Binding(get: { Color(uiColor: CustomKeyboardSkin.color(design[keyPath: path])) },
            set: { update(path, CustomKeyboardSkin.rgb(UIColor($0))) })
  }

  private func value<T>(_ path: WritableKeyPath<CustomKeyboardSkin, T>) -> Binding<T> {
    Binding(get: { design[keyPath: path] }, set: { update(path, $0) })
  }

  var body: some View {
    Form {
      Section("实时预览") {
        Picker("预览布局", selection: $nineKey) {
          Text("26 键").tag(false)
          Text("9 键").tag(true)
        }.pickerStyle(.segmented)
        KeyboardSkinPreview(skin: .custom, nineKey: nineKey)
          .id(design)
          .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        Button {
          selected = KeyboardSkin.custom.rawValue
        } label: {
          Label(selected == KeyboardSkin.custom.rawValue ? "正在使用我的皮肤" : "使用这款皮肤",
                systemImage: selected == KeyboardSkin.custom.rawValue ? "checkmark.circle.fill" : "checkmark.circle")
        }.accessibilityIdentifier("applyCustomSkin")
      }
      Section("配色") {
        ColorPicker("键盘背景", selection: color(\.background), supportsOpacity: false)
        ColorPicker("键帽", selection: color(\.keyBackground), supportsOpacity: false)
        ColorPicker("按键文字", selection: color(\.keyForeground), supportsOpacity: false)
        ColorPicker("提示与工具栏", selection: color(\.accent), supportsOpacity: false)
        ColorPicker("功能键", selection: color(\.actionBackground), supportsOpacity: false)
        if !design.hasReadableText {
          Label("部分文字与背景对比度偏低，建议调整配色。", systemImage: "eye")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Button("优化文字对比度") {
          var next = design
          next.keyForeground = CustomKeyboardSkin.readableText(on: next.keyBackground)
          let black = min(CustomKeyboardSkin.contrast(0, next.background), CustomKeyboardSkin.contrast(0, next.keyBackground))
          let white = min(CustomKeyboardSkin.contrast(0xFFFFFF, next.background), CustomKeyboardSkin.contrast(0xFFFFFF, next.keyBackground))
          next.accent = black >= white ? 0 : 0xFFFFFF
          CustomKeyboardSkinStore.save(next)
          design = next
        }
      }
      Section("键帽设计") {
        VStack(alignment: .leading) {
          Text("圆角 · \(Int(design.cornerRadius))")
          Slider(value: value(\.cornerRadius), in: 0...20, step: 1)
            .accessibilityIdentifier("customSkinCornerRadius")
        }
        VStack(alignment: .leading) {
          Text("边框 · \(design.borderWidth, specifier: "%.1f")")
          Slider(value: value(\.borderWidth), in: 0...2, step: 0.5)
        }
        VStack(alignment: .leading) {
          Text("阴影 · \(Int(design.shadow * 100))%")
          Slider(value: value(\.shadow), in: 0...0.4, step: 0.05)
        }
        Toggle("等宽字形", isOn: value(\.monospaced))
          .accessibilityIdentifier("customSkinMonospaced")
        Picker("背景纹理", selection: value(\.pattern)) {
          Text("纯色").tag(0)
          Text("网点").tag(1)
          Text("网格").tag(2)
          Text("波纹").tag(3)
        }.accessibilityIdentifier("customSkinPattern")
      }
      Section {
        Button("重置我的皮肤", role: .destructive) { confirmReset = true }
      } footer: {
        Text("修改自动保存在设备上。使用中的自定义皮肤会在下次打开键盘时更新；配色在浅色和深色模式下保持一致。功能键文字会自动选择黑色或白色。")
      }
    }
    .navigationTitle("自定义皮肤")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog("恢复默认配色和键帽设计？", isPresented: $confirmReset, titleVisibility: .visible) {
      Button("重置", role: .destructive) {
        let initial = CustomKeyboardSkin()
        CustomKeyboardSkinStore.save(initial)
        design = initial
      }
      Button("取消", role: .cancel) {}
    }
  }
}
