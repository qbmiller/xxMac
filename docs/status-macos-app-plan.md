# Status Mac macOS 监控应用计划

## 1. 产品定位

Status Mac 是一个面向个人用户的 macOS 状态、睡眠与使用行为诊断工具。

它要优先回答几个具体问题：

- 昨晚盖上盖后，Mac 是真的进入睡眠，还是一直在工作？
- 夜间有没有被唤醒？是什么原因唤醒？
- 哪些 App 使用时间最长？用户具体停留在哪些 App？
- CPU、内存、电池、网络、磁盘有没有异常？
- 哪些进程阻止了睡眠或导致后台耗电？

产品定位应避免变成员工监控工具。默认策略是本地存储、用户可见、可暂停、可排除 App、敏感信息默认不采集。

## 2. 应用形态

推荐形态：

- 菜单栏常驻 App
- 原生 macOS 主窗口
- 本地 SQLite 数据库
- 可选 LaunchAgent 后台采集
- 隐私优先的权限分级

主窗口建议采用 `NavigationSplitView`：

- 总览
- 时间线
- 睡眠诊断
- 系统监控
- App 使用
- 异常提醒
- 设置

菜单栏展示轻量状态：

- CPU
- 内存压力
- 电池
- 网络速率
- 当前是否有进程阻止睡眠
- 快捷入口：打开主窗口、暂停监控、查看昨晚报告、设置

## 3. 功能分类

### 3.1 系统活动日志

目标：还原 Mac 的关键系统事件时间线。

功能点：

- 睡眠事件
  - 合盖睡眠
  - 手动睡眠
  - 自动睡眠
  - DarkWake
  - Power Nap
  - 睡眠失败
- 唤醒事件
  - 开盖唤醒
  - 电源按钮唤醒
  - RTC 定时唤醒
  - 网络唤醒
  - USB / 蓝牙设备唤醒
  - 电源适配器事件唤醒
- 屏幕与会话
  - 锁屏
  - 解锁
  - 屏幕关闭
  - 屏幕亮起
  - 屏保开始 / 结束
- 电源事件
  - 接入电源
  - 断开电源
  - 电池电量变化
  - 充电状态变化
- 系统生命周期
  - 启动
  - 重启
  - 注销
  - 异常关机
  - 崩溃重启

可用系统命令：

```bash
pmset -g log
pmset -g assertions
pmset -g sched
log show --predicate 'eventMessage contains "Wake"'
log show --predicate 'eventMessage contains "Sleep"'
last
```

输出示例：

```text
22:41 合盖
22:42 进入睡眠
03:18 DarkWake，原因：网络 / 电源管理
03:19 回到睡眠
08:12 开盖唤醒
08:13 用户解锁
```

### 3.2 睡眠诊断

目标：明确判断“昨晚是否真的睡了”。

功能点：

- 昨晚睡眠报告
  - 入睡时间
  - 唤醒时间
  - 总睡眠时长
  - 实际深睡时长
  - DarkWake 次数
  - 夜间唤醒次数
  - 最长连续睡眠时长
- 睡眠质量判断
  - 正常
  - 轻微异常
  - 明显异常
  - 整晚未休眠
- 睡眠阻止分析
  - 阻止系统睡眠的进程
  - 阻止显示器睡眠的进程
  - 音频播放阻止
  - 网络共享阻止
  - 外接显示器影响
  - 蓝牙 / USB 设备影响
- 唤醒原因解释
  - Lid Open
  - Power Button
  - RTC
  - Network
  - USB
  - Bluetooth
  - Power Adapter

核心判断逻辑：

```text
如果夜间存在长时间 Awake 区间，并且没有 Sleep 事件闭合，则判断为未正常休眠。
如果频繁出现 DarkWake，但每次持续时间短，可判断为轻微异常或系统维护。
如果某个进程持续出现在 assertions 中，应标记为阻止睡眠嫌疑。
```

