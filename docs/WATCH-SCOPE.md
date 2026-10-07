# Apple Watch 客户端范围（WATCH-SCOPE）

> **给 AI agent 的作业单。** 本文定义一个**新的第三条工作线**：MicWisp 的 watchOS 伴侣 App。
> 归属**iOS/iPadOS 线**（同一 Xcode 工程、同一 App bundle、所以同许可），但文件边界独立。

---

## 1. 目标（只有两件事，不要扩大范围）

用户明确要求的**全部**功能：

| # | 功能 | 说明 |
|---|---|---|
| **1** | **远程控制麦克风开关** | 在手表上**临时关闭/开启** iPhone 端的麦克风。典型场景：开会/上厕所时临时静音，不用掏手机 |
| **2** | **显示连接状态** | 显示 **iPhone ↔ 上游机器**（Windows / macOS）的当前连接状态 |

**不做**：手表独立采集音频、手表直连上游机器、手表上选设备/改 DSP、手表上看频谱。

理由是硬约束，见下一节。

---

## 2. 架构（唯一可行方案，不要试图绕过）

```
   Apple Watch  ── WCSession ──▶  iPhone  ── MicYou 协议 TCP 8554 ──▶  上游机器
  (MicWisp Watch)                 (MicWisp iOS)                      (Windows/macOS)
```

### 2.1 为什么手表不直连上游机器

1. **麦克风在 iPhone 上** —— 手表没有麦克风采集链路，且要传的是 iPhone 的流
2. **watchOS 对网络有严格限制** —— 手表 App 默认不允许自行长期持有网络连接
   （为省电，只有极少数例外，且连接会被系统周期性回收）
3. **连接状态的"真相"在 iPhone 端** —— iPhone 才是与上游建连的一方

**结论：手表只跟 iPhone 说话。** 这一层不要自作聪明。

### 2.2 通信通道选择（关键设计，已按 Apple 文档核实）

**方向决定通道**——两侧的"可达性"是不对称的：

| 方向 | 可达性（Apple 官方表述） | 应使用 |
|---|---|---|
| **watch → iPhone** | **iPhone app 永远被视为可达**；从手表调用会**唤醒后台的 iPhone app** | `sendMessage`（即时、可靠） |
| **iPhone → watch** | 手表 app **仅在其运行（前台）时**才算可达 | `updateApplicationContext`（最新快照，随手表唤醒送达） |

**所以两个功能各走一条**：

**功能 1 · 静音指令（watch → iPhone）—— 用 `sendMessage`**

- iPhone app **永远可达**，即使它在后台也会被唤醒 → **指令可靠送达**
- 带 `replyHandler` 拿回执（手表可显示"已执行 / 失败"）
- 失败回退：`transferUserInfo`（排队保证送达），不要静默丢弃

**功能 2 · 连接状态（iPhone → watch）—— 用 `updateApplicationContext`**

- `updateApplicationContext` 是**"最新值覆盖"语义**：只保留最后一份，手表醒来即拿到
- 这**正好匹配状态显示需求**——状态本来就只需"最新快照"，不需要事件流
- **增强**：手表在前台时叠加 `sendMessage` 以获得即时刷新；
  最佳实践是先试 `sendMessage`，**失败回退** `updateApplicationContext`
- **不要**用 `updateApplicationContext` 传静音指令（会被覆盖丢失）
- **不要**用 `sendMessage` 传状态（手表不在前台就丢）

### 2.3 消息契约（**必须版本化**，两侧共同实现）

**状态快照（iPhone → 手表）**

```json
{
  "v": 1,
  "micEnabled": true,
  "connection": "connected",
  "peerName": "TIM-PC",
  "since": 1759900000
}
```

- `connection` 取值：`disconnected` / `connecting` / `connected` / `error`
- `since`：进入该状态的时间戳（手表可显示"已连接 12 分钟"）
- 手表**离开范围**时：保留最后已知快照并标注**时间**，不要假装实时

**指令（手表 → iPhone）**

```json
{ "v": 1, "cmd": "setMic", "enabled": false, "reqId": "<uuid>" }
```

- `cmd` 取值（首版只需这两个）：`setMic`（显式设置）、`toggleMic`
- `reqId` 用于回执配对，**必须回带**在 reply 里
- `v` 版本号两侧都要校验；不认识就拒绝并回复错误，**不要猜**

### 2.4 生命周期与必须处理的坑（已核实）

1. **`WCSession.isSupported()` 在 iPad 上返回 `false`** —— 不检查会崩。
   MicWisp 是 iPhone+iPad 通用 App，**必须**先判断再访问 `WCSession.default`。
