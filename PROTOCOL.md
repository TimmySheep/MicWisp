# MicYou 真实协议规格（v3 — 已用客户端源码验证）

> 本文档由 Hermes 只读研究 MicYou **主仓库**（`MicYou-Dev/MicYou`）整理。
> 来源：`tauri-app/crates/micyou-protocol/`、`micyou-core/src/transport/`、
> `composeApp/.../network/Protocol.kt`、`composeApp/.../audio/AudioEngine.kt`（Android 客户端连接实现）。
> 内容是协议事实的独立复述，不含上游代码。
>
> **v1 勘误**：初版基于官方 `MicYou-iOS` 脚手架的 `Protocol.m`（magic `0x694F5354`/端口 8900），
> 与真实桌面端**不互通**，已作废。以本文为准。

## 0. 关键事实

| 项 | 值 |
|---|---|
| 帧头 magic（TCP） | `0x4D696359`（"MicY"） |
| 帧头 magic（UDP） | `0x4D696355`（"MicU"） |
| 帧结构 | 8 字节头（magic + len）+ **Protobuf** |
| 默认端口 | TCP `8554`，UDP `8555`（= TCP + 1） |
| 握手 | 裸字符串 `"MicYouCheck1"` → `"MicYouCheck2"` |
| 音频编码 | PCM（codec 0）或 Opus（codec 1），**两者服务端都支持** |
| 服务发现 | mDNS `_micyou._tcp.local.` |

**协议完全公开已知**——桌面端（Rust）与 Android 客户端（Kotlin）都是 GPL 开源，
不需要逆向。**Android 客户端是一份完整可用的客户端参考实现**（见第 6 节）。

## 1. 传输层

| 项 | 值 |
|---|---|
| 主通道 | TCP |
| 默认 TCP 端口 | `8554`（用户可配置） |
| UDP 端口 | TCP + 1 → 默认 `8555` |
| 传输模式 | `Tcp`（仅 TCP）/ `Both`（WiFi 下音频走 UDP，控制走 TCP） |
| 服务发现 | mDNS `_micyou._tcp.local.`、`_micyou-web._tcp.local.` |
| 字节序 | 大端 |

> `micyou-protocol` crate 内的 `PORT = 9123` 只见于测试，运行时默认是 8554。

## 2. 连接流程（已由 Android 客户端源码验证）

```
1. TCP 连接 host:8554
2. 写裸字符串 "MicYouCheck1"（12 字节，非帧）
3. 读 12 字节，必须等于 "MicYouCheck2"，否则握手失败
4. 发送 Connect 帧：
     writeInt(PACKET_MAGIC)   // 0x4D696359，大端
     writeInt(payloadLen)     // 大端
     writeFully( protobuf(MessageWrapper{ connect = ConnectMessage(sessionId) }) )
5. 开始录音，持续发送音频帧（同帧格式）
6. 音频可走 TCP（AudioPacketMessageOrdered）或 UDP（裸 Protobuf）
```

**注意**：`UDP-only` 模式会跳过握手，但上游源码注释标注"这可能会有连接问题"。
自研建议始终走 TCP 握手。

## 3. TCP 帧格式

| 偏移 | 字段 | 类型 | 说明 |
|---|---|---|---|
| 0 | `magic` | int32（大端） | `0x4D696359` |
| 4 | `payloadLength` | int32（大端） | Protobuf 字节数，非负 |

上限 `1 MiB`。每帧都是「magic + len + protobuf」，音频帧与 Connect 帧格式一致。

## 4. Protobuf 消息（proto3，package `micyou`）

字段号必须一致（自己写 `.proto`，不要复制上游文件）：

```proto
message MessageWrapper {
  AudioPacketMessageOrdered audioPacket = 1;
  ConnectMessage connect = 2;
  MuteMessage mute = 3;
  // reserved 4
  PingMessage ping = 5;
  PongMessage pong = 6;
  PluginMessage pluginMessage = 7;
}

message ConnectMessage   { int64 sessionId = 1; }   // 0 = 旧版客户端
message MuteMessage      { optional bool isMuted = 1; }
message PingMessage      { int64 timestamp = 1; }
message PongMessage      { int64 timestamp = 1; }

message AudioPacketMessageOrdered {
  int32 sequenceNumber = 1;
  AudioPacketMessage audioPacket = 2;
  int64 timestamp = 3;
  bytes fecBuffer = 4;
  int32 fecSequenceNumber = 5;
  int64 sessionId = 6;
  repeated uint32 fecPacketLengths = 7;
}

message AudioPacketMessage {
  bytes buffer = 1;
  int32 sampleRate = 2;
  int32 channelCount = 3;
  int32 audioFormat = 4;   // 采集格式，仅遥测
  int32 codec = 5;         // 0=PCM, 1=Opus
}

message PluginMessage {
  string source = 1;  string target = 2;  string topic = 3;
  bytes payload = 4;  uint64 correlationId = 5;
  bool isResponse = 6; int32 errorCode = 7; string errorMessage = 8;
}
```

## 5. 音频编码：PCM 与 Opus 都可以

服务端 `audio_pipeline.rs` 的 `decode()` 逻辑：

```
if codec == CODEC_OPUS { decode_opus(...) }
else                   { decode_pcm(audio_format, ...) }
```

**结论：服务端同时支持两种编码，PCM 不是"过时路径"而是正常分支。**
服务端内部统一重采样到 48 kHz f32。

- **只做 PCM（codec=0）是可行的**，能显著降低首版复杂度（不必在 Swift 里接 Opus）。
- 若要用 Opus：采样率仅支持 8/12/16/24/48 kHz；Android 客户端把 44.1 kHz 映射到 48 kHz。
- FEC 分组：每 12 个包生成 1 个 FEC 包（`FEC_GROUP_SIZE = 12`）。

## 6. 客户端参考实现（Android）

Android 客户端 `AudioEngine.kt` 是完整可用的客户端，实现顺序：

1. 建 TCP socket，取 output/input 流
2. 握手（见第 2 节）
3. 建 UDP socket（`Both` 模式且在 WiFi 下）
4. `recorder.startRecording()`
5. writer 循环：控制消息走 TCP；`Both` + WiFi 下音频走 UDP，否则 TCP
6. reader 循环：处理服务端 Ping → 回 Pong

自研 Swift 客户端可以逐段对照这份实现，不必猜测。

## 7. 自研 Swift 实现要点

- **握手别漏**：先写裸字节 `"MicYouCheck1"`，读回 `"MicYouCheck2"`，再发帧。
- 用 **SwiftProtobuf**，自己照字段号写 `.proto`。
- **首版可只做 PCM**，省掉 Opus 依赖；要压缩再加 `libopus`。
- 用 `Network.framework`（`NWConnection`）替代 `CFStream`；mDNS 用 `NWBrowser`。
- 先做 TCP-only，跑通后再加 UDP + FEC。

## 8. 许可边界

- 本文档是协议事实的独立复述，不含上游代码。
- 上游 `MicYou` 与 `MicYou-iOS` 均为 **GPL-3.0**（主项目带 Plugin Exception）。
- **协议接口（字段号、magic、握手串、端口）是接口事实，不受版权保护**——独立实现不构成复制。
- **不要**把上游 `.proto` 原样复制进本仓库。
- Fork 上游核心源码 → 衍生作品须整体以 GPL-3.0 开源。打赏模式与 GPL 兼容。

---

*核验基线：MicYou 主仓库浅克隆（2026-10-08）；iOS 脚手架 branch `v2` commit `9ee4ea1`。*
