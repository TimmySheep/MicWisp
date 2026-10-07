# AGENTS.md — 项目规则

本仓库是 Timmy 的原生客户端项目：为 MicYou 无线麦克风协议编写**平台原生客户端**。

**本仓库同时存在两条工作线，开工前先确认自己属于哪条：**

| 工作线 | 范围 | 任务书 |
|---|---|---|
| **iOS 客户端（iPhone + iPad）** | `Sources/`、`Tests/`、`MicYou.xcodeproj/`、Live Activity、Widget | `docs/PRODUCT_SCOPE.md` |
| **桌面客户端（macOS + Windows）** | `apps/macos/`、`apps/windows/` | **`TASK.md`** |

## 共享红线（两条工作线都适用）

1. **绝不复制上游 GPL 代码进本项目。**
   - `upstream-micyou/`、`MicYou-iOS/` 是只读参考，已被 `.gitignore` 排除。
   - 允许：阅读上游代码理解协议与行为、参考事件类型定义。
   - 禁止：把上游 `.rs` / `.kt` / `.m` / `.swift` / `.proto` 代码复制进本项目源码。
   - 协议事实（字段号、magic、握手串、端口）是接口事实，可自由实现。
   - 以 `PROTOCOL.md`（真实协议，源码已验证）为唯一协议基线。
   - **注意**：`MicYou-iOS/`（官方脚手架）的协议与真实桌面端**不互通**，
     不要参考它的协议实现，只可参考其功能意图。

2. **禁止 webview / Electron / 网页套壳。** 必须使用平台原生框架。

3. **产品名已定 `MicWisp`**（**仅英文名，不使用中文名**），桌面线与 iOS 线统一使用。
   集中定义在**单一位置**，便于日后一行改名。
   - **不得**使用 `MicYou` 作为产品名——GPL 不授予商标权。
   - 可以说「兼容 MicYou 协议」「MicYou 的第三方独立客户端」；
     不要说「变体」「官方版」等暗示隶属关系的词；不要用 MicYou 的 logo/字体/配色。
   - **不得**暗示本应用是官方 MicYou。

4. **许可分层（不要混为一谈）——详见 `docs/LICENSING.md`**：
   - **桌面线（`apps/`、`core/`）：GPL-3.0**。必须保留上游版权声明与完整许可文本；
     若修改上游源码，须显著标注修改及日期（§5a）、整体 GPL 授权（§5c）、
     界面显示 Appropriate Legal Notices（§5d）、提供完整对应源码（§6）。
   - **iOS / iPadOS 线（`Sources/`、`Tests/`、Xcode 工程）：MIT。**
     **不得标为 GPL**——GPL 与 App Store 的 DRM／设备限制存在已知冲突
     （先例：2011 年 VLC iOS 版撤架、2010 年 GNU Go 下架），会引入下架风险。
     iOS 端是独立实现、自有作品，有权自选许可。
   - **任何组件都不得删除原作者版权声明。**
   - 若新引入的依赖或组件造成许可冲突（如把 GPL 库引入 MIT 部分），**先停下报告**。

5. **不要擅自改动用户的机器。** 尤其：
   - 不要修改用户的 Windows 电脑，不要在那里安装软件或远程执行命令。
   - 不要在未获批准前改动系统配置、网络设置或删除文件。

6. **不谎报完成。** 构建失败就说失败；未验证就明确标注"未构建验证"。
   模拟器/本机编译成功不能替代实机与真实桌面端验收。

7. **上游补丁与 PR（桌面线）——详见 `docs/UPSTREAM-PATCH-AND-PR.md`。**
   - 补丁要**最小**：只动 `tauri-app/crates/micyou-cli/`，仅在必要时碰 `micyou-core`。
   - **不得**改动 `micyou-protocol/`（会破坏与官方客户端的互通）。
   - **两条路都要走**：先做本地可用补丁（路径 B 的基础）→ 再提 PR 到上游 `master`（路径 A）。
     **一份补丁服务两条路，不要做两遍。**
   - ⚠️ **PR 中不得出现 `MicWisp` 品牌、产品链接、打赏链接或任何推广内容**——
     那是纯技术贡献。动机可客观描述，维护者追问时如实回答，但**不推销、不攀附官方**。
   - 提交信息与 PR 标题用 **Conventional Commits**（上游硬性要求）。
   - PR 前必须本地通过：`cargo build -p micyou-cli` 与 `cd tauri-app && bun run build`。

