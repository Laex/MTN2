# Сборка и CI

## Локальная сборка

Требуется RAD Studio 13 (`Studio\37.0`), Windows x64. Опционально — Rust (`cargo`) для плагина `mtn.ws`.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # -> bin\MTN2.exe + bin\plugins\
./src/tests/run-tests.ps1                         # регрессионные тесты (DUnitX, dcc64)
./src/tools/package-release.ps1 -Version v0.3.0   # -> dist\MTN2-v0.3.0-win64.zip + -win64-portable.zip
./src/tools/check-release.ps1 -Version v0.3.0     # распаковать оба и прогнать MTN2.exe --self-check
```

Архивы отличаются только файлом `portable.dat` (настройки рядом с exe вместо `%APPDATA%\MTN2`).
Автообновление берёт ровно `MTN2-<тег>-win64.zip` и, распакованное поверх переносной копии, `portable.dat`
не трогает. `--self-check` проверяет встроенные ресурсы, `help\<язык>\` для каждого языка, `sk4d.dll` и
манифесты плагинов, печатает отчёт в stdout и выходит с кодом 0/1, не открывая окно.

`-Version 0.3.2` (или `v0.3.2`) прошивает номер в ресурс версии exe: его показывает заголовок окна и с ним
сравнивает автообновление. Без параметра берётся версия из `MTN2.dproj`; релизная сборка передаёт тег.

`wasmtime.dll` скачивается `src/tools/fetch-wasmtime.ps1`; `7z.dll` (x64) берётся из установленного 7-Zip
или из `MTN2_7Z_DLL` и в релизный архив не входит.

В IDE оба проекта (MTN2 и DialogDesigner) открываются группой `src/tools/Group.groupproj`.
Ресурсы `src/MTN2.dres` (диалоги, строки, клавиши, меню) в git не хранятся — их собирает `build.ps1`
(и `run-tests.ps1` для тестов); перед первой сборкой из IDE запустите `build.ps1` один раз.

Запуск: `bin\MTN2.exe [--no-skia] [--fps] [путь]`. Ключи (`--no-skia`, `--fps` — кадры и время кадра в заголовке, путь новой вкладкой, служебные `--wait-pid` и `--self-check`) — [ARCHITECTURE.md](ARCHITECTURE.md) §10.

## Тесты

Тесты написаны на [DUnitX](https://github.com/VSoftTechnologies/DUnitX) (входит в RAD Studio). Каждый
`src/tests/<группа>/TestXxx.pas` — модуль с фикстурой `[TestFixture] TTestXxx`, методы `[Test]` проверяют
через `Assert.*`. Фикстуры группы собирает консольный раннер `<Группа>Tests.dpr` (например,
`vfs/VfsTests.dpr`); общий `Main` — в `src/tests/common/uTestRunner.pas`. Группы:

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
./src/tests/run-tests.ps1                    # все группы, кроме фикстур категории Manual
./src/tests/run-tests.ps1 -Group vfs,panels  # выбранные группы
./src/tests/run-tests.ps1 -Test TestPty*     # фикстуры по имени модуля (маски), в т.ч. Manual
./src/tests/run-tests.ps1 -All               # вместе с Manual
./src/tests/run-tests.ps1 -List              # только показать список
```

`run-tests.ps1` компилирует раннер группы в `src/tests/dcu` и запускает его из папки группы (пути вида
`..\..\dialogs` в тестах отсчитываются от неё). Отчёт в формате NUnit XML пишется в
`src/tests/dcu/<Группа>Tests.xml`, CI сохраняет его артефактом. Раннер дольше `-TimeoutSec` (по умолчанию
900 с) снимается и считается упавшим; прогон не останавливается на первой ошибке и в конце печатает сводку.

Раннер группы можно запустить и напрямую (из папки группы) — ключи DUnitX: `-h` — справка,
`--run:TestToast.TTestToast` — одна фикстура, `--exclude:Manual`, `--xmlfile:<путь>`.

Новый тест: `src/tests/<группа>/TestXxx.pas` по образцу соседних (фикстура регистрируется в `initialization`
через `TDUnitX.RegisterTestFixture`), модули Core подключать без `in`-путей — их находит `-U` раннера.
Модуль нужно добавить в `uses` раннера группы; `run-tests.ps1` падает, если какой-то `Test*.pas` там не
указан. Ручные, интерактивные и зависящие от окружения фикстуры помечаются `[Category('Manual')]` с
комментарием-причиной над атрибутом. Нет нужного окружения (7z.dll, wasmtime.dll) — тест завершается
`Assert.Pass('SKIP: …')`.

Внутри методов фикстуры `Writeln(…)` разрешается в хелпер DUnitX `TObject.WriteLn(msg)` (один
строковый аргумент, пишет в лог раннера) — для обычного вывода в консоль пишите `System.Writeln`.

## CI/CD (GitHub Actions)

| Workflow | Где | Что |
|---|---|---|
| `ci.yml` → `checks` | GitHub-hosted (ubuntu) | gitleaks, валидность JSON-ресурсов |
| `ci.yml` → `wasm-plugin` | GitHub-hosted (ubuntu) | `cargo build` плагина `mtn.ws` под `wasm32` |
| `ci.yml` → `delphi` | self-hosted `delphi` | `build.ps1` + `run-tests.ps1` + zip-артефакт |
| `release.yml` | self-hosted `delphi` | по тегу `v*`: сборка, тесты, GitHub Release с zip и разделом из `CHANGELOG.md` |

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

### Что нового: `CHANGELOG.md`

`CHANGELOG.md` в корне — для пользователей: что появилось, что исправлено, что изменилось в поведении, по-русски и без
внутренней кухни (рефакторинг, тесты, CI туда не пишутся). Изменение, заметное пользователю, сразу записывается
в раздел «Не выпущено» под «Новое», «Исправлено» или «Изменено». Файл кладётся в оба архива рядом с `LICENSE`.

### Релиз

```powershell
./src/tools/changelog.ps1 -Stamp v0.3.0   # «Не выпущено» -> «v0.3.0 — <дата>», новый пустой «Не выпущено»
                                          # и версия 0.3.0 в MTN2.dproj; оба файла — в коммит «Stamp 0.3.0.»
git tag v0.3.0
git push origin v0.3.0
```

`release.yml` берёт раздел этой версии из `CHANGELOG.md` на теге и ставит его в начало страницы релиза со ссылкой
на весь файл; без такого раздела (не сделан `-Stamp`) релиз останавливается до сборки.

Версию в exe релиза задаёт тег (`build.ps1 -Version`), а локальная сборка без `-Version` берёт её из `MTN2.dproj`.
Если dproj не поднять, локальный exe считает себя старше на версию и встроенное обновление предлагает ему «обновиться»
до уже установленной версии (так было с 0.3.8). Поднять только dproj: `./src/tools/changelog.ps1 -ProjectVersion v0.3.0`.
