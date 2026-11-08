# MTN2 Plugin Development

**English** | [Русский](PLUGIN_DEVELOPMENT.ru.md)

> **Purpose of this document:** a reference for plugin authors – what lives in a plugin folder, what the manifest describes, which extension points the host offers, and how a plugin can replace a built-in feature.
> **Related documents:** [PLUGIN_BOUNDARIES.md](PLUGIN_BOUNDARIES.md) (what stays in the core), [ARCHITECTURE.md](ARCHITECTURE.md) §6 (rules and structure of the seams), [DIALOG_PLUGIN.md](DIALOG_PLUGIN.md) (dialog format).

---

## 1. Folder and manifest

A plugin lives in `plugins\<id>\` next to `MTN2.exe`: one DLL (a native plugin), or `*.wasm` / `*.wat` (a WASM plugin), and an optional `plugin.json`. The plugin identifier is the folder name.

```json
{
  "id": "mtn.example",
  "name": "Example",
  "version": "0.1.0",
  "abi": 2,
  "schemes": ["example"],
  "archiveExtensions": ["exm"],
  "overrides": ["sftp", ".zip"],
  "startup": true
}
```

| Field | Purpose |
|---|---|
| `abi` | The ABI version the plugin was built for (1–4). The host loads plugins with an ABI from 1 up to its own version |
| `schemes` | URI schemes the plugin registers. The plugin is loaded on the first access to such a scheme |
| `archiveExtensions` | File extensions that Enter opens as an archive through the first scheme in `schemes` (`7z` by default) |
| `overrides` | Built-in handlers the plugin asks to replace: a scheme (`sftp`) or an extension with a dot (`.zip`). Takes effect only with the user's permission, see §3 |
| `wasi` | `true` – the WASM module is built for WASI (Go, Rust with a WASI runtime). The host gives it an empty WASI preview1: no files, environment or arguments, with a raised memory limit, and calls `_initialize` on a reactor module. Without this field a module that imports WASI is not loaded |
| `memoryMib` | Memory limit of a WASM module without WASI, in MiB (up to 256); 1 MiB without the field. Needed by a module with large tables, for example a syntax library |
| `keepLoaded` | `true` – the native DLL stays in memory after the plugin is unloaded or disabled: registrations are removed and `mtn_plugin_shutdown` is called, `FreeLibrary` is not. Needed for a DLL with a runtime that cannot be stopped (Go) |
| `description` | What the plugin does and how to use it: a string or an object keyed by language (`{"en": "...", "ru": "..."}`); without the current language, English is used |
| `author`, `homepage` | Author and website; shown in the Info dialog |
| `help` | Name of the markdown help file; it is looked up in `resource\<language>\help\` of the plugin folder, then in `resource\en\help\`. The Help button opens it in the built-in viewer |
| `resources` | Revision number of the key set in the plugin's `resource\<language>\strings.json`. The host compares it with `"version"` in the pack's `locale.json`: a pack newer than the plugin is ignored, an older one is applied (missing keys stay in English). Without the field any pack fits |
| `startup` | `true` – load at program start. Needed by a plugin whose work consists of command hooks, key bindings, captions and status segments: lazy loading by scheme or extension would never start it |
| `permissions` | Permissions the plugin asks the user to grant: `["vfs.read"]`. Without the grant (the Permissions... button in the plugin list) the calls that need it are rejected, see §2.6 |

A plugin without `plugin.json` is also loaded (lazily – when the top menu or the plugin list is opened).

---

## 2. Extension points

A native plugin exports `mtn_plugin_get_abi_version`, `mtn_plugin_init(PHostApiTable)` and `mtn_plugin_shutdown`. The `THostApiTable` table (`uPluginHostAbi.pas`) grows only at the end; fields of ABI 2 and 3 must be checked with `Assigned` if the plugin has to work on an older host too. A WASM plugin uses the same capabilities through the imports of the `mtn_host` module (the list is in the header of `uWasmPluginHost.pas`). All calls are made from the main thread, except `post_to_main`, `vfs_size`, `vfs_read_at` and `vfs_close`.

| Capability | Native ABI | WASM import | What the plugin gets |
|---|---|---|---|
| VFS scheme | `RegisterVfsScheme` | `register_vfs_scheme` | Its own URI scheme: listing, reading, copying |
| F-key captions for a scheme | `SetPanelFBar` (ABI 4) | – | `SetPanelFBar(plugin_id, scheme, json)`: while a panel shows a folder of this scheme, the F-key bar takes its captions from the JSON `{"root": {"F7": "New"}, "inside": {"Shift+F4": "X"}}` (`root` – the root `scheme:///`, `inside` – all other folders; an empty caption leaves only the number and the key does nothing in that folder; a file served as an archive, `scheme:///path!/`, counts as `root` at its top and `inside` below it). An empty JSON removes the captions. Native plugins only |
| VFS scheme with progress and cancellation | `RegisterVfsSchemeV2` (ABI 4) | – | The same, with a version 2 table: operation context (progress, cancellation, error text), paged listing, retry with a bigger buffer, copy flags. Native plugins only, see §2.8 |
| Panel for a scheme | `RegisterPanelPlugin` | `register_panel_plugin` | The identification of a scheme panel |
| Menu item | `RegisterMenuItem` | `register_menu_item` | An item of the Plugins menu (the plugin's group, a line between groups; the parent `Macros` is a separate Macros menu; other parent names are not used) |
| Key binding | `RegisterKeyBinding` | `register_key_binding` | Rebinding of a built-in action or a key for the plugin's own command |
| Event / redraw | `HostPublish`, `HostInvalidate` | `publish` | The event bus |
| Own command | `RegisterCommand`, `ExecuteCommand` | `register_command`, `execute_command` | A command with an arbitrary id (not equal to the name of a built-in one) |
| Built-in command hook | `RegisterCommandHook` | `register_command_hook` | A call before the built-in command; the answer 1 cancels it |
| File opening | `RegisterDocumentProvider` | `register_document_provider` | A decision on F3 / F4 for its own extensions: open it itself, substitute another URI (native only), or skip. The quick view mode (bit 4, the string `quick`, Ctrl+Q) accepts only a URI substitution |
| Launch by a system program | `OpenExternal` | – | Opens a local file with the associated program (native only) |
| Dialog | `ShowDialog` | `show_dialog` | A one-shot modal dialog from a JSON description; instead of the JSON text a file name from `plugins\<id>\dialogs\<name>.json` can be passed |
| Panel row activation | `RegisterPanelActivate` | `register_panel_activate` | A reaction to Enter / double click on a row of a panel of its scheme |
| Command caption | `SetCommandCaption` | `set_command_caption` | A caption in the bottom key bar |
| Status text | `SetStatusSegment` | `set_status_segment` | A named segment of the panel status line |
| Colored status text | `SetStatusSegmentStyled` | – (native plugins only, ABI 5) | The same segment made of colored parts: a JSON array `[{"t": "text", "role": "ok", "fg": "#RRGGBB", "bg": "#RRGGBB", "b": true}]`; `role` is `ok`, `warn`, `error`, `info`, `accent`, `neutral` (a color pair readable in any theme), `fg` and `bg` override its colors, a part without colors takes the status line colors; the optional `s` is a short text of the part: when the status line is hidden, the segments are shown at the right of the tab bar (to the left of the background job chips) in the short form, a part with an empty `s` is skipped there, and the last segments are dropped when space runs out; a click on such a chip shows the full text of the segment as a notification; the optional `c` is the id of a plugin command that a click on the part (in the status line and in the tab bar) runs instead of the notification |
| File in a built-in window | `OpenDocument` | – (native plugins only, ABI 6) | Opens a file by URI in the built-in viewer (`AEdit = 0`) or editor (`AEdit = 1`), bypassing document providers; returns `-1` if no panels are on screen or a dialog is open |
| Row name colors | `SetRowDecorations` | – (native plugins only, ABI 6) | Colors the row names of file panels in the folder `AFolderUri` (the folder address as `PanelInfo` returns it): a JSON object "row name: role" (`ok`, `warn`, `error`, `info`, `accent`, `neutral`) or "name: `#RRGGBB`". An empty object or `nil` removes the colors of the folder. The row under the cursor and selected rows keep the theme colors |
| Panel columns | `RegisterPanelColumns`, `SetPanelColumnValues` | – (native plugins only, ABI 9) | `RegisterPanelColumns(plugin_id, scheme, json)`: describes the columns a file panel shows in folders of the scheme (the "Custom" mode, the "Columns..." dialog). The JSON is an array of `{"id", "title", "title_key", "width", "align": "left\|right", "sortable", "default"}` or an object `{"columns": [...], "builtin": ["size", ...]}`; `builtin` lists which built-in columns (`ext`, `size`, `modified`, `created`, `accessed`, `type`, `attr`) make sense in folders of the scheme (no field – all of them; `[]` – none). This lets the plugin define the set that the "Columns..." dialog offers the user; `title` is the English heading, `title_key` is the key of its translation in the plugin's `resource/<language>/strings.json` (the host translates the heading in the panel, the dialog and the sort menu according to the interface language, including after it changes); `default` – the column is visible until the user picks columns for the scheme. The plugin sends the values in the VFS listing: a row carries an `"extra"` object, where the column `id` maps to a text, a number or `{"t": text, "n": number}` (the number sorts as a number). For folders the plugin does not list (local ones): `SetPanelColumnValues(plugin_id, folder_uri, json)` with the JSON `{"row name": {"id": value}}`, where the value is a text, a number or `{"t": text, "n": number}`, as in the listing; such folders are sorted by a column with `"sortable": true` (a number as a number); an empty JSON removes the values. An empty JSON in `RegisterPanelColumns` removes the columns of the scheme. Unloading the plugin removes everything |
| Settings | `RegisterSettings`, `GetSetting`, `SetSetting` | `register_settings`, `get_setting`, `set_setting` | A handler for the Settings button in the plugin dialog and its own key-value storage |
| Document | `DocInfo`, `DocGetText`, `DocReplace`, `DocSetCursor` | `doc_info`, `doc_get_text`, `doc_replace`, `doc_set_cursor` | The text of a document open in the viewer or editor: description, selection, line, the whole text; replacement in a single undo step |
| Panels | `PanelInfo`, `PanelGoto`, `PanelRefresh` | `panel_info`, `panel_goto`, `panel_refresh` | Both panels (folder, row under the cursor, selected rows), showing a folder in a panel, refresh |
| Clipboard | `ClipboardGet`, `ClipboardSet` | `clipboard_get`, `clipboard_set` | Text in the system clipboard |
| Notification | `ShowMessage` | `show_message` | A short notification (a pop-up chip) |
| Host events | `Subscribe` | `subscribe` | The events `doc.opened`, `doc.saved`, `doc.closed`, `language.changed` |
| Program information | `HostInfo` | `host_info` | The version and interface language (JSON) |
| Text translation | `Translate` (ABI 3) | `translate` | A text by key from the plugin's `resource\<language>\strings.json` pack, or the English default, see §2.7 |
| Drive list item | `RegisterDriveItem` (ABI 4) | – | An item in the drive selection window (Alt+F1 / Alt+F2) and in the drive bar: a caption, the address opened by Enter, a priority. Items follow the built-in ones and get the characters 5–9, then ! @ # $ % (at most ten from all plugins); while a panel stands on an address of the same scheme, the item is marked. Unloading the plugin removes the items. Native plugins only |
| Surface for a picture | `SurfaceOpen`, `SurfaceSetFrame`, `SurfaceSetInfo`, `SurfaceSetTimer`, `SurfaceClose` | `surface_open`, `surface_set_frame`, `surface_set_info`, `surface_set_timer`, `surface_close` | A viewer tab in which the host draws the plugin's frames (BGRA pixels); keys, the timer and closing come back to the plugin |

The names of built-in commands for hooks are the keymap action names (`Copy`, `Move`, `View`, `Edit`, `Delete`, `MkDir`, ...; the full list is `KEYMAP_ACTION_NAMES` in `uKeymap.pas`). A hook is called for a key press in the panels, for global keys and for a top menu item; the source (`key` / `menu`) is passed in the call. In the viewer and editor the actions `DocViewEdit`, `DocClose`, `EditorSave` and the other `Doc*` / `Editor*` actions are hooked.

What a plugin does not get: `TCanvas`, colors, windows. The dialog, panel, key bar and status line are drawn by the host from the plugin's logical data; a picture or a video frame gets into the viewer tab through a surface (section 2.4).

### 2.1. A minimal native plugin

```pascal
library Hello;

uses uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas';

function HookDelete(AUserData: Pointer; ACommand, AOrigin: PAnsiChar): Int64; cdecl;
begin
  Result := 0; // 1 = Delete handled by the plugin
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
begin
  if Assigned(AHostApi.RegisterCommandHook) then
    AHostApi.RegisterCommandHook('mtn.hello', 'Delete', @HookDelete, nil, 100);
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
end;

exports mtn_plugin_get_abi_version, mtn_plugin_init, mtn_plugin_shutdown;

begin
end.
```

The manifest of such a plugin is `{"id":"mtn.hello","abi":2,"startup":true}`.

### 2.2. A minimal WASM plugin

```wat
(module
  (import "mtn_host" "register_command_hook"
    (func $hook (param i32 i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 16) "Delete")
  (data (i32.const 32) "on_delete")
  (func (export "mtn_plugin_get_abi_version") (result i64) (i64.const 2))
  (func (export "mtn_plugin_init") (result i32)
    (drop (call $hook (i32.const 16) (i32.const 6) (i32.const 32) (i32.const 9) (i32.const 100)))
    (i32.const 0))
  (func (export "mtn_plugin_shutdown"))
  (func (export "on_delete") (result i32) (i32.const 0)))
```

A ready-made Rust project built the same way is `samples/plugins/mtn.template.rs`: copy the folder, set a new `id` in `plugin.json` and put your own command in place of `on_count` to get a working plugin.

The guest cannot see the host memory and cannot launch programs: the host copies strings into the guest's linear memory and back. WASI is connected only with `"wasi": true` and is empty: no files, no environment, no network.

A module whose runtime takes the whole linear memory (Go) exports `mtn_scratch_ptr() -> i32` – the address of its own 32-kilobyte buffer for exchanging strings with the host; without this export the host uses the tail of the guest memory.

---

### 2.3. Plugin settings

A plugin with settings registers a handler (`RegisterSettings` / `register_settings`). In **Options → Plugins...** such a row is marked `[settings]`, and the Settings button calls the handler: it shows the plugin's dialog (`ShowDialog`) and saves the choice. The plugin stores values with `SetSetting` / `GetSetting` (key-value strings): the host writes them to `plugin-settings-<id>.json` in the settings folder, so they are included in the settings export and import and work in portable mode; the plugin does not need the file path. `GetSetting` returns the length of the value, `-1` – the key is not set, `-2` – the buffer is too small. Samples: `mtn.demo.pas` (a notes file) and `mtn.demo.go` (indent width).

---

### 2.4. A surface for pictures and video

The plugin does not draw by itself: it opens a viewer tab and hands pixels to the host, and the host fits the frame into the tab, centered (the same drawing pass as for Quick View pictures). The tab title, the key hint and the status line stay native.

1. `SurfaceOpen(plugin_id, title, on_key, on_tick, on_closed, user)` opens a tab and returns a handle (greater than 0); `-1` – the tab cannot be opened (the host is not over the panels). Any of the callbacks may be empty. It is usually called from an open provider (F3), which then answers "handled".
2. `SurfaceSetFrame(handle, width, height, pixels, length)` replaces the picture: `width x height` points of 4 bytes in the order B, G, R, A, rows top to bottom without padding, `length = width * height * 4`. The host copies the data, so the buffer can be reused. A side is at most 16384, the size is at most 256 MB. The frame can be replaced any number of times.
3. `SurfaceSetInfo(handle, title, status)` sets the tab title and the status line text (size, number, time).
4. `SurfaceSetTimer(handle, interval_ms)` switches on the host timer: `on_tick` is called every `interval_ms` milliseconds while the tab is on screen (a hidden tab gets no timer). This is how a player picks the next frame; `0` switches the timer off.
5. `on_key(user, key)` receives a key press named like `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `PageUp`, `PageDown`, `Enter`, `Space`, `Tab`, `Esc`, `Backspace`, `Delete`, `Insert`, `F1`..`F12`, a character (`a`, `+`) or with the prefixes `Ctrl+`, `Alt+`, `Shift+` (`Ctrl+C`); the answer 1 means the key was used. Esc and F10 also reach `on_key` before the built-in handling: if the plugin answered 1, the host does nothing (the plugin calls `surface_close` itself or changes the mode); otherwise Esc leaves full screen and, when it is off, closes the tab, and F10 closes the tab. Closing the tab with the mouse, Ctrl+F4 and unloading the plugin do not depend on the answer.
6. `on_closed(user)` is called when the user closed the tab; the plugin releases its decoder. If the plugin closed the tab itself (`SurfaceClose`) or the plugin is unloaded, there is no call: after unloading, the host closes the plugin's tabs and no longer calls it.

Everything runs in the main thread: long decoding in a handler delays the interface, so heavy files should be reduced to a reasonable size before `SurfaceSetFrame`. Samples: `mtn.demo.img` (Rust, wheel zoom, dragging, rotation, full screen, showing in a panel) and `mtn.demo.video` (C++, video and sound on Media Foundation, pause and seeking).

**Modes, mouse and an own window.** `SurfaceOpenEx(plugin_id, title, mode, on_key, on_tick, on_closed, on_mouse, user)` opens a surface in one of the modes: `0` – a tab, `1` – a full-screen tab without a frame and key bars, `2` – a panel opposite the active one (like Quick View; it is closed with the same key combination, and a repeated call replaces the content). Add `256` to get an own window instead of frames (see below). `SurfaceSetFullscreen(handle, on)` switches full screen, and `surface_get_fullscreen(handle)` returns its state (`1` – on, `0` – off, `-1` – unknown handle); if the plugin did not take Esc, Esc first leaves full screen and only the second press closes the tab.

`on_mouse(user, kind, x, y, width, height, button, extra, shift)`: `kind` 0 – button pressed, 1 – released, 2 – move with a pressed button, 3 – wheel (`extra` is the number of clicks, positive – away from the user), 4 – double click, 5 – the area size changed (`width`, `height`; it also arrives before the first frame, and the plugin prepares a frame of the right size from it). `x`, `y` are in pixels from the top left corner of the area; `button` 1 – left, 2 – right, 3 – middle; `shift` – bits 1 Shift, 2 Ctrl, 4 Alt. The answer 1 means the event was used.

**An own window.** For the `+256` mode the host creates a child container window over the surface area, and `SurfaceNativeHandle(handle)` returns its HWND. The plugin creates its own windows inside it (a player, a web view, a control); the host stretches them over the whole container, keeps them above the tab area and hides them under dialogs and menus. The plugin's windows are destroyed together with the container when the tab is closed. An own window is not available to a WASM plugin. The sample is `mtn.demo.nativeview`. A WASM plugin uses the same functions in the `mtn_host` module (the signatures are in the header of `uWasmPluginHost.pas`): handlers are given by export names, pixels are read from the guest memory.

---

### 2.5. Documents, panels and the clipboard

A plugin can work with what is open in the program and change the built-in behavior of the viewer and editor. Everything runs in the main thread.

**Document.** The calls apply to the document of the active tab (F3 or F4); with no text document on screen (panels, a picture tab, hex view) they return `-1`.

* `doc_info` – JSON: `uri`, `path`, `viewOnly`, `canEdit`, `hex`, `markdown`, `dirty`, `lines`, `row`, `col` (zero-based), `hasSelection`.
* `doc_get_text(what)` – text: `what` 0 – the selection (an empty string if nothing is selected), 1 – the whole document (lines separated by LF), 2 – the line with the cursor.
* `doc_replace(what, text)` – replaces the same text in a single undo step. `what` 0 with an empty selection inserts the text at the cursor position. In the viewer (read-only) it returns `-1`: the plugin can suggest pressing F4.
* `doc_set_cursor(row, col)` – the cursor; a position past the end is clamped to the text bounds.
* `doc_set_selection(row1, col1, row2, col2)` – a selection from the first position to the second, the cursor goes to the end.
* `doc_line(index, buf, size)` – the text of one line (zero-based) without the line break; `-1` – there is no such line.

**How to return text.** `host_info`, `translate`, `doc_info`, `doc_get_text`, `panel_info` and `clipboard_get` return the length of the text in UTF-8 bytes. The text (and a zero byte in the native API) is written to the buffer only if it fits, so a result not smaller than the buffer size means "repeat with a bigger buffer" (`NULL` – only measure). In WASM the zero byte is not written, and the text fits when `length <= size`. `-1` – the data is unavailable.

**Panels.** `panel_info` – JSON: `active` (`left` or `right`) and, for each side, the folder `uri`, `cursor` (the URI of the row under the cursor, if it is not `..`), `cursorIsDirectory` and `selected` (the URIs of selected rows). `panel_goto(side, uri)` shows a folder in a panel: `side` 0 – left, 1 – right, -1 – active; the focus stays on the previous panel. The call is not performed if a dialog is open or the active tab is not a panel tab. `panel_refresh` rereads the active panel. File URIs look like `file:///C:/dir/a%20b.txt` (percent-encoding of UTF-8).

* `panel_list(side, buf, size)` – JSON of one panel: the folder `uri`, `cursor` (an index into `rows`) and `rows` – rows `{uri, name, dir, size}`. The service row `..` is not included.
* `panel_set_cursor(side, uri)` puts the cursor on a row; if the row is in another folder, the panel first goes there.
* `panel_select(side, mode, arg)`: `mode` 0 – select files by the mask `arg` (`*.txt`), 1 – deselect by mask, 2 – clear the whole selection, 3 – select the row `arg` (URI), 4 – deselect it.

**Clipboard and notifications.** `clipboard_get` / `clipboard_set` read and write plain text. `show_message(text, kind)` shows a pop-up notification (0 – information, 1 – warning).

**Events.** `subscribe(topic, ...)` subscribes to host events: `doc.opened` (the text is open and loaded), `doc.saved` (saving finished successfully), `doc.closed`; `doc.changed` (the text changed; arrives at most once per message loop pass), `panel.dir` (a panel changed its folder: `{"side": "left", "uri": "..."}`) and `panel.cursor` (the panel cursor is on a new row: `{"side": "left", "uri": "..."}`); the payload of document events is the JSON `{"uri": "..."}`; the topic `*` means all events. A plugin has one subscription per topic: a repeated call replaces the callback. After the plugin is unloaded it receives no events.

**Background tasks and progress.** Host functions are called only from the main thread, except one: `post_to_main(plugin_id, cb, user)` can be called from any thread, and `cb` runs in the main thread on the nearest message loop pass. This is how a plugin's background thread hands a result to the interface. `progress_set(plugin_id, id, text, percent)` shows a notification that stays on screen and is updated by `id` until `progress_end(plugin_id, id)` removes it; `percent` below 0 – no percentage. For long work that can be interrupted there is a host job (ABI 7, native plugins only): `JobBegin(plugin_id, key, title, on_cancel, user)` creates a row in the background job list and a chip in the tab bar (at the start the host shows a notification; a click on the chip opens a progress window with the Background and Cancel buttons), `JobUpdate(plugin_id, key, text, percent)` updates the text and percentage (below 0 – no percentage), `JobEnd(plugin_id, key)` removes the job. Cancelling in the job list calls `on_cancel(user)` in the main thread: the plugin sets a flag that the worker thread checks, and still calls `JobEnd` when it finishes. `on_cancel` may be `nil` – then the job cannot be cancelled. A host below ABI 7 does not provide these functions: check `AbiVersion` and `Assigned`; on an old host `progress_set` remains. After the plugin is unloaded, calls from its threads are discarded. The sample is `mtn.demo.panelkit` (Ctrl+Shift+K counts the files and the size of a folder in the background).

**Input and program state (ABI 8, native plugins only).** `SendKey(chord)` sends the program a key press as if the user had typed it (`"F5"`, `"Ctrl+Shift+K"`, `"Enter"`); `SendText(text)` enters text; `RunAction(name)` runs a keymap action by name (its first assigned key combination). All three run in the main thread and return 0 on success. `AppState(buf, size)` returns the state as JSON: `{"area":"panels|editor|viewer|terminal","doc":{...},"panels":{"active":"left","left":{"uri","cursor","cursorIsDirectory","selected":[...]},"right":{...}}}`. `SetMenuItemEnabled(plugin, itemId, 0|1)` makes a menu item unavailable (grayed) or available again. `KeyOwner(chord, buf, size)` returns the name of the keymap action or the id of the plugin command to which the key combination is already assigned (0 – free). The topic `input.key` (`Subscribe`) reports every key press as `{"key":"Ctrl+F5"}`; subscribers to `*` do not get it, and key presses that the plugin itself sent through `SendKey`/`SendText` are not published. This is how the `mtn.lua` plugin (macros in Lua) is built: `Ctrl+.` records key presses, a macro file is run by a key or from the Macros menu (the menu item parent `Macros`), and "Manage macros..." enables and disables macros, opens them for editing, assigns a key and rereads the folder.

**Text highlighting.** `register_highlighter(plugin_id, extensions, cb, user)` colors files with the listed extensions (`".json;.ini"`) in the viewer and editor. `cb(user, line, spans, cap)` receives a line in UTF-8 and writes up to `cap` spans of three `int32` each (start in bytes, length in bytes, class), and returns their number. Classes: 0 plain, 1 comment, 2 string, 3 number, 4 keyword, 5 type, 6 function, 7 operator, 8 preprocessor, 9 constant, 10 key, 11 error. The host converts bytes to characters itself, picks colors for the theme background and caches the answers by line text; a plugin has one highlighter, and a repeated call replaces the previous one. The coloring of a line does not depend on its neighbors, and the plugin does not see multi-line constructs. The sample is `mtn.demo.highlight`.

**Stateful highlighting (WASM).** Multi-line comments and strings require knowing how the previous line ended. `register_highlighter_state(ext_ptr, ext_len, export_ptr, export_len, lang)` registers such a highlighter for one language; the plugin calls it once per language, the host returns `lang` unchanged in the call, and a repeated registration of the same extensions replaces the previous one. The guest export `(line_ptr, line_len, lang, state_in, out_ptr, out_cap) -> i32` receives a line in UTF-8 and the state at the start of the line: 0 at the start of the file, otherwise the number the plugin itself returned for the previous line. At the address `out_ptr` it writes the state at the end of the line (`i32`), then up to `out_cap` spans of three `i32` each, as above, and returns the number of spans, or `-1` if it does not know `state_in` (the host starts the file over). The state is an opaque plugin number: the same parse snapshot must always get the same number while it is alive, so that equal states are equal for the host too. The host stores the state at the start of every line of the open text, resets the states from the changed line on an edit and recomputes them as drawing proceeds, for no longer than 30 ms per frame; answers are cached by the pair "state, line". Lines longer than 3500 bytes stay uncolored and do not change the state; in the streaming viewer (files over 10 MB) lines are colored with state 0. Extensions may also be a whole file name (`Makefile`). The fuel limit for one call is higher than usual because the first parse of a language compiles its regular expressions. The sample is `mtn.highlight` (Rust, the `syntect` crate).

**File system (reading).** `vfs_list(plugin_id, uri, cb, user)`, `vfs_exists(...)` and `vfs_read(plugin_id, uri, max_bytes, cb, user)` read through the same schemes as the program itself: `file:///`, archives (`...zip!/...`), `sftp://`, schemes of other plugins. The calls are asynchronous: each returns `0` (the job is started, the callback arrives exactly once), `-1` (invalid arguments) or `-2` (the plugin does not have the `vfs.read` permission, there will be no callback). The callback runs in the main thread on one of the nearest message loop passes, never from inside the call itself; a plugin unloaded before the answer does not receive it. `status` in the callback: 0 – done, 1 – not found, 2 – access denied, 3 – not supported or the file is larger than `max_bytes`, 4 – cancelled, 5 – I/O error, 6 – invalid URI. The result of `vfs_list` is the JSON `{"uri": "...", "entries": [{"name", "uri", "dir", "size", "modified"}]}` (`modified` – seconds since 1970 in local time, at most 100,000 entries); `vfs_exists` – `{"exists": true, "dir": false}`; `vfs_read` returns the whole file content (`max_bytes` 0 – 2 MB, at most 64 MB). The data in the callback is valid only for the duration of the call. In WASM the functions are called like this: `vfs_list(uri_ptr, uri_len, export_ptr, export_len)`, `vfs_exists(...)` and `vfs_read(uri_ptr, uri_len, max_bytes, export_ptr, export_len)` return a handle (greater than 0), the guest export `(handle, status)` is called on completion, after which `vfs_result(handle, out_ptr, out_cap)` returns the result: the length in bytes, with the data copied only if `length <= out_cap`, and then the handle is released; a result longer than the buffer stays for a repeated call. The sample is `mtn.demo.panelkit` (Ctrl+Shift+L shows the size and the first line of the file under the cursor, including inside an archive).

**Reading a file in parts.** A file larger than 64 MB, or one that has to be read in pieces (a video from an archive or from sftp), is opened with `vfs_open(plugin_id, uri, cb, user)`; the permission is the same, `vfs.read`. The call returns a job number (greater than 0; the callback `cb(user, status, handle)` arrives in the main thread), or `-1`, `-2` or `-3` (the plugin already has 16 files open or being opened). While the file is not open, the job can be cancelled: `vfs_cancel(job)` returns `0` (cancelled) or `-1` (there is no such job, it has already finished or belongs to someone else), and the callback still arrives once with the status 4. Cancellation matters mainly for files that are copied to a temporary file. A local file is opened in place. Any other URI (an archive, `sftp://`, a plugin scheme) is first copied by the host to a temporary file and, if the copy takes more than half a second, a notification with the copy progress is shown; the temporary copy is deleted when the file is closed. After that three calls work that can be made **from any thread**, like `post_to_main`: `vfs_size(handle)` – the size in bytes (`-1` if the handle is unknown); `vfs_read_at(handle, offset, buf, size)` – reads up to `size` bytes from the position `offset` and returns the number of bytes read, `0` at the end of the file, a negative number on error (it blocks only the calling thread, not the main one); `vfs_close(handle)` – closes the file (`0` – closed, `-1` – unknown handle), a read in another thread is finished first. The WASM host rejects a handle of another plugin; unclosed files are closed by the host when the plugin is unloaded. In WASM: `vfs_open(uri_ptr, uri_len, export_ptr, export_len)` returns a job number, the guest export `(job, status, file)` is called on completion, `file` is the handle; `vfs_cancel(job)`; `vfs_size(file)` and `vfs_read_at(file, offset_i64, out_ptr, out_cap)` return `i64`, and one call reads at most 16 MiB; `vfs_close(file)`. A WASM plugin calls them only from the main thread.

**Replacing built-in editor features.** A hook on the action `EditorSave`, `DocClose`, `DocViewEdit` and others (section 2), together with the document calls, lets a plugin change how a built-in command works: an `EditorSave` hook can bring the text to the needed form (strip trailing spaces, add a final line break) and return 0, after which saving continues with the new text; the answer 1 cancels saving. The sample is `mtn.demo.texttools`.

**Key combinations.** For your own commands use F1–F12 with modifiers or `Ctrl+Shift+letter`. `Ctrl+Alt+letter` in text fields (the editor, the command line) is treated as the input of a layout character (AltGr) and does not reach the plugin command; a combination already taken by a built-in action stays with it.

---

### 2.6. Plugin permissions

Some host calls require a permission. The plugin names the rights it needs in the manifest (`"permissions": ["vfs.read"]`), and the user grants them in **Options → Plugins...**: the Permissions... button opens a dialog with a checkbox for each right of the plugin (and for replacing built-in handlers, if the plugin asks for it). The state is stored in `plugin-permissions.json` in the settings folder; in the plugin row it is shown as `[needs vfs.read: on]` or `[needs vfs.read: off]`, and in Info it is listed in words. A call that needs a permission is rejected until it is named in the manifest and granted by the user; the plugin gets a refusal (`-2` for file calls) and can explain what to do.

| Permission | What it opens |
|---|---|
| `vfs.read` | `vfs_list`, `vfs_exists`, `vfs_read`, `vfs_open`, `vfs_cancel`, `vfs_size`, `vfs_read_at`, `vfs_close`: browsing folders and reading files on any drive, in an archive, on sftp |

The other host calls (document, panels, clipboard, surfaces, highlighting) need no permission. The check relies on the plugin identifier that the plugin itself passes in the call; a native DLL runs in the program process with its rights, so permissions keep an honest plugin within its declared limits and show the user what it wants, but they do not isolate hostile code. The only reliable limit is a WASM plugin: it has no other path to the host than the `mtn_host` imports.

---

### 2.7. Plugin languages

The interface language is set by the host; the plugin does not choose it. The current language is the `language` field of the `host_info` answer (`en`, `ru`, `de`, ...); the program settings folder is the `configDir` field of the same answer; when the language changes, the host publishes the `language.changed` event with the JSON `{"language":"ru"}` (subscribe through `Subscribe` / `subscribe`), and the plugin can rebuild the captions already shown.

The plugin's texts are in English in the code itself, and translations are in packs next to the plugin:

```
plugins\<id>\resource\<language>\locale.json    {"version": N, "name": "Русский"}
plugins\<id>\resource\<language>\strings.json   key -> text (nested objects are read as dotted keys)
plugins\<id>\resource\<language>\help\<file from "help">
```

The plugin gets a translation from the host: `Translate(plugin_id, key, default, buf, size)` in native ABI 3 or `translate(key_ptr, key_len, def_ptr, def_len, out_ptr, out_cap)` in WASM. The result is the text from `strings.json` for the current language, or `default` if the language is English or the pack or key is missing. The text result is returned the same way as for `host_info`. The `Translate` field exists only in ABI 3: on an older host it must be checked with `Assigned`.

Pack version. The manifest field `resources` is the number of the key set the plugin was written for; `version` in the pack's `locale.json` is compared with it. If they match, the pack is applied; if it is older, it is applied and missing keys stay in English; if it is newer than the plugin or there is no `locale.json`, the pack is ignored. Without `resources` any pack fits. A new language is added by copying the folder `resource\<language>\` into the plugin folder without rebuilding.

### 2.8. VFS scheme version 2

`RegisterVfsSchemeV2(plugin_id, scheme, callbacks, user_data, priority)` takes `TVfsCallbacksCdeclV2` (`uPluginHostAbi.pas`). The calls are synchronous and run in a host worker thread; one call does not block the others, so the plugin protects its own state.

For each call the host passes an operation context `PVfsOpContext`, valid until the call returns:

| Field | What it does |
|---|---|
| `ReportProgress(ctx, done, total, item_done, item_total, name)` | Operation progress: `done`/`total` – the whole operation (`total` 0 – the size is unknown), `item_*` – the current file, `name` – its name. The host shows the progress in the job window, no more often than once per 80 ms. Returns 1 if the user cancelled the operation |
| `IsCancelled(ctx)` | 1 – the user cancelled; the plugin stops working and returns `verCancelled` |
| `SetErrorText(ctx, text)` | A text (UTF-8) that the host shows with the error instead of the standard one |

Features of the version 2 table:

* `ListDirectory(uri, user, ctx, offset, buf, size, &negotiated, &more)` returns entries starting from number `offset` (a JSON array, as in version 1) and sets `more` = 1 while entries remain. The host calls it again with `offset` increased by the number of accepted entries; the plugin keeps the list for the duration of one operation. An entry may contain `unixMode` (file permissions, for example 493 for 0755).
* If the result did not fit in the buffer (4 MB), the plugin returns `verNeedsBiggerBuffer` and the needed size in `negotiated`; the host repeats the call with a buffer of that size (up to 256 MB).
* `CopyItem` / `MoveItem` receive `flags`: bit 0 – overwrite, bit 1 – preserve time. One side of a copy is always a local `file://` path unless both sides belong to this plugin. The plugin copies folders as a whole when writing to its scheme; when reading from it, the host walks the tree itself and calls `CopyItem` for each file. Copying and moving between different plugins, or between a plugin and `sftp://`, is done by the host through a temporary local copy; moving between a plugin and a local folder is a copy followed by deleting the source.
* Result codes: the codes of version 1 are extended with `verCancelled` (8), `verAuthFailed` (9, "access denied" with the plugin's text) and `verTimeout` (10, an I/O error).

**Addresses.** A scheme that the host does not know itself is treated as a folder tree of the form `scheme://node/path`: a POSIX path, without percent-encoding; an empty node (`scheme:///`) is the scheme root. The parent of `scheme://node/` is `scheme:///`; the root has no parent. This gives the plugin going up, address comparison and the tab title without its own code. Addresses with a nested archive (`!/`) follow the archive rules.

## 3. Replacing a built-in handler

The VFS registry sorts handlers by priority (smaller – earlier). A plugin without permission always gets a priority of at least 60 and therefore does not outrun the built-in ones: `find` (10), `sys` / `recycle` / `ws` / `sftp` (15), the `!/` zip chain (20), the extensions `.zip` / `.jar` / `.apk` (50). The schemes `file`, `sys`, `recycle`, `find` and `ws` cannot be replaced at all.

To replace `sftp://` or Enter on `.zip`:

1. The plugin lists the keys in `overrides` of the manifest and registers the scheme (for an archive extension – also `archiveExtensions`).
2. The user allows the replacement in **Options → Plugins...** (the Permissions... button, the replace checkbox; the plugin row is marked `[replaces ...: on]`) or adds the plugin identifier to `plugins\overrides.json` by hand:

```json
{ "allow": ["mtn.example"] }
```

3. After a restart the plugin is loaded at startup, its registrations get a priority of at most 5, and the built-in handler gives way. Unloading the plugin removes the permission and brings back the built-in handler.

An example from the distribution: `mtn.7z` declares `"overrides": [".zip"]` and the extension `zip`. By default `.zip` is opened by the built-in module; after `{"allow": ["mtn.7z"]}`, Enter on a `.zip` leads to `7z:///<path>!/` and the archive is served by `7z.dll` (AES-encrypted archives, rare compression methods). The replacement concerns entering by Enter: paths like `file:///x.zip!/` (Ctrl+PgDn, docx and the like) are still served by the built-in zip.

---

## 4. Disabling a plugin

In **Options → Plugins...** each plugin is marked `[x]` (on) or `[ ]` (off). Space on a row switches the plugin on and off; the choice is applied with the OK button (the plugin is unloaded or loaded), and Cancel discards it. The choice is stored in `disabled-plugins.json` in the settings folder. A disabled plugin is not loaded either at startup or by lazy triggers.

The order in the list is the load order. Ctrl+Up and Ctrl+Down move the selected plugin; the order is stored in `plugin-order.json` in the settings folder (plugins missing from the file come after the listed ones, in folder order). The order matters when several plugins have the same priority: the command hook, open provider or scheme handler of the plugin loaded earlier is asked first. Plugins that are not loaded yet follow the new order immediately; already loaded ones keep their registrations until the next start. The priority that a plugin names at registration (`priority`) is stronger than the load order.

Samples in different languages are in `samples\plugins` (see §5); a working sample that uses almost all extension points is `src/tests/plugins/SamplePlugin.dpr`.

---

## 5. Plugin samples

The `samples` folder is not part of the normal build. `samples\build-samples.ps1` builds the samples for which a toolchain was found into `samples\.build`; with the `-Install` switch it copies them to `bin\plugins`. The C header of the ABI is `samples\include\mtn_plugin.h`.

| Plugin | Language and build | What it shows |
|---|---|---|
| `mtn.demo.cpp` | C++, MSVC | `Copy` / `Move` / `Delete` hooks that only count operations, a status segment, a command with a dialog on Ctrl+Alt+F10 |
| `mtn.demo.video` | C++, MSVC | An open provider for video files: F3 plays the file in a viewer tab (Media Foundation, sound through waveOut); Space – pause, arrows – seek by 10 seconds; a surface with a timer |
| `mtn.demo.img` | Rust, the `image` crate | An open provider for pictures: F3 shows the file in a viewer tab (EXIF rotation, wheel zoom, dragging, rotation with `r`, full screen with `f`), arrows browse the folder; Ctrl+Shift+V shows the picture under the cursor in the other panel, Ctrl+Shift+Y rotates it; surface modes, mouse, panel events |
| `mtn.demo.highlight` | Rust | Highlighting of JSON, INI and similar files (strings, numbers, constants, keys, sections, comments) in the viewer and editor; `register_highlighter` |
| `mtn.demo.nativeview` | C++, MSVC | Ctrl+Shift+G opens a tab whose area is the plugin's own window (GDI animation); `surface_open_ex` with the own-window flag and `surface_native_handle` |
| `mtn.demo.texttools` | C++, MSVC | Editor tools: selection case, sorting and removing duplicate lines (Ctrl+Shift+U / L / S / R), "tidy on save" (Ctrl+Shift+T) through the `EditorSave` hook; the document API, `show_message`, a setting |
| `mtn.demo.panelkit` | Rust, serde_json | Copying the full paths of the selected files to the clipboard (Ctrl+Shift+P), showing the active panel folder in the other panel (Ctrl+Shift+M), selecting files with the same extension (Ctrl+Shift+X), counting the files and size of a folder in a background thread with progress (Ctrl+Shift+K), reading the file under the cursor through the host (Ctrl+Shift+L, the `vfs.read` permission), a checksum of a file of any size and from any scheme: a thread reads it in parts through `vfs_open`, `vfs_read_at` and `vfs_close`, and a repeated press cancels the opening through `vfs_cancel` or the reading (Ctrl+Shift+H), a notification on the `doc.saved` event; the panel API, clipboard, events, background tasks, file system reading and permissions |
| `mtn.demo.wc` | Go, `GOOS=wasip1`, `wasi` | A counter of lines, words and characters of the selection or document (Ctrl+Shift+E); the document API from a WASM module |
| `mtn.demo.rs` | Rust, cargo (DLL) | An open provider: F3 on a `.csv` shows an aligned table (a redirect to a temporary file) |
| `mtn.demo.go` | Go, cgo (needs a 64-bit gcc), `keepLoaded` | An open provider: F3 on a `.json` shows formatted JSON; a command with a dialog on Ctrl+Alt+F9; an indent width setting |
| `mtn.demo.go.wasm` | Go, `GOOS=wasip1`, `wasi` | "Safe delete": hooks block `DeletePermanent` and `Wipe` and explain the reason in a dialog |
| `mtn.demo.pas` | Delphi, dcc64 | Quick notes: a command on Ctrl+Alt+F8 opens a dialog with an input field and appends a line to `mtn2-notes.txt` (the file is chosen in the plugin settings) |
| `mtn.demo.wat` | WAT (WebAssembly text) | A minimal WASM plugin: a counter in the status, a command on Ctrl+Alt+F7 |
| `mtn.template.rs` | Rust, `wasm32-unknown-unknown` | A starting point for your own WASM plugin: `no_std`, no WASI, a counter in the status on Ctrl+Alt+F6; copy it whole and rename it |

On Linux the samples are built by `samples/build-samples.sh` (see `samples/README.md`): a native plugin there is a `.so`, placed in the same folder `plugins/<id>/` next to the manifest.

The `TestSamplePlugins` tests load the built samples with the real loader; a sample that is not built is skipped.

---

## 6. Reliability

* An exception in a handler, hook or provider counts as a refusal: the built-in behavior is executed.
* A native plugin runs in the MTN2 process and is not isolated; a failure in its code can bring the application down. A WASM plugin is isolated: a trap, an out-of-memory access and running out of fuel do not affect the host.
* On unloading, the host removes the plugin's registrations (VFS, menus, commands, hooks, providers, captions, segments, dialog answers) before freeing the module.

---

## 7. Community plugins

A list of plugins written by people other than the MTN2 authors. There is no registry with installation from the interface: a plugin is installed by copying the folder `plugins\<id>\` next to the program, and questions about a plugin go to its author.

| Plugin | Author | What it does | Kind | Link |
|---|---|---|---|---|
| – | – | There are no plugins in the list yet | – | – |

A native plugin (DLL, `.so`) runs in the MTN2 process with the user's rights and is not isolated, so install such plugins only from authors you trust, and check the permissions in **Options → Plugins...**. A WASM plugin is isolated: it has no access to the host except the `mtn_host` imports and the granted permissions.

To add a plugin to the list, open a pull request with a row in the table. The following are required:

* a public repository with the source code and a license;
* `plugin.json` with `id`, `abi`, a description in English and Russian, and help;
* builds for the platforms the plugin declares (DLL, `.so`, `.wasm`) and build instructions;
* the list of rights from `permissions` and an explanation of why they are needed.

Rows without source code, with an unclear license or with undocumented network access are not added to the list. Checking the plugin code amounts to a quick look: the list gives no security guarantee.
