import AppKit
import SwiftUI

@MainActor
final class MacAccountModel: NSObject, ObservableObject {
  @Published var user: BackendAccountClient.User?
  @Published var message: String?
  @Published var busy = false
  @Published var name = ""
  // 匿名账号是本机文件,不在钥匙串里。这一页原来只问 account(钥匙串),于是装完自动开的那个账号
  // 在设置里完全不存在 —— 页面劝你登录一个你已经有的账号。
  @Published var anonymous = false
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private let anonymousAccount: BackendAccountSession
  private let discardAnonymous: () -> Void
  private var pending: Task<Void, Never>?

  // 匿名会话和「用完丢弃凭据」都要能注入:默认值指向本机的真实文件,测试里换成内存的,否则一跑测试就
  // 读到(并可能删掉)本机真实的匿名账号。
  init(client: BackendAccountClient = BackendAccountClient(), account: BackendAccountSession = .shared,
       anonymousAccount: BackendAccountSession = BackendAccountSession(storage: BackendAnonymousAccount.sessionStorage()),
       discardAnonymous: @escaping () -> Void = BackendAnonymousAccount.discard) {
    self.client = client; self.account = account
    self.anonymousAccount = anonymousAccount; self.discardAnonymous = discardAnonymous
    super.init()
  }

  func perform(_ action: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do { try await action(); try Task.checkCancellation() }
      catch is CancellationError { }
      catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
  func load() {
    perform {
      // 钥匙串里的真实身份优先;没有才回落到匿名账号 —— 两者同时存在时匿名那个已经是历史遗留。
      if let user = try await self.account.user() {
        self.user = user; self.anonymous = false
      } else {
        self.user = try await self.anonymousAccount.user(); self.anonymous = self.user != nil
      }
      self.name = self.user?.preferredDisplayName ?? ""
    }
  }

  /// 改昵称、退出、注销针对的是页面上显示的那个账号,不一定是钥匙串里的那个。
  private var currentSession: BackendAccountSession { anonymous ? anonymousAccount : account }

  func rename() {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
    // 见 GeneratedKeyboardSkin:把 CharacterSet.contains 当方法引用传进 contains(where:),
    // 在新版 Foundation 上会把普通汉字判成控制字符。
    guard !value.isEmpty, value.unicodeScalars.count <= 64,
          !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
      message = "昵称需为 1–64 个字符，不能包含换行或控制字符。"; return
    }
    perform {
      let identity = try await self.currentSession.credentials()
      try await self.client.rename(value, token: identity.token)
      let profile = try await self.client.profile(token: identity.token)
      try await self.currentSession.updateUser(profile.user, matching: identity.token)
      try Task.checkCancellation()
      self.user = profile.user; self.name = profile.user.preferredDisplayName
    }
  }
  func logout(all: Bool = false, delete: Bool = false) {
    perform {
      if delete {
        let identity = try await self.currentSession.credentials()
        try await self.client.deleteAccount(token: identity.token)
        try await self.currentSession.forget()
        if self.anonymous { self.discardAnonymous() }
      } else {
        do { try await self.currentSession.logout(all: all) }
        catch { self.user = try await self.currentSession.user(); throw error }
      }
      self.user = nil; self.name = ""; self.anonymous = false
    }
  }
  func close() { pending?.cancel() }
}


// 这一页原来是 Form 里一列九个一模一样的胶囊按钮 —— 「云剪贴板」和「注销账号」长得完全一样,而且
// 外面套着写死的 420×440,内容被截断(注销账号看不全),分页下半截却空着。
//
// 现在按设置窗口自己的语言重排:卡片圆角 12 加 separatorColor 描边、分区标题 11pt semibold、
// 行高 48pt 标签在左控件在右。这些数字不是新定的,是 PreferencesWindowController 里那几个
// AppKit 构造函数(SectionLabel / PreferenceRow / CardHeader)一直在用的,账号页只是一直没跟。

