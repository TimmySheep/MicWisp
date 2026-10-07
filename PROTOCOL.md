# MicYou 真实协议规格（v2 — 已更正）

> ⚠️ **本文档替换了初版。** 初版基于官方 `MicYou-Dev/MicYou-iOS` 仓库的 `Protocol.m` 整理，
> 但经与 MicYou **主仓库**（`MicYou-Dev/MicYou`，含真实桌面端实现）交叉核验后确认：
> **那套协议与真实桌面端不兼容，初版结论是错的。** 本文以主仓库 Rust/Android 实现为准。
>
> 来源（只读核验）：`tauri-app/crates/micyou-protocol/`、`tauri-app/crates/micyou-core/src/transport/`、
> `composeApp/src/main/kotlin/com/lanrhyme/micyou/network/Protocol.kt`。
> 本文是协议事实的独立复述，不含上游代码。

## 0. 关键更正摘要

| 项 | 初版（基于 iOS 脚手架）❌ | 真实协议 ✅ |
|---|---|---|
| 帧头 magic | `0x694F5354`（"iOST"） | `0x4D696359`（"MicY"） |
| 帧结构 | 16 字节头（magic/type/len/seq） | 8 字节头（magic/len）+ Protobuf |
| 负载编码 | 裸 PCM 自定义结构 | **Protocol Buffers** |
| TCP 端口 | 8900 | **8554**（默认，可配置） |
| 握手 | 无（直接发 Hello 帧） | 先发裸字符串 `"MicYouCheck1"` / 收 `"MicYouCheck2"` |
| 音频编码 | 仅裸 PCM | PCM **或 Opus** |
| 发现 | 无 | mDNS `_micyou._tcp.local.` |

**结论：官方 iOS 脚手架用的是一套与真实桌面端不互通的协议。** 要么它是未完成的占位实现，
要么它面向另一个服务端。写客户端必须以本文件的真实协议为准。

## 1. 传输层

| 项 | 值 |
|---|---|
| 主通道 | TCP |
| 默认 TCP 端口 | `8554`（`Constants.DEFAULT_TCP_PORT`，用户可配置） |
| UDP 端口 | TCP 端口 `+ 1` → 默认 `8555` |
| 服务发现 | mDNS：`_micyou._tcp.local.`（Web 模式：`_micyou-web._tcp.local.`） |
| 字节序 | 大端（network byte order） |
| 音频编码 | `0` = 裸 PCM（旧版默认），`1` = Opus |

> 注：`micyou-protocol` crate 里另有一个 `PORT = 9123` 常量，但**运行时默认端口是 8554**，
> 9123 只见于测试/示例，疑为遗留常量。以 8554 为准，或直接用 mDNS 发现实际端口。

## 2. 连接流程

```
1. TCP 连接 host:8554
2. 客户端发送裸字符串 "MicYouCheck1"（12 字节，不加帧头）
3. 服务端回 "MicYouCheck2"（12 字节）
4. 客户端发送第一个帧：Connect 消息（携带 sessionId）
   —— 旧版客户端可跳过 Connect，直接发控制/音频帧
5. 之后所有消息走「8 字节帧头 + Protobuf 负载」
6. Ping 心跳（服务端每 500ms 发 Ping，客户端回 Pong）
7. 音频可走 TCP（AudioPacketMessageOrdered）或 UDP（裸 Protobuf）
```

## 3. TCP 帧格式

固定 8 字节头，后接 Protobuf 字节流：

| 偏移 | 字段 | 类型 | 说明 |
|---|---|---|---|
| 0 | `magic` | int32（大端） | 固定 `0x4D696359`（"MicY"） |
| 4 | `payloadLength` | int32（大端） | 后续 Protobuf 字节数，不得为负 |

限制：`payloadLength ≤ 1 MiB`（`MAX_CONTROL_PAYLOAD_LEN`）。

## 4. Protobuf 消息定义（proto3，package `micyou`）

以官方 `proto/network.proto` 为准，字段号如下（实现时用自己的类型，字段号必须一致）：

```proto
message MessageWrapper {
  AudioPacketMessageOrdered audioPacket = 1;  // TCP-only 模式
  ConnectMessage connect = 2;
  MuteMessage mute = 3;
  // reserved 4
  PingMessage ping = 5;
  PongMessage pong = 6;
  PluginMessage pluginMessage = 7;            // 跨设备插件消息
}

message ConnectMessage   { int64 sessionId = 1; }   // 0 = 旧版客户端
message MuteMessage      { optional bool isMuted = 1; }
message PingMessage      { int64 timestamp = 1; }
message PongMessage      { int64 timestamp = 1; }

message AudioPacketMessageOrdered {
  int32 sequenceNumber = 1;
  AudioPacketMessage audioPacket = 2;
  int64 timestamp = 3;
  bytes fecBuffer = 4;              // 前向纠错
  int32 fecSequenceNumber = 5;
  int64 sessionId = 6;
  repeated uint32 fecPacketLengths = 7;
}

message AudioPacketMessage {
  bytes buffer = 1;        // 音频数据（PCM 或 Opus）
  int32 sampleRate = 2;
  int32 channelCount = 3;
  int32 audioFormat = 4;   // 采集格式，仅供遥测
  int32 codec = 5;         // 0=PCM, 1=Opus
}

message PluginMessage {
  string source = 1;
  string target = 2;
  string topic = 3;
  bytes payload = 4;
  uint64 correlationId = 5;
  bool isResponse = 6;
  int32 errorCode = 7;
  string errorMessage = 8;
}
```

## 5. UDP 通道

帧头同为 8 字节，magic 换成 `0x4D696355`（"MicU"），后接 Protobuf：

| 项 | 值 |
|---|---|
| 头 | magic(4) + len(4) |
| 最大音频负载 | 64 KiB（`MAX_AUDIO_PAYLOAD_LEN`） |
| 最大数据报 | 1472 字节 |
| PCM 建议负载 | 1320 字节 |
| 端口 | TCP 端口 + 1 |

## 6. 自研 Swift 实现要点

- **握手不能忘**：先写裸字节 `"MicYouCheck1"`，读 `"MicYouCheck2"`，再开始发帧。这是最容易漏的一步。
- 帧头 8 字节手写即可；负载用 **SwiftProtobuf** 生成（从 `network.proto` 自己写一份同字段号的 `.proto`，不要复制上游文件）。
- Opus 用 `libopus`（可先只支持 PCM codec=0，桌面端接受旧版 PCM）。
- mDNS 发现用 `Network.framework` 的 `NWBrowser`（`_micyou._tcp`）。
- 先做 TCP-only 模式（`AudioPacketMessageOrdered`），UDP + FEC 后续再加。

## 7. 许可边界

- 本文档是协议事实的独立复述，不含上游代码。
- 上游 `MicYou`（含桌面端）为 **GPL-3.0 + Plugin Exception**；`MicYou-iOS` 脚手架为 **GPL-3.0**。
- **协议接口（字段号、magic、握手串、端口）是接口事实，不受版权保护**——自己写实现不构成复制。
- **不要**把上游 `.proto` 文件原样复制进本项目；照字段号自己写一份。
- 修改上游核心源码（如 Fork 桌面端）→ 必须整体以 GPL-3.0 开源分发。打赏模式与 GPL 兼容。

---

*核验基线：MicYou 主仓库（浅克隆，2026-10-08）；iOS 脚手架 branch `v2` commit `9ee4ea1`。*
