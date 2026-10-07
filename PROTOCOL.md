# MicYou iOS 协议规格（自研客户端基线）

> 本文档由 Hermes 通过只读研究官方 `MicYou-Dev/MicYou-iOS`（branch `v2`）的源码整理而成。
> 内容是**协议事实的独立描述**（帧格式、字段、连接流程），不包含上游 GPL 代码。
> 目的：作为自研 Swift 客户端的接口基线，避免复制上游实现。

## 1. 传输层

| 项 | 值 |
|---|---|
| 主通道 | TCP |
| 默认端口 | `8900` |
| 附加通道 | UDP（同一端口，独立 socket，客户端绑定随机本地端口） |
| 字节序 | 大端（network byte order） |
| 采样率 | `44100` Hz |
| 声道 | `1`（单声道） |
| 位深 | `16` bit |
| 音频编码 | 原始 PCM（未压缩） |

连接流程（客户端主动发起）：

```
1. TCP 连接 host:8900
2. 发送 Hello（携带设备名、设备 ID、采样率、声道）
3. 启动 KeepAlive 定时器，周期性发送 KeepAlive
4. 持续发送 AudioFrame
5. 结束时发送 Disconnect（可带原因字符串）
```

## 2. 消息头（16 字节，固定）

所有消息共享一个 16 字节头，字段均为大端 uint32：

| 偏移 | 字段 | 类型 | 说明 |
|---|---|---|---|
| 0 | `magic` | uint32 | 固定 `0x694F5354`（ASCII `iOST`） |
| 4 | `type` | uint32 | 消息类型，见下表 |
| 8 | `payloadLength` | uint32 | 负载字节数 |
| 12 | `sequence` | uint32 | 序号，递增 |

解析规则：先读 16 字节头，校验 `magic == 0x694F5354`；再按 `payloadLength` 读负载。

## 3. 消息类型

| 值 | 名称 | 方向 | 说明 |
|---|---|---|---|
| 1 | Hello | 客户端 → 服务端 | 握手，声明音频参数 |
| 2 | Ack | 服务端 → 客户端 | 确认（客户端目前只解析头） |
| 3 | KeepAlive | 客户端 → 服务端 | 保活，无负载 |
| 4 | Disconnect | 客户端 → 服务端 | 断开，负载为原因字符串 |
| 16 | AudioFrame | 客户端 → 服务端 | 音频数据帧 |

> 注：上游另有一份 Kotlin 常量表（`MicYouProtocolConstants`）使用 `HANDSHAKE=1 / AUDIO=2 / CONTROL=3 / HEARTBEAT=4 / CONFIG=5` 的定义。
> 两份定义并不一致，**以 Objective-C 实现（本表）为准**，因为它是实际发送路径。这一点在自研时应向官方确认。

## 4. 各消息负载格式

### 4.1 Hello（type=1）

顺序拼接，字符串与数值均为大端：

```
uint32  nameLen        // 设备名（UTF-8）字节数
bytes   name           // 设备名
uint32  idLen          // 设备 ID（UTF-8）字节数
bytes   deviceId       // 设备 ID
uint32  sampleRate     // 例 44100
uint32  channelCount   // 例 1
```

头中的 `sequence` 固定为 `0`。

### 4.2 AudioFrame（type=16）

```
uint32  sequence       // 帧序号（与头中 sequence 一致）
uint64  timestamp      // 时间戳（大端）
uint32  sampleRate
uint32  channelCount
uint32  dataLen        // PCM 字节数
bytes   pcmData        // 原始 PCM
```

> 注意：`timestamp` 为 uint64，**但上游实现未做字节序转换**（直接按主机序写入）。
> 在 arm64（小端）到服务端解析之间需保持一致；自研时应按小端写入以匹配上游行为，或与官方确认。

### 4.3 KeepAlive（type=3）

无负载，`payloadLength = 0`，`sequence` 递增。

### 4.4 Disconnect（type=4）

```
uint32  reasonLen
bytes   reason         // UTF-8 原因字符串
```

### 4.5 Ack（type=2）

客户端当前只解析头，未读取负载内容。自研时可先忽略负载。

## 5. 客户端行为要点

- 连接成功后**立即**发 Hello，然后启动 KeepAlive。
- 音频帧持续发送，帧间隔由采集缓冲决定。
- UDP 通道单独建立，绑定随机本地端口后 `connect` 到远端 8900。
- 断链处理：先发 Disconnect，再关闭流。

## 6. 自研实现建议（Swift）

- 用 `Network.framework`（`NWConnection`）替代上游的 `CFStreamCreatePairWithSocketToHost`。
- 用 `AVAudioEngine` 采集，`AVAudioSession` 设为 `.playAndRecord` + `.voiceChat` 模式（注意：上游踩过 `AVAudioSessionModeVoiceCommunication` 不存在的坑，正确常量是 `AVAudioSessionModeVoiceChat`）。
- 手写 16 字节头编解码（`withUnsafeBytes` + `bigEndian`），无需依赖上游代码。
- 40 行左右即可完成 Hello / AudioFrame / KeepAlive / Disconnect 的编解码。

## 7. 待向官方确认的问题

1. 两份消息类型定义（Kotlin 常量 vs ObjC 实现）哪个是权威？
2. `timestamp` 的真实字节序（上游未转换）。
3. 服务端是否要求 UDP 与 TCP 同时建立，还是二选一可用。
4. 是否支持有损压缩（当前看是纯 PCM）。
5. 服务端对 `Ack` 的发送时机与客户端是否必须处理。

## 8. 许可边界（重要）

- 本文件是**协议事实的独立复述**，不含上游代码，不受 GPL 约束。
- 上游 `MicYou-iOS` 为 **GPL-3.0**；若复制其 `.m/.swift/.kt` 源码，你的衍生作品需整体以 GPL-3.0 分发。
- **协议接口本身不受版权保护**，独立重写实现不构成复制。这是本方案可闭源/可打赏的法律基础。
- 上游 MicYou 主项目的 Plugin Exception 对**商业插件**要求书面授权；自研独立客户端不属于插件，不受该条约束。

---

*研究基线版本：上游 branch `v2`，commit `9ee4ea1`（2026-08 前后）。*