## 并行工作纪律（重要）

两条工作线可能在**同一时间**被不同 agent 会话编辑。因此：

- **只改自己范围内的文件。** 桌面线只写 `apps/macos/`、`apps/windows/`、
  `core/` 与自己新增的文档。
- `Sources/MicYouCore/`（Swift 协议核心）由 iOS 线维护：**桌面线视为只读共享代码**，
  如需改动，先在会话中明确说明理由，不要静默重写。
- 不要触碰 `MicYou.xcodeproj/`、`Tests/`、`docs/PRODUCT_SCOPE.md`（iOS 线所有）。
- 需要新文档时，用带前缀的名字（如 `docs/DESKTOP-*.md`）避免冲突。

## 技术约定

- **macOS**：Swift 6 / SwiftUI，优先 SwiftPM 或标准 Xcode 工程。
- **Windows**：WinUI 3 / C#（本机无 .NET SDK，构建验证可能需在 Windows 上进行）。
- **iOS / iPadOS：必须是 Universal App（iPhone + iPad 同时支持，单一 target，不是 iPhone-only）。**
  - iPad 要有适配大屏的布局（SwiftUI 自适应：`NavigationSplitView`、size classes），
    **不能只是把 iPhone 界面拉伸**。
  - 支持 iPadOS 多任务（Split View / Slide Over）与横竖屏。
  - Info.plist 的 `UIDeviceFamily` 必须包含 2（iPad），不要只声明 iPhone。
  - Live Activity / 灵动岛是 iPhone 特性；iPad 没有灵动岛，相关代码必须用
    `#if os(iOS)` + 设备判断做条件处理，**不能因为 iPad 不支持就让构建失败**。
  - iPad 也应有对应的 Widget / 大屏信息展示形态，而不是功能缺一块。
- **音频后端**：复用上游 `micyou-cli serve`，不要自己实现虚拟音频设备
  （上游已实现 BlackHole / VB-CABLE / PipeWire）。
- **协议**：真实协议见 `PROTOCOL.md`（magic `0x4D696359`、握手 `MicYouCheck1/2`、TCP 8554 / UDP 8555）。
- **控制通道**：上游 CLI 目前输出人类可读文本，需先设计结构化方案
  （见 `TASK.md` 第 4 节与 `docs/DESKTOP-PREWORK.md`）；
  实现方式与双路交付要求见 **`docs/UPSTREAM-PATCH-AND-PR.md`**。

## 工作方式

- **先读**：对应的任务书 → 本文件 → `docs/` 相关文档 → 再动手。
- **先解决任务书列出的前置技术问题**，结论写入 `docs/`。
- **先出实施计划**，再逐步实现；每阶段有可验证产出。
- 重要决策追加到 `docs/DECISIONS.md`。
- 提交信息用 `feat:` / `fix:` / `docs:` / `chore:` 前缀。

## 已知坑（已核实，不要再踩）

- 官方 `MicYou-iOS` 脚手架协议与真实桌面端不互通（magic `iOST`/端口 8900）——勿参考。
- 上游桌面端 `externalBin` 同时打包 `micyou-cli` 与 `micyou-tui`，核心被打包三遍；
  我们只用一个后端，这是"轻量"的机会点。
- `mode_lock`（`RunMode::Cli` / `RunMode::Gui`）：官方 GUI 与 CLI **互斥**运行。
- 上游 `AVAudioSessionModeVoiceCommunication` 不存在，正确常量是 `AVAudioSessionModeVoiceChat`。
- Opus 采样率仅支持 8/12/16/24/48 kHz；44.1 kHz 需映射到 48 kHz（若用 Opus）。
- **PCM（codec=0）服务端完全支持**，首版可不实现 Opus。
- 服务端 `decode()` 对 PCM 与 Opus 都有分支，PCM 不是废弃路径。
