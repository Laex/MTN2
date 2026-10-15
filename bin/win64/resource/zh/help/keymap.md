## 快捷键

内置按键集可以通过设置文件夹中的 `keymap.json` 文件(或通过**选项 → 快捷键...**)部分重新定义: 只列出更改过的操作,其余保持内置。**Ctrl+Alt+K** – 无需重启即可重新加载该文件。

除面板外,查看器和编辑器的命令也可以重新绑定。它们在 `keymap.json` 中的名称以 `Doc` 开头(查看和编辑都适用: `DocHex`、`DocFind`、`DocEncoding`、`DocClose` 等)、`Viewer`(仅查看: `ViewerWrap`)、`Markdown`(渲染后的 Markdown: `MarkdownSource`)和 `Editor`(仅编辑: `EditorSave`、`EditorUndo`、`EditorDeleteLine` 等)。同一个组合键在面板和文档中可以有不同含义 – Ctrl+H 在面板上显示隐藏文件,在文档中切换十六进制。范围较窄的含义会覆盖较宽的含义: 在渲染后的 Markdown 上 F4 切换源码,而不是十六进制。

全局命令在任何窗口都有效 – 面板、文档、终端: `Help` (F1)、`TopMenu` (F9)、`NextTab` / `PrevTab` (Ctrl+Alt+PgDn / Ctrl+Alt+PgUp)、`AppConsoleToggle` (Ctrl+O)、`NewTerminal` (Ctrl+Shift+N)、`SelectConsoleProfile` (Ctrl+Alt+O)、`AppQuit` (Alt+X)、`ZoomReset` (Ctrl+0) 和 `ReloadKeymap` (Ctrl+Alt+K)。窗口自己绑定的组合键仍归窗口所有: F10 在文档中关闭文档,只有在面板上才退出(`Quit`); 面板获得焦点时,面板上的 Esc 显示控制台(`ConsoleToggle`); 在命令行中它先清除命令行,再把焦点交还面板。当控制台或终端中运行全屏程序时(配置的按键模式为*自动*或*终端*,见"终端"),控制台也会收到这些按键,但用于离开控制台的按键除外: F11、Ctrl+O、切换标签页、Ctrl+Shift+N 和 Ctrl+Alt+O。对话框打开期间全局命令不会触发; `ZoomReset` 和 `ReloadKeymap` 始终触发。

在控制台 (Ctrl+O) 和终端中,名称以 `Shell…` 开头的命令可以重新绑定: `ShellHistory` (Alt+F8)、`ShellSelectAll` (Ctrl+A)、`ShellCopyOrInterrupt` (Ctrl+C – 复制所选内容,没有选择时中断命令)、`ShellCopy` (Ctrl+Ins) 和 `ShellPaste` (Ctrl+V, Shift+Ins); 在控制台中还有 `ConsoleSyncDir` (Ctrl+Shift+O – 面板转到控制台的文件夹)。其他按键都交给 Shell。

**设置 → 快捷键**按窗口对操作分组 – 全局、文件面板、查看器和编辑器、控制台和终端 – 并使用易读的名称; 编辑窗口中会显示 `keymap.json` 中的名称。底部的功能键标签、`A:All` 之类的提示以及顶部菜单中的快捷键都来自键位配置: 重新绑定后它们会显示新的按键。

一个操作可以有多个快捷键: 在编辑窗口中用 `;` 分隔列出,或者在 `keymap.json` 中写成单独的条目。除字母、数字和特殊键外,还可以分配 `/`、`,`、`.`、`'`、`=` 这些符号; 分号和主键盘区的减号写作 `Semicolon` 和 `Minus`(`-`、`+` 和 `*` 表示小键盘上的按键)。

修饰键必须完全匹配: Ctrl+Shift+A 不是 Ctrl+A。方向键、Home/End、输入以及查看器中的 `/` 不可配置。

### 标签页按键

所有标签页按键都是普通的键位操作,可以在 `keymap.json` 中重新绑定。面板标签页和工作区(顶行的标签页)是不同的东西,各有自己的操作:

| 内容 | `keymap.json` 中的操作 | 默认 |
| --- | --- | --- |
| 新建面板标签页 | `NewTab` | Ctrl+T |
| 下一个 / 上一个面板标签页 | `NextPanelTab` / `PrevPanelTab` | Ctrl+Tab / Ctrl+Shift+Tab |
| 关闭面板标签页 | `CloseTab` | Ctrl+W |
| 新建工作区 | `NewWorkspace` | Ctrl+Shift+W |
| 下一个 / 上一个工作区 | `NextTab` / `PrevTab` | Ctrl+Alt+PgDn / Ctrl+Alt+PgUp |

标签行中的 `[+]` 和 `[x]` 按钮以及顶部菜单项作用相同。

### 你自己的 `keymap.json` 和更新

设置文件夹中的 `keymap.json` 叠加在内置键位之上: 它列出的操作优先于内置的操作。**设置 → 快捷键**对话框只把更改过的操作写入文件,所以更新后其他按键会跟随内置键位。早期版本保存的文件列出了所有操作,会冻结旧按键: 要获得新按键,请从中删除你需要的那些操作的行,或删除整个文件(如果其中有你自己的更改,请先备份)。没有按键的操作写成空列表。

### 保留按键

尚未占用,留给计划中的功能: **Shift+F3**(压缩包命令)、**F11**(插件菜单)、**Ctrl+Alt+Ins**(网络 UNC 路径)、**Ctrl+.**(宏录制)。自动检查会防止内置键位占用它们。

---

[目录](index.md)