### 3.3 实时系统监控

目标：提供当前系统健康状态和趋势。

功能点：

- CPU
  - 总占用率
  - 每核心占用率
  - 负载均值
  - Top CPU 进程
  - 长时间高占用提醒
- 内存
  - 已用内存
  - 可用内存
  - 压缩内存
  - Swap 使用
  - Memory Pressure
  - Top 内存进程
- 磁盘
  - 可用空间
  - 读写速度
  - Top I/O 进程
  - 磁盘空间预警
- 网络
  - 上传速度
  - 下载速度
  - 当前 Wi-Fi
  - 当前 IP
  - 网络切换记录
  - 异常夜间流量提醒
- 电池
  - 电量
  - 充电状态
  - 电源来源
  - 预计剩余时间
  - 循环次数
  - 电池健康
  - 合盖后掉电分析
- 温度与风扇
  - Intel Mac 可通过 SMC 方案实现
  - Apple Silicon 受系统限制，第一版不作为核心功能

### 3.4 App 使用日志

目标：记录用户停留在哪些 App，以及每个 App 的使用时间。

功能点：

- 前台 App 记录
  - App 名称
  - Bundle ID
  - 开始时间
  - 结束时间
  - 持续时间
- App 切换时间线
- 今日 Top Apps
- 每小时 App 分布
- 分类统计
  - 开发
  - 浏览器
  - 通讯
  - 设计
  - 娱乐
  - 系统工具
- 专注分析
  - 最长连续停留 App
  - App 切换频率
  - 打断次数
  - 深度工作时间段
- 可选窗口标题
  - 默认关闭
  - 用户明确开启后才记录
  - 支持指定 App 禁止记录标题

权限：

- 记录前台 App：Accessibility 权限
- 读取部分窗口标题：可能需要 Accessibility 或 Screen Recording 权限

隐私策略：

- 默认只记录 App 名和 Bundle ID
- 默认不记录窗口标题
- 默认不截图
- 不上传数据
- 提供暂停记录
- 提供忽略 App 列表
- 提供数据清理

### 3.5 异常检测与提醒

目标：从数据里主动发现问题。

功能点：

- 睡眠异常
  - 整晚未睡眠
  - 夜间唤醒次数过多
  - 某进程阻止睡眠超过指定时间
  - 合盖后电量异常下降
- 性能异常
  - CPU 长时间高占用
  - 内存压力过高
  - Swap 快速增长
  - 磁盘 I/O 异常
- 电池异常
  - 充电异常慢
  - 电池健康下降
  - 循环次数过高
  - 后台高耗电
- 存储异常
  - 可用空间低
  - 某目录快速增长
  - 日志文件异常变大
- 网络异常
  - 夜间大量上传 / 下载
  - Wi-Fi 频繁断开
  - VPN 状态变化

提醒方式：

- 菜单栏标记
- App 内通知中心
- macOS 本地通知
- 日报中汇总

### 3.6 报告

目标：把监控数据变成用户能直接理解的结论。

日报：

- 今日开机时间
- 今日活跃时间
- 今日空闲时间
- 昨晚睡眠结论
- Top Apps
- CPU / 内存异常
- 电池消耗
- 网络流量
- 关键异常事件

周报：

- 每日活跃时长
- 每日睡眠质量
- 高频 App
- 专注趋势
- 电池趋势
- 系统异常趋势

导出：

- Markdown
- CSV
- JSON
- 后续可支持 PDF

## 4. 权限分级

### 4.1 基础模式

不强依赖敏感权限。

能力：

- CPU
- 内存
- 磁盘
- 网络
- 电池
- 基础系统状态

### 4.2 活动模式

需要 Accessibility 权限。

能力：

- 前台 App 记录
- App 使用时间统计
- App 切换时间线
- 可选窗口标题

### 4.3 诊断模式

可能需要 Full Disk Access。

能力：

