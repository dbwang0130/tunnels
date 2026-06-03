# Tunnels

> 一个原生 macOS 的 SSH 端口转发管理器。简单、稳定、免费。

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)

## 为什么做这个

市面上 SSH 隧道 GUI 工具大多是付费的——Termius 订阅、Secure Shellfish、Shuttle Pro……一个**最基本**的 "把 27017 转发到远端 mongo"，要么得开终端 `ssh -L`、要么得掏每年几十美元订阅费。

这种工具理应是**开源、免费、原生**的。Tunnels 就是这个目的：

- **纯 SwiftUI**：跟系统融为一体，启动快，不吃资源
- **零订阅**：自由、免费，永远开源
- **够用**：本地/远程端口转发、Keychain 存凭证、自动重连、菜单栏常驻——足以替代日常 SSH 隧道脚本

## 特性

- ⚡ **SSH 隧道管理**：本地 (-L) / 远程 (-R) 端口转发，多隧道并行
- 🔐 **Keychain 凭证**：密码 / OpenSSH 私钥（ed25519/RSA）安全存储
- 🔄 **保活 + 自动重连**：keepalive 心跳防断线，指数退避重连
- 📋 **规则即时生效**：已连接状态下增删改规则自动重应用
- 🪵 **实时日志**：每条隧道独立日志面板，500 行循环缓冲
- 🎨 **菜单栏常驻**：⚡ 状态图标、快捷启停
- 🌙 **深浅自适应**：跟随系统外观
- 💾 **SwiftData 持久化**：配置自动保存

## 截图

> 暂无（欢迎贡献）

## 安装

### 方式 1：下载 DMG

到 [Releases](https://github.com/dbwang0130/tunnels/releases) 下载最新的 `Tunnels-x.x.dmg`，挂载后拖到 Applications。

### 方式 2：从源码构建

需要 Xcode 16+ / macOS 14+。

```bash
git clone https://github.com/dbwang0130/tunnels.git
cd tunnels
open Tunnels.xcodeproj
# Cmd+R 运行
```

或命令行构建：

```bash
xcodebuild -project Tunnels.xcodeproj -scheme Tunnels \
  -configuration Release -derivedDataPath build/DerivedData build
```

## 使用

1. 启动 App，点左下角 `+` 新建隧道
2. 填入 SSH 服务器地址、用户名、密码或私钥
3. 添加转发规则（本地 -L：把本机端口映射到隧道另一端；远程 -R：反向）
4. 点右上角 ▶ 启动；菜单栏 ⚡ 图标会亮起表示运行中

## 路线图

- [ ] 动态 SOCKS5 代理（-D）
- [ ] SSH Agent 认证
- [ ] known_hosts 验证（目前 `acceptAnything`，不适合不可信网络）
- [ ] 跳板机（ProxyJump）
- [ ] iCloud 同步配置
- [ ] iOS / iPadOS 版本

## 贡献

欢迎 Issue 和 PR。

构建依赖（Xcode 自动管理 SPM，`Package.resolved` 在本地构建时生成）：
- [Citadel](https://github.com/orlandos-nl/Citadel) — Swift SSH 客户端
- [swift-nio](https://github.com/apple/swift-nio) / [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) — Apple 网络框架
- [swift-crypto](https://github.com/apple/swift-crypto) — Apple 加密库

## 协议

本项目采用 [MIT License](LICENSE)。

第三方依赖协议见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) 和 [NOTICE](NOTICE)。

---

> "Tools should be free."
