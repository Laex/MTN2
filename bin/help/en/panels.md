# Panels and navigation

| Key | Action |
| --- | --- |
| ↑ ↓ PgUp PgDn Home End | move the cursor |
| Enter | enter a folder / archive, open a file (by [association](associations.md)) |
| Shift+Enter | run a file or command in a separate OS window |
| Tab | switch the active panel |
| Ctrl+\\ | go to the drive root (inside an archive — leave the archive) |
| Alt+← / Alt+→ | back / forward through the folder history |
| Ctrl+U | swap the panels |
| Ctrl+] | passive panel := folder of the active one |
| Ctrl+[ | active panel := folder of the passive one |
| Ctrl+F1 / Ctrl+F2 | hide / show the left / right panel |
| Ctrl+L | information panel (drive, memory) on the other side |
| Ctrl+H | show / hide hidden and system files |
| Ctrl+R | refresh the panel |
| Ctrl+Q | quick view of the file on the other panel: picture, text, Markdown or hex |
| Alt+letter | quick search by name in the panel |

**Quick view (Ctrl+Q)** shows the file under the cursor on the other panel: a picture, text (the encoding is detected), rendered Markdown or a hex dump of a binary file; large files are streamed. The mouse wheel over it scrolls the preview. Files on SFTP and big files inside archives are not read on every cursor move — the panel suggests opening them with F3. Tab or Ctrl+Q again closes the quick view.

A mouse click places the cursor, a double click acts like Enter. Files can be dragged with the mouse between the panels and to other programs (and back).

---

[Contents](index.md)
