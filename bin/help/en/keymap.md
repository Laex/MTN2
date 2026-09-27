# Key bindings

The built-in key set can be partly redefined by the `keymap.json` file in the settings folder (or via **Options → Keymap...**): only the changed actions are listed, the rest stay built-in. **Ctrl+Alt+K** — reload the file without a restart.

Besides the panels, the viewer and editor commands can be rebound. Their names in `keymap.json` start with `Doc` (both viewing and editing: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…), `Viewer` (viewing only: `ViewerWrap`), `Markdown` (rendered Markdown: `MarkdownSource`) and `Editor` (editing only: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…). The same chord can mean different things on the panels and in a document — Ctrl+H shows hidden files on a panel and toggles hex in a document. A narrower meaning overrides a general one: F4 over rendered Markdown toggles the source, not hex.

Modifiers must match exactly: Ctrl+Shift+A is not Ctrl+A. Arrows, Home/End, typing and `/` in the viewer are not configurable.

---

[Contents](index.md)
