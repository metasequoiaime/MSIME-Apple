import AuthenticationServices
import SwiftUI

@MainActor
final class AccountSettingsModel: ObservableObject {
  @Published var user: BackendAccountClient.User?
  @Published var providers: [String: Bool] = [:]
  @Published var challenge: BackendAccountClient.Challenge?
  @Published var busy = false
  @Published var message: String?
  let client = BackendAccountClient()
  let session = BackendAccountSession.shared

  func load() async {
    await perform {
      self.providers = try await self.client.providers()
      self.user = try await self.session.user()
      if self.user != nil {
        do {
          let token = try await self.session.accessToken()
          self.user = try await self.client.profile(token: token).user
        } catch let failure as BackendAccountClient.Failure where failure.status == 401 {
          try await self.session.forget(); self.user = nil
        }
      }
      if self.user == nil && self.providers["apple"] == true {
        self.challenge = try await self.client.challenge(provider: "apple")
      }
    }
  }
  func signIn(_ authorization: ASAuthorization, challenge: BackendAccountClient.Challenge) async {
    await perform {
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            credential.state == challenge.challenge_id,
            let bytes = credential.identityToken, let token = String(data: bytes, encoding: .utf8)
      else { throw BackendAccountClient.Failure(status: 401) }
      try await self.session.signIn(challenge: challenge.challenge_id, credential: token)
      self.user = try await self.session.user(); self.challenge = nil
    }
  }
  func requestCode(provider: String, target: String) async -> BackendAccountClient.Challenge? {
    var response: BackendAccountClient.Challenge?
    await perform {
      guard self.providers[provider] == true else { throw BackendAccountClient.Failure(status: 503) }
      response = try await self.client.challenge(provider: provider, target: target)
    }
    return response
  }
  func signInWithCode(challenge: String, code: String) async {
    await perform {
      try await self.session.signIn(challenge: challenge, credential: code)
      self.user = try await self.session.user(); self.challenge = nil
    }
  }
  func rename(_ name: String) async {
    await perform {
      let token = try await self.session.accessToken()
      try await self.client.rename(name, token: token)
      self.user = try await self.client.profile(token: token).user
    }
  }
  func logout(all: Bool = false) async {
    await perform {
      defer { self.user = nil; self.challenge = nil }
      try await self.session.logout(all: all)
    }
    let logoutMessage = message
    await load()
    if let logoutMessage { message = logoutMessage }
  }
  func deleteAccount() async {
    await perform {
      let token = try await self.session.accessToken()
      try await self.client.deleteAccount(token: token)
      try await self.session.forget(); self.user = nil; self.challenge = nil
    }
    if user == nil { await load() }
  }
  private func perform(_ operation: () async throws -> Void) async {
    guard !busy else { return }
    busy = true; message = nil
    defer { busy = false }
    do { try await operation() }
    catch is CancellationError { }
    catch let error as BackendAccountClient.Failure { message = error.localizedDescription }
    catch { message = "连接未完成，请检查网络后重试。" }
  }
}

struct AccountSettingsView: View {
  @StateObject private var model = AccountSettingsModel()
  @State private var appleChallenge: BackendAccountClient.Challenge?
  @State private var name = ""
  @State private var codeChannel: CodeLoginChannel?
  @State private var confirmDelete = false
  @State private var confirmLogoutAll = false

