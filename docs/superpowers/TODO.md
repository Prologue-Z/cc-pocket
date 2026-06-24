# TODO — cc-pocket 改进计划

## K9i-0/ccpocket 参考学习

- [ ] Git 操作集成 — daemon 侧执行 git，手机端 stage/commit/push/branch UI
- [ ] Git worktree 会话隔离
- [ ] 历史增量同步 (history delta + seq)
- [ ] 离线消息队列
- [ ] LLM 自动会话命名
- [ ] mDNS 局域网发现
- [ ] 调试诊断包导出 (debug bundle)
- [ ] 移动端测试体系 (Mock + 录制回放)

## UI 改进（对比 K9i-0/ccpocket 分析）

- [ ] 导航框架 — Navigation 栈 + 过渡动画，修复 Android 返回键
- [ ] 会话卡片升级 — 信息密度：最后消息、git 分支、内联权限审批
- [ ] 消息气泡重设计 — 不对称圆角 + 双向区分色 + 流式光标动画
- [ ] 自适应布局 — 平板/折叠屏分栏 (WindowSizeClass)
- [ ] 输入框增强 — @文件提及、prompt 历史

## 新功能

- [ ] Double-Escape 回退模式 — 长按停止按钮 → 回合列表 → 回退到指定回合


重大bug
发现手机端发消息会导致电脑上的会话复制了好几个

我们暂时只针对bug，daemon的修复如果没有解决问题就先删掉，因为我不确定会不会带来新的问题。我们不是仓库的upstream，只是想解决几个bug
然后把那几个chore合并一下，还有我们自己dev分支以后用中文写message。

bat的退出写好一点，别还得手动去任务管理器关闭


