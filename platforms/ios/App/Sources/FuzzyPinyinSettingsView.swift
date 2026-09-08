import SwiftUI

struct FuzzyPinyinSettingsView: View {
  @AppStorage(FuzzyPinyinPreference.enabledKey, store: FuzzyPinyinPreference.defaults) private var enabled = false
  @AppStorage(FuzzyPinyinPreference.rulesKey, store: FuzzyPinyinPreference.defaults) private var storedRules = ""
  @State private var confirmingReset = false

  private let groups: [(String, [(String, String)])] = [
    ("平翘舌", [("z-zh", "z ↔ zh"), ("c-ch", "c ↔ ch"), ("s-sh", "s ↔ sh")]),
    ("声母", [("n-l", "n ↔ l"), ("f-h", "f ↔ h"), ("r-l", "r ↔ l")]),
    ("前后鼻音", [("an-ang", "an ↔ ang"), ("en-eng", "en ↔ eng"), ("in-ing", "in ↔ ing")]),
    ("其他韵母", [("ian-iang", "ian ↔ iang"), ("uan-uang", "uan ↔ uang")]),
  ]

  private func selection(_ id: String) -> Binding<Bool> {
    Binding(get: { storedRules.split(separator: ",").contains(Substring(id)) }, set: { selected in
      var rules = Set(storedRules.split(separator: ",").map(String.init))
      if selected { rules.insert(id) } else { rules.remove(id) }
      storedRules = rules.sorted().joined(separator: ",")
    })
  }

  var body: some View {
    Form {
      Section {
        Label("全拼、九键与双拼均支持", systemImage: "info.circle")
          .foregroundStyle(.secondary).accessibilityIdentifier("fuzzyPinyinAvailability")
        Text("勾选容易混淆的读音后，会补充对应候选。更改会在当前输入结束后生效。").font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        Toggle("启用模糊音", isOn: $enabled).accessibilityIdentifier("fuzzyPinyinEnabled")
      } footer: {
        Text("模糊音用于兼容容易混淆的拼音读音。只选择你需要的规则，避免增加无关候选。关闭总开关会保留已选规则。")
      }
      ForEach(groups, id: \.0) { title, rules in
        Section(title) {
          ForEach(rules, id: \.0) { id, label in
            Toggle(label, isOn: selection(id)).disabled(!enabled)
              .accessibilityIdentifier("fuzzyPinyinRule_" + id)
          }
        }
      }
      Section {
        Button("重置模糊音配置", role: .destructive) { confirmingReset = true }
      }
    }.navigationTitle("模糊音").navigationBarTitleDisplayMode(.inline)
      .confirmationDialog("关闭模糊音并清空所有规则？", isPresented: $confirmingReset, titleVisibility: .visible) {
        Button("重置", role: .destructive) { enabled = false; storedRules = "" }
      }
  }
}
