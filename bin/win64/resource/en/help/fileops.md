## File operations

| Key | Action |
| --- | --- |
| F3 | view a file; on folders – calculate the size of the selected folders (Esc – cancel) |
| F4 | edit |
| Shift+F4 | create a file |
| F5 | copy |
| Shift+F5 | copy under another name in the same folder |
| F6 | move / rename |
| Shift+F6 | rename the item under the cursor |
| F7 | create a folder |
| Alt+F6 | create a link (symbolic link, hard link, junction) |
| F8, Del | delete to the Recycle Bin |
| Shift+F8, Shift+Del | delete permanently (wipe) |
| Ctrl+A | attributes, owner and dates (created / modified / accessed) |
| Alt+Enter | the Windows “Properties” window (for the selection or the item under the cursor; files and folders on disk only) |
| Shift+F10, Menu key | the Windows context menu (for the selection or the item under the cursor) |
| Ctrl+Alt+C | compare the files under the cursors of both panels, or the two marked files of the active panel; the dialog shows size, modified time and a content verdict |
| Ctrl+Alt+H | checksums (MD5, SHA-1, SHA-256, SHA-512) of the selected files and folders; on a `.md5` / `.sha1` / `.sha256` / `.sha512` file – verify it |
| Ctrl+Alt+N | rename the selected items in one go: name and extension masks, counter, search and replace, letter case |
| Ctrl+C / Ctrl+X / Ctrl+V | copy / cut / paste files through the clipboard |
| Alt+Shift+Ins | copy the full path to the clipboard |
| Ctrl+Shift+Ins | copy only the name (no path) to the clipboard |

**Alt+Shift+Ins** and **Ctrl+Shift+Ins** take the selected items (one per line) or, with nothing selected, the item under the cursor; on `..` – the current folder. Paste the result anywhere with **Shift+Ins** / **Ctrl+V**. A short notice in the bottom right corner confirms the copy (or says there is nothing to copy); it can be turned off in **Options → User interface...**.

<!--attributes-->In the **Ctrl+A** dialog dates are typed in the system date format, time as `hh:mm:ss` (seconds and the time part are optional).
- An empty field keeps the date: that is how dates that differ between the selected files are shown.
- **Current** puts the current time into all three fields, **Original** restores the values read from the files.
- “Process subfolders” applies to the dates too.

The same dialog has the other file flags: **Compressed**, **Encrypted**, **Not indexed**, **Sparse**, **Temporary** and **Offline** (each one: keep / set / clear; compression, encryption and the sparse flag are done by the file system, so a volume without them reports an error).

**Drive root.** For a drive root (**F4** in the **Alt+F1** / **Alt+F2** drive list) the volume (GUID path) and the device are shown at the top; the **System properties** button opens the Windows properties window.

**Windows context menu** – the same menu as a right click in Explorer: “Open with”, “Send to”, archiver, antivirus and version-control items and so on.

**How to open it:** **Shift+F10** or the **Menu** key at the cursor row, **Files → Windows context menu**, or holding the right mouse button on a file for about a second.

**What it acts on**
- From the keyboard and the menu – the selection, or without one the item under the cursor (on `..` – the current folder).
- Holding the mouse button opens the menu of the file under the mouse.

Only for files and folders on disk: archives, SFTP, the Recycle Bin and search results have no Windows menu.

<!--multi-rename-->**Multi-rename (Ctrl+Alt+N).** Files > Multi-rename... renames the selected items of one folder in one go. The name and extension masks understand `[N]` (old name), `[E]` (old extension), `[C]` (counter with start, step and digits), `[Date]`, `[Time]`, `[Year]`, `[Month]`, `[Day]`, `[Parent]`, `[Size]` and the metadata values `[Dim]`, `[Camera]`, `[Artist]`, `[Title]`; other text stays as typed. Search and Replace (optionally a regular expression with `$1`, `$2`) and the letter case apply to the new name. The list under the fields shows the “old -> new” pairs as you type; a name that is empty, invalid, used twice or already taken is marked with `!`, and **Rename** does nothing while any is left. The renaming runs as a background job.

<!--copy-->The copy/move dialog lets you keep all timestamps, copy only newer files, copy the contents of symbolic links and set an exclusion mask. On a name conflict the program asks what to do (overwrite, skip, rename, for all…).

---

[Contents](index.md)

<!--admin-->**Protected folders.** When a copy, move, delete, new folder or rename fails with “Access denied” on a local path (for example in `C:\Program Files`), the error window offers **Admin**, and new folder and rename ask “Repeat as administrator?”.

**How it works**
- After a yes Windows shows its usual UAC prompt and MTN2 starts a small helper process with administrator rights.
- The failed item and the rest of the job run there, with the same progress and error windows.
- Nothing runs with these rights before you confirm.
- While the helper runs the window title shows **[Admin helper]** and a notice says so; it ends by itself after two minutes without work, or when MTN2 closes.

**Limits**
- The helper only copies, moves, deletes, creates folders and saves text on local paths: it cannot start programs, and only the MTN2 that started it can talk to it.
- Archives and virtual folders have no such step.

**MTN2 as administrator.** If MTN2 itself is started as administrator (right click, Run as administrator) the title shows **[Administrator]** and no helper is needed; Windows then blocks drag and drop from non-elevated programs such as Explorer.
