## Terminals

**Ctrl+Shift+N** – a new terminal in a separate workspace tab: choose a shell profile (cmd, PowerShell, WSL, saved SSH connections). Full-screen programs (vim, mc, htop, …) work in the terminal just as in a regular console.

In the profile list:

- **1-9, 0, A-Z** – start the profile with that number (highlighted at the start of the line).
- **Ins** – copy the selected profile: the same shell, its own settings. **Del** deletes a copy (a profile itself cannot be deleted).
- **Ctrl+Up / Ctrl+Down** – move the profile; the order is remembered (`shellprofiles.json` in the settings folder).
- **F4** – the profile's keys mode: *auto* (the program gets the keys while a full-screen application such as mc or vim runs in the console), *terminal* (the program gets every key, including F1, F9 and Alt+letter) and *host* (the MTN2 window's keys come first). In *auto* and *terminal* the window keeps only the keys that leave the console: F11, Ctrl+O, switching tabs, Ctrl+Shift+N and Ctrl+Alt+O. The mode applies to the background console (Ctrl+O) too when its profile is chosen.

---

[Contents](index.md)
