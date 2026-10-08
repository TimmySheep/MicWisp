# 桌面客户端前置技术核查与实施计划

> 日期：2026-10-08  
> 范围：桌面客户端（macOS + Windows）；只读核查上游，不修改上游源码。  
> 依据：仓库 `TASK.md`、`AGENTS.md`、`PROTOCOL.md` 及本地只读参考 `upstream-micyou/`。

## 1. 前置问题结论

### 1.1 配置是否热加载

**连接配置不热加载，修改后需重启服务。** `micyou-cli serve` 调用 `StartRequest::resolve` 时读取 `server.json` 并解析端口、模式、绑定地址和输出设备；`start_server` 按解析后的请求创建监听器。`micyou-cli server set` 只保存共享配置，不会通知或重配运行中的服务。

**DSP 设置也没有可由 CLI 调用的运行中控制接口。** `micyou-cli settings set` / `chain set` 只读改写 `settings.json`。运行服务的 DSP 状态保存在进程内 `ServerState`；设置文件变化本身不会更新该状态。GUI 则通过 `Controls::apply_dsp_settings` 持久化并立即应用。故当前仅用 CLI sidecar 时，DSP 配置改动需重启服务才能可靠生效；UI 不得把文件写入成功误报成运行时已应用。

**建议接口行为：** 控制通道提供运行时 `applySettings`，由后端走现有 controls 路径验证、持久化和更新；连接级设置变化则明确要求重启，并由 UI 提供可见的“重启服务以应用”状态。

证据：`upstream-micyou/tauri-app/crates/micyou-cli/src/serve.rs`、`commands.rs`；`micyou-core/src/server/service.rs`（`StartRequest::resolve`、`start_server`）；`micyou-core/src/settings.rs`（`apply_dsp_settings`）。

### 1.2 `ServerEvents` 完整事件清单

`micyou_core::events::ServerEvents` 共 13 个回调。建议 JSON 协议以稳定事件名及下列字段为准，结构体字段使用 camelCase；无字段事件传空对象。

| 事件 | 字段 |
|---|---|
| `device_connected` | `name: string`, `ip: string`, `latency: u32`（`DeviceInfo`） |
| `device_disconnected` | 无 |
| `audio_metrics` | `bitrate: i32`, `sampleRate: i32`, `latencyMs: i64`, `networkLatencyMs: i64`, `packetLossRate: f64`, `jitterMs: f64`, `bufferDurationMs: i64`（`AudioMetrics`） |
| `udp_audio_warning` | 无 |
| `mute_state_changed` | `isMuted: bool` |
| `audio_level` | `level: u32` |
| `audio_spectrum` | `raw: number[]`, `processed: number[]`（f32 数组） |
| `server_stopped` | 无 |
| `web_client_count` | `count: u32` |
| `install_progress` | `message: string` |
| `aec_status_changed` | `available: bool`, `enabled: bool`, `reason: AecFailure?`；原因代码：`inference_failed`、`model_load_failed`、`model_missing`、`pipewire_unavailable`、`reference_lost`、`virtual_source_missing` |
| `monitoring_state_changed` | `enabled: bool` |
| `plugin_download_progress` | `id: string`, `downloaded: u64`, `total: u64`, `done: bool` |

当前 CLI 文本 sink **不是完整事件接口**：它不输出频谱；AEC 只输出部分摘要；插件下载只在完成时输出；`--quiet` 还会抑制音频电平和每秒网络指标。因此不应解析现有 stdout 文本作为产品协议。高频 `audio_level` / `audio_spectrum` 需要协议定义节流/采样策略，不能无限制写盘或让 UI 主线程消费。

证据：`micyou-core/src/events.rs`、`stats.rs`、`transport/tcp.rs`；`micyou-audio/src/aec.rs`；`micyou-cli/src/events.rs`。

### 1.3 控制通道设计

**推荐：由桌面应用启动并独占管理 CLI 子进程，通过 stdin/stdout 建立双向、版本化 JSON Lines 通道；不解析人类可读日志，也不开放本地 TCP 控制端口。**

