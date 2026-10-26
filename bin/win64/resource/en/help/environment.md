## Environment profiles

**Options → Environment profiles...** opens the `environment.json` file in the editor (on first use it is created with an example). A profile is a named list of `NAME=value` entries that are laid over the environment of every new shell: terminal tabs and the console under the panels. Shells that are already running keep their environment; a shell started after the file is saved sees the change.

```json
{
  "profiles": [
    { "name": "default", "vars": ["EDITOR=vim", "WORK=%TEMP%\\work", "OLD_VARIABLE="] },
    { "name": "proxy", "auto": false, "shells": ["pwsh"], "vars": ["HTTPS_PROXY=http://proxy:3128"] }
  ]
}
```

**Entries.** Profiles apply in the order of the file and entries in the order of the list, so a later entry sees the result of an earlier one. An entry with an empty value (`OLD_VARIABLE=`) removes the variable. `%NAME%` is replaced by the current value of the variable on every system; on Linux and macOS `$NAME` and `${NAME}` work too. A name that is not set stays as written. On Windows names are compared without regard to case.

**Which profiles apply to a shell**
- `default` – applies to every shell, first.
- `auto` (on by default) – the profile applies by itself. With `"auto": false` it applies only to a shell that names it (see below).
- `shells` – the shell profiles the profile is meant for: `pwsh`, `wsl`, `wsl:Ubuntu`, the id of a copy such as `pwsh#2`. A bare `wsl` also covers `wsl:Ubuntu`, and a base id covers its copies. Empty or missing – every shell.
- `off` – `true` switches the profile off altogether, even where it is named.

<!--choice-->**Profile for one shell.** In the shell list (**Ctrl+Shift+N**) **F6** opens the choice of an environment profile for the selected shell or its copy. Such a shell starts with `default` and the chosen profile; `(none)` goes back to the automatic profiles. Only profiles that are not off and are not `default` are listed.

The file is part of **Export settings / Import settings**.

---

[Contents](index.md)
