## Search and filters

| Key | Action |
| --- | --- |
| Alt+F7 | find files (mask, contents, subfolders, case, whole words, regular expressions) |
| Ctrl+I | panel filter: a dialog with a list of ready-made filters and a line for your own mask; Enter or a double click on the list applies the filter, Clear removes it |
| Ctrl+B | flat view: all files of the subtree in one list |
| Alt+letter | quick search by name |

### Search through plugins

The Everything plugin answers name searches in local folders from its index, the ripgrep plugin (`rg` in the PATH or next to the plugin) searches file text, and the Document viewer plugin lets a text search look inside `.docx`, `.xlsx`, `.pptx`, `.pdf`, `.svg` and SQLite files. Searches inside archives, by hex bytes or by attributes use the built-in search. A text search with a selective mask runs as a pipeline: the first stage lists the files by name (Everything or the built-in walk) and the second looks for the text in them (ripgrep or the built-in check). The **Pipeline** button of the Find dialog opens a dialog with one list per stage: **Auto** picks the best plugin, **Built-in** uses the built-in code, or choose one plugin by name; the built-in code runs when that plugin cannot serve the stage.

### Quick search

Alt+letter opens a search box in the active panel; further letters are added to it and the cursor moves to the first file whose name begins with the typed text. Backspace erases the last character, Esc closes the box and Enter opens the file under the cursor. Up and Down move to the neighbouring files; any other key or a Ctrl chord closes the search and acts as usual.

Options (Settings – Interface):

- **Keep quick search open after Alt is released** – the box stays open until Esc or Enter is pressed;
- **Keep an empty quick search open** – an empty box is not closed by Backspace;
- **Quick search also filters the panel** – besides the cursor, only the matching files remain in the panel; the box then stays open after Alt is released, Esc or Enter brings all files back and the cursor stays on the same file;
- **Keep the quick search filter in other folders** – Enter on a folder or a click carries the filter into the new folder, and then only Esc removes it;
- **Fuzzy quick search filter** – names that contain the typed letters in order, not necessarily next to each other, also match (`mnr` finds `main_readme.txt`); the cursor goes to a file with a matching beginning, or else to the first one in the list.

Search results open as a panel – the usual operations work on them.

Esc while a search runs asks “Stop the search?”: **Stop** ends the search, **Continue** (Esc) lets it keep running.

---

[Contents](index.md)
