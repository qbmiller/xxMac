# AGENTS
## 指令范围
- 本文件是本仓库的 macos agent 指南，适用于整个仓库。
- 若子目录未来出现更近的 `AGENTS.md`，以更近文件为准。
- `CLAUDE.md`、`GEMINI.md` 只做兼容入口；共享规则应优先维护在本文件。

macos工具集合，类似alfred，有启动器。 README.md 是项目内容介绍
- 不需要在github 操作东西 尤其 Issue。只需要管好本项目 . github人工操作提交发版等
- 新增加的功能，要补全到readme.md 里
- 新增或调整左侧工具功能时，要同步检查“通用 > 配置目录”，功能是否有需要记录的东西，写在里面.
- ref/ 目录下是别的开源项目，开发时候参考的，不作为项目代码用
- 改完功能，git别auto commit. 人工提交
- 增加快捷执行，只需给出脚本shell/python ,由用户自己添加

## 构建与验证
- 需要生成应用包时使用根目录的 `bash bundle_app.sh`。 平时也用这个打包。
- 本项目是 Swift Package 项目，根目录使用 `Package.swift`，没有 `MacTools.xcodeproj` 或其他 Xcode 工程文件，也没有 `Makefile`。
- 编译使用 `swift build`，测试使用 `swift test`；定向测试可使用 `swift test --filter <TestName>`。
- 不要对本仓库运行 `xcodebuild -project MacTools.xcodeproj ...`。

