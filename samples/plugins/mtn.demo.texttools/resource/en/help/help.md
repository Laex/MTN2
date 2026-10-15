# Text tools (C++)

Small tools for the text on screen in the editor (F4) and the viewer (F3).

## Use

Open a text file and press:

- **Ctrl+Shift+U** – upper-case the selection; **Ctrl+Shift+L** – lower-case it.
- **Ctrl+Shift+S** – sort the lines of the selection (or of the whole document when nothing is selected), ignoring case.
- **Ctrl+Shift+R** – remove repeated lines of the selection (or of the whole document), keeping the first of each.
- **Ctrl+Shift+T** – switch **tidy on save** on or off. While it is on, **Tidy on save** shows in the status line of the panels, and every F2 (save) in the editor first strips trailing blanks and makes the text end with a line break. The choice is kept between runs.

Every change is one undo step (Ctrl+Z). In the viewer (read-only) the tools tell you to press F4 first.

## For authors

Source: `samples/plugins/mtn.demo.texttools/plugin.cpp`. It reads the document with `doc_get_text`, changes it with `doc_replace`, keeps the cursor with `doc_info` / `doc_set_cursor`, and hooks the built-in `EditorSave` command (the hook answers 0, so the save goes on). See `docs/PLUGIN_DEVELOPMENT.md`, section "Documents, panels and the clipboard".
