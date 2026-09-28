# Settings

The **Options** menu (F9):

- **Theme...** — appearance; changes at once.
- **Font / Display...** — font, size, zoom, cursor blinking, file icons in the panel, pop-up notifications and the **interface language** (English / Русский); everything applies without a restart.
- **Columns...** — the columns of the “Custom” mode.
- **Color coding...** — row colors by name masks.
- **Keymap...** — view and change keys.
- **Plugins...** — installed plugins.
- **External viewer/editor...** — the Alt+F3 / Alt+F4 commands; `%1` is the file path (without `%1` the path is added at the end), e.g. `"C:\Program Files\Notepad++\notepad++.exe" %1`.
- **Zoom**: Ctrl+mouse wheel, **Ctrl+0** — reset.

## Notifications

Commands that change nothing on screen confirm themselves with a short notice in the bottom right corner; it disappears after a few seconds and does not take keys. Notices appear for:

- **Ctrl+Alt+Ins** / **Alt+Shift+Ins** — the path / name copied (or “Nothing to copy”);
- **Ctrl+C** / **Ctrl+X** (**Ctrl+Ins** / **Ctrl+Del**) on the panel — the files placed on the clipboard;
- copying text in the viewer / editor (without a selection — the current line), in the command line and in a terminal;
- **Ctrl+R** — the panel refreshed;
- **Ctrl+Shift+O** — the folder the console went to;
- **Ctrl+Alt+R** — the item restored from the Recycle Bin;
- **Ctrl+Alt+D** — the folder added to the hotlist;
- selection by mask (**Gray +/−**, **Ctrl+Gray +/−**, **Alt+Gray +/−**) that changed nothing — shown in red.

Notices are turned off in **Options → Font / Display...** (“Show pop-up notifications”). The update-check notice is the exception: it has its own checkbox (see “Updates” below).

## Updates

A few seconds after startup, once a day, MTN2 checks GitHub for a new version. If there is one, it asks: **Update**, **Later** or **Skip this version** (a skipped version is not offered again). Nothing is downloaded or installed without your answer.

After the download (the package is checked against its SHA-256) you choose **Restart** now or install **On exit**. While copy jobs are running, installation waits until exit. Only program files are replaced — settings, `7z.dll` and your other files stay as they are.

**≡ → Check for updates...** shows the installed version, turns the startup check on or off and checks right away.

When the startup check goes online, a notice “Checking github.com for MTN2 updates...” appears in the bottom right corner for a few seconds, with a hint on how to turn it off. It is shown even when other notices are off; the “Show a notice when checking” checkbox in the same dialog removes it.

The check is a single HTTPS request to `api.github.com` for the latest release of the `Laex/MTN2` repository. It carries nothing but the MTN2 version in the `User-Agent` header — no file names, paths or settings. With “Check for updates at startup” off, MTN2 does not go online by itself.

---

[Contents](index.md)
