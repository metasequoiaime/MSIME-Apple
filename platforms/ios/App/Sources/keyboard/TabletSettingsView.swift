import SwiftUI
import UIKit

/// The keyboard tab at regular width (iPad full screen or a wide Split View pane).
///
/// A phone walks one stack from the card dashboard. On an iPad the same stack stretches a column of cards across the whole screen and every page replaces the dashboard, so the sections live in a sidebar instead and each one opens beside it. The dashboard stays as the first section because it carries the keyboard preview and the try-out entry.
struct TabletSettingsView: View {
  enum Page: String, Hashable, CaseIterable, Identifiable {
    case home, skin, input, layout, dictionary, ai
    var id: Self { self }
    var title: String {
      switch self {
      case .home: return "我的键盘"
      case .skin: return "皮肤"
      case .input: return "输入方案"
      case .layout: return "按键"
      case .dictionary: return "词库"
      case .ai: return "AI"
      }
    }
    var symbol: String {
      switch self {
      case .home: return "keyboard"
      case .skin: return "paintpalette.fill"
      case .input: return "keyboard.fill"
      case .layout: return "slider.horizontal.3"
      case .dictionary: return "books.vertical.fill"
      case .ai: return "sparkles"
      }
    }
  }

  @State private var selection: Page? = .home
  @State private var columns = NavigationSplitViewVisibility.all

  var body: some View {
    NavigationSplitView(columnVisibility: $columns) {
      List(selection: $selection) {
        ForEach(Page.allCases) { page in
          Label(page.title, systemImage: page.symbol).tag(page)
            .accessibilityIdentifier("tabletSettings.\(page.rawValue)")
        }
        Section {
          Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
          } label: {
            Label("系统设置", systemImage: "gearshape.fill")
          }.accessibilityIdentifier("tabletSettings.system")
        } footer: {
          Text("在系统设置中启用水杉输入法并开启完全访问。")
        }
      }
      .navigationTitle("键盘")
    } detail: {
      // A fresh stack per section, so switching sections never leaves a page from the previous one on top.
      NavigationStack { page(selection ?? .home) }.id(selection)
    }
    .navigationSplitViewStyle(.balanced)
    .tint(MetasequoiaTheme.accent)
  }

  @ViewBuilder private func page(_ page: Page) -> some View {
    switch page {
    case .home: SettingsView()
    case .skin: SkinSettingsView()
    case .input: InputSettingsView()
    case .layout: KeyboardLayoutSettingsView()
    case .dictionary: DictionarySettingsView()
    case .ai: ServiceSettingsView(kind: .ai)
    }
  }
}
