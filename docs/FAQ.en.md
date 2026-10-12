# Frequently Asked Questions

## General

### Who is MTN2 for?

MTN2 is for people who are used to DOS Navigator and Far Manager and work from the keyboard: system and network
engineers, developers, and administrators. MTN2 does not replace Far Manager or compete with Total Commander. It is
another dual-panel manager with its own conventions: a GPU-rendered character grid, a real terminal in tabs, and
plugins.

### Why is the interface text-based while the window is graphical?

The entire screen is one character grid, as in DOS Navigator and Far Manager, so the position and overlap of elements
remain predictable. The grid is rendered in a regular window on a FireMonkey canvas (Skia), with TrueType fonts,
Unicode, 32-bit color, smooth scaling, and none of the limitations of the Windows console. For a true text terminal,
use `mtn2-tui` on Linux.

### Which operating systems are supported?

Windows x64 (the graphical application) and Linux x86-64: `mtn2-tui` for a text terminal and the experimental
`mtn2-sdl` graphical application using SDL2. See [LINUX.md](LINUX.md) for details. A macOS build is planned.

### What does the project name mean?

Modern Terminal Navigator 2 (MTN2). The Habr article incorrectly expands it as Modern Turbo Navigator.

### Which license does MTN2 use?

[Mozilla Public License 2.0](../LICENSE). The source code, documentation, and releases are open on GitHub.

## Installation and startup

### How do I install MTN2?

There is no installer. Download an archive from the [Releases](https://github.com/Laex/MTN2/releases/latest) page,
extract it to any folder, and run `MTN2.exe`. Two archives contain the same application:

- `MTN2-<version>-win64.zip` – settings are stored in `%APPDATA%\MTN2`;
- `MTN2-<version>-win64-portable.zip` – settings are stored next to `MTN2.exe` (useful for a USB drive or a folder
  you carry with you).

Portable mode is enabled by placing `portable.dat` next to `MTN2.exe`. The program does not write to the registry.

### Windows shows a SmartScreen warning or an antivirus complains. What should I do?

The executable files are not digitally signed yet, so SmartScreen may show “Windows protected your PC”: choose
**More info → Run anyway**. Programs built with Delphi can sometimes trigger false antivirus positives.

You can verify the archive with its SHA-256 checksum, shown next to the file on the release page. The built-in updater
also checks the SHA-256 of a downloaded archive. You can build the program yourself; see [BUILDING.md](BUILDING.md).

### Can I build MTN2 with Delphi 12.2?

RAD Studio 13 is required because its FireMonkey rendering system was changed. Ready-made builds are available on the
Releases page, so building it yourself is not needed for ordinary use. Build requirements are listed in
[BUILDING.md](BUILDING.md).

### Why is the archive so large?

The archive is about 23 MB. Most of the size comes from the Skia graphics engine (`sk4d.dll`) and the WebAssembly
runtime (`wasmtime.dll`) used by plugins; `MTN2.exe` itself is one executable without a virtual machine or garbage
collector.

## Network and privacy

### Why does the program access the internet at startup?

It checks for a new version: once a day at startup, it asks GitHub (`api.github.com`) for information about the latest
release. The program does not otherwise access the network on its own: there is no telemetry or cloud functionality.
Downloading and installing a new version starts only after you agree. SSH/SFTP connections are made only to hosts you
specify.

To disable the check, open **≡ → Check for updates...** and clear **Check for updates at startup**. The check
notification can be disabled there as well (**Show update check notification**). Afterwards, updates happen only when
you use **≡ → Check for updates...**.

### Where are the settings stored?

In `%APPDATA%\MTN2`, or next to `MTN2.exe` in portable mode. They are ordinary JSON files such as `session.json` and
`keymap.json`; themes are stored as separate files. You can edit and copy them between machines manually.

## Appearance

### The font looks blurry or is clipped at the bottom at 125% Windows scaling.

Glyph rasterization for fractional Windows scaling has been fixed. If the problem remains, update to the latest version
and open **Settings → Font / display...**: **Integer font size** and **Text contrast** make strokes clearer at 125%
and 150% scaling. If that does not help, attach a screenshot to an issue and include the font and scale.

### How do I change the colors? Is there a DN palette?

Open **Settings → Theme...**. Built-in themes include Far Classic, Total Commander, Dracula, Nord, Solarized, High
Contrast, and ASCII, and custom themes can be created in the theme editor or as a file. The format is documented in
[THEMES.md](THEMES.md). Button shadow style can be changed in **Settings → Font / display...**.

### How do I remap keys?

Use the key editor or edit the `keymap.json` file in the settings folder. The default layout is close to Far Manager.

## Features

### Does MTN2 include an editor and viewer?

Yes: a text and hex viewer, an editor, Quick View (`Ctrl+Q`), and a Markdown viewer with tables. The console and panels
are toggled with `Ctrl+O`, as in Far Manager.

### Does it support syntax highlighting, batch renaming, or keyboard macros?

Text highlighting can be provided by a plugin (the `mtn.demo.highlight` samples cover JSON and INI). The other features
are planned; progress is tracked in [Issues](https://github.com/Laex/MTN2/issues) and [Discussions](https://github.com/Laex/MTN2/discussions).

### Can I use Far Manager or Total Commander plugins?

Not yet. Bridges to Far and Total Commander plugins are still being designed. MTN2 plugins are native DLLs or WebAssembly;
see [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md) for details.

### Which terminals are supported?

The real terminal supports ConPTY, cmd, PowerShell, pwsh, Git Bash, WSL, and SSH. Full-screen terminal programs such
as `mc` use the alternate screen.

## Contributing

### How do I report a bug or suggest an idea?

- For a bug or incomplete behavior, open a [new issue](https://github.com/Laex/MTN2/issues/new/choose) with the
  version, Windows details, scaling, reproduction steps, and a screenshot.
- For a question, idea, or a theme or plugin to share, use [Discussions](https://github.com/Laex/MTN2/discussions).
- For a vulnerability, follow [SECURITY.md](../SECURITY.md).

See [CONTRIBUTING.en.md](../CONTRIBUTING.en.md) for build and contribution instructions.
