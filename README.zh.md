# Modern Terminal Navigator 2 (MTN2)

[English](README.en.md) | [Deutsch](README.de.md) | [Русский](README.md) | **中文** | [한국어](README.ko.md)

基于 **Necromancer's DOS Navigator** 与 **Far Manager** 理念的双面板文件管理器，内置控制台、终端、文件查看器和编辑器。界面为文本用户界面（TUI），但在常规 GUI 窗口中渲染：基于 Delphi FireMonkey 画布（Skia 渲染，支持通过 `--no-skia` 回退到标准画布）的虚拟字符网格，支持 TrueType 字体、Unicode 与 32 位色彩。中日韩（CJK）表意文字占用两列宽度（双宽），与其他现代终端表现一致。

[![CI](https://github.com/Laex/MTN2/actions/workflows/ci.yml/badge.svg)](https://github.com/Laex/MTN2/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

![MTN2：带标签页的双面板](docs/images/mtn2-panels.png)

[项目主页](https://laex.github.io/MTN2/zh/) ·
[下载最新版本](https://github.com/Laex/MTN2/releases/latest) ·
[更新日志](CHANGELOG.md) · [常见问题](docs/FAQ.md)（俄语） · [参与贡献](CONTRIBUTING.md)（俄语） ·
[讨论区](https://github.com/Laex/MTN2/discussions) ·
[Habr 文章](https://habr.com/ru/articles/1087174/)（俄语）

MTN2 面向在 DOS Navigator 与 Far Manager 陪伴下成长、习惯用键盘工作的人：系统与网络工程师、开发者、管理员。它不取代 Far Manager，也不与 Total Commander 竞争，只是又一个有自己使用习惯的双面板管理器。

## 设计原则

- **无遥测、无云端功能。** 唯一的网络访问是向 GitHub 检查新版本（每天启动时一次）；可在 **≡ → 检查更新...** 中关闭（“启动时检查更新”）。
- **便携。** 单个目录，无需安装程序，不写注册表；便携版的设置保存在 `MTN2.exe` 同级目录，普通版保存在 `%APPDATA%\MTN2`。设置、主题与快捷键映射均为普通 JSON 文件。
- **键盘优先。** 快捷键布局接近 Far Manager，可完全自定义；标签页与终端的用法类似 ConEmu。
- **真正的终端。** 控制台基于 ConPTY（cmd、PowerShell、WSL、SSH），而非模拟。
- **可扩展。** 原生与 WebAssembly 插件：自定义文件系统、面板、命令、对话框、文本着色。

> Habr 文章将名称解释为 Modern Turbo Navigator；当前名称为 **Modern Terminal Navigator**。


## 截图

| | |
|---|---|
| ![带标签页的双面板](docs/images/mtn2-panels.png) | ![压缩包作为文件夹](docs/images/mtn2-archive.png) |
| 带标签页的面板，Far Classic 主题 | 压缩包可作为文件夹打开 |
| ![Markdown 查看器](docs/images/mtn2-markdown.png) | ![带 JSON 高亮的编辑器](docs/images/mtn2-editor.png) |
| 支持表格的 Markdown 查看器 | 编辑器；高亮由插件提供 |
| ![内置控制台](docs/images/mtn2-console.png) | ![Dracula 主题](docs/images/mtn2-dracula.png) |
| 内置控制台（Ctrl+O） | Dracula 主题 |

## 功能特性

- **面板：** 支持标签页的双面板、简要/完整/多列显示模式、排序、快速搜索与实时筛选、通配符选择、目录对比、历史记录与常用文件夹列表、支持长路径（> MAX_PATH）。
- **文件操作：** 支持进度显示的后台任务复制、移动与删除，属性与时间戳修改，软/硬链接，回收站，校验和计算，目录同步。
- **控制台与终端：** 面板下方的命令行输入、真正的 ConPTY（cmd、PowerShell、pwsh、Git Bash、WSL、SSH）、ANSI/VT 转义序列解析、面向 TUI 程序的备用屏幕缓冲、终端工作区。从面板或命令行启动的控制台程序在内置控制台中运行，输出保留在屏幕上（`Ctrl+O`）。
- **查看与编辑：** 内置 Viewer（文本、十六进制、大文件流式加载）、Editor、快速查看（`Ctrl+Q`）、Markdown 预览、支持外部查看器与编辑器。
- **虚拟文件系统（VFS）：** 压缩包浏览（zip、基于 `7z.dll` 的 7z）、SSH 上的 SFTP、插件扩展 VFS。
- **个性化设置：** 可自定义快捷键映射（`keymap.json`）、基于文件的主题系统（Far Classic、Total Commander、Dracula、Nord、Solarized、High Contrast 等；可通过内置主题编辑器创建自定义主题）、用户菜单（F2）、文件关联、F1 上下文帮助。
- **多语言：** 界面和帮助文档支持英语、俄语和德语；语言可在 **选项 → 字体 / 显示...**（Options → Font / Display...）中选择并实时生效，无需重启。可通过在 `MTN2.exe` 同级目录下放置 `resource\<语言代码>\` 文件夹（`locale.json`、`strings.json`，帮助文档在 `help\` 中）添加自定义语言，无需重新编译。程序内仅内置英语。
- **Unicode：** CJK 汉字（基本多语言平面）、平假名、片假名、谚文及全角字符在控制台、面板、标签页和标题中均以双列宽度显示；缺失字符自动使用系统字体回退渲染。
- **插件系统：** 原生 DLL 与 WebAssembly（基于 Wasmtime）—— 支持自定义 VFS 方案及专属面板、菜单项、按键绑定、消息总线。已定义对话框、覆盖层与状态栏的插件协议，目前由主程序内部使用——详见 [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md)。
- **自动更新：** 每日自动检查 GitHub 上的新版本；下载（包含 SHA-256 校验）、安装及重启均需用户确认。菜单入口：**≡ → 检查更新...**。

支持 Windows x64（图形界面程序）与 Linux x86-64：`mtn2-tui` 运行在全屏文本终端中，拥有完全相同的面板、查看器、编辑器、控制台与插件，支持 SSH 远程连接与 `tmux`（参见 [docs/LINUX.md](docs/LINUX.md)）。实验性的 Linux 图形界面版本 `mtn2-sdl` 在普通 SDL2 窗口中显示相同的窗口：使用系统字体，支持鼠标与滚轮、任意键盘布局输入、桌面剪贴板，以及快速预览中的图片。它可运行于 X11 与 Wayland（Windows 下通过 WSLg），包含在 `tar.gz` 与 `.deb` 软件包中，需要 `libSDL2` 与 `libfreetype`（PNG 和 JPEG 另需 `libSDL2_image`）：依赖项与参数详见 [docs/LINUX.md](docs/LINUX.md)（俄语）。macOS 构建已在规划中。

## 安装指南

预编译版本可在 [Releases](https://github.com/Laex/MTN2/releases) 页面下载：

- `MTN2-<版本>-win64.zip` – 配置和历史记录保存在 `%APPDATA%\MTN2`；
- `MTN2-<版本>-win64-portable.zip` – 便携版：所有内容均存放在 `MTN2.exe` 同级目录下；
- `MTN2-<版本>-linux-x64.tar.gz` 与 `MTN2-<版本>-linux-x64.deb` – Linux 版本：`mtn2-tui`（在终端窗口内运行，支持 SSH）与实验性的图形版 `mtn2-sdl`（SDL2 窗口，需要 `libSDL2` 与 `libfreetype`）：
  安装指南、依赖项与参数说明详见 [docs/LINUX.md](docs/LINUX.md)。

**Windows：** 只需解压至任意文件夹并运行 `MTN2.exe` 即可。之后程序支持自动更新（菜单 **≡ → 检查更新...**）。发布包中包含来自 [7-Zip](https://www.7-zip.org) 的 `7z.dll`（GNU LGPL 许可；许可证文本位于 `plugins\mtn.7z\license.txt`，详情参阅 [THIRD-PARTY.md](THIRD-PARTY.md)），用于打开 7z 及其他 7-Zip 支持的格式。可在 `plugins\mtn.7z\` 中替换为您自己的 x64 版本；zip 格式无需此 DLL 即可原生打开。

**Linux：** `tar xzf MTN2-*-linux-x64.tar.gz && ./mtn2/install.sh`（为所有用户安装请加 `sudo`），或 `sudo apt install ./MTN2-*-linux-x64.deb`。安装后 `mtn2` 启动终端版，`mtn2-sdl` 启动 SDL2 窗口。解压后的文件夹也可免安装运行：`mtn2/mtn2-tui` 与 `mtn2/mtn2-sdl` 可就地启动。

### 开发版构建（Dev Builds）

每次向 `main` 分支提交代码后，预发布（dev）构建会自动发布在独立仓库 [Laex/MTN2-dev](https://github.com/Laex/MTN2-dev/releases) 中。如需自动接收开发版更新，请打开 **≡ → 检查更新...** 并勾选 dev 渠道复选框；取消勾选即可随时切回稳定版本。开发版构建包含最新特性，但稳定性可能稍低。

## 编译源码

需要 RAD Studio 13（Delphi，`Studio\37.0`）及 Windows x64；编译 WASM 插件 `mtn.ws` 需要 Rust。
Linux 版本在 Windows 环境下通过 `dcclinux64` 编译器进行交叉编译，其测试套件在 WSL 中运行。

```powershell
./src/build.ps1 -Config Release -Platform Win64   # bin\win64\MTN2.exe + bin\win64\plugins\
./src/tests/run-tests.ps1                          # DUnitX 回归测试
./src/build-linux.ps1                              # bin\linux64\mtn2-tui
./src/tests/run-tests-linux.ps1                    # 在 WSL 中运行相同测试
```

运行：`bin\win64\MTN2.exe [--no-skia] [--fps] [路径]`。详细说明请参阅 [docs/BUILDING.md](docs/BUILDING.md)。

## 仓库结构

| 路径 | 内容说明 |
|---|---|
| `src/Core` | 核心引擎：面板、VFS、控制台、编辑器、对话框、插件宿主 |
| `src/Platform` | 平台适配层：包含同名模块的 `Windows` 与 `Posix` |
| `src/Hosts` | 外壳宿主：`Ansi` – 文本终端版本 |
| `src/Forms`, `src/dialogs`, `src/Assets/themes` | 主窗体、JSON 对话框、内置主题 |
| `src/plugins` | 内置插件（`mtn.7z`、`mtn.tmp`、`mtn.ws`、WASM 演示） |
| `src/tests` | 按组划分的 DUnitX 回归测试及运行脚本 `run-tests.ps1` |
| `src/tools` | DialogDesigner、ExportDialogJson、`Group.groupproj` 项目组、工具脚本 |
| `bin/win64`, `bin/linux64` | 各平台构建输出目录 |
| `bin/win64/resource` | 语言包：界面文本和 F1 帮助文档（en/ru/de），随程序一同发布 |
| `docs` | 开发者文档、截图（`docs/images`） |

## 相关文档

- [SDS.md](docs/SDS.md) – 完整软件规格说明书：理念、数据结构、API、路线图。
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) – 架构分层、数据流及系统不变量。
- [BUILDING.md](docs/BUILDING.md) – 构建指南、测试、CI/CD。
- [LINUX.md](docs/LINUX.md) – Linux 终端版本：安装、运行参数与依赖说明。
- [THEMES.md](docs/THEMES.md) – 主题文件格式与颜色角色定义。
- [HELP.md](docs/HELP.md) – 单文件完整用户帮助手册。
- 插件接口规范：[PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md)、[PANEL](docs/PANEL_PLUGIN.md)、
  [DIALOG](docs/DIALOG_PLUGIN.md)、[INPUT](docs/INPUT_PLUGIN.md), [OVERLAY](docs/OVERLAY_PLUGIN.md)、
  [STATUS](docs/STATUS_PLUGIN.md)、[TEXTAREA](docs/TEXTAREA_PLUGIN.md)、[TOOLBAR](docs/TOOLBAR_PLUGIN.md)、
  [UI_PRIMITIVES](docs/UI_PRIMITIVES.md)。

## 项目研发背景

在 MTN2 的开发过程中应用了人工智能辅助工具（包括自研工具）。利用 AI 完成了：

- 项目前期文档准备：规格说明书（[SDS.md](docs/SDS.md)）、架构概述、`docs/` 中的插件协议描述；
- 路线图跟踪与任务规划；
- 代码中绝大多数注释的编写；
- 基于 DUnitX 的回归测试套件（`src/tests`）；
- 面向用户的文本文档：F1 帮助（`bin/win64/resource/<语言代码>/help`）、[CHANGELOG.md](CHANGELOG.md) 以及版本发布说明。

## 许可证

[Mozilla Public License 2.0](LICENSE)。
