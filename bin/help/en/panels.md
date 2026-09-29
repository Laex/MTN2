## Panels and navigation

| Key | Action |
| --- | --- |
| ↑ ↓ PgUp PgDn Home End | move the cursor |
| ← / → | in Brief mode – one column left / right; in the other modes – to the first / last item (like Home / End) |
| Enter | enter a folder / archive, open a file (by [association](associations.md)); run a console program in the built-in console (see below) |
| Backspace | up one level, like Enter on `..` (with an empty command line; otherwise it erases a character there) |
| Shift+Enter | run a file or command in a separate OS window |
| Tab | switch the active panel |
| Ctrl+\\ | go to the drive root (inside an archive – leave the archive) |
| Alt+← / Alt+→ | back / forward through the folder history |
| Ctrl+U | swap the panels |
| Ctrl+] | passive panel := folder of the active one |
| Ctrl+[ | active panel := folder of the passive one |
| Ctrl+F1 / Ctrl+F2 | hide / show the left / right panel |
| Ctrl+L | information panel (drive, memory) on the other side |
| Ctrl+H | show / hide hidden and system files |
| Ctrl+R | refresh the panel |
| Ctrl+Q | quick view of the file on the other panel: picture, text, Markdown or hex |
| Alt+F10 | folder tree of the drive over the active panel (see below) |
| Alt+letter | quick search by name in the panel |

**Folder tree (Alt+F10)** opens over the active panel: the drive root with the path to the current folder open and the cursor on it. ↑ ↓ PgUp PgDn Home End move, → or `+` opens a branch (`[+]`) or steps into it, ← or `-` closes a branch (`[-]`) or goes to the parent, a letter jumps to the next folder starting with it. The other panel goes to the folder under the cursor once the cursor stops. Enter opens the folder in the active panel and closes the tree; Esc or Alt+F10 closes the tree and the same panel shows again. Tab or a click on the other panel moves the focus there and the tree stays, like a FAR tree panel; Tab or a click on the tree's frame brings the focus back. With the mouse the tree works as an index: a click on a folder shows it in the other panel at once and moves the focus there, a click on `[+]` / `[-]` opens or closes the branch without moving the focus; the mouse wheel scrolls the tree without moving the cursor. The tree also follows the other panel: when it goes to another folder, the tree opens the path to it and puts the cursor there, and rebuilds itself for another drive. Folders are read in the background; if the panel under the tree goes to another folder meanwhile, the tree closes. The tree is open over one panel at a time.

**Quick view (Ctrl+Q)** shows the file under the cursor on the other panel: a picture, text (the encoding is detected), rendered Markdown or a hex dump of a binary file; large files are streamed. The mouse wheel over it scrolls the preview. Files on SFTP and big files inside archives are not read on every cursor move – the panel suggests opening them with F3. Tab or Ctrl+Q again closes the quick view.

**Console programs** (a console-subsystem `.exe`, `.bat`, `.cmd`, `.ps1`) run on Enter so that their output stays on screen, not in a separate Windows window:
- in the background console (Ctrl+O) when its shell is cmd, PowerShell or pwsh and nothing runs in it: like a command typed in the command line;
- otherwise (a WSL, Git Bash or SSH console, or one busy with another command) – in a new terminal tab with cmd, or PowerShell for a `.ps1`; the tab stays open after the program ends.

Window programs and documents open with their Windows program as before. **Shift+Enter** still runs any file in a separate window.

A mouse click places the cursor, a double click acts like Enter. Files can be dragged with the mouse between the panels and to other programs (and back).

---

[Contents](index.md)
