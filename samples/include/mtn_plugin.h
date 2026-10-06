/* MTN2 native plugin ABI (version 2) for C and C++.
 *
 * Mirrors THostApiTable in src/Core/uPluginHostAbi.pas. The table only grows at
 * the end: a plugin built against ABI 2 must check a field for NULL before
 * calling it if it should also run on an older host. All strings are UTF-8,
 * every function uses the C calling convention, all calls come from the main
 * thread. See docs/PLUGIN_DEVELOPMENT.md. */
#ifndef MTN_PLUGIN_H
#define MTN_PLUGIN_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MTN_ABI_VERSION 2

#ifdef _WIN32
#define MTN_EXPORT __declspec(dllexport)
#else
#define MTN_EXPORT __attribute__((visibility("default")))
#endif

/* Callbacks the plugin hands to the host. */
typedef void (*mtn_command_cb)(void *user);
/* Returns 1 when the plugin handled the command (the built-in one is skipped). */
typedef int64_t (*mtn_command_hook_cb)(void *user, const char *command, const char *origin);
/* mode is "view" or "edit". Returns 0 = not mine, 1 = handled, 2 = open the URI
 * written into redirect (NUL-terminated, at most redirect_cap bytes). */
typedef int64_t (*mtn_document_cb)(void *user, const char *uri, const char *mode,
                                   char *redirect, int64_t redirect_cap);
/* Answer of a plugin dialog: the control id that closed it and the values JSON. */
typedef void (*mtn_dialog_cb)(void *user, const char *control_id, const char *values_json);
/* Returns 1 when the plugin dealt with the row of its panel. */
typedef int64_t (*mtn_panel_activate_cb)(void *user, const char *panel_uri,
                                         const char *row_uri, int64_t is_directory);

/* Picture surface. The key is named like "Left", "Right", "Space", "Enter", "Ctrl+C", "+";
 * return 1 when the plugin used it (Esc and F10 always close the tab). */
typedef int64_t (*mtn_surface_key_cb)(void *user, const char *key);
/* Timer tick, see surface_set_timer. */
typedef void (*mtn_surface_tick_cb)(void *user);
/* The user closed the tab (not called when the plugin closed it). */
typedef void (*mtn_surface_closed_cb)(void *user);

/* A host event: "doc.opened", "doc.saved" or "doc.closed"; payload is JSON with the document "uri". */
typedef void (*mtn_event_cb)(void *user, const char *topic, const char *payload_json);

/* Mouse on a surface: kind 0 = button down, 1 = up, 2 = move while a button is held, 3 = wheel
 * (extra = clicks, positive away from the user), 4 = double click, 5 = the size of the area
 * changed (width, height); x and y are pixels from the top-left corner of the area; button 1 =
 * left, 2 = right, 3 = middle; shift is a bit set (1 Shift, 2 Ctrl, 4 Alt). Return 1 when used. */
typedef int64_t (*mtn_surface_mouse_cb)(void *user, int64_t kind, int64_t x, int64_t y, int64_t width,
                                        int64_t height, int64_t button, int64_t extra, int64_t shift);
/* Called on the main thread by post_to_main. */
typedef void (*mtn_main_cb)(void *user);
/* Colors a line (UTF-8): write up to span_cap spans of three int32 (start byte, byte length, class)
 * into spans and return how many. Classes: 0 plain, 1 comment, 2 string, 3 number, 4 keyword, 5 type,
 * 6 function, 7 operator, 8 preprocessor, 9 constant, 10 key, 11 error. */
typedef int64_t (*mtn_highlight_cb)(void *user, const char *line, int32_t *spans, int64_t span_cap);

/* File system results (permission "vfs.read"). status: 0 = ok, 1 not found, 2 access denied,
 * 3 not supported or too large, 4 cancelled, 5 I/O error, 6 invalid URI. Each callback runs once, on
 * the main thread, after the start call returned; text and data are valid only during the call. */
typedef void (*mtn_vfs_text_cb)(void *user, int64_t status, const char *json);
typedef void (*mtn_vfs_data_cb)(void *user, int64_t status, const uint8_t *data, int64_t length);

