## PR Review — fix/windows-claude-launcher
**日期**: 2026-06-24
**Base**: main
**Target**: fix/windows-claude-launcher

### 概要
修复 Windows 上 claude 调起失败 + 异常传播导致连接崩溃 + 局域网 UX 改进。已提交代码有 6 个问题，工作区未提交修改已全部修复 —— 需 commit 后方可合并。

---

### 发现

#### 🔴 Critical（必须修改）

| 文件:行号 | 问题 | 建议 |
|---|---|---|
| `Main.kt:67-68` | **静默绑定拓宽** `val bindHost = if (host == "127.0.0.1" && ip != null) "0.0.0.0" else host`。当用户使用默认 `--host 127.0.0.1` 时，daemon 自动绑定到 `0.0.0.0` 暴露给全局域网。直连模式无加密无认证，任意局域网机器可达 `/v1/ws`。违反安全红线：静默绑定变更。 | 只绑定用户显式指定的 host。工作区未提交修改已修复（绑定 `host` 而非 `bindHost`，增加安全警告） |
| `DeviceSessions.kt:101` | `catch (e: Exception)` 吞掉 `CancellationException`，破坏 Kotlin 协程结构化并发。被取消的协程不会正确传播取消信号，导致资源泄漏和协程泄漏。 | 在 `catch` 前加 `if (e is CancellationException) throw e`。工作区未提交修改已修复 |
| `WsConnection.kt:58` | 同上，`catch (e: Exception)` 吞掉 `CancellationException`，破坏结构化并发。 | 同上。工作区未提交修改已修复 |
| `CLAUDE.md` | 新文件，包含个人 Windows 路径 (`C:\Users\Administrator\...`)、内网 IP (`10.242.219.124`, `10.1.1.115`)、个人计划任务配置。`.gitignore` 第 14 行明确排除 `CLAUDE.md`。 | 从分支移除：`git rm --cached CLAUDE.md` |
| `ClaudeLauncher.kt:60-61` | PATH 探测未遍历 `.cmd`/`.bat` 扩展名。只探测 `claude`（无扩展名），在 Windows 上找到的是 `#!` 脚本而非可执行的 `.cmd` wrapper，ProcessBuilder 无法执行（error 193）。核心修复不完整。 | 在 Windows PATH 探测中遍历 `claude.com`, `claude.exe`, `claude.bat`, `claude.cmd`。工作区未提交修改已添加 `winExts` 遍历 |

#### ⚠️ Caution（建议修改）

| 文件:行号 | 问题 | 建议 |
|---|---|---|
| `ClaudeLauncher.kt:65` | **死代码**：when 分支第 3 条 `isWindows && looksLikeScript(it) -> 2` 永远不可达。`looksLikeScript` 是 `looksLikePosixScript` 的纯别名，第 1 条 `looksLikePosixScript(it) -> 2` 已覆盖所有匹配。 | 删除死分支。工作区未提交修改已移除 |
| `ClaudeLauncher.kt:79` | **纯别名方法** `private fun looksLikeScript(p: Path): Boolean = looksLikePosixScript(p)`。无调用者差异，只增加维护负担。 | 删除此方法，统一使用 `looksLikePosixScript`。工作区未提交修改已删除 |
| `Main.kt:33-39` | `lanIp()` 未排除 ZeroTier (`zt*`)、Docker (`docker*`, `veth*`)、VPN tunnel (`tun*`, `tap*`) 等虚拟网卡。本机 ZeroTier IP `10.242.219.124` 会被误选为 LAN IP。 | 添加虚拟前缀过滤。工作区未提交修改已添加 `virtualPrefixes` 集合 |

#### 💡 Note（可选优化）

- **ClaudeLauncher 缺少 `resolveExecutable` 的单测**。现有 `ClaudeLauncherTest` 只覆盖 `buildArgs` 和 `wireName`。Windows PATH 探测、shebang 检测、排序优先级逻辑在重构时容易回归。非阻塞，建议后续补充。
- **`lanIp()` 的接口选择**：多个物理接口同时在线时（WiFi + 以太网），`sortedBy` 确保一致性但理论上仍可能选中非期望接口。对展示 QR 码给用户扫描的场景可接受——用户看到错误 IP 可自行纠正。
- **注释语言**：ClaudeLauncher.kt 的 KDoc 保持英文（正确），与项目风格一致。

#### ✅ Good（做得好的地方）

1. **ClaudeLauncher shebang 检测**：`readNBytes(2)` + `contentEquals(byteArrayOf('#', '!'))` 精确高效，不加载整个文件。
2. **异常封装修复方向正确**：将 `router.handle()` 异常转为 `PocketError` 发送给手机而非崩连接。
3. **isWindows 检测**：`System.getProperty("os.name").lowercase().contains("win")` 是 JVM 标准写法。
4. **工作区未提交修改质量高**：`CancellationException` re-throw、死代码清理、虚拟网卡过滤、绑定策略安全警告——每项修改都精准命中问题。

---

### 不应合并的文件

| 文件 | 理由 |
|---|---|
| `CLAUDE.md` | `.gitignore` 第 14 行已明确排除。包含个人路径、内网 IP、计划任务配置等本地信息 |

---

### 合并决策
**状态**: ❌ changes-requested

### 决策理由

当前分支 HEAD（commit `29ee588`）存在 5 个 Critical + 3 个 Caution。关键问题：

1. **安全红线**：Main.kt 静默将 loopback 绑定拓宽到 0.0.0.0，直连模式无加密无认证
2. **协程安全**：两处 try-catch 破坏结构化并发，吞掉 CancellationException
3. **核心修复不完整**：ClaudeLauncher PATH 探测不遍历 Windows 扩展名，Bug #1 修复失效
4. **代码质量**：when 死代码 + 别名代理方法
5. **合规**：CLAUDE.md 不应进入仓库

**好消息**：工作区未提交修改已全部修复。操作步骤：

```
git add daemon/src/main/kotlin/dev/ccpocket/daemon/Main.kt \
        daemon/src/main/kotlin/dev/ccpocket/daemon/claude/ClaudeLauncher.kt \
        daemon/src/main/kotlin/dev/ccpocket/daemon/relay/DeviceSessions.kt \
        daemon/src/main/kotlin/dev/ccpocket/daemon/server/WsConnection.kt
git rm --cached CLAUDE.md
git commit -m "fix(windows): complete claude.cmd resolution + safe local bind + structured concurrency"
```

提交后重新审查即可 ready-to-merge。
