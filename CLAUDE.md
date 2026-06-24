# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库概要

手机端远程操控电脑上的 `claude` CLI — 新建/恢复会话、浏览工作目录、实时流式输出、远程批准工具权限。流量经零知识中继（zero-knowledge relay）转发，端到端加密（P-256 ECDH + AES-256-GCM）。Kotlin 纯净室实现，MIT 许可。

## 模块

| 模块 | 职责 | 技术栈 |
|---|---|---|
| `:protocol` | 共享线路协议（`pocket/*` frames）、E2E 加密 | Kotlin Multiplatform + kotlinx.serialization + cryptography-kotlin |
| `:daemon` | 电脑端守护进程，驱动 `claude` CLI，外连中继 | Kotlin/JVM + Ktor |
| `:relay` | 云端 broker：设备配对、密文路由、限流、推送 | Kotlin/JVM + Ktor + SQLite |
| `:mobile` | CC Pocket App（手机端） | Compose Multiplatform（Android / iOS / desktop） |

## 常用命令

```bash
# 全部单元测试（protocol + daemon + relay）
./gradlew test

# 单模块测试
./gradlew :protocol:allTests        # protocol 跨平台测试（JVM + Android + iOS targets）
./gradlew :daemon:test              # daemon JVM 测试
./gradlew :relay:test               # relay JVM 测试

# 全量编译 + 测试
./gradlew build

# 构建 daemon 启动器
./gradlew :daemon:installDist
# 产物在 daemon/build/install/cc-pocket-daemon/bin/cc-pocket-daemon

# 本地开发（不走 relay）—— daemon 在 127.0.0.1:8765 起 WebSocket
./gradlew :daemon:run --args="run --local --host 0.0.0.0"
# Windows 上需指定 claude.cmd（或设 CC_POCKET_CLAUDE_BIN 环境变量）：
./gradlew :daemon:run --args="run --local --host 0.0.0.0 --claude-bin $env:LOCALAPPDATA\\npm\\claude.cmd"

# 经 relay 模式
./gradlew :daemon:run --args="run --relay wss://pocket.ark-nexus.cc"

# test-client 驱动（另开终端）：
daemon/build/install/cc-pocket-daemon/bin/cc-pocket-daemon test-client

# 配对手机（需要 daemon 已在运行）
daemon/build/install/cc-pocket-daemon/bin/cc-pocket-daemon pair

# 构建 Android APK
./gradlew :mobile:composeApp:assembleDebug

# 构建自带 JRE 的独立 App（macOS/Windows/Linux，由 CI release 脚本调用）
./gradlew :daemon:packageDaemon

# 桌面 Compose 客户端（需要图形界面）
./gradlew :mobile:composeApp:run
```

## 架构总览

### 数据流

```
phone (Compose Multiplatform) ──wss·密文──▶ relay (zero-knowledge broker)
relay ──wss·密文──▶ daemon (你的电脑)
daemon ──stdio──▶ claude CLI (子进程, stream-json)
```

- **relay 模式**（生产路径）：手机 ↔ relay ↔ daemon，全程 E2E 加密，relay 只看到密文
- **直连模式**（`--local`）：手机/桌面客户端直连 daemon WebSocket，仅用于本地开发调试，无 E2E 加密

### 协议层

所有消息包裹在 `Envelope(id, ts, to: Route, body: Frame)` 中，JSON 序列化，discriminator `"t"`。

**Frame 方向类型：**
- `ToDaemon` — 手机→daemon：`ListDirectories`、`OpenSession`、`SendPrompt`、`PermissionVerdict`、`SwitchMode`、`CancelTurn`、`CloseSession`、`AudioChunk` 等
- `ToPhone` — daemon→手机：`SessionLive`、`AssistantChunk`（流式文本/thinking）、`ToolEvent`、`PermissionAsk`、`TurnDone`、`PocketError`、`ConvoHistory`、`BackgroundJobs`、`CommandList`、`Transcript` 等
- 控制面帧（`to=RELAY`）：`DaemonHello`/`Challenge`/`DaemonAuth`（daemon 登录）、`DeviceHello`（设备登录）、`Attached`/`AuthError`、`PairBegin`/`PairTicket`/`DevicePaired`、`PeerPresence`、`Ping`/`Pong`（心跳）

**E2E 加密（`protocol/.../e2e/`）：**
- 握手：Noise-KK 风格 4-DH + PSK（双方已知对方 P-256 静态公钥，各自贡献临时密钥提供前向安全性）
- 传输：AES-256-GCM，8 字节 BE counter 作 nonce，严格递增防重放/乱序
- relay 只转发二进制密文帧 `[idLen:1][deviceId][E2E payload]`，不解密

### Daemon 启动流程

