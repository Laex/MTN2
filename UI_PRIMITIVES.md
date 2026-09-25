# Контракты UI-примитивов (плагин ↔ ядро)

> **Роль документа:** оглавление технических контрактов базовых визуальных контейнеров ядра.  
> **Контекст:** [readme.md](readme.md) §6.2, [ARCHITECTURE.md](ARCHITECTURE.md) §6.

Каждый документ описывает взаимодействие **одного** примитива с плагином-поставщиком данных (Pull-модель, без `TCanvas` у плагина).

**Поставка:** в MVP плагины реализуются внутри единой кодовой базы, но контракты ниже обязательны уже на этом этапе. После стабилизации системы код плагинов выносится во внешние загружаемые модули (DLL/SO/WASM) без изменения протоколов. Порядок экосистемы: **родные плагины MTN2 → Far → Total Commander** (SDS §6.0). Подробнее — SDS, §6. Dual Panel F-bar / status line сейчас Host-only (`uFunctionBar`, `uDualPanelStatus`); cdecl toolbar/status — цель контрактов, не текущий runtime.

| # | Примитив | Документ |
|---|---|---|
| 1 | Панель (Panel) / файловый список | [PANEL_PLUGIN.md](PANEL_PLUGIN.md) |
| 2 | Текстовое поле (Input Line) | [INPUT_PLUGIN.md](INPUT_PLUGIN.md) |
| 3 | Текстовая область (Text Area) — Viewer / Editor | [TEXTAREA_PLUGIN.md](TEXTAREA_PLUGIN.md) |
| 4 | Диалоговое окно (Dialog) | [DIALOG_PLUGIN.md](DIALOG_PLUGIN.md) |
| 5 | Панель инструментов (Toolbar / Button Bar) | [TOOLBAR_PLUGIN.md](TOOLBAR_PLUGIN.md) |
| 6 | Строка состояния (Status Line) | [STATUS_PLUGIN.md](STATUS_PLUGIN.md) |
| 7 | Графический оверлей (Media Overlay) | [OVERLAY_PLUGIN.md](OVERLAY_PLUGIN.md) |

### Общие инварианты всех примитивов

1. Плагин не рисует и не выбирает цвета — только логические данные и события.
2. Стиль ячеек — `IThemeRenderer`; композитинг и focus — ядро (Host).
3. Pull / callback из UI-потока без блокирующего I/O; диск и сеть — Async VFS / Jobs.
4. Сигнал «данные изменились» — `mtn_host_invalidate(WindowId)` (или эквивалент Event Bus).
5. Ошибки не пробрасываются исключениями через границу DLL — коды / JSON / пустая модель.
