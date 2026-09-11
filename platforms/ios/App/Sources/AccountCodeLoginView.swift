import SwiftUI

@MainActor
final class CodeLoginModel: ObservableObject {
  @Published var user: BackendAccountClient.User?
  @Published var providers: [String: Bool] = [:]
  @Published var busy = false
  @Published var message: String?
  let client = BackendAccountClient()
  let session = BackendAccountSession.shared

  func loadProviders() async {
    await perform { self.providers = try await self.client.providers() }
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
      self.user = try await self.session.user()
    }
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

enum CodeLoginChannel: String, CaseIterable, Identifiable {
  case email, phone
  var id: String { rawValue }
  var title: String { self == .email ? "邮箱登录" : "手机号登录" }
}

struct CodeLoginView: View {
  @ObservedObject var model: CodeLoginModel
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
