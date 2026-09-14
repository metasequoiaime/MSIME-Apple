import Foundation

// Whether an account is signed in, so the settings can say what a provider needs before anyone
// turns it on. Reading a file or the keychain is cheap and synchronous, and the token itself is not
// needed to answer this much.
//
// 匿名账号不在钥匙串里,只问钥匙串就会在输入法明明登着的时候报「未登录」—— 设置页于是劝用户去登录一个
// 他已经有的账号,而候选旁的译文一直在正常出现。
@_cdecl("MSIMEBackendAccountSignedIn")
func backendAccountSignedIn() -> Bool {
  if ((try? BackendKeychain().load()) ?? nil) != nil { return true }
  return ((try? BackendAnonymousAccount.sessionStorage().load()) ?? nil) != nil
}

// 首次激活时自动开一个匿名账号。The controller is Objective-C and this target emits no -Swift.h, so the
// entry point is a @_cdecl function like the rest of the bridges in this file.
//
// 只尝试一次,失败就算了:开户不成功不该拦着用户打字,下次激活会再试。登录成功前不写钥匙串,所以失败
// 不会留下一把永远登不上的凭据。
private actor AnonymousBootstrap {
  static let shared = AnonymousBootstrap()
  private var attempted = false
  func runOnce() async {
    guard !attempted else { return }
    attempted = true
    // 用户主动挂上去的身份在钥匙串里;先问它,匿名账号不能把它顶掉。
    let signedIn = BackendAccountSession()
    if (try? await signedIn.accessToken()) != nil { return }
    // 匿名账号连同它换来的会话都留在本机文件里,不进钥匙串 —— 自动生成、用户全程不知情的东西不该
    // 让输入法去问登录密码。
    let anonymous = BackendAccountSession(storage: BackendAnonymousAccount.sessionStorage())
    if (try? await anonymous.accessToken()) != nil { return }
    _ = try? await BackendAnonymousAccount.ensureSignedIn(session: anonymous, client: BackendAccountClient())
  }
}

@_cdecl("MSIMEEnsureAnonymousAccount")
func ensureAnonymousAccount() {
  Task { await AnonymousBootstrap.shared.runOnce() }
}
