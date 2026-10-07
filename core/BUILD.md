# 上游 CLI 控制通道补丁与构建

本目录保存桌面端所需的上游 CLI 补丁，不 vendoring 上游代码。完整对应源码由固定上游 commit、此目录的原创 bridge 源码和补丁共同组成。上游仓库 `upstream-micyou/` 在本项目中只读；不得在该目录直接应用补丁。

## 基线与内容

- 上游：`https://github.com/MicYou-Dev/MicYou.git`
- 固定基线：见 [`upstream-base.txt`](upstream-base.txt)
- 补丁：[`patches/0001-cli-jsonl-control-channel.patch`](patches/0001-cli-jsonl-control-channel.patch)
- 新增原创 CLI 模块：[`patches/micyou-cli-jsonl/src/jsonl.rs`](patches/micyou-cli-jsonl/src/jsonl.rs)
- 应用入口：`sh core/apply-patches.sh /path/to/writable/upstream-micyou`

请在单独的可写上游 clone/worktree 上应用。脚本拒绝错误 commit、脏工作区及已存在的目标文件；不会强杀进程或触碰 `mode.lock`。补丁只更改 `tauri-app/crates/micyou-cli/`，不改网络协议、音频核心或 Android 代码。

## 从干净 checkout 重现

```sh
git clone https://github.com/MicYou-Dev/MicYou.git upstream-micyou-build
git -C upstream-micyou-build checkout 0c69fdd4b0c26553bd4a74aed38a808f0fce621a
sh core/apply-patches.sh "$PWD/upstream-micyou-build"
cd upstream-micyou-build/tauri-app
cargo test -p micyou-cli
cargo build -p micyou-cli --release
bun run build
```

桌面 bundle 应打包此构建产物作为独占 sidecar，并按目标平台构建。不要以读取现有 CLI 文本输出作为兼容回退。

## 当前验证状态

- 固定基线与补丁应用上下文已针对只读参考 checkout 做 `git apply --check`（检查模式，不修改 checkout）。
- 本任务尚未在可写独立上游 checkout 运行 Rust 编译、Rust 测试或 `bun run build`；因此这些构建均**未验证**。
- macOS 客户端真实音频端到端及 Windows 构建/运行还需分别按各平台验收。当前 Mac 没有 .NET SDK，不得改动用户 Windows 电脑。

## GPL-3.0 对应源码与上游 PR

桌面应用采用 GPL-3.0。分发时须附完整许可证文本、保留上游版权/许可，About 页面展示 Appropriate Legal Notices，并向接收者提供固定上游源码、补丁和构建说明。应用补丁的上游文件已加修改日期注释，新模块有 GPL-3.0 标识。

该补丁亦按项目上游贡献规则准备为纯技术贡献：PR 标题/提交信息使用 Conventional Commits，PR 不包含 MicWisp 品牌、产品链接或推广内容。创建公开 fork/分支并提交 PR 属于对外发布动作；在构建验收及用户明确批准前，不会推送或创建 PR。
