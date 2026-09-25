# Разделение функциональности: Ядро / Системные плагины / Пользовательские плагины

> **Роль документа:** классификация существующей и планируемой функциональности MTN2 по трём зонам ответственности — что обязано остаться в ядре, что поставляется продуктом как «системный» плагин, что относится к экосистеме сторонних «пользовательских» плагинов.
> **Источники:** [ARCHITECTURE.md](ARCHITECTURE.md) §6 (паттерн Ядро–Тема–Плагин, инварианты 13–14), [PLUGIN_TRANSITION.md](PLUGIN_TRANSITION.md) (фазы 0–7), [readme.md](readme.md) §6.0/§6.8 (продуктовый приоритет и Far/TC мосты), [UI_PRIMITIVES.md](UI_PRIMITIVES.md) и связанные `*_PLUGIN.md`.
> Ничего нового не проектирует — сводит уже принятые решения в одну таблицу, чтобы разделение было видно целиком, а не по кускам в разных файлах.

---

## 1. Три зоны — определения

| Зона | Определение | Кто пишет | Где живёт код |
|---|---|---|---|
| **Ядро** | Функциональность, которая по инварианту 13 ARCHITECTURE.md обязана остаться в едином нативном exe — не выносится в плагины ни при каких обстоятельствах, независимо от того, сколько плагинов появится. | Только разработчик MTN2 | `src/Core`, `src/Forms`, `src/Themes` — компилируется в `MTN2.exe` |
| **Системные плагины** | Плагины «первой партии»: используют тот же родной ABI (`uPluginHostAbi`, `cPluginAbiVersion`), что и сторонние, но поставляются вместе с продуктом по умолчанию и реализуют функциональность, которую продукт обещает «из коробки» (архивы, workspace-панель…). | Разработчик MTN2 | `src/plugins/<id>/` — отдельные DLL/WASM рядом с exe (`plugins\<id>\*.dll`/`*.wasm`) |
| **Пользовательские плагины** | Та же экосистема ABI, но код и поставка — сторонние. Хост не различает системный и пользовательский плагин на уровне протокола — разница только в том, кто их написал и откуда они попали в `plugins\`. | Сторонние разработчики / пользователь | Вне репозитория; тот же контракт `plugins\<id>\*.dll`/`*.so`/`*.wasm` + опциональный `plugin.json` |

**Ключевой нюанс (инвариант 14, ARCHITECTURE.md):** деление «системный / пользовательский» — это вопрос **поставки**, не архитектуры. Протокол один и тот же (Host API, Pull, JSON, запрет `TCanvas`, async I/O). Настоящая архитектурная граница, которую видит хост — не «кто автор», а **уровень доверия/изоляции**:

| Форма поставки | Доступ к памяти процесса | Куда попадает сейчас |
|---|---|---|
| DLL/SO (родной ABI v1) | Полный (native, доверенный код) | `mtn.7z` (системный) |
| WASM (Wasmtime, без WASI) | Только копии UTF-8/JSON по смещениям в линейной памяти guest, песочница | `mtn.ws`, `mtn.tmp`, `mtn.wasm.demo` (системные) |
| Far/TC bridge (будущее) | Через отдельный ABI-мост поверх родного Plugin Manager | не реализовано (этапы 31–32) |

Системный и пользовательский плагин в DLL-форме одинаково доверенные (полный доступ к процессу) — «системность» тут не даёт дополнительных прав и не отбирает их.

---

## 2. Ядро — что не выносится никогда

Источник: ARCHITECTURE.md §6 (таблица ролей), инварианты 1–19 (§9), в первую очередь №13 «Ядро как артефакт» и №1 «Безопасность UI».

| Подсистема | Модули | Почему это ядро |
|---|---|---|
| Layout / Focus / Z-order / MDI-композитор | `uMdiCompositor`, `TDualPanelWindow`, `TMainForm` | Инвариант 13; «Не резать `TDualPanelWindow`» (PLUGIN_TRANSITION.md §1) |
| Рендеринг (double buffering, dynamic grid) | `uTerminalRenderer.pas`, `TTerminalGrid` | Плагину никогда не отдаётся `TCanvas` (общий инвариант всех примитивов, UI_PRIMITIVES.md) |
| Тема (`IThemeRenderer`) | `src/Themes/*.pas` (8 встроенных тем) | Роль «Тема» отдельна от «Плагина» в самом паттерне (§6); альтернативные темы — Pascal-классы, «не loadable-плагины — это отдельный, более поздний этап» (ARCHITECTURE.md §6) |
| Keymap-диспетчер и активный keymap | `uKeymap.pas` | Плагину доступен только rebind существующих действий через `IKeymapRegistry` — «Новые keymap-действия не вводим через DLL: enum закрыт» (PLUGIN_TRANSITION.md §3.6) |
| Jobs Manager / фоновые задачи | `uDualPanelJobList.pas`, `TPanelJobController` | Инвариант 1: весь I/O — только через async VFS/Jobs ядра |
| VFS Core & маршрутизация (`uVfsRegistry`) | `uVfsRegistry.pas` | Сам registry, классификация transfer-маршрутов, `plugin.json`-загрузка — ядро; отдельные VFS-**провайдеры** могут быть плагинами (см. §3) |
| Ядерные VFS-схемы: `file`, `zip`, `sys`, `recycle`, `find`, `ws` | `uFileVfs`, `uZipVirtualFileSystem`, `uSysFoldersVfs`, `uRecycleBinVfs`, `uFindVfs`, `uWorkspaceVfs` | Явно защищены от перехвата: «WASM `register_vfs_scheme` для `file`/`recycle`/`sys`/`find`/`ws` хост принимает и игнорирует» (PLUGIN_TRANSITION.md §3.1) |
| `sftp://` | `uSftpVfs.pas` | Сейчас in-process провайдер ядра, не вынесен в плагин (ARCHITECTURE.md §1) — кандидат на будущий системный плагин, см. §4 |
| Dialog Host (движок диалогов) | `uDialogHost.pas`, `uDialogTypes.pas`, `uDialogJson.pas` | Layout/focus/modal-overlay — Host; cdecl `mtn_dialog_*` для контента ещё не экспортирован (DIALOG_PLUGIN.md «Статус реализации») |
| Overlay Renderer | `uOverlayRenderer.pas` | «Canvas плагину не отдаётся»; плагин только публикует логический запрос превью (ARCHITECTURE.md §6, OVERLAY_PLUGIN.md) |
| Text Area (Viewer/Editor) | `uEditorWindow.pas`, `uEditorDoc.pas`, `uEditorPainter.pas` | «Not a plugin API yet; extract TEXTAREA_PLUGIN only if a second multiline consumer appears» (ARCHITECTURE.md §3) |
| Toolbar (F-bar) / Status line Dual Panel | `uFunctionBar.pas`, `uDualPanelStatus.pas` | «Host-only… cdecl ещё не экспортируется» (TOOLBAR_PLUGIN.md, STATUS_PLUGIN.md) |
| Event Bus (`IMessageBus`) | `uMessageBus.pas` | Инфраструктура pub/sub сама по себе ядро; ей пользуются и системные, и пользовательские плагины |
| Process bridge / ConPTY, ANSI Parser | `uConPty.pas`, `uANSIParser.pas`, `uConsoleBuffer.pas` | Инвариант 10 «Process-изоляция только через process bridge ядра» |
| Config / Session / Keymap-файлы | `uConfigLocation.pas`, `uSession` | Персистентность состояния приложения — ядро |
| Plugin Manager (загрузчик, реестры, ABI) | `uPluginHost.pas`, `uPluginLoader.pas`, `uPluginManifest.pas`, `uPluginHostAbi.pas`, `uPanelPluginRegistry.pas`, `uWasmPluginHost.pas` | Сама инфраструктура, которая *обслуживает* оба вида плагинов — по определению ядро |

---

## 3. Системные плагины — что уже вынесено или явно спланировано как «плагин первой партии»

Источник: PLUGIN_TRANSITION.md §6–7, ARCHITECTURE.md таблица «Stage 29 seams».

| Плагин | Схема/точка входа | Статус | Роль |
|---|---|---|---|
| `mtn.7z` | `7z://`, DLL (родной ABI v1) | **Сделано** (этап 29, фаза 1) | Родной VFS-плагин архивов `.7z` через локальный `7z.dll` (LGPL, не Far ArcLite) — list/exists/read, F5-extract через host-мост `vtrPluginExtract`, pack (этап 49) |
| `mtn.ws` | меню Commands → Workspace, WASM | **Сделано** (этап 30) | Сама схема `ws:///` — в ядре (`uWorkspaceVfs.pas`); WASM-плагин добавляет только пункты меню поверх неё. Нет `wasmtime.dll` → пункты меню не появляются, схема продолжает работать |
| `mtn.tmp` | `tmp:///`, WASM | **Сделано** (демо/референс) | Демонстрационная панель поверх WASM guest ABI — образец для сторонних авторов |
| `mtn.wasm.demo` | `wasmdemo://`, WASM (`.wat`) | **Сделано** (этап 30, демо) | Read-only fake VFS — эталонный пример гостевого ABI (`mtn_vfs_list`/`exists`/`read_text`/…) |
| **SFTP-провайдер** | `sftp://` | **In-process в ядре, не вынесен** | Кандидат на вынос в системный DLL/WASM-плагин по образцу `mtn.7z`, когда появится второй сетевой протокол (S3 и т.п. — явно отмечены как «не сделано») |
| **Far API Wrapper** | мост VFS-плагинов Far Manager | **Не реализовано** (этап 31, «отложено») | Не «плагин» в родном ABI — мост, транслирующий `PluginPanelItem` Far → Pull MTN2. Системный в смысле поставки (часть продукта), но отдельная, более поздняя категория моста совместимости |
| **TC Plugin Bridge (WCX/WFX)** | мост packer/FS-плагинов Total Commander | **Не реализовано** (этап 32, «отложено») | То же — мост совместимости, не собственный ABI-плагин |

**Правило приоритета поставки** (readme.md §6.0): родные плагины MTN2 → WASM → Far → Total Commander. Любой внешний формат обязан уметь жить как родной VFS/panel-плагин; мосты Far/TC — совместимость с уже написанной сторонней экосистемой, не единственный путь поддержки форматов.

---

## 4. Пользовательские (сторонние) плагины — что экосистема уже позволяет и чего ей пока не хватает

Хост не вводит отдельного «пользовательского» ABI — сторонний плагин пишется и грузится ровно так же, как `mtn.7z`/`mtn.ws` (`plugins\<id>\*.dll` или `*.wasm` + опциональный `plugin.json`). Разница только в том, что три пункта ниже — единственное, что сторонний плагин физически может сделать сегодня; остальное описано в контрактах `*_PLUGIN.md`, но cdecl-экспорт ещё не открыт.

### 4.1. Доступно сторонним плагинам уже сейчас

| Возможность | Host API | Ограничение |
|---|---|---|
| Зарегистрировать VFS-схему | `RegisterPluginScheme` / `RegisterVfsScheme` | Нельзя перехватить `file`/`recycle`/`sys`/`find`/`ws` — хост игнорирует такую попытку |
| Зарегистрировать панель для своей схемы | `RegisterPanelPlugin` → `IPanelPluginRegistry` | Идентификация плагина для схемы; сама отрисовка панели всё ещё через `TFilePanelModel` ядра (Pull cdecl для панели — фаза 3, не начата) |
| Добавить пункт меню | `RegisterMenuItem` → `IMenuRegistry` | Новые пункты — да; новые *действия* keymap — нет |
| Перебиндить существующий хоткей | `RegisterKeyBinding` → `IKeymapRegistry` | Только rebind, не новое действие |
| Опубликовать событие / подписаться | `HostPublish` / `mtn_host_publish` → `IMessageBus` | — |
| Запросить перерисовку окна | `HostInvalidate` / `mtn_host_invalidate` | — |
| Скопировать/переместить через свой backend | `ClassifyVfsTransfer` | plugin-owned Copy/Move остаются в backend плагина; cross-scheme кроме `plugin→file` — `vecNotSupported` |

### 4.2. Описано контрактом, но cdecl ещё не экспортирован (недоступно сторонним плагинам сегодня)

Источник: [UI_PRIMITIVES.md](UI_PRIMITIVES.md) — таблица 7 примитивов.

| Примитив | Документ | Текущий статус |
|---|---|---|
| Панель (полный cdecl Pull: `get_row_json`/`handle_event`) | [PANEL_PLUGIN.md](PANEL_PLUGIN.md) | Протокол описан, не экспортирован — PLUGIN_TRANSITION.md фаза 3 |
| Диалог | [DIALOG_PLUGIN.md](DIALOG_PLUGIN.md) | `mtn_dialog_*` не экспортирован — фаза 5 |
| Text Area (Viewer/Editor) | [TEXTAREA_PLUGIN.md](TEXTAREA_PLUGIN.md) | Host-only, «until a second multiline consumer appears» — фаза 5 |
| Toolbar / F-bar | [TOOLBAR_PLUGIN.md](TOOLBAR_PLUGIN.md) | Host-only — фаза 5 |
| Status line | [STATUS_PLUGIN.md](STATUS_PLUGIN.md) | Host-only — фаза 5 |
| Graphic Overlay | [OVERLAY_PLUGIN.md](OVERLAY_PLUGIN.md) | Host-only, Canvas не отдаётся — фаза 5 |
| Input Line | [INPUT_PLUGIN.md](INPUT_PLUGIN.md) | Общий примитив диалогов/cmdline, отдельного cdecl нет |

### 4.3. Явно недоступно и не планируется как ABI-плагин

- **Макросы/скриптинг (этап 26)** — это не тот же механизм, что DLL/WASM-плагины. Движок макросов (PascalScript/Lua/QuickJS — ещё не выбран) выполняет **пользовательские скрипты**, но сам движок — код ядра; скрипт пользователя не проходит через `uPluginHostAbi` и не грузится как `plugins\<id>\*.dll`. Не путать «пользовательский плагин» (сторонний DLL/WASM по Host API) с «пользовательским макросом» (скрипт уровня приложения) — в документации это разные механизмы расширения.
- **Far/TC-плагины напрямую** — сторонний Far/TC-плагин (`.dll` в формате Far/WCX/WFX) никогда не грузится напрямую родным Plugin Manager'ом; он проходит либо не проходит через мост (§3, этапы 31–32), которого пока нет.

---

## 5. Сводная таблица

| Зона | Примеры | Файлы/каталоги | Готовность |
|---|---|---|---|
| **Ядро** | Dual Panel, Editor/Viewer, Theme Engine, Keymap, Jobs, VFS Core+схемы `file/zip/sys/recycle/find/ws/sftp`, Dialog Host, Overlay Renderer, ConPTY, Event Bus, Plugin Manager сам по себе | `src/Core`, `src/Forms`, `src/Themes` | Реализовано |
| **Системные плагины (готово)** | `mtn.7z` (7z-архивы), `mtn.ws` (workspace-меню), `mtn.tmp`/`mtn.wasm.demo` (демо) | `src/plugins/mtn.7z`, `src/plugins/mtn.ws`, `src/plugins/mtn.tmp`, `src/plugins/mtn.wasm.demo` | Сделано, покрыто тестами |
| **Системные плагины (запланировано)** | SFTP как отдельный плагин, Far API Wrapper, TC Plugin Bridge | — | Не начато (этапы 31–32 «отложено»; SFTP-вынос без номера этапа) |
| **Пользовательские плагины (доступно)** | VFS-схема + панель (идентификация) + пункты меню + rebind хоткеев + pub/sub + invalidate | Host API (`uPluginHostAbi.pas`) | Работает уже сейчас, тем же путём что `mtn.7z` |
| **Пользовательские плагины (запланировано)** | Полный Pull для панели, диалоги, F-bar/status/overlay/text-area как плагин-контент | `PANEL_PLUGIN.md` и другие `*_PLUGIN.md` | Контракт описан, cdecl не экспортирован — фазы 3 и 5 PLUGIN_TRANSITION.md |
| **Не ABI-плагин (отдельный механизм)** | Макросы/скриптинг пользователя | — | Не путать с DLL/WASM-плагинами |

---

## 6. Как это соотносится с текущим планом (PLUGIN_TRANSITION.md)

- Фазы **0, 1, 2, 4, 6** (швы Host, `mtn.7z`, invalidate+PluginId, copy-bridge, WASM-host) закрывают колонку «Системные плагины (готово)» и базовый набор «Пользовательские плагины (доступно)» из §5.
- Фаза **3** (cdecl Pull для самой панели) и фаза **5** (overlay/textarea/dialog cdecl) — это именно то, что должно случиться, чтобы строки §4.2 переехали из «описано, не экспортировано» в «доступно».
- Фаза **7** (Far/TC-мосты) закрывает последнюю строку §3.
- Все три фазы сознательно **отложены** до закрытия daily-use очереди (см. предыдущий разбор: этапы 26/36/54) — само разделение на зоны в этом документе не меняется от того, когда фазы будут реализованы, но столбец «Готовность» в §5 будет обновляться по мере их закрытия.
