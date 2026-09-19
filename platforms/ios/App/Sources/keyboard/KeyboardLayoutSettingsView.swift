import SwiftUI

struct KeyboardLayoutSettingsView: View {
  @State private var keySpacing = KeyboardLayoutPreference.keySpacing
  @State private var rowSpacing = KeyboardLayoutPreference.rowSpacing
  @State private var height = KeyboardLayoutPreference.heightAdjustment
  @State private var skin = KeyboardSkinPreference.selected
  @State private var nineKey = InputSchemePreference.scheme == .nineKey
  @State private var voice = KeyboardLayoutPreference.voiceShortcutEnabled
  @State private var dragBase: (height: Double, keySpacing: Double, rowSpacing: Double)?
  @State private var dragAxis: Axis?

  private enum Axis { case vertical, horizontal }
  private static let spacingDragScale: Double = 18

  var body: some View {
    VStack(spacing: 0) {
      preview
      form
    }
    .tint(MetasequoiaTheme.accent)
    .navigationTitle("键盘设置").navigationBarTitleDisplayMode(.inline)
    .onAppear { readPreferences() }
  }

  private var preview: some View {
    VStack(spacing: 6) {
      grip
      KeyboardSkinPreview(
        skin: skin, nineKey: nineKey,
        layout: KeyboardGeometry(keySpacing: keySpacing, rowSpacing: rowSpacing),
        heightAdjustment: height
      )
      .gesture(spacingDrag)
      .accessibilityIdentifier("keyboardLayoutPreview")
      Text(dragHint).font(.caption2).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
  }

  private var grip: some View {
    Capsule()
      .fill(MetasequoiaTheme.accent.opacity(0.35))
      .frame(width: 44, height: 5)
      .frame(maxWidth: .infinity)
      .frame(height: 26)
      .contentShape(Rectangle())
      .gesture(heightDrag)
      .accessibilityIdentifier("keyboardHeightGrip")
      .accessibilityLabel("键盘高度")
      .accessibilityValue(format(height))
      .accessibilityAdjustableAction { direction in
        height = clamp(height + (direction == .increment ? 2 : -2), -12, 48)
        KeyboardLayoutPreference.heightAdjustment = height
      }
  }

  private var dragHint: String {
    switch dragAxis {
    case .vertical: return "行间距 \(String(format: "%.1f", rowSpacing))"
    case .horizontal: return "按键间距 \(String(format: "%.1f", keySpacing))"
    case nil: return "拖上面的把手改高度，在键盘上左右拖改键距、上下拖改行间距"
    }
  }

  private var heightDrag: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let base = dragBase ?? snapshot()
        if dragBase == nil { dragBase = base }
        height = clamp(base.height - Double(value.translation.height), -12, 48)
        KeyboardLayoutPreference.heightAdjustment = height
      }
      .onEnded { _ in dragBase = nil }
  }

  private var spacingDrag: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        let base = dragBase ?? snapshot()
        if dragBase == nil { dragBase = base }
        let axis = dragAxis
          ?? (abs(value.translation.height) >= abs(value.translation.width) ? .vertical : .horizontal)
        dragAxis = axis
        switch axis {
        case .vertical:
          rowSpacing = clamp(base.rowSpacing + Double(value.translation.height) / Self.spacingDragScale, 4, 10)
          KeyboardLayoutPreference.rowSpacing = rowSpacing
        case .horizontal:
          keySpacing = clamp(base.keySpacing + Double(value.translation.width) / Self.spacingDragScale, 3, 6)
          KeyboardLayoutPreference.keySpacing = keySpacing
        }
      }
      .onEnded { _ in
        dragBase = nil
        dragAxis = nil
      }
  }

  private func snapshot() -> (height: Double, keySpacing: Double, rowSpacing: Double) {
    (height, keySpacing, rowSpacing)
  }

  private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(upper, max(lower, value))
  }

  private func format(_ value: Double) -> String {
    value > 0 ? "+\(Int(value))" : "\(Int(value))"
  }

  private var form: some View {
    Form {
      Section {
        spacingRow("键盘高度", value: $height, range: -12...48, identifier: "appKeyboardHeightSlider",
                   format: { $0 > 0 ? "+\(Int($0))" : "\(Int($0))" }) {
          KeyboardLayoutPreference.heightAdjustment = $0
        }
      } header: {
        Text("键盘高度")
      } footer: {
        Text("在系统键盘高度的基础上增减，按键会跟着变高。上面的预览实时跟着走；已经打开的键盘要重新唤出才生效。")
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
        Text("间距只改变键位外观，不影响输入方案。键盘布局在键盘的布局按钮里切换。")
      }
      Section {
        Toggle("顶部语音入口", isOn: $voice)
          .accessibilityIdentifier("appVoiceShortcutSwitch")
          .onChange(of: voice) { KeyboardLayoutPreference.voiceShortcutEnabled = $0 }
        NavigationLink(destination: ServiceSettingsView(kind: .voice)) {
          Label("语音设置", systemImage: "waveform")
        }.accessibilityIdentifier("voiceSettingsLink")
      } header: {
        Text("快捷入口")
      } footer: {
        Text("语音入口用于打开已识别的语音结果。")
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
  }

  private func readPreferences() {
    keySpacing = KeyboardLayoutPreference.keySpacing
    rowSpacing = KeyboardLayoutPreference.rowSpacing
    height = KeyboardLayoutPreference.heightAdjustment
    skin = KeyboardSkinPreference.selected
    nineKey = InputSchemePreference.scheme == .nineKey
    voice = KeyboardLayoutPreference.voiceShortcutEnabled
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
