/// Acceptance means the host queued a request, not that insertion has completed.
struct MacEmojiSelectionState {
  private(set) var rejected = false
  static let failureMessage = "输入目标已失效或请求被拒绝，请回到目标应用重新打开表情面板。"

  mutating func submit(_ text: String, send: (String) -> Bool) {
    rejected = !send(text)
  }
}
