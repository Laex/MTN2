# User menu (F2)

Your own list of commands: items with hot keys, nested submenus and separators. A command runs in the panel console, in the folder of the active panel; its output is shown with **Ctrl+O**.

**Two menus:**

- **Main** — shared by all folders.
- **Folder menu** — the `.mtn2menu.json` file in a folder. It applies to that folder and all folders below it; if such files exist on several levels, the nearest one is used. Handy for projects: a menu in the root of a repository is available in any of its subfolders.

**F2** opens the folder menu if there is one, otherwise the main menu. **Shift+F2** in an open menu switches folder menu ↔ main menu. To create a menu for a folder: F2, then Shift+F2 (an empty menu of this folder opens) and **Ins**.

**Keys in the menu:**

| Key | Action |
| --- | --- |
| Enter, item hot key, click | run the command or enter the submenu |
| → | enter the submenu |
| ← / Esc | one level up; Esc at the top level closes the menu |
| Ins | add an item before the cursor |
| F4 | edit the item |
| Del | delete the item (a submenu — together with its contents) |
| Ctrl+↑ / Ctrl+↓ | move the item |
| Shift+F2 | folder menu ↔ main menu |

**Menu item:** hot key (one character), type (command / submenu / separator), caption and command. If the caption is empty, the command itself is shown.

**Substitutions in a command:**

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
| `!^` | further substitutions — from the **active** panel again |
| `!!` | the `!` character itself |

Names with spaces are substituted as is — quote them yourself: `"!\!.!"`.

**Examples:**

```
notepad.exe "!\!.!"                    open the file in Notepad
explorer.exe /select,"!\!.!"           show the file in Explorer
certutil -hashfile "!.!" SHA256        checksum
fc "!.!" "!#!\!.!"                     compare with the same-named file on the other panel
7z a "!?Archive name?backup!.7z" @!@!  pack the selection, asking for the archive name
git commit -am "!?Commit message?!"    commit, asking for the message
```

The command runs in the shell chosen for the console (cmd, PowerShell, WSL) — write commands in its syntax. Several commands on one line can be joined with `&&` (cmd, PowerShell 7).

Until the main menu has been saved even once, it shows examples. Menu files can also be edited by hand — changes are picked up the next time the menu opens.

---

[Contents](index.md)
