import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

/// 编辑器的顶层分栏。
///
/// 原先这是一个 `String`,取值有六个,而标签栏只画得出四个:「设计」和「我的」没有格子,只能从背景页里的按钮或工具菜单进,进去之后 `activeCategory` 又把它们映射回「背景」—— 人站在一个标签栏说他不在的页面上,而唯一的出路是点那个已经高亮着的格子。每个屏幕都有自己的格子,这件事就不会发生。
private enum SkinEditorTab: String, CaseIterable, Identifiable {
  case template = "模板", background = "背景", keys = "按键", text = "文本", library = "我的"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .template: return "square.grid.2x2"
    case .background: return "rectangle.on.rectangle"
    case .keys: return "square.on.square"
    case .text: return "textformat"
    case .library: return "square.stack"
    }
  }
}

struct CustomSkinEditorView: View {
  /// 从发布页推进来的那一份不提供发布入口。两边互相能进对方就成了环:发布页 → 去设计一款 → 编辑器 → 发布到社区 → 发布页 → …… 一层套一层没有尽头。推进来的这一程只负责把设计做出来,回去就是发布。
  var publishable = true
  @Environment(\.scenePhase) private var scenePhase
  @State private var design = CustomKeyboardSkinStore.current
  @State private var nineKey = InputSchemePreference.scheme == .nineKey
  @State private var confirmReset = false
  @State private var section = SkinEditorTab.background
  @State private var undo: [CustomKeyboardSkin] = []
  @State private var redo: [CustomKeyboardSkin] = []
  @State private var sliderStart: CustomKeyboardSkin?
  @State private var saved = CustomSkinLibrary.designs
  @State private var showSave = false
  @State private var name = ""
  @State private var renaming: UUID?
  @State private var deleting: SavedKeyboardSkin?
  @State private var replacing: SavedKeyboardSkin?
  @State private var showAI = false
  @State private var showPhotos = false
  @State private var publishingSkin: SavedKeyboardSkin?
  @State private var message: String?


  private func apply(_ next: CustomKeyboardSkin, record: Bool = true) {
    let next = next.normalized
    guard next != design else { return }
    if record { undo.append(design); undo = Array(undo.suffix(30)); redo.removeAll() }
    CustomKeyboardSkinStore.save(next)
    design = next
  }
  @AppStorage(KeyboardSkinPreference.key, store: KeyboardFeedbackPreference.defaults)
  private var selected = KeyboardSkin.forest.rawValue

  private func update<T>(_ path: WritableKeyPath<CustomKeyboardSkin, T>, _ value: T) {
    var next = design
    next[keyPath: path] = value
    apply(next, record: sliderStart == nil)
  }

  private func trackSlider(_ editing: Bool) {
    if editing { sliderStart = design }
    else {
      if let start = sliderStart, start != design { undo.append(start); undo = Array(undo.suffix(30)); redo.removeAll() }
      sliderStart = nil
    }
  }

  private func color(_ path: WritableKeyPath<CustomKeyboardSkin, UInt32>) -> Binding<Color> {
    Binding(get: { Color(uiColor: CustomKeyboardSkin.color(design[keyPath: path])) },
            set: { update(path, CustomKeyboardSkin.rgb(UIColor($0))) })
  }

  private func value<T>(_ path: WritableKeyPath<CustomKeyboardSkin, T>) -> Binding<T> {
    Binding(get: { design[keyPath: path] }, set: { update(path, $0) })
  }

