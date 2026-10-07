# 上游补丁与 PR 双路方案

> **给 AI agent 的作业单。** 完成"给上游 `micyou-cli` 加运行时控制通道"这一个补丁，
> 然后走两条路：**路径 A 提 PR 给上游**；**路径 B 若被拒则在本地使用**。
> 一份补丁同时服务两条路，**不要做两遍。**

---

## 0. 为什么需要这个补丁（问题定义）

MicWisp 桌面端采用路线 B：原生 UI + 打包上游 `micyou-cli` 作无头后端。

**缺口**（见 `docs/DESKTOP-PREWORK.md`）：上游 CLI **没有运行时控制通道**。

- 配置**不热加载**——`server set` 只写文件，运行中的服务不受影响
- `ServerEvents` 有 13 个回调，但**现有 CLI 文本输出不是完整事件接口**（无频谱、AEC 仅摘要、插件仅完成时输出）
- 因此 UI **无法**在运行时做：静音／切换监听／改 DSP／获取频谱

**结论：必须给上游 CLI 打补丁。** 绝不解析人类可读的 stdout 文本当协议（脆弱、会随上游文案改动而崩）。

---

## 1. 上游事实（已核实，2026-10-08）

| 项 | 值 |
|---|---|
| 仓库 | `MicYou-Dev/MicYou`（`LanRhyme/MicYou` 是同一仓库的重定向名，`gh` 会自动跟随） |
| 默认分支 | `master` |
| 补丁基线 commit | **`0c69fdd`**（2026-10-06，feat(installer) #361） |
| 许可证 | GPL-3.0 + MicYou Plugin Exception |
| 贡献指南 | `CONTRIBUTING.md` / `CONTRIBUTING_zh-cn.md` |
| 行为准则 | `CODE_OF_CONDUCT.md` |
| 提交信息格式 | **Conventional Commits**（`feat(cli): …` / `fix: …` / `docs: …`） |
| 无 PR 模板 | 是（无 `.github/PULL_REQUEST_TEMPLATE.md`） |
| 项目语言 | 中文项目（维护者中文，有中文贡献指南与爱发电赞助）→ **沟通用中文** |

**上游 PR 前的自检要求（原文）**：
- Android 调试构建通过：`./gradlew :composeApp:assembleDebug`
- 桌面构建通过：`cd tauri-app && bun run build`

**上游 CI**：`.github/workflows/development.yml`，每次推送与 PR 时构建
Android 调试 APK + **Windows / macOS / Linux 三平台 Tauri 安装包**。

> **⭐ 关键收益**：CI 在 GitHub 的干净机器上跑三平台构建 →
> **提 PR 就等于免费获得 Windows 构建验证**，
> 解决了本项目"MacBook Pro 上无 .NET/Windows SDK、无法本地验证 Windows"的死结。

**未发现重复劳动**：搜索 `repo:MicYou-Dev/MicYou json` / `cli control` / `headless api`
均无"CLI 运行时控制通道"相关 issue 或 PR。
（`#327 为cli/tui依赖Tauri的插件api提供纯后端实现` 说明上游正在推进 CLI/TUI 去 GUI 化——
**我们的补丁与其路线一致，属于顺向延伸，被接受概率较高**。）

---

## 2. 补丁范围（最小化是硬要求）

**只改必要的，能少动一行就少动一行。** 理由：上游昨天还在提交，
补丁碰得越多，上游改动时越容易冲突，维护成本越高。

**允许改动**：
- `tauri-app/crates/micyou-cli/src/**` — 主战场
- `tauri-app/crates/micyou-core/src/**` — **仅在确实必要时**（如事件回调需要暴露给 CLI）

**不得改动**：
- `tauri-app/src/**`（Vue 前端）
- `composeApp/**`（Android）
- `tauri-app/crates/micyou-protocol/**`（网络协议——改了会破坏与官方客户端的互通）
- 版本号、i18n 键集合（除非必须且符合贡献指南）

**接口设计要点**（详见 `docs/DESKTOP-PREWORK.md`）：
- **stdin/stdout 双向 JSON Lines**
- **版本化信封** + 请求 ID（保证前后兼容）
- **日志走 stderr**（绝不污染 stdout 的协议流）
- 高频事件（频谱）**节流**，避免刷爆管道
- 不改动网络协议与音频管线行为——纯控制面增强

**`mode_lock` 纪律**：GUI/CLI/TUI 共享锁文件，任一存活即互斥。
补丁**不得**强杀进程、不得删除锁文件。

---

## 3. 路径 A：提 PR 给上游

### 步骤

