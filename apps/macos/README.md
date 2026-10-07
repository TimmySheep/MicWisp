# MicWisp for macOS

原生 Swift 6 / SwiftUI 客户端，无 WebView、Electron 或网页套壳。应用只管理桌面接收端；协议、网络服务、DSP 与虚拟音频设备由单独构建的上游 `micyou-cli` sidecar 提供。

## 功能

- Wi-Fi、USB/ADB、Web 三种服务模式；mDNS 服务发现、手动监听 IP/端口配置，并显示可提供给手机端使用的本机 IPv4 地址。
- 实时连接设备、电平、频谱、延迟、抖动、丢包、缓冲、码率、采样率和 Web 客户端状态。
- 静音与本机监听控制；完整 DSP 参数、10 段 EQ 和处理链顺序。
- BlackHole 输出状态/安装提示、菜单栏入口、macOS 登录时启动、简体中文/英文、关于与 GPL legal notices。
- 隐私边界：登录启动只打开应用界面；麦克风服务只在用户显式点击“启动”后运行，应用不会自动取消静音。

## 构建

依赖仅为 Xcode/Swift 工具链和系统框架（SwiftUI、Network、ServiceManagement），不使用第三方 Swift 包。

```sh
cd apps/macos
swift build
```

当前本机验证：`swift build` 成功（Apple Swift 6.4，macOS 27 SDK）。这只验证原生 UI 编译，不代表 sidecar 已构建、真实设备连接或音频端到端已验证。

### 构建与打包后端

遵循 [`../../core/BUILD.md`](../../core/BUILD.md)，在独立可写的上游 checkout 上应用固定补丁、运行 `cargo test -p micyou-cli` 和 `cargo build -p micyou-cli --release`。不要修改本仓库只读的 `upstream-micyou/`。

提供已构建且可执行的 patched CLI 后，可打包 macOS `.app`：

```sh
MICWISP_CLI_PATH=/absolute/path/to/micyou-cli sh apps/macos/Scripts/package-app.sh
```

打包器从唯一的 `Info.plist` 读取展示名和 Bundle ID，将 sidecar 放进 `Contents/Helpers/`，并把本地化资源、完整 GPL-3.0 文本及上游许可/Plugin Exception 放入应用资源包。未设置 `MICWISP_CLI_PATH` 或 sidecar 不可执行时会停止，不会生成缺少后端的“完整应用”。当前 JSONL 补丁尚未在独立可写 checkout 上构建，因此打包和端到端状态仍未验证。

## 运行与验收

1. 首次运行时，在“连接”中选择模式、端口、监听地址和输出设备，点“保存并应用”。连接设置持久化到上游共享的 `server.json`；运行中的变更会按提示重启 sidecar。
2. 回到概览，用户显式点击“启动接收服务”。USB 模式需在手机启用 USB 调试，并在本机安装/配置 ADB。
3. 在连接页检查 BlackHole。未检测到时应用只提供安装说明，不自动下载/安装驱动。
4. 检查连接、所有音频/网络指标、静音、本机监听、DSP 应用、Web 模式客户端数量、菜单栏停止/退出和登录项设置。
5. 关于页验证独立第三方声明、双方版权、无担保说明、GPL 再分发提示及许可文本可打开。

遇到另一个 GUI/CLI/TUI 持有 `mode_lock` 时，应用展示后端错误；请用户自行关闭占用端。应用不强杀别的进程，也不删除锁文件。若 sidecar 管道关闭或协议异常，状态需明确变为失败；不得显示旧连接状态为当前成功状态。

真实手机、真实上游桌面服务、虚拟麦克风输出和分发签名/公证尚未验收，不能以本地 Swift 编译通过替代。
