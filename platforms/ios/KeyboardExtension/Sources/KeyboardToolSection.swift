import UIKit

/// 工具面板里的一项。
struct KeyboardTool {
  let title: String
  var symbol: String?
  var selected = false
  var enabled = true
  /// 覆盖分组的默认第二行,给那些既不是开关也不是二选一的卡用。
  var caption: String?
  let run: () -> Void
}

/// 工具面板里的一组。
///
/// 组自己说明怎么排、第二行写什么,不再靠面板去猜。
///
/// The panel used to read its own layout out of the section's Chinese title: one string match
/// decided the column count, another decided whether a card carried a state line at all. Five
/// sections accumulated against those two matches and no two of them looked alike -- full-width
/// rows above a two-column grid above a three-column grid, some cards captioned and some bare,
/// all of it looking like a list that had been added to rather than designed.
struct KeyboardToolSection {
  /// 决定卡片第二行说什么,也是这三类之间唯一真正的差别。
  enum Kind {
    /// Opens something and leaves the panel; the chevron is the whole explanation.
    case opens
    /// A switch that is independently on or off.
    case toggle
  }

  let title: String?
  let kind: Kind
  /// One column is a full-width row with a chevron; more is a grid.
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