typedef struct MtnHostApi {
    int64_t abi_version;
    int64_t (*host_publish)(const char *plugin_id, const char *topic, const char *payload_json);
    int64_t (*host_invalidate)(int64_t window_id);
    void *register_vfs_scheme;   /* see TVfsCallbacksCdecl in uPluginHostAbi.pas */
    int64_t (*register_panel_plugin)(const char *plugin_id, const char *scheme, int64_t priority);
    int64_t (*register_key_binding)(const char *plugin_id, const char *action,
                                    const char *key_combo);
    int64_t (*register_menu_item)(const char *plugin_id, const char *parent_path,
                                  const char *item_id, const char *caption,
                                  void (*on_click)(void *user), void *user, int64_t priority);
    /* ABI 2 */
    int64_t (*register_command)(const char *plugin_id, const char *command_id,
                                mtn_command_cb on_run, void *user);
    int64_t (*register_command_hook)(const char *plugin_id, const char *command,
                                     mtn_command_hook_cb hook, void *user, int64_t priority);
    int64_t (*execute_command)(const char *command_id);
    int64_t (*register_document_provider)(const char *plugin_id, const char *extensions,
                                          int64_t modes /* 1 = view, 2 = edit */,
                                          mtn_document_cb handler, void *user, int64_t priority);
    int64_t (*open_external)(const char *uri);
    int64_t (*show_dialog)(const char *plugin_id, const char *decl_json,
                           mtn_dialog_cb on_command, void *user);
    int64_t (*register_panel_activate)(const char *plugin_id, const char *scheme,
                                       mtn_panel_activate_cb handler, void *user);
    int64_t (*set_command_caption)(const char *plugin_id, const char *command_id,
                                   const char *caption);
    int64_t (*set_status_segment)(const char *plugin_id, const char *segment_id,
                                  const char *text);
    /* The Plugins dialog calls on_configure when the user presses Settings. */
    int64_t (*register_settings)(const char *plugin_id, mtn_command_cb on_configure, void *user);
    /* Value length in bytes (a NUL is written too); -1 = never set, -2 = buffer too small. */
    int64_t (*get_setting)(const char *plugin_id, const char *key, char *buf, int64_t buf_size);
    /* 0 = stored, -1 = the settings file could not be written. */
    int64_t (*set_setting)(const char *plugin_id, const char *key, const char *value);
    /* Picture surface: a viewer tab whose picture the plugin supplies. Check each field for
     * NULL on an older host. */
    /* Opens the tab. Returns the handle (above 0), or -1 (the host is not over the panels).
     * Any callback may be NULL. */
    int64_t (*surface_open)(const char *plugin_id, const char *title, mtn_surface_key_cb on_key,
                            mtn_surface_tick_cb on_tick, mtn_surface_closed_cb on_closed,
                            void *user);
    /* width x height pixels of 4 bytes in B, G, R, A order, rows top to bottom without padding,
     * length bytes in all. The host copies them, fits and centers the picture. 0 = shown. */
    int64_t (*surface_set_frame)(int64_t handle, int64_t width, int64_t height,
                                 const uint8_t *pixels, int64_t length);
    /* Tab title and status line text (either may be empty). */
    int64_t (*surface_set_info)(int64_t handle, const char *title, const char *status);
    /* on_tick every interval_ms milliseconds while the tab is on screen; 0 stops it. */
    int64_t (*surface_set_timer)(int64_t handle, int64_t interval_ms);
    /* Closes the tab; no callback follows. */
    int64_t (*surface_close)(int64_t handle);
    /* Functions that return text (host_info, doc_info, doc_get_text, panel_info, clipboard_get):
     * the result is the length of the UTF-8 text in bytes; the text and a NUL are written to buf
     * only when length < buf_size, so a result >= buf_size means "call again with a bigger
     * buffer" (a NULL buf measures). -1 = not available. */
    int64_t (*host_info)(char *buf, int64_t buf_size);      /* JSON: version, language */
    int64_t (*doc_info)(char *buf, int64_t buf_size);       /* JSON about the active text document */
    /* what: 0 = selection (empty when none), 1 = the whole document with LF breaks, 2 = cursor line. */
    int64_t (*doc_get_text)(int64_t what, char *buf, int64_t buf_size);
    /* Replaces that text as one undo step (0 with no selection inserts at the cursor). 0 = done. */
    int64_t (*doc_replace)(int64_t what, const char *text);
    int64_t (*doc_set_cursor)(int64_t row, int64_t col);    /* 0-based */
    int64_t (*panel_info)(char *buf, int64_t buf_size);     /* JSON about both file panels */
    /* side: 0 = left, 1 = right, -1 = the active panel. */
    int64_t (*panel_goto)(int64_t side, const char *uri);
    int64_t (*panel_refresh)(void);
    int64_t (*clipboard_get)(char *buf, int64_t buf_size);
    int64_t (*clipboard_set)(const char *text);
    int64_t (*show_message)(const char *text, int64_t kind); /* 0 = information, 1 = warning */
    /* Calls on_event for the events of topic ("*" = all). */
    int64_t (*subscribe)(const char *plugin_id, const char *topic, mtn_event_cb on_event, void *user);
    /* Panels. side: 0 = left, 1 = right, -1 = active. panel_list is JSON: "uri" of the folder, "cursor"
     * (index in "rows"), "rows" of {uri, name, dir, size}. */
    int64_t (*panel_list)(int64_t side, char *buf, int64_t buf_size);
    /* Cursor of a panel onto the row uri (a row of another folder: the panel goes there first). */
    int64_t (*panel_set_cursor)(int64_t side, const char *uri);
    /* mode: 0 = select the files matching the mask arg ("*.txt"), 1 = unselect them, 2 = clear,
     * 3 = select the row arg (URI), 4 = unselect it. */
    int64_t (*panel_select)(int64_t side, int64_t mode, const char *arg);
    /* Selection from (row1, col1) to (row2, col2), 0-based; the cursor goes to the end. */
    int64_t (*doc_set_selection)(int64_t row1, int64_t col1, int64_t row2, int64_t col2);
    int64_t (*doc_line)(int64_t index, char *buf, int64_t buf_size);
    /* The only host function that may be called from any thread: runs cb on the main thread. */
    int64_t (*post_to_main)(const char *plugin_id, mtn_main_cb cb, void *user);
    /* A notice that stays until progress_end (main thread only); percent below 0 = none. */
    int64_t (*progress_set)(const char *plugin_id, const char *id, const char *text, int64_t percent);
    int64_t (*progress_end)(const char *plugin_id, const char *id);
    /* mode: 0 = a tab, 1 = a full-screen tab, 2 = the panel opposite the active one (like Quick View);
     * add 256 for a native window (see surface_native_handle) instead of drawn frames. */
    int64_t (*surface_open_ex)(const char *plugin_id, const char *title, int64_t mode,
                               mtn_surface_key_cb on_key, mtn_surface_tick_cb on_tick,
                               mtn_surface_closed_cb on_closed, mtn_surface_mouse_cb on_mouse, void *user);
    int64_t (*surface_set_fullscreen)(int64_t handle, int64_t on);
    /* HWND of a native surface (0 for the others). The host keeps it over the area, hides it under
     * dialogs and menus and resizes the windows inside it to fill it. */
    int64_t (*surface_native_handle)(int64_t handle);
    /* Colors the text of files with these extensions (".json;.ini") in the viewer and editor. */
    int64_t (*register_highlighter)(const char *plugin_id, const char *extensions, mtn_highlight_cb handler,
                                    void *user);
    /* File system, read only. The plugin asks for the permission in its plugin.json
     * ("permissions": ["vfs.read"]) and the user grants it in Plugins - Permissions. Each call returns
     * 0 (started, the callback follows), -1 (bad arguments) or -2 (no permission; no callback). Any
     * URI works: file:///, archives, sftp://, schemes of other plugins. Main thread only. */
    /* JSON: "uri" and "entries" of {name, uri, dir, size, modified (seconds since 1970)}. */
    int64_t (*vfs_list)(const char *plugin_id, const char *uri, mtn_vfs_text_cb done, void *user);
    /* JSON: {"exists": bool, "dir": bool}. */
    int64_t (*vfs_exists)(const char *plugin_id, const char *uri, mtn_vfs_text_cb done, void *user);
    /* Reads a whole file of at most max_bytes (0 = 2 MB, at most 64 MB). */
    int64_t (*vfs_read)(const char *plugin_id, const char *uri, int64_t max_bytes, mtn_vfs_data_cb done,
                        void *user);
} MtnHostApi;

/* Entry points every plugin DLL exports. */
MTN_EXPORT int64_t mtn_plugin_get_abi_version(void);
MTN_EXPORT int64_t mtn_plugin_init(const MtnHostApi *host); /* 0 = success */
MTN_EXPORT void mtn_plugin_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* MTN_PLUGIN_H */
