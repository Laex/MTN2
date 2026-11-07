## Synchronization and comparison

<!--dir-sync-->- **Ctrl+Alt+S** – synchronize the folders of the active and passive panels: one-way or two-way; the dry-run check box shows what would be done without changing anything.
- In the synchronization dialog every difference is a list row with its action: `->` copies to the right, `<-` to the left, `--` skips; conflicts start as skipped. The **Right**, **Left** and **Skip** buttons set the action of the selected row (a manual choice is marked `*`), **Reset** returns the automatic one, and **Only skipped** shows the rows that still need a decision. Differences left skipped stay open for the next synchronization.
<!--compare-files-->- **Ctrl+Alt+C** – compare the files under the cursors of both panels, or the two marked files of the active panel; the dialog shows size, modified time and a content verdict. With two or more files marked, the same-named files are compared (marks on both panels: only the marked ones; marks on one panel: the other panel is searched by name) and a list shows each pair as identical or different; Enter on a pair opens the differences. Folders are skipped.
  For text files a full-screen compare-and-merge window opens: two columns with line numbers, the differences marked in the middle and the changed part of a line highlighted (`~` changed, `<` only on the left, `>` only on the right). **Ctrl+Down** and **Ctrl+Up** (or **Tab** and **Shift+Tab**) move between differences, **Ctrl+Left** and **Ctrl+Right** scroll long lines, **Right** copies a difference from left to right, **Left** from right to left, **Ctrl+Z** undoes a copy, **Ctrl+S** writes the changed files with their original encoding and line breaks. **Esc** closes the window; with unsaved changes press it again to close without saving. Binary, very large (over 16 MB or 60000 lines) and identical files are shown in the earlier summary window.
<!--compare-folders-->- **Ctrl+Shift+C** – compare folders: both panels select the files missing on the other side and the newer of same-named ones; same time but a different size selects both.

Details of the comparison:
- Folders are selected only when missing on the other side.
- The current panel lists are compared, without subfolders, so it works in archives and on SFTP too.
- The dialog asks what counts as a difference: time, size, content.
- Content is compared byte by byte, only for same-size files on disk, and runs in the background (Esc cancels).

---

[Contents](index.md)
