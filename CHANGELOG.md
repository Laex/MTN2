# What's new in MTN2

**English** | [Русский](CHANGELOG.ru.md)

This file describes what changes for the user from version to version: new features, fixed bugs and changes in behavior. The "Unreleased" section lists what will go into the next version.

## Unreleased

## v0.5.5 – 2026-11-09

### New

- The JSON and YAML tree plugin: Enter on a `.json`, `.yaml` or `.yml` file opens it like a folder. Objects and arrays are folders, values are files; the Value and Type columns show the content, F3 views a value, F5 copies a value or a whole subtree out as text. Read-only. YAML: the common subset (no anchors, aliases or tags).
- The Everything plugin (Windows): Plugins > Everything search asks for a query and opens the results of the Everything program as a panel (`everything:///query`). The rows are the real files, so F3, F4, F5, F6 and F8 act on them. Needs Everything running.
- The Rclone plugin: the storages configured in rclone (Google Drive, OneDrive, Dropbox, S3, Yandex Disk and dozens of others) open as folders of the panels (`rclone:///`, Change Drive list). Browsing, viewing (F3), editing (F4), copying and moving (F5, F6), making folders (F7) and deleting (F8) work between a storage and a local folder or between two storages. Needs `rclone` in PATH and a configured storage.

### Changed

- The Change Drive list (Alt+F1 / Alt+F2) holds up to ten items from plugins; the items after the ninth are marked with the symbols `!`, `@`, `#`, `$` and `%` (also the hotkeys in the dialog), which no drive letter uses.
- A plugin can switch off F-keys for its folders: an empty caption in the function bar also makes the key do nothing there (the Rclone list of storages, the JSON tree, Everything results).

### Fixed

- A JSON, YAML or other file opened by a plugin as a folder no longer ends with "Path not found", and ".." at its top leads back to the folder of the file.
- A huge JSON file is refused with a clear message instead of an error (the tree takes files up to 200 MB).
- The Rclone panel is no longer empty when rclone prints a notice before the listing (for example about a shared Google Drive client id).
- The PowerShell 7 (pwsh) profile starts even when pwsh is not in PATH (for example after a Store update left an outdated PATH entry): the per-user alias and the standard install folder are tried too.

## v0.5.4 – 2026-11-08

### New

- Pinning a panel tab: `Ctrl+Alt+T`. A pinned tab is highlighted with the theme's accent color, stays in its folder (navigating to another folder opens a new tab) and cannot be closed until it is unpinned; the state is kept between launches.
- A Total Commander-style keymap example: `docs/keymap-presets/keymap.tc.json` (Alt+F5/Alt+F9 – pack and unpack, Ctrl+A – select all, Ctrl+M – rename by rules, Ctrl+P – folder path to the command line, Ctrl+Tab – tabs, Alt+Down – folder history).
- Informational command-line switches (Windows and Linux): `--version`, `--paths` (program, settings, plugin, resource and theme folders), `--list-commands` (built-in commands with their keys), `--list-plugins`, `--check-keymap [file]` (checks `keymap.json`: unknown actions and keys, one key bound to two commands) and `--export-theme [id]` (a theme as JSON).
- Search results (Alt+F7) can be saved: `Ctrl+Alt+F7` (Commands menu – "Found items to Workspace") adds links to the marked items to the workspace links panel, or to all items if nothing is marked, and opens it in the other panel. Files with identical names get a number, and items already added are not repeated. If the workspace is not empty or saved sets exist, a choice is offered: add to the current set, replace it, create a new one or add to a saved one; a modified set is saved before it is replaced. A set is saved and restored the same way as a workspace: `Ctrl+Alt+Shift+D` and `Ctrl+Shift+D`.
- `--shell-init bash|zsh|fish|powershell` prints an `mtn` function: after the program exits, the shell changes to the folder that was open in the active panel.
- Releases now include a `SHA256SUMS` file with checksums of all archives and packages and a list of third-party components in CycloneDX format.
- Mask groups: in any mask (selection, panel filter, search, color groups) an `@Name` entry expands to a named set, for example `@Images` or `*.log;@Documents`. Images, Audio, Video, Documents, Archives and Sources are built in; custom groups are created in the select-by-mask dialog (the "Save as mask group" field) and in the list under Options – "Mask groups...", where they can be edited and deleted; they are stored in `maskgroups.json` in the settings folder. In a dialog's mask field (selection, filter, search) `Ctrl+G` saves the entered masks as a group named after the first mask.
- Column sets: in the column mode menu, named sets are listed under "Custom" (Minimal, Dates and Technical are built in); in the "Custom columns" dialog the current choice can be saved under a name in the "Save as column set" field (file `columnsets.json`).

