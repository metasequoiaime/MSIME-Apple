import SwiftUI

/// 二级设置页共用的行与状态条。
///
/// 放在 shared/backend-ui 而不是 platforms/ios/App/Sources:这个目录里的云词库、词包等页面和应用内其余二级页是同一批,读者不会知道它们的源码分属两处,却看得出它们长得不一样。目前只有 iOS 目标编译这个目录。
///
/// 这些页面原先各写各的:动作是一排裸文字按钮,说明文字挤在动作同一组里当成一个列表行,加载和报错也当列表行插在条目中间。于是同一个标签页点进去,每一页都是另一套写法,而加载一结束列表还会跳一下。
struct SettingsRowLabel: View {
  let title: String
  var detail: String?
  let symbol: String
  var color: Color = MetasequoiaTheme.accent
  var destructive = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
        .foregroundStyle(destructive ? Color.red : color)
        .frame(width: 30, height: 30)
        .background((destructive ? Color.red : color).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).foregroundStyle(destructive ? Color.red : Color.primary)
        if let detail {
          Text(detail).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
  }
}

/// 点一下就做一件事的行。用 `.plain` 是因为列表里的按钮默认整行染成强调色,那样图标的颜色就白给了。
struct SettingsActionRow: View {
  let title: String
  var detail: String?
  let symbol: String
  var color: Color = MetasequoiaTheme.accent
  var destructive = false
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      SettingsRowLabel(title: title, detail: detail, symbol: symbol, color: color, destructive: destructive)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.45)
  }
}

/// 只读的一行事实 —— 云端版本、条目数这类。跟动作行同一套排版,免得同一页里「能点的」和「不能点的」长得像两个控件族。
struct SettingsFactRow: View {
  let title: String
  var detail: String?
  let symbol: String
  var color: Color = MetasequoiaTheme.accent

  var body: some View {
    SettingsRowLabel(title: title, detail: detail, symbol: symbol, color: color)
  }
}

/// 加载与报错固定在底部,不参与列表布局。作为列表行时,它们出现和消失都会把下面的条目推上推下,而这恰好发生在用户正要去点某一行的时候。
struct SettingsStatusBar: View {
  let busy: Bool
  var busyTitle = "正在处理…"
  let message: String?

  var body: some View {
    if busy || message != nil {
      HStack(spacing: 10) {
        if busy {
          ProgressView()
        } else {
          Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
        Text(busy ? busyTitle : (message ?? ""))
          .font(.footnote)
          .foregroundStyle(busy ? Color.secondary : Color.primary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 20).padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial)
      .overlay(alignment: .top) { Divider() }
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }
}

extension View {
  func settingsStatus(busy: Bool, busyTitle: String = "正在处理…", message: String?) -> some View {
    safeAreaInset(edge: .bottom, spacing: 0) {
      SettingsStatusBar(busy: busy, busyTitle: busyTitle, message: message)
        .animation(.easeInOut(duration: 0.18), value: busy)
        .animation(.easeInOut(duration: 0.18), value: message)
    }
  }
}
