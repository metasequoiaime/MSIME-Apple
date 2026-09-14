import AppKit
import AuthenticationServices
import SwiftUI

@MainActor
final class MacAccountModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  @Published var user: BackendAccountClient.User?
  @Published var providers: [String: Bool] = [:]
  @Published var message: String?
  @Published var busy = false
  @Published var authorizing = false
  @Published var name = ""
  @Published var target = ""
  @Published var code = ""
  @Published var channel = "email"
  @Published var challenge: BackendAccountClient.Challenge?
  @Published var expiresAt = Date.distantPast
  @Published var resendAt = Date.distantPast
  weak var window: NSWindow?
  // 匿名账号是本机文件,不在钥匙串里。这一页原来只问 account(钥匙串),于是装完自动开的那个账号
  // 在设置里完全不存在 —— 页面劝你登录一个你已经有的账号。
  @Published var anonymous = false
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private let anonymousAccount: BackendAccountSession
  private let discardAnonymous: () -> Void
  private var pending: Task<Void, Never>?
  private var appleController: ASAuthorizationController?
  private var appleChallenge: String?

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
      let providers = try await self.client.providers()
      try Task.checkCancellation()
      self.providers = providers
    }
  }

  /// 改昵称、退出、注销针对的是页面上显示的那个账号,不一定是钥匙串里的那个。
  private var currentSession: BackendAccountSession { anonymous ? anonymousAccount : account }

  /// 当前显示的是匿名账号时返回它的 token,登录于是变成「把身份绑到这个账号上」而不是另开一个。
  /// 不这么做,用户一登录就换了账号,匿名账号名下的云端词库当场变成孤儿。
  private func linkToken() async -> String? {
    guard anonymous else { return nil }
    return try? await anonymousAccount.accessToken()
  }

  /// 绑定成功后账号已经有了真实身份,凭据归位到钥匙串,本机那份匿名凭据就该清掉 —— 留着只会在
  /// 下次启动时被当成另一个可用会话。
  private func adoptKeychainIdentity() async {
    guard anonymous else { return }
    try? await anonymousAccount.forget()
    discardAnonymous()
    anonymous = false
  }
  func requestCode() {
    guard resendAt <= Date() else { return }
    perform {
      guard self.providers[self.channel] == true else { throw BackendAccountClient.Failure(status: 503) }
      let response = try await self.client.challenge(provider: self.channel,
                                                     target: self.target.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     linkToken: await self.linkToken())
      try Task.checkCancellation()
      self.challenge = response
      self.expiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in))
      self.resendAt = Date().addingTimeInterval(60)
      self.code = ""
    }
  }
  func codeLogin() {
    guard let challenge, expiresAt > Date(), code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else { return }
    perform {
      try await self.account.signIn(challenge: challenge.challenge_id, credential: self.code,
                                    linkToken: await self.linkToken())
      let user = try await self.account.user()
      try Task.checkCancellation()
      await self.adoptKeychainIdentity()
      self.user = user; self.name = self.user?.preferredDisplayName ?? ""
      self.challenge = nil; self.code = ""; self.target = ""
    }
  }
  func appleLogin() {
    perform {
      guard self.window != nil, self.providers["apple"] == true else { throw BackendAccountClient.Failure(status: 503) }
      let challenge = try await self.client.challenge(provider: "apple", linkToken: await self.linkToken())
      try Task.checkCancellation()
      guard let nonce = challenge.nonce else { throw BackendAccountClient.Failure(status: 503) }
      let request = ASAuthorizationAppleIDProvider().createRequest()
      request.nonce = nonce
      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self; controller.presentationContextProvider = self
      self.appleChallenge = challenge.challenge_id; self.appleController = controller; self.authorizing = true
      controller.performRequests()
    }
  }
  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window! }
  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    guard controller === appleController else { return }
    defer { appleController = nil; appleChallenge = nil; authorizing = false }
    guard let challenge = appleChallenge, let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
          let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else { return }
    perform {
      try await self.account.signIn(challenge: challenge, credential: token, linkToken: await self.linkToken())
      let user = try await self.account.user()
      try Task.checkCancellation()
      await self.adoptKeychainIdentity()
      self.user = user; self.name = self.user?.preferredDisplayName ?? ""
    }
  }
  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    guard controller === appleController else { return }
    appleController = nil; appleChallenge = nil; authorizing = false
    // 把真正的错误带出来。"请重试" was all the user and the log ever saw, so a build that can never
    // succeed -- an ad-hoc signature carries no com.apple.developer.applesignin entitlement, which
    // ASAuthorizationServices refuses outright -- looked exactly like a flaky network.
    guard (error as? ASAuthorizationError)?.code != .canceled else { return }
    let reason = (error as NSError).localizedFailureReason ?? error.localizedDescription
    message = "Apple 登录未完成：\(reason)（\((error as NSError).domain) \((error as NSError).code)）"
    NSLog("[Metasequoia] Apple sign-in failed: %@", error as NSError)
  }
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
  func close() { pending?.cancel(); if #available(macOS 13.0, *) { appleController?.cancel() }; authorizing = false; appleController = nil; appleChallenge = nil; code = ""; target = ""; challenge = nil }
}

