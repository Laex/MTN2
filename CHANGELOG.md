# What's new in MTN2

**English** | [Русский](CHANGELOG.ru.md)

This file describes what changes for the user from version to version: new features, fixed bugs and changes in behavior. The "Unreleased" section lists what will go into the next version.

## Unreleased

### Fixed

- Copying only newer files, overwrite-newer, folder synchronization and Compare folders now share one rule for which file is newer: when both modification times carry fractions of a second they are compared almost exactly, and the two-second tolerance applies only when one of them is a whole-second time (FAT, some network shares). Files copied to such volumes are no longer reported as newer because of timestamp rounding.
- After a copy, move, pack or unpack that ended early (cancelled, stopped by an error) or skipped some items, the items that did go through are deselected in the panel and the rest stay selected, so the selection shows what is still to be done. Ctrl+M brings the whole selection back.
- A search by text in a folder on a network share found nothing when the Everything plugin was used to list the files: Everything does not index network shares. The names are now listed by the built-in walk in that case.

## v0.5.12 – 2026-11-23

### New

- In the connection list of the network plugin, F5 and Shift+F5 copy a saved connection under a new name, and F6 renames it.
- The synchronization dialog has a Mirror mode: files that exist only on the target are marked `XX` (delete; the `X` key sets it by hand). The mode starts with the dry-run box on, so the first run only reports the count. The deletion follows a successful copy and asks for confirmation; the files go to the Recycle Bin unless "Delete extras for good" is ticked. The Extras to panel button lists the target-only files in the Temporary panel for review.
- The synchronization and search dialogs keep named presets: the current mode and options are saved under a name, loaded from a list and deleted again.
- The synchronization dialog shows the progress of the folder comparison (files and folders scanned, then files compared). Esc sends the comparison to the background, where it keeps a chip and a job list entry until it finishes; opening the chip shows the plan.
- A dialog before the folder comparison asks for the mode, the comparison kind and what to leave out: junctions (skipped by default), .gitignore, .geminiignore and .obsidianignore patterns, a robocopy exclude.rcj, Obsidian ignore filters and extra patterns.
- The multi-rename dialog has "In editor": the new names open in the built-in editor, one per line; after saving and closing it the dialog returns with those names, checked for empty, invalid, duplicate and taken names like the rest. The number of lines must stay the same.
- The multi-rename dialog has "Undo last": it takes the previous batch back, renaming each item whose new name still exists and whose old name is free to its old name and leaving the rest as they are. The last batch on local disks is remembered between runs; undoing it clears the record.
- `F3` on the `..` row calculates the size of every folder of the panel. Calculated folder sizes stay in the Size column after the panel leaves the folder and returns, until the folder changes.
- The "File already exists" prompt has three more answers: overwrite if the existing file is older, overwrite if the size differs, and automatic rename (`name (2).ext`, the first free number). With "Remember choice" the rule is applied to every following conflict of the job, file by file; a pair a rule cannot judge (a folder against a file) is still asked about. The copy dialog's "Already existing files" list offers the same three choices up front.
- The copy and move dialog has "Verify after copying": each file written is compared byte by byte with its source before it replaces the destination. A difference is reported as an error of that file, with the usual retry / skip / cancel.
- The job list has "When the queue ends": do nothing (default), sleep, shut down or close the program. The action is armed for one run, fires after the last job finishes without errors or cancels, asks first and goes ahead by itself after 30 seconds.
- The top menu (≡ menu, Help) has "What MTN2 can do": a help page that lists the program's features by task (find a command, move around, select and rename files, search and compare, view and edit, console and terminals, tabs and workspaces, settings) with the keys and links to the details. The page is in the help contents too, in English, Russian, German and Chinese.
- The help has a "Recipes" page with short answers to common tasks (copy, find, rename many files, compare folders, unpack an archive, return to a folder, terminals, remote servers, moving the settings), in English, Russian, German and Chinese.
- From the third run on, the program shows one short tip per run about a feature you have not used yet (the command search, multi-rename, the folder hotlist, paired folders, comparison, Quick View, terminals, the folder tree, grouping, checksums, workspaces) with its current keys. A feature you already use is skipped and each tip appears once. The "Reset hints" button brings the tips back; the key hints switch turns them off.

### Changed

