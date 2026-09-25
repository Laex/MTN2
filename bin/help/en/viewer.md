# Viewing and editing files

**F3** — view, **F4** — edit, **F6** — switch viewer ↔ editor without closing the file.

**Alt+F3** / **Alt+F4** — open the cursor file in the external viewer / editor. The commands are set in **Options → External viewer/editor...**; without them Alt+F3 opens the file with its Windows program and Alt+F4 with the Windows “Edit” command, or Notepad if there is none. Files on disk only.

| Key | Action |
| --- | --- |
| F7, Ctrl+F (in the viewer also `/`) | search; in the Find: field Ctrl+↓ / Alt+↓ — earlier searches |
| Shift+F7 / Alt+F7, F3 / Shift+F3 | next / previous match |
| Ctrl+F7 | find and replace (editor) |
| Alt+F8 | go to line |
| F8 | next encoding; Shift+F8 — choose an encoding |
| F4 (in the viewer), Ctrl+H | HEX mode (in the editor's HEX mode bytes can be edited) |
| Ctrl+M | Markdown: rendered view ↔ source text |
| F2 | save (editor) / word wrap (viewer) |
| Ctrl+S | save |
| Ctrl+Z / Ctrl+Shift+Z | undo / redo |
| Ctrl+Y, Ctrl+D | delete the line |
| Ctrl+K | delete to the end of the line |
| Ctrl+N | insert an empty line below |
| Ctrl+Home / Ctrl+End | to the start / end of the file |
| Ctrl+C / Ctrl+X / Ctrl+V | copy (without a selection — the line) / cut / paste |
| Esc, F10 (in the viewer also 5 on the numeric keypad) | close |

Large files are streamed, not loaded as a whole. If the file changes on disk, the open window is updated. For a read-only file the program offers to open it for writing by clearing the attribute.

---

[Contents](index.md)
