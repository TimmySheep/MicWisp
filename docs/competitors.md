# 竞品分析

## 需求层同类产品（iPhone 当 PC/Mac 无线麦克风）

| 产品 | 作者 | 形态 | 许可 | iOS 分发 | 与真实桌面端协议兼容 | 备注 |
|---|---|---|---|---|---|---|
| **MicYou** | LanRhyme / MicYou-Dev | 手机客户端 + 桌面服务端 | GPL-3.0 + Plugin Exception | Android 已分发；iOS 无成品 | —（本体） | 桌面端支持 Win/Linux/macOS；Wi-Fi/USB/Web |
| **MicYou-iOS**（官方脚手架） | herbrine8403（MicYou-Dev 组织） | iOS 客户端**脚手架** | GPL-3.0 | **未上架 App Store** | ❌ **不互通**（见下） | branch `v2`，主要提交 2026-07～08 |
| **VioRelay** | kmgcc | iPhone → Mac 专有工具 | **闭源专有** | TestFlight 分发 | ❌ 不兼容 | 只做 Apple 生态，独立配对协议 |
| **ios2pc-myp** | herbrine8403 | MicYou 插件脚手架 | — | — | 插件形式 | 2026-05 独立成库 |
| **kmgcc/MicYou-iOS-Mici-** | kmgcc | 社区 iOS 移植 | — | — | 未核验 | issue #163 提及"功能不完整但能用"，后被官方脚手架取代 |

## ⚠️ 关键发现：官方 iOS 脚手架与真实桌面端协议不互通

交叉核验 `MicYou-Dev/MicYou-iOS`（脚手架）与 `MicYou-Dev/MicYou`（主仓库）后：

| 项 | iOS 脚手架 | 真实桌面端 |
|---|---|---|
| magic | `0x694F5354`（"iOST"） | `0x4D696359`（"MicY"） |
| 帧结构 | 16 字节头 + 自定义负载 | 8 字节头 + **Protobuf** |
| 端口 | 8900 | 8554 |
| 握手 | 无 | `MicYouCheck1`/`MicYouCheck2` |
| 编码 | 仅裸 PCM | PCM / **Opus** |

主仓库内**完全搜不到** `0x694F5354` 或 `8900`。也就是说这份"官方 iOS 客户端"要么是未完成的占位实现，
要么面向另一个服务端——**它很可能无法与真实 MicYou 桌面端通信。**

## 判断

- **协议层直接竞品**：**实际上没有**。官方 iOS 脚手架疑似不能与桌面端互通；主维护者 herbrine8403 精力在 Minecraft 启动器项目（`Amethyst-iOS-MyRemastered`，193 stars）。
- **需求层同类产品**：`VioRelay`（闭源、TestFlight、协议不互通）。抢的是同一批"想要 iPhone 当麦克风"的新用户。
- **机会**：iOS 侧没有可用的开源客户端 → 存在真空。但同时也意味着**这条路没有前人验证过**，协议细节必须自己实测（尤其是握手与 Opus）。
- **差异化**：开源 + 灵动岛，与官方和 VioRelay 都不冲突。

## 待实测确认

1. 官方 iOS 脚手架是否真的无法连接真实桌面端（需实机验证，目前是代码层推断）。
2. 桌面端是否接受纯 PCM（codec=0）而无需 Opus。
3. 桌面端 Web 模式的端口与协议（`web_port` 可配置，尚未核验是否另一套协议）。

## 调研时间

2026-10-08（数据来自 GitHub API、上游主仓库与 iOS 仓库只读核验）。
