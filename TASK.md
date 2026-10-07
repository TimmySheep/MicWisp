# 任务书：原生桌面客户端（macOS + Windows）

> 状态：**待执行**
> 目标：完整实现，**不是 MVP**。
> 指定模型：`openai/gpt-6-luna`
> 工作目录：本仓库根目录（`micyou-ios-study/`）

---

## 1. 任务目标

为 MicYou 的无线麦克风协议，**各写一套完整的原生桌面客户端**：

- **macOS**：Swift / SwiftUI 原生应用
- **Windows**：原生应用（WinUI 3 / C# 优先）

**硬性要求：**
- **禁止** Electron、**禁止**网页套壳、**禁止**嵌入 webview
- 必须是真正的平台原生框架
- **完整实现全部功能**，不做精简 MVP

## 2. 架构：路线 B（核心复用 + 原生 UI）

**不重写核心。** 复用上游 MicYou 的 Rust 核心，以无头方式驱动：

```
[原生 UI (SwiftUI / WinUI3)]
        │  控制通道（见第 4 节，需先设计）
        ▼
[上游 micyou-cli serve]  ← 复用，负责传输/协议/DSP/虚拟音频设备
        ▲
        │ MicYou 协议 (TCP 8554 / UDP 8555, Protobuf)
        │
[手机端 MicYou 客户端 / Android]
```

上游核心**已经包含**全部难点：TCP/UDP 传输、Protobuf、Opus、FEC、抖动缓冲、
DSP 链（降噪/AEC/去混响/EQ/AGC/VAD）、以及虚拟音频设备集成
（macOS BlackHole、Windows VB-CABLE、Linux PipeWire）。**不要重写这些。**

## 3. 必须阅读的文档（本仓库内）

| 文件 | 内容 |
|---|---|
| `docs/ARCHITECTURE.md` | 桌面端架构、三条路线对比、为什么选 B |
| `PROTOCOL.md` | 真实协议规格（已用源码验证） |
| `docs/SIZE-MEASUREMENT.md` | 体积实测与构成 |
| `docs/UI-SCOPE.md` | UI 规模实测与功能面清单 |
| `docs/DECISIONS.md` | 已定决策（D001–D005） |
| `docs/competitors.md` | 竞品与协议不互通发现 |

上游源码参考（只读）：
- `upstream-micyou/` — MicYou 主仓库（含 Rust 核心与 Android 客户端）
- `MicYou-iOS/` — 官方 iOS 脚手架（注意：**其协议与真实桌面端不互通**）

## 4. 开工前必须先解决的技术问题

**在写 UI 之前**，先解决以下问题并记录结论，否则 UI 会建立在对控制通道的错误假设上：

1. **CLI 是否支持运行时热加载配置**，还是改配置必须重启服务？
   （`micyou-cli` 的 `serve` 启动参数为 port/mode/device/bind；
   需确认 `commands.rs` 的 settings 读写对运行中的服务是否生效。）
2. **完整的服务端事件清单**：读 `micyou_core::events::ServerEvents` 的全部 trait 方法，
   列出所有事件类型与字段——这是控制通道的接口基础。
3. **控制通道设计**：上游 CLI 当前输出**人类可读文本**，不是结构化数据。
   请评估并选择方案（推荐前者）：
   - 给上游 CLI 增加 **JSON 事件输出模式**（作为本地补丁集维护）
   - 或解析文本行（脆弱，不推荐）
   > 注意：若修改上游 CLI 源码，即构成 GPL 衍生作品，须遵守第 6 节义务。
4. **`mode_lock` 约束**：`RunMode::Cli` / `RunMode::Gui` 互斥，
   官方 GUI 与 CLI 不能同时运行。设计时要考虑该限制并给出用户提示。

## 5. 交付物

### 5.1 目录结构（沿用 `apps/<platform>` 约定）

```
apps/macos/      # SwiftUI 原生应用（含 Xcode 工程或 SwiftPM 工程）
apps/windows/    # WinUI 3 / C# 原生应用（含解决方案文件）
core/            # 控制层 / 对上游 CLI 的补丁集（如有）
docs/            # 补充设计与决策记录
```

