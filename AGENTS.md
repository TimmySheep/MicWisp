# AGENTS.md — 项目规则

本仓库是 Timmy 的自研 iOS 客户端项目。任何 AI agent（OpenCode / Codex / Hermes）在此工作时遵守以下规则。

## 项目边界

- **目标**：用 Swift 独立实现 iPhone → PC 无线麦克风客户端，兼容 MicYou 桌面端协议。
- **不做什么**：不把项目做成 MicYou 的 Fork，不引入上游 GPL 源码作为项目依赖。

## 硬性红线

1. **绝不复制上游 GPL 代码。** `MicYou-iOS/` 目录是只读参考，已被 `.gitignore` 排除。
   - 允许：阅读上游代码理解协议行为。
   - 禁止：把上游 `.m` / `.kt` / `.swift` 代码复制、粘贴、改改变量名后进入本项目。
   - 协议事实（帧格式、magic、端口、消息类型）可以自由使用，接口不受版权保护。
   - 参考 `PROTOCOL.md` 作为实现基线。

2. **不做付费解锁（paywall）。** 项目定位是开源 + 打赏。任何"花钱解锁功能"的设计都违反项目定位。

3. **不擅自扩大范围。** 当前阶段只做协议实现和基础音频链路；灵动岛等 UI 增强等主干稳定后再做。

## 技术约定

- 语言：**Swift**（不用 Objective-C，除非有明确理由）。
- 网络：优先 `Network.framework`（`NWConnection`），不用过时的 `CFStreamCreatePairWithSocketToHost`。
- 音频：`AVAudioEngine` 采集；`AVAudioSession` 用 `.playAndRecord` + `AVAudioSessionModeVoiceChat`（注意正确常量名，别写成 `VoiceCommunication`）。
- 协议编解码：手写 16 字节大端头，不依赖第三方库。
- 目标：iOS 11+，arm64。

## 工作方式

- 改动前先读 `PROTOCOL.md` 和本文件。
- 每个功能做完要有可验证的结果（能连上、能传音频），不要只写代码不验证。
- 提交信息用 `feat:` / `fix:` / `docs:` / `chore:` 前缀。
- 重要决策写进 `docs/DECISIONS.md`。

## 已知坑（来自上游 commit 历史）

- `AVAudioSessionModeVoiceCommunication` **不存在**，会导致编译错误；正确的是 `AVAudioSessionModeVoiceChat`。
- RNNoise 需要 vendored 静态库，不要在构建时远程拉取。
- `timestamp` 上游未做字节序转换，实现时要与服务端行为对齐（见 `PROTOCOL.md` 第 7 节）。
