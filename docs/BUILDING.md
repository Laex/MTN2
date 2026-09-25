# Сборка и CI

## Локальная сборка

Требуется RAD Studio 13 (`Studio\37.0`), Windows x64. Опционально — Rust (`cargo`) для плагина `mtn.ws`.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # -> bin\MTN2.exe + bin\plugins\
./src/tests/run-tests.ps1                         # регрессионные тесты (dcc64)
./src/tools/package-release.ps1 -Version v0.3.0   # -> dist\MTN2-v0.3.0-win64.zip
```

`-Version 0.3.2` (или `v0.3.2`) прошивает номер в ресурс версии exe: его показывает заголовок окна и с ним
сравнивает автообновление. Без параметра берётся версия из `MTN2.dproj`; релизная сборка передаёт тег.

`wasmtime.dll` скачивается `src/tools/fetch-wasmtime.ps1`; `7z.dll` (x64) берётся из установленного 7-Zip
или из `MTN2_7Z_DLL` и в релизный архив не входит.

В IDE оба проекта (MTN2 и DialogDesigner) открываются группой `src/tools/Group.groupproj`.

Запуск: `bin\MTN2.exe [--no-skia] [путь]`. Ключи (`--no-skia`, путь новой вкладкой, служебный `--wait-pid`) — [ARCHITECTURE.md](ARCHITECTURE.md) §10.

## Тесты

Каждый тест — отдельная консольная программа `Test*.dpr` (без фреймворка): код выхода 0 — успех.
Тесты разложены по группам в `src/tests/<группа>/`:

| Группа | Что покрывает |
|---|---|
| `console` | ANSI-парсер, консольный буфер, ConPTY, cmd/PowerShell-сессии, профили оболочек |
| `panels` | двухпанельное окно: ввод, мышь, вкладки, меню, отрисовка, статус, модель панели |
| `editor` | редактор, просмотрщики, Quick View, Markdown |
| `dialogs` | JSON-диалоги, рендер, история ввода, отдельные диалоги |
| `vfs` | файловые операции, VFS, архивы, SFTP, диски, длинные пути |
| `plugins` | плагинный хост, загрузчик, 7z/tmp/WASM-плагины (`SamplePlugin.dpr` — фикстура) |
| `core` | конфигурация, keymap, шина сообщений, строки, справка |

```powershell
./src/tests/run-tests.ps1                    # все группы, кроме тестов из manual.txt
./src/tests/run-tests.ps1 -Group vfs,panels  # выбранные группы
./src/tests/run-tests.ps1 -Test TestPty*     # по имени (маски), в т.ч. из manual.txt
./src/tests/run-tests.ps1 -All               # вместе с manual.txt
./src/tests/run-tests.ps1 -List              # только показать список
```

Раннер компилирует тест в `src/tests/dcu` и запускает его из папки группы (пути вида `..\..\dialogs`
в тестах отсчитываются от неё). Тест дольше `-TimeoutSec` (по умолчанию 300 с) снимается и считается
упавшим; прогон не останавливается на первой ошибке и в конце печатает сводку.

Новый тест: `src/tests/<группа>/TestXxx.dpr`, модули подключать как `uX in '..\..\Core\uX.pas'` — раннер
подхватит его автоматически. Ручные, интерактивные и зависящие от окружения тесты перечислены в
`src/tests/manual.txt` с причиной.

## CI/CD (GitHub Actions)

| Workflow | Где | Что |
|---|---|---|
| `ci.yml` → `checks` | GitHub-hosted (ubuntu) | gitleaks, валидность JSON-ресурсов |
| `ci.yml` → `wasm-plugin` | GitHub-hosted (ubuntu) | `cargo build` плагина `mtn.ws` под `wasm32` |
| `ci.yml` → `delphi` | self-hosted `delphi` | `build.ps1` + `run-tests.ps1` + zip-артефакт |
| `release.yml` | self-hosted `delphi` | по тегу `v*`: сборка, тесты, GitHub Release с zip |

RAD Studio коммерческая и на GitHub-hosted раннерах отсутствует, поэтому Delphi-часть идёт на своей машине.

### Подключение self-hosted раннера

1. GitHub → *Settings → Actions → Runners → New self-hosted runner* (Windows x64), выполнить показанные команды
   на машине с RAD Studio. При `config.cmd` добавить метку: `--labels delphi`.
2. Запускать раннер **интерактивно** (`run.cmd`, автозапуск при входе), а не как службу: часть тестов (ConPTY,
   буфер обмена, FMX) требует пользовательского сеанса.
3. Нужны PowerShell 7 (`pwsh`), Git, опционально Rust с `wasm32-unknown-unknown`.
4. *Settings → Secrets and variables → Actions → Variables*: `DELPHI_RUNNER = true` — включает job `delphi`
   (без неё CI не будет висеть в очереди в ожидании раннера).
5. *Settings → Actions → General → Fork pull request workflows*: «Require approval for all outside collaborators».
   Job `delphi` и так не запускается для PR из форков.

### Релиз

```powershell
git tag v0.3.0
git push origin v0.3.0
```
