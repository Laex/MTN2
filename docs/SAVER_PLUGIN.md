# Screensaver Pictures and the `mtn.screensaver` Plugin

**English** | [Русский](SAVER_PLUGIN.ru.md)

> **Role of this document:** how a screensaver picture is registered with the host, and how to write a picture as a separate library for the `mtn.screensaver` plugin.  
> **Context:** [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md); the picture, the idle time and the random choice are set in the Settings window of the plugin.

---

## 1. Parts

| Part | Where | Role |
|---|---|---|
| Registry and idle timer | `uScreenSaver.pas` (core) | Idle time, wake-up on input, the list of pictures, the chosen picture (`saverId` in `session.json`). The built-in picture is the sharks. |
| Plugin ABI | `uPluginHostAbi.pas`, `uPluginSaver.pas` | `RegisterSaver` of the host table (plugin ABI 10): any plugin can hand the host a picture as a table of cdecl callbacks. |
| `mtn.screensaver` plugin | `plugins/mtn.screensaver` | Loads the picture libraries from its `savers` folder and registers each one through `RegisterSaver`. |
| Picture library | `savers/*.dll` (Windows), `savers/*.so` (Linux) | One picture (or several, see below). |

The plugin starts with the program (`"startup": true` in its `plugin.json`), so the pictures are in the list from the first start. The host has no picture of its own: the sharks are the library `savers/SharksSaver.dpr` (built from the units of `src/ascii-sharks`), and without the plugin the screensaver does not start. Unloading the plugin removes its pictures; a running saver stops first.

## 2. Modes

| Mode | Picture draws | Where it works |
|---|---|---|
| `text` | a grid of characters, in a buffer of cells the host owns; before every call it is filled with white blanks on black | MTN2, MTN2-sdl and MTN2-tui |
| `pixels` | a bitmap of the whole window, 4 bytes per pixel in B, G, R, A order, filled with opaque black before every call | MTN2 and MTN2-sdl; MTN2-tui has no way to show a bitmap, so it does not list or use such a picture |

A picture may have both modes: it is drawn in pixels where the host can show them and in characters elsewhere. A bitmap is about 8 x 16 pixels per cell of the window, scaled down to fit 1280 x 800 and shown over the grid, which is black under it.

## 3. Library contract

All functions are `cdecl`; text is UTF-8; no pointers cross the boundary except the cell buffer of one call. An instance is told apart by an `Int64` handle, so one library can serve several instances.

| Export | Meaning |
|---|---|
| `mtn_saver_get_abi_version(): Int64` | Contract version; now `1`. |
| `mtn_saver_info(buf, size): Int64` | Writes a JSON object with `id`, `name`, `tickMs` (10..1000, default 90) and `modes` (`"text"`, `"pixels"`; default `["text"]`); returns the byte length, `-1` when it does not fit. A picture with no known mode is refused. |
| `mtn_saver_create(cols, rows, seed): Int64` | New instance; a handle above 0, `0` when it fails. |
| `mtn_saver_resize(handle, cols, rows)` | The window size changed: in cells for a text picture, in pixels for a pixel picture. |
| `mtn_saver_advance(handle, deltaMs)` | Time step. |
| `mtn_saver_draw_text(handle, cols, rows, cells): Int64` | Fills `cols x rows` cells row by row; `0` = drawn. Needed when the modes include `text`. |
| `mtn_saver_draw_pixels(handle, width, height, pixels): Int64` | Fills `width x height` pixels, rows top to bottom without padding; `0` = drawn. Needed when the modes include `pixels`. |
| `mtn_saver_destroy(handle)` | Drops the instance. |

A cell (`TSaverCell`) is four `UInt32` values: code point (one character of the basic plane, anything else is a blank), foreground and background as `$AARRGGBB`, attributes (1 bold, 2 italic, 4 underline, 8 reverse).

A picture that raises an error or returns a failure leaves a black screen until the next key press.

## 4. Building a picture

`savers/StarfieldSaver.dpr` (text) and `savers/PlasmaSaver.dpr` (pixels) are complete examples. `src/build.ps1` compiles every `plugins/<id>/savers/*.dpr` into `<plugin folder>\savers`; `src/build-linux.ps1` does the same for `.so`. The picture's name in the list is translated through the `saver.<id>` string when the program has one.

## 5. Registering from another plugin

A plugin that is not `mtn.screensaver` can call `RegisterSaver(pluginId, id, caption, modes, callbacks, userData)` of the host table directly. `modes` is `1` (text), `2` (pixels) or both; the callbacks are `TickMs`, `Prepare`, `Advance`, `Finish`, `Draw` (needed for text) and `DrawPixels` (needed for pixels), see `TSaverCallbacks`. The host copies the table. Registering an id again replaces the picture.

## Settings dialog

The "Settings" button of the plugin in the plugins dialog opens a window with the picture, the idle time and a "Random screensaver" check box that picks one of the pictures at random at every start. The plugin reads and writes them through two functions at the end of the host table: `SaverGetSettings(buf, size)` fills `buf` with a JSON object (`saverId`, `random`, `minutes`, `minuteChoices`, `savers` with `id` and `caption`) and returns its length (`-2` = the buffer is too small); `SaverSetSettings(id, minutes, random)` sets the picture (`''` = keep), the idle minutes (`-1` = keep) and the random flag (`1`/`0`, `-1` = keep) and returns `0`, or `-1` without changing anything when the picture is unknown or the minutes are not one of the choices.
