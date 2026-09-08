# Apple 共通后端接入

`BackendAccountClient.swift` 是 iOS 与 macOS 可复用的账号网络层。服务地址固定为生产 HTTPS，拒绝重定向，禁用 Cookie 和缓存，限制普通 JSON 响应大小；不记录凭据或供应商响应。平台负责 Keychain、登录 UI、会话刷新协调和用户明确开启的同步。

当前已提供渠道查询、登录挑战、登录、刷新、账号资料、修改名称、注销会话与删除账号的传输。iOS 设置页通过原生 Apple 登录按钮传递服务端 nonce/state，令牌存入仅当前设备可用的 Keychain；会话 actor 协调刷新并拒绝退出后迟到的响应。真实签名账号验收及其他平台 UI 仍待完成。

验证：`swift test --package-path shared/backend`。iOS App 和 ServiceTests 的 XcodeGen 输入包含同一份实现。

`BackendClipboardClient.swift` 提供云剪贴板操作，iOS 账号页连接这些操作；Swift 客户端已用临时账号完成生产 API 往返。大快照、设置和词库同步会使用各自的类型与大小限制，不复用普通 JSON 的 1 MiB 限额。

词库导出通过 `download` 流式写入独占临时目录，普通 JSON 请求仍限制为 1 MiB。下载拒绝重定向、非文本响应、超限及已知长度不完整的文件，失败或取消清理半成品。成功后调用方拥有返回文件及父目录，应在系统分享结束或取消时删除；不要将这些私人文件写入日志或公共缓存。

`BackendCommunityResourceClient.swift` 提供共享词包和回复模板的分页查询、详情、发布/版本更新、收藏、评分和删除。发布使用调用方持有的稳定 UUID 与已预览版本，版本冲突直接返回，不自动重试覆盖；私有列表和写操作由界面提供当前账号凭据。列表包含最多 20 份完整资源，因此仅该列表允许最多 48 MiB JSON，详情最多 3 MiB；其他普通请求继续限制为 1 MiB。
