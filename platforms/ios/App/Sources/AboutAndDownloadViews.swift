import SwiftUI
import UIKit

private enum DesktopPlatform: String, CaseIterable, Identifiable {
  case macOS, windows = "Windows", linux = "Linux"
  var id: String { rawValue }
  var symbol: String {
    switch self { case .macOS: "laptopcomputer"; case .windows: "pc"; case .linux: "terminal" }
  }
  var repository: String {
    switch self { case .macOS: "MSIME-Apple"; case .windows: "MSIME-Windows"; case .linux: "MSIME-Linux" }
  }
  var releaseURL: URL { URL(string: "https://github.com/metasequoiaime/\(repository)/releases")! }
  var steps: [String] {
    switch self {
    case .macOS:
      ["在 Mac 上打开下载页，选择适合你的 macOS 安装包。", "按照发布页说明完成安装。", "在系统设置的键盘输入法中添加水杉输入法，再切换使用。"]
    case .windows:
      ["在 Windows 电脑上打开下载页，选择与你的系统架构匹配的安装包。", "运行安装程序，按发布页说明完成安装。", "使用 Win + 空格切换到水杉输入法。"]
    case .linux:
      ["在 Linux 电脑上打开发布页，查看适用发行版与依赖要求。", "按照项目安装说明配置 IBus 和水杉输入法。", "在系统输入源中添加水杉输入法，按说明重新登录后使用。"]
    }
  }
}

struct DesktopDownloadView: View {
  @State private var platform = DesktopPlatform.macOS
  @State private var copied = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "desktopcomputer").font(.system(size: 38)).foregroundStyle(MetasequoiaTheme.forest)
          Text("在电脑上，也用水杉").font(.title2.bold())
          Text("选择你的电脑系统，获取官方安装包与使用指南。").foregroundStyle(.secondary)
        }.padding(.top, 12)
        Picker("电脑系统", selection: $platform) {
          ForEach(DesktopPlatform.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("desktopPlatformPicker")
        VStack(alignment: .leading, spacing: 20) {
          Label(platform.rawValue + " 安装指南", systemImage: platform.symbol).font(.headline)
          ForEach(Array(platform.steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 12) {
              Text(String(index + 1)).font(.subheadline.bold()).foregroundStyle(MetasequoiaTheme.forest)
                .frame(width: 28, height: 28).background(MetasequoiaTheme.forest.opacity(0.1), in: Circle())
              Text(step).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
          }
          Link(destination: platform.releaseURL) {
            Label("打开官方发布页", systemImage: "arrow.down.circle")
              .frame(maxWidth: .infinity).padding(.vertical, 6)
          }.buttonStyle(.borderedProminent).accessibilityIdentifier("desktopReleaseLink")
          Button {
            UIPasteboard.general.url = platform.releaseURL
            copied = true
          } label: {
            Label(copied ? "已复制下载链接" : "复制链接，在电脑上打开", systemImage: copied ? "checkmark" : "doc.on.doc")
              .frame(maxWidth: .infinity)
          }.accessibilityIdentifier("copyDesktopDownloadLink")
        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        Text("电脑安装包需要在对应系统上安装。具体系统要求、版本说明和安装步骤以官方发布页为准。").font(.footnote).foregroundStyle(.secondary)
        Link("官网与完整下载指南", destination: URL(string: "https://msime.app/download/")!)
        Link("阅读用户文档", destination: URL(string: "https://msime.app/docs/")!)
      }.padding(20)
    }.background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("电脑版下载").navigationBarTitleDisplayMode(.inline)
      .onChange(of: platform) { _ in copied = false }
  }
}

struct AboutView: View {
  private var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
  }

  var body: some View {
    List {
      Section {
        VStack(spacing: 12) {
          Image("MSIMELogo").resizable().scaledToFit().frame(width: 72, height: 72)
            .accessibilityHidden(true)
          Text("水杉输入法").font(.title2.bold())
          Text("让输入更自然").foregroundStyle(.secondary)
          Text("版本 " + version).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("aboutAppVersion")
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
      }
      Section("关于水杉") {
        Text("水杉是一款开源输入法，支持多种输入方案和个性化皮肤。手机与电脑共用输入引擎，各平台提供原生输入体验。")
        NavigationLink(destination: DesktopDownloadView()) {
          Label("电脑版下载", systemImage: "desktopcomputer")
        }
      }
      Section("帮助与开源") {
        Link(destination: URL(string: "https://msime.app/")!) { Label("官方网站", systemImage: "globe") }
        Link(destination: URL(string: "https://msime.app/docs/")!) { Label("使用文档", systemImage: "book") }
        Link(destination: URL(string: "https://github.com/metasequoiaime/MSIME-Apple")!) { Label("开源代码与许可证", systemImage: "curlybraces") }
        Link(destination: URL(string: "https://github.com/metasequoiaime/MSIME-Apple/issues")!) { Label("反馈问题与建议", systemImage: "bubble.left.and.bubble.right") }
      }
      Section("隐私") {
        Text("键盘默认离线。仅在你使用 AI 或语音时，将本次文字或录音发送到所配置的服务。账号、云同步和皮肤社区按你启用的功能联网。手写首次联网下载模型，之后在设备上识别；Google ML Kit 会发送性能及使用统计，不会上传笔迹或识别结果。").font(.footnote).foregroundStyle(.secondary)
        Link("隐私说明", destination: URL(string: "https://msime.app/privacy/")!)
      }
    }.navigationTitle("关于水杉").navigationBarTitleDisplayMode(.inline)
  }
}
