# Modern Terminal Navigator 2 (MTN2)

[English](README.en.md) | **Deutsch** | [Русский](README.md) | [中文](README.zh.md) | [한국어](README.ko.md)

Zweipanel-Dateimanager im Geiste von **Necromancer's DOS Navigator** und **Far Manager** mit integrierter Konsole,
Terminals, Datei-Viewer und Editor. Die Benutzeroberfläche ist textbasiert (TUI), wird jedoch in einem regulären GUI-Fenster gerendert:
ein virtuelles Zeichenraster auf einem Delphi-FireMonkey-Canvas (Skia, mit Fallback auf Standard-Canvas über `--no-skia`)
mit TrueType-Schriftarten, Unicode und 32-Bit-Farben. Chinesische, japanische und koreanische (CJK) Schriftzeichen
nehmen zwei Spalten ein, genau wie in anderen modernen Terminals.

[![CI](https://github.com/Laex/MTN2/actions/workflows/ci.yml/badge.svg)](https://github.com/Laex/MTN2/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

![MTN2: zwei Panels und Über-Dialog](docs/images/mtn2-about.png)

Neuerungen in den Versionen – siehe [CHANGELOG.md](CHANGELOG.md).

## Funktionen

- **Panels:** zwei Panels mit Tabs, Brief-/Full-/Spaltenmodi, Sortierung, Schnellsuche und Live-Filter,
  Maskenauswahl, Verzeichnisvergleich, Verlauf und Ordner-Hotlist (Favoriten), lange Pfade (> MAX_PATH).
- **Dateioperationen:** Kopieren, Verschieben und Löschen über Hintergrundaufträge mit Fortschrittsanzeige, Dateiattribute und Zeitstempel,
  Verknüpfungen/Links, Papierkorb, Prüfsummen, Verzeichnissynchronisierung.
- **Konsole und Terminals:** Befehlszeile unter den Panels, echtes ConPTY (cmd, PowerShell, pwsh, Git Bash, WSL,
  SSH), ANSI/VT-Sequenz-Parsing, alternativer Bildschirmpuffer für TUI-Programme, Terminal-Arbeitsbereiche.
  Aus dem Panel oder der Befehlszeile gestartete Konsolenprogramme laufen in der integrierten Konsole, und ihre Ausgabe
  bleibt auf dem Bildschirm erhalten (`Ctrl+O`).
- **Anzeigen und Bearbeiten:** integrierter Viewer (Text, Hex, Streaming großer Dateien), Editor,
  Quick View (`Ctrl+Q`), Markdown-Vorschau, externer Viewer/Editor.
- **Virtuelle Dateisysteme:** Archive als Ordner (zip, 7z über `7z.dll`), SFTP über SSH, Plugin-VFS.
- **Anpassung:** anpassbare Tastenbelegung (`keymap.json`), dateibasierte Themes (Far Classic, Total Commander, Dracula, Nord, Solarized, High Contrast usw.; eigene Themes im Theme-Editor),
  Benutzermenü (F2), Dateizuordnungen, kontextbezogene F1-Hilfe.
- **Sprachen:** Oberfläche und Hilfe auf Deutsch, Englisch und Russisch; Sprache wird unter **Optionen → Schrift / Anzeige...**
  ausgewählt und ohne Neustart angewendet. Eigene Sprachen können über eine Datei `strings\<sprache>.json` neben `MTN2.exe` hinzugefügt werden.
- **Unicode:** CJK-Schriftzeichen (BMP), Hiragana, Katakana, Hangeul und vollbreite Zeichen
  werden in Konsole, Panels, Tabs und Titeln zweispaltig dargestellt; fehlende Glyphen werden aus Systemschriftarten ergänzt.
- **Plugins:** native DLLs und WebAssembly (über Wasmtime) – eigene VFS-Schemata und Panels, Menüeinträge,
  Tastenbelegungen, Nachrichtenbus. Protokolle für Dialoge, Overlays und Statuszeilen sind spezifiziert,
  aktuell jedoch dem Hauptprogramm vorbehalten – siehe [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md).
- **Updates:** tägliche Prüfung auf neue GitHub-Releases; Download (mit SHA-256-Prüfung), Installation
  und Neustart erfolgen erst nach Bestätigung durch den Benutzer. Menü **≡ → Nach Updates suchen...**.

Derzeit wird Windows x64 unterstützt; POSIX PTY und Builds für macOS/Linux sind in Planung.

## Installation

Fertige Builds stehen auf der [Releases](https://github.com/Laex/MTN2/releases)-Seite bereit:

- `MTN2-<version>-win64.zip` – Einstellungen und Verlauf werden in `%APPDATA%\MTN2` gespeichert;
- `MTN2-<version>-win64-portable.zip` – portable Version: alles wird direkt neben `MTN2.exe` abgelegt.

Das Archiv einfach in einen beliebigen Ordner entpacken und `MTN2.exe` starten. Danach aktualisiert sich das Programm selbst
(Menü **≡ → Nach Updates suchen...**). Das Paket enthält `7z.dll` aus [7-Zip](https://www.7-zip.org) (GNU LGPL; Lizenztexte in
`plugins\mtn.7z\license.txt`, Details in [THIRD-PARTY.md](THIRD-PARTY.md)): damit lassen sich 7z- und andere
7-Zip-Archive öffnen. Sie kann durch eine eigene x64-Version in `plugins\mtn.7z\` ersetzt werden; zip lässt sich auch ohne sie öffnen.

### Dev-Builds

Entwickler-Builds (dev) werden nach jedem Commit auf `main` in einem separaten Repository veröffentlicht:
[Laex/MTN2-dev](https://github.com/Laex/MTN2-dev/releases). Um sie automatisch zu beziehen, öffnen Sie
**≡ → Nach Updates suchen...** und aktivieren Sie den Dev-Kanal; Sie können jederzeit wieder auf stabile Releases zurückkehren.
Dev-Builds enthalten die neuesten Änderungen und sind möglicherweise weniger stabil.

## Kompilieren

Erforderlich sind RAD Studio 13 (Delphi, `Studio\37.0`) und Windows x64; für das WASM-Plugin `mtn.ws` wird Rust benötigt.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # bin\MTN2.exe + bin\plugins\
./src/tests/run-tests.ps1                          # DUnitX-Regressionstests
```

Start: `bin\MTN2.exe [--no-skia] [--fps] [pfad]`. Details unter [docs/BUILDING.md](docs/BUILDING.md).

## Repository-Struktur

| Pfad | Inhalt |
|---|---|
| `src/Core` | Kern: Panels, VFS, ConPTY, Konsole, Editor, Dialoge, Plugin-Host |
| `src/Forms`, `src/dialogs`, `src/strings`, `src/Assets/themes` | Hauptformular, JSON-Dialoge, Lokalisierung, integrierte Themes |
| `src/plugins` | Integrierte Plugins (`mtn.7z`, `mtn.tmp`, `mtn.ws`, WASM-Demo) |
| `src/tests` | DUnitX-Regressionstests nach Gruppen und Test-Runner `run-tests.ps1` |
| `src/tools` | DialogDesigner, ExportDialogJson, Projektgruppe `Group.groupproj`, Hilfsskripte |
| `bin/help` | F1-Hilfe (en/ru/de), wird zusammen mit dem Programm ausgeliefert |
| `docs` | Entwicklerdokumentation, Screenshots (`docs/images`) |

## Dokumentation

- [SDS.md](docs/SDS.md) – Vollständige Spezifikation: Konzept, Datenstrukturen, APIs, Roadmap.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) – Schichten, Datenflüsse und Invarianten.
- [BUILDING.md](docs/BUILDING.md) – Bauen, Tests, CI/CD.
- [THEMES.md](docs/THEMES.md) – Theme-Dateiformat und Farbrollen.
- [HELP.md](docs/HELP.md) – Vollständiger Text der Benutzerhilfe in einer Datei.
- Plugin-Schnittstellen: [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md), [PANEL](docs/PANEL_PLUGIN.md),
  [DIALOG](docs/DIALOG_PLUGIN.md), [INPUT](docs/INPUT_PLUGIN.md), [OVERLAY](docs/OVERLAY_PLUGIN.md),
  [STATUS](docs/STATUS_PLUGIN.md), [TEXTAREA](docs/TEXTAREA_PLUGIN.md), [TOOLBAR](docs/TOOLBAR_PLUGIN.md),
  [UI_PRIMITIVES](docs/UI_PRIMITIVES.md).

## Wie das Projekt entstanden ist

Bei der Entwicklung von MTN2 wurden KI-Assistenten eingesetzt, darunter auch eigene Entwicklungen. Mit ihrer Hilfe entstanden:

- Vorprojektdokumentation – Spezifikation ([SDS.md](docs/SDS.md)), Architekturübersicht, Plugin-Protokollbeschreibungen in `docs/`;
- Nachverfolgung der Roadmap und Arbeitspläne;
- die meisten Codekommentare;
- DUnitX-Regressionstests (`src/tests`);
- textuelle Benutzerdokumentation: F1-Hilfe (`bin/help`), [CHANGELOG.md](CHANGELOG.md), Versionshinweise.

## Lizenz

[Mozilla Public License 2.0](LICENSE).
