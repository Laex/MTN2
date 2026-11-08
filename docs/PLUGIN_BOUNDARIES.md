# Functionality Split: Core / System Plugins / User Plugins

**English** | [Русский](PLUGIN_BOUNDARIES.ru.md)

> **Role of this document:** a classification of existing and planned MTN2 functionality into three areas of responsibility – what must stay in the core, what the product ships as a "system" plugin, and what belongs to the ecosystem of third-party "user" plugins.
> **Sources:** [ARCHITECTURE.md](ARCHITECTURE.md) §6 (the Core–Theme–Plugin pattern, invariants 13–14), [SDS.md](SDS.md) §6.0/§6.8 (product priority and the Far/TC bridges), [UI_PRIMITIVES.md](UI_PRIMITIVES.md) and the related `*_PLUGIN.md` files.
> How to write a plugin and replace built-in features: [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md).
> Designs nothing new – it gathers decisions already made into one table, so the split is visible as a whole rather than in pieces across different files.

---

## 1. The three areas – definitions

| Area | Definition | Written by | Where the code lives |
|---|---|---|---|
| **Core** | Functionality that, per invariant 13 of ARCHITECTURE.md, must stay in the single native exe – it is never moved into plugins, no matter how many plugins appear. | The MTN2 developer only | `src/Core`, `src/Forms`, `src/Themes` – compiled into `MTN2.exe` |
| **System plugins** | "First batch" plugins: they use the same native ABI (`uPluginHostAbi`, `cPluginAbiVersion`) as third-party ones, but ship with the product by default and implement functionality the product promises out of the box (archives, the workspace panel…). | The MTN2 developer | `src/plugins/<id>/` – separate DLL/WASM files next to the exe (`plugins\<id>\*.dll`/`*.wasm`) |
| **User plugins** | The same ABI ecosystem, but the code and delivery are third-party. The host does not distinguish a system plugin from a user plugin at the protocol level – the only difference is who wrote them and how they got into `plugins\`. | Third-party developers / the user | Outside the repository; the same contract `plugins\<id>\*.dll`/`*.so`/`*.wasm` + optional `plugin.json` |

**Key nuance (invariant 14, ARCHITECTURE.md):** the "system / user" split is a matter of **delivery**, not architecture. The protocol is the same (Host API, Pull, JSON, no `TCanvas`, async I/O). The real architectural boundary the host sees is not "who is the author" but the **level of trust/isolation**:

| Delivery form | Access to process memory | Where it is used now |
|---|---|---|
| DLL/SO (native ABI v1) | Full (native, trusted code) | `mtn.7z` (system) |
| WASM (Wasmtime, no WASI) | Only UTF-8/JSON copies at offsets in the guest's linear memory, sandboxed | `mtn.ws`, `mtn.tmp`, `mtn.highlight` (system) |
| Far/TC bridge (future) | Through a separate ABI bridge on top of the native Plugin Manager | not implemented ("Far API Wrapper" – "Total Commander plugin bridge") |

A system plugin and a user plugin in DLL form are equally trusted (full process access) – being "system" grants no extra rights and takes none away.

---

## 2. Core – what is never moved out

Source: ARCHITECTURE.md §6 (the roles table), invariants 1–19 (§9), first of all No. 13 "Core as an artifact" and No. 1 "UI safety".

| Subsystem | Modules | Why it is core |
|---|---|---|
| Layout / Focus / Z-order / MDI compositor | `uMdiCompositor`, `TDualPanelWindow`, `TMainForm` | Invariant 13; "Do not cut up `TDualPanelWindow`" (ARCHITECTURE.md §6, "Rules for the plugin system seams") |
| Rendering (double buffering, dynamic grid) | `uTerminalRenderer.pas`, `TTerminalGrid` | A plugin is never given a `TCanvas` (a common invariant of all primitives, UI_PRIMITIVES.md) |
| Theme (`IThemeRenderer`) | `uDataTheme.pas` + theme files: `NDN` is embedded in the exe (`src/Assets/themes/NDN.theme.json`), the other seven are in `resource\themes\` | The "Theme" role is separate from the "Plugin" role in the pattern itself (§6); alternative themes are Pascal classes, "not loadable plugins – that is a separate, later piece of work" (ARCHITECTURE.md §6) |
| Keymap dispatcher and the active keymap | `uKeymap.pas` | A plugin may only rebind existing actions through `IKeymapRegistry` – "We do not introduce new keymap actions through a DLL: the enum is closed" (ARCHITECTURE.md §6, rule 6) |
| Jobs Manager / background tasks | `uDualPanelJobList.pas`, `TPanelJobController` | Invariant 1: all I/O goes only through the core's async VFS/Jobs |
| VFS Core & routing (`uVfsRegistry`) | `uVfsRegistry.pas` | The registry itself, transfer route classification and `plugin.json` loading are core; individual VFS **providers** may be plugins (see §3) |
| Core VFS schemes: `file`, `zip`, `sys`, `recycle`, `find`, `ws` | `uFileVfs`, `uZipVirtualFileSystem`, `uSysFoldersVfs`, `uRecycleBinVfs`, `uFindVfs`, `uWorkspaceVfs` | Explicitly protected from interception: "the host accepts and ignores WASM `register_vfs_scheme` for `file`/`recycle`/`sys`/`find`/`ws`" (ARCHITECTURE.md §6, rule 1) |
| `sftp://` | `uSftpVfs.pas` | Currently an in-process core provider, not moved into a plugin (ARCHITECTURE.md §1) – a candidate for a future system plugin, see §4 |
| Dialog Host (dialog engine) | `uDialogHost.pas`, `uDialogTypes.pas`, `uDialogJson.pas` | Layout/focus/modal overlay are Host; the cdecl `mtn_dialog_*` for content is not exported yet (DIALOG_PLUGIN.md, "Implementation status") |
| Overlay Renderer | `uOverlayRenderer.pas` | "No Canvas is given to a plugin"; the plugin only publishes a logical preview request (ARCHITECTURE.md §6, OVERLAY_PLUGIN.md) |
| Text Area (Viewer/Editor) | `uEditorWindow.pas`, `uEditorDoc.pas`, `uEditorPainter.pas` | "Not a plugin API yet; extract TEXTAREA_PLUGIN only if a second multiline consumer appears" (ARCHITECTURE.md §3) |
| Toolbar (F-bar) / Dual Panel status line | `uFunctionBar.pas`, `uDualPanelStatus.pas` | "Host-only… cdecl is not exported yet" (TOOLBAR_PLUGIN.md, STATUS_PLUGIN.md) |
| Event Bus (`IMessageBus`) | `uMessageBus.pas` | The pub/sub infrastructure is itself core; both system and user plugins use it |
| Process bridge / ConPTY, ANSI Parser | `uConPty.pas`, `uANSIParser.pas`, `uConsoleBuffer.pas` | Invariant 10 "Process isolation only through the core's process bridge" |
| Config / Session / Keymap files | `uConfigLocation.pas`, `uSession` | Persistence of application state is core |
| Plugin Manager (loader, registries, ABI) | `uPluginHost.pas`, `uPluginLoader.pas`, `uPluginManifest.pas`, `uPluginHostAbi.pas`, `uPanelPluginRegistry.pas`, `uWasmPluginHost.pas` | The infrastructure that *serves* both kinds of plugins – core by definition |

