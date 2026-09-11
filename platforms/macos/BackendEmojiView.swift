import AppKit
import SwiftUI

struct MacEmojiView: View {
  @State private var search = ""
  private let emojis = ["😀","😃","😄","😁","😆","😅","😂","🤣","😊","🙂","🙃","😉","😌","😍","🥰","😘","😗","😙","😚","😋","😛","😝","😜","🤪","🤨","🧐","🤓","😎","🤩","🥳","😏","😒","😞","😔","😟","😕","🙁","☹️","😣","😖","😫","😩","🥺","😢","😭","😤","😠","😡","🤬","🤯","😳","🥵","🥶","😱","😨","😰","😥","😓","🤗","🤔","🤭","🤫","🤥","😶","😐","😑","😬","🙄","😯","😦","😧","😮","😲","🥱","😴","🤤","😪","😵","🤐","🥴","🤢","🤮","🤧","😷","🤒","🤕","❤️","👍","👎","👏","🙏","🎉","🔥","✨","⭐","💡","✅","❌"]
  private var filtered: [String] { search.isEmpty ? emojis : emojis.filter { $0.contains(search) } }
  var onSelect: (String) -> Void = { text in NotificationCenter.default.post(name: .msimeHandwritingCandidateSelected, object: nil, userInfo: ["text": text]) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) { Text("表情与符号").font(.title2); TextField("搜索", text: $search); ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) { ForEach(filtered, id: \.self) { emoji in Button(emoji) { onSelect(emoji) }.font(.title2).buttonStyle(.plain) } } } }.padding(20).frame(width: 420, height: 360)
  }
}
