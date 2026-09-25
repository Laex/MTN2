# План перехода на родную плагинную систему

> **Роль:** операционный план этапа 29 (родные DLL/SO) и этапа 30 (WASM host).  
> **Контракты примитивов:** [UI_PRIMITIVES.md](UI_PRIMITIVES.md).  
> **Слои и инварианты:** [ARCHITECTURE.md](ARCHITECTURE.md) §6.  
> **Продуктовый порядок:** SDS §6.0 — родные плагины → WASM → Far → Total Commander.

**Цель этого прохода:** родной VFS-плагин `mtn.7z` на `7z.dll` (не Far ArcLite): листинг, чтение и F5 extract незашифрованных `.7z` по схеме `7z://`. Dual Panel и Viewer остаются в exe.

---

## 1. Принцип

Не резать `TDualPanelWindow`. Панель, Viewer, Overlay, тема остаются Host. Плагин на этапе 29 — **поставщик данных и команд**:

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

Вынос самой панели в DLL — фаза 5, отдельный cdecl Pull (`get_row_json` / `handle_event`), не этот коммит.

---

## 2. Фазы

| Фаза | Что | Критерий готовности | Статус |
|---|---|---|---|
| **0 — швы Host** | Unregister VFS/panel, Copy/Move на plugin-owned backend, `plugin.json`, фасад `uPluginHost`, Dual Panel регистрирует `mtn_host_invalidate` | UnloadAll не оставляет cdecl; F5 на `sample://`→`sample://` зовёт плагин | сделано |
| **1 — demo VFS DLL** | Родной `mtn.7z` (`7z://`, list/exists/read через локальный `7z.dll`). ZIP остаётся in-process. Pack в `.7z` — этап 49. | Ядро стартует без DLL; Enter на `.7z` монтирует схему с диска | сделано |
| **2 — invalidate + PluginId** | `IPanelModel.PluginId`; HostInvalidate реально перерисовывает | Плагин зовёт invalidate — панель dirty | сделано (`panel.reload` / `mtn_host_invalidate`) |
| **3 — cdecl Pull-адаптер** | Рядом с `TFilePanelModel`, Dual Panel не режется | Smoke list/navigate на DLL-панели | не начинать раньше 1–2 |
| **4 — copy bridge** | Cross-scheme plugin→file через ReadBytes + запись на диск; file→`7z://` через plugin `CopyItem` | F5 из `7z://` на диск; Pack/F5 в открытый `.7z` | сделано |
| **5 — overlay / textarea / dialog cdecl** | Только если появится второй потребитель примитива | SDS этап 29 не требует | отложено |
| **6 — WASM** | Этап 30 | Wasmtime + demo `wasmdemo://`; ловушка/OOB/WASI не валят ядро | сделано |
| **7 — Far / TC** | Этапы 31–32 | После стабильного родного API + WASM | отложено |

---

## 3. Правила швов (фаза 0)

1. **Plugin-owned URI.** Схема, зарегистрированная через `RegisterPluginScheme`, принадлежит плагину. `file` / `zip` / `find` / `sys` / `recycle` / `ws` — ядро, Copy/Move как раньше. WASM `register_vfs_scheme` для `file` / `recycle` / `sys` / `find` / `ws` хост принимает и игнорирует (схема остаётся ядерной).
2. **Same-backend transfer.** Copy/Move, где оба URI plugin-owned и резолвятся в один backend, идут в этот backend. Copy plugin→`file://` идёт хостовым extract-мостом (`vtrPluginExtract`: ReadBytes плагина → запись на диск). Остальной cross-scheme (plugin→zip, move plugin↔file) — `vecNotSupported`.
3. **Unload.** `UnloadAll` снимает keymap, menu, VFS plugin-owned записи и panel-plugin записи **до** `FreeLibrary`.
4. **Манифест.** `plugins\<id>\plugin.json` опционален. Если `abi` ≠ `cPluginAbiVersion` — DLL не грузится. Без файла — грузим как сейчас.
5. **Canvas.** Плагину не отдаётся. Overlay остаётся Host-only.
6. **Новые keymap-действия** не вводим через DLL: enum закрыт. Меню — новые пункты с cdecl callback.

---

## 4. Что сознательно не трогаем

- Вынос Dual Panel / Editor / Theme в DLL.
- `TVfsCallbacksCdecl` progress/cancel/PreserveTimestamps (ABI v1). Retry `verNeedsBiggerBuffer`.
- POSIX `.so` / манифест как обязательный файл.
- Far/TC мосты.
- Оборачивать ArcLite / Far ABI. Движок — свой `7z.dll` рядом с плагином (LGPL, не коммитить).

---

## 5. Проверка фазы 0

- `TestVfsRegistry` — classify + unregister + plugin-owned Copy route. `7z://` без плагина → `vtrNotSupported` (не zip-ядро). plugin→file при живом плагине → `vtrPluginExtract`.
- `TestPanelPluginRegistry` — UnregisterPlugin.
- `TestPluginManifest` — разбор `plugin.json`.
- `TestPluginLoader` — после UnloadAll `sample://` больше не plugin-owned; helper DLL без `mtn_plugin_*` (`7z.dll`) — skip, не fail.
- `TestSevenZipUri` — грамматика `7z:///<abs>!/<inner>`.
- `TestSevenZipPlugin` — list/read/F5 extract через загруженный `SevenZipPlugin.dll` + `7z.dll` (skip, если `7z.dll` нет).
- `TestWasmHost` — Pull `wasmdemo://` через Wasmtime; trap / WASI / OOB не валят процесс (skip, если `wasmtime.dll` нет).
- `TestWorkspacePlugin` — встроенная панель `ws:///` собирает **ссылки** (не копии) на файлы и каталоги; F8 снимает ссылку, оригинал на диске остаётся. WASM `mtn.ws` не обязан быть загружен (схема в ядре).
- `TestWorkspaceLibrary` — save / restore / rename / delete именованных снимков (`workspaces.json`).
- `run-panel-smoke.ps1` зелёный.

---

## 6. Фаза 1 — `mtn.7z`

Раскладка: `<exe>\plugins\mtn.7z\SevenZipPlugin.dll` + `plugin.json` + `7z.dll` (LGPL, подкладывается при сборке или вручную).

URI: `7z:///<abs-path>!/<inner>` (пустой inner = корень архива). Enter на `.7z` / `.rar` / `.tar` / `.gz` / `.iso` / … (не `.zip`) переводит на этот корень. Ядро больше не отдаёт любой `!/` в ZIP — только `file://` + `.zip`/`.jar`/`.apk`.

ABI v1: list / exists / read. F5 extract на диск делает хост (`vtrPluginExtract`). Pack в `7z://` (файл/дерево → `.7z`) – `CopyItem` через `SevenZipAddLocalPath` / `IOutArchive.UpdateItems`; только формат `.7z` (не RAR/TAR). Move/Delete/WriteText по-прежнему `verNotSupported`. Пароль → `verAccessDenied` + диалог хоста. Нет `7z.dll` → init −2, ядро живёт без схемы.

---

## 7. Фаза 6 — WASM и ядерные схемы

`ws:///` — встроенный VFS (`uWorkspaceVfs.pas`), не модуль `mtn.ws`. WASM в `src/plugins/mtn.ws` только регистрирует меню (**Commands → Workspace** / **Clear workspace**), если есть `wasmtime.dll`. Справка по панели ссылок и библиотеке снимков: `src/plugins/mtn.ws/readme.md`.