### Changed

- File copying writes data to a temporary `name.mtnpart` file alongside and renames it once the file is fully written. An interrupted, canceled or crashed copy no longer leaves a truncated file under the real name.

### Fixed

- Drop-down lists (mask and command history, lists in dialogs) attach to the field without a gap: a block of the same width directly below the field (or above it) with a shadow and the row colors of the selected theme.
- Themes gained the `dialog.listBg` role – the background of lists and drop-down lists in dialogs. If a theme does not define it, a color slightly lighter or darker than the dialog body is used (10% of the text color), so the list stands out in any theme. The "Mask groups" dialog became wider, and groups are shown in columns: name, the "built-in" mark, masks.
- Retrying a file copy after an error no longer returns the error of the previous attempt.

## v0.5.3 – 2026-11-08

### New

- Three-line footer of the file panel: the "Free ... on disk" line shows the percentage of free space and a bar behind the text: the used part is darker than the free part, with a one-cell margin at the edges.

### Changed

- File copying and unpacking from zip read and write in 256 KB blocks instead of 64 KB: fewer system calls, faster on large files and network folders.

### Fixed

- "Columns" dialog: after OK the active panel switches to the "Custom" mode, so the chosen columns are visible immediately (previously the changes only showed after switching the mode manually).
- Linux: a panel left open on a plugin folder (`svc:`, `proc:` and the like) is restored with its contents on the next launch instead of showing a "Path not found" error.
- Linux, services panel (`svc:`): the PID column shows the identifier of the service's main process; previously the column was empty.
- 7z and other archives via the 7-Zip plugin: files with two dots in the name, for example `v1..2.txt`, no longer disappear from the list.
- Windows: arguments of external programs (Git, Docker, Lua plugins) that contain a quote inside or end with a backslash, for example the path `C:\My Dir\`, are passed intact and are not merged with the next argument.
- Windows: plugin libraries and their dependencies are no longer searched for in the current directory, so a DLL with the same name planted there is not loaded.
- Update: if no checksum is published for a package, a question is shown before downloading asking whether to install an unverifiable update; in the console `--update` command such a package is installed only with the `--allow-unverified` switch.

## v0.5.2 – 2026-11-08

### New

- A "Show a slash after directory names" checkbox was added to the interface settings (on by default): with it off, folder names in the file list are shown without a trailing slash.
- Linux: during copying and other background tasks, terminals that support a progress indicator (Windows Terminal, ConEmu, Ghostty, WezTerm, GNOME Terminal and others on VTE 0.80+) show it on the tab or in the title; the indicator is removed when the task finishes. It can be disabled with the environment variable `MTN2_NO_PROGRESS=1`.
- Linux: Alt+Enter opens the properties window of the system file manager (via `org.freedesktop.FileManager1`); if there is none, the built-in attributes dialog opens.
- Linux: Shift+F10 (and the "Context menu" item) shows a list of programs registered for the file type according to the desktop data (`.desktop`, `xdg-mime`); the chosen program is started separately from MTN2. Programs that run in a terminal are not included in the list.
- Linux (SDL): files dragged into the window from another program are copied to the folder under the pointer, or moved when Shift is held; outside the panels the paths are pasted as text.
- File search (Alt+F7) can be sent to the background with the "Background" button in the search dialog (started in the background right away) or in the regular progress window of a running search (the "Background", "To panel" and "Cancel" buttons). While the progress window is open, the found files are visible in the panel; "Background" returns the panel to its previous folder, and "To panel" closes the window and leaves the panel on the list of found files, which keeps growing. Leaving such a list does not stop the running search: it continues in the background, and a click on its chip shows the progress window and the list again. Each such search is a separate background task with its own chip in the tab row (the chip shows the growing number of found files) and a row in the background jobs list; several can run at the same time. A click on the chip (or selecting the task in the list) brings back the progress window and shows the found files in the panel, and the list keeps growing while the search runs; a finished search opens its results immediately. Stopping leaves the found files in the panel. The search and its result disappear when the panel leaves the list of found files.
- Linux: the "Processes and services" plugin now works on Linux too: the drive list gains "Processes" (`proc://`, data from `/proc`, F3 – details, F8 – terminate with SIGTERM) and "Services" (`svc://`, systemd services via `systemctl`, coloring by state, start, stop and restart from the Plugins menu). The registry and suspending and resuming services remain Windows-only.
- File comparison (Ctrl+Alt+C) works with groups of marked files. If two or more files are marked, files with the same names are compared: with marks in both panels – only the marked ones, with marks in one panel – against the same-named files of the other panel. The resulting list shows which pairs are identical and which differ; Enter on a pair opens the differences. After the differences are closed, the list returns with the same file selected. Folders and files without a pair are skipped and counted in the summary line as not compared. Without marks, comparing the files under the cursors works as before.

