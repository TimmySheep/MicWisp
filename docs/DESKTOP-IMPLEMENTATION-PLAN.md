# 桌面客户端实施计划与 P0 核查结论

> 日期：2026-10-08  
> 工作线：macOS + Windows 桌面客户端  
> 产品命名：遵循当前 `TASK.md` / `AGENTS.md`，产品名 `MicWisp`；Bundle ID `com.timmysheep.micwisp`。  
> 依据：`TASK.md`、`AGENTS.md`、`PROTOCOL.md`、`docs/DESKTOP-PREWORK.md` 与只读上游源码。

## 1. 第 4 节前置问题核查

### 配置热加载

- 连接配置（端口、模式、绑定地址、输出设备）由 `StartRequest::resolve` 在启动时读取共享 `server.json`；保存配置不会重配正在运行的服务。更改后必须提示并重启服务。
- `settings set` / `chain set` 只改写 DSP 配置文件。运行时 DSP 必须通过 `ServerState::controls().apply_dsp_settings` 校验、持久化并应用；不能把仅写文件显示为已生效。
- 上游证据：`tauri-app/crates/micyou-core/src/server/service.rs`、`config.rs`、`settings.rs`；CLI 的配置命令在 `tauri-app/crates/micyou-cli/src/commands.rs`。

### 服务端事件

`ServerEvents` 有 13 个回调，JSON 名称及 payload 使用 camelCase：

| 名称 | payload |
|---|---|
| `device_connected` | `{name, ip, latency}` |
| `device_disconnected` | `{}` |
| `audio_metrics` | `{bitrate, sampleRate, latencyMs, networkLatencyMs, packetLossRate, jitterMs, bufferDurationMs}` |
| `udp_audio_warning` | `{}` |
| `mute_state_changed` | `{isMuted}` |
| `audio_level` | `{level}` |
| `audio_spectrum` | `{raw, processed}` |
| `server_stopped` | `{}` |
| `web_client_count` | `{count}` |
| `install_progress` | `{message}` |
| `aec_status_changed` | `{available, enabled, reason}` |
| `monitoring_state_changed` | `{enabled}` |
| `plugin_download_progress` | `{id, downloaded, total, done}` |

当前 `CliEventSink` 对频谱不输出，AEC 仅输出摘要，插件下载只输出完成项；quiet 模式还会隐藏电平和网络指标。现有文本 stdout 不是完整、稳定的接口，禁止从自然语言日志解析产品状态。

### 控制通道

上游当前 `micyou-cli serve` 只在 stdout 打印启动/事件文本，并等待 Ctrl+C；它未监听 stdin 命令，也未提供运行时静音、监听、DSP 设置、频谱开关的 CLI 命令。`micyou-core` 内存在对应运行时控制 API，但 CLI 没有接线。因此 P1 必须为上游 CLI 维护可复现的 GPL 合规补丁，不能把 JSONL 能力说成上游现成功能。

接口约定：应用独占启动 sidecar，通过 stdin/stdout 使用本地双向 JSON Lines，不开本地 TCP 控制端口；stdout 只传协议，日志/诊断转 stderr。每行均带 `v: 1`，启动先发送 `ready`；事件采用 `{v,type:"event",name,payload}`；命令含唯一请求 `id`，至少支持 graceful stop、静音、监听、读取/应用 DSP 设置、频谱开关，以及读取/保存连接设置。响应回显 `id` 并带成功结果或结构化错误。连接设置仅保存并返回 `requiresRestart: true`，DSP 则走核心运行时 API。

实现必须限制单行长度、校验版本/命令/字段，不接受 shell 字符串；高频电平/频谱使用有界队列与节流/合并，避免阻塞音频回调。stdin EOF、stop、Ctrl+C 都应进入同一有界清理路径，关闭服务后释放锁；启动失败与冲突需有可读结构化错误及非零退出状态。协议不无限重试、不混入 stdout 文本。

### `mode_lock`

上游 GUI、CLI、TUI 共享 `mode.lock`，存活持锁进程会阻止新 CLI sidecar 启动。桌面端必须将 sidecar 视为唯一后端实例，遇到冲突时报告并指导用户关闭占用方；不得强杀占用进程或删除锁文件。`mode_lock` 不保证原生 UI 自身单实例，应用还需使用平台单实例机制。

## 2. 分阶段实施计划与验收

### P1 — 控制层与上游补丁

- 维护独立补丁集/应用说明，不修改只读 `upstream-micyou/`；补丁保留上游版权声明和许可证，显著标注修改日期，并说明获取完整对应源码的方法。
- 实现版本化 JSONL 双向通道、13 类事件、命令/响应、配置语义、输出隔离、节流/有界队列、优雅关闭与锁冲突处理。
- 为 JSON 编解码、未知版本/命令、超限输入、错误回包、EOF 关闭及事件映射编写自动化测试。
- **验收**：补丁可应用到注明的上游版本；测试通过；端到端启动、控制、停止可观察。未经实际构建/运行不得标为通过。

### P2 — macOS 原生客户端

- Swift 6 / SwiftUI；实现 Wi-Fi、USB/ADB、Web 模式，mDNS 发现与手动配置，运行状态和所有指标，DSP 全部设置、输出设备提示、静音/监听、菜单栏、登录时启动 UI、中英文、关于页和 GPL notices。**登录启动仅打开 UI，不自动启动服务；服务必须经用户显式点击启动。**
- 由统一配置点定义产品名与 Bundle ID；实现 sidecar 定位/启动/管道管理、异常状态处理及 macOS 单实例。
- **验收**：`xcodebuild` 或等效可复现构建通过；测试 JSONL 状态/控制；真实设备与虚拟音频端到端验收单列，不以编译通过替代。

### P3 — Windows 原生客户端

- WinUI 3 / C# 实现与 macOS 功能等价的设置、状态、进程管理与 JSONL、系统托盘、自启、中英文和法务页。
- 提供完整可复现 Windows 构建、打包、运行、验证说明；不在用户 Windows 设备安装软件或执行命令。
- **验收**：Windows 环境构建与端到端验证；若本机工具链不具备，明确标记“未构建验证”。当前核实本机 `dotnet` 不存在。

### P4 — 交付回归

- 对照 `TASK.md` 第 5.2 节逐项验收；核对统一命名、Bundle/Package 标识、GPL 与第三方独立声明、构建/验证说明、补丁对应源码说明。
- 检查工作范围只包含 `apps/macos/`、`apps/windows/`、`core/` 与新增 `docs/DESKTOP-*.md`，不覆盖 iOS 工作线文件。

## 3. 当前核验状态与限制

- P0 结论已完成并落盘；本文件补充记录实施接口和执行验收条件。
- 当前工作区已有其他会话的 README、`docs/PRODUCT_SCOPE.md`、`Config/`、`MicYou.xcodeproj/`、`Sources/` 变更；这些文件不属于桌面线，本任务保持不动。
- macOS 工具链可见：Swift 6.4、Xcode build tools、Cargo 1.97.1。`dotnet` 不存在，Windows 构建无法在当前本机完成。
- 本文是核查与计划，不代表控制通道、客户端、构建或真实音频链路已经实现/验证。
