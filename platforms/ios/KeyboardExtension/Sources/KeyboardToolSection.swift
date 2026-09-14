import UIKit

struct KeyboardTool {
  let title: String
  var symbol: String?
  var selected = false
  var enabled = true
  var caption: String?
  let run: () -> Void
}

struct KeyboardToolSection {
  enum Kind {
    case opens
    case toggle
  }

  let title: String?
  let kind: Kind
  let columns: Int
  let tools: [KeyboardTool]

  func caption(for tool: KeyboardTool) -> String? {
    if let caption = tool.caption { return caption }
    switch kind {
    case .opens: return nil
    case .toggle: return tool.selected ? "已开启" : "已关闭"
    }
  }
}