struct MacAccountView: View {
  @ObservedObject var model: MacAccountModel
  @State private var deleting = false
  @State private var clipboard = false
  @State private var settings = false
  @State private var dictionary = false
  @State private var snapshot = false
  @State private var resources = false
  var body: some View {
    ScrollView {
      Form {
      if let user = model.user {
        Text(user.preferredDisplayName).font(.title2)
        // 匿名账号是装完自动开的,用户没做过任何操作,所以「它从哪来、丢了会怎样」必须写在他会看到的
        // 地方。提示放在这一页而不是打字时弹出来:内容是一次性的,但看的时机该由用户决定。
        if model.anonymous, let anonymous = BackendAnonymousAccount.stored() {
          Text("本机账号 \(anonymous.subject)")
            .font(.callout)
          Text("安装时自动创建,用于候选词翻译与云同步。凭据保存在本机的应用支持目录,清除输入法数据或更换设备后无法找回这个账号及其云端词库 —— 想长期保留请在下面绑定 Apple 或邮箱,绑定后仍是同一个账号,云词库不会丢。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        TextField("昵称", text: $model.name)
        Button("保存昵称") { model.rename() }
        Button("云剪贴板…") { clipboard = true }
        Button("桌面设置同步…") { settings = true }
        Button("词包与回复模板…") { resources = true }
        Button("云词库…") { dictionary = true }
        Button("云词库同步与备份…") { snapshot = true }
        Button("退出登录") { model.logout() }
        Button("退出所有设备") { model.logout(all: true) }
        Button("注销账号", role: .destructive) { deleting = true }
      }
      if model.user == nil || model.anonymous {
        Button(model.anonymous ? "绑定 Apple 账号" : "使用 Apple 登录") { model.appleLogin() }
          .disabled(model.providers["apple"] != true)
        Picker(model.anonymous ? "验证码绑定" : "验证码登录", selection: $model.channel) {
          Text("邮箱").tag("email"); Text("手机号").tag("phone")
        }.onChange(of: model.channel) { _ in model.challenge = nil; model.code = "" }
        TextField(model.channel == "email" ? "邮箱地址" : "手机号（含国家区号，如 +86）", text: $model.target)
          .onChange(of: model.target) { _ in model.challenge = nil; model.code = "" }
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
          let remaining = max(0, Int(ceil(model.resendAt.timeIntervalSince(timeline.date))))
          Button(remaining == 0 ? "获取验证码" : "\(remaining) 秒后可重发") { model.requestCode() }
            .disabled(remaining > 0 || model.providers[model.channel] != true || model.target.isEmpty)
          if model.challenge != nil {
            TextField("6 位验证码", text: $model.code)
            Button(model.anonymous ? "绑定" : "登录") { model.codeLogin() }
              .disabled(model.expiresAt <= timeline.date || model.code.utf8.count != 6 || !model.code.utf8.allSatisfy { (48...57).contains($0) })
          }
        }
        if model.providers[model.channel] != true { Text("此登录方式尚未启用。").foregroundStyle(.secondary) }
      }
      if model.busy { ProgressView() }
      if let message = model.message { Text(message).foregroundStyle(.secondary) }
    }
    }
    .padding(24).frame(width: 420, height: 440).disabled(model.busy || model.authorizing)
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
}

@MainActor @objc(MSIMEBackendAccountWindow)
final class BackendAccountWindow: NSWindowController, NSWindowDelegate {
  @objc static let shared = BackendAccountWindow()
  private let model = MacAccountModel()
  private init() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = "水杉账号"; window.isReleasedWhenClosed = false; window.delegate = self
    window.contentView = NSHostingView(rootView: MacAccountView(model: model)); model.window = window
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

// 登录要一个 presentationAnchor;嵌进设置页之后它没有自己的窗口,得由宿主交出来。
@_cdecl("MSIMEAccountPaneAttach")
func accountPaneAttach(_ window: NSWindow?) {
  MainActor.assumeIsolated {
    AccountPane.shared.model.window = window
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
