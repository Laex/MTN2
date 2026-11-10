# MTN2 Features

**English** | [Русский](FEATURES.ru.md)

A short overview of the features; details are in the help (F1), the other documents in the `docs` folder, and the CHANGELOG.

## Panels and navigation

- **Column modes and column sets** – brief, full and custom modes; the Custom Columns dialog saves a selection under a name (Minimal, Dates, Technical are built in), and vertical lines between columns can be turned on in the settings.
- **Plugin columns** – in custom mode plugins add their own columns (Docker, processes, services, image, MP3 and program metadata); sort by clicking the header or with `Ctrl+F12`.
- **List grouping** – `Ctrl+Alt+G`: groups by file type or modification date with captions and alternating background; the mode is kept per panel.
- **Paired folders** – `Ctrl+Alt+P`: entering a subfolder or going up is repeated in the other panel when it has a folder with the same name.
- **NDN-style panel footer** – the line for the file under the cursor, totals for the selection, and free disk space with a fill bar.
- **Folder tree** – `Alt+F10` over the panel: branches expand with the arrow keys, the other panel follows the cursor, folders are read in the background.
- **Drive selection** – `Alt+F1` / `Alt+F2`: drives with fill bars, recent network shares, plugin entries; `F4` shows volume details, `Del` ejects a removable or network drive.
- **Folder hotlist** – `Ctrl+D`: groups, manual order, quick letters via `&` in the name and `Ctrl+1`...`Ctrl+0`; the list is protected against loss on a failed write.
- **Frequent folders** – `Ctrl+Shift+F12`: a list ranked by visits and recency, typing narrows it.
- **Folder and navigation history** – `Alt+F12` with type-to-filter, `Alt+Left` / `Alt+Right` move back and forward; `Del` and `Ctrl+Del` clear entries.
- **Far-style navigation** – `Ctrl+PgUp` / `Ctrl+PgDn` go up and into a folder; `Ctrl+PgDn` on a file opens it as an archive by content (`.docx`, `.xlsx`, etc.); `Backspace` with an empty command line goes up a level.
- **Resilience to missing folders** – if a panel's folder is deleted or unavailable at startup, the panel moves to the nearest existing parent.
- **Context-aware ".."** – from a folder opened through a link it returns to where the link is; from the Recycle Bin, system folders and plugin folders it returns to where you came from.
- **Cursor sync** – `Ctrl+Alt+M` puts the passive panel's cursor on the file with the same name, `Alt+Shift+F3` shows the item under the cursor in the other panel.
- **Panel control** – `Ctrl+P` hides the inactive panel, `Ctrl+U` swaps panels, `Ctrl+L` shows the info panel with fill bars.
- **Vim keys in panels** – optional: `j`/`k`, `h`/`l`, `g`/`G`, `/` for quick search, `:` for the command line.
- **Wide characters** – Chinese, Japanese and Korean characters take two columns in panels, the console and interface lines.
- **Smooth scrolling** – one redraw per frame while keys are held, including at Windows scaling of 125% and above.

## Tabs and workspaces

- **Panel tabs** – `Ctrl+T` / `Ctrl+W`, switching with `Alt+PgDn` / `Alt+PgUp`, a `[+]` button; Total Commander-style keys, remappable in `keymap.json`.
- **Pinned tabs** – `Ctrl+Alt+T`: the tab stays in its folder and navigation opens a new tab; the state is saved.
- **Workspaces** – separate sets of panels, terminals, viewer and editor; `Ctrl+Tab` / `Ctrl+Shift+Tab` and `Ctrl+Alt+PgDn` / `Ctrl+Alt+PgUp`, a new one with `Ctrl+Shift+W`; the cursor is kept when switching.
- **Compact tab bar** – long titles are shortened, room for window buttons and background task chips is reserved.

## Selection and masks

- **Far-style selection** – `Ins`, `Space`, Gray `+` / `-` / `*`, `Shift+Gray +`, selection by extension; folders are included with the "Select folders too" option.
- **Shift movement** – arrows, `Home`, `End`, `PgUp`, `PgDn` with `Shift` mark or unmark based on the row where the movement started.
- **Restore selection** – `Ctrl+M` brings back the selection cleared after a copy or delete.
- **Mask groups** – `@Name` in any mask (selection, filter, search, color highlighting); Images, Audio, Video, Documents, Archives, Sources are built in, custom groups are created in the dialogs and with `Ctrl+G` in a mask field.
- **Fast selection in large lists** – invert and mask selection in folders with tens of thousands of files are instant.