### Changed

- The background search chip in the tab row shows the number of found files and updates it as the search progresses.
- The history drop-down list in input fields (the Alt+F7 mask and others) opens on the most recently used entry rather than on the entry matching the field text; the order is by last use.
- Deleting a busy file or folder: retry attempts were shortened from ~0.7 s to ~0.06 s, and the window with the reason for the failure appears almost immediately.

### Fixed

- Security: when copying a folder from a ZIP archive, entries with `..` in the name (for example `dir/../x`) are no longer written outside the destination folder.
- Security: links in documents are opened in an external program only for the `http`, `https`, `mailto`, `ftp` and `ftps` schemes; other schemes are rejected. The update package is downloaded only over `https`.
- Files with very long paths (over 260 characters) now take part in content search, folder comparison, unpacking from ZIP and appending to the end of a file; previously such operations failed on them.
- Renaming a file or folder where only the letter case changes (for example `report.txt` to `Report.txt`) previously did nothing or ended with an overwrite question; now the name changes.
- Alt+F7 search with subfolders does not enter symbolic links and junctions to folders: a link to a parent folder used to make the traversal loop.
- If the folder in which one of the panels stands is deleted (for example from the other panel), the panel moves to the nearest existing parent folder instead of staying with a "Path not found" message. The same applies when switching to another drive whose remembered folder no longer exists.
- Viewing through a plugin (images and other plugin windows): the 5 key on the numeric keypad, which opens a file from the panel, now also closes the viewer window, as in the text viewer. If the plugin uses this key itself, it stays with the plugin.
- ZIP archives created on macOS and in some Linux programs: Russian file and folder names are no longer shown as garbled text. If a name in the archive is not marked as UTF-8 but its bytes are valid UTF-8, it is read as UTF-8; otherwise it is read in the OEM encoding as before.

## v0.5.1 – 2026-11-07

### New

- Color coding: a group gained a "Condition" field – size (`size>10M`), age (`age<7d`, `age>30d`) and attributes (`+H` hidden, `-R` not read-only, and so on). A group applies (and sets the sort priority) only if both the mask and the condition are met.
- List grouping (Ctrl+Alt+G, the "Group by type / date" item in the Commands menu): panel rows are ordered by groups – by type (folders, images, audio, video, documents, archives, programs, code, other) or by date (today, yesterday, last 7 days, last 30 days, last year, older); within a group the selected sort order applies, the start of a group is labeled, and the background of neighboring groups alternates. The mode is stored per panel.
- Metadata plugin: new "Album" and "Year" columns (MP3) and "Version", "Company" and "Description" columns (EXE, DLL, SYS, OCX, SCR on Windows); versions are sorted by number, not by text. The columns are added in the "Custom" mode.
- Paired folders (Ctrl+Alt+P, the "Paired folders" item in the Commands menu): entering a subfolder or going up one level in one panel is repeated in the other if it has a folder with that name (or the parent). Works for ordinary local folders; the setting is stored in the tab and kept between launches.
- Unpacking into a protected folder: on "Access denied" the error window shows an "Admin" button. MTN2 itself reads the archive, while the administrator helper writes to the folder (through a temporary folder).

