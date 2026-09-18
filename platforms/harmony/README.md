# HarmonyOS 输入宿主预览

OpenHarmony 适配保留 ArkTS/ArkUI 应用入口与 NAPI 原生边界。共享输入算法、组合状态、配置校验和资源准备继续由 Rust Host API 与 C++ Engine 提供；`platforms/harmony/native/client_napi.cpp` 只负责 NAPI 注册和 C ABI 转发，不复制候选分页或输入状态机。

## 目录结构

- `entry/src/`：ArkTS 应用与键盘宿主源码。
- `native/`：NAPI/C++ 适配层。
- `tests/`：不依赖设备的 TypeScript 键盘逻辑测试。
- `AppScope/`、`entry/src/main/resources/`：应用元数据和资源。
- `build-native.sh`、`stage-resources.sh`：共享 Host API、NAPI 库和固定资源的构建/暂存入口。

## 本地构建

准备 DevEco Studio 提供的 OpenHarmony NDK，或设置 `MSIME_OHOS_NDK` 指向包含 `build/cmake/ohos.toolchain.cmake` 的 NDK。先安装依赖（根目录 `pnpm install --frozen-lockfile`），准备对应 Rust target、目标 ABI 的 SQLite 前缀和 Boost/fmt/spdlog CMake 配置目录。非 Homebrew 布局需显式设置 `MSIME_BOOST_DIR`、`MSIME_BOOST_HEADERS_DIR`、`MSIME_FMT_DIR` 和 `MSIME_SPDLOG_DIR`，再运行：

```sh
resource_dir="$(cargo run --quiet -p msime-client-core --example install_resources --locked -- target/resources)"
bash platforms/harmony/stage-resources.sh "$resource_dir"
MSIME_OHOS_NDK=/absolute/openharmony/native \
MSIME_OHOS_DEPS=/absolute/ohos-deps/arm64-v8a \
bash platforms/harmony/build-native.sh arm64-v8a
cd platforms/harmony
# 使用 DevEco SDK 配套且已加入 PATH 的 hvigorw
hvigorw assembleHap
```

支持 `arm64-v8a`、`armeabi-v7a` 和 `x86_64`。原生库暂存到 `entry/libs/<abi>/`，这些目录是构建产物，不提交到仓库。资源准备仍使用根目录固定的 `resources/desktop-dictionary.lock.json`，不得把本机路径、凭据或用户输入放入 HAP。

## 验证边界

不依赖设备的逻辑回归：

```sh
bash platforms/harmony/tests/run.sh
```

该命令编译并运行 `tests/keyboard-logic.test.ts`。`build-native.sh` 只证明指定 OpenHarmony NDK 下的 Rust/C++/NAPI 交叉构建和 ELF 导出检查；`hvigorw assembleHap` 只证明 HAP 打包。当前没有 HarmonyOS 真机或模拟器运行证据，未完成系统输入法注册、焦点/选区、生命周期、签名和设备编辑器验收，因此不能把交叉构建描述为平台接入完成。
