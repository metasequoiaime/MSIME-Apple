import SwiftUI
import UIKit

/// Candidate text size, pinyin typo correction, 以词定字, cloud candidates, and what gets mixed into the Chinese candidates.
///
/// Like the punctuation page, these live only in the shared preference document, nested under `quanpin`, `word_character` and `mixed_input`, so each write merges one field into its object and leaves the rest of the object as stored. Cloud candidates are the exception: an iOS-only switch in the App Group (see CloudCandidatePreference). The keyboard hands a change to its live session the next time it appears.
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
  @State private var candidateSize = CandidateFontPreference.defaultCandidateSize
  @State private var preeditSize = CandidateFontPreference.defaultPreeditSize
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
            Text("水杉输入法").font(Font(CandidateFontPreference.font(
              .body, scale: CGFloat(candidateSize) / CGFloat(CandidateFontPreference.defaultCandidateSize))))
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
      } header: {
        Text("字号")
      } footer: {
        Text(tablet
          ? "默认 18 和 15，与桌面端同步。候选栏会随字号变高；浮动的小键盘按手机的上限显示。"
          : "默认 18 和 15，与桌面端同步。候选栏会随字号变高；桌面端设得更大时，手机上最多显示到 24 和 20。")
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
    wordCharacter = (preferences["word_character"] as? [String: Any])?["enabled"] as? Bool ?? wordCharacter
  }
}