### 5.2 功能范围（对齐上游桌面端，非 MVP）

- 连接：Wi-Fi / USB(ADB) / Web 模式
- 设备发现（mDNS `_micyou._tcp`）与手动 IP 连接
- 实时状态：连接状态、音频电平、延迟/抖动/丢包/缓冲区
- 音频处理设置：AI 降噪、AEC、去混响、均衡器、放大、AGC、VAD
- 虚拟音频设备选择与配置提示（BlackHole / VB-CABLE）
- 静音 / 监听
- 菜单栏（macOS）/ 系统托盘（Windows）
- 开机自启
- 多语言（至少简体中文 + 英文）
- 关于页 + 开源许可声明（GPL 必需）

### 5.3 每个平台都必须

- 提供可复现的构建步骤（写入 `apps/<platform>/README.md`）
- **真实构建通过**（不是"应该能编译"）
- 提供验证方法

## 6. 许可与命名（硬性红线）

1. **产品名使用占位名 `MicDesk`**，集中定义在**单一位置**（一个常量/配置文件），
   便于日后一行改名。
   **不得**继续使用 `MicYou` 作为产品名——GPL 不授予商标权。
2. **不得**让用户误以为本应用是官方 MicYou。
3. 本应用代码须以 **GPL-3.0** 分发。
4. 若修改上游源码（如给 CLI 加 JSON 输出）：
   - 显著标注"已修改"及日期（GPLv3 §5(a)）
   - 保留许可证与原有版权声明（§5(b)）
   - 整体以 GPL-3.0 授权（§5(c)）
   - 界面显示 Appropriate Legal Notices（§5(d)）
   - 提供完整对应源码（§6）
5. **不得删除**原作者的版权声明。
6. Bundle ID / 应用标识**不得**使用 `com.lanrhyme.*`，改用 `com.timmysheep.micdesk`。
7. 协议接口（字段号、magic、握手串、端口）是接口事实，可自由实现；
   但**不要**把上游 `.proto` 文件原样复制进本仓库。

## 7. 环境现状（已核实）

| 项 | 状态 |
|---|---|
| Rust | ✅ `cargo 1.97.1`（可编译上游核心/CLI） |
| Xcode / Swift | ✅ `Xcode 27.0`、`Swift 6.4` |
| .NET SDK | ❌ **本机无 `dotnet`** |
| 磁盘 | ✅ 约 95 GB 可用 |

**Windows 构建的已知障碍**：本机（Mac）没有 .NET SDK / Windows SDK，
WinUI 3 通常需要 Windows 环境才能构建与验证。

**处理方式**：
- Windows 代码要**完整写完**，并提供完整构建说明。
- **不要**擅自改动用户的 Windows 电脑、不要在那里安装软件、不要远程执行命令。
- 若无法在本机验证 Windows 构建，**必须明确标注"未构建验证"**，不得声称通过。

## 8. 工作纪律

1. **先读文档再动手**：`AGENTS.md`、本任务书、`docs/` 全部。
2. **先解决第 4 节的问题**，把结论写进 `docs/`，再开始写 UI。
3. **先出一个实施计划**（分阶段、可验收），再逐步实现。
4. **不要谎报完成**：构建失败就说失败；未验证就标注未验证。
5. 每个阶段要有可验证的产出（能构建、能连上、能传音频）。
6. 重要决策追加到 `docs/DECISIONS.md`。
7. 提交信息用 `feat:` / `fix:` / `docs:` / `chore:` 前缀。
8. 上游源码（`upstream-micyou/`、`MicYou-iOS/`）**只读参考**，已被 `.gitignore` 排除，
   不要把其中的代码复制进本项目。

## 9. 验收标准

- [ ] 第 4 节的四个技术问题有明确结论并落盘
- [ ] `apps/macos/` 可构建，且能实际连接上游 `micyou-cli` 后端并传输音频
- [ ] `apps/windows/` 代码完整、有构建说明（构建验证状态如实标注）
- [ ] 功能覆盖第 5.2 节清单
- [ ] GPL 合规：许可证文件、版权声明、修改标注、关于页声明齐全
- [ ] 产品名与 Bundle ID 已按要求集中定义
- [ ] 构建步骤可复现
