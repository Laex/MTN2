## Terminals

**Ctrl+Shift+N** – a new terminal in a separate workspace tab: choose a shell profile (cmd, PowerShell, WSL, saved SSH connections). Full-screen programs (vim, mc, htop, …) work in the terminal just as in a regular console.

<!--profiles-->In the profile list:

- **1-9, 0, A-Z** – start the profile with that number (highlighted at the start of the line).
- **Ins** – copy the selected profile: the same shell, its own settings. **Del** deletes a copy (a profile itself cannot be deleted).
- **Ctrl+Up / Ctrl+Down** – move the profile; the order is remembered (`shellprofiles.json` in the settings folder).
- **F4** – the profile's keys mode. The mode applies to the background console (Ctrl+O) too when its profile is chosen.

The modes:
- *auto* – the program gets the keys while a full-screen application such as mc or vim runs in the console;
- *while running* – as *auto*, and also while a console program started from the shell is running, even one that does not use the alternate screen, such as Far Manager. At the bare prompt the window's keys apply; a GUI program launched from the shell does not count;
- *terminal* – the program gets every key, including F1, F9 and Alt+letter; the only keys that stay with the window are the bare navigation keys (arrows, Home, End, PgUp, PgDn, Insert, Delete, with or without Shift) at the bare prompt, where they scroll, select and recall history. It is the mode for shells that are themselves the program (bash in WSL, ssh, Git Bash), which need their own Ctrl+R, Ctrl+A and so on;
- *host* – the MTN2 window's keys come first.

Who gets the keys:

| Mode | At the bare prompt | An ordinary command (`ping`, `git`, a build) | A full-screen program (`vim`, `htop`) | A console program without the alternate screen (Far Manager) |
|---|---|---|---|---|
| auto | window | window | program | window |
| while running | window | program | program | program |
| terminal | program | program | program | program |
| host | window | window | window | window |

"Window" here means the MTN2 window's own keys: help, scrolling and selecting the output, command recall. In *auto* the window keeps scrolling and selecting while an ordinary command runs; a program such as Far needs *while running* or *terminal*. "While running" tells a program from the prompt by a console process started by the shell, so it does not apply to a shell that is itself the program (WSL, ssh): use *terminal* for those.

In *auto*, *while running* and *terminal* the window keeps only the keys that leave the console: F11, Ctrl+O, switching tabs, Ctrl+Shift+N and Ctrl+Alt+O.
- **F6** – the environment profile of the selected shell or its copy (see [Environment profiles](environment.md)).

---

[Contents](index.md)