```
1. gh repo fork MicYou-Dev/MicYou --clone=false        # fork 到 TimmySheep/MicYou
2. 在 fork 上从上游 master 最新 commit 拉分支：
   feat/cli-jsonl-control-channel
3. 只改第 2 节允许的文件
4. 本地验证：
   cd tauri-app && cargo build -p micyou-cli       # 必须通过
   cd tauri-app && bun run build                    # 上游要求
   （如加了 Rust 测试：cargo test -p micyou-cli）
5. 提交：Conventional Commits，例：
   feat(cli): add JSON Lines control channel for headless frontends
6. push 分支 → gh pr create --repo MicYou-Dev/MicYou --base master
7. 等上游 CI（会自动跑三平台构建 + Android APK）
```

### PR 描述必须写清

- **问题**：CLI 无运行时控制通道，第三方前端/自动化脚本无法在运行时控制服务
- **方案**：stdin/stdout JSON Lines，版本化信封，日志走 stderr
- **兼容性**：默认关闭或向前兼容，不改变现有 CLI 文本输出与网络协议行为
- **测试**：本地构建通过 + CI 结果
- **未验证项如实标注**（例如未在真实 Windows 硬件上运行，仅 CI 构建通过）

### ⚠️ PR 红线（非常重要）

1. **这是纯技术贡献，不是推广。** PR 里**不得**出现 `MicWisp` 品牌、产品链接、宣传语、
   打赏链接、"我的客户端"之类内容。
2. **动机要如实但不推销**：可以写"为支持第三方前端/自动化脚本的运行时控制"这类
   客观使用场景（这有助于被接受，也诚实）。若维护者追问具体项目，**如实回答**，不隐瞒。
3. **不得声称代表官方**，不得暗示隶属、赞助或背书关系。
4. **不得夹带**与本功能无关的格式化、重命名、依赖升级等噪音改动。
5. **不得**删除或改动上游版权声明与许可证文件。

---

## 4. 路径 B：本地打补丁（PR 被拒或未合并时）

**补丁本身已经在手，不需要重做。** 只需改变"怎么用"：

### 在 MicWisp 仓库里怎么引用

**推荐**：`core/` 目录保存
- `core/upstream-base.txt` —— 钉死基线（`MicYou-Dev/MicYou@0c69fdd`，含日期）
- `core/patches/0001-cli-jsonl-control-channel.patch` —— 补丁文件
- `core/apply-patches.sh` —— 可复现的应用脚本（`git apply` 或 `patch -p1`）
- `core/BUILD.md` —— 拉取上游源码 → 应用补丁 → 构建 `micyou-cli` 的完整说明

**合规依据**：GPL 要求提供"完整对应源码"。**上游原始源码 + 补丁文件 + 构建说明**
是发行界通行做法（Debian/Fedora 皆如此），被广泛认可为满足 §6。
不必把上游源码 vendor 进来（那会带来同步负担），但**必须钉死基线 commit**。

### 若被拒绝的后续

- 把上游的拒绝理由**如实记录**到 `docs/DECISIONS.md`（追加，不改旧条目）
- 保留 fork 分支（万一以后想重提）
- 继续用本地补丁，**不因此停止 MicWisp 开发**

---

## 5. GPL 义务清单（无论走哪条路都必须做到）

| | 条款 | 要求 | 落地位置 |
|---|---|---|---|
| ① | §5a | **显著标注修改及日期** | 补丁文件头 + 被改文件顶部注释 |
| ② | §5b | 保留上游版权声明与许可证文本 | 不得删除任何现有声明 |
| ③ | §5c | 整体以 GPL-3.0 授权 | 仓库 LICENSE |
| ④ | §5d | 界面显示 Appropriate Legal Notices | MicWisp 关于页 |
| ⑤ | §6 | 提供完整对应源码 | 上游源码 + 本补丁 + 构建说明 |

**红线**：不得附加额外限制（如"禁止再分发本修改版"）；不得把修改版当官方 MicYou。

---

## 6. 完成标准（DoD）

- [ ] 补丁可**独立应用**到基线 `0c69fdd` 且**构建通过**（`cargo build -p micyou-cli`）
- [ ] `bun run build` 通过（上游硬性要求）
- [ ] 补丁文件在 `core/`，含基线钉死、应用脚本、构建说明
- [ ] GPL ①–⑤ 五条义务全部落地
- [ ] 路径 A：PR 已创建（附 URL）**或**已如实记录为何未创建
- [ ] 路径 B：若 PR 被拒/未合并，本地补丁仍可用，拒绝理由已记录到 `docs/DECISIONS.md`
- [ ] **未验证项明确标注**（尤其是 Windows：只能靠 CI，无本地硬件验证）

---

## 7. 边界

- 不许碰 iOS/iPadOS 线（`Sources/`、`Tests/`、`MicYou.xcodeproj/`、`docs/PRODUCT_SCOPE.md`）
- 不许动 Timmy 的 Windows 电脑
- 不用中文产品名（产品名只有英文 `MicWisp`）
- **不得**把 `MicWisp` 品牌带进上游 PR
