# Calendar Almanac Implementation Plan

> **For agentic workers:** Execute inline with superpowers:executing-plans. User authorized implementation with “do it”.

**Goal:** 离线黄历摘要及左侧详情卡。
**Architecture:** cnlunar 开发时生成年度 raw DEFLATE JSON；Swift 年度缓存查询；SwiftUI 界面通过小型 AppKit 桥管理附属面板。
**Tech Stack:** SwiftUI / AppKit / Foundation，Python 标准库及 vendored cnlunar。
**Spec:** docs/superpowers/specs/2026-11-25-calendar-almanac-design.md

## Constraints and review focus
- macOS 13；只在本地修改，不提交或发布 GitHub。
- 日期按用户日历时区取年月日，日级黄历固定中午；不提供实时当前时辰。
- 验证春节、闰月、立春、跨年、范围外、损坏资源、时区查询、屏幕边缘、关闭与置顶。

## Tasks
- [x] 数据：scripts/generate_calendar_almanac.py、scripts/vendor/cnlunar、Resources/Almanac。固定版本、算法、覆盖范围；生成全部有效日期，复核边界及稳定性。
- [x] 查询：Sources/xxMac/Models/CalendarAlmanac.swift，按年解压与限量缓存；Tests/xxMacTests/CalendarAlmanacTests.swift 验证实际数据、时区、坏文件、范围外。
- [x] 界面：CalendarAlmanacView.swift 摘要及详情，CalendarAlmanacPanel.swift 面板定位与窗口生命周期；CalendarFeatureView.swift 接入日期联动和弹窗关闭协调。定位算法单测覆盖屏幕边缘。
- [x] 文档与验证：中英 README、三语文案、配置目录说明和 MIT 许可；swift build、定向及完整 swift test、diff check；可用时原生界面验证。

## Execution notes
- 保留用户的 xxmac.json 与 lockjob.json；不创建提交、不安装应用。

- 覆盖决定：上游 lunarMonthData 实际只有 199 年，生成范围固定为 1901-02-19 至 2099-12-31；首年负索引日期不使用。
- 稳定性修正：上游未列入 thingsSort 的事项用 Unicode 次序作为并列排序，跨 PYTHONHASHSEED 输出一致；不更改上游规则和事项集合。
- 已验证：72,635 天连续覆盖及年度校验和；查询、定位定向测试通过；Python 跨种子回归通过；首次完整 Swift 测试 345 项通过。
- 独立审核修正：资源键始终使用公历及调用者时区，避免系统佛历年份；状态栏按钮 mouseDown 不走外部关闭，避免 mouseUp 重新打开。

- 最终验证：swift build 成功；完整 Swift 测试 347 项通过；Python 稳定性测试通过；全量 72,635 天连续性和 SHA-256 校验通过；原生详情渲染及面板打开、收起、再打开、父窗口关闭通过。未安装、替换或启动主应用，未进行 GitHub 操作。