  private var categoryBar: some View {
    HStack(spacing: 0) {
      ForEach(SkinEditorTab.allCases) { tab in
        let active = section == tab
        Button { section = tab } label: {
          VStack(spacing: 5) {
            Group {
              if tab == .text { Text("T").font(.system(size: 22, weight: .medium, design: .serif)) }
              else { Image(systemName: tab.symbol).font(.system(size: 20, weight: .regular)) }
            }.frame(height: 24)
            Text(tab.rawValue).font(.system(size: 12, weight: active ? .semibold : .regular))
          }.frame(maxWidth: .infinity).frame(height: 62)
            .foregroundStyle(active ? MetasequoiaTheme.forest : Color.secondary)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("skinEditorTab_" + tab.rawValue)
          .accessibilityAddTraits(active ? .isSelected : [])
      }
    }.background(Color(uiColor: .systemBackground))
  }

  private func previewDock() -> some View {
    VStack(spacing: 0) {
      Divider()
      HStack(spacing: 10) {
        Button {
          guard let previous = undo.popLast() else { return }; redo.append(design); apply(previous, record: false)
        } label: { Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 38) }
          .disabled(undo.isEmpty || sliderStart != nil).accessibilityLabel("撤销设计").accessibilityIdentifier("undoSkinDesign")
        Button {
          guard let next = redo.popLast() else { return }; undo.append(design); apply(next, record: false)
        } label: { Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 38) }
          .disabled(redo.isEmpty || sliderStart != nil).accessibilityLabel("重做设计").accessibilityIdentifier("redoSkinDesign")
        Picker("预览布局", selection: $nineKey) {
          Text("26 键").tag(false); Text("9 键").tag(true)
        }.pickerStyle(.segmented).frame(width: 118).accessibilityIdentifier("skinEditorPreviewLayout")
        Spacer(minLength: 0)
        Button { selected = KeyboardSkin.custom.rawValue } label: {
          Label(selected == KeyboardSkin.custom.rawValue ? "正在使用" : "使用皮肤", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
        }.accessibilityIdentifier("applyCustomSkin")
      }.padding(.horizontal, 12).background(Color(uiColor: .systemBackground))
      KeyboardSkinPreview(skin: .custom, nineKey: nineKey).id(design)
        .accessibilityIdentifier("fullKeyboardSkinPreview")
    }
  }