/// 一张卡片。分区标题在卡片外面,和其他分页一致。
private struct SettingsCard<Content: View>: View {
  var title: String?
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let title {
        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .padding(.leading, 2)
      }
      VStack(spacing: 0) { content }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
    }
  }
}

/// 标签在左、控件在右的一行。48pt 是其他分页 PreferenceRow 的行高。
private struct SettingsRow<Trailing: View>: View {
  let title: String
  var subtitle: String?
  var destructive = false
  @ViewBuilder var trailing: Trailing
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 15)).foregroundStyle(destructive ? Color.red : Color.primary)
        if let subtitle {
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      trailing
    }
    .frame(minHeight: subtitle == nil ? 48 : 56)
  }
}

/// 打开一个子面板的一行。整行可点,右端一个 chevron —— 这是「还有下一层」的标准写法,
/// 而原来它和「注销账号」一样只是一个灰胶囊。
private struct DisclosureRow: View {
  let title: String
  let subtitle: String
  let action: () -> Void
  @State private var hovering = false
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 15)).foregroundStyle(.primary)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
      }
      .frame(minHeight: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(hovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12) : .clear)
    .onHover { hovering = $0 }
  }
}

private struct CardDivider: View {
  var body: some View { Divider().overlay(Color(nsColor: .separatorColor)) }
}

struct MacAccountView: View {
  @ObservedObject var model: MacAccountModel
  @State private var deleting = false
  @State private var clipboard = false
  @State private var settings = false
  @State private var dictionary = false
  @State private var snapshot = false
  @State private var resources = false

  private var monogram: String {
    let name = model.user?.preferredDisplayName ?? ""
    return String(name.prefix(1)).uppercased()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let user = model.user { identity(user) }
        if model.anonymous { localAccountNotice }
        if model.user == nil {
          Text("当前没有可用账号。输入法会在启动时尝试连接本机账号，请检查网络后重启输入法。")
            .font(.callout).foregroundStyle(.secondary)
        }
        if model.user != nil { cloudServices; accountActions }
        if model.busy { ProgressView().controlSize(.small) }
        if let message = model.message {
          Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .disabled(model.busy)
    .sheet(isPresented: $resources) {
      if let user = model.user { BackendCommunityResourcesView(accountID: user.id).frame(width: 650, height: 650) }
    }
    .sheet(isPresented: $snapshot) {
      if let user = model.user { MacCloudSnapshotView(accountID: user.id) }
    }
    .sheet(isPresented: $dictionary) {
      if let user = model.user { MacCloudDictionaryView(accountID: user.id) }
    }
    .sheet(isPresented: $settings) {
      if let user = model.user { MacCloudSettingsView(accountID: user.id) }
    }
    .sheet(isPresented: $clipboard) {
      if let user = model.user { MacCloudClipboardView(accountID: user.id) }
    }
    .alert("注销账号？", isPresented: $deleting) {
      Button("取消", role: .cancel) { }
      Button("确认注销", role: .destructive) { model.logout(delete: true) }
    } message: { Text("将删除账号及其云端数据，此操作不可撤销。") }
  }

  /// 身份卡:头像、昵称、账号标识,以及匿名与否的状态。原来这三样是三行字号递减的纯文本,
  /// 看不出哪个是「我是谁」哪个是「机器给的编号」。
  private func identity(_ user: BackendAccountClient.User) -> some View {
    SettingsCard {
      HStack(spacing: 14) {
        Text(monogram)
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(.white)
          .frame(width: 52, height: 52)
          .background(Circle().fill(Color.accentColor))
        VStack(alignment: .leading, spacing: 3) {
          Text(user.preferredDisplayName).font(.system(size: 17, weight: .semibold))
          if model.anonymous, let anonymous = BackendAnonymousAccount.stored() {
            Text(anonymous.subject)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
        Spacer(minLength: 12)
        if model.anonymous {
          Text("本机账号")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.16)))
            .foregroundStyle(.orange)
        }
      }
      .frame(minHeight: 72)
      CardDivider()
      SettingsRow(title: "昵称") {
        HStack(spacing: 8) {
          TextField("", text: $model.name).textFieldStyle(.roundedBorder).frame(width: 200)
          Button("保存") { model.rename() }
            .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines) == user.preferredDisplayName)
        }
      }
    }
  }

  /// 本机账号的恢复边界，避免暗示存在可用的身份绑定入口。
  private var localAccountNotice: some View {
    SettingsCard(title: "本机账号") {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 13))
        Text("这个账号是安装时自动创建的，凭据只在本机。清除输入法数据或更换设备后无法找回它和它的云端词库。")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 12)
    }
  }

  /// 五个子面板。它们都是「进去还有一层」,所以是带 chevron 的整行,不是五个和注销并排的胶囊。
  private var cloudServices: some View {
    SettingsCard(title: "云服务") {
      DisclosureRow(title: "云剪贴板", subtitle: "在设备之间同步复制的内容") { clipboard = true }
      CardDivider()
      DisclosureRow(title: "桌面设置同步", subtitle: "把这台机器的偏好上传或取回") { settings = true }
      CardDivider()
      DisclosureRow(title: "词包与回复模板", subtitle: "社区分享的词库与常用语") { resources = true }
      CardDivider()
      DisclosureRow(title: "云词库", subtitle: "自造词与调频记录") { dictionary = true }
      CardDivider()
      DisclosureRow(title: "云词库同步与备份", subtitle: "手动备份与按版本回滚") { snapshot = true }
    }
  }

  /// 退出和注销放在最后一张卡,注销用红色 —— 原来它和「云剪贴板」是同一个灰胶囊,还被截断看不全。
  private var accountActions: some View {
    SettingsCard(title: "账号") {
      SettingsRow(title: "退出登录", subtitle: "只退出这台设备") {
        Button("退出") { model.logout() }
      }
      CardDivider()
      SettingsRow(title: "退出所有设备", subtitle: "使其他设备上的登录立即失效") {
        Button("全部退出") { model.logout(all: true) }
      }
      CardDivider()
      SettingsRow(title: "注销账号", subtitle: "删除账号及其云端数据，不可撤销", destructive: true) {
        Button("注销") { deleting = true }
      }
    }
  }
}


