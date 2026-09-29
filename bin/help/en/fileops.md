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
| Ctrl+Alt+C | compare the files under the cursors of both panels |
| Ctrl+Alt+H | checksums (MD5, SHA-1, SHA-256, SHA-512) of the selected files and folders; on a `.md5` / `.sha1` / `.sha256` / `.sha512` file – verify it |
| Ctrl+C / Ctrl+X / Ctrl+V | copy / cut / paste files through the clipboard |
| Alt+Shift+Ins | copy the full path to the clipboard |
| Ctrl+Shift+Ins | copy only the name (no path) to the clipboard |
| Ctrl+Z | describe the file: an input line, the text is kept in `Descript.ion` next to the file |

**Alt+Shift+Ins** and **Ctrl+Shift+Ins** take the selected items (one per line) or, with nothing selected, the item under the cursor; on `..` – the current folder. Paste the result anywhere with **Shift+Ins** / **Ctrl+V**. A short notice in the bottom right corner confirms the copy (or says there is nothing to copy); it can be turned off in **Options → Font / Display...**.

In the **Ctrl+A** dialog dates are typed in the system date format, time as `hh:mm:ss` (seconds and the time part are optional). An empty field keeps the date: that is how dates that differ between the selected files are shown. **Current** puts the current time into all three fields, **Original** restores the values read from the files. “Process subfolders” applies to the dates too.

**Windows context menu** – the same menu as a right click in Explorer: “Open with”, “Send to”, archiver, antivirus and version-control items and so on. It opens with **Shift+F10** or the **Menu** key at the cursor row, from **Files → Windows context menu**, or by holding the right mouse button on a file for about a second. From the keyboard and the menu it acts on the selection, or without one on the item under the cursor (on `..` – on the current folder); holding the mouse button opens the menu of the file under the mouse. Only for files and folders on disk: archives, SFTP, the Recycle Bin and search results have no Windows menu.

The copy/move dialog lets you keep all timestamps, copy only newer files, copy the contents of symbolic links and set an exclusion mask. On a name conflict the program asks what to do (overwrite, skip, rename, for all…).

**Checksums.** They are calculated in the background (Esc – cancel). In the result list: **Copy** – to the clipboard, **Save** – to `<file>.sha256` (one file) or `checksums.sha256` in the panel folder. Verification marks every line `OK`, `FAILED` or `MISSING`. Lines `hash *name`, `hash  name` and `SHA256 (name) = hash` are understood.

---

[Contents](index.md)