### Changed

- Permanent deletion of a folder: if there are no rights for a single file inside, the error window asks about that file. "Skip" leaves only it (and the folders above it) and deletes the rest; "Skip all" and "Admin" are also available at the file level.
- The file compare and merge window (Ctrl+Alt+C) takes the whole screen instead of a dialog: lines of the left and right files are aligned by similarity, so similar lines stand opposite each other and the changed part of a line is highlighted; Tab and Shift+Tab for moving between differences, mouse wheel scrolling and clicking a line were added. As in the viewer and editor, there is an F-key row at the bottom (F2 – save, F3/F4 – next and previous difference, F5/F6 – copy right and left, F8 – revert, F10 – exit) and a status line.
- The prompt to repeat an operation as administrator was reworded: "Access denied. Repeat as administrator?".

### Fixed

- The "Repeat as administrator?" prompt is no longer truncated in the Russian locale: the confirmation window widens to fit the text.
- Error windows with the "Admin" button (deletion, I/O) widen to fit the button translations, and the outermost "Cancel" button has its shadow again.
- Deleting a folder without rights (for example in `C:\Program Files`) with Shift+Del now immediately offers to repeat as administrator: the tree traversal stops at the first access denial, and retries on denial were shortened, instead of minutes of waiting.
- Unpacking ZIP and 7z into a folder without write permission reports "Access denied" instead of "The system cannot find the path specified".

## v0.5.0 – 2026-11-05

### New

