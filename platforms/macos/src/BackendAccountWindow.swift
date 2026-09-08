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
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private var pending: Task<Void, Never>?
  private var appleController: ASAuthorizationController?
  private var appleChallenge: String?

  init(client: BackendAccountClient = BackendAccountClient(), account: BackendAccountSession = .shared) {
    self.client = client; self.account = account
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
      self.user = try await self.account.user()
      self.name = self.user?.preferredDisplayName ?? ""
      let providers = try await self.client.providers()
      try Task.checkCancellation()
      self.providers = providers
    }
  }
  func requestCode() {
    guard resendAt <= Date() else { return }
    perform {
      guard self.providers[self.channel] == true else { throw BackendAccountClient.Failure(status: 503) }
      let response = try await self.client.challenge(provider: self.channel, target: self.target.trimmingCharacters(in: .whitespacesAndNewlines))
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
      try await self.account.signIn(challenge: challenge.challenge_id, credential: self.code)
      let user = try await self.account.user()
      try Task.checkCancellation()
      self.user = user; self.name = self.user?.preferredDisplayName ?? ""
      self.challenge = nil; self.code = ""; self.target = ""
    }
  }
  func appleLogin() {
    perform {
      guard self.window != nil, self.providers["apple"] == true else { throw BackendAccountClient.Failure(status: 503) }
      let challenge = try await self.client.challenge(provider: "apple")
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
      try await self.account.signIn(challenge: challenge, credential: token)
      let user = try await self.account.user()
      try Task.checkCancellation()
      self.user = user; self.name = self.user?.preferredDisplayName ?? ""
    }
  }
  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    guard controller === appleController else { return }
    appleController = nil; appleChallenge = nil; authorizing = false
    if (error as? ASAuthorizationError)?.code != .canceled { message = "Apple 登录未完成，请重试。" }
  }
  func rename() {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.unicodeScalars.count <= 64,
          !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      message = "昵称需为 1–64 个字符，不能包含换行或控制字符。"; return
    }
    perform {
      let identity = try await self.account.credentials()
      try await self.client.rename(value, token: identity.token)
      let profile = try await self.client.profile(token: identity.token)
      try await self.account.updateUser(profile.user, matching: identity.token)
      try Task.checkCancellation()
      self.user = profile.user; self.name = profile.user.preferredDisplayName
    }
  }
  func logout(all: Bool = false, delete: Bool = false) {
    perform {
      if delete {
        let identity = try await self.account.credentials()
        try await self.client.deleteAccount(token: identity.token)
        try await self.account.forget()
      } else {
        do { try await self.account.logout(all: all) }
        catch { self.user = try await self.account.user(); throw error }
      }
      self.user = nil; self.name = ""
    }
  }
  func close() { pending?.cancel(); if #available(macOS 13.0, *) { appleController?.cancel() }; authorizing = false; appleController = nil; appleChallenge = nil; code = ""; target = ""; challenge = nil }
}

private struct MacAccountView: View {
  @ObservedObject var model: MacAccountModel
  @State private var deleting = false
  @State private var clipboard = false
  @State private var settings = false
  var body: some View {
    Form {
      if let user = model.user {
        Text(user.preferredDisplayName).font(.title2)
        TextField("昵称", text: $model.name)
        Button("保存昵称") { model.rename() }
        Button("云剪贴板…") { clipboard = true }
        Button("桌面设置同步…") { settings = true }
        Button("退出登录") { model.logout() }
        Button("退出所有设备") { model.logout(all: true) }
        Button("注销账号", role: .destructive) { deleting = true }
      } else {
        Button("使用 Apple 登录") { model.appleLogin() }.disabled(model.providers["apple"] != true)
        Picker("验证码登录", selection: $model.channel) {
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
            Button("登录") { model.codeLogin() }
              .disabled(model.expiresAt <= timeline.date || model.code.utf8.count != 6 || !model.code.utf8.allSatisfy { (48...57).contains($0) })
          }
        }
        if model.providers[model.channel] != true { Text("此登录方式尚未启用。").foregroundStyle(.secondary) }
      }
      if model.busy { ProgressView() }
      if let message = model.message { Text(message).foregroundStyle(.secondary) }
    }
    .padding(24).frame(width: 420, height: 440).disabled(model.busy || model.authorizing)
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

@_cdecl("MSIMEShowBackendAccount")
func showBackendAccount() {
  Task { @MainActor in BackendAccountWindow.shared.showAccount() }
}