- 深度系统日志读取
- 更完整睡眠诊断
- 历史日志回溯
- 更详细异常分析

## 5. 数据模型

建议使用 SQLite。

### 5.1 system_events

```sql
CREATE TABLE system_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  occurred_at TEXT NOT NULL,
  type TEXT NOT NULL,
  source TEXT,
  title TEXT NOT NULL,
  detail TEXT,
  raw_payload TEXT
);
```

事件类型：

```text
sleep
wake
dark_wake
lock
unlock
screen_on
screen_off
power_connected
power_disconnected
boot
shutdown
reboot
```

### 5.2 app_sessions

```sql
CREATE TABLE app_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  app_name TEXT NOT NULL,
  bundle_id TEXT NOT NULL,
  window_title TEXT,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  duration_seconds INTEGER
);
```

### 5.3 metrics_samples

```sql
CREATE TABLE metrics_samples (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sampled_at TEXT NOT NULL,
  cpu_percent REAL,
  memory_used_bytes INTEGER,
  memory_pressure TEXT,
  swap_used_bytes INTEGER,
  disk_read_bytes_per_sec INTEGER,
  disk_write_bytes_per_sec INTEGER,
  network_up_bytes_per_sec INTEGER,
  network_down_bytes_per_sec INTEGER,
  battery_percent REAL,
  power_source TEXT
);
```

### 5.4 sleep_reports

```sql
CREATE TABLE sleep_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  sleep_started_at TEXT,
  wake_ended_at TEXT,
  total_sleep_seconds INTEGER,
  deep_sleep_seconds INTEGER,
  awake_seconds INTEGER,
  dark_wake_count INTEGER,
  wake_count INTEGER,
  quality TEXT NOT NULL,
  summary TEXT
);
```

### 5.5 alerts

```sql
CREATE TABLE alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  occurred_at TEXT NOT NULL,
  severity TEXT NOT NULL,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  related_process TEXT,
  resolved_at TEXT
);
```

## 6. 技术路线

### 6.1 推荐技术栈

- Swift
- SwiftUI
- AppKit bridge
- MenuBarExtra 或 NSStatusItem
- SQLite
- Combine / async-await
- UserNotifications

### 6.2 核心模块

```text
StatusMacApp
├── MenuBar
├── Dashboard
├── Collectors
│   ├── PowerLogCollector
│   ├── SystemMetricsCollector
│   ├── AppActivityCollector
│   └── SleepAssertionCollector
├── Analyzer
│   ├── SleepAnalyzer
│   ├── AlertEngine
│   └── DailyReportBuilder
├── Storage
│   ├── Database
│   ├── Repositories
│   └── RetentionPolicy
└── Settings
```

### 6.3 采集频率建议

```text
前台 App：切换时记录
CPU / 内存：5 秒到 15 秒
网络速率：1 秒到 5 秒
电池：30 秒到 60 秒
睡眠日志：启动时、唤醒后、每天生成报告时解析
assertions：30 秒到 60 秒
```

需要避免过度采样，否则监控工具本身会耗电。

## 7. MVP 范围

第一版只做最有用、风险最低的功能。

### 7.1 MVP 必做

- 菜单栏状态
  - CPU
  - 内存压力
  - 电池
  - 网络速率
- 主窗口
  - 总览
  - 时间线
  - 睡眠诊断
  - App 使用
  - 设置
- 睡眠报告
  - 昨晚是否睡眠
  - 入睡时间
  - 唤醒时间
  - 唤醒次数
  - DarkWake 次数
  - 基础唤醒原因
- App 使用统计
  - 前台 App 记录
  - 今日 Top Apps
  - App 切换时间线
- 本地数据库
  - SQLite 存储
  - 7 / 30 / 90 天数据保留
- 隐私控制
  - 暂停记录
  - 忽略 App
  - 不记录窗口标题
  - 清空数据

### 7.2 MVP 暂不做

