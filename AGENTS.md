# AGENTS
## 指令范围
- 本文件是本仓库的 macos agent 指南，适用于整个仓库。
- 若子目录未来出现更近的 `AGENTS.md`，以更近文件为准。
- `CLAUDE.md`、`GEMINI.md` 只做兼容入口；共享规则应优先维护在本文件。

README.md 是项目内容介绍
- 新增加的功能，要补全到readme.md 里
- 新增或调整左侧工具功能时，要同步检查“通用 > 导出配置/导入配置”，确保导出覆盖所有可配置功能；剪贴板只导出设置，不导出剪贴板历史记录、SQLite 数据库或图片缓存。
ref/ 目录下是别的开源项目，开发时候参考的，不作为项目代码用

<skills_system priority="1">

## Available Skills

<!-- SKILLS_TABLE_START -->
<usage>
When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.

</usage>

<available_skills>

<skill>
<name>grill-me</name>
<description>A relentless interview to sharpen a plan or design.</description>
<location>global</location>
</skill>

<skill>
<name>grill-with-docs</name>
<description>A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.</description>
<location>global</location>
</skill>

<skill>
<name>karpathy-guidelines</name>
<description>Behavioral guidelines to reduce common LLM coding mistakes. Use when writing, reviewing, or refactoring code to avoid overcomplication, make surgical changes, surface assumptions, and define verifiable success criteria.</description>
<location>global</location>
</skill>

<skill>
<name>macos</name>
<description>Apple Human Interface Guidelines for Mac. Use when building macOS apps with SwiftUI or AppKit, implementing menu bars, toolbars, window management, or keyboard shortcuts. Triggers on tasks involving Mac UI, desktop apps, or Mac Catalyst.</description>
<location>global</location>
</skill>

<skill>
<name>macos-app-design</name>
<description>Use when designing or building native macOS applications with SwiftUI or AppKit. Triggers on menu bar structure, keyboard shortcuts, multi-window behavior, Liquid Glass design system, macOS Tahoe/Sequoia, sidebar navigation, toolbar design, app icons, SF Symbols, or making an app feel like a "good Mac citizen."</description>
<location>global</location>
</skill>


</available_skills>
<!-- SKILLS_TABLE_END -->

</skills_system>
