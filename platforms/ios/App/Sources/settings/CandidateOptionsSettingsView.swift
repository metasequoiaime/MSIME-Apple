import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Candidate text size and font, the candidate skin, what the strip shows while spelling, pinyin typo correction, 以词定字, cloud candidates, and what gets mixed into the Chinese candidates.
///
/// Like the punctuation page, these live only in the shared preference document, nested under `quanpin`, `word_character` and `mixed_input`, so each write merges one field into its object and leaves the rest of the object as stored. Cloud candidates are the exception: an iOS-only switch in the App Group (see CloudCandidatePreference). The keyboard hands a change to its live session the next time it appears. The candidate skin, theme and colours are shared too, and the switch that lets them replace the keyboard skin's colours is iOS-only (see CandidatePalette).
struct CandidateOptionsSettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var transposition = false
  @State private var neighbor = false
  @State private var english = true
  @State private var minimumPrefix = 5
  @State private var emoji = false
  @State private var kaomoji = false
  @State private var wordCharacter = true
  @AppStorage(CloudCandidatePreference.key, store: CloudCandidatePreference.defaults)
  private var cloudCandidates = false
  @AppStorage(CandidatePageSizePreference.key, store: CandidatePageSizePreference.defaults)
  private var pageSize = CandidatePageSizePreference.defaultSize
  @AppStorage(EnglishSuggestionsPreference.enabledKey, store: EnglishSuggestionsPreference.defaults)
  private var englishSuggestions = true
  @State private var candidateSize = CandidateFontPreference.defaultCandidateSize
  @State private var preeditSize = CandidateFontPreference.defaultPreeditSize
  @State private var fontFamily = CandidateFontPreference.defaultFamily
  @State private var englishFamily: String?
  @State private var fontFamilies: [String] = []
  @State private var fallbackFamilies = CandidateFontPreference.defaultFallbackFamilies
  @State private var preeditStyle = CandidatePreeditStyle.pinyin.rawValue
  @State private var shuangpinRaw = true
  @State private var inlinePreedit = InlinePreeditPreference.style
  @AppStorage(CandidatePalette.followsDesktopKey, store: CandidatePalette.defaults)
  private var followsDesktopPalette = false
  @State private var candidateSkin = CandidatePalette.defaultSkin
  @State private var candidateTheme = "follow"
  @State private var globalTheme = "system"
  @State private var candidateColors: [String: String] = [:]
  @State private var installedSkins: [(id: String, skin: ExternalCandidateSkin)] = []
  @State private var importingSkin = false
  @State private var skinStatus = ""
  @Environment(\.colorScheme) private var colorScheme
  @State private var saveFailed = false
  /// A docked iPad keyboard has room for larger candidates than a phone strip; the keyboard applies the same limits when it draws.
  private let tablet = UIDevice.current.userInterfaceIdiom == .pad

  var body: some View {
    Form {
      Section {
        Stepper(value: storedTop(CandidateFontPreference.candidateKey, $candidateSize),
                in: CandidateFontPreference.candidateRange(tablet: tablet)) {
          VStack(alignment: .leading, spacing: 2) {
            Text("候选字号：\(candidateSize)")
            Text("水杉输入法 MSIME").font(Font(CandidateFontPreference.font(
              .body, scale: CGFloat(candidateSize) / CGFloat(CandidateFontPreference.defaultCandidateSize),
              families: fontFamilies)))
          }
        }.accessibilityIdentifier("candidateFontSize")
        Stepper(value: storedTop(CandidateFontPreference.preeditKey, $preeditSize),
                in: CandidateFontPreference.preeditRange(tablet: tablet)) {
          VStack(alignment: .leading, spacing: 2) {
            Text("编码字号：\(preeditSize)")
            Text("shui'shan").font(Font(CandidateFontPreference.font(
              .subheadline, scale: CGFloat(preeditSize) / CGFloat(CandidateFontPreference.defaultPreeditSize))))
          }
        }.accessibilityIdentifier("candidatePreeditFontSize")
        NavigationLink {
          CandidateFontFamilyList(title: "中文字体", selection: fontFamily, none: nil) { family in
            write { $0[CandidateFontPreference.familyKey] = family ?? CandidateFontPreference.defaultFamily }
          }
        } label: {
          LabeledContent("中文字体", value: familyTitle(fontFamily))
        }.accessibilityIdentifier("candidateFontFamily")
        NavigationLink {
          CandidateFontFamilyList(title: "英文字体", selection: englishFamily, none: "跟随中文字体") { family in
            write { $0[CandidateFontPreference.englishFamilyKey] = family }
          }
        } label: {
          LabeledContent("英文字体", value: englishFamily.map(familyTitle) ?? "跟随中文字体")
        }.accessibilityIdentifier("candidateEnglishFont")
        NavigationLink {
          CandidateFallbackFontList(families: fallbackFamilies) { families in
            write { $0[CandidateFontPreference.fallbackFamiliesKey] = families }
            return fallbackFamilies
          }
        } label: {
          LabeledContent("补充字体", value: "\(fallbackFamilies.count) 个")
        }.accessibilityIdentifier("candidateFallbackFonts")
      } header: {
        Text("字号与字体")
      } footer: {
        Text((tablet
          ? "默认 18 和 15，与桌面端同步。候选栏会随字号变高；浮动的小键盘按手机的上限显示。"
          : "默认 18 和 15，与桌面端同步。候选栏会随字号变高；桌面端设得更大时，手机上最多显示到 24 和 20。")
          + "字体与桌面端同步；中英文字体缺字时依次使用补充字体。此设备没有的字体会跳过，全都没有时使用系统字体。")
      }
      paletteSection
      Section {
        Stepper(value: Binding(get: { CandidatePageSizePreference.clamped(pageSize) }, set: { pageSize = CandidatePageSizePreference.clamped($0) }),
                in: CandidatePageSizePreference.range) {
          labelled("每页候选数：\(CandidatePageSizePreference.clamped(pageSize))", "候选栏编号的候选个数，其余的展开候选面板查看")
        }.accessibilityIdentifier("candidatePageSize")
      } footer: {
        Text("默认 9 个，与符号键盘和 iPad 数字行的 1–9 对应；组字时按数字键选对应编号的候选。只在本机生效，不影响电脑上的候选窗口。")
      }
      Section {
        Picker(selection: Binding(get: { inlinePreedit }, set: { inlinePreedit = $0; InlinePreeditPreference.style = $0 })) {
          ForEach(InlinePreeditPreference.Style.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
          labelled("行内预编辑", "把正在拼写的编码也写进输入框，像系统键盘那样带下划线显示")
        }.accessibilityIdentifier("inlinePreedit")
        Picker("候选栏预编辑", selection: storedTop(CandidatePreeditStyle.key, $preeditStyle)) {
          ForEach(CandidatePreeditStyle.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
        }.accessibilityIdentifier("candidatePreeditStyle")
        Toggle(isOn: storedTop("shuangpin_preedit_uses_raw", $shuangpinRaw)) {
          labelled("双拼显示原始按键", "关闭后显示按键对应的完整拼音，只对双拼生效")
        }.accessibilityIdentifier("shuangpinPreeditUsesRaw")
      } header: {
        Text("预编辑")
      } footer: {
        Text("行内预编辑默认关闭；个别 App 显示输入框里的组字不完整时可以关掉。候选栏预编辑选「不显示」时，候选栏不再显示正在拼写的编码，把位置留给候选；已选定的半个词和本地输入模式的名称仍会显示。")
      }
      Section {
        Toggle(isOn: stored("quanpin", "autocorrect_transposition", $transposition)) {
          labelled("字母顺序错位", "例如把 shang 输入为 sahng")
        }.accessibilityIdentifier("autocorrectTransposition")
        Toggle(isOn: stored("quanpin", "autocorrect_neighbor", $neighbor)) {
          labelled("相邻键误触", "例如把 shang 输入为 shabg")
        }.accessibilityIdentifier("autocorrectNeighbor")
      } header: {
        Text("全拼纠错")
      } footer: {
        Text("分别控制字母错位和邻键误触的拼音纠错，只对全拼生效。")
      }
      Section {
        Toggle(isOn: stored("word_character", "enabled", $wordCharacter)) {
          labelled("以词定字", "长按两个字以上的候选，可以只上屏它的首字或末字")
        }.accessibilityIdentifier("wordCharacter")
      }
      Section {
        Toggle(isOn: $cloudCandidates) {
          labelled("云候选", "输入停顿时向 Google 输入法服务查询候选，排进候选栏")
        }.accessibilityIdentifier("cloudCandidates")
      } footer: {
        Text("默认关闭。开启后，正在输入的编码会发送到 Google 输入法服务；还需要在系统设置中允许键盘完全访问。")
      }
      Section {
        Toggle(isOn: $englishSuggestions) {
          labelled("英文单词提示", "英文输入时在候选栏提示常用单词，点选补全当前单词")
        }.accessibilityIdentifier("englishSuggestions")
      }
      Section {
        Toggle(isOn: stored("mixed_input", "english", $english)) {
          labelled("中英混输", "中文输入时在候选中补充英文单词")
        }.accessibilityIdentifier("mixedEnglish")
        Stepper(value: stored("mixed_input", "minimum_prefix", $minimumPrefix), in: 1...8) {
          labelled("触发字母数：\(minimumPrefix)", "输入的字母达到这个长度后才出现英文候选")
        }
        .disabled(!english)
        .accessibilityIdentifier("mixedEnglishMinimumPrefix")
      }
      Section {
        Toggle(isOn: stored("mixed_input", "emoji", $emoji)) {
          labelled("emoji 混输", "在候选中加入匹配的 emoji，排在英文候选之后")
        }.accessibilityIdentifier("mixedEmoji")
        Toggle(isOn: stored("mixed_input", "kaomoji", $kaomoji)) {
          labelled("颜文字混输", "在候选中加入匹配的颜文字，排在 emoji 之后")
        }.accessibilityIdentifier("mixedKaomoji")
      } footer: {
        if saveFailed { Text("设置没有保存，键盘可能正在写入同一份设置，请再试一次。") }
      }
    }
    .navigationTitle("候选与纠错").navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scenePhase) { if $0 == .active { reload() } }
  }

  private var paletteSection: some View {
    Section {
      Toggle(isOn: $followsDesktopPalette) {
        labelled("使用桌面候选皮肤", "关闭时候选栏跟随键盘皮肤")
      }.accessibilityIdentifier("candidatePaletteFollowsDesktop")
      if followsDesktopPalette {
        Picker("皮肤", selection: storedTop("candidate_skin", $candidateSkin)) {
          ForEach(CandidatePalette.skins, id: \.id) { Text($0.title).tag($0.id) }
          ForEach(installedSkins.filter { $0.skin.horizontal }, id: \.id) { package in
            Text(Self.title(package.skin)).tag(package.id)
          }
        }.accessibilityIdentifier("candidateSkin")
        Button("导入皮肤…") { importingSkin = true }
          .accessibilityIdentifier("candidateSkinImport")
        if let selected = installedSkins.first(where: { $0.id == candidateSkin }) {
          Button("删除「\(selected.skin.name)」", role: .destructive) { removeSkin(selected.id) }
            .accessibilityIdentifier("candidateSkinRemove")
        }
        if !skinStatus.isEmpty {
          Text(skinStatus).font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("candidateSkinStatus")
        }
        Picker("明暗", selection: storedTop("candidate_theme", $candidateTheme)) {
          ForEach(CandidatePalette.themes, id: \.id) { Text($0.title).tag($0.id) }
        }.accessibilityIdentifier("candidateTheme")
        ForEach(CandidatePalette.editableColors, id: \.key) { item in
          ColorPicker(item.title, selection: colorBinding(item.key), supportsOpacity: false)
            .accessibilityIdentifier(item.key)
        }
        if !candidateColors.isEmpty {
          Button("恢复皮肤颜色", role: .destructive, action: clearColors)
            .accessibilityIdentifier("candidateColorsReset")
        }
        palettePreview
      }
    } header: {
      Text("候选皮肤")
    } footer: {
      Text(followsDesktopPalette
        ? "皮肤、明暗和颜色与电脑版的候选窗同步；首选候选使用皮肤的高亮色。“明暗”选跟随系统时，先看共享的主题设置。\n\n“导入皮肤”从“文件”里选一个含 skin.toml 的皮肤文件夹，复制进键盘能读到的共享目录，同名皮肤整个替换。候选栏是横排的，只列出支持横排的皮肤；皮肤没声明的明暗下仍用杨柳青。"
        : "默认关闭，候选栏和按键一起使用键盘皮肤的颜色。")
    }
    .fileImporter(isPresented: $importingSkin, allowedContentTypes: [.folder]) { importSkin($0) }
  }

  /// A package that declares one appearance says so, since the other falls back to the default skin.
  private static func title(_ skin: ExternalCandidateSkin) -> String {
    if skin.themes == ["light"] { return skin.name + "（仅浅色）" }
    if skin.themes == ["dark"] { return skin.name + "（仅深色）" }
    return skin.name
  }

  /// The copy runs off the main thread: a picked folder can hold up to the import's size limit of assets.
  private func importSkin(_ result: Result<URL, Error>) {
    guard case .success(let source) = result, let root = ExternalCandidateSkin.defaultRoot else { return }
    skinStatus = "正在导入…"
    DispatchQueue.global(qos: .userInitiated).async {
      let scoped = source.startAccessingSecurityScopedResource()
      let outcome = ExternalCandidateSkin.importFolder(source, root: root)
      if scoped { source.stopAccessingSecurityScopedResource() }
      let installed = ExternalCandidateSkin.scan(root) ?? []
      DispatchQueue.main.async { finishImport(outcome, installed: installed) }
    }
  }

  private func finishImport(_ outcome: Result<String, ExternalCandidateSkin.ImportFailure>,
                            installed: [(id: String, skin: ExternalCandidateSkin)]) {
    installedSkins = installed
    switch outcome {
    case .success(let id):
      guard let package = installed.first(where: { $0.id == id }) else {
        skinStatus = "已复制，但 skin.toml 有误，这款皮肤不能使用。"
        return
      }
      guard package.skin.horizontal else {
        skinStatus = "已导入「\(package.skin.name)」，但它只支持竖排候选窗，iOS 的横排候选栏用不了。"
        return
      }
      storedTop("candidate_skin", $candidateSkin).wrappedValue = id
      skinStatus = saveFailed ? "" : "已导入并选用「\(package.skin.name)」。"
    case .failure(.name):
      skinStatus = "文件夹名只能用小写英文字母、数字、点、下划线和连字符，并以字母或数字开头，也不能和内置皮肤同名。"
    case .failure(.manifest):
      skinStatus = "这个文件夹里没有 skin.toml，不是候选皮肤。"
    case .failure(.storage):
      skinStatus = "导入失败：文件夹读不出来，或者超过 4096 个文件、256 MB。"
    }
  }

  private func removeSkin(_ id: String) {
    guard let root = ExternalCandidateSkin.defaultRoot else { return }
    guard ExternalCandidateSkin.remove(id, root: root) else {
      skinStatus = "删除失败，请再试一次。"
      return
    }
    installedSkins = ExternalCandidateSkin.scan(root) ?? []
    storedTop("candidate_skin", $candidateSkin).wrappedValue = CandidatePalette.defaultSkin
    skinStatus = ""
  }

  /// iPad has the width to show both appearances at once; the phone shows the one the keyboard is drawing now.
  @ViewBuilder private var palettePreview: some View {
    if tablet {
      HStack(spacing: 12) {
        previewStrip(dark: false)
        previewStrip(dark: true)
      }
    } else {
      previewStrip(dark: colorScheme == .dark)
    }
  }

  private func previewStrip(dark: Bool) -> some View {
    let palette = CandidatePalette.resolve(previewPreferences, systemDark: dark)
    return HStack(spacing: 6) {
      ForEach(Array(["水杉", "输入", "输入法"].enumerated()), id: \.offset) { index, word in
        HStack(spacing: 3) {
          Text("\(index + 1)").font(.caption).foregroundStyle(Color(palette.number))
          Text(word).foregroundStyle(Color(palette.text))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(index == 0 ? palette.hover : palette.surface)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(palette.border)))
      }
    }
    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(palette.surface)))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(dark ? "深色预览" : "浅色预览")
  }

  private var previewPreferences: [String: Any] {
    var preferences: [String: Any] = ["candidate_skin": candidateSkin, "candidate_theme": candidateTheme, "theme": globalTheme]
    preferences.merge(candidateColors) { _, custom in custom }
    return preferences
  }

  /// A colour override; while unset the picker shows the skin's own colour for the current appearance.
  private func colorBinding(_ key: String) -> Binding<Color> {
    Binding(get: {
      if let custom = CandidatePalette.color(hex: candidateColors[key]) { return Color(custom) }
      let palette = CandidatePalette.resolve(previewPreferences, systemDark: colorScheme == .dark)
      switch key {
      case "candidate_text_color": return Color(palette.text)
      case "candidate_hover_color": return Color(palette.hover)
      default: return Color(palette.surface)
      }
    }, set: { color in
      let hex = CandidatePalette.hex(UIColor(color))
      candidateColors[key] = hex
      saveFailed = !MetasequoiaInputSessionBridge.updateSharedPreferences { $0[key] = hex }
      if saveFailed { reload() }
    })
  }

  private func clearColors() {
    let keys = CandidatePalette.editableColors.map(\.key)
    saveFailed = !MetasequoiaInputSessionBridge.updateSharedPreferences { preferences in
      keys.forEach { preferences.removeValue(forKey: $0) }
    }
    reload()
  }

  private func labelled(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
      Text(detail).font(.footnote).foregroundStyle(.secondary)
    }
  }

  /// A binding that merges one field into a nested object of the shared document; a refused write puts the stored value back.
  private func stored<Value>(_ object: String, _ key: String, _ state: Binding<Value>) -> Binding<Value> {
    Binding(get: { state.wrappedValue }, set: { value in
      state.wrappedValue = value
      saveFailed = !MetasequoiaInputSessionBridge.updateSharedPreferences {
        var nested = $0[object] as? [String: Any] ?? [:]
        nested[key] = value
        $0[object] = nested
      }
      if saveFailed { reload() }
    })
  }

  /// A family name, marked when this device does not have it and the keyboard therefore skips it.
  private func familyTitle(_ family: String) -> String {
    CandidateFontPreference.isInstalled(family) ? family : "\(family)（未安装）"
  }

  private func write(_ mutate: (inout [String: Any]) -> Void) {
    saveFailed = !MetasequoiaInputSessionBridge.updateSharedPreferences(mutate)
    reload()
  }

  /// A binding that writes one top-level field of the shared document; a refused write puts the stored value back.
  private func storedTop<Value>(_ key: String, _ state: Binding<Value>) -> Binding<Value> {
    Binding(get: { state.wrappedValue }, set: { value in
      state.wrappedValue = value
      saveFailed = !MetasequoiaInputSessionBridge.updateSharedPreferences { $0[key] = value }
      if saveFailed { reload() }
    })
  }

  private func reload() {
    guard let preferences = MetasequoiaInputSessionBridge.loadSharedPreferences() else { return }
    let quanpin = preferences["quanpin"] as? [String: Any] ?? [:]
    let mixed = preferences["mixed_input"] as? [String: Any] ?? [:]
    transposition = quanpin["autocorrect_transposition"] as? Bool ?? false
    neighbor = quanpin["autocorrect_neighbor"] as? Bool ?? false
    english = mixed["english"] as? Bool ?? english
    minimumPrefix = (mixed["minimum_prefix"] as? NSNumber)?.intValue ?? minimumPrefix
    emoji = mixed["emoji"] as? Bool ?? emoji
    kaomoji = mixed["kaomoji"] as? Bool ?? kaomoji
    candidateSize = CandidateFontPreference.candidateSize(in: preferences, tablet: tablet)
    preeditSize = CandidateFontPreference.preeditSize(in: preferences, tablet: tablet)
    fontFamily = preferences[CandidateFontPreference.familyKey] as? String ?? CandidateFontPreference.defaultFamily
    englishFamily = (preferences[CandidateFontPreference.englishFamilyKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
    fontFamilies = CandidateFontPreference.families(in: preferences)
    fallbackFamilies = CandidateFontPreference.fallbackFamilies(in: preferences)
    preeditStyle = CandidatePreeditStyle(in: preferences).rawValue
    candidateSkin = preferences["candidate_skin"] as? String ?? CandidatePalette.defaultSkin
    installedSkins = ExternalCandidateSkin.defaultRoot.flatMap(ExternalCandidateSkin.scan) ?? []
    candidateTheme = preferences["candidate_theme"] as? String ?? "follow"
    globalTheme = preferences["theme"] as? String ?? "system"
    candidateColors = CandidatePalette.editableColors.reduce(into: [:]) { colors, item in
      if let hex = preferences[item.key] as? String, CandidatePalette.color(hex: hex) != nil { colors[item.key] = hex }
    }
    shuangpinRaw = preferences["shuangpin_preedit_uses_raw"] as? Bool ?? true
    wordCharacter = (preferences["word_character"] as? [String: Any])?["enabled"] as? Bool ?? wordCharacter
  }
}

/// 「补充字体」, the Windows appearance page's ordered supplementary families: drag to reorder, swipe to remove, and add from the families this device has. A family synced from a desktop that this device lacks stays in the list, marked, because the desktop still uses it.
private struct CandidateFallbackFontList: View {
  @State var families: [String]
  /// Stores the chain and returns what the document now holds, which is the old chain when the write was refused.
  let save: ([String]) -> [String]
  var body: some View {
    List {
      Section {
        // A synced document may name a family twice, so rows are keyed by position.
        ForEach(Array(families.enumerated()), id: \.offset) { _, family in
          Text(CandidateFontPreference.isInstalled(family) ? family : "\(family)（未安装）")
            .font(CandidateFontPreference.isInstalled(family)
              ? .custom(family, size: UIFont.preferredFont(forTextStyle: .body).pointSize, relativeTo: .body) : .body)
        }
        .onMove { from, to in
          var next = families
          next.move(fromOffsets: from, toOffset: to)
          families = save(next)
        }
        .onDelete { offsets in
          var next = families
          next.remove(atOffsets: offsets)
          families = save(next)
        }
        NavigationLink {
          CandidateFontFamilyList(title: "添加字体", selection: nil, none: nil) { family in
            if let family { families = save(CandidateFontPreference.appending(family, to: families)) }
          }
        } label: { Label("添加字体", systemImage: "plus") }
          .disabled(families.count >= CandidateFontPreference.maximumFallbackFamilies)
          .accessibilityIdentifier("addCandidateFallbackFont")
      } footer: {
        Text("中英文字体里没有的字，按这里的顺序找下一个字体；都没有时用系统字体。最多 \(CandidateFontPreference.maximumFallbackFamilies) 个，与桌面端同步。")
      }
    }
    .toolbar { EditButton() }
    .navigationTitle("补充字体").navigationBarTitleDisplayMode(.inline)
  }
}

/// The font families this device has, each drawn in itself, for one of the candidate font fields. A name synced from another device that this one lacks stays listed at the top, so the page shows what the document says rather than silently picking something else.
private struct CandidateFontFamilyList: View {
  let title: String
  let selection: String?
  /// The title of the "no family" row, or nil when the field always names one; choosing it passes nil.
  let none: String?
  let choose: (String?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  private let installed = UIFont.familyNames.sorted()

  var body: some View {
    List {
      if let none, query.isEmpty { row(none, family: nil, font: .body) }
      if let selection, !installed.contains(selection), query.isEmpty {
        Section {
          row(selection, family: selection, font: .body)
        } footer: {
          Text("此设备没有这个字体，键盘会跳过它。")
        }
      }
      Section {
        ForEach(installed.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { family in
          row(family, family: family, font: .custom(family, size: UIFont.preferredFont(forTextStyle: .body).pointSize,
                                                  relativeTo: .body))
        }
      }
    }
    .searchable(text: $query)
    .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
  }

  private func row(_ title: String, family: String?, font: Font) -> some View {
    Button {
      choose(family)
      dismiss()
    } label: {
      HStack {
        Text(title).font(font).foregroundStyle(.primary)
        Spacer()
        if family == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
      }
    }
    .accessibilityAddTraits(family == selection ? .isSelected : [])
  }
}