- stdout 仅承载 JSON 行；普通日志及诊断写 stderr，避免混流。
- 启动后先收 `ready`（或结构化 `error`）；事件采用 `{ "v": 1, "type": "event", "name": ..., "payload": ... }` 信封。
- stdin 接收有请求 ID 的命令及响应：至少覆盖停止服务、静音、监听、获取/应用 DSP 设置、频谱开关；按需覆盖安装/插件操作。命令值必须校验，未知版本/命令返回结构化错误。
- 父进程关闭 stdin、进程崩溃、协议版本不匹配和启动失败都要有明确状态；有界队列/节流高频事件。子进程退出后由 UI 明确呈现并允许重启，不自动无限重试。
- 此能力**当前上游 CLI 尚不存在**。交付时需在 `core/` 维护一个清晰、可复现且 GPL 合规的上游补丁集，或在有可用上游版本前明确标记依赖；不要把上游 `.rs` 源码直接复制进此仓库，也不要通过 stdout 文本猜事件。

选择理由：单向 JSON 事件输出只能满足遥测，无法满足运行时静音、监听及 DSP 修改等控制要求；stdin/stdout 限定在应用直接持有的子进程上，避免新增监听面和认证复杂度。实现前需验证 CLI 的 async 生命周期可以同时处理 stdin 命令与 Ctrl+C，并确认平台子进程管道关闭/退出行为。

### 1.4 `mode_lock` 约束

GUI、CLI、TUI 共享 `mode.lock`，任一存活进程持锁时其他模式不能启动。MicDesk 必须把其 CLI sidecar 作为唯一后端实例，不可同时启动或接管另一份服务。已有官方 GUI/TUI/CLI 占锁时，向用户解释冲突并引导关闭占用方；不得强杀进程或删除锁文件。CLI `status` 可用于辅助诊断，但锁文件记录的只有 mode、PID、启动时间，不能单靠模式名断定持锁进程就是本应用。后端正常退出后才允许 UI 重新启动 sidecar。

另外，`mode_lock` 是服务互斥机制，不是桌面客户端的单实例锁；MicDesk 自身仍需避免用户重复启动带来多个 UI 同时争用 sidecar。

证据：`micyou-core/src/mode_lock.rs`（互斥、PID 存活及 stale lock 行为）；`micyou-cli/src/serve.rs`（启动前 acquire、退出后 release）。

## 2. 分阶段实施计划（可验收里程碑）

1. **P0 前置设计（本阶段）**：完成上述配置语义、事件清单、控制通道与互斥机制核查；把文档提交为本文件。验收：四项结论完整，未改上游和 iOS 文件。
2. **P1 集成协议与后端可复现性**：确定上游补丁维护/分发方式；实现并测试 JSONL 双向控制协议、所有事件映射、配置应用语义、进程生命周期与锁冲突错误；确认 CLI 可在 macOS/Windows 取得并运行。验收：自动化协议测试通过，事件/命令覆盖表完整，CLI 进程启动、控制、停止均可验证。
3. **P2 macOS 完整客户端**：Swift 6 / SwiftUI 原生实现连接与设备发现、手动 IP、Wi-Fi/USB/Web、状态与音频指标、DSP/音频设备设置、静音/监听、菜单栏、自启、中英双语、关于与 GPL notices；集中定义产品名 `MicDesk` 和 Bundle ID `com.timmysheep.micdesk`。验收：macOS 构建通过；与后端端到端连接及虚拟音频输出实测；逐项验证功能清单。
4. **P3 Windows 完整客户端**：WinUI 3 / C# 原生实现与 macOS 功能等价的完整 UI 和 sidecar 生命周期，支持系统托盘、自启、双语、关于与 GPL notices；提供可复现构建说明。验收：Windows 环境真实构建及端到端验收；若无 Windows/.NET SDK 环境，则明确“未构建验证”，不改动用户机器。
5. **P4 跨平台回归与交付**：检查命名、Bundle/Package 标识、GPL 许可与上游补丁标注/对应源码，完成 README 构建/验证步骤、功能验收矩阵和回归；报告实测结果及未验证边界。

## 3. 边界和当前状态

- 本次只读核查上游；未复制或修改 `upstream-micyou/`、`MicYou-iOS/` 的代码。
- 桌面实现阶段仅允许写 `apps/macos/`、`apps/windows/`、`core/` 及新增 `docs/DESKTOP-*.md`；iOS 线文件保持只读。
- 本文是架构/协议设计结论，不代表 JSONL 通道或任一客户端已实现/构建/端到端验证。
