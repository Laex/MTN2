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

## Editor, panels, dialogs and programs

These functions also wait until the program has handled the call. Lines and columns count from 1; a panel side is `"left"`, `"right"` or `nil` (the active one).

| Function | Action |
|---|---|
| `mtn.editor.info()` | table: `uri`, `lines`, `row`, `col`, `dirty`, `can_edit`, `has_selection`; `nil` without a document |
| `mtn.editor.text()`, `.selection()`, `.current_line()` | the whole text, the selection, the current line |
| `mtn.editor.line(n)` | line `n` or `nil` |
| `mtn.editor.replace(text)` | replace the selection (or insert at the cursor) |
| `mtn.editor.replace_all(text)`, `.replace_line(text)` | replace the whole text or the current line |
| `mtn.editor.set_cursor(row, col)`, `.set_selection(r1, c1, r2, c2)` | place the cursor or the selection |
| `mtn.panel.list(side)` | table: `path`, `files` (rows with `name`, `uri`), `cursor`, `truncated` |
| `mtn.panel.path(side)`, `.cursor(side)` | the path of a panel, the row under the cursor |
| `mtn.panel.open(uri, side)`, `.set_cursor(uri, side)` | go to a folder, put the cursor on an item |
| `mtn.panel.select(mask, side)`, `.unselect(mask, side)`, `.clear_selection(side)` | mark, unmark by mask, unmark all |
| `mtn.panel.select_item(uri, side)`, `.unselect_item(uri, side)` | mark or unmark one item |
| `mtn.panel.refresh()` | reread the panels |
| `mtn.clipboard.get()`, `.set(text)` | the clipboard |
| `mtn.input(prompt, default, title)` | an input box; `nil` when closed |
| `mtn.confirm(text, title)` | a Yes/No question: `true` or `false` |
| `mtn.choose(title, items)` | pick from a list of strings: the item number or `nil` |
| `mtn.exec(program, args, opts)` | run a program: its output and exit code, or `nil` and the reason |

A program starts only when its name (without path and extension) is listed in the macro's `exec` field, comma separated, for example `exec = "git, hg"`. `opts` takes `stdin` (text for the input) and `timeout` (seconds, 10 by default, at most 60). The output is cut at 1 MB. Dialogs are unavailable while another dialog is open.

### Events

`mtn.on(topic, function, {exec = "..."})` called while a file loads registers a handler. When the program publishes an event (`doc.opened`, `doc.saved`, `doc.changed`, `doc.closed`, `panel.dir`, `panel.cursor`), the function runs as a macro and gets the event table with a `topic` field. An event that arrives while another macro or handler runs is skipped, so a handler cannot start itself.

```lua
mtn.on("doc.saved", function(e)
  mtn.message("Saved: " .. (e.uri or ""))
end)
```

### Panel columns

`mtn.column{...}` called while a file loads adds a column to the file panels (Settings – Columns...).

```lua
mtn.column {
  id = "kb", title = "KB", width = 7, align = "right", default = true,
  value = function(f)
    if f.dir then return nil end
    return f.size // 1024 .. " KB"
  end,
}
```

| Field | Meaning |
|---|---|
| `id` | the name of the column (required) |
| `title` | the heading, `id` by default |
| `width` | the width (10 by default) |
| `align` | `"left"` or `"right"` |
| `default` | `true` shows the column until the user picks a set of their own |
| `value` | a function: gets the file table (`name`, `uri`, `dir`, `size`) and returns a text or a number; `nil` leaves the cell empty |

The values are computed for both panels when the macros load and whenever a folder changes, for the first 3000 files and in local folders only. The function runs like a macro but cannot wait: calls that reach into the program (`mtn.key`, `mtn.editor.*`, dialogs, `mtn.exec`) are unavailable in it. A column whose function raised an error is switched off until the macros are reloaded, and the error is shown once. A column cannot be sorted.
