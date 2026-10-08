## Key bindings

The built-in key set can be partly redefined by the `keymap.json` file in the settings folder (or via **Options → Keymap...**): only the changed actions are listed, the rest stay built-in. **Ctrl+Alt+K** – reload the file without a restart.

Besides the panels, the viewer and editor commands can be rebound. Their names in `keymap.json` start with `Doc` (both viewing and editing: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…), `Viewer` (viewing only: `ViewerWrap`), `Markdown` (rendered Markdown: `MarkdownSource`) and `Editor` (editing only: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…). The same chord can mean different things on the panels and in a document – Ctrl+H shows hidden files on a panel and toggles hex in a document. A narrower meaning overrides a general one: F4 over rendered Markdown toggles the source, not hex.

Global commands work in any window – the panels, a document, a terminal: `Help` (F1), `TopMenu` (F9), `NextTab` / `PrevTab` (Ctrl+Alt+PgDn / Ctrl+Alt+PgUp), `AppConsoleToggle` (Ctrl+O), `NewTerminal` (Ctrl+Shift+N), `SelectConsoleProfile` (Ctrl+Alt+O), `AppQuit` (Alt+X), `ZoomReset` (Ctrl+0) and `ReloadKeymap` (Ctrl+Alt+K). A chord the window binds itself stays the window's: F10 closes a document and quits only on the panels (`Quit`); Esc on the panels shows the console (`ConsoleToggle`) when the panel has the focus; in the command line it first clears it, then gives the focus back to the panel. While a full-screen program runs in a console or terminal (the profile's keys mode is *auto* or *terminal*, see Terminals), the console gets these keys too, except the ones that leave it: F11, Ctrl+O, switching tabs, Ctrl+Shift+N and Ctrl+Alt+O. While a dialog is open the global commands do not fire; `ZoomReset` and `ReloadKeymap` always do.

In the console (Ctrl+O) and a terminal the commands named `Shell…` can be rebound: `ShellHistory` (Alt+F8), `ShellSelectAll` (Ctrl+A), `ShellCopyOrInterrupt` (Ctrl+C – copy the selection, or interrupt the command without one), `ShellCopy` (Ctrl+Ins) and `ShellPaste` (Ctrl+V, Shift+Ins); in the console also `ConsoleSyncDir` (Ctrl+Shift+O – the panel goes to the console's folder). Every other key goes to the shell.

**Settings → Keymap** groups the actions by window – global, file panels, viewer and editor, console and terminal – under readable names; the `keymap.json` name shows in the edit window. The F-key labels at the bottom, hints such as `A:All` and the shortcuts in the top menu come from the keymap: after a rebinding they show the new key.

An action can have several shortcuts: list them separated by `;` in the edit window, or as separate entries in `keymap.json`. Besides letters, digits and special keys, the signs `/`, `,`, `.`, `'`, `=` can be assigned; write semicolon and the main-block minus as `Semicolon` and `Minus` (`-`, `+` and `*` mean the numeric keypad keys).

Modifiers must match exactly: Ctrl+Shift+A is not Ctrl+A. Arrows, Home/End, typing and `/` in the viewer are not configurable.

### Tab keys

All tab keys are ordinary keymap actions and can be rebound in `keymap.json`. Panel tabs and workspaces (the tabs of the top row) are different things, each with its own actions:

| What | Action in `keymap.json` | Default |
| --- | --- | --- |
| New panel tab | `NewTab` | Ctrl+T |
| Next / previous panel tab | `NextPanelTab` / `PrevPanelTab` | Ctrl+Tab / Ctrl+Shift+Tab |
| Close the panel tab | `CloseTab` | Ctrl+W |
| New workspace | `NewWorkspace` | Ctrl+Shift+W |
| Next / previous workspace | `NextTab` / `PrevTab` | Ctrl+Alt+PgDn / Ctrl+Alt+PgUp |

The `[+]` and `[x]` buttons in the tab rows and the top menu items do the same.

### Your own `keymap.json` and updates

The `keymap.json` in the settings folder is laid over the built-in keymap: the actions it lists win over the built-in ones. The **Settings → Keymap** dialog writes only the changed actions to the file, so the other keys follow the built-in keymap after an update. A file saved by earlier versions lists all actions and freezes the old keys: to get the new ones, delete the lines of the actions you need from it, or the whole file (keep a copy first if it holds changes of your own). An action without keys is written as an empty list.

### Reserved keys

Not taken yet and kept for planned features: **Shift+F3** (archive commands), **F11** (the plugin menu), **Ctrl+Alt+Ins** (network UNC paths), **Ctrl+.** (macro recording). An automatic check keeps the built-in keymap from taking them.

---

[Contents](index.md)
