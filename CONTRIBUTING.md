# Contributing to Tunnels

Thanks for considering a contribution! Here's the short version.

## 报 Bug / 请求功能

[开 Issue](../../issues/new)，附上：

- macOS 版本、Xcode 版本（若构建相关）
- 复现步骤（最小化）
- 期望行为 vs 实际行为
- 如果是崩溃，附 Console.app 中的 crash log 片段

## 提交代码

1. Fork → 新建 feature 分支：`git checkout -b feat/your-feature`
2. 写代码 + 测试。代码风格跟项目保持一致：
   - SwiftUI、`@Observable`、`@MainActor` 用现代写法
   - Actor 隔离严格遵守
   - 不要引入新 SPM 依赖除非真的有必要
3. 提交：commit message 用中文或英文都行，**遵循 Conventional Commits**：
   - `feat: 添加 SOCKS5 动态转发`
   - `fix: 修复 keepalive 在 sleep 后不恢复`
   - `refactor: ...` `docs: ...` `test: ...`
4. `git push` → 在 GitHub 开 PR
5. PR 描述里说清楚**为什么改**，不只是改了什么

## 本地构建

需要 Xcode 16+ / macOS 13+：

```bash
git clone <your-fork>
cd Tunnels
open Tunnels.xcodeproj  # 或 xcodebuild
```

App Icon 是脚本生成的，改设计请改 `Tools/gen_app_icon.swift` 再跑 `swift Tools/gen_app_icon.swift`。

## 行为准则

互相尊重就行。不接受人身攻击、骚扰、歧视言论。

## License

提交代码即视为同意按本项目的 [MIT License](LICENSE) 发布。
