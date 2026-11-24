# xxMac 功能全景图

## 设计方向：有序轻盈

以留白、整齐的卡片和克制的色彩建立阅读秩序。每一处间距、边界与基线都经过细致校准，让大量功能仍有清晰的呼吸感。

深靛蓝承载品牌和核心句，浅灰蓝承载内容。蓝、紫、青色只承担分组与提示作用，保持整体安静、统一。

标题、功能名、简介和示意形成四级视觉层次。文字紧扣操作价值，示意采用熟悉的搜索框、窗口分区与任务象限；不将示意冒充真实截图。

重复的模块提供稳定节奏，小范围的功能差异表达产品个性。精心处理每张卡片的对齐和内容长度，兼顾原始分辨率与 README 缩小显示后的可读性。

## 实施

- 1920 × 2240 PNG，三列四行，顶部品牌区，底部兼容性说明。
- 按已确认文案整合 12 张卡片；LockJob 与推荐工具在同一卡片内分别标明。
- 使用仓库应用图标、macOS 系统字体与 Pillow 绘制，保留可重复生成的脚本。
- 执行 `python3 docs/artwork/render_feature_overview.py` 更新 `docs/images/feature-overview.png`。
- 脚本依赖 Pillow 和 macOS 字体、sips；无网络依赖。
- 中文 README 引用 `feature-overview.png`，英文 README 引用全英文 `feature-overview-en.png`。
- 执行 `python3 docs/artwork/render_feature_overview.py --lang en` 重新生成英文版。
- README 采用简短简介、功能全景图、折叠功能参考、界面预览的阅读顺序。
