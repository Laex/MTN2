# 宏

该插件运行用 Lua 编写的宏。宏是设置目录下 `macros` 文件夹中的文本文件。宏可用自己的快捷键启动，也可在面板、查看器、编辑器和控制台的**宏**菜单中启动（命令行中不可用）。按 Esc 停止正在运行的宏。

## 录制

* **Ctrl+.** 开始录制按下的按键；再按一次 **Ctrl+.**（或点击 **REC** 标记）结束录制。**Ctrl+Shift+.** 暂停和继续。
* 录制结束后，对话框会询问名称、快捷键以及是否在“宏”菜单中显示该宏。快捷键输入框记录你按下的组合键；Backspace 清除。如果程序或其他插件已占用该快捷键，对话框会提示：再次确认会照样分配；录制之后，被占用的快捷键不会被分配。
* 宏保存为 Lua 文件，可像普通文本一样编辑。

## 管理宏

**宏 > 管理宏...** 以表格显示所有宏。

| 按键 | 操作 |
|---|---|
| Enter | 运行 |
| 空格 | 启用 / 停用 |
| F2 | 分配快捷键 |
| F4 | 在编辑器中打开（保存文件后宏会重新读取） |
| F5 | 不重启重新读取文件夹 |
| Del | 删除 |

**导入...** 按钮接受宏文件或包含宏的文件夹；**导出...** 把所有宏复制到一个文件夹。

## 编写宏

```lua
macro {
  name = "Make folder",
  area = "panels",
  requires = "has_selection",
  key = "Ctrl+Alt+2",
  menu = true,
  run = function()
    mtn.key("F7")
    mtn.text("New folder")
    mtn.key("Enter")
  end,
}
```

| 字段 | 含义 |
|---|---|
| `name` | 菜单和列表中的名称 |
| `area` | 宏的适用范围：`panels`、`editor`、`viewer`、`terminal`，可用逗号列出多个，或 `any` |
| `requires` | 启动前的条件，用逗号分隔：`has_selection`、`no_selection`、`cursor_file`、`cursor_dir`、`editable`、`modified` |
| `key` | 快捷键组合，例如 `Ctrl+Alt+2` |
| `menu` | `true` 时在“宏”菜单中显示该宏 |
| `run` | 完成工作的函数 |

`run` 中可用的函数：

| 函数 | 作用 |
|---|---|
| `mtn.key("F7")` | 按下按键或组合键 |
| `mtn.text("abc")` | 输入文本 |
| `mtn.action(name)` | 执行程序命令 |
| `mtn.state()` | 状态表：`area`、`has_selection`、`selected_count`、`cursor_kind`、`cursor_name`、`panel_kind`、`active_side`、`editor_modified`、`editor_has_selection`、`viewer_mode` |
| `mtn.selected()` | 已标记项目的列表 |
| `mtn.message(text)` | 显示通知 |
| `mtn.wait_idle()` | 让程序绘制并处理宏已开始的操作 |

每个涉及程序的调用都会等程序处理完毕，宏才继续执行。Lua 环境包含基础库以及 `string`、`table`、`math`、`utf8`、`coroutine`；`io`、`os`、`package` 和 `debug` 不可用。长时间不等待地运行的宏会被停止。

发行包的 `samples/macros` 文件夹中有三个示例：去重排序行、创建文件夹、已标记文件报告。
