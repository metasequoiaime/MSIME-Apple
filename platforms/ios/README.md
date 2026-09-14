# iOS App 与键盘扩展

`MSIMEClient.xcodeproj` 包含设置 App、`UIInputViewController` 键盘扩展和共享 Swift 适配层。输入算法与组合状态仍由 C++ Engine 管理；扩展只负责宿主事件、候选展示和文本提交。语音录制由 App 的 Swift `AVAudioEngine` 宿主管理，键盘扩展不直接使用桌面音频采集桥接。

键盘扩展通过共享宿主策略执行智能标点：中文跟随模式且 Engine 空闲时，逗号、句点或冒号紧跟 ASCII 字母/数字会保留 ASCII，锁定中文或英文优先；已有组合、日语、英文和本地模式仍交给 Engine。扩展只从 `UITextDocumentProxy.documentContextBeforeInput` 提取紧邻光标的一个 Unicode 标量，不保存或记录宿主文字；中文/日文键帽显示值会先映射回 Engine 的 ASCII 标点输入，缺失上下文安全回退到 Engine 标点。

表情浏览器以远端默认分支固定来源 `MSIME-Apple@7de60fb5c5590f33e7f515db7e595a1d7e848ad1` 为交互基线，在空闲候选工具栏和“更多”面板提供入口，按 Unicode 固定顺序显示最近、笑脸、人物、动物、食物、旅行、活动、物品、符号和旗帜，每行八项，支持删除和返回。为适配共享客户端架构，iOS 不复制 Apple 扩展内的 SQLite 读取器，而是在串行后台队列通过共享 C ABI 分页读取已验证 `others.db`；每页、游标、文本和注释均有边界校验，过期分类结果不会覆盖当前页。选择后通过正常 `UITextDocumentProxy` 路径插入并记录最多 24 项的去重最近使用；打开面板前先由 Engine 完成已有组合，不保存或记录编辑器上下文。

## 开发构建

先初始化固定的 Engine gitlink 与递归子模块，并准备包含 iOS 版 Boost 的依赖前缀：

```sh
git submodule update --init --recursive
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

词库必须来自仓库固定的 `resources/desktop-dictionary.lock.json`。安装器下载并校验发布文件，暂存脚本再次检查名称、长度与 SHA-256，只把允许的六个运行资源复制到 `target/ios/EngineResources`：

```sh
resource_dir="$(cargo run --quiet -p msime-client-core --example install_resources -- target/resources)"
platforms/ios/stage-resources.sh "$resource_dir"
```

只构建 Rust/C++ 宿主库时运行：

```sh
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  platforms/ios/build-native.sh simulator
```

`device` 目标产出 `target/ios/device/libmsime_host_api.a`，`simulator` 目标产出 arm64 的 `target/ios/simulator/libmsime_host_api.a`。脚本会自动识别依赖前缀下唯一的版本化 `BoostConfig.cmake` 与 `boost_headers-config.cmake`；有多个版本时，分别用 `MSIME_BOOST_DIR` 和 `MSIME_BOOST_HEADERS_DIR` 指向对应配置目录。

一条命令完成资源暂存、native 构建、XcodeGen 工程刷新和无签名 arm64 构建：

```sh
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  platforms/ios/build-app.sh "$resource_dir" simulator
```

真机产物把最后一个参数改为 `device`。无签名构建只验证源码、链接和 bundle 内容，不代表键盘扩展已经安装、授权或完成真机宿主验证。
