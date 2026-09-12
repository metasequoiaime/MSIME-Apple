@main enum EmojiSelectionStateTest {
  static func main() {
    var state = MacEmojiSelectionState()
    assert(!state.rejected)
    var calls = 0
    state.submit("synthetic-choice") { text in
      calls += 1
      assert(text == "synthetic-choice")
      return false
    }
    assert(state.rejected && calls == 1)
    state.submit("synthetic-retry") { _ in calls += 1; return false }
    assert(state.rejected && calls == 2)
    state.submit("synthetic-accepted") { _ in calls += 1; return true }
    assert(!state.rejected && calls == 3)
    assert(!MacEmojiSelectionState.failureMessage.contains("synthetic"))
    print("Emoji selection feedback checks passed")
  }
}
