## Updates

MTN2 can update itself: it finds a new version on GitHub, downloads and installs it, but only when the user agrees.

### How an update goes

A few seconds after startup, once a day, MTN2 checks GitHub for a new version. If there is one, it asks: **Update**, **Later** or **Skip this version** (a skipped version is not offered again). Nothing is downloaded or installed without an answer.

After the download (the package is checked against its SHA-256) MTN2 offers to **Restart** now or install **On exit**. While copy jobs are running, installation waits until exit. Only program files are replaced – settings, `7z.dll` and other user files stay as they are.

### Check settings

**≡ → Check for updates...** (F9, then the leftmost top-menu item) shows the installed version, checks right away (**Check now**) and has two checkboxes:

- **Check for updates at startup** – once a day at startup. With it off, MTN2 does not go online by itself.
- **Show a notice when checking** – every check that goes online (at startup or with **Check now**) shows a notice “Checking github.com for MTN2 updates...” in the bottom right corner for a few seconds. For the startup check it has a second line on how to turn the check off. It is shown even when other pop-up notices are off; while a dialog is open it stays hidden under it.

### What goes over the network

The check is a single HTTPS request to `api.github.com` for the latest release of the `Laex/MTN2` repository. It carries nothing but the MTN2 version in the `User-Agent` header – no file names, paths or settings. The update itself is the release package downloaded from GitHub after **Update**.

---

[Contents](index.md)
