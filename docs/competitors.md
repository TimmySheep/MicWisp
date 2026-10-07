# 竞品分析

## 需求层同类产品（iPhone 当 PC/Mac 无线麦克风）

| 产品 | 作者 | 形态 | 许可 | iOS 分发 | 与 MicYou 协议兼容 | 备注 |
|---|---|---|---|---|---|---|
| **MicYou** | LanRhyme / MicYou-Dev | 手机客户端 + 桌面服务端 | GPL-3.0 + Plugin Exception | Android 已上架分发；iOS 仅**代码仓** | —（本体） | 桌面端支持 Win/Linux/macOS，Wi-Fi/USB/Web 三种连接 |
| **MicYou-iOS** | herbrine8403（MicYou-Dev 组织） | 官方 iOS 客户端脚手架 | GPL-3.0 | **未上架 App Store** | ✅ 同一协议 | branch `v2`，主要提交 2026-07～08 |
| **VioRelay** | kmgcc | iPhone → Mac 专有工具 | **闭源专有** | TestFlight 分发 | ❌ 不兼容 | 只做 Apple 生态，独立配对协议 |
| **ios2pc-myp** | herbrine8403 | MicYou 插件脚手架 | — | — | 插件形式 | 2026-05 独立成库 |
| **kmgcc/MicYou-iOS-Mici-** | kmgcc | 社区 iOS 移植 | — | — | 部分 | issue #163 提及"功能不完整但能用"，后被官方仓取代 |

## 判断

- **协议层直接竞品**：只有官方 `MicYou-iOS`。它未上架、无商业化迹象，主维护者精力在 Minecraft 启动器项目（`Amethyst-iOS-MyRemastered`，193 stars，持续更新）。
- **需求层同类产品**：`VioRelay`。闭源收费、TestFlight 分发、协议不互通。抢的是同一批"想要 iPhone 当麦克风"的新用户，但不抢 MicYou 存量用户。
- **差异空间**：官方缺 App Store 版本、缺灵动岛、无付费/打赏设计。本项目以"开源 + 打赏 + 灵动岛"切入，定位与两者都不冲突。

## 调研时间

2026-10-08（数据来自 GitHub API 与上游仓库只读检查）。
