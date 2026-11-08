# UI Primitive Contracts (Plugin ↔ Core)

**English** | [Русский](UI_PRIMITIVES.ru.md)

> **Role of this document:** an index of the technical contracts for the core's basic visual containers.  
> **Context:** [SDS.md](SDS.md) §6.2, [ARCHITECTURE.md](ARCHITECTURE.md) §6.

Each document describes how **one** primitive interacts with a data-providing plugin (Pull model, no `TCanvas` for the plugin).

**Delivery:** plugins are currently implemented inside the single code base, but the contracts below are binding already. Once the system is stable, plugin code moves into external loadable modules (DLL/SO/WASM) without changing the protocols. Ecosystem order: **native MTN2 plugins → Far → Total Commander** (SDS §6.0). See SDS, §6 for details. The Dual Panel F-bar / status line are currently Host-only (`uFunctionBar`, `uDualPanelStatus`); the cdecl toolbar/status is the goal of the contracts, not the current runtime.

| # | Primitive | Document |
|---|---|---|
| 1 | Panel / file list | [PANEL_PLUGIN.md](PANEL_PLUGIN.md) |
| 2 | Text field (Input Line) | [INPUT_PLUGIN.md](INPUT_PLUGIN.md) |
| 3 | Text area (Text Area) – Viewer / Editor | [TEXTAREA_PLUGIN.md](TEXTAREA_PLUGIN.md) |
| 4 | Dialog window (Dialog) | [DIALOG_PLUGIN.md](DIALOG_PLUGIN.md) |
| 5 | Toolbar (Toolbar / Button Bar) | [TOOLBAR_PLUGIN.md](TOOLBAR_PLUGIN.md) |
| 6 | Status line (Status Line) | [STATUS_PLUGIN.md](STATUS_PLUGIN.md) |
| 7 | Graphic overlay (Media Overlay) | [OVERLAY_PLUGIN.md](OVERLAY_PLUGIN.md) |

### Common invariants of all primitives

1. The plugin neither draws nor picks colors – only logical data and events.
2. Cell style is `IThemeRenderer`; compositing and focus belong to the core (Host).
3. Pull / callback from the UI thread without blocking I/O; disk and network go through Async VFS / Jobs.
4. The "data changed" signal is `mtn_host_invalidate(WindowId)` (or the Event Bus equivalent).
5. Errors are not propagated as exceptions across the DLL boundary – codes / JSON / an empty model.
