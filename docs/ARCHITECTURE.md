# 桌面端架构分析与重写方案

> 基于 MicYou 主仓库只读核验（2026-10-08）。用于判断"原生重写"的真实成本。

## 1. 桌面端到底是什么

| 层 | 技术 | 是否原生 |
|---|---|---|
| UI 层 | **Vue 3 + Vite + Tailwind**，跑在 Tauri 的系统 webview 里 | ❌ 网页 |
| 应用壳 | **Tauri 2**（Rust） | ✅ |
| 核心 | **Rust**：`micyou-core` / `micyou-protocol` / `micyou-audio` / `micyou-plugin` | ✅ 原生 |

**结论：桌面端不是"移植的"，它是独立的 Rust 实现；"不原生"只体现在 UI 层。**
重量感来自捆绑 webview 与前端资源，而不是核心。

## 2. 核心已经包含所有难点

`micyou-core` 里已实现（**重写就等于全部重做**）：

- 传输：TCP/UDP、FEC 前向纠错、抖动缓冲、会话管理
- 协议：Protobuf 编解码（`micyou-protocol`）
- 音频：Opus 编解码、重采样、DSP 链
- **虚拟音频设备集成**（最难的平台相关部分）：
  - `platform/blackhole.rs` — macOS（BlackHole）
  - `platform/vbcable.rs` — Windows（VB-CABLE）
  - `platform/pipewire.rs` — Linux
- 插件宿主：Native（cdylib）+ WASM 双运行时

## 3. 已有三种前端

| 前端 | 形态 | 说明 |
|---|---|---|
| GUI | Vue webview | 现有桌面端 |
| CLI | `micyou-cli`，含 `serve` 子命令 | **可无头运行音频服务** |
| TUI | `micyou-tui` | 终端仪表盘 |

CLI/TUI 作为 sidecar 打包。`micyou-cli serve` 以前台方式运行音频服务，
读取共享的 `server.json`，事件以文本行输出到 stdout。
`micyou-core::host::headless::HeadlessHost` 是无头宿主实现。

**架构上已经支持"多前端 + 单核心"**——加一个原生 GUI 是顺着架构走，不是对抗它。

## 4. 核心没有暴露 C ABI

`crates/*/Cargo.toml` 里**没有 `crate-type = ["cdylib"]`/`["staticlib"]`**。
唯一的 `extern "C"` 是插件系统（加载原生插件 cdylib），不是核心对外的 API。

→ 若要让 Swift / C# 直接调用核心，**需要自己写 FFI 层**（UniFFI 是 Rust↔Swift/C# 的惯用选择）。

## 5. 三条路线

### 路线 A：原生 UI + 复用 Rust 核心（FFI）
- **保留**全部难点（虚拟音频设备、DSP、协议）。
- 自写 FFI 层（UniFFI）把核心暴露给 SwiftUI / WinUI。
- 上游同步：保留其核心代码，可正常 merge。
- 成本：中高，但避开了杀手级难点。

### 路线 B：原生 UI + 打包现有 CLI 作无头后端（sidecar）⭐ 推荐先做
- 原生 UI 产出 `server.json` + 启动 `micyou-cli serve`，读取事件。
- **最轻**：不写 FFI，不重写核心，不碰虚拟音频设备。
- 上游同步：替换二进制即可，最省心。
- 缺口：CLI 事件目前是**人类可读文本**，不是结构化输出 → 需要一个 JSON 事件模式
  （小而增量、上游友好的改动，适合作为 PR 提交）。

### 路线 C：完全原生重写（Swift + C#）
- 需重做传输、Protobuf、DSP、**以及虚拟音频设备**。
- Windows 侧 = 内核态音频驱动 + EV 证书 + 微软签名 → 不属于常规 App 工程。
- 上游同步：语言不同，**没有代码可 merge**，只能手工跟协议。
- 成本：极高，收益最低。

## 6. 结论

**要改的是 UI 层，不是 MicYou 本身。** 核心已经是原生 Rust，且含全部难点。

推荐顺序：**路线 B →（若需要深度控制）路线 A**。路线 C 不建议。

## 7. 独立仓库与上游同步的现实

- **可以独立建仓**：GPL 允许 Fork 与再分发，**无需原作者同意**。
- **义务**：继续以 GPL-3.0 分发、提供源码、保留版权声明、不得暗示为官方版本。
- **商标**：GPLv3 §7(e) 明确**不授予商标权**。**不要用 "MicYou" 作为你的产品名**，
  也不要让用户误以为它是官方版本。
- **同步的真相**：
  - 保留其代码（路线 A/B）→ 可以真正 git merge 上游更新。
  - 从零重写（路线 C）→ 不同语言，**无代码可同步**，只能手工跟踪协议变更。
- **更可能被接受的 PR**：不是"一整个新 UI"，而是**小的赋能性改动**
  （如给 CLI 加 `--json` 事件输出）。这既解决你的需要，也利于其他原生前端。

## 8. 待确认

1. CLI 事件改 JSON 的具体设计（需读 `micyou_core::events::ServerEvents` 全量事件类型）。
2. `server.json` 的完整字段（配置面）。
3. macOS 上 BlackHole 是否需要用户另行安装（影响分发说明）。
