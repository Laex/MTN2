## Synchronization and comparison

<!--dir-sync-->- **Ctrl+Alt+S** – synchronize the folders of the active and passive panels: one-way or two-way; the dry-run check box shows what would be done without changing anything.
- In the synchronization dialog every difference is a list row with its action: `->` copies to the right, `<-` to the left, `--` skips; conflicts start as skipped. The **Right**, **Left** and **Skip** buttons set the action of the selected row (a manual choice is marked `*`), **Reset** returns the automatic one, and **Only skipped** shows the rows that still need a decision. Differences left skipped stay open for the next synchronization.
<!--compare-files-->- **Ctrl+Alt+C** – compare the files under the cursors of both panels, or the two marked files of the active panel; the dialog shows size, modified time and a content verdict.
<!--compare-folders-->- **Ctrl+Shift+C** – compare folders: both panels select the files missing on the other side and the newer of same-named ones; same time but a different size selects both.

Details of the comparison:
- Folders are selected only when missing on the other side.
- The current panel lists are compared, without subfolders, so it works in archives and on SFTP too.
- The dialog asks what counts as a difference: time, size, content.
- Content is compared byte by byte, only for same-size files on disk, and runs in the background (Esc cancels).

---

[Contents](index.md)
