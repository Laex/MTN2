# MTN2 – User Guide

**English** | [Русский](HELP.ru.md) | [Deutsch](HELP.de.md) | [中文](HELP.zh.md)

Modern Terminal Navigator 2 is a dual-panel file manager in the spirit of NDN / FAR Manager with a built-in console, terminals, viewer and editor.

Keys are given for the built-in profile; you can redefine them (see [Key bindings](#key-bindings)).

## Contents

- [Program screen](#program-screen)
- [Panels and navigation](#panels-and-navigation)
- [Selecting files](#selecting-files)
- [File operations](#file-operations)
- [Drives and special places](#drives-and-special-places)
- [Tabs and workspaces](#tabs-and-workspaces)
- [Panel view and sorting](#panel-view-and-sorting)
- [Search and filters](#search-and-filters)
- [History and folder hotlist](#history-and-folder-hotlist)
- [Command line and console](#command-line-and-console)
- [Terminals](#terminals)
- [Environment profiles](#environment-profiles)
- [Viewing and editing files](#viewing-and-editing-files)
- [Working with text and the mouse](#working-with-text-and-the-mouse)
- [Top menu (F9)](#top-menu-f9)
- [User menu (F2)](#user-menu-f2)
- [Archives](#archives)
- [Network: SSH and SFTP](#network-ssh-and-sftp)
- [Synchronization and comparison](#synchronization-and-comparison)
- [Background jobs](#background-jobs)
- [File associations](#file-associations)
- [Settings](#settings)
- [Updates](#updates)
- [Key bindings](#key-bindings)
- [Settings files](#settings-files)

### Using the help

| Key | Action |
| --- | --- |
| Tab / Shift+Tab | next / previous link |
| Enter, click on a link | follow the link |
| Backspace, Alt+← | go back |
| F1 | this page (contents) |
| F7, Shift+F7 / Alt+F7 | search text, next / previous match |
| ↑ ↓ PgUp PgDn Home End | scroll |
| Esc, F10 | close the help |

## Key bindings

The built-in key set can be partly redefined by the `keymap.json` file in the settings folder (or via **Options → Keymap...**): only the changed actions are listed, the rest stay built-in. **Ctrl+Alt+K** – reload the file without a restart.

Besides the panels, the viewer and editor commands can be rebound. Their names in `keymap.json` start with:
- `Doc` – both viewing and editing: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…;
- `Viewer` – viewing only: `ViewerWrap`;
- `Markdown` – rendered Markdown: `MarkdownSource`;
- `Editor` – editing only: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…

The same chord can mean different things on the panels and in a document – Ctrl+H shows hidden files on a panel and toggles hex in a document. A narrower meaning overrides a general one: F4 over rendered Markdown toggles the source, not hex.

Global commands work in any window – the panels, a document, a terminal:
- `Help` (F1), `TopMenu` (F9), `CommandPalette` (Shift+F9);
- `NextTab` / `PrevTab` (Ctrl+Alt+PgDn / Ctrl+Alt+PgUp);
- `AppConsoleToggle` (Ctrl+O), `NewTerminal` (Ctrl+Shift+N), `SelectConsoleProfile` (Ctrl+Alt+O);
- `AppQuit` (Alt+X), `ZoomReset` (Ctrl+0), `ReloadKeymap` (Ctrl+Alt+K);
- `ToggleMouse` (Ctrl+Shift+M, text terminal version only).

**A chord the window binds itself.** It stays the window's:
- F10 closes a document and quits only on the panels (`Quit`);
- Esc on the panels shows the console (`ConsoleToggle`) when the panel has the focus; in the command line it first clears it, then gives the focus back to the panel.

**Full-screen program.** While one runs in a console or terminal (the profile's keys mode is *auto* or *terminal*, see Terminals), the console gets these keys too, except the ones that leave it: F11, Ctrl+O, switching tabs, Ctrl+Shift+N and Ctrl+Alt+O.

**Dialogs.** While a dialog is open the global commands do not fire; `ZoomReset` and `ReloadKeymap` always do.

In the console (Ctrl+O) and a terminal the commands named `Shell…` can be rebound:
- `ShellHistory` (Alt+F8), `ShellSelectAll` (Ctrl+A);
- `ShellCopyOrInterrupt` (Ctrl+C – copy the selection, or interrupt the command without one), `ShellCopy` (Ctrl+Ins), `ShellPaste` (Ctrl+V, Shift+Ins);
- `ShellFind` (Ctrl+Shift+F – search the output), `ShellFindNext` / `ShellFindPrev` (F3 / Shift+F3);
- in the console also `ConsoleSyncDir` (Ctrl+Shift+O – the panel goes to the console's folder).

Every other key goes to the shell.

**Settings → Keymap** groups the actions by window – global, file panels, viewer and editor, console and terminal – under readable names; the `keymap.json` name shows in the edit window. The F-key labels at the bottom, hints such as `A:All` and the shortcuts in the top menu come from the keymap: after a rebinding they show the new key.

An action can have several shortcuts: list them separated by `;` in the edit window, or as separate entries in `keymap.json`. Besides letters, digits and special keys, the signs `/`, `,`, `.`, `'`, `=` can be assigned; write semicolon and the main-block minus as `Semicolon` and `Minus` (`-`, `+` and `*` mean the numeric keypad keys).

Modifiers must match exactly: Ctrl+Shift+A is not Ctrl+A. Arrows, Home/End, typing and `/` in the viewer are not configurable.

### Tab keys

All tab keys are ordinary keymap actions and can be rebound in `keymap.json`. Panel tabs and workspaces (the tabs of the top row) are different things, each with its own actions:

| What | Action in `keymap.json` | Default |
| --- | --- | --- |
| New panel tab | `NewTab` | Ctrl+T |
| Next / previous panel tab | `NextPanelTab` / `PrevPanelTab` | Ctrl+Tab / Ctrl+Shift+Tab |
| Close the panel tab | `CloseTab` | Ctrl+W |
| New workspace | `NewWorkspace` | Ctrl+Shift+W |
| Next / previous workspace | `NextTab` / `PrevTab` | Ctrl+Alt+PgDn / Ctrl+Alt+PgUp |

The `[+]` and `[x]` buttons in the tab rows and the top menu items do the same.

### Your own `keymap.json` and updates

The `keymap.json` in the settings folder is laid over the built-in keymap: the actions it lists win over the built-in ones.
- The **Settings → Keymap** dialog writes only the changed actions to the file, so the other keys follow the built-in keymap after an update.
- A file saved by earlier versions lists all actions and freezes the old keys: to get the new ones, delete the lines of the actions you need from it, or the whole file (keep a copy first if it holds changes of your own).
- An action without keys is written as an empty list.

### Examples for Far and MC habits

The repository holds three example `keymap.json` files, [`keymap.far.json`, `keymap.mc.json` and `keymap.tc.json`](https://github.com/Laex/MTN2/tree/main/docs/keymap-presets). Copy the one you want into the settings folder as `keymap.json` (or add its actions to your own file) and press **Ctrl+Alt+K**.
- **Far:** Esc on the panels clears the command line and does not open the console (it stays on Ctrl+O).
- **MC:** Alt+. shows hidden files, Ctrl+\ opens the folder list, Alt+Enter inserts the file name into the command line, Alt+A and Alt+Shift+A insert the folder path of the active and the other panel, and Properties moves to Ctrl+Shift+P.
- **Total Commander:** Alt+F5 and Alt+F9 pack and unpack, Ctrl+A selects all, Ctrl+M renames by rules, Ctrl+P inserts the folder path, Ctrl+Tab and Ctrl+Shift+Tab switch tabs, Alt+Down opens the folder history. The default keymap already follows Norton Commander habits.

### Reserved keys

Not taken yet and kept for planned features: **Shift+F3** (archive commands), **F11** (the plugin menu), **Ctrl+Alt+Ins** (network UNC paths), **Ctrl+.** (macro recording). An automatic check keeps the built-in keymap from taking them.

---

[Contents](#contents)

## Program screen

From top to bottom:
- **Top menu** – the Left / Files / Edit / Commands / Options / Right categories and a clock. Opened with **F9**, **Alt** or a click.
- **Workspace tabs** – sets of panels and terminals (see [Tabs and workspaces](#tabs-and-workspaces)).
- **Two file panels** – the active one is highlighted by its frame; **Tab** switches sides. Drive letters are shown on the bottom edge of a panel.
- **Command line** – a prompt with the current folder.
- **F-key bar** – hints for the actions of the current mode; you can click them. While Shift / Ctrl / Alt is held, the bar shows the matching actions. In a window 100 columns wide or more, the bar on the panels also names the key of the command palette on its left.
- **Status line** – facts about the panel; clicking a section opens its dialog: the side and the free space open the drive list, the path opens the folder history, the column mode opens the mode menu, the item or the selection opens its properties. In the viewer and editor: the position opens Go to line, the encoding opens the encoding list, the search result opens Find.

The **console** lives under the panels: **Ctrl+O** (or **Esc** with the focus on the panel) hides the panels and shows the command output.

The window title shows **[Administrator]** when MTN2 itself was started as administrator, and **[Admin helper]** while the administrator helper runs (see [File operations](#file-operations)).

**Dialog buttons** press like real ones: a pressed button moves right and covers its shadow.
- **Mouse.** The command runs when the mouse button is released over the same button; move the pointer away and release there, and nothing happens.
- **Enter and Space.** They hold the button down until the key is released, and the command runs on release; pressing **Esc** meanwhile lifts the button without running the command and leaves the dialog open.
- **The highlighted letter and Y / N.** They push the button down for a moment and then fire it.
- Otherwise **Esc** closes the dialog at once.

**Hotkey letters in dialogs.** Buttons, checkboxes and radio buttons have one letter of their caption highlighted in colour (underlined in some themes).
- Pressing that letter presses the button, toggles the checkbox or selects the radio button; while the focus is in an input field, press it with Alt.
- The letter also works from the other keyboard layout: "Skip" with a highlighted S responds both to S and to the Cyrillic letter on the same key.
- The default button (in angle brackets) and the cancel button need no letter – Enter and Esc do that.

**F1** – help on what is on screen (panels, viewer, the open dialog or menu); **F1** inside the help – the contents. **F10** – quit.

---

[Contents](#contents)

## Panels and navigation

| Key | Action |
| --- | --- |
| ↑ ↓ PgUp PgDn Home End | move the cursor |
| ← / → | in Brief mode – one column left / right; in the other modes – to the first / last item (like Home / End) |
| Enter | enter a folder / archive, open a file (by [association](#file-associations)); run a console program in the built-in console (see below) |
| Backspace | up one level, like Enter on `..` (with an empty command line; otherwise it erases a character there) |
| Ctrl+PgUp / Ctrl+PgDn | up one level / enter the folder under the cursor, as in FAR; on a file Ctrl+PgDn opens it as an archive (see [Archives](#archives)) |
| Shift+Enter | run a file or command in a separate OS window |
| Alt+Shift+Enter | run the command line in the background: the console shows it for a moment, then the panels come back; with an empty line it runs the console program under the cursor the same way |
| Ctrl+Alt+Enter | run the command line in a new terminal tab (the shell of the background console); with an empty line it runs the console program under the cursor in the terminal tab of the panels tab |
| Alt+Shift+F3 | show the item under the cursor on the other panel |
| Tab | switch the active panel |
| Ctrl+\\ | go to the drive root (inside an archive – leave the archive) |
| Alt+← / Alt+→ | back / forward through the folder history |
| Ctrl+U | swap the panels |
| Ctrl+] | passive panel := folder of the active one |
| Ctrl+[ | active panel := folder of the passive one |
| Ctrl+Alt+P | paired folders on / off: entering a subfolder (Enter, Ctrl+PgDn) or going up (`..`, Ctrl+PgUp) in one panel does the same in the other, if the other panel has a folder of that name (or a parent); both panels must show plain local folders; the setting belongs to the tab and is kept between runs |
| Ctrl+Alt+G | group the rows: by type, by date, none (each press moves to the next) |
| Ctrl+F1 / Ctrl+F2 | hide / show the left / right panel |
| Ctrl+P | hide / show the inactive panel |
| Ctrl+L | information panel (drive, memory) on the other side |
| Ctrl+H | show / hide hidden and system files |
| Ctrl+R | refresh the panel |
| Ctrl+Q | quick view of the file on the other panel: picture, text, Markdown or hex |
| Alt+F10 | folder tree of the drive over the active panel (see below) |
| Alt+letter | quick search by name in the panel |

**Paired folders (Ctrl+Alt+P)** – example: the left panel shows `D:\Work1`, the right one `D:\Work2`, both have `src\Core`. With the mode on, Enter on `src` in the left panel opens `D:\Work1\src` and `D:\Work2\src` at once, and Enter on `Core` goes one level deeper in both; `..` in one panel goes up in both. If the other panel has no folder of that name (say `v2` has no `docs`), it stays where it is. Good for comparing two copies of a tree folder by folder.

**Grouping (Ctrl+Alt+G)** – the rows are ordered by group first, and the current sort applies inside each group; the first row of a group shows its heading at the right of the name, and every other group has a slightly tinted background. By type: folders, images, audio, video, documents, archives, programs, code and data, other. By date: today, yesterday, last 7 days, last 30 days, last year, older, no date. Example: press Ctrl+Alt+G twice in a Downloads folder and sort by size – the files of each day are listed together, the largest first. The mode is kept per panel and saved with the session.

**Folder tree (Alt+F10)** opens over the active panel. It is open over one panel at a time.

**Opening.** The drive root is shown with the path to the current folder open and the cursor on it.

**Keyboard**
- ↑ ↓ PgUp PgDn Home End – move.
- → or `+` – open a branch (`[+]─`) or step into it.
- ← or `-` – close a branch (`[-]─`) or go to the parent.
- A letter – jump to the next folder starting with it.
- Enter – open the folder in the active panel and close the tree.
- Esc or Alt+F10 – close the tree; the same panel shows again.

**The other panel.** It goes to the folder under the cursor once the cursor stops.

**Focus**
- Tab or a click on the other panel moves the focus there; the tree stays, like a FAR tree panel.
- Tab or a click on the tree's frame brings the focus back.

**Mouse.** The tree works as an index:
- a click on a folder shows it in the other panel at once and moves the focus there;
- a click on `[+]` / `[-]` opens or closes the branch without moving the focus;
- the wheel scrolls the tree without moving the cursor.

**Following and background reading**
- When the other panel goes to another folder, the tree opens the path to it and puts the cursor there; for another drive it rebuilds itself.
- Folders are read in the background; if the panel under the tree goes to another folder meanwhile, the tree closes.

**Quick view (Ctrl+Q)** shows the file under the cursor on the other panel: a picture, text (the encoding is detected), rendered Markdown or a hex dump of a binary file.
- Large files are streamed.
- The mouse wheel over the preview scrolls it.
- Files on SFTP and big files inside archives are not read on every cursor move – the panel suggests opening them with F3.
- Tab or Ctrl+Q again closes the quick view.

**Console programs** (a console-subsystem `.exe`, `.bat`, `.cmd`, `.ps1`) run on Enter so that their output stays on screen, not in a separate Windows window:
- in the background console (Ctrl+O) when its shell is cmd, PowerShell or pwsh and nothing runs in it: like a command typed in the command line;
- otherwise (a WSL, Git Bash or SSH console, or one busy with another command) – in a new terminal tab with cmd, or PowerShell for a `.ps1`; the tab stays open after the program ends.

With **Run programs from the panels in a terminal tab** (**Commands → Background console...**) every console program goes to a terminal tab, so the other tabs stay usable while it runs.
- The first program started from a panels tab opens a terminal tab next to it.
- The next ones are typed into that tab's shell (in the folder of the file) while it is idle and nothing is typed on its input line, otherwise a new tab opens.
- The tab's shell has its own environment profile (**F6** in the shell list) and its own shell history.

Window programs and documents open with their Windows program as before. **Shift+Enter** still runs any file in a separate window.

A mouse click places the cursor, a double click acts like Enter. Files can be dragged with the mouse between the panels and to other programs (and back).

---

[Contents](#contents)

## Selecting files

| Key | Action |
| --- | --- |
| Ins | select / deselect and move down |
| Shift+arrows, Shift+Home/End/PgUp/PgDn | select as the cursor moves |
| Shift+Gray + | select all files |
| Ctrl+M | bring back the selection held before it was last cleared (after a copy, say); a second press swaps back |
| Gray + / Gray − | select / deselect by mask (`*.txt`, `a*.*`) |
| Gray * | invert the selection |
| Ctrl+Gray + / Ctrl+Gray − | select / deselect files with the same extension as the one under the cursor |
| Shift+Gray − | deselect all files |
| Alt+Gray + / Alt+Gray − | select / deselect files with the same name |

In the select-by-mask dialog the “Select folders” check box applies the mask to folders as well. Operations (copy, delete, …) work on the selected items, or on the item under the cursor if nothing is selected.

### Mask groups

<!--mask-groups-->In any mask (selection, panel filter, search, colour groups) `@Name` expands to a named set of masks, for example `@Images` or `*.log;@Documents`. The groups Images, Audio, Video, Documents, Archives and Sources are built in. Your own groups, or replacements of built-in ones, go into `maskgroups.json` in the settings folder: `{ "groups": { "Logs": "*.log;*.out" } }`. An unknown name stays ordinary mask text. The Options menu item "Mask groups..." opens a list where groups are added, changed and deleted; the select-by-mask dialog can also save its mask as a group. In a mask field of a dialog (select, filter, search), Ctrl+G saves the typed masks as a group named after the first mask and puts `@Name` in the field.

### Column sets

The column modes menu lists named column sets under Custom (Minimal, Dates and Technical are built in). A set applies its columns to the Custom mode. To save the current choice, type a name in the "Save as column set" field of the Custom columns dialog; sets are kept in `columnsets.json` in the settings folder. The same dialog lists the sets: Edit loads the selected set into the checkboxes and the name field (OK saves the changes under that name), Rename gives the selected set the name typed in the field, Delete removes it. Built-in sets cannot be renamed or deleted; saving a set under a built-in name replaces it, and deleting that set brings the built-in one back.

---

[Contents](#contents)

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
| Ctrl+Alt+M | rename the selected items in one go: name and extension masks, counter, search and replace, letter case |
| Ctrl+C / Ctrl+X / Ctrl+V | copy / cut / paste files through the clipboard |
| Alt+Shift+Ins | copy the full path to the clipboard |
| Ctrl+Shift+Ins | copy only the name (no path) to the clipboard |
| Ctrl+Z | describe the file: an input line, the text is kept in `Descript.ion` next to the file |

**Alt+Shift+Ins** and **Ctrl+Shift+Ins** take the selected items (one per line) or, with nothing selected, the item under the cursor; on `..` – the current folder. Paste the result anywhere with **Shift+Ins** / **Ctrl+V**. A short notice in the bottom right corner confirms the copy (or says there is nothing to copy); it can be turned off in **Options → User interface...**.

<!--export-list-->**Files → Export list...** saves the selected items (or, with nothing selected, the item under the cursor) to a file.

**The dialog asks for**
- the file name;
- the layout – by extension (`.md` – Markdown table, `.csv` – CSV, anything else – aligned text), plain text, Markdown or CSV;
- the fields: name, full path, extension, size, modified / created / accessed date, type and attributes.

The header line can be switched off (a Markdown table always has one). Folders show `<DIR>` in place of the size. The choice is remembered between launches; the item has no default key, one can be assigned in the key bindings dialog (action `ExportList`).

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

<!--copy-->The copy/move dialog lets you keep all timestamps, copy only newer files, copy the contents of symbolic links and set an exclusion mask. On a name conflict the program asks what to do (overwrite, skip, rename, for all…).

<!--checksums-->**Checksums.** They are calculated in the background (Esc – cancel). In the result list: **Copy** – to the clipboard, **Save** – to `<file>.sha256` (one file) or `checksums.sha256` in the panel folder. Verification marks every line `OK`, `FAILED` or `MISSING`. Lines `hash *name`, `hash  name` and `SHA256 (name) = hash` are understood.

<!--multi-rename-->**Multi-rename.** The name and extension masks understand:
- `[N]` – the old name without extension;
- `[E]` – the old extension;
- `[C]` – a counter with the given start, step and number of digits;
- `[Date]` and `[Time]` – the modification date (`2026-11-05`) and time (`14-30-07`); `[Year]`, `[Month]` and `[Day]` – parts of the date;
- `[Parent]` – the name of the folder; `[Size]` – the size in bytes;
- `[Dim]`, `[Camera]`, `[Artist]` and `[Title]` – the values of the metadata plugin columns (image size and camera, audio artist and title) as the panel shows them; they are empty until the plugin has read the file;
- other text stays as typed.

Search and Replace work on the new name and extension, and the letter case comes from the list. With **Regular expression** Search is a pattern and Replace may use `$1`, `$2`; a pattern that is not valid leaves the names unchanged. Tokens may be typed in any letter case; a value that is unknown is empty, and characters a name cannot hold become `_`. The list under the fields shows the "old -> new" pairs as you type.

**Errors.** A name that is empty, invalid, used twice or already taken in the folder (also by another item of the batch) is marked with `!`, and **Rename** does nothing while any is left.

Only items of one folder can be chosen. The renaming runs as a background job, like a move.

---

[Contents](#contents)

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

## Drives and special places

**Alt+F1 / Alt+F2** – choose the drive for the left / right panel. Below the drive list are special places (choose by digit, Enter or a click):
1. **System folders** – Desktop, Documents, Downloads and others.
2. **Recycle bin** – browse it; **Ctrl+Alt+R** restores an item, **F8** deletes it permanently. Quick jump – **Ctrl+Alt+F8**.
3. **Temporary** – a temporary panel, if the Temporary plugin is installed.
4. **Workspace** – a panel of links to files and folders (not copies): **F5** adds a link, **F8** removes it, **F7** creates a group.

After the drives the list shows network shares such as `\\server\share` in which a panel is open now or was open lately (up to eight). Enter opens the share, the share of the active panel is marked with an asterisk.

**On a drive**
- **F4** shows the attributes of its root folder.
- **Del** on a removable or optical drive or a mapped network drive disconnects it (ejects the medium) after a confirmation; a drive with open files stays connected and the program says why.

**Ctrl+← / Ctrl+→** – preview the neighbouring drive on the bottom edge of the panel; the jump happens when Ctrl is released (Esc – cancel). A click on a drive letter jumps at once. The last folder is remembered for each drive.

The **..** entry in system folders and the Recycle Bin takes you back to where you came from.

---

[Contents](#contents)

## Tabs and workspaces

<!--panel-tabs-->**Panel tabs** – each side has its own. The **[+]** button after the last tab, or a double click on an empty spot of the tab row, creates a new one:

| Key | Action |
| --- | --- |
| Ctrl+T | new tab |
| Ctrl+W | close the tab |
| Ctrl+Alt+T | lock or unlock the tab (a locked tab has an accent-coloured background: going to another folder opens a new tab, and it cannot be closed) |
| Ctrl+Tab / Ctrl+Shift+Tab | next / previous panel tab (on a document or terminal – workspace) |

<!--workspaces-->**Workspaces** – the tabs of the top row (**Ctrl+Shift+W** creates one, **Ctrl+Alt+PgDn** / **Ctrl+Alt+PgUp** switch). Each one holds its own pair of panels or a terminal. A double click on a tab renames it; the **[+]** button right after the last tab creates a new one.

<!--saved-->**Saved workspaces** – **Ctrl+Shift+D** (list, jump, delete), **Ctrl+Alt+Shift+D** – save the current one.

<!--findtows-->**Search results to a workspace** – **Ctrl+Alt+F7** (the **Commands** menu) adds links to the marked items of the active panel, or to all of them when none is marked (for example the **Alt+F7** results), to the `ws:///` link panel and opens it in the other panel. Equal names get a number, items already linked are not repeated, and items inside archives or plugin schemes are skipped. When the workspace already has links or saved sets exist, a choice appears: add to the current set, replace it, create a new set, or add to a saved one; a changed set is saved before it is replaced. Save the set with **Ctrl+Alt+Shift+D** to come back to it later.

---

[Contents](#contents)

## Panel view and sorting

| Key | Action |
| --- | --- |
| Ctrl+\` | column modes menu |
| Ctrl+Shift+F1 … F7 | mode: brief, size, date, full, created, types, custom |
| Ctrl+F12 | sort menu |
| Ctrl+F3 / F4 / F5 / F6 | sort by name / extension / modification date / size |
| Ctrl+F7 / F8 / F9 | unsorted / by creation date / by access date |

Choosing the same sort order again reverses the direction. The letter in the top-left corner of the panel shows the sort order (upper case – descending). The columns of the “Custom” mode are set in **Options → Columns...**. Row colors by mask – **Options → Color coding...**.

---

[Contents](#contents)

## Search and filters

| Key | Action |
| --- | --- |
| Alt+F7 | find files (mask, contents, subfolders, case, whole words, regular expressions) |
| Ctrl+I | panel filter: a dialog with a list of ready-made filters and a line for your own mask; Enter or a double click on the list applies the filter, Clear removes it |
| Ctrl+B | flat view: all files of the subtree in one list |
| Alt+letter | quick search by name |

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

[Contents](#contents)

## History and folder hotlist

| Key | Action |
| --- | --- |
| Alt+F12 | history of visited folders |
| Ctrl+Shift+F12 | frequent folders (by visit count and recency) |
| Alt+F11 | history of viewed and edited files |
| Alt+F8 | command history |
| Ctrl+D | folder hotlist |
| Ctrl+Alt+D | add the current folder to the hotlist |

In the lists: **Ins** – add, **F2** – edit, **Del** – delete (where applicable). Choosing an entry from the command history puts the command on the command line but does not run it.

In the folder, file and command history (Alt+F12, Alt+F11, Alt+F8) **Del** removes the selected entry from the history and **Ctrl+Del** clears the whole history; typing filters the list.

<!--frecent-->**Frequent folders (Ctrl+Shift+F12)** – the folders you enter most often, with recent visits weighing more. Typing narrows the list, **Enter** opens the folder, **Del** forgets its count, **Ctrl+Del** clears the ranking. Unlike Alt+F12, which is ordered by time, the folders you use every day stay at the top.

<!--file-history-->**File history (Alt+F11)** – the last 100 files opened with F3/F4, newest first; the mark on the left is the mode the file was last opened in (**V** – view, **E** – edit).
- **Enter** opens the file in the same mode.
- **F3** / **F4** – in the viewer / editor.
- **Ctrl+Enter** – goes to the file in the panel.
- **Del** – removes it from the history.
- Typing filters the list by path. The position inside the file is restored.

---

[Contents](#contents)

## Command line and console

The command line is always below the panels: just start typing. A command runs in the built-in console; its output is shown with **Ctrl+O**.

| Key | Action |
| --- | --- |
| Enter | run the command; a typed folder path goes to the folder, a file (including a name put there by Ctrl+Enter) runs: a console program in the built-in console, anything else with its Windows program. Then the focus goes back to the panel and the arrows move the cursor again |
| Ctrl+↓ / Ctrl+↑ | focus the command line / back to the panel |
| ↑ / ↓ (while typing a command) | command history |
| Tab | completion: a name from the panel, or a path from the disk when the word has `\`, `/` or `X:` (repeated presses cycle the matches) |
| Ctrl+↓ / Alt+↓ (line focused) | command history as a list: Enter – put on the line, Del – remove from the history, Esc – close |
| Typing in the line | the older commands that start with the typed text appear above the line as a list that does not take the keys: ↑ / ↓ select an entry, Enter puts it on the line (Enter with nothing selected runs the line), Del removes the entry from the history, Esc closes the list. With **Don't move focus to the command line when typing** (Options → User interface) set, what you type on the panels goes into the line without moving the focus there (Space and Backspace only when the line already has text); Ctrl+↓ or a click moves the focus |
| Ctrl+Enter | insert the name of the item under the cursor |
| Ctrl+F, Ctrl+Shift+Enter | insert the full path of the item |
| Alt+Shift+Enter | run the command line in the background: the console shows the start for a moment, then the panels come back (**Options → Console...** below); with an empty line it runs the console program under the cursor the same way |
| Ctrl+Alt+Enter | run the command line in a new terminal tab: a new workspace tab with the shell of the background console (cmd, PowerShell, WSL, ...), the command starts there and the tab stays open; with an empty line it runs the console program under the cursor in the terminal tab of the panels tab |
| Esc | step by step: clear the line → give the focus back to the panel → show the console. With an empty line the first step is skipped; with the focus on the panel text left in the line is cleared first, and with an empty line Esc shows the console at once |
| Ctrl+O | panels ↔ console |
| Ctrl+Shift+O | synchronize the folder between the active panel and the console |
| Ctrl+Alt+O | choose the shell of the background console (cmd, PowerShell, WSL, …) |

<!--console-profile-->**Commands → Background console...** is the same dialog.
- **Start shell at program launch** is off by default: the shell starts on the first **Ctrl+O** or the first command from the command line. Turn the option on to start the shell together with the program, as before.
- **Run programs from the panels in a terminal tab** sends console programs started with Enter in a panel to terminal tabs instead of this console.

**In the console:** **Ctrl+C** interrupts the command; **Esc** only hides the console and does not stop the process. The mouse wheel scrolls the output. Text is selected with the mouse (see [Working with text and the mouse](#working-with-text-and-the-mouse)).

**Searching the output** (console and terminal):
- **Ctrl+Shift+F** asks for the text; matches are highlighted in the whole history and the current one is selected like a mouse selection. An empty string in the dialog clears the search.
- **F3** / **Shift+F3** go to the next / previous match (wrapping around) while a search is set and no full-screen program runs in the window.
- In a console with the cmd shell **↑** / **↓** walk the shared command history (as Alt+F8) and **↓** after the newest command brings back the line that was being typed.

**Paste into the console** (**Ctrl+V**, **Shift+Ins**): every line break goes to the shell as Enter, so pasted lines run one after another, the last one too. With **Confirm multi-line paste** on, the program asks first.

**Options → Console...** sets:
- the scrollback size of the console and terminals (1000 – 50,000 lines, 10,000 by default);
- the confirmation of a multi-line paste (off; a full-screen program such as vim never asks);
- the removal of trailing spaces on copy and on paste;
- **Always return to the panels when a command ends** (off). With it on, a command run from the command line under the panels sends you back to the panels as soon as the shell shows its prompt again; a command typed in the background console (Ctrl+O) always stays in the console.

**Background run.** **Alt+Shift+Enter** runs the command line in the console in the background: the console is shown for the time set in **Background run** (0.5 – 10 s, 2 s by default) and the panels come back by themselves. A key pressed in the console before that keeps it in front; the command goes on running either way.

Changes apply at once, to open consoles too.

<!--save-output-->**Commands → Save console output...** writes the background console's scrollback (Ctrl+O) to a UTF-8 text file; **Clear console buffer** erases it, the shell keeps running.

---

[Contents](#contents)

## Terminals

**Ctrl+Shift+N** – a new terminal in a separate workspace tab: choose a shell profile (cmd, PowerShell, WSL, saved SSH connections). Full-screen programs (vim, mc, htop, …) work in the terminal just as in a regular console.

<!--profiles-->In the profile list:

- **1-9, 0, A-Z** – start the profile with that number (highlighted at the start of the line).
- **Ins** – copy the selected profile: the same shell, its own settings. **Del** deletes a copy (a profile itself cannot be deleted).
- **Ctrl+Up / Ctrl+Down** – move the profile; the order is remembered (`shellprofiles.json` in the settings folder).
- **F4** – the profile's keys mode. The mode applies to the background console (Ctrl+O) too when its profile is chosen.

The modes:
- *auto* – the program gets the keys while a full-screen application such as mc or vim runs in the console;
- *terminal* – the program gets every key, including F1, F9 and Alt+letter;
- *host* – the MTN2 window's keys come first.

In *auto* and *terminal* the window keeps only the keys that leave the console: F11, Ctrl+O, switching tabs, Ctrl+Shift+N and Ctrl+Alt+O.
- **F6** – the environment profile of the selected shell or its copy (see [Environment profiles](#environment-profiles)).

---

[Contents](#contents)

## Environment profiles

**Options → Environment profiles...** opens the `environment.json` file in the editor (on first use it is created with an example).

A profile is a named list of `NAME=value` entries that are laid over the environment of every new shell: terminal tabs and the console under the panels. Shells that are already running keep their environment; a shell started after the file is saved sees the change.

```json
{
  "profiles": [
    { "name": "default", "vars": ["EDITOR=vim", "WORK=%TEMP%\\work", "OLD_VARIABLE="] },
    { "name": "proxy", "auto": false, "shells": ["pwsh"], "vars": ["HTTPS_PROXY=http://proxy:3128"] }
  ]
}
```

**Entries.**
- Profiles apply in the order of the file and entries in the order of the list, so a later entry sees the result of an earlier one.
- An entry with an empty value (`OLD_VARIABLE=`) removes the variable.
- `%NAME%` is replaced by the current value of the variable on every system; on Linux and macOS `$NAME` and `${NAME}` work too. A name that is not set stays as written.
- On Windows names are compared without regard to case.

**Which profiles apply to a shell**
- `default` – applies to every shell, first.
- `auto` (on by default) – the profile applies by itself. With `"auto": false` it applies only to a shell that names it (see below).
- `shells` – the shell profiles the profile is meant for: `pwsh`, `wsl`, `wsl:Ubuntu`, the id of a copy such as `pwsh#2`. A bare `wsl` also covers `wsl:Ubuntu`, and a base id covers its copies. Empty or missing – every shell.
- `off` – `true` switches the profile off altogether, even where it is named.

<!--choice-->**Profile for one shell.** In the shell list (**Ctrl+Shift+N**) **F6** opens the choice of an environment profile for the selected shell or its copy. Such a shell starts with `default` and the chosen profile; `(none)` goes back to the automatic profiles. Only profiles that are not off and are not `default` are listed.

The file is part of **Export settings / Import settings**.

---

[Contents](#contents)

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
| Enter, click on a link | Markdown: open a local link (`other.md`, `other.md#section`, `#section`) in the same window; an external link (`https://…`, `mailto:…`) opens in the default application after a confirmation |
| Backspace / Alt+← | Markdown: return from a followed local link |
| F2 | save (editor) / word wrap (viewer; remembered per file along with the position) |
| Ctrl+Shift+F | viewer: follow the end of a growing file (a log); leave with the same key, a scroll up, Up, PgUp, Home or another mode |
| Ctrl+S | save |
| Ctrl+Z / Ctrl+Shift+Z | undo / redo |
| Ctrl+Y, Ctrl+D | delete the line |
| Ctrl+K | delete to the end of the line |
| Ctrl+N | insert an empty line below |
| Ctrl+Alt+S / Ctrl+Alt+Shift+S | sort the selected lines (the whole file without a selection) ascending / descending |
| Ctrl+Alt+U | remove repeated lines |
| Ctrl+Alt+F | format the text to a given width (paragraphs are separated by blank lines) |
| Alt+→ / Alt+← | shift the selected lines (the current line without a selection) right / left |
| Alt+Shift+arrows (and Home / End / PgUp / PgDn), Alt+mouse | select a rectangular block – the same columns of several lines; Del, Backspace, typing and Ctrl+X / Ctrl+C / Ctrl+V act on every line of the block, a copied block is pasted as a block |
| Enter (editor) | the new line starts with the indent of the line it continues (the blanks left of the cursor); the mode is switched on and off with **Ctrl+Alt+I**, in the Edit menu and in the settings (User interface) |
| Ctrl+F2 | set / clear the bookmark of the cursor line (the line is marked with ■ in the frame on the left) |
| Ctrl+Shift+F2 / Ctrl+Alt+F2 | go to the next / previous bookmark (wrapping around) |
| Ctrl+Alt+B | list of the bookmarks (line number and text): Enter goes to the chosen one |
| Ctrl+Home / Ctrl+End | to the start / end of the file |
| Ctrl+C / Ctrl+X / Ctrl+V | copy (without a selection – the line) / cut / paste |
| Esc, F10 (in the viewer also 5 on the numeric keypad) | close |

Large files are streamed, not loaded as a whole. If the file changes on disk, the open window is updated. For a read-only file the program offers to open it for writing by clearing the attribute.

<!--bookmarks-->**Bookmarks.** **Ctrl+F2** marks the cursor line, **Ctrl+Shift+F2** / **Ctrl+Alt+F2** go to the next / previous one and **Ctrl+Alt+B** opens the list: Enter goes to the chosen line, Esc closes it.

<!--find-->**Search dialog.** The field keeps earlier searches (**Ctrl+↓** / **Alt+↓**); the options are **Case sensitive**, **Whole words**, **Regular expressions** and **Reverse search**.

**The field and matches**
- **Word** puts the word under the cursor into the field, **Selection** puts in the selection (the current line when nothing is selected; the first line of a multi-line selection). With **Regular expressions** on, the text of those two buttons is escaped.
- A found match is selected and **F3** / **Shift+F3** go on from it. A match never spans a line break.
- With **Regular expressions** the pattern is a PCRE expression and in the replacement `$0` is the whole match, `$1` ... `$9` are the groups and `$$` is a dollar sign; without the option the replacement is taken as it is. A pattern that cannot be compiled is reported and nothing is searched.

<!--replace-->**Replacing**
- **Replace** in the Replace dialog goes through the matches one by one: each is shown selected, with the text, its replacement and the line that holds it, and is answered with **Replace** (replace it and go on to the next), **All** (replace the rest without asking), **Skip** or **Cancel**.
- When the end of the text is reached and the search began in the middle, it offers to continue from the beginning (from the end when searching backwards).
- **All** in the Replace dialog replaces every match of the whole text in one go.
- Both ways show how many replacements were made at the end of **All**, are undone with a single **Ctrl+Z**, and put the cursor back where it was before the replace.

**What is remembered.** Case, whole words and regular expressions are remembered between runs; **Reverse search** only until MTN2 closes.

---

[Contents](#contents)

## Working with text and the mouse

The same in the viewer and editor, on the command line, in dialog fields and in consoles.

A **word** is made of letters of any alphabet, digits and `_`. Everything else – spaces, punctuation, `\`, `/`, `.`, `:` – is a **separator**.

| Action | Result |
| --- | --- |
| Ctrl+← / Ctrl+→ | to the start of a word / to the end of a word (up to the next separator) |
| Ctrl+Shift+← / Ctrl+Shift+→ | the same with selection; stepping back deselects the part passed over |
| Shift+arrows, Shift+Home/End | selection |
| Click | place the cursor |
| Double click | select a word (on a separator – a run of identical characters) |
| Next quick click | select the whole line |
| Shift+click | extend or shrink the selection to the click point |
| Mouse drag | selection (viewer, editor, console) |
| Alt+mouse drag | rectangular block (viewer, editor) |
| Ctrl+C / Ctrl+Ins, Ctrl+X / Shift+Del, Ctrl+V / Shift+Ins | clipboard |
| Ctrl+A | select all |

In the panels, when the command line is not empty, Ctrl+Shift+←/→ work on the command line.

<!--mouse-->**Text terminal version (mtn2-tui).** The program asks the terminal for the mouse, so a drag selects inside MTN2 and the text goes to the clipboard through the terminal (an escape sequence that some terminals, PuTTY by default among them, ignore; inside tmux and on a desktop MTN2 also fills the tmux buffer and the system clipboard).

To select with the terminal itself:
- hold **Shift** while dragging;
- or turn the mouse off with **Ctrl+Shift+M** (**Options → Terminal mouse on/off**); the same key turns it back on.

The `--no-mouse` option starts the program with the mouse off.

**Input history.** Fields with **↓** at the right end remember their last 20 values. These are selection masks, file search (mask and text), copy/move destination and exclusions, link target, new folder and file, editor find and replace, user menu prompts.

**Using the list.** **Ctrl+↓** / **Alt+↓** or a click on the arrow drops the list down:
- **Enter** – use the entry;
- **Del** – remove it from the history;
- **Esc** – close the list.

A value is added when the dialog is accepted.

---

[Contents](#contents)

## Top menu (F9)

**F9** or **Alt** opens the menu.
- Arrows move, **Enter** runs, **Esc** closes.
- The highlighted (accent) letter of an item runs it at once – in any keyboard layout: with a submenu open the letter is looked up among its items, otherwise among the categories.
- Item keys are shown to the right of the items. Items unavailable in the current mode are gray.
- A menu that does not fit in the window scrolls: a bar with ▲ ▼ marks shows on its right border, the selected item always stays in view, and the mouse wheel moves the selection.

**Shift+F9** (or "Find command..." in the ≡ menu) opens the command palette, a search over the menu items.

**Searching**
- Typing narrows the list: the words of the caption, of the category and common synonyms are matched ("shell" finds "Background console..."; "bc" finds it by the first letters of its words).
- The query shows in the field above the list; a word of the query may contain `?` (one character) and `*` (any run of characters).
- The search also covers the shortcut column: "F9" finds the commands whose shortcut uses F9, "shift" every shortcut with Shift, "ctrl+f" the shortcuts that contain Ctrl+F.
- Your own search words go into `aliases.json` in the settings folder: `{ "tmaCmdConsoleProfile": "bash, zsh" }` – the item name and the words, comma separated or as a list. The file is read again each time the palette opens.

**Keys**
- Arrows select, **Enter** runs, **Backspace** erases, **Esc** closes.
- **Ctrl+K** opens the key list on the selected command, so its key can be changed; closing the list returns to the palette with the same search and command, and the new key shown (a command without a key of its own says so). On a plugin command it opens a field for a single key instead (an empty field leaves the command without a key; the plugin's own key is brought back by entering it or with **Reset**); the choice is kept in `plugin-keys.json` in the settings folder.
- The palette's own key can be changed in the keymap (command `CommandPalette`).

**What is listed.** Only the items available now; the commands run last come first. Commands that have no menu item (Ctrl+Enter, Alt+Shift+Enter and the other panel keys) are listed in the "Keys" category together with their shortcuts.

**Key hints.** When the program enters a new state, it shows a short notice with the useful keys once for good.

**When they appear**
- After a search, in an archive, in a temporary panel, in a workspace, in an SFTP or plugin folder, in the Recycle Bin.
- When files are selected, in the quick view and the info panel, with a second panel tab or workspace, with background jobs.
- In the console and a terminal, in the viewer, the hex view, Markdown and the editor, with the menu open, while a command is being typed and after a console program is started with Enter.
- Further hints name rarely used keys: with several files selected, on an archive under the cursor, in a long folder, after many folder changes, with a folder of the same name in both panels and with lines selected in the editor.

**How they work.** The keys come from the current keymap. The hints already shown are remembered between runs. In **Options → User interface** the "Show key hints" check box switches them off and the "Reset hints" button makes them new again; with pop-up notifications off there are no hints either.

---

[Contents](#contents)

## User menu (F2)

Your own list of commands: items with hot keys, nested submenus and separators. A command runs in the panel console, in the folder of the active panel; its output is shown with **Ctrl+O**.

**Two menus:**

- **Main** – shared by all folders.
- **Folder menu** – the `.mtn2menu.json` file in a folder. It applies to that folder and all folders below it; if such files exist on several levels, the nearest one is used. Handy for projects: a menu in the root of a repository is available in any of its subfolders.

**F2** opens the folder menu if there is one, otherwise the main menu. **Shift+F2** in an open menu switches folder menu ↔ main menu. To create a menu for a folder: F2, then Shift+F2 (an empty menu of this folder opens) and **Ins**.

**Keys in the menu:**

| Key | Action |
| --- | --- |
| Enter, item hot key, click | run the command or enter the submenu |
| → | enter the submenu |
| ← / Esc | one level up; Esc at the top level closes the menu |
| Ins | add an item before the cursor |
| F4 | edit the item |
| Del | delete the item (a submenu – together with its contents) |
| Ctrl+↑ / Ctrl+↓ | move the item |
| Shift+F2 | folder menu ↔ main menu |

<!--item-->**Menu item:** hot key (one character), type (command / submenu / separator), caption and command. If the caption is empty, the command itself is shown.

<!--substitutions-->**Substitutions in a command:**

| Pattern | Replaced with |
| --- | --- |
| `!.!` | name of the file under the cursor with extension |
| `!` | file name without extension |
| `!\` | panel folder with a trailing `\` |
| `!:` | drive of the folder (`C:`) |
| `!&` | selected names separated by spaces (or the name under the cursor); names with spaces are quoted |
| `!@!` | path to a temporary file listing the full paths of the selected items (one per line, UTF-8) |
| `!?Question?answer!` | user's answer: before running, a window with the question and a suggested answer appears; Cancel cancels the command |
| `!#` | further substitutions are taken from the **passive** panel |
| `!^` | further substitutions – from the **active** panel again |
| `!!` | the `!` character itself |

Names with spaces are substituted as is – quote them yourself: `"!\!.!"`.

**Examples:**

```
notepad.exe "!\!.!"                    open the file in Notepad
explorer.exe /select,"!\!.!"           show the file in Explorer
certutil -hashfile "!.!" SHA256        checksum
fc "!.!" "!#!\!.!"                     compare with the same-named file on the other panel
7z a "!?Archive name?backup!.7z" @!@!  pack the selection, asking for the archive name
git commit -am "!?Commit message?!"    commit, asking for the message
```

The command runs in the shell chosen for the console (cmd, PowerShell, WSL) – write commands in its syntax. Several commands on one line can be joined with `&&` (cmd, PowerShell 7).

Until the main menu has been saved even once, it shows examples. Menu files can also be edited by hand – changes are picked up the next time the menu opens.

**After run** in the item dialog says where the program goes once a command has finished: **As in the console options** (the **Always return to the panels** box in **Options → Console...**), **Return to the panels** or **Stay in the console**.

---

[Contents](#contents)

## Archives

- **Enter** on an archive opens it as a folder; **Ctrl+\\** or `..` in the archive root – leave it.
- **Ctrl+PgDn** opens a file as an archive whatever its extension: `.docx`, `.xlsx` or `.odt` (ZIP inside), or an archive with an unusual extension. The format is found from the file's content; on a file that is not an archive nothing happens.
- **F5** from an archive extracts the selection, **F5** into an open archive adds to it.
- **Shift+F1** – pack the selection, **Shift+F2** – unpack.
<!--pack-->- The pack dialog suggests the name of the current folder as the archive name and lets you pick the type: `zip` or `7z`. A `7z` archive can get a compression level, a password and encrypted file names (these fields are greyed out for `zip`); files can be added to and deleted from an encrypted `7z` archive.
<!--password-->- 7z and other formats – through the 7-Zip plugin (`7z.dll` comes with the program; you can replace it with your own copy in `plugins\mtn.7z\`).
- For encrypted archives the program asks for the password: on entering one whose file names are encrypted, otherwise on the first view or copy of an encrypted file. A wrong password is asked again; the right one is kept until the program closes.

---

[Contents](#contents)

## Network: SSH and SFTP

**Ctrl+Alt+Shift+N** – the list of SSH/SFTP connections: add, edit, delete, open as a panel (SFTP) or as a terminal (SSH). An SFTP panel needs key authentication (or ssh-agent / `~/.ssh/config`); a password for the panel is neither stored nor asked for. In an SSH terminal the password is entered as usual.

---

[Contents](#contents)

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

[Contents](#contents)

## Background jobs

<!--job-list-->Copying, moving and deleting run in the background. The progress window can be sent to the background; **Ctrl+Shift+J** – the job list (progress, cancel).

<!--stop-->A job can be stopped from the progress window with the **Cancel** button, **Esc** or a click outside the window; the Cancel and Cancel all buttons in the job list do the same.

A question comes first: “Cancel the current operation?”:
- **Stop** stops the job;
- **Continue** (the default button, also Esc) returns to the previous window.

After **Stop** the progress window closes at once and the job finishes stopping by itself: until it notices the request it stays in the job list, without a chip.

Dialog buttons are pressed with **Enter** and **Space**: the button looks pressed while the key is held and acts when the key is released. Esc before the release lifts the button without acting.

<!--queue-->**Queue, pause and speed.** Copy and move jobs that touch the same drive run one after another; the rest wait in the queue (`..`). In the job list (**Ctrl+Shift+J**), with a job selected:
- **Pause/Resume** holds a running copy at its next chunk (chip `||`, state "paused") or keeps a queued job from starting; a held job keeps its drive busy until it is resumed or cancelled;
- **Up** and **Down** change the start order of queued jobs;
- **Speed** steps the copy speed limit of the job through none, 1, 5, 20 and 100 MB/s (shown in the state column). The limit applies to copying between local folders.

<!--errors-->When a copy, move or delete stops with an error, the error window offers **Retry**, **Skip**, **Skip all**, **Cancel** and, for “Access denied” on a local path, **Admin**: it repeats the item and the rest of the job through the administrator helper (see [File operations](#file-operations)).

Background jobs show at the right of the tab bar: one chip per job and a list button at the end.

**Chips**
- A chip has an icon for the operation and its progress: `»` copy, `►` move, `▼` recycle, `‼` delete, `■` pack, `□` unpack.
- Instead of a percentage it can show `..` (queued), `?` (waiting for an answer) or `!` (failed).
- Clicking a chip brings that job back: its progress window, question or error message.
- The `[≡N]` button opens the job list.
- With no background jobs nothing is shown there, whether or not the status line is visible.

**Finishing.** When a job that ran in the background for a while finishes, a toast says so; if it stopped with an error, the toast is shown even with notifications turned off, and clicking the job's chip opens the error.

---

[Contents](#contents)

## File associations

**Ctrl+Alt+Shift+A** – what **Enter** does for files with a given extension: view, edit, open with the Windows program or a custom command (`%1` – path to the file). In the list: **Ins** – add, **F2** – edit, **Del** – delete.

---

[Contents](#contents)

## Settings

The **Options** menu (F9):
<!--theme-->- **Theme...** – pick the appearance; changes at once.

**Customize...** opens the editor of the selected theme: sections (colors of windows, dialogs, buttons, cursor, panels and more, Markdown, text styles, glyphs, frames) with their values.
- **Enter** on a row edits the value: a color is typed as `#RRGGBB` or picked with **F9** / the **[...]** button.
- **Inherit** returns the value of the base theme; rows with an asterisk are set by the theme itself.
- A color is a `#RRGGBB` value, a reference to another role of the theme (`@cursor.bg`) or a name from the palette.
- The **Bases** section lists the themes this one builds on (several separated by `;`, later ones override earlier ones).
- Changes show at once.

**Saving**
- **Save** writes the theme to a file. Built-in themes are read-only: a copy of a built-in theme is saved under a new name (a file in the `themes` folder of the settings folder), your own theme is updated in place by **Save**.
- **Save as...** writes the theme under another name.
- **New...** makes a theme from scratch ("blank") or from any other one.
- **Delete** removes your own theme.

If the theme of the saved session is not found, the program says so and uses the classic Far theme.
<!--display-->- **Font / Display...** – font, size, zoom, cursor shape and blinking, file icons in the panel, **line spacing** (see below), **shadows** and how **marked files** look; everything applies without a restart.

**Shadows and marked files**
- Window and button **shadows**: Classic, Soft or None; the dimming behind a dialog is lightened or dropped with them.
- **Marked files:** “Text color” – only the letters change colour, as in Far; “Row background” – a background band across the whole row as well.
<!--interface-->- **User interface...** – the interface language, notifications, the visibility of the window rows, dragging, the menu on Alt, auto-indent and a few more boxes; everything applies without a restart.

**What it sets**
- The **interface language** (English / Русский / Deutsch / 简体中文) and pop-up notifications.
- The **window title bar, menu bar, F-key bar and status line.** A hidden row goes to the panels.
- **Dragging files with the mouse** (can be switched off), the **menu on a single Alt press** (can be switched off), the cursor in the inactive panel, **vertical lines between columns** (Full and custom modes; Brief always has them, off by default) the **editor auto-indent on Enter** (can be switched off) and **filtering the panel while quick searching** (Alt+letter: besides moving the cursor, the files whose names do not begin with the typed text are hidden; the search box stays open after Alt is released and Esc or Enter removes the filter; the option **fuzzy filter** also keeps names that contain the typed letters in order, not necessarily next to each other; the option **keep the filter in other folders** carries it into a folder opened with Enter or a click, and then only Esc removes it; off by default).

**Hidden window rows**
- With the menu bar hidden, F9 shows it over the top row while the menu is open.
- With the window title bar hidden the **[_] [□] [x]** buttons move to the right end of the menu bar, or of the tab bar when that is hidden too.
- The window title is shown in the free space of the tab bar; the window is dragged by the free parts of the menu and tab bars and resized by its edges.
- A right click on a free spot of the tab bar opens the top menu, like F9.

**Selection and size boxes**
- **“Select all also folders”** makes Shift+Gray + / Shift+Gray − and select by extension take folders too (files only by default, as in Far).
- **“Show exact size in bytes”** shows the sizes in the panel footer (the totals of the folder or of the selection, the size of the item under the cursor) and in the status line as the exact number of bytes with the system digit grouping (`1,234,567`) instead of `1.2 M`; when the number does not fit, the short form stays. The Size column of the file list does not change.

**Vim keys on the panel.** The **“Vim keys on the panel”** box (off by default) enables these keys on the panel while the command line is empty:
- **j / k** – cursor down / up;
- **h** – go to the parent folder; **l** – open the item;
- **g / G** – jump to the first / last row;
- **/** – start the quick search; **:** – move to the command line.
<!--columns-->- **Columns...** – the columns of the “Custom” mode.
<!--console-->- **Console...** – the scrollback size of the console and terminals, confirmation of a multi-line paste, removal of trailing spaces on copy and paste, return to the panels when a command from the command line ends (more in the command line help).
<!--save-settings-->- **Save settings** – writes the settings, the panels and the tabs to the settings file now, not only when the program closes; a toast confirms it or names the problem. Options changed in dialogs are applied at once; this item makes sure they are on disk, for example before a copy of the settings folder is taken.
<!--settings-file-->- **Export settings... / Import settings...** – the settings as one zip file.

**What is included.** The session and display options, keys, user menu, associations, hotlist, SSH connection list, workspaces, own themes; histories are not included.

**How it works**
- The file name field is an input with a ↓ drop-down of the files used before; by default it is `mtn2-settings.zip` in the folder of the active panel.
- Before an import the replaced files are saved as `settings-backup.zip` in the settings folder.
- The new settings take effect after MTN2 restarts.
<!--location-->- **Settings location...** – chooses where the settings are kept: the user folder (standard mode) or next to the program (portable mode, the `portable.dat` file).

**What the dialog shows.** Both places, how many files move and what stands in the way: no write access to the program folder, a program folder shared by all users, files at the target that are replaced (they stay as `*.before-switch`).

**Moving**
- The session, histories, keys, plugin settings and your own themes move together and the old copies are deleted.
- The change applies at once, without a restart. If anything fails, the old place stays in force.
- The languages and shipped themes in `resource\` always stay with the program.
<!--color-coding-->- **Color coding...** – row colors by name masks and, optionally, by size, age and attributes (the **Condition** field: terms such as `size>10M`, `age<7d`, `+H`, `-R`; the letters are H hidden, R read-only, S system, A archive, C compressed, E encrypted, L link; `age<7d` means modified less than 7 days ago); they are stored in the theme, so an edit made with a built-in theme is saved as a new theme (the program asks for its name). **F9** on a color field, or a click on the **[...]** button at its right end (it shows the field's color), opens the color picker (see below).
  Condition examples (a group applies only when the mask and the condition both match):
  - `size>100M` – files larger than 100 MB, for example to paint big logs red with the mask `*.log`.
  - `size>0 size<4K` – small non-empty files.
  - `age<1d` – changed within the last day; `age<90m` – within 90 minutes.
  - `age>30d` – not touched for a month (grey out stale files); `age>2w` – older than two weeks.
  - `+H` – hidden files only; `+HS` – hidden and system; `-R` – anything that is not read-only.
  - `size>1G age>90d -R` – big, old and writable: all three must hold (candidates for cleanup).
  - A folder has no size, so a group with a size term never matches folders; a condition with only attributes or age works for folders too. Groups are checked top to bottom and the first match wins, so put the narrow group (`*.log` + `size>100M`) above the general one (`*.log`).
- **Keymap...** – view and change keys.
<!--plugins-->- **Plugins...** – installed plugins. Every plugin is on by default.

**Controls**
- **Space** on a row switches the plugin off or on (`[x]` is on, `[ ]` is off); the choice applies on **OK** and is kept between runs, **Cancel** drops it.
- **Permissions...** opens a dialog: allow the plugin to replace built-in handlers (`[replaces .zip: on]`) and what its manifest asks for, for example reading files through the program (`[needs vfs.read: on]`).
- **Ctrl+Up** and **Ctrl+Down** change the load order of the plugins (it matters between plugins of equal priority and applies from the next start).
- **Info** shows what the plugin is for and what it added (commands, keys, file types, schemes) and opens its help page when it has one.
- **Add...** installs a plugin from a folder or a `.zip` file (it must contain `plugin.json`; the folder is named after its `id`). An installed plugin is switched off: turn it on with Space and press **OK**. A plugin with the same `id` is replaced after a confirmation; a loaded plugin keeps its old version until the next start. An archive with paths outside the plugin folder is refused.
- **Remove** deletes the folder of the selected plugin after a confirmation. If its files are in use (the plugin is loaded), switch it off, restart the program and try again.
<!--external-tools-->- **External viewer/editor...** – the Alt+F3 / Alt+F4 commands; `%1` is the file path (without `%1` the path is added at the end), e.g. `"C:\Program Files\Notepad++\notepad++.exe" %1`.
- **Environment profiles...** – variables laid over the environment of new shells; see [Environment profiles](#environment-profiles).
<!--markdown-colors-->- **Markdown colors...** – colors of the Markdown view (F3 on a `.md` file): a foreground and a background (`#RRGGBB`) and a **text style** for every element.

**Elements and styles**
- Elements: headings, bold, italic, strikethrough, code, quote, list markers, rules, links, tables.
- The style comes from a list: Theme, Plain, Bold, Italic, Bold italic, Underline, Strikethrough and combinations.
- An empty field or **Theme** in the style list keeps the theme's own; **Plain** turns off the style the element has (for example the underline of links).
- **F9** on a field or a click on its **[...]** button opens the color picker.
- The **Text / document** row sets the text color and the background of the whole Markdown view (only for Markdown, other files keep the theme colors); elements without a background of their own follow it.
- The sample next to a row is drawn with its colors and style.

**Import from Obsidian...** reads the colors from an Obsidian theme (`theme.css`, for example `<vault>\.obsidian\themes\<theme>\theme.css`).
- The **Dark** or **Light** palette is picked in the import dialog.
- The imported colors and text styles (weight, italic and underline the theme sets for headings, bold, links, quotes and table headers) replace the fields and lists (nothing is saved until OK).

**Reset** empties all fields and sets every style to **Theme**, so the theme's own colors and styles apply.

**Where they are stored.** In the active theme: with a built-in theme the program asks for the name of a new theme, your own theme is updated in place; the fields hold only what the theme sets itself (the rest is inherited).
- **Zoom**: Ctrl+mouse wheel, **Ctrl+0** – reset.

<!--color-picker-->### Color picker

The picker has:
- a grid of swatches (hues across, light to dark down; the bottom row is gray);
- sliders **H, S, L** (hue, saturation, lightness) and **R, G, B**;
- a **Hex** field next to two swatches: the color **was** when the picker opened and the color **now**.

**Keys**
- **Up / Down** switch between the grid, the sliders and the hex field.
- **Left / Right** move along the grid or change a slider by 1 (**Shift** – by 10, **PgUp / PgDn** – by 10, **Home / End** – to the ends).

**Mouse.** A click picks a swatch or sets a slider; a click on the **was** swatch returns to the original color.

The grid uses the current saturation, so the **S** slider makes it paler or more vivid. **Use** takes the color, **Theme color** clears the field so the theme's color applies again.

### Font and line spacing

The **Line spacing (as in a terminal)** checkbox in **Options → Font / Display...** makes rows 15% of the font size taller; the text stays centred in the row, frames and highlights stretch over its whole height. It is off by default: rows are as tall as the font's line, and more of them fit on the screen. For Cascadia Mono 11 pt that is 17 pixels without spacing and 19 with it – the same as in Windows Terminal.

Font size is in typographic points, as in Windows Terminal and the Windows console: 6 to 24 pt, in half-point steps from 8 to 12 pt. At 100% Windows scaling 1 pt = 4/3 pixel: 10.5 pt is 14 pixels (the former default), 11 pt is 14.7 pixels.

Two more options in the same dialog make the text crisper:
- **Snap font size to device pixels** rounds the letter size to whole physical screen pixels. With 125% or 150% Windows scaling and fractional sizes (11 pt) the strokes then have an equal weight. The cell size can change slightly. Off by default.
- **Text contrast** (Off, Low, Medium, High) fills in the faint anti-aliased fringe: thin light text on a dark background reads firmer. Off by default.
- **Cell width** and **Cell height** add 0 to 4 physical pixels to every cell. They help a font whose letters touch or whose rows sit too tight. Letters stay centred in the cell, frames fill it completely. 0 by default.
- **Fallback font** names a second font family for the characters the main font lacks, such as CJK ideographs and symbols. Type the family name; an empty field, or a family that is not installed, leaves the choice to Windows. The fallback does not change the cell size: that comes from the main font.

#### Why text looks different from Far

Far does not draw its text itself: the console window it runs in does – Windows Terminal or the classic Windows console – with its own font and rules. Compared with the same font, size and colours, MTN2 and Far draw the same letters: stroke weight and antialiasing match. The differences come from settings:
- **Font and size.** Windows Terminal defaults to Cascadia Mono 11 pt. MTN2 uses the font and size from Font / Display (Cascadia Mono if installed, otherwise Consolas; 10.5 pt). Narrow, light fonts such as Ubuntu Mono look thinner and paler, especially on blue.
- **Row height.** Windows Terminal adds about 15% of the font size to the font's line. In MTN2 that is the Line spacing checkbox; without it rows are tighter. The classic Windows console takes the row height from the font's Windows metrics, which can be another 1–3 pixels taller (Cascadia Mono 11 pt – 20 pixels).
- **Colours.** MTN2's colours come from its theme; Far's from its own highlighting and the terminal's colour scheme. In the default theme plain files are light grey; in Far they are usually cyan, with twice the contrast on blue, so the text looks bolder.
- **Antialiasing.** MTN2 uses greyscale antialiasing. So does Windows Terminal when the profile's `antialiasingMode` is `grayscale` (the default); with `cleartype` letters get coloured fringes. The classic Windows console uses ClearType when it is on in Windows.
- **Windows scaling.** Both draw text in physical screen pixels, so it is equally sharp at 125% and 150%.

#### When they match

MTN2 matches Far in Windows Terminal in cell size, stroke weight and row height when:
- the font is the same (Windows Terminal's default is Cascadia Mono);
- the size is the same (Windows Terminal's default is 11 pt);
- Line spacing (as in a terminal) is on;
- the Windows Terminal profile uses `grayscale` antialiasing;
- MTN2's theme and Far use similar colours.

With the classic Windows console (Far without Windows Terminal) they will not match exactly: its row height and ClearType are its own.

### Notifications

Commands that change nothing on screen confirm themselves with a short notice in the bottom right corner; it disappears after a few seconds and does not take keys. Notices appear for:
- **Alt+Shift+Ins** / **Ctrl+Shift+Ins** – the path / name copied (or “Nothing to copy”);
- **Ctrl+C** / **Ctrl+X** (**Ctrl+Ins** / **Ctrl+Del**) on the panel – the files placed on the clipboard;
- copying text in the viewer / editor (without a selection – the current line), in the command line and in a terminal;
- **Ctrl+R** – the panel refreshed;
- **Ctrl+Shift+O** – the folder the console went to;
- **Ctrl+Alt+R** – the item restored from the Recycle Bin;
- **Ctrl+Alt+D** – the folder added to the hotlist;
- selection by mask (**Gray +/−**, **Ctrl+Gray +/−**, **Alt+Gray +/−**) that changed nothing – shown in red.

Notices are turned off in **Options → User interface...** (“Show pop-up notifications”). The update-check notice is the exception: it has its own checkbox (see [Updates](#updates)).

### Updates

Checking for and installing new versions, their settings and what goes over the network are on the [Updates](#updates) page.

---

[Contents](#contents)

## Updates

MTN2 can update itself: it finds a new version on GitHub, downloads and installs it, but only when the user agrees.

### How an update goes

A few seconds after startup, once a day, MTN2 checks GitHub for a new version. If there is one, it asks: **Update**, **Later** or **Skip this version** (a skipped version is not offered again). Nothing is downloaded or installed without an answer.

After the download (the package is checked against its SHA-256) MTN2 offers to **Restart** now or install **On exit**. While copy jobs are running, installation waits until exit. Only program files are replaced (including `7z.dll`, which comes with the package) – settings and other user files stay as they are.

### Check settings

**≡ → Check for updates...** (F9, then the leftmost top-menu item) shows the installed version, checks right away (**Check now**) and has two checkboxes:

- **Check for updates at startup** – once a day at startup. With it off, MTN2 does not go online by itself.
- **Show a notice when checking** – every check that goes online (at startup or with **Check now**) shows a notice “Checking github.com for MTN2 updates...” in the bottom right corner for a few seconds.

Details:
- For the startup check the notice has a second line on how to turn the check off.
- It is shown even when other pop-up notices are off and disappears as soon as GitHub has answered.
- While a dialog is open it stays hidden under it.

### What goes over the network

The check is a single HTTPS request to `api.github.com` for the latest release of the `Laex/MTN2` repository. It carries nothing but the MTN2 version in the `User-Agent` header – no file names, paths or settings. The update itself is the release package downloaded from GitHub after **Update**.

---

[Contents](#contents)

## Key bindings

The built-in key set can be partly redefined by the `keymap.json` file in the settings folder (or via **Options → Keymap...**): only the changed actions are listed, the rest stay built-in. **Ctrl+Alt+K** – reload the file without a restart.

Besides the panels, the viewer and editor commands can be rebound. Their names in `keymap.json` start with:
- `Doc` – both viewing and editing: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…;
- `Viewer` – viewing only: `ViewerWrap`;
- `Markdown` – rendered Markdown: `MarkdownSource`;
- `Editor` – editing only: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…

The same chord can mean different things on the panels and in a document – Ctrl+H shows hidden files on a panel and toggles hex in a document. A narrower meaning overrides a general one: F4 over rendered Markdown toggles the source, not hex.

Global commands work in any window – the panels, a document, a terminal:
- `Help` (F1), `TopMenu` (F9), `CommandPalette` (Shift+F9);
- `NextTab` / `PrevTab` (Ctrl+Alt+PgDn / Ctrl+Alt+PgUp);
- `AppConsoleToggle` (Ctrl+O), `NewTerminal` (Ctrl+Shift+N), `SelectConsoleProfile` (Ctrl+Alt+O);
- `AppQuit` (Alt+X), `ZoomReset` (Ctrl+0), `ReloadKeymap` (Ctrl+Alt+K);
- `ToggleMouse` (Ctrl+Shift+M, text terminal version only).

**A chord the window binds itself.** It stays the window's:
- F10 closes a document and quits only on the panels (`Quit`);
- Esc on the panels shows the console (`ConsoleToggle`) when the panel has the focus; in the command line it first clears it, then gives the focus back to the panel.

**Full-screen program.** While one runs in a console or terminal (the profile's keys mode is *auto* or *terminal*, see Terminals), the console gets these keys too, except the ones that leave it: F11, Ctrl+O, switching tabs, Ctrl+Shift+N and Ctrl+Alt+O.

**Dialogs.** While a dialog is open the global commands do not fire; `ZoomReset` and `ReloadKeymap` always do.

In the console (Ctrl+O) and a terminal the commands named `Shell…` can be rebound:
- `ShellHistory` (Alt+F8), `ShellSelectAll` (Ctrl+A);
- `ShellCopyOrInterrupt` (Ctrl+C – copy the selection, or interrupt the command without one), `ShellCopy` (Ctrl+Ins), `ShellPaste` (Ctrl+V, Shift+Ins);
- `ShellFind` (Ctrl+Shift+F – search the output), `ShellFindNext` / `ShellFindPrev` (F3 / Shift+F3);
- in the console also `ConsoleSyncDir` (Ctrl+Shift+O – the panel goes to the console's folder).

Every other key goes to the shell.

**Settings → Keymap** groups the actions by window – global, file panels, viewer and editor, console and terminal – under readable names; the `keymap.json` name shows in the edit window. The F-key labels at the bottom, hints such as `A:All` and the shortcuts in the top menu come from the keymap: after a rebinding they show the new key.

An action can have several shortcuts: list them separated by `;` in the edit window, or as separate entries in `keymap.json`. Besides letters, digits and special keys, the signs `/`, `,`, `.`, `'`, `=` can be assigned; write semicolon and the main-block minus as `Semicolon` and `Minus` (`-`, `+` and `*` mean the numeric keypad keys).

Modifiers must match exactly: Ctrl+Shift+A is not Ctrl+A. Arrows, Home/End, typing and `/` in the viewer are not configurable.

### Tab keys

All tab keys are ordinary keymap actions and can be rebound in `keymap.json`. Panel tabs and workspaces (the tabs of the top row) are different things, each with its own actions:

| What | Action in `keymap.json` | Default |
| --- | --- | --- |
| New panel tab | `NewTab` | Ctrl+T |
| Next / previous panel tab | `NextPanelTab` / `PrevPanelTab` | Ctrl+Tab / Ctrl+Shift+Tab |
| Close the panel tab | `CloseTab` | Ctrl+W |
| New workspace | `NewWorkspace` | Ctrl+Shift+W |
| Next / previous workspace | `NextTab` / `PrevTab` | Ctrl+Alt+PgDn / Ctrl+Alt+PgUp |

The `[+]` and `[x]` buttons in the tab rows and the top menu items do the same.

### Your own `keymap.json` and updates

The `keymap.json` in the settings folder is laid over the built-in keymap: the actions it lists win over the built-in ones.
- The **Settings → Keymap** dialog writes only the changed actions to the file, so the other keys follow the built-in keymap after an update.
- A file saved by earlier versions lists all actions and freezes the old keys: to get the new ones, delete the lines of the actions you need from it, or the whole file (keep a copy first if it holds changes of your own).
- An action without keys is written as an empty list.

### Examples for Far and MC habits

The repository holds three example `keymap.json` files, [`keymap.far.json`, `keymap.mc.json` and `keymap.tc.json`](https://github.com/Laex/MTN2/tree/main/docs/keymap-presets). Copy the one you want into the settings folder as `keymap.json` (or add its actions to your own file) and press **Ctrl+Alt+K**.
- **Far:** Esc on the panels clears the command line and does not open the console (it stays on Ctrl+O).
- **MC:** Alt+. shows hidden files, Ctrl+\ opens the folder list, Alt+Enter inserts the file name into the command line, Alt+A and Alt+Shift+A insert the folder path of the active and the other panel, and Properties moves to Ctrl+Shift+P.
- **Total Commander:** Alt+F5 and Alt+F9 pack and unpack, Ctrl+A selects all, Ctrl+M renames by rules, Ctrl+P inserts the folder path, Ctrl+Tab and Ctrl+Shift+Tab switch tabs, Alt+Down opens the folder history. The default keymap already follows Norton Commander habits.

### Reserved keys

Not taken yet and kept for planned features: **Shift+F3** (archive commands), **F11** (the plugin menu), **Ctrl+Alt+Ins** (network UNC paths), **Ctrl+.** (macro recording). An automatic check keeps the built-in keymap from taking them.

---

[Contents](#contents)

## Settings files

The settings folder is `%APPDATA%\MTN2\`. If a `portable.dat` file lies next to `MTN2.exe`, settings are kept next to the program (portable mode).

| File | Contents |
| --- | --- |
| `session.json` | state of the window, panels and tabs, theme, font, language |
| `keymap.json` | redefined keys |
| `environment.json` | environment profiles for shells |
| `aliases.json` | your own search words for the command palette |
| `history.json` | command history |
| `folderhistory.json` | folder history |
| `filehistory.json` | file history (Alt+F11) |
| `externaltools.json` | external viewer and editor (Alt+F3 / Alt+F4) |
| `themes\*.theme.json` | your themes (Settings → Theme...) |
| `dialoghistory.json` | dialog input field history |
| `workspaces.json` | saved workspaces |
| `sshconnections.json` | SSH/SFTP connections |
| `associations.json` | file associations |
| `usermenu.json` | main user menu (F2) |
| `.mtn2menu.json` (in any folder) | menu of that folder and the folders below |

---

[Contents](#contents)
