# План перехода на родную плагинную систему

> **Роль:** операционный план «Родные плагины: Plugin Manager + DLL/SO» (родные DLL/SO) и «WASM Host для родных плагинов» (WASM host).  
> **Контракты примитивов:** [UI_PRIMITIVES.md](UI_PRIMITIVES.md).  
> **Слои и инварианты:** [ARCHITECTURE.md](ARCHITECTURE.md) §6.  
> **Продуктовый порядок:** SDS §6.0 – родные плагины → WASM → Far → Total Commander.

**Цель этого прохода:** родной VFS-плагин `mtn.7z` на `7z.dll` (не Far ArcLite): листинг, чтение и F5 extract незашифрованных `.7z` по схеме `7z://`. Dual Panel и Viewer остаются в exe.

---

## 1. Принцип

Не резать `TDualPanelWindow`. Панель, Viewer, Overlay, тема остаются Host. Плагин на «Родные плагины: Plugin Manager + DLL/SO» – **поставщик данных и команд**:

```text
DLL  ──cdecl──►  THostApiTable (uPluginHostAbi)
                     │
                     ├─ RegisterVfsScheme  → IVfsRegistry (plugin-owned)
                     ├─ RegisterPanelPlugin → IPanelPluginRegistry
                     ├─ RegisterMenuItem    → IMenuRegistry
                     ├─ RegisterKeyBinding  → IKeymapRegistry (rebind only)
                     ├─ HostPublish         → IMessageBus
                     └─ HostInvalidate      → Dual Panel / windows
                              │
TFilePanelModel  ──Pull──►  IVirtualFileSystem  (CreateDefaultVfs)
```

Вынос самой панели в DLL – отдельный шаг, cdecl Pull (`get_row_json` / `handle_event`), не этот коммит.

---

## 2. Шаги перехода

| Шаг | Что | Критерий готовности | Статус |
|---|---|---|---|
| **Швы Host** | Unregister VFS/panel, Copy/Move на plugin-owned backend, `plugin.json`, фасад `uPluginHost`, Dual Panel регистрирует `mtn_host_invalidate` | UnloadAll не оставляет cdecl; F5 на `sample://`→`sample://` зовёт плагин | сделано |
| **Demo VFS DLL** | Родной `mtn.7z` (`7z://`, list/exists/read через локальный `7z.dll`). ZIP остаётся in-process. Pack в `.7z` – «Pack в `7z://`». | Ядро стартует без DLL; Enter на `.7z` монтирует схему с диска | сделано |
| **Invalidate + PluginId** | `IPanelModel.PluginId`; HostInvalidate реально перерисовывает | Плагин зовёт invalidate – панель dirty | сделано (`panel.reload` / `mtn_host_invalidate`) |
| **Cdecl Pull-адаптер** | Рядом с `TFilePanelModel`, Dual Panel не режется | Smoke list/navigate на DLL-панели | строки панели плагина идут через VFS (`ListDirectory`), реакция на Enter – `RegisterPanelActivate` (§3.12); полный `get_row_json` / `handle_event` позже |
| **Copy bridge** | Cross-scheme plugin→file через ReadBytes + запись на диск; file→`7z://` через plugin `CopyItem` | F5 из `7z://` на диск; Pack/F5 в открытый `.7z` | сделано |
| **Overlay / textarea / dialog cdecl** | Только если появится второй потребитель примитива | SDS «Родные плагины: Plugin Manager + DLL/SO» не требует | диалог: сделано (`ShowDialog`, §3.12); подпись команды и сегмент статуса: сделано; overlay и text area: отложено |
| **WASM** | «WASM Host для родных плагинов» | Wasmtime + demo `wasmdemo://`; ловушка/OOB/WASI не валят ядро | сделано |
| **Far / TC** | «Far API Wrapper» – «Total Commander plugin bridge» | После стабильного родного API + WASM | отложено |

---

## 3. Правила швов

