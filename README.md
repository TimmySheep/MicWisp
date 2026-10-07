# MicYou iOS 自研客户端 — 项目仓库

Timmy 的独立 iOS 客户端项目工作区。目标：用 Swift 自己重写一个 iPhone → PC 无线麦克风客户端，加灵动岛支持，**全开源 + 纯打赏（Apple IAP tip）**，不做付费解锁。

## 为什么自研而不是 Fork

官方 `MicYou-Dev/MicYou-iOS` 是 **GPL-3.0**。直接改它并闭源分发不合规；而"付费解锁高级功能"在 GPL 下也无法成立（用户有权拿到源码并移除付费墙）。

本项目路线：
1. **只读研究**上游协议（已完成，见 `PROTOCOL.md`）
2. **用 Swift 独立重写**客户端，不复制上游代码
3. 独立原生实现客户端完整功能，并加入灵动岛 / Live Activity
4. 全开源，收入来自打赏

协议接口本身不受版权保护，独立实现是干净的。

## 仓库结构

```
micyou-ios-study/
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

- 开发机：MacBook Pro（`tims-mbp`, macOS 27.0.1）
- Xcode 工程目标：iOS 16.1+，arm64（Live Activity 最低系统版本）
- 参考设备：iPhone 15（无个人数据，可用于测试）
