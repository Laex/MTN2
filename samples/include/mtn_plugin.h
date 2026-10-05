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
} MtnHostApi;

/* Entry points every plugin DLL exports. */
MTN_EXPORT int64_t mtn_plugin_get_abi_version(void);
MTN_EXPORT int64_t mtn_plugin_init(const MtnHostApi *host); /* 0 = success */
MTN_EXPORT void mtn_plugin_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* MTN_PLUGIN_H */