@MainActor @objc(MSIMEBackendAccountWindow)
final class BackendAccountWindow: NSWindowController, NSWindowDelegate {
  @objc static let shared = BackendAccountWindow()
  private let model = MacAccountModel()
  private init() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = "水杉账号"; window.isReleasedWhenClosed = false; window.delegate = self
    window.contentView = NSHostingView(rootView: MacAccountView(model: model))
    window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc func showAccount() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); model.load() }
  func windowWillClose(_ notification: Notification) { model.close() }
}

// 设置页里直接用的账号视图。The preferences page used to hold a button that opened this same UI in a
// separate window, so reaching the sign-in meant a panel on top of a panel; the view is plain SwiftUI
// and hosting it inline costs nothing.
//
// 桥接沿用本文件既有的做法:只导出 @_cdecl 的 C 函数。这个 target 不生成 -Swift.h,所以 ObjC 那边
// 看不见 Swift 类,只能收一个 NSView。
@MainActor
private final class AccountPane {
  static let shared = AccountPane()
  let model = MacAccountModel()
  lazy var hosting: NSHostingView<MacAccountView> = {
    let view = NSHostingView(rootView: MacAccountView(model: model))
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
}

@_cdecl("MSIMEAccountPaneView")
func accountPaneView() -> NSView {
  MainActor.assumeIsolated { AccountPane.shared.hosting }
}

// Refresh the account when its settings pane is attached.
@_cdecl("MSIMEAccountPaneAttach")
func accountPaneAttach(_ window: NSWindow?) {
  MainActor.assumeIsolated {
    AccountPane.shared.model.load()
  }
}

@_cdecl("MSIMEAccountPaneClose")
func accountPaneClose() {
  MainActor.assumeIsolated { AccountPane.shared.model.close() }
}

@_cdecl("MSIMEShowBackendAccount")
func showBackendAccount() {
  Task { @MainActor in BackendAccountWindow.shared.showAccount() }
}
