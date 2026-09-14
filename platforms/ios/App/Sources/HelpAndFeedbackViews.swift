import SwiftUI
import UIKit

// 帮助和反馈原来只是「关于」页里两条指向网页的链接。键盘出问题的时候把人送去浏览器,恰好是最不该
// 发生的时候 —— 而反馈落到一张空白的 issue 表单,等于让用户自己猜要附哪些信息,结果是我们拿到的
// 报告无从复现。这两页把答案和报告都留在 App 里。

private struct HelpItem: View {
  let term: String
  let detail: String
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(term).font(.callout.weight(.medium))
      Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }.padding(.vertical, 2)
  }
}

struct HelpView: View {
  var body: some View {
    Form {
      // 步骤和引导页用的是同一套措辞 —— 用户在两处看到不一致的路径,会以为自己走错了。
      Section("启用键盘") {
        HelpItem(term: "1. 打开键盘设置", detail: "前往“设置 → 通用 → 键盘 → 键盘”。")
        HelpItem(term: "2. 添加水杉输入法", detail: "选择“添加新键盘”，再选择水杉输入法。")
        HelpItem(term: "3. 切换并开始输入", detail: "在输入框长按地球键，选择水杉输入法。")
        Button {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        } label: {
          Label("打开系统键盘设置", systemImage: "gearshape")
        }.accessibilityIdentifier("helpOpenKeyboardSettings")
      }
      Section("打字") {
        HelpItem(term: "选择候选词", detail: "点候选栏里的词上屏。候选多于一行时，点右端的箭头展开整页。")
        HelpItem(term: "换一种输入方案", detail: "全拼、双拼、五笔等在“键盘设置 → 输入设置”里切换。")
        HelpItem(term: "换皮肤与布局", detail: "“键盘设置”里可以改皮肤、键位布局和按键间距。")
      }
      Section("需要完全访问权限的功能") {
        HelpItem(term: "什么时候需要",
                 detail: "打字统计要保存本机字数、手写首次要下载识别模型，这两项需要在系统键盘设置里开启“允许完全访问”。")
        HelpItem(term: "不开会怎样", detail: "键盘照常打字。默认离线，不开这项不影响输入本身。")
      }
      Section("遇到问题") {
        HelpItem(term: "键盘里没有水杉", detail: "回到上面的启用步骤确认已添加；添加过仍看不到时，长按地球键翻一下列表。")
        HelpItem(term: "云功能连不上", detail: "云词库、皮肤社区这些要联网并登录账号。在“我的”里确认账号状态。")
        HelpItem(term: "更新后行为变了", detail: "在 App Store 确认已是最新版本，词库随版本更新。")
      }
      Section("更多") {
        Link(destination: URL(string: "https://msime.app/docs/")!) {
          Label("完整文档（网页）", systemImage: "book")
        }
      }
    }.navigationTitle("使用帮助").navigationBarTitleDisplayMode(.inline)
  }
}

struct FeedbackView: View {
  @State private var kind = "功能异常"
  @State private var detail = ""
  @State private var copied = false

  private let kinds = ["功能异常", "候选词不对", "功能建议", "其他"]

  // 版本、系统、机型 —— 这三项决定一个报告能不能复现,而它们恰好都是用户不知道要附的。
  private var diagnostics: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "开发构建"
    let build = info?["CFBundleVersion"] as? String ?? "-"
    let device = UIDevice.current
    return "水杉输入法 \(version)（构建 \(build)）\n\(device.systemName) \(device.systemVersion)\n\(device.model)"
  }

  private var report: String {
    "### 类型\n\(kind)\n\n### 描述\n\(detail)\n\n### 环境\n\(diagnostics)\n"
  }

  var body: some View {
    Form {
      Section("类型") {
        Picker("类型", selection: $kind) {
          ForEach(kinds, id: \.self) { Text($0).tag($0) }
        }.pickerStyle(.menu).accessibilityIdentifier("feedbackKindPicker")
      }
      Section("描述") {
        TextEditor(text: $detail).frame(minHeight: 120).accessibilityIdentifier("feedbackDetailEditor")
        Text("发生了什么？如果和打字有关，写出你输入的编码和期望的结果最有用。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      // 诊断信息摆出来给用户看,而不是提交时悄悄附上 —— 他有权知道自己发出去的是什么。
      Section("会一起附上的信息") {
        Text(diagnostics).font(.footnote.monospaced()).foregroundStyle(.secondary)
          .accessibilityIdentifier("feedbackDiagnostics")
      }
      Section {
        Button {
          UIPasteboard.general.string = report
          copied = true
        } label: {
          Label(copied ? "已复制报告" : "复制报告", systemImage: copied ? "checkmark" : "doc.on.doc")
        }.accessibilityIdentifier("feedbackCopyButton")
        Button {
          submit()
        } label: {
          Label("在 GitHub 提交", systemImage: "arrow.up.forward.square")
        }.accessibilityIdentifier("feedbackSubmitButton")
      } footer: {
        Text("提交会打开 GitHub 并预填这份报告。网址长度有限，过长的描述会被截断，完整内容请用“复制报告”。")
      }
    }.navigationTitle("反馈").navigationBarTitleDisplayMode(.inline)
  }

  private func submit() {
    // URL 有长度上限,超了 GitHub 直接返回 414,所以正文截断到一个安全长度;完整报告走「复制报告」。
    let body = String(report.prefix(4000))
    var components = URLComponents(string: "https://github.com/metasequoiaime/MSIME-Apple/issues/new")
    components?.queryItems = [URLQueryItem(name: "title", value: kind), URLQueryItem(name: "body", value: body)]
    guard let url = components?.url else { return }
    UIApplication.shared.open(url)
  }
}