---

## 3. System plugins – what is already moved out or explicitly planned as a "first batch plugin"

Source: ARCHITECTURE.md §6 (the "Plugin seams" table, "Rules for the plugin system seams").

| Plugin | Scheme/entry point | Status | Role |
|---|---|---|---|
| `mtn.7z` | `7z://`, DLL (native ABI v1) | **Done** ("Native plugins: Plugin Manager + DLL/SO") | Native VFS plugin for `.7z` archives via the local `7z.dll` (LGPL, not Far ArcLite) – list/exists/read, F5 extract through the host bridge `vtrPluginExtract`, pack ("Pack into `7z://`") |
| `mtn.ws` | Commands → Workspace menu, WASM | **Done** ("WASM Host for native plugins") | The `ws:///` scheme itself is in the core (`uWorkspaceVfs.pas`); the WASM plugin only adds menu items on top of it. Without `wasmtime.dll` the menu items do not appear, and the scheme keeps working |
| `mtn.highlight` | text highlighting, WASM | **Done** | Colors about 70 languages in the viewer and editor with the `syntect` library; parsing runs in the WASM sandbox, and the plugin keeps the state between lines (`register_highlighter_state`) |
| `mtn.tmp` | `tmp:///`, WASM | **Done** (demo/reference) | A demonstration panel on top of the WASM guest ABI – a sample for third-party authors |
| `mtn.wasm.demo` (`samples\plugins`) | `wasmdemo://`, WASM (`.wat`) | **Done** (sample, not part of the build) | A read-only fake VFS – the reference example of the guest ABI (`mtn_vfs_list`/`exists`/`read_text`/…) |
| `mtn.net` | `net://`, `ftp://`, `ftps://`, `nsftp://`, `scp://`, `dav://`, `davs://`, `s3://`, DLL (ABI 4) | **Done** | Network client for FTP/FTPS/SFTP/SCP/WebDAV/S3 on libcurl: an entry in the drive selection window, a list of saved connections, VFS scheme version 2 (transfer progress and cancellation, paged listing), prompts for password, server key and certificate. Does not replace the built-in `sftp://`: the plugin's SFTP runs under `nsftp://` |
| **SFTP provider** | `sftp://` | **In-process in the core, not moved out** | Stays in the core: `mtn.net` runs next to it, with its own SFTP under the `nsftp://` scheme |
| **Far API Wrapper** | bridge for Far Manager VFS plugins | **Not implemented** ("Far API Wrapper", "deferred") | Not a "plugin" in the native ABI – a bridge translating Far's `PluginPanelItem` to MTN2 Pull. System in the sense of delivery (part of the product), but a separate, later category of compatibility bridge |
| **TC Plugin Bridge (WCX/WFX)** | bridge for Total Commander packer/FS plugins | **Not implemented** ("Total Commander plugin bridge", "deferred") | Likewise – a compatibility bridge, not a plugin of the native ABI |

