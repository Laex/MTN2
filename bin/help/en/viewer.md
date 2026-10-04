## Viewing and editing files

**F3** – view, **F4** – edit, **F6** – switch viewer ↔ editor without closing the file.

**Alt+F3** / **Alt+F4** – open the cursor file in the external viewer / editor. The commands are set in **Options → External viewer/editor...**; without them Alt+F3 opens the file with its Windows program and Alt+F4 with the Windows “Edit” command, or Notepad if there is none. Files on disk only.

| Key | Action |
| --- | --- |
| F7, Ctrl+F (in the viewer also `/`) | the search dialog (see below) |
| Shift+F7 / Alt+F7, F3 / Shift+F3 | next / previous match (with **Reverse search** on, the two swap) |
| Ctrl+F7 | find and replace (editor): the same options and buttons, plus **Replace** and **All** |
| Alt+F8 | go to line |
| F8 | next encoding; Shift+F8 – choose an encoding |
| F4 (in the viewer), Ctrl+H | HEX mode (in the editor's HEX mode bytes can be edited) |
| Ctrl+M | Markdown: rendered view ↔ source text |
| Tab / Shift+Tab | Markdown: next / previous link |
| Enter, click on a link | Markdown: open an external link (`https://…`, `mailto:…`) in the default application, after a confirmation |
| F2 | save (editor) / word wrap (viewer; remembered per file along with the position) |
| Ctrl+S | save |
| Ctrl+Z / Ctrl+Shift+Z | undo / redo |
| Ctrl+Y, Ctrl+D | delete the line |
| Ctrl+K | delete to the end of the line |
| Ctrl+N | insert an empty line below |
| Ctrl+Home / Ctrl+End | to the start / end of the file |
| Ctrl+C / Ctrl+X / Ctrl+V | copy (without a selection – the line) / cut / paste |
| Esc, F10 (in the viewer also 5 on the numeric keypad) | close |

Large files are streamed, not loaded as a whole. If the file changes on disk, the open window is updated. For a read-only file the program offers to open it for writing by clearing the attribute.

**Search dialog.** The field keeps earlier searches (**Ctrl+↓** / **Alt+↓**); the options are **Case sensitive**, **Whole words**, **Regular expressions** and **Reverse search**. **Word** puts the word under the cursor into the field, **Selection** puts in the selection (the current line when nothing is selected; the first line of a multi-line selection). With **Regular expressions** on, the text of those two buttons is escaped. A found match is selected and **F3** / **Shift+F3** go on from it. A match never spans a line break. With **Regular expressions** the pattern is a PCRE expression and in the replacement `$0` is the whole match, `$1` ... `$9` are the groups and `$$` is a dollar sign; without the option the replacement is taken as it is. A pattern that cannot be compiled is reported and nothing is searched. **Replace** in the Replace dialog goes through the matches one by one: each is shown selected, with the text, its replacement and the line that holds it, and is answered with **Replace** (replace it and go on to the next), **All** (replace the rest without asking), **Skip** or **Cancel**. When the end of the text is reached and the search began in the middle, it offers to continue from the beginning (from the end when searching backwards). **All** in the Replace dialog replaces every match of the whole text in one go. Both ways show how many replacements were made at the end of **All**, are undone with a single **Ctrl+Z**, and put the cursor back where it was before the replace. Case, whole words and regular expressions are remembered between runs; **Reverse search** only until MTN2 closes.

---

[Contents](index.md)