```
Main.kt:run
  ├─ ClaudeLauncher.resolveExecutable()    # 解析 claude 二进制路径
  ├─ DaemonCore(exe)                       # SessionRegistry + DirectoryService + TranscribeService + RequestRouter
  ├─ Identity.loadOrCreate()               # 加载/生成 ~/.cc-pocket/identity.json（Ed25519 + P-256 密钥对）
  │   └─ accountId = base32(sha256(ed25519Pub))
  ├─ RelayClient(relay, identity, core)    # 外拨 WSS 到 relay，指数退避重连
  │   ├─ authenticate(): DaemonHello → Challenge → DaemonAuth → Attached
  │   ├─ 数据面：二进制帧 → DeviceSessions.onFrame() → E2E 解密 → RequestRouter.handle()
  │   ├─ 控制面：配对票据、设备上下线、Ping/Pong 心跳（20s 间隔，45s 死线）
  │   └─ 空闲回收：90s 无设备连接的会话
  └─ PairLoopback(port=8799)               # HTTP 回环，供 `pair` CLI 子命令使用
```

### 会话生命周期

```
OpenSession(workdir, resumeId?, model, mode, effort)
  → SessionRegistry.open()
  → Conversation: 启动 claude 子进程
    → ClaudeProcess: claude -p --output-format stream-json --input-format stream-json --permission-prompt-tool stdio ...
    → StreamParser: 解析 stdout stream-json 行
    → PermissionBridge: 工具授权弹窗映射到 PermissionAsk/Verdict
    → BackgroundJobRegistry: 跟踪后台 shell/子 agent
  → SessionLive 发送到手机

SendPrompt → Conversation.sendPrompt() → 写到 claude stdin
  → AssistantChunk + ToolEvent 流式推送到手机
  → TurnDone 时回传 token 用量

SwitchMode / SwitchModel / SwitchEffort
  → 停止当前 claude 进程，用 --resume + 新参数重启
  → SessionLive 重发

CloseSession → 杀 claude 进程树，清理注册表
```

### 关键文件速查

**protocol：** `src/commonMain/kotlin/dev/ccpocket/protocol/Messages.kt`（全部消息类型）、`Envelope.kt`（传输包装）、`e2e/E2ESession.kt`（Noise 握手）、`e2e/Wire.kt`（二进制帧格式）

**daemon 核心链路：** `Main.kt` → `DaemonCore.kt` → `relay/RelayClient.kt`（外连中继）/ `server/DaemonServer.kt`（直连模式）→ `server/RequestRouter.kt`（帧分发）→ `session/SessionRegistry.kt` → `conversation/Conversation.kt` → `claude/ClaudeProcess.kt`（子进程管理）、`claude/StreamParser.kt`（stdout 解析）、`claude/PermissionBridge.kt`（权限桥）

**relay：** `Main.kt` → `RelayServer.kt`（Ktor CIO 路由）→ `Broker.kt`（内存路由表）→ `pairing/PairingService.kt`（配对票据）、`auth/DaemonAuthenticator.kt`（Ed25519 签名挑战）、`auth/DeviceAuthenticator.kt`（bearer token）

**mobile 共享层：** `ui/App.kt`（导航/状态）、`net/RelayE2EConnection.kt`（relay 模式 WSS + E2E）、`net/RelayConnection.kt`（直连 WS）、`data/PocketRepository.kt`（中心状态管理）、`pairing/Pairing.kt`（QR 扫描 + 票据兑换）

## 技术栈要点

- **JDK 17**（Temurin），Gradle 8.x wrapper，`gradle.properties` 中 `org.gradle.java.home` 锁定 JDK 路径
- **Kotlin 2.1.21** + kotlinx.serialization 1.7.3 + kotlinx.coroutines 1.9.0
- **Ktor 3.1.3**（CIO 引擎，daemon 和 relay 都用）
- **Clikt 5.0.1**（daemon CLI 参数解析）
- **JUnit Jupiter 5.11.3**（测试框架，通过 `kotlin.test` API 使用）
- **cryptography-kotlin 0.4.0**（跨平台 E2E 加密，固定此版本因为 0.5.0+ 的 klib ABI 不兼容 Kotlin 2.1.21）
- **Compose Multiplatform 1.7.3**（mobile UI）
- Android AGP 8.7.3，compileSdk 35，minSdk 26

## 测试

测试使用 `kotlin.test` API + JUnit Jupiter 平台 runner。daemon 测试需要 `testRuntimeOnly("org.junit.platform:junit-platform-launcher")`。

- `:protocol` — 跨平台测试（`commonTest`）：序列化往返（9 个 case，覆盖 discriminator/默认值/null/未知 key）、E2E 加密/握手（P-256 ECDH 对称性、HKDF 确定性、AEAD 篡改检测、MITM 检测、relay 密文透明性、重放拒绝）
- `:daemon` — StreamParser（stream-json 解析 8 个 case）、PermissionBridge（授权回环）、BackgroundJobRegistry（后台任务生命周期）、ClaudeLauncher（参数构建）、TranscriptScanner/SlashCommandScanner/ProjectPaths
- `:relay` — Broker（路由 + 离线推送 + 配对码单次有效）、PushService