## File operations and background jobs

- **Background copy, move and delete** – operations run as background jobs with a chip and progress in the tab bar; clicking a chip brings back the job window.
- **Job list** – `Ctrl+Shift+J`: columns, pause, queue order, copy speed limit; operations on the same disk run one after another.
- **Windows taskbar progress** – a bar on the program button colored by state; a notification when a job finishes.
- **Safe copying** – data is written to a temporary `name.mtnpart` and renamed after a complete write; copying in 256 KB blocks.
- **Error resilience** – automatic read retries, per-file "Skip" and "Skip all", confirmation before aborting an operation.
- **Administrator helper** – on "Access denied" the "Admin" button repeats the copy, move, delete, folder creation or extraction with a single UAC prompt.
- **Folder merge** – copying or moving a folder onto an existing one merges the contents; the "File already exists" prompt offers overwrite, skip, rename, append.
- **Far-style delete** – `F8` / `Del` to the Recycle Bin, `Shift+Del` permanently, `Shift+F8` only the item under the cursor; if the Recycle Bin fails, permanent deletion is offered.
- **Multi-rename** – `Ctrl+Alt+N`: `[N]`, `[E]`, `[C]` masks, date, parent, size and metadata tags, text replacement and regular expressions, case changes, preview with conflict checks.
- **Attributes** – `Ctrl+A`: three-state check boxes for a group of files, extended NTFS attributes, owner, dates; on Linux – permissions, owner and `chattr` flags.
- **Link creation** – `Alt+F6`: a symbolic link, junction or hard link depending on rights and source.
- **Link copying** – symbolic links and junctions are copied as links, their contents only on request.
- **Apply command to selection** – `Ctrl+G` runs a command on the selected files with user menu substitutions (`!.!`, `!&`, `!\`, `!#`).
- **File descriptions** – `Ctrl+Z`: a description in `Descript.ion` in Far and Total Commander format, shown in the status line.
- **Save list to file** – selected items as text, a Markdown table or CSV with a choice of fields.
- **Copy names and paths** – `Ctrl+Shift+Ins` copies names, `Alt+Shift+Ins` full paths to the clipboard.
- **Long paths** – paths longer than 260 characters work in operations, search, comparison and extraction.
- **Parallel operations** – copying sibling folders runs alongside a background delete; a repeated operation on the same folder brings its window to the front.

## Search and filters

- **File search** – `Alt+F7`: mask, text, hex bytes with `??`, size, date with a calendar, three-state attributes, code page choice with autodetection.
- **Search in archives** – the "Search in archives" option: zip and plugin archive entries by mask and text; `Enter` opens the archive at the found file.
- **Background search** – the "Background" button: several searches at once, each with a chip and a counter; results fill the panel as they arrive.
- **Results panel** – found items open as a panel right away; `Ctrl+]` / `Ctrl+[` open the file's folder in the other panel; the function key bar shows only available actions.
- **Results to workspace** – `Ctrl+Alt+F7` saves found files as links in a working set: add, replace or create a new one.
- **Quick search** – `Alt+letter` by name; optionally the field stays open after `Alt` is released, and there is a variant without `Alt`.
- **Panel filtering during quick search** – only matching names remain, with a fuzzy "letters in order" mode and an option to keep the filter across folders.
- **Panel filter** – `Ctrl+I`: ready-made filters, recent masks and a custom mask.

## Comparison and synchronization

- **File compare and merge** – `Ctrl+Alt+C`: a full-screen window, lines aligned by similarity, jumps between differences, copying differences both ways, undo and save.
- **Group comparison** – with several files marked, files with the same names are compared in pairs, and a summary list leads to the differences.
- **Folder comparison** – `Ctrl+Shift+C` by time, size or contents; contents are compared in the background.
- **Folder synchronization** – `Ctrl+Alt+S`: an action per file (`->`, `<-`, `--`), conflict resolution, counts of copies and skips.

## Archives

- **Archives as folders** – ZIP is built in, 7z, RAR and dozens of formats (zst, vhd, msi, deb, rpm, dmg, squashfs, etc.) via 7-Zip; the format is detected by content, not by extension.
- **Packing** – `Shift+F1`: zip or 7z, compression level, password and name encryption; adding to an existing archive.
- **Archive editing** – copying and moving into an open archive, deleting entries, editing a file inside an archive and saving it back with `F2`.
- **Encrypted archives** – AES ZIP and 7z with encrypted contents or names; the password is asked once per session.
- **Large archives** – fast entry into zip files with tens of thousands of entries, large entries are extracted straight to disk.
- **Launch from archive** – `Enter` on a file inside an archive opens it in the default program through a temporary folder.
- **ZIP names** – name encoding is detected automatically (UTF-8 or OEM), entries with `..` cannot escape the destination folder.

## Network and virtual file systems

- **Network connections** – FTP, FTPS, SFTP (password, key, agent, fingerprint check), SCP, WebDAV, S3 as panel folders; the connection list is on `Ctrl+Shift+B`, passwords are stored encrypted.
- **Network addresses** – `ftp://`, `sftp://`, `dav://`, `s3://` and others can be typed in full; file permissions on the server can be changed over FTP and SFTP.
- **Rclone** – storages configured in rclone (cloud drives, S3, etc.) open as folders with viewing, editing, copying and deleting.
- **Everything** – Everything search results (Windows) open as a panel of real files.
- **JSON and YAML tree** – `Enter` on `.json`, `.yaml`, `.yml` opens the file as a folder tree with values; `F5` copies a branch as text.
- **Docker and Kubernetes** – containers and pods as folders with `info.txt`, `logs.txt` and their file system; start, stop and restart from the Plugins menu.
- **Registry, processes and services** – the Windows registry with value editing, processes with details and termination, services with start and stop control.
- **Recycle Bin and system folders** – as panel folders, with restore and ".." navigation.

## Terminal, console and command line

- **Console under the panels** – `Ctrl+O`: cmd, PowerShell, WSL, Git Bash and other shells; the panel follows the console folder after commands.
- **Terminal tabs** – `Ctrl+Shift+N`: shell profiles with numbers, a key mode (auto, terminal, host) and their own environment.
- **Terminal emulation** – full-screen programs (`htop`, `mc`, `vim`, `less`) with application cursor mode, scroll regions, and function keys and shortcuts passed through.
- **Environment profiles** – `environment.json`: named variable sets for new shells with substitution of current values.
- **Command line** – running a file by name, `Ctrl+Enter` / `Ctrl+F` insert the name and path, `Esc` step by step clears the line and shows the console.
- **Command history** – `Alt+F8` and drop-down suggestions while typing, without duplicates; `Del` removes an entry.
- **Run in a new tab or in the background** – `Ctrl+Alt+Enter` in a new terminal tab, `Alt+Shift+Enter` in the console with a short display and return to the panels.
- **Console programs from the panel** – `.exe`, `.bat`, `.cmd`, `.ps1` on `Enter` run in the built-in console or a terminal tab, and the output stays on screen.
- **Search in output** – `Ctrl+Shift+F` in the console and terminal with highlighted matches, `F3` / `Shift+F3` for next and previous.
- **Output handling** – saving and clearing the console buffer, configurable history size, confirmation before pasting several lines.
- **WSL commands** – `wsl`, `wsl -d ...` open a terminal tab, management commands run in the console.
- **Shell integration** – `--shell-init bash|zsh|fish|powershell` prints an `mtn` function; on exit the shell changes to the active panel's folder.
- **Typing without moving focus** – optionally characters typed on the panel go to the command line while focus stays on the panel.

## Viewer

- **Viewer** – `F3`: text with word wrap, hex mode with byte search, encoding choice; large files open immediately while lines are indexed in the background.
- **Tail mode** – `Ctrl+Shift+F`: the window follows the end of a growing log, file rotation is handled.
- **Quick View** – `Ctrl+Q` in the other panel; `Tab` passes the keyboard to it for scrolling text or an image.
- **Syntax highlighting** – about 70 languages in the viewer and editor; numbers, punctuation and links highlighted in `.txt` and `.log`.
- **Markdown** – headings, italics, strikethrough, tables, images at their own size, links between files and sections, selection and search over the displayed text.
- **Markdown colors** – custom colors and styles for elements, palette import from an Obsidian theme.
- **PDF** – pages as images with zoom and paging, the document text in Quick View.
- **Documents and data** – text from `.docx`, `.xlsx`, `.pptx`, `.svg`, the schema and rows of SQLite databases, aligned CSV and TSV tables.
- **Images and video** – an image viewer with zoom and rotation, a video player with sound (via plugins).
- **Remote and archived files** – large files from servers and archives open through a temporary copy, `Esc` cancels the download.

## Editor

- **Editor** – `F4`: undo, encodings (including GBK, GB18030, Big5), auto-indent, bookmarks on `Ctrl+F2` with a list.
- **Find and replace** – `F7` / `Ctrl+F7`: match case, whole words, regular expressions with `$1`...`$9`, Far-style step-by-step replace.
- **Column blocks** – `Alt+Shift` with the arrows or `Alt` with the mouse; typing, deleting, copying and pasting as a block.
- **Line commands** – sorting, removing duplicates, reflowing paragraphs to width, shifting, alignment, case changes.
- **Line drawing** – `Ctrl+Alt+D`: the arrows draw single or double frames.
- **Incremental search** – `Ctrl+Alt+T`.
- **Change tracking** – a change to the file on disk is noticed, and the editor's own save does not trigger a reload.

## Menus, keys and command palette

- **Main menu** – `F9` or a single `Alt`, a Plugins menu with the commands of all plugins, scrolling for long menus.
- **Command palette** – `Shift+F9`: search over menu items and keys with synonyms in several languages, command descriptions, `Ctrl+K` changes a command's key, a plugin command's too.
- **Key bindings** – Settings → Key Bindings and `keymap.json` for panels, viewer, editor, console and global keys; only changes are stored.
- **Ready-made keymaps** – Far, Midnight Commander and Total Commander-style samples in `docs/keymap-presets`.
- **Function key bar** – captions for all modifiers, mouse clicks, only available actions shown.
- **Status line** – clicking a section opens the drive list, history, column mode, go to line or encoding choice.
- **User menu** – `F2`: commands with substitutions and a choice of what happens after the run.
- **Windows context menu** – `Shift+F10` or the Menu key for the selected files or the current folder.
- **Context help** – `F1` in any dialog opens the section about it, including plugin help.
- **Key tips** – short notifications about useful keys in new situations, each shown once.
- **Keyboard-friendly dialogs** – hotkey letters in any keyboard layout, double click and `Del` in lists, mouse text selection in fields.
- **Full screen** – `F11`.

## Themes, fonts, appearance

- **Themes** – about twenty themes: Far Classic, NDN, Norton Commander, Midnight Commander, Total Commander, High Contrast, Navigator, Gruvbox, Monokai, Tokyo Night, Solarized, phosphor and others.
- **Custom themes** – a theme editor for colors, frames and symbols, an HSL/RGB/hex color picker, inheritance from several themes and role references; the format is described in `docs/THEMES.md`.
- **File color highlighting** – groups by mask and condition (size, age, attributes) with sort priority.
- **Font and sharpness** – size in points, a fallback font for missing glyphs, Windows Terminal-style line spacing, contrast and cell size.
- **Cursor** – shape and blinking, a Far-style underline cursor.
- **Shadows and dialog look** – classic, soft or no shadows; buttons press like real ones.
- **Marked files** – shown by text color or row background.
- **Hiding window elements** – the window title bar, menu, function key bar and status line; window buttons move to the menu bar.
- **Screen saver** – after idle time sharks made of letters swim across the screen.

## Language and localization

- **Interface languages** – English, Russian, German, Simplified Chinese: menus, dialogs, key and status lines, F1 help.
- **Language packs** – files in `resource\<language>\`; a new language is added by copying a folder, plugins are translated with their own packs.
- **Language on first start** – taken from the Windows language when a translation exists.

## Settings and configuration

- **Settings dialogs** – "Font / Display" and "Interface" with options for panel, command line and notification behavior.
- **Settings export and import** – a single zip with the session, keys, user menu, folder hotlist, connections and themes.
- **Settings location** – moving between the user folder and portable mode next to the program; the `MTN2_CONFIG_DIR` variable sets a custom folder.
- **Command line arguments** – paths open as tabs, `--view` and `--edit`, paths are passed to an already open window.
- **Information switches** – `--version`, `--paths`, `--list-commands`, `--list-plugins`, `--check-keymap`, `--export-theme`.
- **Exact size in bytes** – optional, with digit grouping in the footer and status line.
- **Notifications** – short messages in the lower right corner; dialogs hidden with "Don't show again" come back with one command.
- **Drag and drop** – files between panels and from other programs.
- **Fast startup** – plugins load on first use, the shell starts with the first command.

## Plugins and extensibility

- **Plugin management** – the Plugins dialog: enabling, load order, permissions, settings, installing from a folder or `.zip` and removal; after installation all plugins are disabled until turned on.
- **Native and WASM plugins** – DLL and WebAssembly (Rust, Go, others), including WASI; templates and samples in `samples/plugins`, the guide is `docs/PLUGIN_DEVELOPMENT.md`.
- **Lua macros** – `Ctrl+.` records keys, macros run with their own key or from a menu, with a macro manager.
- **Macro API** – access to the editor, panels, clipboard, input and events; custom panel columns from Lua.
- **Plugin virtual file systems** – `scheme://host/path` schemes as folders with progress and cancellable transfers.
- **Interface extensions** – own commands and keys, drive list entries, status line text and chips, JSON dialogs, image tabs.
- **Intercepting and replacing built-ins** – command hooks (copy, view, save, etc.), opening files by type on `F3`/`F4`, replacing scheme and archive handlers with the user's permission.
- **File and document access** – reading files through any scheme with the `vfs.read` permission, working with document text and panel rows.
- **Git** – branch and change status in the status line, names colored by state, `Ctrl+Shift+G` for a file diff, file blame.
- **File metadata** – image dimensions and camera, MP3 tags, program version and company in the status line and columns.
- **Temporary panel** – a panel from command output (`rg -l`, `git ls-files`), duplicate file search by SHA-256.
- **Line filter** – `Ctrl+Alt+J` in the viewer or editor opens the lines matching a text or regular expression.
- **Long plugin operations** – run as background jobs with cancellation.

## Updates, installation, portable mode

- **Built-in updates** – a daily check with "Update / Later / Skip", checksum verification, installation with restart; settings are left untouched.
- **Update channels** – stable and a dev channel with builds after every change.
- **Console update** – `--update [stable|nightly]` in all program variants.
- **Portable mode** – the `win64-portable.zip` archive or a `portable.dat` file next to the program.
- **Linux packages** – `tar.gz` with `install.sh`, `.deb` and `.rpm`; in packages self-update is replaced by a version check.
- **Release integrity** – a `SHA256SUMS` file and a list of third-party components in CycloneDX format.

## Linux (mtn2-tui, mtn2-sdl)

- **mtn2-tui** – the full program in a plain terminal (SSH, `tmux`, container): panels, tabs, viewer, editor, console, terminals; TrueColor with fallback to 256 and 16 colors.
- **mtn2-sdl** – an experimental graphical version on SDL2: system font, file icons, IME, clipboard, images in Quick View.
- **Terminal keyboard** – the kitty keyboard protocol and `modifyOtherKeys`, reaction to modifier release, recognition of function keys from simple terminals.
- **Mouse and clipboard** – terminal mouse toggled with `Ctrl+Shift+M`, clipboard via OSC 52, `tmux`, `wl-copy` or `xclip`; a desktop file clipboard.
- **Images in the terminal** – Quick View with colored blocks through `chafa`.
- **Permissions and file properties** – mode, owner, group, `chattr` flags, creation time; properties through the system file manager.
- **Desktop integration** – "Open with" on `Shift+F10`, a menu entry and icon, dropping files into the window.
- **Retry as administrator** – through `sudo` with the password entered in a dialog.
- **Plugins on Linux** – archives through an installed 7-Zip, processes and systemd services, Docker, PDF, documents, Lua, Git.
- **Terminal progress** – background job progress on the tab or title of supporting terminals.
- **Clean drive list** – without system mounts, with the mount point of every volume.

## Miscellaneous

- **Safe writes** – an interrupted transfer, a failed archive write or a failed update does not lose the previous file; links from documents open only for safe schemes.
- **Unusual file names** – names with control and invalid characters can be opened and processed.
- **"[Administrator]" mark** – in the window title when running with administrator rights.
