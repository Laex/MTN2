## Command line and console

The command line is always below the panels: just start typing. A command runs in the built-in console; its output is shown with **Ctrl+O**.

| Key | Action |
| --- | --- |
| Enter | run the command; a typed folder path goes to the folder, a file (including a name put there by Ctrl+Enter) runs: a console program in the built-in console, anything else with its Windows program. Then the focus goes back to the panel and the arrows move the cursor again |
| Ctrl+↓ / Ctrl+↑ | focus the command line / back to the panel |
| ↑ / ↓ (while typing a command) | command history |
| Tab | completion: a name from the panel, or a path from the disk when the word has `\`, `/` or `X:` (repeated presses cycle the matches) |
| Ctrl+↓ / Alt+↓ (line focused) | command history as a list: Enter – put on the line, Del – remove from the history, Esc – close |
| Ctrl+Enter | insert the name of the item under the cursor |
| Ctrl+F, Ctrl+Shift+Enter | insert the full path of the item |
| Alt+Shift+Enter | run the command line in the background: the console shows the start for a moment, then the panels come back (**Options → Console...** below) |
| Ctrl+Alt+Enter | run the command line in a new terminal tab: a new workspace tab with the shell of the background console (cmd, PowerShell, WSL, ...), the command starts there and the tab stays open |
| Esc | step by step: clear the line → give the focus back to the panel → show the console. With an empty line the first step is skipped; with the focus on the panel Esc shows the console at once |
| Ctrl+O | panels ↔ console |
| Ctrl+Shift+O | synchronize the folder between the active panel and the console |
| Ctrl+Alt+O | choose the shell of the background console (cmd, PowerShell, WSL, …) |

**Commands → Background console...** is the same dialog. **Start shell at program launch** is off by default: the shell starts on the first **Ctrl+O** or the first command from the command line. Turn the option on to start the shell together with the program, as before.

**In the console:** **Ctrl+C** interrupts the command; **Esc** only hides the console and does not stop the process. The mouse wheel scrolls the output. Text is selected with the mouse (see [Working with text and the mouse](text.md)).

**Paste into the console** (**Ctrl+V**, **Shift+Ins**): every line break goes to the shell as Enter, so pasted lines run one after another, the last one too. With **Confirm multi-line paste** on, the program asks first.

**Options → Console...** sets the scrollback size of the console and terminals (1000 – 50,000 lines, 10,000 by default), the confirmation of a multi-line paste (off; a full-screen program such as vim never asks) the removal of trailing spaces on copy and on paste, and **Always return to the panels when a command ends** (off). With it on, a command run from the command line under the panels sends you back to the panels as soon as the shell shows its prompt again; a command typed in the background console (Ctrl+O) always stays in the console. **Alt+Shift+Enter** runs the command line in the console in the background: the console is shown for the time set in **Background run** (0.5 – 10 s, 2 s by default) and the panels come back by themselves; a key pressed in the console before that keeps it in front, and the command goes on running either way. Changes apply at once, to open consoles too.

**Commands → Save console output...** writes the background console's scrollback (Ctrl+O) to a UTF-8 text file; **Clear console buffer** erases it, the shell keeps running.

---

[Contents](index.md)
