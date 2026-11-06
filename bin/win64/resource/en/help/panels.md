## Panels and navigation

| Key | Action |
| --- | --- |
| ↑ ↓ PgUp PgDn Home End | move the cursor |
| ← / → | in Brief mode – one column left / right; in the other modes – to the first / last item (like Home / End) |
| Enter | enter a folder / archive, open a file (by [association](associations.md)); run a console program in the built-in console (see below) |
| Backspace | up one level, like Enter on `..` (with an empty command line; otherwise it erases a character there) |
| Ctrl+PgUp / Ctrl+PgDn | up one level / enter the folder under the cursor, as in FAR; on a file Ctrl+PgDn opens it as an archive (see [Archives](archives.md)) |
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

[Contents](index.md)