**Delivery priority rule** (SDS §6.0): native MTN2 plugins → WASM → Far → Total Commander. Any external format must be able to live as a native VFS/panel plugin; the Far/TC bridges provide compatibility with the existing third-party ecosystem and are not the only way to support formats.

---

## 4. User (third-party) plugins – what the ecosystem already allows and what it still lacks

The host does not introduce a separate "user" ABI – a third-party plugin is written and loaded exactly like `mtn.7z`/`mtn.ws` (`plugins\<id>\*.dll` or `*.wasm` + optional `plugin.json`). The only difference is that the items in §4.1 are all a third-party plugin can physically do today; the rest is described in the `*_PLUGIN.md` contracts, but the cdecl export is not open yet.

### 4.1. Available to third-party plugins now

| Capability | Host API | Limitation |
|---|---|---|
| Register a VFS scheme | `RegisterPluginScheme` / `RegisterVfsScheme` | `file`/`recycle`/`sys`/`find`/`ws` cannot be intercepted – the host ignores such an attempt. A plugin does not take over a scheme with a built-in handler (`sftp`) without permission |
| Replace a built-in scheme or archive extension | `overrides` in `plugin.json` + `plugins\overrides.json` | Only with the user's explicit permission; reserved schemes are not replaced; `.zip` changes the Enter transition, not the internal `!/` path (ARCHITECTURE.md §6, rule 7) |
| Register a panel for its own scheme | `RegisterPanelPlugin` → `IPanelPluginRegistry` | Identifies the plugin for the scheme; the panel is still drawn through the core's `TFilePanelModel` (the Pull cdecl for the panel is the "cdecl Pull adapter" step, not started) |
| Add a menu item | `RegisterMenuItem` → `IMenuRegistry` | New items – yes; new keymap *actions* – no |
| Add an entry to the drive selection window | `RegisterDriveItem` → the drive item registry | At most ten items from all plugins; the address cannot be `file://` |
| Rebind an existing hotkey | `RegisterKeyBinding` → `IKeymapRegistry` | Only a rebind of an existing action; for a shortcut for its own command, see below |
| Intercept a built-in command | `RegisterCommandHook` → `ICommandRegistry` | Commands of the panels, the top menu, the viewer and the editor; a hook may cancel the command (ARCHITECTURE.md §6, rule 8) |
| Open files of a type in F3 / F4 its own way | `RegisterDocumentProvider` → `IDocumentProviderRegistry` | The plugin opens the file itself, passes a different URI to the built-in window, or declines; the viewer and editor window stays the host's (ARCHITECTURE.md §6, rule 9) |
| Add its own command and shortcut | `RegisterCommand` + `RegisterKeyBinding` | A shortcut taken by a built-in action stays with it |
| Publish an event / subscribe | `HostPublish` / `mtn_host_publish` → `IMessageBus` | – |
| Request a window repaint | `HostInvalidate` / `mtn_host_invalidate` | – |
| Copy/move through its own backend | `ClassifyVfsTransfer` | Plugin-owned Copy/Move stay in the plugin's backend; cross-scheme except `plugin→file` is `vecNotSupported` |

### 4.2. Described by a contract, but the cdecl is not exported yet (not available to third-party plugins today)

Source: [UI_PRIMITIVES.md](UI_PRIMITIVES.md) – the table of 7 primitives.