- After an update, the "What's new" button of the announcement opens only the changelog sections between the previous version and the installed one, instead of the whole changelog.
- The first run of the program opens the "What MTN2 can do" help page.
- The file search dialog has two tabs ("Search" and "Filters") and the attributes dialog has three ("Attributes", "Dates", "Owner"), so both fit an 80x24 terminal. In dialogs with tabs, the rule under the tab strip opens under the shown tab.
- The plugin permissions dialog is compact when a plugin asks for no permissions. The attributes dialog highlights the file name and, for several items, shows how many files and folders are selected.
- The network connections dialog of the network plugin has a cleaner layout, and its host-key and certificate prompts have tidy buttons. The "Set mode" dialog is translated, and a few menu hotkeys that clashed in German and Chinese are fixed.

### Fixed

- On Linux, replacing an existing folder on copy works again instead of failing with "file not found".
- Updating a 7z archive (adding, deleting or editing files inside) replaces it in one step on Windows, so a failure no longer leaves the archive missing.
- Saving a text file restores its previous content when the write fails half way, for example on a full disk.
- Exporting settings to an existing file keeps that file if the export fails.
- Installing, replacing and removing a plugin folder no longer follow a link into the folder it points at.
- Deleting the root of a drive, a network share, the file system or an FTP/SFTP server is refused, including delete with administrator rights.
- Replacing a folder on copy, cleaning up a failed copy and moving a folder from an SFTP session no longer follow links into the folders they point at.
- Permanent delete of a junction or a folder symbolic link on Windows no longer wipes the files in the folder it points at: only the link is removed. The same applies to links inside a deleted folder and to the source folder of a move between drives.
- Backslashes in dialog fields (for example a Windows path in the key file field of a connection) are kept as typed; before, a sequence such as backslash-n or backslash-t in a path turned into a control character and the value was saved broken.
- SFTP / SCP with a key file: an encrypted key now asks for its passphrase before the first connection, a wrong passphrase is asked again, and a key the server rejects shows the reason instead of failing silently. A missing key file and a PuTTY (.ppk) key, which the plugin cannot read, are reported with an explanation (export the key in OpenSSH format with PuTTYgen).
- Cancelling the login question of a network connection returns the panel from "Waiting for the server..." to a "Cancelled" row with a way back to the list of connections. Errors of network connections show the server's own message instead of "Access denied".

## v0.5.11 – 2026-11-22

### New

- Links (symbolic links and junctions) in the file panels carry a marker before the name: `~` for a folder, `@` for a file. A link keeps the color of a regular folder or file of the same type. The "Mark links" option in the Interface settings turns the marker off.
- In the Folder map plugin, Ctrl+click or Shift+click on a tile shows it in the file panel and closes the map, like the G key. Quick View stays open and follows the cursor in the new folder.
- In the Folder map plugin, Backspace (or the right mouse button) at the top of the scanned folder maps the folder above it, up to the root of the disk, and selects the folder you came from.
- The Folder map plugin: the mouse wheel enters and leaves folders, End selects the last tile, F5 or Ctrl+R scans the folder again, G also works on a Russian layout, and a click gives the keyboard to the map.
- The Folder map status line shows the folder in view, the selected tile and a key reminder, nested folder headers show their size, and Enter on a file, an empty folder or one still being scanned says why nothing happened.

### Changed

- The Interface dialog is split into the tabs Window, Panels and Behavior, so it fits an 80x24 terminal; the tabs switch with a click, Ctrl+PgUp/Ctrl+PgDn or Ctrl+Tab.
- The Markdown colors dialog is split into the tabs Text, Emphasis, Blocks and Links and tables and fits an 80x24 terminal.
- Dialogs wider than the screen (Mask groups, Multi-rename, Synchronize, File history, Plugins and others, also in translated captions) are squeezed to fit an 80x24 terminal instead of losing their right part: fields and lists get narrower first, then spare cells of captions; buttons stay whole.
- Dialog descriptions (plugins and built-in windows) can have tabs: a `tabs` control and a `tab` number on the controls of each page.
- The sets Minimal, Dates and Technical are no longer created in `columnsets.json`; the built-in wide variants are listed first in the sets list of the Columns dialog. Existing files keep their sets.
- The column modes menu lists two kinds of view: Brief, and Wide with the built-in variants (size, date, full, created, types) followed by your own column sets.
- In the Custom columns dialog the columns of a plugin are listed under the name of the plugin, apart from the built-in ones.
- While the "Paired folders" mode is on, the status line shows a "Paired" marker; a click on it turns the mode off. The mode is no longer kept between launches and is off after every start.
- Tab or Esc in the Folder map plugin returns the keyboard to the file panel without discarding the map.
- With the cursor on `..`, the Folder map plugin in Quick View (Ctrl+Q) shows the map of the current folder, so the folder you have just entered and the whole disk stay in view.