- "PDF Viewer" plugin: F3 on a `.pdf` shows the pages as images (PDFium), so text with non-standard fonts and scans look as in a regular viewer. Keys: PageUp/PageDown and Space scroll through pages, Home/End – first and last page, `+`/`-` change the zoom, `0` – whole page, `w` – fit width, the mouse wheel scrolls, Ctrl+wheel changes the zoom. Quick view (Ctrl+Q) shows the text of the document; the plugin settings can enable showing pages as images always or only for a document without text (a scan); Tab opens the full viewer in the panel (pages, zoom, mouse wheel and dragging), and Tab or Esc return the file panel. If `pdfium.dll` is not found, the "Document Viewer" plugin opens the PDF as text.
- File comparison (Ctrl+Alt+C) for text files opens a compare and merge window: two columns with line numbers, differences marked in the middle; Ctrl+Down/Ctrl+Up move between differences, Right and Left copy a difference to the chosen side, Ctrl+Z undoes, Ctrl+S saves the modified files with their original encoding and line endings. Binary, very large and identical files are shown in the previous summary window.
- "Document Viewer" plugin: F3 on `.docx`, `.xlsx`, `.pptx`, `.pdf`, `.svg` files and SQLite databases (`.sqlite`, `.sqlite3`, `.db`, `.db3`) shows their text: paragraphs, sheet rows, slide and page text, an SVG summary with source indentation, a database schema with the first rows of the tables. PDF text with fonts in a custom encoding is not decoded. F4 still opens the editor. Quick view (Ctrl+Q) shows the same texts for files up to 16 MB; viewing `.csv` tables works the same way.
- "Plugins..." window: the "Add..." button installs a plugin from a folder or a `.zip` file (with `plugin.json`), and the "Remove" button deletes the folder of the selected plugin. An installed plugin is off until it is enabled in the list; a plugin with the same identifier is replaced after confirmation, and an archive with paths outside the plugin folder is rejected.
- Lua macros gained access to the editor, panels, clipboard and dialogs: `mtn.editor.*` (text, selection, lines, replace, cursor), `mtn.panel.*` (file list, navigation, cursor, marks by mask), `mtn.clipboard.*`, `mtn.input`, `mtn.confirm`, `mtn.choose`. `mtn.exec` runs an external program and returns its output, but only from the list in the macro's `exec` field (for example `exec = "git"`). A call to `mtn.on(topic, function)` in a macro file runs the function on program events: opening, saving, changing and closing a document, changing the folder and cursor in a panel. The description is in the "Macros" plugin help; the new `word-count.lua` sample counts lines and words.
- A Lua macro can add its own column to the file panels: `mtn.column{id, title, width, align, default, value}`, where `value` is a Lua function that receives the name, path, folder flag and file size and returns the cell text. The column appears in the "Columns..." window, and values are recalculated when the folder changes; the new `size-kb.lua` sample shows the size in kilobytes.
- Background jobs: the jobs list (Ctrl+Shift+J) gained the "Pause", "Up", "Down" and "Speed" buttons. Pause stops copying at the next block (the `||` chip) or holds the job in the queue; "Up"/"Down" change the start order; "Speed" limits copying between local folders (1, 5, 20, 100 MB/s). Copying and moving on the same disk now run in turn rather than interleaved.
- Batch rename (Ctrl+Alt+N): masks gained the tokens `[Date]`, `[Time]`, `[Year]`, `[Month]`, `[Day]` (modification date and time), `[Parent]` (folder name), `[Size]` (size) and `[Dim]`, `[Camera]`, `[Artist]`, `[Title]` (values of the metadata plugin columns); tokens can be typed in any case. The "Regular expression" checkbox turns "Search" into a pattern, and `$1`, `$2` are available in "Replace"; an invalid pattern leaves the names as they are. The token hint is in the window itself.
- Folder synchronization (Ctrl+Alt+S): in the list of differences each file has its own action – `->` right, `<-` left or `--` skip. The "Right", "Left" and "Skip" buttons change the action of the selected row (a manual choice is marked with `*`), "Reset" restores the automatic one, and the "Only skipped" checkbox shows the rows without a decision. A conflict can be resolved in either direction, and a new file can be left in place. The list scrolls and shows all differences, not the first twelve; the status line counts copies and skips according to the chosen actions.
- "Vertical lines between columns" option (Options – User interface): vertical lines are drawn between panel columns in the "Full" and "Custom columns" modes, including in the header. Off by default; in the brief mode the lines are always there.
- "Quick search also filters the panel" option (Options – User interface): with quick search by Alt+letter, besides moving the cursor to the found file, only files whose names start with the typed text remain in the panel; the search field stays open after Alt is released until Esc or Enter is pressed, which return all files; Backspace widens the list. The "Fuzzy quick search filter: letters in order" option also keeps names in which the typed letters occur in order, not necessarily consecutively (for example, "mnr" finds "main_readme.txt"). The additional "Keep the quick search filter in other folders" option keeps the filter when entering a folder with Enter or a mouse click: then only Esc removes it. Off by default.
- The metadata plugin columns ("Size px", "Camera", "Artist", "Title") can now be sorted – by clicking the header or in the sort menu; "Size px" orders by the number of pixels. Plugins can send numeric column values for local folders.
- Drive change window (Alt+F1/F2): the used space of a volume is shown as a pale bar behind the total size and free space columns; the text does not change.
- Plugin columns (for example, "Size px" of the metadata plugin) can now be enabled in the "Custom columns" window for local folders as well.
- Linux: the "PDF Viewer", "Document Viewer" and "CSV Table" plugins find a file by a `file:///...` address and open it on Linux; the PDFium library (`libpdfium.so`) is included in the archive and in the `.deb` / `.rpm` packages.
- Linux: copying and moving from one disk (mount point) are queued, as on Windows with a single drive letter.

### Fixed

- Linux: the "Line Filter" and "Macros" plugins open the file in the editor and save the macro result under the correct path (previously the path was built as on Windows).
- Linux (window): a PDF page no longer stays on screen after the viewer is closed.
- Tab in quick view (Ctrl+Q) on an image no longer closes the view and no longer returns the file panel: the keyboard moves to the viewer, and Tab or Esc return it back.
- If a plugin could not read a folder (for example, `kubectl` in the `kubernetes` folder of the Docker plugin could not reach the cluster), the row with the error text no longer triggers the "Invalid characters in file name" window when selected or when Enter is pressed on it.

Earlier versions are on the [releases](https://github.com/Laex/MTN2/releases) page.
