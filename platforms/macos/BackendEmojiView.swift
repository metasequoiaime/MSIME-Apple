import AppKit
import SwiftUI

struct MacEmojiView: View {
  @State private var search = ""
  @AppStorage("msime.emoji.recent") private var recentStorage = ""
  private let emojis = ["😀","😃","😄","😁","😆","😅","😂","🤣","😊","🙂","😉","😍","🥰","😘","😋","😜","🤪","🤓","😎","🤩","🥳","😏","😞","😢","😭","😤","😠","😡","🤬","🤯","😳","😱","🤗","🤔","😶","😐","😬","🙄","😮","😲","😴","🤤","😵","🤢","🤮","🤧","😷","❤️","👍","👎","👏","🙏","🎉","🔥","✨","⭐","💡","✅","❌"]
  private var recent: [String] { recentStorage.split(separator: " ").map(String.init) }
  private var filtered: [String] { search.isEmpty ? emojis : emojis.filter { $0.contains(search) } }
  var onSelect: (String) -> Void = { text in NotificationCenter.default.post(name: .msimeHandwritingCandidateSelected, object: nil, userInfo: ["text": text]) }
  private func select(_ value: String) { recentStorage = Array(([value] + recent).uniqued().prefix(12)).joined(separator: " "); onSelect(value) }
  var body: some View { VStack(alignment: .leading, spacing: 12) { Text("表情与符号").font(.title2); TextField("搜索表情", text: $search); if !recent.isEmpty && search.isEmpty { Text("最近使用").font(.headline); grid(recent) }; ScrollView { grid(filtered) } }.padding(20).frame(width: 420, height: 360) }
  @ViewBuilder private func grid(_ values: [String]) -> some View { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) { ForEach(values, id: \.self) { value in Button(value) { select(value) }.font(.title2).buttonStyle(.plain) } } }
}
private extension Array where Element: Equatable { func uniqued() -> [Element] { reduce(into: []) { if !$0.contains($1) { $0.append($1) } } } }
