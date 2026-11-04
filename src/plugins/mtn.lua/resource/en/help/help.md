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

Three samples are in the `samples/macros` folder of the distribution: sorting lines without duplicates, making a folder, a report on the marked files.
