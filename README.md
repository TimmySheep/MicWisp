# MicWisp — 独立 iOS 客户端项目

面向 MicYou 无线麦克风协议的第三方独立 iPhone → PC 客户端。使用 Swift / Apple 原生框架实现，目标包含灵动岛；**全开源**，也不隶属于 MicYou 官方项目。

## 为什么自研而不是 Fork

官方 `MicYou-Dev/MicYou-iOS` 是 **GPL-3.0**。直接改它并闭源分发不合规；而"付费解锁高级功能"在 GPL 下也无法成立（用户有权拿到源码并移除付费墙）。

本项目路线：
1. **只读研究**上游协议（已完成，见 `PROTOCOL.md`）
2. **用 Swift 独立重写**客户端，不复制上游代码
3. 独立原生实现客户端完整功能，并加入灵动岛 / Live Activity
4. 全开源

协议接口本身不受版权保护，独立实现是干净的。

## 仓库结构

```
MicWisp/
├── PROTOCOL.md      # 协议规格（自研基线，自有文档）
├── README.md        # 本文件
├── AGENTS.md        # 给 AI agent 的项目规则
├── docs/            # 竞品分析、决策记录
├── Sources/         # Swift 原生客户端与协议核心
├── Tests/           # 协议与核心逻辑测试
├── MicYou.xcodeproj/ # iOS App 与 Live Activity 工程
├── reference/       # 参考资料（自有笔记）
└── MicYou-iOS/      # 上游 GPL 源码克隆，仅本地参考，已被 .gitignore 排除
```

## 上游参考

```bash
# 如需重新拉取上游（只读参考，不要 commit）
git clone --branch v2 https://github.com/MicYou-Dev/MicYou-iOS.git MicYou-iOS
```

## 状态

- [x] 克隆并研究官方 iOS 仓库协议实现
- [x] 整理独立协议规格 `PROTOCOL.md`
- [ ] 建立并验证 Xcode 工程骨架
- [ ] 实现真实协议（握手 / Protobuf / TCP 与 UDP 音频 / 心跳 / 控制）
- [ ] 接入 AVAudioEngine、音频处理与完整设置
- [ ] 实现 mDNS、重连、日志、通知、更新检查与本地化
- [ ] 灵动岛 / Live Activity
- [ ] 上架准备（Apple Developer 年费 $99）

## 环境

- Xcode 工程目标：iOS 16.1+，arm64（Live Activity 最低系统版本）

## Acknowledgments & Disclaimer

This project is an independent, unofficial iOS client designed for compatibility with the "MicYou" (https://github.com/MicYou-Dev/MicYou) communication protocol and ecosystem.

It is not an official MicYou application and is not affiliated with, endorsed by, or maintained by the MicYou team.

We sincerely thank the original MicYou author, LanRhyme, and all contributors for their work on the project and its open-source ecosystem.

We also acknowledge the existing "MicYou-iOS" (https://github.com/MicYou-Dev/MicYou-iOS) project and the work of its maintainers.

This client is independently developed and maintained. Issues related to this application should be reported in this repository.

Any reused MicYou source code or components will retain their applicable copyright notices and license terms.