1. **Plugin-owned URI.** Схема, зарегистрированная через `RegisterPluginScheme`, принадлежит плагину. `file` / `zip` / `find` / `sys` / `recycle` / `ws` – ядро, Copy/Move как раньше. Эти пять схем зарезервированы (`IsReservedVfsScheme`): WASM `register_vfs_scheme` для них хост принимает и игнорирует, нативный `RegisterVfsScheme` возвращает отказ, сам реестр такую регистрацию не принимает.
2. **Same-backend transfer.** Copy/Move, где оба URI plugin-owned и резолвятся в один backend, идут в этот backend. Copy plugin→`file://` идёт хостовым extract-мостом (`vtrPluginExtract`: ReadBytes плагина → запись на диск). Остальной cross-scheme (plugin→zip, move plugin↔file) – `vecNotSupported`.
3. **Unload.** `UnloadAll` снимает keymap, menu, VFS plugin-owned записи и panel-plugin записи **до** `FreeLibrary`.
4. **Манифест.** `plugins\<id>\plugin.json` опционален. Если `abi` ≠ `cPluginAbiVersion` – DLL не грузится. Без файла – грузим как сейчас.
5. **Canvas.** Плагину не отдаётся. Overlay остаётся Host-only.
6. **Новые keymap-действия** не вводим через DLL: enum закрыт. Меню – новые пункты с cdecl callback.
7. **Замена встроенного обработчика.** Реестр сортирует обработчики по приоритету (меньше – раньше). Плагин без разрешения получает приоритет не ниже `cPluginMinPriority` (60), поэтому не обгоняет встроенные `find`, `sys`, `recycle`, `ws`, `sftp` (10–15), `!/`-цепочку zip (20) и расширения `.zip`/`.jar`/`.apk` (50). Заменить схему (`sftp`) или расширение (`.zip`) можно так: плагин перечисляет ключи в `overrides` манифеста, пользователь вносит его id в `plugins\overrides.json` (`{"allow": ["id"]}`). Разрешённый плагин получает приоритет не выше `cOverridePriority` (5) и загружается сразу при `CatalogPlugins`, потому что ленивая загрузка по схеме или расширению не срабатывает, пока встроенный обработчик отвечает на тот же URI. Разрешение живёт, пока плагин загружен: `UnregisterPlugin` снимает его вместе с записями, и встроенный обработчик возвращается. Замена расширения `.zip` меняет только переход по Enter (`<схема>:///<путь>!/`); `file:///x.zip!/` по-прежнему обслуживает встроенный zip.
8. **Архивное расширение плагина** ведёт в первую схему из `schemes` манифеста (`7z` по умолчанию).
9. **Команды.** `uCommandRegistry` (ABI 2: `RegisterCommand`, `RegisterCommandHook`, `ExecuteCommand`; WASM: `register_command`, `register_command_hook`, `execute_command`). Встроенная команда называется как действие раскладки (`Copy`, `View`, `Delete`, ...). Перехватчик (`RegisterCommandHook`) вызывается до встроенного обработчика: при нажатии клавиши на панелях (`DispatchPanelFreeInput`), для глобальных клавиш (`HandleInput`) и из верхнего меню (`DispatchTopMenuAction`; «Calculate size» не считается командой View). Он получает имя команды и источник (`key` / `menu`) и возвращает 1, если команду выполнил сам. Перехватчики идут по возрастанию приоритета, первый принявший команду завершает цепочку; исключение в перехватчике считается отказом; повторный вход в ту же команду из своего перехватчика не вызывает его снова. Команда плагина (`RegisterCommand`) получает id, не совпадающий с именем встроенной; сочетание клавиш к ней задаётся тем же `RegisterKeyBinding`, где вместо действия указан id команды, и действует, только если встроенное действие это сочетание не занимает. Плагины, чья работа сводится к перехватчикам и сочетаниям клавиш, указывают в `plugin.json` `"startup": true`, иначе ленивая загрузка их не запустит. Команды просмотрщика и редактора (`kaDoc*`, `kaEditor*`) перехватываются в `DispatchEditorKeysWith` тем же способом, сочетания клавиш плагина там тоже работают.
10. **Версии ABI.** Таблица `THostApiTable` только растёт в конце; хост грузит плагины с ABI от `cPluginMinAbiVersion` (1) до `cPluginAbiVersion` (2), плагин версии 1 видит префикс таблицы и работает как раньше.
11. **Открытие файлов.** `uDocumentProviders` (ABI 2: `RegisterDocumentProvider`, `OpenExternal`; WASM: `register_document_provider`). Все открытия просмотрщика и редактора идут через `TDualPanelWindow.OpenDocument`; он спрашивает провайдеров, подходящих по расширению и режиму (view / edit), по возрастанию приоритета. Ответ `dokPass` – не мой, `dokHandled` – плагин открыл файл сам, `dokRedirect` – встроенное окно открывает URI, названный плагином (цель редиректа провайдерам повторно не предлагается). Исключение в провайдере считается `dokPass`. Canvas плагину не отдаётся: окно остаётся хостовым. Из WASM доступен только `dokPass` / `dokHandled`: редирект и `OpenExternal` (запуск программы через систему) только у нативных плагинов, иначе гость мог бы запускать программы. Быстрый просмотр (Ctrl+Q) и справка провайдеров не спрашивают.
12. **Диалоги, строки панели, подписи и статус.** Диалог плагина (`uPluginUi`: ABI `ShowDialog`, WASM `show_dialog`) – тот же JSON, что у встроенных диалогов (DIALOG_PLUGIN.md); хост показывает его через `TDualPanelWindow.ShowHostDialog` только поверх панелей, диалог одноразовый, ответ (id контрола и values JSON) не доходит до выгруженного плагина. Активация строки (`RegisterPanelActivate`, WASM `register_panel_activate`): `TDualPanelWindow` до своей обработки Enter спрашивает обработчики схемы URI панели (не для строки `..`); исключение в обработчике – отказ. Подпись команды (`SetCommandCaption`, WASM `set_command_caption`) показывается в нижней строке клавиш (`FunctionBarItemsForPanels`), если сочетание команды лежит на F1–F10 с текущими модификаторами и слот свободен (подписи встроенных действий не вытесняются). Сегмент статуса (`SetStatusSegment`, WASM `set_status_segment`, `uPluginChrome`) добавляется после собственных сегментов строки состояния панелей, текст – одна строка до 40 символов, цвета задаёт тема. В WASM значения диалога длиннее 2 КиБ приходят гостю пустыми.

