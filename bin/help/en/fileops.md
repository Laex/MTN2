# File operations

| Key | Action |
| --- | --- |
| F3 | view a file; on folders — calculate the size of the selected folders (Esc — cancel) |
| F4 | edit |
| Shift+F4 | create a file |
| F5 | copy |
| Shift+F5 | copy under another name in the same folder |
| F6 | move / rename |
| Shift+F6 | rename the item under the cursor |
| F7 | create a folder |
| Shift+F7 | create a link (symbolic link, hard link, junction) |
| F8, Del | delete to the Recycle Bin |
| Shift+F8, Shift+Del | delete permanently (wipe) |
| Ctrl+Shift+A | attributes, owner and dates (created / modified / accessed) |
| Alt+Enter | the Windows “Properties” window (for the selection or the item under the cursor; files and folders on disk only) |
| Ctrl+Alt+C | compare the files under the cursors of both panels |
| Ctrl+Alt+H | checksums (MD5, SHA-1, SHA-256, SHA-512) of the selected files and folders; on a `.md5` / `.sha1` / `.sha256` / `.sha512` file — verify it |
| Ctrl+C / Ctrl+X / Ctrl+V | copy / cut / paste files through the clipboard |
| Ctrl+Alt+Ins | copy the full path to the clipboard |

In the **Ctrl+Shift+A** dialog dates are typed in the system date format, time as `hh:mm:ss` (seconds and the time part are optional). An empty field keeps the date: that is how dates that differ between the selected files are shown. **Current** puts the current time into all three fields, **Original** restores the values read from the files. “Process subfolders” applies to the dates too.

The copy/move dialog lets you keep all timestamps, copy only newer files, copy the contents of symbolic links and set an exclusion mask. On a name conflict the program asks what to do (overwrite, skip, rename, for all…).

**Checksums.** They are calculated in the background (Esc — cancel). In the result list: **Copy** — to the clipboard, **Save** — to `<file>.sha256` (one file) or `checksums.sha256` in the panel folder. Verification marks every line `OK`, `FAILED` or `MISSING`. Lines `hash *name`, `hash  name` and `SHA256 (name) = hash` are understood.

---

[Contents](index.md)