  private var backgroundGallery: some View {
    Section {
      Button { showPhotos = true } label: {
        Label("从相册选一张", systemImage: "photo.badge.plus").frame(maxWidth: .infinity).frame(height: 44)
      }.buttonStyle(.bordered).tint(MetasequoiaTheme.forest).accessibilityIdentifier("skinEditorAlbum")
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
        ForEach(Array(backgroundPresets.enumerated()), id: \.offset) { index, preset in
          let active = design.photo == nil && design.background == preset.0 && design.gradientEnd == preset.1
          Button {
            var next = design; next.photo = nil; next.background = preset.0; next.gradientEnd = preset.1
            next.gradientHorizontal = false
            apply(next)
          } label: {
            RoundedRectangle(cornerRadius: 10)
              .fill(LinearGradient(colors: [Color(uiColor: CustomKeyboardSkin.color(preset.0)), Color(uiColor: CustomKeyboardSkin.color(preset.1 ?? preset.0))], startPoint: .topLeading, endPoint: .bottomTrailing))
              .frame(height: 74)
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? MetasequoiaTheme.forest : Color.primary.opacity(0.08), lineWidth: active ? 2 : 1))
              .overlay(alignment: .bottomTrailing) {
                if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, MetasequoiaTheme.forest).padding(6) }
              }
          }.buttonStyle(.plain).accessibilityLabel(preset.2)
            .accessibilityIdentifier("skinBackgroundPreset_\(index)")
            .accessibilityAddTraits(active ? .isSelected : [])
        }
      }
    }.listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
  }

  private var backgroundPresets: [(UInt32, UInt32?, String)] {
    [(0xFFFFFF, nil, "纯白"), (0xDFE2EB, nil, "雾灰"), (0x171717, nil, "曜黑"),
     (0xFFD5DB, nil, "樱粉"), (0xAEE3F3, nil, "晴空"), (0xC6E9A7, nil, "嫩绿"),
     (0x160A3F, 0xA747DF, "紫夜渐变"), (0xC5F5FF, 0xFAD8F6, "极光渐变"), (0x185C47, 0x80BFA8, "森林渐变")]
  }

  private var editorControls: some View {
  Form {
    if section == .background { backgroundGallery }
    if section == .template {
      // 整套设计的三个来源放在一起:抽一张、挑一款、或者推倒重来。原先 AI 和模板顶在「背景」那一组上面,而它们换掉的远不止背景。
      Section {
        Button { showAI = true } label: {
          Label("AI 皮肤抽卡", systemImage: "sparkles").font(.headline)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }.accessibilityIdentifier("openAISkinDesigner")
      } footer: {
        Text("选择模板后，继续到背景、按键和文本里细调。修改自动保存；撤销可找回刚才的设计，到「我的」命名保存可以留下多套方案。")
      }
      Section("水杉设计 · 14 款") {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
          ForEach(CustomKeyboardSkin.curatedTemplates + Array(CustomKeyboardSkin.templates.prefix(6)), id: \.0) { title, template in
            Button { apply(template) } label: {
              VStack(alignment: .leading, spacing: 10) {
                CommunityDesignPreview(design: template)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color(uiColor: CustomKeyboardSkin.color(template.accent)))
              }.padding(10).background(LinearGradient(colors: [Color(uiColor: CustomKeyboardSkin.color(template.background)), Color(uiColor: CustomKeyboardSkin.color(template.gradientEnd ?? template.background))], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("skinTemplate_" + title)
          }
        }
      }
      Section {
        SettingsActionRow(title: "重置我的皮肤", detail: "回到默认外观，已保存的方案不受影响",
                          symbol: "arrow.counterclockwise", destructive: true) { confirmReset = true }
          .accessibilityIdentifier("resetCustomSkin")
      }
    }
    if section == .background {
      Section("背景底色") {
        ColorPicker("背景起始色", selection: color(\.background), supportsOpacity: false)
        Toggle("渐变背景", isOn: Binding(get: { design.gradientEnd != nil }, set: { update(\.gradientEnd, $0 ? design.background : nil) }))
          .accessibilityIdentifier("customSkinGradient")
        if design.gradientEnd != nil {
          ColorPicker("渐变结束色", selection: Binding(get: { Color(uiColor: CustomKeyboardSkin.color(design.gradientEnd ?? design.background)) }, set: { update(\.gradientEnd, CustomKeyboardSkin.rgb(UIColor($0))) }), supportsOpacity: false)
          Toggle("横向渐变", isOn: Binding(get: { design.gradientHorizontal ?? false }, set: { update(\.gradientHorizontal, $0) }))
        }
      }
      Section("照片壁纸") {
        Button { showPhotos = true } label: { Label(design.photo == nil ? "选择照片" : "更换照片", systemImage: "photo") }
          .accessibilityIdentifier("customSkinPhoto")
        if design.photo != nil {
          Text("照片位置").font(.subheadline)
          Slider(value: Binding(get: { design.photoPosition ?? 0.5 }, set: { update(\.photoPosition, $0) }), in: 0...1, onEditingChanged: trackSlider)
          Text("压暗照片 · \(Int((design.photoShade ?? 0.25) * 100))%")
          Slider(value: Binding(get: { design.photoShade ?? 0.25 }, set: { update(\.photoShade, $0) }), in: 0...0.8, onEditingChanged: trackSlider)
          Button("移除照片", role: .destructive) { update(\.photo, nil) }
        }
      }
      Section("纹理") {
        Picker("背景纹理", selection: value(\.pattern)) {
          Text("纯色").tag(0); Text("网点").tag(1); Text("网格").tag(2); Text("波纹").tag(3)
        }.accessibilityIdentifier("customSkinPattern")
        if design.pattern != 0 {
          Text("纹理强度 · \(Int((design.patternOpacity ?? 0.15) * 100))%")
          Slider(value: Binding(get: { design.patternOpacity ?? 0.15 }, set: { update(\.patternOpacity, $0) }), in: 0...0.5, onEditingChanged: trackSlider)
        }
      }
    }
    if section == .text {
Section("文字与提示") {
  Toggle("等宽字形", isOn: value(\.monospaced)).accessibilityIdentifier("customSkinMonospaced")
  ColorPicker("按键文字", selection: color(\.keyForeground), supportsOpacity: false)
  ColorPicker("提示与工具栏", selection: color(\.accent), supportsOpacity: false)
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
    apply(next)
  }
}
}
if section == .keys {
Section("按键配色") {
  ColorPicker("键帽颜色", selection: color(\.keyBackground), supportsOpacity: false)
  ColorPicker("功能键颜色", selection: color(\.actionBackground), supportsOpacity: false)
}
Section("键帽设计") {
  Picker("键帽造型", selection: Binding(get: { design.keyShape ?? .rounded }, set: { update(\.keyShape, $0) })) {
    ForEach(SkinKeyShape.allCases, id: \.self) { Text($0.title).tag($0) }
  }.accessibilityIdentifier("customSkinKeyShape")
  Picker("键帽材质", selection: Binding(get: { design.keyMaterial ?? .flat }, set: { update(\.keyMaterial, $0) })) {
    ForEach(SkinKeyMaterial.allCases, id: \.self) { Text($0.title).tag($0) }
  }.accessibilityIdentifier("customSkinKeyMaterial")
  VStack(alignment: .leading) {
    Text("键帽不透明度 · \(Int((design.keyOpacity ?? 1) * 100))%")
    Slider(value: Binding(get: { design.keyOpacity ?? 1 }, set: { update(\.keyOpacity, $0) }), in: 0.25...1, onEditingChanged: trackSlider)
      .accessibilityIdentifier("customSkinKeyOpacity")
  }
  if design.photo != nil || (design.keyOpacity ?? 1) < 1 {
    Text("半透明键帽会露出背景。可在“背景”中压暗照片，让文字更清晰。").font(.footnote).foregroundStyle(.secondary)
  }
  VStack(alignment: .leading) {
    Text("圆角 · \(Int(design.cornerRadius))")
    Slider(value: value(\.cornerRadius), in: 0...20, step: 1, onEditingChanged: trackSlider)
      .accessibilityIdentifier("customSkinCornerRadius")
  }
  VStack(alignment: .leading) {
    Text("边框 · \(design.borderWidth, specifier: "%.1f")")
    Slider(value: value(\.borderWidth), in: 0...2, step: 0.5, onEditingChanged: trackSlider)
  }
  VStack(alignment: .leading) {
    Text("阴影 · \(Int(design.shadow * 100))%")
    Slider(value: value(\.shadow), in: 0...0.4, step: 0.05, onEditingChanged: trackSlider)
  }
  ColorPicker("边框颜色", selection: Binding(get: { Color(uiColor: CustomKeyboardSkin.color(design.customBorderColor ?? design.accent)) }, set: { update(\.customBorderColor, CustomKeyboardSkin.rgb(UIColor($0))) }), supportsOpacity: false)
}
}
if section == .library {
  Section("我的皮肤 · \(saved.count)/12") {
    if saved.isEmpty { Text("还没有命名保存的皮肤。调整满意后，点击右上角“保存”。").foregroundStyle(.secondary) }
    ForEach(saved) { item in
      HStack {
        Button { apply(item.design) } label: {
          HStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(uiColor: CustomKeyboardSkin.color(item.design.background))).frame(width: 32, height: 32)
            Text(item.name)
          }
        }.accessibilityIdentifier("savedSkin_" + item.name)
        Spacer()
        Menu {
          if publishable { Button("发布到社区") { publishingSkin = item } }
          Button("用当前设计更新") { replacing = item }
          Button("重命名") { renaming = item.id; name = item.name; showSave = true }
          Button("删除", role: .destructive) { deleting = item }
        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
          .accessibilityLabel("管理" + item.name)
      }
    }
  }
}
  }
  .id(section)
  .accessibilityIdentifier("skinEditorControls")
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        categoryBar
        if geometry.size.width > geometry.size.height {
          HStack(spacing: 0) {
            editorControls
            previewDock().frame(width: geometry.size.width * 0.55)
          }
        } else {
          editorControls
          previewDock()
        }
      }
      .background(Color(uiColor: .systemGroupedBackground))
    }
    .onChange(of: scenePhase) { phase in
      guard phase == .active else { return }
      let current = CustomKeyboardSkinStore.current
      if current != design { design = current; undo.removeAll(); redo.removeAll() }
      saved = CustomSkinLibrary.designs
    }
    .navigationTitle("自定义皮肤")
    .navigationBarTitleDisplayMode(.inline)
    // 这一页自己的底栏已经钉在下沿:撤销、重做、预览布局、使用皮肤,再加一整块键盘预览。系统的标签栏压在它下面就是两条栏叠着,而 iOS 26 的标签栏是浮在内容上的,会直接盖掉预览的最后一行。
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        HStack(spacing: 10) {
          Button { renaming = nil; name = "我的设计 \(saved.count + 1)"; showSave = true } label: {
            Text("保存").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 7)
              .foregroundStyle(.white).background(MetasequoiaTheme.forest, in: Capsule())
          }.accessibilityIdentifier("saveCustomSkin")
        }
      }
    }
    .sheet(isPresented: $showAI, onDismiss: { saved = CustomSkinLibrary.designs }) {
      AISkinGenerationView { next in apply(next); selected = KeyboardSkin.custom.rawValue; section = .keys }
    }
    .sheet(item: $publishingSkin) { item in SavedSkinPublishFlow(skinID: item.id) }
    .sheet(isPresented: $showPhotos) {
      SkinPhotoPicker { data in
        showPhotos = false
        if let data { update(\.photo, data) }
        else { message = "无法读取这张照片，请换一张再试。" }
      }
    }
    .sheet(isPresented: $showSave) {
      NavigationView {
        Form {
          TextField("皮肤名称", text: $name).accessibilityIdentifier("customSkinName")
            .onChange(of: name) { if $0.count > 32 { name = String($0.prefix(32)) } }
          Button("保存") {
            let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            guard !saved.contains(where: { $0.id != renaming && $0.name == title }) else {
              showSave = false; message = "已经有同名皮肤，请换一个名称。"; return
            }
            if let id = renaming, let index = saved.firstIndex(where: { $0.id == id }) { saved[index].name = title }
            else if saved.count < 12 { saved.append(SavedKeyboardSkin(name: title, design: design)) }
            else { showSave = false; message = "最多保存 12 套皮肤，请先删除不需要的设计。"; return }
            guard CustomSkinLibrary.save(saved) else {
              saved = CustomSkinLibrary.designs
              showSave = false; message = "保存失败，请检查设备可用空间后重试。"; return
            }
            if renaming == nil { selected = KeyboardSkin.custom.rawValue }
            showSave = false
            section = .library
          }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("confirmSaveCustomSkin")
        }.navigationTitle(renaming == nil ? "保存我的皮肤" : "重命名")
          .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showSave = false } } }
      }
    }
    .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
      Button("好") { message = nil }
    } message: { Text(message ?? "") }
    .confirmationDialog("用当前设计更新“\(replacing?.name ?? "")”？", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }), titleVisibility: .visible) {
      Button("更新已保存的皮肤") {
        if let item = replacing, let index = saved.firstIndex(where: { $0.id == item.id }) {
          saved[index].design = design
          if !CustomSkinLibrary.save(saved) { saved = CustomSkinLibrary.designs; message = "保存失败，请重试。" }
        }
        replacing = nil
      }
    }
    .confirmationDialog("删除这套已保存的皮肤？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
      Button("删除", role: .destructive) {
        if let item = deleting {
          saved.removeAll { $0.id == item.id }
          if !CustomSkinLibrary.save(saved) { saved = CustomSkinLibrary.designs; message = "删除失败，请重试。" }
        }
        deleting = nil
      }
    }
    .confirmationDialog("恢复默认配色和键帽设计？", isPresented: $confirmReset, titleVisibility: .visible) {
      Button("重置", role: .destructive) {
        let initial = CustomKeyboardSkin()
        apply(initial)
      }
      Button("取消", role: .cancel) {}
    }
  }
}

// The system picker grants access only to the chosen image; no library-wide permission is needed.
struct SkinPhotoPicker: UIViewControllerRepresentable {
  let receive: (Data?) -> Void
  @Environment(\.dismiss) private var dismiss
  func makeCoordinator() -> Coordinator { Coordinator(receive: receive, cancel: { dismiss() }) }
  func makeUIViewController(context: Context) -> PHPickerViewController {
    var config = PHPickerConfiguration()
    config.filter = .images; config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = context.coordinator
    return picker
  }
  func updateUIViewController(_ view: PHPickerViewController, context: Context) {}
  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let receive: (Data?) -> Void
    let cancel: () -> Void
    init(receive: @escaping (Data?) -> Void, cancel: @escaping () -> Void) { self.receive = receive; self.cancel = cancel }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      guard let item = results.first else { cancel(); return }
      item.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [self] url, _ in
        let result = url.flatMap { SkinPhotoData.thumbnail(at: $0) }
        DispatchQueue.main.async { self.receive(result) }
      }
    }
  }
}
