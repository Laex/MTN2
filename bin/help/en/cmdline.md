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
| Esc | step by step: clear the line → give the focus back to the panel → show the console. With an empty line the first step is skipped; with the focus on the panel Esc shows the console at once |
| Ctrl+O | panels ↔ console |
| Ctrl+Shift+O | synchronize the folder between the active panel and the console |
| Ctrl+Alt+O | choose the shell of the background console (cmd, PowerShell, WSL, …) |

**Commands → Background console...** is the same dialog. **Start shell at program launch** is off by default: the shell starts on the first **Ctrl+O** or the first command from the command line. Turn the option on to start the shell together with the program, as before.

**In the console:** **Ctrl+C** interrupts the command; **Esc** only hides the console and does not stop the process. The mouse wheel scrolls the output. Text is selected with the mouse (see [Working with text and the mouse](text.md)).

**Options → Console...** sets the scrollback size of the console and terminals (1000 – 50,000 lines, 10,000 by default), the confirmation of a multi-line paste (off; a full-screen program such as vim never asks) and the removal of trailing spaces on copy and on paste. Changes apply at once, to open consoles too.

**Commands → Save console output...** writes the background console's scrollback (Ctrl+O) to a UTF-8 text file; **Clear console buffer** erases it, the shell keeps running.

---

[Contents](index.md)
