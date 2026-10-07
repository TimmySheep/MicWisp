# 体积与运行时开销实测

> 方法：下载官方 v2.1.0 Linux `.deb`，用 `ar` + `tar` 解包后实测各文件字节数。
> 日期：2026-10-08。macOS DMG 41 MB / Windows 安装包 29 MB / Linux deb 46 MB（均为压缩后）。

## 1. 当前桌面端装了什么（实测，未压缩）

| 文件 | 体积 | 说明 |
|---|---|---|
| `usr/bin/micyou` | **42 MB** | GUI 主程序（Tauri + 内嵌 Rust 核心） |
| `usr/bin/micyou-cli` | **28 MB** | CLI（**又一份完整核心**） |
| `usr/bin/micyou-tui` | **28 MB** | TUI（**再一份完整核心**） |
| `usr/lib/micyou/resources/libonnxruntime.so` | **24 MB** | AI 降噪运行时 |
| `usr/lib/micyou/resources/aec7_ep0185.onnx` | 4.8 MB | 回声消除模型 |
| `usr/lib/micyou/resources/purevox6.onnx` | 2.1 MB | AI 降噪模型 |
| **合计（主要项）** | **≈ 129 MB** | |

**关键观察：核心代码被打包了三遍**（GUI 42 MB + CLI 28 MB + TUI 28 MB = 98 MB）。
`tauri.conf.json` 的 `externalBin: ['binaries/micyou-cli', 'binaries/micyou-tui']` 证实了这一点。
这就是"重"的主要来源。

## 2. 路线 B 的体积预估

B = 原生 UI + 单个 CLI 无头后端：

| 项 | 体积 |
|---|---|
| 原生 UI（SwiftUI / WinUI） | ~3 MB |
| `micyou-cli`（核心，保留） | 28 MB |
| `libonnxruntime.so`（保留） | 24 MB |
| ONNX 模型（保留） | 7 MB |
| **合计** | **≈ 62 MB** |

**相对当前 ≈129 MB，约减半。**

## 3. 三条结论

1. **安装体积**：B 约为当前的一半。省下来的是重复的 TUI 二进制与较重的 Tauri GUI 二进制。
2. **运行时内存/CPU**：B 明显更轻——**没有 webview 进程、没有 JS 运行时**。
   用户感知到的"重"主要来自这里，B 能实打实解决。
3. **地板**：B 的下限是 `micyou-cli` 28 MB + `onnxruntime` 24 MB ≈ 52 MB。
   **只要复用上游核心，就绕不过这个地板。** 想更小只有两条路：
   - 放弃 AI 降噪（省 24 + 7 MB）——功能损失
   - 自己重写核心（路线 C）——成本极高，且失去上游同步能力

## 4. 可能的进一步优化（未实测）

- Rust 发布二进制通常可 `strip` 符号表；能否显著减小需实测。
- 若上游提供 feature flags 可按需裁剪（如去掉插件 WASM 运行时），需核对 `Cargo.toml`。
- 以上均属"可尝试"，**未经验证，不作为承诺**。

## 5. 方向提示

若目标是"尽可能轻量"，B 是性价比最高的选择；但要有预期：
**它的下限由上游核心决定，不是由你的 UI 决定。**
