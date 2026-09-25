# Modern Terminal Navigator 2 (MTN2)

Двухпанельный файловый менеджер в духе **Necromancer's DOS Navigator** и **FAR Manager** со встроенной консолью,
терминалами, просмотрщиком и редактором. Интерфейс — текстовый (TUI), но рисуется в обычном GUI-окне:
виртуальная сетка символов на GPU-холсте Delphi FireMonkey с TrueType-шрифтами, Unicode и 32-битным цветом.

[![CI](https://github.com/Laex/MTN2/actions/workflows/ci.yml/badge.svg)](https://github.com/Laex/MTN2/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

## Возможности

- **Панели:** две панели с вкладками, Brief/Full/колоночные режимы, сортировка, быстрый поиск и живой фильтр,
  выделение по маске, сравнение каталогов, история и избранные папки, длинные пути (> MAX_PATH).
- **Операции с файлами:** копирование, перенос и удаление в фоновых заданиях с прогрессом, атрибуты и даты,
  ссылки, корзина, контрольные суммы, синхронизация каталогов.
- **Консоль и терминалы:** командная строка под панелями, настоящий ConPTY (cmd, PowerShell, pwsh, Git Bash, WSL,
  SSH), ANSI/VT-разбор, альтернативный экран для TUI-программ, рабочие пространства терминалов.
- **Просмотр и редактирование:** встроенные Viewer (текст, hex, потоковое чтение больших файлов), Editor,
  Quick View (`Ctrl+Q`), просмотр Markdown, внешние просмотрщик/редактор.
- **Виртуальные ФС:** архивы как папки (zip, 7z через `7z.dll`), SFTP по SSH, плагинные VFS.
- **Настройка:** переопределяемые клавиши (`keymap.json`), темы (NDN, Total Commander, Dracula, Nord, Solarized, High Contrast и др.),
  меню пользователя (F2), ассоциации файлов, контекстная справка F1 на русском и английском.
- **Плагины:** нативные DLL и WebAssembly (через Wasmtime) — панели, VFS, диалоги, оверлеи, строки состояния.

Сейчас поддерживается Windows x64; POSIX PTY и сборки под macOS/Linux — в планах.

## Сборка

Нужны RAD Studio 13 (Delphi, `Studio\37.0`) и Windows x64; для WASM-плагина `mtn.ws` — Rust.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # bin\MTN2.exe + bin\plugins\
./src/tests/run-tests.ps1                          # регрессионные тесты
```

Подробности — в [docs/BUILDING.md](docs/BUILDING.md).

## Структура репозитория

| Путь | Содержимое |
|---|---|
| `src/Core` | ядро: панели, VFS, ConPTY, консоль, редактор, диалоги, плагинный хост |
| `src/Forms`, `src/Themes`, `src/dialogs`, `src/strings` | главная форма, темы, JSON-диалоги, локализация |
| `src/plugins` | встроенные плагины (`mtn.7z`, `mtn.tmp`, `mtn.ws`, WASM-демо) |
| `src/tests` | регрессионные тесты по группам и раннер `run-tests.ps1` |
| `src/tools` | DialogDesigner, ExportDialogJson, группа проектов `Group.groupproj`, служебные скрипты |
| `bin/help` | справка F1 (ru/en), поставляется вместе с программой |
| `docs` | документация разработчика |

## Документация

- [SDS.md](docs/SDS.md) — полная спецификация: концепция, структуры данных, API, дорожная карта.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — слои, потоки данных и инварианты.
- [BUILDING.md](docs/BUILDING.md) — сборка, тесты, CI/CD.
- [DAILY_USE.md](docs/DAILY_USE.md) — аудит повседневных сценариев и план.
- [HELP.md](docs/HELP.md) — исходный текст справки пользователя одним файлом.
- Плагинные контракты: [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md), [PANEL](docs/PANEL_PLUGIN.md),
  [DIALOG](docs/DIALOG_PLUGIN.md), [INPUT](docs/INPUT_PLUGIN.md), [OVERLAY](docs/OVERLAY_PLUGIN.md),
  [STATUS](docs/STATUS_PLUGIN.md), [TEXTAREA](docs/TEXTAREA_PLUGIN.md), [TOOLBAR](docs/TOOLBAR_PLUGIN.md),
  [UI_PRIMITIVES](docs/UI_PRIMITIVES.md), [PLUGIN_TRANSITION](docs/PLUGIN_TRANSITION.md).

## Лицензия

[Mozilla Public License 2.0](LICENSE).