- 截图
- 云同步
- 进程级网络流量
- 温度 / 风扇
- AI 报告
- PDF 导出
- 多设备汇总

## 8. 里程碑

### Milestone 1：原型

目标：验证系统数据可采集。

任务：

- 创建 SwiftUI 菜单栏 App
- 显示 CPU / 内存 / 电池基础状态
- 解析 `pmset -g log`
- 生成昨晚睡眠摘要
- 记录前台 App 切换

验收：

- 菜单栏能显示实时状态
- 主窗口能看到睡眠时间线
- App 使用记录能落库

### Milestone 2：MVP

目标：形成可日常使用版本。

任务：

- SQLite 数据层
- 时间线页面
- 睡眠诊断页面
- App 使用页面
- 设置页面
- 权限引导
- 数据保留策略

验收：

- 连续运行 24 小时无明显耗电问题
- 能准确生成昨晚睡眠报告
- 能统计今日 App 使用排行

### Milestone 3：异常检测

目标：从记录工具升级为诊断工具。

任务：

- AlertEngine
- 睡眠异常规则
- CPU / 内存异常规则
- 电池异常规则
- macOS 本地通知
- 日报页面

验收：

- 能识别整晚未睡眠
- 能识别阻止睡眠进程
- 能识别长时间高 CPU / 高内存

### Milestone 4：报告与导出

目标：提供长期分析能力。

任务：

- 日报
- 周报
- CSV 导出
- JSON 导出
- Markdown 导出

验收：

- 能查看最近 7 天趋势
- 能导出完整数据

## 9. UI 信息架构

### 9.1 总览

内容：

- 当前系统状态
- 昨晚睡眠结论
- 今日活跃时间
- Top Apps
- 当前异常

### 9.2 时间线

内容：

- 睡眠
- 唤醒
- 锁屏
- 解锁
- 电源变化
- App 切换
- 异常事件

交互：

- 按日期筛选
- 按事件类型筛选
- 点击事件查看原始详情

### 9.3 睡眠诊断

内容：

- 昨晚睡眠卡片
- 睡眠阶段图
- 唤醒原因
- 阻止睡眠进程
- 改善建议

### 9.4 系统监控

内容：

- CPU 图表
- 内存图表
- 网络图表
- 磁盘图表
- 电池图表
- Top 进程

### 9.5 App 使用

内容：

- 今日排行
- 时间分布
- App 切换记录
- 分类统计
- 忽略列表

### 9.6 设置

内容：

- 权限状态
- 采集频率
- 数据保留
- 隐私选项
- 通知选项
- 导出 / 清空数据

## 10. 风险与限制

### 10.1 macOS 权限限制

问题：

- 前台 App 和窗口标题需要用户授权
- 深度日志可能需要 Full Disk Access
- 不同 macOS 版本日志格式可能不同

应对：

- 做权限分级
- 明确展示功能缺失原因
- 日志解析器保留 raw payload

### 10.2 Apple Silicon 温度限制

问题：

- 温度 / 风扇读取没有稳定公开 API

应对：

- 第一版不承诺温度和风扇
- 后续通过可选底层 helper 或第三方方案评估

### 10.3 监控工具自身耗电

问题：

- 采样过频会让工具本身成为耗电来源

应对：

- 默认低频采样
- App 切换使用事件驱动
- 睡眠日志批量解析
- 提供低功耗模式

### 10.4 隐私风险

问题：

- App 使用日志和窗口标题可能非常敏感

应对：

- 默认不记录窗口标题
- 默认不截图
- 全部本地存储
- 明确隐私开关
- 支持排除 App
- 支持一键清空

## 11. 推荐第一步

先做一个可运行原型，验证三个核心能力：

1. 菜单栏实时状态
2. 昨晚睡眠报告
3. 前台 App 使用记录

只要这三个能力稳定，Status Mac 就已经具备产品价值。后续的异常提醒、日报、导出都可以在同一数据模型上继续扩展。