  var body: some View {
    Form {
      if let user = model.user {
        Section("我的账号") {
          Text(user.display_name.isEmpty ? "水杉用户" : user.display_name)
          TextField("昵称", text: $name)
            .onAppear { name = user.display_name }
            .accessibilityIdentifier("accountDisplayName")
          Button("保存昵称") { Task { await model.rename(name) } }
            .disabled(name.count > 64 || name == user.display_name)
          Button("退出登录") { Task { await model.logout() } }
          Button("退出所有设备") { confirmLogoutAll = true }
        }
        Section("云端数据") {
          NavigationLink(destination: CloudClipboardView(session: model.session, client: model.client)) {
            Label("云剪贴板", systemImage: "doc.on.clipboard")
          }
        }
        Section {
          Button("注销账号", role: .destructive) { confirmDelete = true }
        } footer: {
          Text("注销会删除云端账号及关联的词库、设置和剪贴板数据，需要最近十分钟内登录。")
        }
      } else {
        Section {
          if model.providers["apple"] == true {
            SignInWithAppleButton(.signIn) { request in
              appleChallenge = model.challenge
              request.nonce = model.challenge?.nonce
              request.state = model.challenge?.challenge_id
            } onCompletion: { result in
              guard let challenge = appleChallenge else { return }
              appleChallenge = nil
              switch result {
              case .success(let authorization): Task { await model.signIn(authorization, challenge: challenge) }
              case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                  model.message = "Apple 登录未完成，请重试。"
                }
                Task { await model.load() }
              }
            }
            .frame(height: 46)
            .disabled(model.challenge?.nonce == nil)
            .accessibilityIdentifier("backendAppleSignIn")
          }
          ForEach(CodeLoginChannel.allCases) { channel in
            if model.providers[channel.rawValue] == true {
              Button(channel.title) { model.message = nil; codeChannel = channel }
                .accessibilityIdentifier("backendCodeLogin_\(channel.rawValue)")
            }
          }
          Button("刷新登录方式") { Task { await model.load() } }
        } header: {
          Text("登录水杉账号")
        } footer: {
          Text("登录本身不会上传输入内容、个人词库或系统剪贴板。")
        }
      }
      if model.busy { ProgressView("正在处理…") }
      if let message = model.message { Text(message).foregroundStyle(.secondary) }
    }
    .disabled(model.busy)
    .navigationTitle("账号")
    .task { await model.load() }
    .sheet(item: $codeChannel) { channel in CodeLoginView(model: model, channel: channel) }
    .alert("注销水杉账号？", isPresented: $confirmDelete) {
      Button("取消", role: .cancel) { }
      Button("永久注销", role: .destructive) { Task { await model.deleteAccount() } }
    } message: { Text("此操作无法撤销。云端账号及关联数据将被删除。") }
    .alert("退出所有设备？", isPresented: $confirmLogoutAll) {
      Button("取消", role: .cancel) { }
      Button("退出所有设备", role: .destructive) { Task { await model.logout(all: true) } }
    } message: { Text("所有设备都需要重新登录。") }
  }
}

enum CodeLoginChannel: String, CaseIterable, Identifiable {
  case email, phone
  var id: String { rawValue }
  var title: String { self == .email ? "邮箱登录" : "手机号登录" }
}

private struct CodeLoginView: View {
  @ObservedObject var model: AccountSettingsModel
  let channel: CodeLoginChannel
  @Environment(\.dismiss) private var dismiss
  @State private var target = ""
  @State private var code = ""
  @State private var challenge: BackendAccountClient.Challenge?
  @State private var expiresAt = Date.distantPast
  @State private var resendAt = Date.distantPast
  @State private var pending: Task<Void, Never>?

  var body: some View {
    NavigationView {
      Form {
        Section {
          TextField(channel == .email ? "邮箱地址" : "手机号（含国家区号，如 +86）", text: $target)
            .keyboardType(channel == .email ? .emailAddress : .phonePad)
            .textContentType(channel == .email ? .emailAddress : .telephoneNumber)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("backendCodeTarget")
            .onChange(of: target) { _ in challenge = nil; code = "" }
          TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let seconds = max(0, Int(ceil(resendAt.timeIntervalSince(timeline.date))))
            Button(seconds == 0 ? "获取验证码" : "\(seconds) 秒后可重新发送") {
              pending = Task {
                let response = await model.requestCode(provider: channel.rawValue,
                  target: target.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !Task.isCancelled, let response else { return }
                challenge = response; code = ""
                expiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in))
                resendAt = Date().addingTimeInterval(60)
              }
            }
            .disabled(seconds > 0 || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          if let challenge {
            TextField("6 位验证码", text: $code)
              .keyboardType(.numberPad)
              .textContentType(.oneTimeCode)
              .accessibilityIdentifier("backendVerificationCode")
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              let expired = expiresAt <= timeline.date
              Button(expired ? "验证码已过期，请重新获取" : "登录") {
                pending = Task { await model.signInWithCode(challenge: challenge.challenge_id, code: code) }
              }
              .disabled(expired || code.utf8.count != 6 || !code.utf8.allSatisfy { (48...57).contains($0) })
            }
          }
        } footer: {
          Text("验证码只用于本次登录，请勿向他人透露。")
        }
        if model.busy { ProgressView("正在处理…") }
        if let message = model.message { Text(message).foregroundStyle(.secondary) }
      }
      .disabled(model.busy)
      .navigationTitle(channel.title)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { pending?.cancel(); dismiss() } } }
    }
    .onChange(of: model.user?.id) { userID in if userID != nil { dismiss() } }
    .onDisappear { pending?.cancel() }
  }
}