2. **`WCSession.delegate` 必须在 `activate()` 之前设置**，且在 App 启动早期完成
   （SwiftUI 里用 `@main App` 里创建的 manager，不要放在某个 View 的 `onAppear`）。
3. **`sessionDidDeactivate` 里必须重新 `activate()`** —— 用户换手表后不重新激活，
   通信会静默失效。
4. **委托回调在后台线程** —— 更新 UI 必须跳回主 actor。
5. **`isReachable` 为 true 也可能失败**（手表 app 不在前台）—— 错误处理必须实现，不可依赖。

---

## 3. 交付物

| 交付物 | 路径 | 说明 |
|---|---|---|
| 手表 App target | `Sources/MicWispWatch/` | SwiftUI watchOS App |
| 共享消息契约 | `Sources/MicWispCore/`（复用 iOS 协议核心包） | 状态/指令的可编解码类型，**两侧共用一份** |
| Xcode 集成 | iOS 工程内嵌 Watch target | `WKCompanionAppBundleIdentifier` 指向 iOS app；`WKWatchOnly = false` |
| 范围文档 | `docs/WATCH-SCOPE.md` | 本文 |
| 决策记录 | `docs/DECISIONS.md`（**只追加**） | 通道选择等关键决策 |

**命名**：target / 目录 / Bundle 显示名统一用 **`MicWispWatch`**（产品名已定 `MicWisp`，
不要再用 `MicYou*` 命名）。显示名可为 `MicWisp`。

---

## 4. 验收标准（**必须逐条实测，不许口头声称通过**）

**能构建**
- [ ] iOS app 与 Watch app **都能构建**（`xcodebuild` 双 target）
- [ ] **iPad 上不崩**（`isSupported()` 分支正确）

**功能 1**
- [ ] iPhone app 在**后台**时，手表按静音 → iPhone 端麦克风状态**确实变了**（真机）
- [ ] 静音后**音频流行为明确**：停止发送音频（或发送静音），且**会话不断开**
- [ ] 断连/失败时手表**明确显示失败**，不假装成功

**功能 2**
- [ ] 上游机器未启动时，手表显示 `disconnected`
- [ ] iPhone 连上上游后，手表显示 `connected` + 正确的机器名
- [ ] 拔掉上游/断开网络 → 手表状态**跟着变**（允许延迟到手表下次唤醒）
- [ ] 手表离开范围再回来 → 显示**最新**状态，不是陈旧状态

**明确标注不可验证项**
- ⚠️ **模拟器不能复现后台/唤醒行为**（Apple 明确说明：后台场景必须真机测）。
  模拟器只用于 UI 与编译验证；**后台唤醒与真实静音必须真机**。
- ⚠️ 若因签名/设备限制无法真机验证，**必须如实标注"未真机验证"**，不得写成通过。

---

## 5. 许可与发布

- **MIT**（与 iOS/iPadOS 线一致，见 `docs/LICENSING.md`）。
  **不得标为 GPL** —— 手表 App 随 iOS App 一起进 App Store，GPL 与 App Store 条款冲突。
- 手表 App **内嵌于 iOS App bundle** 分发，不单独上架。
- 遵守 `AGENTS.md` 共享红线：不使用 `MicYou` 作产品名、不暗示官方隶属、不复制上游 GPL 代码。

---

## 6. 与其它工作线的边界

- 本文属 **iOS/iPadOS 线**（同一 Xcode 工程）。**桌面线不得触碰** `Sources/MicWispWatch/`。
- 只新增/修改：
  - `Sources/MicWispWatch/**`（新）
  - `Sources/MicWispCore/**` 中新增**消息契约类型**（新增文件优先，避免与改名冲突）
  - Xcode 工程文件（新增 Watch target）
  - `docs/WATCH-SCOPE.md`、`docs/DECISIONS.md`（追加）
- **不要**顺手改桌面线的 `apps/`、`core/`、`TASK.md`。

---

## 7. 分期建议（先能跑，再加料）

| 阶段 | 内容 |
|---|---|
| **W1** | 消息契约类型 + 两侧 WCSession 管理器 + 最简两屏 UI（一个开关按钮 + 一行状态） |
| **W2** | 错误处理、失败回退、断连/重连状态机、iPad 安全分支 |
| **W3** | 真机验证（后台唤醒 + 真实静音） |
| **W4（可选）** | 表盘复杂功能 / Smart Stack 显示连接状态 |

**W1–W3 是用户要求的全部内容；W4 是加分项，不要因此推迟 W1–W3。**
