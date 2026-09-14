# iOS App 与键盘扩展

`MSIMEClient.xcodeproj` 包含设置 App、`UIInputViewController` 键盘扩展和共享 Swift 适配层。输入算法与组合状态仍由 C++ Engine 管理；扩展只负责宿主事件、候选展示和文本提交。语音录制由 App 的 Swift `AVAudioEngine` 宿主管理，键盘扩展不直接使用桌面音频采集桥接。

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
