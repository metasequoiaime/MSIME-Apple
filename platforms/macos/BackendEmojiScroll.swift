import SwiftUI

/// Reset only the viewport subtree, keeping the search field and keyboard entry alive.
struct MacEmojiScroll<ID: Hashable, Content: View>: View {
  let resetID: ID
  @ViewBuilder let content: () -> Content

  var body: some View {
    ScrollView { content() }.id(resetID)
  }
}