### Fixed

- In a console or terminal tab, Enter pressed in a running console or full-screen program (Far Manager, vim) no longer sends an extra line feed; in Far it opened Explorer on `..` as if Shift+Enter had been pressed.
- While a console program such as Far Manager is running and the profile's keys mode is "while running" or "terminal", PgUp, PgDn, Insert and Shift with the arrow, Home and End keys go to the program instead of scrolling or selecting in the window.
- Copying a folder out of an archive (7z, RAR and others, F5) unpacks the whole folder in one pass. Before, every file was unpacked on its own, and in a solid archive that meant reading it again from the start each time: a 30 MB RAR with about 1300 files took minutes, now it takes about a second. [#106](https://github.com/Laex/MTN2/issues/106)
- In the built-in themes, color coding by extension (archives, temporary files and so on) applies to files only: a folder named like `name.7z` or `name.tmp` keeps the folder color. Themes you saved earlier keep their groups as they are; choose "Files only" for them in the color coding editor.
- In consoles, the mouse wheel and the keyboard scroll from the current view instead of jumping to an old position. When scrolling hides the last line, following the output of a running program stops, and it resumes once the console is scrolled back to the bottom.
- After leaving a link to a folder that sits next to its target, the cursor returns to the link instead of the target folder, so a delete no longer hits the wrong folder.
- Ctrl+Enter and Ctrl+Shift+Enter no longer paste the "Reading..." or error line of a panel into the command line.
- Folder map: the key that shows a tile in the panel no longer also types its letter into the command line, and the Cyrillic "п" works as G.
- Folder map: Backspace at the top of a whole disk no longer reaches the file panel, so the map stays on the disk.

### Added

- The profile list of the Background console dialog shows the key mode of each profile in a second column, as the New terminal dialog does.
- Two options in the Interface dialog: "Show column headers" and "Show the sort mode letter". With the headers off the list starts one row higher; the sort letter then sits on the top border. [#97](https://github.com/Laex/MTN2/issues/97)
- A fourth key mode for shell profiles, "while running" (F4 in the shell list): the program gets every key while a console program started from the shell, such as Far Manager, is running, and the window's keys apply at the bare prompt. A GUI program launched from the shell does not count. [#105](https://github.com/Laex/MTN2/discussions/105)
- A program that asks for the mouse (Far Manager, `htop`, `mc`) now receives clicks, drags and the wheel over the console or terminal text; hold Shift to select text with the mouse as before. [#105](https://github.com/Laex/MTN2/discussions/105)
- The width of a Brief column can be set (10-50 characters, 28 by default): the "Brief view" field in the Columns dialog; the panel holds as many columns of that width as fit. The column modes menu ends with a separator and a "Settings..." item that opens it. The plugin headings in that dialog are highlighted. [#103](https://github.com/Laex/MTN2/discussions/103)
- Column sets can include the columns that plugins add. A set saved in the Custom columns dialog remembers them for the folder type it was saved in, and choosing the set shows them again.

## v0.5.10 – 2026-11-17

### New

- The Service bridge plugin can connect a service by HTTP address as well as by program: the address takes one POST per JSON-RPC message and answers with a JSON body or an event stream, and the session id it sets is sent back with the next requests. The address and headers are shown for approval before the first request, like a program's command line.

### Changed

- F1 in the settings of the Screensavers and Service bridge plugins opens the help page of the plugin.
- The Service bridge settings show the servers as a list with the columns number, name, type, program or address, and state. Servers can be added, edited, deleted and moved up or down, and Check starts the program or contacts the address and shows in the State column how many tools it offers or why it is not available.
- A text search with a mask or bounds that leave files out in Alt+F7 now runs as a pipeline: the first stage lists the files by name (the Everything plugin or the built-in walk) and the second looks for the text only in those files (the ripgrep plugin or the built-in check). The "Engine" list of the Find dialog is replaced by the "Pipeline" button, which opens a dialog with one list per stage: Auto, Built-in or a plugin that can serve the stage. A text search with an open mask (`*.*`) is still served by one plugin such as ripgrep. Plugin manifests can list the capabilities of their services (`serviceCapabilities`), so the lists need not load the plugins.
- The flat view of Commands > Flat/hierarchical view (Ctrl+B) lists the files through the file-search plugin (for example Everything) when one can serve the folder, and falls back to the built-in walk otherwise.

## v0.5.9 – 2026-11-17

### New

- Alt+F7 file search can be served by a plugin. The Everything plugin answers name searches in local folders from the Everything index (when Everything is running), so results appear almost at once. The ripgrep plugin answers searches by file text with `rg` (found in the PATH or next to the plugin). Searches inside archives or with attribute filters, and searches when Everything or `rg` is not available, use the built-in search as before. The Find dialog has an "Engine" list: Auto picks the best plugin, Built-in always uses the built-in search, or a plugin can be chosen by name (the built-in search runs when that plugin cannot serve the search). Documents (.docx, .xlsx, .pptx, .pdf, .svg, SQLite databases) are now searched by their text when the Document viewer plugin is loaded. The Everything, ripgrep and Document viewer plugins have a Settings option to stop offering their JSON-RPC services.
- The new Service bridge plugin connects external programs (in any language) that exchange one JSON message per line over stdin/stdout as providers of services named `bridge.<server>.<tool>`. The servers are listed in the plugin settings; a program starts only after its full command line is approved there, and a changed command asks again. A sample server is in the plugin folder.
- WASM plugins can provide and call JSON-RPC services: new `service_register`, `service_reply`, `service_notify`, `service_message`, `service_call` and `service_cancel` imports. Calling the services of other plugins needs the new `services.call` permission, which the user grants in the plugin's Permissions dialog; providing a service needs none.
- The "Custom columns" dialog lists the column sets and can edit (load a set into the checkboxes), rename and delete them.
- In consoles, a selection inside the command line is replaced by the next typed character and removed by Del or Backspace. Selecting the command line from the keyboard (Shift+Left, Shift+Home) stops at the end of the prompt.

### Changed

- Ctrl+Shift+F7 opens the Options > Columns... dialog.
- Each file panel has its own columns for custom column sets: choosing a set in the Column modes menu or confirming the "Custom columns" dialog changes only the active panel, and each panel keeps its columns between sessions. The separate "Custom" menu item is gone; the column sets are listed right after the preset modes.
- The sets Minimal, Dates and Technical are created in `columnsets.json` when the file does not exist, and are ordinary sets from then on: they can be edited, renamed and deleted like any other.
- The command-line history list opens right after the prompt (long entries are cut instead of moving the list over the prompt) and is outlined on the left, top and right (with cell edges where the window supports them), the outline one cell left of the text.
- In the Change Drive dialog the current drive is marked with a diamond instead of an asterisk, and its row is drawn in lighter text. The Column modes menu marks the current mode with a diamond too.

### Fixed

- With several tabs on a file panel, a long folder path in a tab title is no longer cut down to the drive and the last folder. The title keeps as many trailing folders as fit after the "..." mark (for example `D:\...\Name\1`).
- The Alt+F7 results overlay shows relative paths for ordinary local hits again: splitting an archive hit no longer clears a plain local path.
- In consoles, keyboard selection (Shift+arrows, Shift+Home/End, Shift+PgUp/PgDn) starts at the current input cursor instead of where the previous selection or search ended.
- Switching to a disconnected network drive no longer freezes the window: the status line reads the folder's `Descript.ion` in the background, and neither the check for a vanished folder nor the parsing of a path with a `!` in a folder name waits on the drive. Leaving such a drive no longer hangs either.

## v0.5.8 – 2026-11-12

### New

- Quick View (Ctrl+Q) shows a map of disk usage when the cursor of the other panel is on a folder: the new `mtn.diskmap` plugin scans the folder in the background and draws a treemap, with a tile for every subfolder and large file, sized by the space it takes. The map fills in as the scan goes on: the large folders appear first, then the folders and files inside them, and every tile grows as its contents are found. A scan stops after 30 seconds or 3 million entries and the map is marked as incomplete. Tab moves into the map: the arrow keys pick a tile, Enter or a double click zooms into a folder, Backspace zooms out, G goes to the picked folder or file in the panel. The Settings window of the plugin has a check box to turn the map off. The map is drawn only in programs with a graphic window (MTN2 and MTN2-sdl); MTN2-tui still shows "(directory)".
- The "Loading..." note of the viewer and the editor is followed by a progress bar when the file size is known, with the percentage, the amount read and the full size under it (for example "45%  7.2 MB of 16.0 MB"). This works for files on disks and network folders, for files inside ZIP archives, for files opened through the `mtn.rclone` plugin and for large files that are first extracted from an archive or fetched from a plugin's file system. Esc now also stops such a read midway instead of waiting for it to end. Once the rate can be told, the line under the bar also shows it and the time left ("1.2 MB/s  0:07 left"), and the window title shows the file name with the percentage while the file loads. The note names the stage ("Loading...", "Extracting...", "Indexing..."), and the bar appears only when the load takes longer than a quarter of a second. A file opened over SFTP shows how much of it has arrived.
- While the size of a loading file is not known, a segment runs back and forth along the bar, so a load that is still going can be told from one that hangs. The rate and the time left stay current between progress reports.
- Opening a remote file (a plugin's file system) that is too large to be read whole now asks first: the file would be downloaded in full to a temporary folder. "Download" starts it; refusing closes the tab. Quick View downloads without asking, as it shows no dialogs.
- Copying and moving files through the `mtn.rclone` plugin shows the progress of the transfer.
- Screensaver pictures now come from the `mtn.screensaver` plugin: it adds the pictures found as libraries (`.dll` on Windows, `.so` on Linux) in the `savers` folder next to it; the sharks, "Starfield" and "Plasma" come with it, and without the plugin the screensaver does not start. All screensaver settings moved from Options > User interface to the Settings window of the plugin. Text-grid pictures work in all three programs (MTN2, MTN2-sdl, MTN2-tui); pixel pictures ("Plasma") work in MTN2 and MTN2-sdl, and MTN2-tui does not list them. The plugin has a Settings window (plugins dialog) with the picture, the start time and a "Random screensaver" check box (a random picture at every start).

### Fixed

- Cancelling an operation of the `mtn.rclone` plugin (Esc while a file loads, cancelling a copy) stops the rclone program at once; it used to carry on in the background until it finished.
- A remote file larger than the viewer's whole-file limit is no longer downloaded in full through the `mtn.rclone` plugin only to show its beginning: the download stops as soon as the size is known and the file opens in the viewer for large files.
- F9 and Alt no longer drop the Left/Right submenu down at once: they only select the category of the active panel, and the submenu opens with Enter, the Down arrow or the category's letter. The highlighted letters of a closed submenu no longer run its items, so F9 and a category letter (for example the one of Options) reach that category instead of an item of Left.
- The highlighted letters in the Files, Edit, Commands and Options dropdowns no longer repeat within one menu in English and Russian: an item whose letter was already taken now gets a free letter from its name, or none when all are taken. German and Chinese keep a repeated letter where the Russian text has one, so the marked items stay the same across languages.
- A macro that presses a button of a dialog with a key (for example Enter on "Save changes?" after Escape in the editor) no longer goes on before the button's command has run: the command runs at once, so the next macro call sees its effect.

## v0.5.7 – 2026-11-11

### New

- The hex editor marks the bytes edited since the file was opened or saved with a different background (in the hex and in the text column); the mark follows inserts, deletes and undo.
- A plugin command or a plugin menu item (Plugins menu) can be given a key from the command palette: Ctrl+K on it opens a field for one key. The choice replaces the key the plugin registers and is kept in `plugin-keys.json` in the settings folder; a key that a built-in action or another plugin command already uses is refused.

### Changed

- PgUp/PgDn also keep the cursor on the same screen row in the hex view and in the viewer with word wrap (Markdown is unchanged).
- In the F5/F6 dialog, for one file or folder a bare name (no `\`, `/` or `:`) that is not an existing folder is the new name of the item: type a new name on F5 to get a copy in the same folder (F6 moves and renames). A name that Windows or Linux would not accept is refused with the reason, and the dialog stays open. A path or a name with a slash still means a folder. Rename (Shift+F6) and copy under another name (Shift+F5) refuse such names the same way, with the reason.
- In the editor, PgUp/PgDn page the view and the cursor together, so the cursor stays on the same screen row as in other editors. Before, the first press moved only the cursor and the text shifted by one line.
- On the first run all plugins are switched on instead of off; turn off the ones that are not needed in Options → Plugins. Existing installations keep their choice.

### Fixed

- A macro that opens a file in the editor (F4) and then sends keys no longer loses them: the macro commands that can start a background read, save or folder listing (`mtn.key`, `mtn.text`, `mtn.action`, `mtn.panel.*`, `mtn.editor.*`, `mtn.clipboard.set`) wait until it is done. `mtn.state()` has new `busy` and `jobs` fields, and the new `mtn.wait_jobs()` waits for the background jobs (copy, move, delete, pack) to finish.
- In the Font / Display dialog the right column no longer touches the window border: a checkbox, label or dropdown that is wider than its box now stops one cell short of the frame, and the longer Russian and German captions were shortened. Dialogs in other languages also widen by that cell when a caption would otherwise touch the border (the About dialog in Russian, for one).

## v0.5.6 – 2026-11-09

### Changed

- The Windows build uses about 6 MB less memory at startup: the unused default FMX style is no longer loaded.
- The syntax highlighting plugin loads when the viewer or the editor first opens a file of a language it colors, not at start: until then the program takes about 10 MB less memory. The first source file opens a little slower.
- Plugins that only add menu items, Change Drive entries or document viewers are loaded on first use instead of at start (Docker, Rclone, Network connections, JSON and YAML tree, Temporary panel, Registry, processes and services, Everything, CSV, PDF and document viewers, Line filter): their menu items, `Ctrl+Alt+J` and drive entries exist from the start, and the first click, key press or opened file loads the plugin. Menu captions follow the interface language before the plugin loads. The plugin information dialog lists the registrations a plugin made that its `plugin.json` does not declare and the declared ones it did not make.
- Git status loads when a panel enters a git folder (or on its commands), Macros at start only while the macros folder has files, otherwise on `Ctrl+.` or the Macros menu: their keys and menu items exist from the start. Plugin manifests can now name such triggers (`activateOn`, `startupWhen`, `openRegistrations`), so further plugins can stay out of memory until needed.
- The saved workspaces dialog shows its keys: `Ins` saves, `F2` renames, `Del` deletes.
- Plugin keys no longer overlap the program's own: the Git diff moved to `Ctrl+Shift+G` (it was taken by the saved workspaces list), the Line filter to `Ctrl+Alt+J` (it was taken by the job list). A key that a built-in action, a key handled in code (cursor and editing keys, word and file jumps, clipboard keys, rectangular selection) or an earlier plugin already uses is not bound to a plugin, for a command as well as for an extra key of a built-in action, and the plugin's information dialog says which one holds it. The sample plugins and macros were moved off taken keys as well.
- The lists of dropdown fields are outlined with thin lines along the outer edges of their cells instead of frame characters: the highlight of a row reaches the line, and a list opened from a field has no line on the side that touches the field. The dropdown menus keep their frame characters. Options > Display > "Thin lines in dropdown lists only" switches back to the framed look (a list opened from a field is then drawn in a single-line frame of characters, open on the side that touches the field); text-mode (terminal) hosts keep it anyway.

### Fixed

- The pwsh console profile starts when PowerShell 7 is installed from the Microsoft Store and is not on PATH (the Store alias was rejected as a missing file).
- On Linux (SDL) characters missing from the main font are taken from a font that really has them, and under WSL from the CJK fonts of the Windows host, so Chinese, Japanese and Korean text is shown without installing a font.
- After the interface language is changed, the menu items of the plugins (Macros, Plugins and others) switch to the new language at once; before, they kept the language of the previous start. A plugin without a pack for the language shows English.
- The command palette (`Shift+F9`) lists the plugin commands that have no menu item (for example the Line filter and macros kept out of the menu), with their keys. Line filter gets a Plugins menu item, and the Git and Net commands show their keys in the palette.
- The Everything plugin: a search no longer ends with "Everything gave no answer"; the plugin waits for the reply, which Everything 1.4 sends after the query call has returned.
- Plugins that run external programs (Rclone, Docker, SFTP) report "did not run (is it installed and in PATH?)" no more when the program was installed after the session that started MTN2: the program is also looked up in the current user and machine PATH from the registry.

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
