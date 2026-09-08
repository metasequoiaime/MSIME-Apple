import SwiftUI
import AuthenticationServices

struct AccountSettingsView: View {
  @State private var signedIn = false
  @State private var designs = CustomSkinLibrary.designs
  @State private var showPublish = false

  var body: some View {
    Form {
      AppleAccountSection(signedIn: $signedIn)

      Section("我的创作") {
        NavigationLink(destination: CustomSkinEditorView()) {
          HStack(spacing: 12) {
            accountIcon("paintbrush.pointed.fill", color: .purple)
            VStack(alignment: .leading, spacing: 4) {
              Text("我的设计").foregroundStyle(.primary)
              Text("保存在本机的 \(designs.count) 款皮肤").font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
        }.accessibilityIdentifier("accountLocalDesigns")
        if signedIn {
          NavigationLink(destination: SkinCommunityView(onlyMine: true)) {
            HStack(spacing: 12) {
              accountIcon("square.stack.3d.up.fill", color: .orange)
              VStack(alignment: .leading, spacing: 4) {
                Text("已发布作品").foregroundStyle(.primary)
                Text("查看下载、评分和管理作品").font(.caption).foregroundStyle(.secondary)
              }
            }.padding(.vertical, 4)
          }.accessibilityIdentifier("accountPublishedSkins")
          Button { showPublish = true } label: {
            Label("发布新作品", systemImage: "square.and.arrow.up")
          }
        }
      }

      if signedIn {
        Section("云端数据") {
          NavigationLink(destination: SettingsSyncView(session: .shared, client: BackendAccountClient())) {
            Label("设置同步", systemImage: "arrow.triangle.2.circlepath")
          }.accessibilityIdentifier("accountSettingsSync")
          NavigationLink(destination: CloudClipboardView(session: .shared, client: BackendAccountClient())) {
            Label("云剪贴板", systemImage: "doc.on.clipboard")
          }.accessibilityIdentifier("accountCloudClipboard")
        }
      }

      Section("我的记录") {
        NavigationLink(destination: TypingStatisticsView()) {
          HStack(spacing: 12) {
            accountIcon("chart.bar.xaxis", color: .blue)
            VStack(alignment: .leading, spacing: 4) {
              Text("我的打字统计").foregroundStyle(.primary)
              Text("查看输入趋势和语言分布").font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
        }
      }
      Section {
        NavigationLink(destination: WelcomeFlowView()) {
          Label("重新查看新手引导", systemImage: "sparkles.rectangle.stack")
        }.accessibilityIdentifier("replayOnboardingLink")
      }
      Section {
        Label("本地数据与云端作品", systemImage: "lock.shield")
          .font(.subheadline)
        Text("皮肤设计和打字统计保存在本机。只有你主动发布的作品会分享至社区；Apple 登录不会自动上传本地设计或输入记录。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("我的")
    .task { designs = CustomSkinLibrary.designs }
    .sheet(isPresented: $showPublish) { CommunityPublishView {} }
  }

  private func accountIcon(_ symbol: String, color: Color) -> some View {
    Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
      .foregroundStyle(color).frame(width: 42, height: 42)
      .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
  }
}

struct AppleAccountSection: View {
  @Binding var signedIn: Bool
  @StateObject private var codeModel = CodeLoginModel()
  @State private var codeChannel: CodeLoginChannel?
  @State private var user: CommunityUser?
  @State private var editProfile = false
  @State private var needsRecovery = false
  @State private var busy = false
  @State private var message: String?
  @State private var challenge: CommunityChallenge?
  @State private var confirmDeleteAccount = false
  @State private var confirmLogoutAll = false
  private let api = SkinCommunityAPI.shared

  private var displayName: String {
    user?.preferredDisplayName ?? "水杉用户"
  }

  var body: some View {
    Section {
      HStack(spacing: 14) {
        Image(systemName: signedIn ? "person.crop.circle.fill" : "person.crop.circle")
          .font(.system(size: 48)).foregroundStyle(MetasequoiaTheme.forest)
        VStack(alignment: .leading, spacing: 5) {
          Text(signedIn ? displayName : "欢迎来到水杉")
            .font(.title3.bold())
          Text(signedIn ? "水杉账号已登录" : "登录，分享你的键盘设计")
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }.padding(.vertical, 10)
      if signedIn {
        Button { editProfile = true } label: {
          HStack {
            Label("个人资料", systemImage: "person.text.rectangle")
            Spacer()
            Text("查看与编辑")
              .font(.subheadline).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
          }
        }.accessibilityIdentifier("editAccountProfile")
        Menu("账号") {
          Button("退出登录") { run { try await api.logout(); signedIn = false; await prepareLogin() } }
          Button("退出所有设备") { confirmLogoutAll = true }
          Button("重新登录") { run { try await api.clearExpiredLogin(); signedIn = false; await prepareLogin() } }
          Button("注销账号", role: .destructive) { confirmDeleteAccount = true }
        }
      } else {
        if let challenge {
          SignInWithAppleButton(.signIn) { request in
            request.nonce = challenge.nonce
            request.state = challenge.challenge_id
          } onCompletion: { result in
            switch result {
            case .success(let authorization):
              guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    credential.state == challenge.challenge_id,
                    let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                message = "Apple 登录未返回有效凭据，请重试。"; Task { await prepareLogin() }; return
              }
              run {
                do { try await api.login(challenge: challenge.challenge_id, identityToken: token) }
                catch { await prepareLogin(); throw error }
                user = try await api.currentUser()
                signedIn = true
              }
            case .failure(let error):
              if (error as? ASAuthorizationError)?.code != .canceled { message = error.localizedDescription }
              Task { await prepareLogin() }
            }
          }.accessibilityIdentifier("backendAppleSignIn").signInWithAppleButtonStyle(.black).frame(height: 44).disabled(busy)
        } else if codeModel.providers["apple"] == true {
          Button("准备 Apple 登录") { Task { await prepareLogin() } }.disabled(busy)
        }
        ForEach(CodeLoginChannel.allCases) { channel in
          if codeModel.providers[channel.rawValue] == true {
            Button(channel.title) { codeModel.user = nil; codeModel.message = nil; codeChannel = channel }
              .accessibilityIdentifier("backendCodeLogin_\(channel.rawValue)")
          }
        }
        Button("刷新登录方式") { Task { await codeModel.loadProviders(); await prepareLogin() } }
        if let status = codeModel.message { Text(status).font(.caption).foregroundStyle(.secondary) }
        Text("登录后可在皮肤社区发布、下载和评分。日常输入无需登录。").font(.caption).foregroundStyle(.secondary)
        if needsRecovery {
          Button("清除失效登录状态") { run { try await api.clearExpiredLogin(); signedIn = false; needsRecovery = false; await prepareLogin() } }
            .font(.caption)
        }
      }
    }
    .task {
      await codeModel.loadProviders()
      do { user = try await api.currentUser(); signedIn = user != nil } catch { needsRecovery = true; message = error.localizedDescription }
      if signedIn {
        do { user = try await api.profile().user }
        catch is CancellationError { }
        catch { message = error.localizedDescription }
      } else { await prepareLogin() }
    }
    .sheet(item: $codeChannel, onDismiss: {
      Task {
        do { user = try await api.currentUser(); signedIn = user != nil }
        catch { message = error.localizedDescription }
      }
    }) { channel in CodeLoginView(model: codeModel, channel: channel) }
    .sheet(isPresented: $editProfile) { AccountProfileEditor { profile in user = profile } }
    .alert("账号与登录", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
      Button("好", role: .cancel) {}
    } message: { Text(message ?? "") }
    .confirmationDialog("退出所有设备后，所有设备都需要重新登录。", isPresented: $confirmLogoutAll, titleVisibility: .visible) {
      Button("退出所有设备") { run { try await api.logout(all: true); signedIn = false; await prepareLogin() } }
    }
    .confirmationDialog("注销账号将删除已发布皮肤、评分及其他云端账号数据，无法撤销。", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
      Button("注销账号", role: .destructive) { run { try await api.logout(deleteAccount: true); signedIn = false; await prepareLogin() } }
    }
  }
  @MainActor private func prepareLogin() async {
    challenge = nil
    guard codeModel.providers["apple"] == true else { return }
    do { challenge = try await api.challenge() } catch { message = error.localizedDescription }
  }
  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }; busy = true
    Task {
      defer { busy = false }
      do { try await action() }
      catch {
        message = error.localizedDescription
        if let state = try? await api.signedIn() {
          signedIn = state
          if !state { await prepareLogin() }
        }
      }
    }
  }
}

struct AccountProfileEditor: View {
  var onSaved: (CommunityUser) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var profile: CommunityProfile?
  @State private var name = ""
  @State private var busy = false
  @State private var message: String?
  private var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var validName: Bool {
    !normalizedName.isEmpty && normalizedName.unicodeScalars.count <= 64 &&
      !normalizedName.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
  }
  private var joined: String? {
    guard let value = profile?.user.created_at else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fractional = formatter.date(from: value)
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = fractional ?? formatter.date(from: value) else { return nil }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
  var body: some View {
    NavigationView {
      Form {
        Section {
          TextField("设置你的昵称", text: $name)
            .textContentType(.nickname).submitLabel(.done)
            .accessibilityIdentifier("accountNicknameField")
            .disabled(profile == nil || busy)
          Text("\(normalizedName.unicodeScalars.count)/64").font(.caption).foregroundStyle(.secondary)
        } header: { Text("昵称") } footer: {
          Text("昵称会公开显示在你的社区作品上，修改后已发布作品也会使用新昵称。")
        }
        if let profile {
          Section("账号信息") {
            Button {
              UIPasteboard.general.string = profile.user.id
              message = "完整账号 ID 已复制。"
            } label: {
              HStack {
                Text("账号 ID").foregroundStyle(.primary)
                Spacer()
                Text("#" + profile.user.id.prefix(6).uppercased()).font(.subheadline.monospaced())
                Image(systemName: "doc.on.doc").font(.subheadline)
              }
            }.accessibilityLabel("复制完整账号 ID")
              .accessibilityIdentifier("copyAccountID")
            HStack {
              Text("登录方式")
              Spacer()
              Text(profile.identities.map { $0.provider == "apple" ? "Apple" : $0.provider }.joined(separator: "、"))
                .foregroundStyle(.secondary)
            }
            if let joined {
              HStack { Text("注册时间"); Spacer(); Text(joined).foregroundStyle(.secondary) }
            }
          }
        }
        if busy { ProgressView().frame(maxWidth: .infinity) }
        if profile == nil && !busy { Button("重新加载资料") { load() } }
      }
      .navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            busy = true
            Task {
              defer { busy = false }
              do {
                let updated = try await SkinCommunityAPI.shared.updateProfile(name: normalizedName)
                onSaved(updated.user)
                dismiss()
              } catch { message = error.localizedDescription }
            }
          }.disabled(busy || profile == nil || !validName || normalizedName == profile?.user.preferredDisplayName)
            .accessibilityIdentifier("saveAccountProfile")
        }
      }
      .task { load() }
      .alert("个人资料", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
        Button("好", role: .cancel) {}
      } message: { Text(message ?? "") }
    }
  }
  private func load() {
    guard !busy else { return }; busy = true
    Task {
      defer { busy = false }
      do {
        let result = try await SkinCommunityAPI.shared.profile()
        profile = result; name = result.user.preferredDisplayName
        onSaved(result.user)
      } catch { message = error.localizedDescription }
    }
  }
}
