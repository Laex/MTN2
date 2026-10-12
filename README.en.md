# Modern Terminal Navigator 2 (MTN2)

**English** | [Deutsch](README.de.md) | [Русский](README.md) | [中文](README.zh.md) | [한국어](README.ko.md)

A dual-panel file manager inspired by **Necromancer's DOS Navigator** and **Far Manager**, featuring a built-in console,
terminals, file viewer, and editor. The user interface is text-based (TUI), but rendered inside a standard GUI window:
a virtual character grid on a Delphi FireMonkey canvas (Skia-rendered, with fallback to standard canvas via `--no-skia`)
with TrueType fonts, Unicode, and 32-bit color. Chinese, Japanese, and Korean (CJK) characters
occupy two columns, matching standard terminal behavior.

[![CI](https://github.com/Laex/MTN2/actions/workflows/ci.yml/badge.svg)](https://github.com/Laex/MTN2/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

![MTN2: panels with tabs](docs/images/mtn2-panels.png)

[Download the latest version](https://github.com/Laex/MTN2/releases/latest) ·
[What's new](CHANGELOG.md) · [FAQ](docs/FAQ.en.md) · [Contributing](CONTRIBUTING.en.md) ·
[Discussions](https://github.com/Laex/MTN2/discussions) ·
[Article on Habr (in Russian)](https://habr.com/ru/articles/1087174/)

MTN2 is made for people who grew up with DOS Navigator and Far Manager and work from the keyboard: system and network
engineers, developers, administrators. It does not replace Far Manager and does not compete with Total Commander;
it is one more two-panel manager with its own habits.

## Principles

- **No telemetry, no cloud features.** The only network access is a check for a new version on GitHub (once a day,
  at startup); turn it off in **≡ → Check for updates...** ("Check for updates at startup").
  Details in the [FAQ](docs/FAQ.en.md).
- **Portable.** One folder, no installer, no registry entries; the portable edition keeps its settings next to
  `MTN2.exe`, the regular one in `%APPDATA%\MTN2`. Settings, themes and key bindings are plain JSON files.
- **Keyboard first.** The key layout is close to Far Manager and fully remappable; tabs and terminals work as in ConEmu.
- **A real terminal.** The console runs on ConPTY (cmd, PowerShell, WSL, SSH), not an imitation.
- **Extensible.** Native and WebAssembly plugins: custom file systems, panels, commands, dialogs, text highlighting.

> The Habr article expands the name as Modern Turbo Navigator; the current name is **Modern Terminal Navigator**.

## Screenshots

| | |
|---|---|
| ![Two panels with tabs](docs/images/mtn2-panels.png) | ![An archive as a folder](docs/images/mtn2-archive.png) |
| Panels with tabs, Far Classic theme | An archive opens as a folder |
| ![Markdown viewer](docs/images/mtn2-markdown.png) | ![Editor with JSON highlighting](docs/images/mtn2-editor.png) |
| Markdown viewer with tables | Editor; highlighting comes from a plugin |
| ![Built-in console](docs/images/mtn2-console.png) | ![Dracula theme](docs/images/mtn2-dracula.png) |
| Built-in console (Ctrl+O) | Dracula theme |

## Features

- **Panels:** two tabbed panels, Brief/Full/column view modes, sorting, quick search and live filter,
  mask selection, directory comparison, history and folder hotlist (favorites), long paths (> MAX_PATH).
- **File operations:** copy, move, and delete via background jobs with progress reporting, attributes and timestamps,
  symlinks/hardlinks, Recycle Bin, checksums, directory synchronization.
- **Console and terminals:** command line under the panels, genuine ConPTY (cmd, PowerShell, pwsh, Git Bash, WSL,
  SSH), ANSI/VT escape sequence parsing, alternate screen buffer for TUI applications, terminal workspaces.
  Console applications launched from panels or the command line run in the integrated console, with their output
  retained on screen (`Ctrl+O`).
- **View and edit:** built-in Viewer (text, hex, streamed reading of large files), Editor,
  Quick View (`Ctrl+Q`), Markdown preview, external viewer/editor support.
- **Virtual file systems:** archives as folders (zip, 7z via `7z.dll`), SFTP over SSH, plugin VFS.
- **Customization:** remappable key bindings (`keymap.json`), file-based themes (Far Classic, Total Commander, Dracula, Nord, Solarized, High Contrast, etc.; custom themes via built-in theme editor),
  user menu (F2), file associations, F1 context help.
- **Languages:** UI and help available in English, Russian, and German; language is selected in **Options → Font / Display...**
  and applied on the fly without restarting. Custom languages can be added via `strings\<language>.json` placed next to `MTN2.exe`.
- **Unicode:** CJK ideographs (BMP), Hiragana, Katakana, Hangul, and full-width forms
  render across console, panels, tabs, and headers in two columns; missing glyphs fall back to system fonts.
- **Plugins:** native DLLs and WebAssembly (via Wasmtime) – custom VFS schemes and dedicated panels, menu items,
  key bindings, and message bus. Dialog, overlay, and status bar plugin protocols are specified,
  though currently reserved for internal use – see [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md).
- **Updates:** daily check for new GitHub releases; download (with SHA-256 verification), installation,
  and restart occur only after user confirmation. Menu **≡ → Check for updates...**.

Windows x64 (GUI application) and Linux x86-64 are supported: `mtn2-tui` runs in a full-screen text terminal,
featuring the same panels, viewer, editor, console, and plugins, and works over SSH and inside `tmux` (see [docs/LINUX.md](docs/LINUX.md)).
An experimental GUI version for Linux, `mtn2-sdl`, shows the same windows in a regular SDL2 window: system font,
mouse and wheel, input in any keyboard layout, desktop clipboard, pictures in Quick View. It runs on X11 and Wayland
(in Windows through WSLg), is included in the `tar.gz` and `.deb` packages and needs `libSDL2` and `libfreetype`
(`libSDL2_image` for PNG and JPEG): dependencies and options are described in [docs/LINUX.md](docs/LINUX.md)
(in Russian). A macOS build is planned.

## Installation

Pre-built binaries are available on the [Releases](https://github.com/Laex/MTN2/releases) page:

- `MTN2-<version>-win64.zip` – settings and history are stored in `%APPDATA%\MTN2`;
- `MTN2-<version>-win64-portable.zip` – portable edition: everything is stored next to `MTN2.exe`;
- `MTN2-<version>-linux-x64.tar.gz` and `MTN2-<version>-linux-x64.deb` – Linux version: `mtn2-tui` (inside a terminal
  window, works over SSH) and the experimental GUI `mtn2-sdl` (SDL2 window, needs `libSDL2` and `libfreetype`):
  installation, dependencies, and options in [docs/LINUX.md](docs/LINUX.md).

**Windows:** simply extract the archive into any folder and run `MTN2.exe`. The application can then update itself
(menu **≡ → Check for updates...**). The release includes `7z.dll` from [7-Zip](https://www.7-zip.org) (GNU LGPL; license text in
`plugins\mtn.7z\license.txt`, details in [THIRD-PARTY.md](THIRD-PARTY.md)) enabling support for 7z and other
7-Zip formats. You may replace it with your own x64 version in `plugins\mtn.7z\`; zip archives open without it.

**Linux:** `tar xzf MTN2-*-linux-x64.tar.gz && ./mtn2/install.sh` (use `sudo` for all users) or
`sudo apt install ./MTN2-*-linux-x64.deb`. Afterwards `mtn2` starts the terminal version and `mtn2-sdl` the SDL2 window.
The unpacked folder also runs without installing: `mtn2/mtn2-tui` and `mtn2/mtn2-sdl` start where they lie.

### Dev Builds

Pre-release (dev) builds are published after every commit to `main` in a dedicated repository:
[Laex/MTN2-dev](https://github.com/Laex/MTN2-dev/releases). To receive them automatically, open
**≡ → Check for updates...** and check the dev channel box; you can uncheck it at any time to return to stable releases.
Dev builds contain the latest changes and may be less stable.

## Building

Requires RAD Studio 13 (Delphi, `Studio\37.0`) and Windows x64; the `mtn.ws` WASM plugin requires Rust.
The Linux version is cross-compiled from Windows using the `dcclinux64` compiler, with tests run in WSL.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # bin\win64\MTN2.exe + bin\win64\plugins\
./src/tests/run-tests.ps1                          # regression tests (DUnitX)
./src/build-linux.ps1                              # bin\linux64\mtn2-tui
./src/tests/run-tests-linux.ps1                    # same tests in WSL
```

Run: `bin\win64\MTN2.exe [--no-skia] [--fps] [path]`. Details in [docs/BUILDING.md](docs/BUILDING.md).

## Repository Structure

| Path | Contents |
|---|---|
| `src/Core` | Core engine: panels, VFS, console, editor, dialogs, plugin host |
| `src/Platform` | Platform abstraction layer: `Windows` and `Posix` modules |
| `src/Hosts` | Shell hosts: `Ansi` – text terminal version |
| `src/Forms`, `src/dialogs`, `src/strings`, `src/Assets/themes` | Main form, JSON dialogs, localization, built-in themes |
| `src/plugins` | Built-in plugins (`mtn.7z`, `mtn.tmp`, `mtn.ws`, WASM demo) |
| `src/tests` | DUnitX regression tests by group and test runner `run-tests.ps1` |
| `src/tools` | DialogDesigner, ExportDialogJson, `Group.groupproj` project group, utility scripts |
| `bin/win64`, `bin/linux64` | Build output by platform |
| `bin/win64/help` | F1 help files (en/ru/de), bundled with the application |
| `docs` | Developer documentation, screenshots (`docs/images`) |

## Documentation

- [FAQ.en.md](docs/FAQ.en.md) – frequently asked questions: network and privacy, SmartScreen, display scaling, themes, plugins.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md) – how to report a bug, suggest an idea, build the project and send a change.
- [SDS.md](docs/SDS.md) – full specification: concept, data structures, API, roadmap.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) – layers, data flows, and invariants.
- [BUILDING.md](docs/BUILDING.md) – build guide, tests, CI/CD.
- [LINUX.md](docs/LINUX.md) – Linux terminal edition: installation, options, dependencies.
- [THEMES.md](docs/THEMES.md) – theme file format and color roles.
- [HELP.md](docs/HELP.md) – complete user guide in a single file.
- Plugin contracts: [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md), [PANEL](docs/PANEL_PLUGIN.md),
  [DIALOG](docs/DIALOG_PLUGIN.md), [INPUT](docs/INPUT_PLUGIN.md), [OVERLAY](docs/OVERLAY_PLUGIN.md),
  [STATUS](docs/STATUS_PLUGIN.md), [TEXTAREA](docs/TEXTAREA_PLUGIN.md), [TOOLBAR](docs/TOOLBAR_PLUGIN.md),
  [UI_PRIMITIVES](docs/UI_PRIMITIVES.md).

## How the Project Was Created

MTN2 was developed with the assistance of AI coding assistants, including in-house tooling. They helped create:

- Preliminary project documentation: specification ([SDS.md](docs/SDS.md)), architecture overview, plugin protocol specifications in `docs/`;
- Roadmap tracking and task planning;
- Most source code comments;
- DUnitX regression tests (`src/tests`);
- User-facing text documentation: F1 help (`bin/win64/help`), [CHANGELOG.md](CHANGELOG.md), and release notes.

## License

[Mozilla Public License 2.0](LICENSE).