| Primitive | Document | Current status |
|---|---|---|
| Panel (full cdecl Pull: `get_row_json`/`handle_event`) | [PANEL_PLUGIN.md](PANEL_PLUGIN.md) | The panel rows of a plugin are supplied by its VFS scheme; reacting to row activation (`RegisterPanelActivate`) is available. The full `get_row_json` / `handle_event` is not exported |
| Dialog | [DIALOG_PLUGIN.md](DIALOG_PLUGIN.md) | A one-shot modal dialog is available (`ShowDialog`: JSON declaration, the response is a control id and values); separate `mtn_dialog_*` for a live dialog are not exported |
| Text Area (Viewer/Editor) | [TEXTAREA_PLUGIN.md](TEXTAREA_PLUGIN.md) | Host-only, "until a second multiline consumer appears" – the "overlay / textarea / dialog cdecl" step |
| Toolbar / F-bar | [TOOLBAR_PLUGIN.md](TOOLBAR_PLUGIN.md) | The plugin sets the caption of its command (`SetCommandCaption`) for an F-key with modifiers; the button set stays the host's |
| Status line | [STATUS_PLUGIN.md](STATUS_PLUGIN.md) | The plugin adds a named text segment (`SetStatusSegment`) to the panels' status line; the composition and look are set by the host |
| Graphic Overlay | [OVERLAY_PLUGIN.md](OVERLAY_PLUGIN.md) | Host-only, no Canvas is given – the "overlay / textarea / dialog cdecl" step |
| Input Line | [INPUT_PLUGIN.md](INPUT_PLUGIN.md) | A common primitive of dialogs/cmdline, no separate cdecl |

### 4.3. Explicitly unavailable and not planned as an ABI plugin

- **Macros/scripting ("Macros / scripting")** – this is not the same mechanism as DLL/WASM plugins. The macro engine (PascalScript/Lua/QuickJS – not chosen yet) runs **user scripts**, but the engine itself is core code; a user's script does not pass through `uPluginHostAbi` and is not loaded as `plugins\<id>\*.dll`. Do not confuse a "user plugin" (a third-party DLL/WASM using the Host API) with a "user macro" (an application-level script) – in the documentation these are different extension mechanisms.
- **Far/TC plugins directly** – a third-party Far/TC plugin (a `.dll` in the Far/WCX/WFX format) is never loaded directly by the native Plugin Manager; it passes (or does not pass) through the bridge (§3, "Far API Wrapper" – "Total Commander plugin bridge"), which does not exist yet.

---

## 5. Summary table

| Area | Examples | Files/directories | Readiness |
|---|---|---|---|
| **Core** | Dual Panel, Editor/Viewer, Theme Engine, Keymap, Jobs, VFS Core + schemes `file/zip/sys/recycle/find/ws/sftp`, Dialog Host, Overlay Renderer, ConPTY, Event Bus, the Plugin Manager itself | `src/Core`, `src/Forms`, `src/Themes` | Implemented |
| **System plugins (ready)** | `mtn.7z` (7z archives), `mtn.ws` (workspace menu), `mtn.tmp` | `src/plugins/mtn.7z`, `src/plugins/mtn.ws`, `src/plugins/mtn.tmp` | Done, covered by tests |
| **System plugins (planned)** | SFTP as a separate plugin, Far API Wrapper, TC Plugin Bridge | – | Not started ("Far API Wrapper" – "Total Commander plugin bridge" "deferred"; moving SFTP out is not started) |
| **User plugins (available)** | VFS scheme + panel (identification) + menu items + hotkey rebind + pub/sub + invalidate | Host API (`uPluginHostAbi.pas`) | Works now, the same way as `mtn.7z` |
| **User plugins (planned)** | Full Pull for the panel, dialogs, F-bar/status/overlay/text-area as plugin content | `PANEL_PLUGIN.md` and other `*_PLUGIN.md` | Contract described, cdecl not exported: Pull for the panel itself, overlay and text area (see §6) |
| **Not an ABI plugin (separate mechanism)** | User macros/scripting | – | Do not confuse with DLL/WASM plugins |

---

## 6. Implementation state

- Ready: the host seams, the native VFS plugin `mtn.7z`, the panel plugin identifier and repaint (`mtn_host_invalidate`), the copy bridge, the WASM host. These are the "System plugins (ready)" column and the base set of "User plugins (available)" from §5. The plugin dialog (`ShowDialog`), the command caption and the status segment are ready as well.
- Not ready: Pull for the panel itself (cdecl `get_row_json` / `handle_event`) and cdecl for overlay and text area. These are what turn the §4.2 rows from "described, not exported" into "available"; overlay and text area are deferred until a second consumer of the primitive appears.
- The Far and Total Commander bridges cover the last row of §3 and are deferred until the native API and WASM are stable.
- These steps are deliberately deferred until the queue of everyday features is done. The split into areas does not depend on timing; the "Readiness" column in §5 is updated as they are completed.
