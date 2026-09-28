## Key bindings

The built-in key set can be partly redefined by the `keymap.json` file in the settings folder (or via **Options → Keymap...**): only the changed actions are listed, the rest stay built-in. **Ctrl+Alt+K** – reload the file without a restart.

Besides the panels, the viewer and editor commands can be rebound. Their names in `keymap.json` start with `Doc` (both viewing and editing: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…), `Viewer` (viewing only: `ViewerWrap`), `Markdown` (rendered Markdown: `MarkdownSource`) and `Editor` (editing only: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…). The same chord can mean different things on the panels and in a document – Ctrl+H shows hidden files on a panel and toggles hex in a document. A narrower meaning overrides a general one: F4 over rendered Markdown toggles the source, not hex.

Global commands work in any window – the panels, a document, a terminal: `Help` (F1), `TopMenu` (F9), `NextTab` / `PrevTab` (Ctrl+Tab / Ctrl+Shift+Tab), `AppConsoleToggle` (Ctrl+O), `NewTerminal` (Ctrl+Shift+N), `SelectConsoleProfile` (Ctrl+Alt+O), `AppQuit` (Alt+X), `ZoomReset` (Ctrl+0) and `ReloadKeymap` (Ctrl+Alt+K). A chord the window binds itself stays the window's: F10 closes a document and quits only on the panels (`Quit`); Esc on the panels shows the console (`ConsoleToggle`). While a dialog is open the global commands do not fire; `ZoomReset` and `ReloadKeymap` always do.

In the console (Ctrl+O) and a terminal the commands named `Shell…` can be rebound: `ShellHistory` (Alt+F8), `ShellSelectAll` (Ctrl+A), `ShellCopyOrInterrupt` (Ctrl+C – copy the selection, or interrupt the command without one), `ShellCopy` (Ctrl+Ins) and `ShellPaste` (Ctrl+V, Shift+Ins); in the console also `ConsoleSyncDir` (Ctrl+Shift+O – the panel goes to the console's folder). Every other key goes to the shell.

**Settings → Keymap** groups the actions by window – global, file panels, viewer and editor, console and terminal – under readable names; the `keymap.json` name shows in the edit window. The F-key labels at the bottom, hints such as `A:All` and the shortcuts in the top menu come from the keymap: after a rebinding they show the new key.

Modifiers must match exactly: Ctrl+Shift+A is not Ctrl+A. Arrows, Home/End, typing and `/` in the viewer are not configurable.

---

[Contents](index.md)
