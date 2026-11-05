# Macros

The plugin runs macros written in Lua. A macro is a text file in the `macros` folder of the settings directory. It runs from its own key or from the **Macros** menu in the panels, viewer, editor and console (not from the command line). Esc stops a running macro.

## Recording

* **Ctrl+.** starts recording the keys you press; **Ctrl+.** again (or a click on the **REC** mark) ends it. **Ctrl+Shift+.** pauses and resumes.
* After recording a dialog asks for the name, the key and whether the macro is shown in the Macros menu. The key field records the combination you press; Backspace removes it. A key that the program or another plugin already uses is reported: confirming again assigns it anyway; after a recording such a key is not assigned.
* The macro is saved as a Lua file and can be edited like any text.

## Managing macros

**Macros > Manage macros...** shows the macros as a table.

| Key | Action |
|---|---|
| Enter | run |
| Space | switch on / off |
| F2 | assign a key |
| F4 | open in the editor (saving the file reloads the macros) |
| F5 | reload the folder without a restart |
| Del | delete |

The **Import...** button takes a macro file or a folder of them; **Export...** copies all macros to a folder.

## Writing a macro

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

| Field | Meaning |
|---|---|
| `name` | name in the menu and the list |
| `area` | where it runs: `panels`, `editor`, `viewer`, `terminal`, several separated by commas, or `any` |
| `requires` | conditions checked before the start, separated by commas: `has_selection`, `no_selection`, `cursor_file`, `cursor_dir`, `editable`, `modified` |
| `key` | key combination, e.g. `Ctrl+Alt+2` |
| `menu` | `true` shows the macro in the Macros menu |
| `run` | the function that does the work |

Functions available to `run`:

| Function | Action |
|---|---|
| `mtn.key("F7")` | press a key or combination |
| `mtn.text("abc")` | type text |
| `mtn.action(name)` | run a program command |
| `mtn.state()` | table with the state: `area`, `has_selection`, `selected_count`, `cursor_kind`, `cursor_name`, `panel_kind`, `active_side`, `editor_modified`, `editor_has_selection`, `viewer_mode` |
| `mtn.selected()` | list of the marked items |
| `mtn.message(text)` | show a notice |
| `mtn.wait_idle()` | let the program draw and handle what the macro started |

Each call that touches the program waits for the program to handle it before the macro goes on. The Lua environment has the base library and `string`, `table`, `math`, `utf8` and `coroutine`; there are no `io`, `os`, `package` or `debug`. A macro that runs too long without waiting is stopped.

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

Three samples are in the `samples/macros` folder of the distribution: sorting lines without duplicates, making a folder, a report on the marked files.