---

## 4. Что сознательно не трогаем

- Вынос Dual Panel / Editor / Theme в DLL.
- `TVfsCallbacksCdecl` progress/cancel/PreserveTimestamps (ABI v1). Retry `verNeedsBiggerBuffer`.
- POSIX `.so` / манифест как обязательный файл.
- Far/TC мосты.
- Оборачивать ArcLite / Far ABI. Движок – свой `7z.dll` рядом с плагином (LGPL, не коммитить).

---

## 5. Проверка швов

- `TestVfsRegistry` – classify + unregister + plugin-owned Copy route. `7z://` без плагина → `vtrNotSupported` (не zip-ядро). plugin→file при живом плагине → `vtrPluginExtract`.
- `TestPanelPluginRegistry` – UnregisterPlugin.
- `TestPluginManifest` – разбор `plugin.json`.
- `TestPluginLoader` – после UnloadAll `sample://` больше не plugin-owned; helper DLL без `mtn_plugin_*` (`7z.dll`) – skip, не fail.
- `TestSevenZipUri` – грамматика `7z:///<abs>!/<inner>`.
- `TestSevenZipPlugin` – list/read/F5 extract через загруженный `SevenZipPlugin.dll` + `7z.dll` (skip, если `7z.dll` нет).
- `TestWasmHost` – Pull `wasmdemo://` через Wasmtime; trap / WASI / OOB не валят процесс (skip, если `wasmtime.dll` нет).
- `TestWorkspacePlugin` – встроенная панель `ws:///` собирает **ссылки** (не копии) на файлы и каталоги; F8 снимает ссылку, оригинал на диске остаётся. WASM `mtn.ws` не обязан быть загружен (схема в ядре).
- `TestWorkspaceLibrary` – save / restore / rename / delete именованных снимков (`workspaces.json`).
- `src/tests/run-tests.ps1` зелёный.

---

## 6. `mtn.7z`

Раскладка: `<exe>\plugins\mtn.7z\SevenZipPlugin.dll` + `plugin.json` + `7z.dll` (LGPL, подкладывается при сборке или вручную).

URI: `7z:///<abs-path>!/<inner>` (пустой inner = корень архива). Enter на `.7z` / `.rar` / `.tar` / `.gz` / `.iso` / … (не `.zip`) переводит на этот корень. Ядро больше не отдаёт любой `!/` в ZIP – только `file://` + `.zip`/`.jar`/`.apk`.

ABI v1: list / exists / read. F5 extract на диск делает хост (`vtrPluginExtract`). Pack в `7z://` (файл/дерево → `.7z`) – `CopyItem` через `SevenZipAddLocalPath` / `IOutArchive.UpdateItems`; только формат `.7z` (не RAR/TAR). Move/Delete/WriteText по-прежнему `verNotSupported`. Пароль → `verAccessDenied` + диалог хоста. Нет `7z.dll` → init −2, ядро живёт без схемы.

---

## 7. WASM и ядерные схемы

`ws:///` – встроенный VFS (`uWorkspaceVfs.pas`), не модуль `mtn.ws`. WASM в `src/plugins/mtn.ws` только регистрирует меню (**Commands → Workspace** / **Clear workspace**), если есть `wasmtime.dll`. Справка по панели ссылок и библиотеке снимков: `src/plugins/mtn.ws/readme.md`.