## CI/CD

- **`release.yml`**（手动触发，需要 version 参数）：构建 macOS（arm64 + x86_64）、Windows（x86_64）、Linux（x86_64）daemon 独立包 + Android APK，发布到 GitHub Releases
- **`ios-release.yml`**（手动触发，需要 marketing_version）：在 macos-26 runner 上用 Xcode 构建 iOS App，上传到 App Store Connect
- 发布脚本在 `scripts/release-*.{sh,ps1}`，jpackage 打包，macOS 带签名公证

## 本机开发环境

- JDK 17（Temurin-17.0.17）
- Gradle 8.x wrapper（可能被墙，可手动下载放 `~/.gradle/wrapper/dists/`）
- `claude` CLI 已装（npm 全局安装）
- **Windows `gradle.properties`** 中 `org.gradle.java.home` 指向 macOS 的 `/opt/homebrew/opt/openjdk@17`（Homebrew），Windows 上需注释或修改此行

## 本机 daemon 配置

已安装为 Windows 计划任务（登录自启）：

```
程序: C:\Users\Administrator\AppData\Local\Programs\cc-pocket-daemon\cc-pocket-daemon.exe
参数: run --relay wss://pocket.ark-nexus.cc
任务名: CC Pocket Daemon
触发: 登录时
```

环境变量（已永久设）：
```
CC_POCKET_CLAUDE_BIN=C:\Users\Administrator\AppData\Roaming\npm\claude.cmd
```

## 我们提交的 PR

**https://github.com/heypandax/cc-pocket/pull/2** (branch: `fix/windows-claude-launcher`)

### Bug 1: Windows 上 claude 可执行文件解析错误（ClaudeLauncher.kt）

npm 安装的 `claude` 是 POSIX `#!/bin/sh` shell 脚本，Java 的 `ProcessBuilder` 在 Windows 上无法执行（CreateProcess error 193）。手机打开会话时 daemon 调起 claude 失败，异常传播导致 relay WebSocket 连接崩溃重连。

**修复**: Windows 上优先选 `.cmd`/`.bat` wrapper。

### Bug 2: 错误传播导致传输层崩溃（DeviceSessions.kt + WsConnection.kt）

`router.handle()` 抛异常直接波及 WebSocket 连接。relay 模式和直连模式都受影响。

**修复**: try-catch 包裹，发 `PocketError` 给手机而非崩连接。

### 改进: 局域网模式自动获取 IP（Main.kt）

`--local` 原来输出 `ws://0.0.0.0` 无法用。修复后自动检测局域网 IP、打印可用 URL 和终端二维码。

## 排查过程中的关键发现

1. **ZeroTier 虚拟网卡**: 本机有 ZeroTier（IP 10.242.219.124），物理 WiFi IP 为 10.1.1.115。ZeroTier UDP 隧道不稳定是断连主因之一，推荐 relay 模式（走物理网卡出互联网，不经过 ZeroTier）。

2. **Relay 模式 vs 直连模式**: relay 模式有心跳保活和推送通知，移动端体验更好。直连模式（`--local`）无 E2E 加密、无守护心跳，适合局域网开发调试。

3. **claude 环境变量陷阱（Windows）**: Java 调 `claude`（不带扩展名）会拿到 POSIX 脚本而非可执行文件。必须设 `CC_POCKET_CLAUDE_BIN` 指向 `.cmd`。

## 技术注意事项

- **cryptography-kotlin 0.4.0**（固定此版本因为 0.5.0+ 的 klib ABI 不兼容 Kotlin 2.1.21），不支持 `-optimal` umbrella provider，需按目标显式指定：JDK provider（JVM/Android）、OpenSSL3 prebuilt（iOS）。
- **relay 心跳：** daemon 侧每 20s 发 Ping，45s 无 Pong 触发重连。会话空闲 90s 自动回收。
- **jpackage** 不能交叉构建，打包的 JRE 与构建机 OS/arch 必须匹配（CI 上三个 OS job 并行）。

## 开发工作流

Git 远程：`fork`=自己的fork, `origin`=上游原仓库。本地 skip-worktree 保护 `.gitignore` 和 `gradle.properties`。日常同步：`git fetch origin && git checkout main && git merge origin/main`。开新 PR 从 main 切分支推到 fork。当前活跃分支：`fix/windows-claude-launcher`（PR #2，已推送等 review）。

## 上游 PR #2 反馈

heypandax 2026-06-24 提 6 项全部已修复：PATH 扩展名探测、bind 安全警告、CancellationException rethrow、lanIp 虚拟网卡过滤、CLAUDE.md 移除、sortedBy 清理。

## 参考项目 K9i-0/ccpocket

TypeScript+Flutter，MIT，功能更成熟。Bridge 直连+双 agent。借鉴：Git 集成、worktree、增量同步、离线队列、mDNS、UI 气泡/权限/多面板。我们优势：E2E relay、天然跨网络、Kotlin 类型安全。
