# 输入法工具实现计划

**Goal:** 在 xxMac 原生整合输入法自动切换及提示。
**Architecture:** 纯规则模型与决策器、公开 TIS 输入源控制器、后台 AX 浏览器上下文提供器、主线程协调器、SwiftUI 设置页。
**Tech Stack:** Swift 5.9 / macOS 13+ / SwiftUI / AppKit / Carbon。
**Spec:** docs/superpowers/specs/2026-11-24-input-source-design.md

## 约束
不操作 GitHub 写入，不提交，不改已有 xxmac.json 和 lockjob.json；ref 仅作参考。用户要求直接执行，不再设置审批停点。

## 任务
- [x] 1. 实现 InputSourceModels.swift 与规则测试：InputSourcePolicy.resolve(settings:context:memory:)，域名边界、优先级、暂停和失效源。
- [x] 2. 扩展 InputSourceManager，新增浏览器 AX 观察和 InputSourceAutomationManager：事件驱动应用切换、来源验证、地址栏恢复、用户输入源记忆、快捷键与提示。覆盖状态与持久化测试。
- [x] 3. 新增 InputSourceSettingsView，接入工具侧栏、启动生命周期、启动器、配置导入导出/迁移、三语资源和 README。
- [x] 4. swift build、定向与完整 swift test，独立审查并修复实质问题。

## Review Focus
快速切换后的过期 AX 结果；自动切换污染记忆；地址栏和网页输入框混淆；停用后残留监听；导入旧配置和不可用输入源。

## 执行记录
- 已下载并阅读参考实现。采用公开 API 独立实现，避免复制 GPL 源码和引入私有输入法选择器。

- 规则与运行时新增 24 项测试，完整 `swift test` 共 322 项通过。系统输入源枚举进行了只读真机验证。
- 独立审查发现的同浏览器过期查询、地址栏祖先边界、手动输入法恢复、自动标记消费、锁屏/睡眠分别暂停、录制单会话与失焦释放、提示等待输入源确认、备份预校验均已修复。关键状态转换均增加回归测试；地址栏和手动记忆问题先复现失败后通过。
- 改正了网站/地址栏记忆测试的前台应用注入，避免提前返回导致虚假通过。
- `git diff --check`、三语资源和 Info.plist 的 `plutil -lint` 通过。
- `INSTALL_TO_APPLICATIONS=0 bash bundle_app.sh </dev/null` 成功；主程序、小组件及嵌入框架签名校验通过。未覆盖 /Applications，未提交或推送。
- Chrome/Edge/Safari 实际前台切换、地址栏焦点及第三方输入法内部模式兼容性尚未进行完整交互验收。
