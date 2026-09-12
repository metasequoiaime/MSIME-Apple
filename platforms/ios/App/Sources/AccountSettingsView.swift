import SwiftUI
import AuthenticationServices

struct AccountSettingsView: View {
  @State private var signedIn = false
  @State private var designs = CustomSkinLibrary.designs
  @State private var replayOnboarding = false

  var body: some View {
    Form {
      AppleAccountSection(signedIn: $signedIn)

      Section("个性化") {
        NavigationLink(destination: AppIconSettingsView()) {
          HStack(spacing: 12) {
            accountIcon("app.badge", color: MetasequoiaTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
              Text("App 图标").foregroundStyle(.primary)
              Text("给主屏幕上的水杉换个颜色").font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
        }.accessibilityIdentifier("accountAppIcon")
      }

      Section("我的创作") {
        NavigationLink(destination: CustomSkinEditorView()) {
          HStack(spacing: 12) {
            accountIcon("paintbrush.pointed.fill", color: MetasequoiaTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
              Text("我的设计").foregroundStyle(.primary)
              Text("保存在本机的 \(designs.count) 款皮肤").font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
        }.accessibilityIdentifier("accountLocalDesigns")
      }

      if signedIn {
        Section("我发布的作品") {
          NavigationLink(destination: SkinCommunityView(onlyMine: true)) {
            Label("我发布的皮肤", systemImage: "paintpalette")
          }.accessibilityIdentifier("accountPublishedSkins")
          ForEach(CommunityResourceKind.allCases) { kind in
            NavigationLink(destination: CommunityResourcesView(kind: kind, initialScope: "mine")) {
              Label("我发布的\(kind.title)", systemImage: kind.icon)
            }
          }
        }
        Section("我的收藏") {
          ForEach(CommunityResourceKind.allCases) { kind in
            NavigationLink(destination: CommunityResourcesView(kind: kind, initialScope: "saved")) {
              Label("收藏的\(kind.title)", systemImage: "bookmark")
            }
          }
        }
      }

      if signedIn {
        Section("云端数据") {
          NavigationLink(destination: SettingsSyncView(session: .shared, client: BackendAccountClient())) {
            Label("设置同步", systemImage: "arrow.triangle.2.circlepath")
          }.accessibilityIdentifier("accountSettingsSync")
          NavigationLink(destination: CommunityResourcesAccountView()) {
            Label("词包与回复模板", systemImage: "books.vertical")
          }.accessibilityIdentifier("accountCommunityResources")
          NavigationLink(destination: CloudDictionaryView()) {
            Label("云词库", systemImage: "character.book.closed")
          }.accessibilityIdentifier("accountCloudDictionary")
          NavigationLink(destination: CloudClipboardView(session: .shared, client: BackendAccountClient())) {
            Label("云剪贴板", systemImage: "doc.on.clipboard")
          }.accessibilityIdentifier("accountCloudClipboard")
        }
      }

        Section("了解水杉") {
          NavigationLink(destination: DesktopDownloadView()) {
            Label("电脑版下载", systemImage: "desktopcomputer")
          }.accessibilityIdentifier("desktopDownloadLink")
          NavigationLink(destination: AboutView()) {
            Label("关于水杉", systemImage: "info.circle")
          }.accessibilityIdentifier("aboutSettingsLink")
        }

      Section {
        Button { replayOnboarding = true } label: {
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
    .sheet(isPresented: $replayOnboarding) {
      NavigationView { WelcomeFlowView(onFinish: { replayOnboarding = false }) }.navigationViewStyle(.stack)
    }
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
    .sheet(isPresented: $editProfile) { AccountProfileEditor(initialUser: user) { profile in user = profile } }
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
  var initialUser: CommunityUser? = nil
  var onSaved: (CommunityUser) -> Void
  @Environment(\.dismiss) private var dismiss
  @FocusState private var editingName: Bool
  @State private var profile: CommunityProfile?
  @State private var name = ""
  @State private var loading = true
  @State private var saving = false
  @State private var message: String?
  @State private var copiedID = false
  @State private var confirmDiscard = false

  private var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var validName: Bool {
    !normalizedName.isEmpty && normalizedName.unicodeScalars.count <= 64 &&
      !normalizedName.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
  }
  private var hasChanges: Bool {
    guard let profile else { return false }
    return normalizedName != profile.user.preferredDisplayName
  }
  private var previewName: String {
    if profile == nil { return initialUser?.preferredDisplayName ?? "水杉用户" }
    return normalizedName.isEmpty ? "你的昵称" : normalizedName
  }
  private var nameHint: String {
    if normalizedName.isEmpty { return "取一个喜欢的名字，让大家记住你。" }
    if !validName { return "昵称最多 64 个字符，请勿使用换行或控制字符。" }
    return "昵称会显示在社区作品中，已发布的作品也会同步更新。"
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
      ScrollView {
        VStack(spacing: 28) {
          profilePreview
          if loading {
            ProgressView("正在加载资料")
              .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 28)
          } else if profile != nil {
            nicknameCard
            accountDetails
          }
          if let message, profile == nil {
            VStack(alignment: .leading, spacing: 12) {
              Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
              if profile == nil {
                Button("重新加载") { Task { await load() } }
                  .font(.subheadline.weight(.semibold))
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("accountProfileError")
          }
        }
        .frame(maxWidth: 540)
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 28)
        .frame(maxWidth: .infinity)
      }
      .background(MetasequoiaTheme.canvas.ignoresSafeArea())
      .navigationTitle("编辑资料")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            editingName = false
            if hasChanges { confirmDiscard = true } else { dismiss() }
          } label: {
            Image(systemName: "xmark").font(.subheadline.weight(.semibold))
              .frame(width: 32, height: 32)
          }
          .accessibilityLabel("关闭编辑资料").disabled(saving)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") { editingName = false }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
      .interactiveDismissDisabled(hasChanges || saving)
      .confirmationDialog("要放弃这次修改吗？", isPresented: $confirmDiscard, titleVisibility: .visible) {
        Button("放弃修改", role: .destructive) { dismiss() }
        Button("继续编辑", role: .cancel) {}
      }
      .task { await load() }
    }
    .navigationViewStyle(.stack)
    .tint(MetasequoiaTheme.accent)
  }

  private var profilePreview: some View {
    VStack(spacing: 14) {
      ZStack {
        Circle().fill(MetasequoiaTheme.accent.opacity(0.07)).frame(width: 104, height: 104)
        Circle()
          .fill(LinearGradient(colors: [MetasequoiaTheme.needle, MetasequoiaTheme.forest],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(width: 84, height: 84)
        Text(String(previewName.prefix(1)))
          .font(.system(size: 32, weight: .medium, design: .rounded)).foregroundStyle(.white)
      }
      .accessibilityHidden(true)
      VStack(spacing: 6) {
        Text(previewName).font(.title2.weight(.semibold))
          .multilineTextAlignment(.center).lineLimit(2)
        Text("在水杉，留下你的名字")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 8)
    .accessibilityIdentifier("accountProfilePreview")
  }

  private var nicknameCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("社区昵称").font(.subheadline.weight(.semibold))
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
          TextField("设置你的昵称", text: $name)
            .font(.title3.weight(.medium))
            .textContentType(.nickname).submitLabel(.done)
            .focused($editingName).onSubmit { editingName = false }
            .disabled(saving)
            .accessibilityIdentifier("accountNicknameField")
          if !name.isEmpty {
            Button { name = ""; editingName = true } label: {
              Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("清空昵称").disabled(saving)
          }
        }
        Divider()
        HStack(alignment: .top, spacing: 16) {
          Text(nameHint).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Text("\(normalizedName.unicodeScalars.count)/64")
            .monospacedDigit().fixedSize()
            .accessibilityLabel("已输入 \(normalizedName.unicodeScalars.count) 个字符，最多 64 个")
        }
        .font(.caption)
        .foregroundStyle(validName || normalizedName.isEmpty ? Color.secondary : Color.red)
      }
      .padding(20)
      .background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 22))
      .overlay {
        RoundedRectangle(cornerRadius: 22)
          .strokeBorder(editingName ? MetasequoiaTheme.accent.opacity(0.5) : .clear, lineWidth: 1.5)
      }
    }
  }

  private var accountDetails: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("账号信息").font(.subheadline.weight(.semibold))
      VStack(spacing: 0) {
        if let profile {
          Button {
            UIPasteboard.general.string = profile.user.id
            copiedID = true
          } label: {
            detailRow("账号 ID", value: "#" + profile.user.id.prefix(6).uppercased(),
                      symbol: "number", accessory: copiedID ? "checkmark" : "doc.on.doc")
          }
          .buttonStyle(.plain)
          .accessibilityLabel(copiedID ? "账号 ID 已复制" : "复制完整账号 ID")
          .accessibilityIdentifier("copyAccountID")
          if copiedID {
            Text("账号 ID 已复制").font(.caption).foregroundStyle(MetasequoiaTheme.accent)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 20).padding(.bottom, 12)
          }
          Divider().padding(.leading, 54)
          detailRow("登录方式", value: loginProviders(profile), symbol: "person.badge.key")
          if let joined {
            Divider().padding(.leading, 54)
            detailRow("加入水杉", value: joined, symbol: "calendar")
          }
        }
      }
      .background(MetasequoiaTheme.surface, in: RoundedRectangle(cornerRadius: 22))
      Label("轻点账号 ID 即可复制", systemImage: "lock")
        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
    }
  }

  private func detailRow(_ title: String, value: String, symbol: String,
                         accessory: String? = nil) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: symbol).font(.subheadline)
        .foregroundStyle(MetasequoiaTheme.accent).frame(width: 22)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value.isEmpty ? "暂无信息" : value).font(.subheadline.weight(.medium))
          .foregroundStyle(.primary)
      }
      Spacer(minLength: 8)
      if let accessory {
        Image(systemName: accessory).font(.subheadline)
          .foregroundStyle(MetasequoiaTheme.accent)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
  }

  private func loginProviders(_ profile: CommunityProfile) -> String {
    profile.identities.map {
      switch $0.provider {
      case "apple": return "Apple"
      case "email": return "邮箱"
      case "phone", "sms": return "手机号"
      default: return $0.provider
      }
    }.joined(separator: "、")
  }

  private var saveBar: some View {
    VStack(spacing: 12) {
      if let message, profile != nil {
        Label(message, systemImage: "exclamationmark.circle")
          .font(.caption).foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("accountProfileSaveError")
      }
      Button(action: save) {
        HStack(spacing: 10) {
          if saving { ProgressView().tint(.white) }
          Text(saving ? "正在保存…" : "保存修改").font(.body.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 17)
        .background(MetasequoiaTheme.forest.opacity(canSave || saving ? 1 : 0.45),
                    in: RoundedRectangle(cornerRadius: 18))
      }
      .buttonStyle(.plain)
      .disabled(!canSave)
      .accessibilityIdentifier("saveAccountProfile")
    }
    .frame(maxWidth: 540)
    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
    .frame(maxWidth: .infinity)
    .background(.regularMaterial)
  }

  private var canSave: Bool { !loading && !saving && profile != nil && validName && hasChanges }

  private func save() {
    guard canSave else { return }
    editingName = false
    saving = true
    message = nil
    let submittedName = normalizedName
    Task {
      defer { saving = false }
      do {
        let updated = try await SkinCommunityAPI.shared.updateProfile(name: submittedName)
        onSaved(updated.user)
        dismiss()
      } catch { message = error.localizedDescription }
    }
  }

  @MainActor private func load() async {
    loading = true
    message = nil
    defer { loading = false }
    do {
      let result = try await SkinCommunityAPI.shared.profile()
      profile = result
      name = result.user.preferredDisplayName
      onSaved(result.user)
    } catch is CancellationError {
    } catch { message = error.localizedDescription }
  }
}
