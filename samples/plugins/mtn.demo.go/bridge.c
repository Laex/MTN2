#include "bridge.h"

#include "mtn_plugin.h"

static const MtnHostApi *g_host;
static const char kId[] = "mtn.demo.go";

static int64_t document_cb(void *user, const char *uri, const char *mode, char *redirect,
                           int64_t cap) {
    (void)user;
    return goOnDocument((char *)uri, (char *)mode, redirect, cap);
}

static void info_cb(void *user) {
    (void)user;
    goShowInfo();
}

static void dialog_cb(void *user, const char *control_id, const char *values_json) {
    (void)user;
    (void)control_id;
    (void)values_json;
}

static void settings_answer_cb(void *user, const char *control_id, const char *values_json) {
    (void)user;
    goSettingsAnswer((char *)control_id, (char *)values_json);
}

static void configure_cb(void *user) {
    (void)user;
    goConfigure();
}

int64_t bridgeShowSettingsDialog(const char *json) {
    return g_host != 0 ? g_host->show_dialog(kId, json, settings_answer_cb, 0) : -1;
}

int64_t bridgeGetSetting(const char *key, char *buf, int64_t size) {
    return g_host != 0 ? g_host->get_setting(kId, key, buf, size) : -1;
}

int64_t bridgeSetSetting(const char *key, const char *value) {
    return g_host != 0 ? g_host->set_setting(kId, key, value) : -1;
}

void bridgeSetStatus(const char *text) {
    if (g_host != 0) {
        g_host->set_status_segment(kId, "state", text);
    }
}

int64_t bridgeShowDialog(const char *json) {
    return g_host != 0 ? g_host->show_dialog(kId, json, dialog_cb, 0) : -1;
}

MTN_EXPORT int64_t mtn_plugin_get_abi_version(void) { return MTN_ABI_VERSION; }

MTN_EXPORT int64_t mtn_plugin_init(const MtnHostApi *host) {
    if (host == 0 || host->abi_version < 2 || host->register_document_provider == 0 ||
        host->register_command == 0 || host->show_dialog == 0 ||
        host->set_status_segment == 0 || host->register_settings == 0 ||
        host->get_setting == 0 || host->set_setting == 0) {
        return -1;
    }
    g_host = host;
    // F3 on a .json file: pretty-printed text in the built-in viewer.
    host->register_document_provider(kId, ".json", 1, document_cb, 0, 100);
    host->register_command(kId, "demo.go.info", info_cb, 0);
    host->register_key_binding(kId, "demo.go.info", "Ctrl+Alt+F9");
    host->set_command_caption(kId, "demo.go.info", "GoInfo");
    host->register_settings(kId, configure_cb, 0);
    return 0;
}

MTN_EXPORT void mtn_plugin_shutdown(void) { g_host = 0; }
