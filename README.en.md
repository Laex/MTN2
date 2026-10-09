# Modern Terminal Navigator 2 (MTN2)

**English** | [Deutsch](README.de.md) | [Русский](README.md) | [中文](README.zh.md) | [한국어](README.ko.md)

A dual-panel file manager inspired by **Necromancer's DOS Navigator** and **Far Manager**, featuring a built-in console,
terminals, file viewer, and editor. The user interface is text-based (TUI), but rendered inside a standard GUI window:
a virtual character grid on a Delphi FireMonkey canvas (Skia-rendered, with fallback to standard canvas via `--no-skia`)
with TrueType fonts, Unicode, and 32-bit color. Chinese, Japanese, and Korean (CJK) characters
occupy two columns, matching standard terminal behavior.

[![CI](https://github.com/Laex/MTN2/actions/workflows/ci.yml/badge.svg)](https://github.com/Laex/MTN2/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

![MTN2: dual panels and About dialog](docs/images/mtn2-about.png)

What's new in each version – [CHANGELOG.md](CHANGELOG.md).

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

Currently supports Windows x64; POSIX PTY and macOS/Linux builds are planned.

## Installation

Pre-built binaries are available on the [Releases](https://github.com/Laex/MTN2/releases) page:

- `MTN2-<version>-win64.zip` – settings and history are stored in `%APPDATA%\MTN2`;
- `MTN2-<version>-win64-portable.zip` – portable edition: everything is stored next to `MTN2.exe`.

Simply extract the archive into any folder and run `MTN2.exe`. The application can then update itself
(menu **≡ → Check for updates...**). The release includes `7z.dll` from [7-Zip](https://www.7-zip.org) (GNU LGPL; license text in
`plugins\mtn.7z\license.txt`, details in [THIRD-PARTY.md](THIRD-PARTY.md)) enabling support for 7z and other
7-Zip formats. You may replace it with your own x64 version in `plugins\mtn.7z\`; zip archives open without it.

### Dev Builds

Pre-release (dev) builds are published after every commit to `main` in a dedicated repository:
[Laex/MTN2-dev](https://github.com/Laex/MTN2-dev/releases). To receive them automatically, open
**≡ → Check for updates...** and check the dev channel box; you can uncheck it at any time to return to stable releases.
Dev builds contain the latest changes and may be less stable.

## Building

Requires RAD Studio 13 (Delphi, `Studio\37.0`) and Windows x64; the `mtn.ws` WASM plugin requires Rust.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # bin\MTN2.exe + bin\plugins\
./src/tests/run-tests.ps1                          # DUnitX regression tests
```

Run: `bin\MTN2.exe [--no-skia] [--fps] [path]`. Details in [docs/BUILDING.md](docs/BUILDING.md).

## Repository Structure

| Path | Contents |
|---|---|
| `src/Core` | Core engine: panels, VFS, ConPTY, console, editor, dialogs, plugin host |
| `src/Forms`, `src/dialogs`, `src/strings`, `src/Assets/themes` | Main form, JSON dialogs, localization, built-in themes |
| `src/plugins` | Built-in plugins (`mtn.7z`, `mtn.tmp`, `mtn.ws`, WASM demo) |
| `src/tests` | DUnitX regression tests by group and test runner `run-tests.ps1` |
| `src/tools` | DialogDesigner, ExportDialogJson, `Group.groupproj` project group, utility scripts |
| `bin/help` | F1 help files (en/ru/de), bundled with the application |
| `docs` | Developer documentation, screenshots (`docs/images`) |

## Documentation

- [SDS.md](docs/SDS.md) – full specification: concept, data structures, API, roadmap.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) – layers, data flows, and invariants.
- [BUILDING.md](docs/BUILDING.md) – build guide, tests, CI/CD.
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
- User-facing text documentation: F1 help (`bin/help`), [CHANGELOG.md](CHANGELOG.md), and release notes.

## License

[Mozilla Public License 2.0](LICENSE).
