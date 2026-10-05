// Demo plugin in C++: counts Copy / Move / Delete and shows the total in the
// status line. Ctrl+Alt+F10 (caption "Stats" in the function bar) opens a
// dialog with the counts.
//
// Shows: command hooks that only observe (they answer 0, so the built-in
// command still runs), a status-line segment, a plugin command with a key
// chord and a bar caption, and a dialog described as JSON.

#include <cstdio>
#include <string>

#include "mtn_plugin.h"

namespace {

constexpr const char *kPluginId = "mtn.demo.cpp";

const MtnHostApi *g_host = nullptr;
int g_copy = 0;
int g_move = 0;
int g_delete = 0;

void update_status() {
    char text[48];
    std::snprintf(text, sizeof(text), "Ops: %d", g_copy + g_move + g_delete);
    g_host->set_status_segment(kPluginId, "ops", text);
}

// The hook sees the command before the built-in handler; returning 0 lets the
// built-in command run as usual.
int64_t on_command(void *, const char *command, const char *origin) {
    (void)origin;
    const std::string name = command;
    if (name == "Copy") {
        ++g_copy;
    } else if (name == "Move") {
        ++g_move;
    } else if (name == "Delete") {
        ++g_delete;
    }
    update_status();
    return 0;
}

void on_dialog_answer(void *, const char *, const char *) {
    // Nothing to do: the dialog only informs.
}

void show_stats(void *) {
    char json[768];
    std::snprintf(
        json, sizeof(json),
        "{\"type\":\"dialog\",\"version\":\"2.0\",\"title\":\"Operations\","
        "\"width\":40,\"height\":10,\"children\":["
        "{\"type\":\"label\",\"text\":\"Copy:   %d\",\"col\":2,\"row\":1,\"width\":30,\"height\":1},"
        "{\"type\":\"label\",\"text\":\"Move:   %d\",\"col\":2,\"row\":2,\"width\":30,\"height\":1},"
        "{\"type\":\"label\",\"text\":\"Delete: %d\",\"col\":2,\"row\":3,\"width\":30,\"height\":1},"
        "{\"type\":\"button\",\"id\":\"ok\",\"text\":\"  OK  \",\"default\":true,\"cancel\":true,"
        "\"col\":14,\"row\":6,\"width\":10,\"height\":1}]}",
        g_copy, g_move, g_delete);
    g_host->show_dialog(kPluginId, json, on_dialog_answer, nullptr);
}

}  // namespace

extern "C" {

MTN_EXPORT int64_t mtn_plugin_get_abi_version(void) { return MTN_ABI_VERSION; }

MTN_EXPORT int64_t mtn_plugin_init(const MtnHostApi *host) {
    if (host == nullptr || host->abi_version < 2 || host->register_command_hook == nullptr ||
        host->register_command == nullptr || host->set_status_segment == nullptr ||
        host->show_dialog == nullptr) {
        return -1;
    }
    // The host keeps the table until mtn_plugin_shutdown.
    g_host = host;

    host->register_command_hook(kPluginId, "Copy", on_command, nullptr, 100);
    host->register_command_hook(kPluginId, "Move", on_command, nullptr, 100);
    host->register_command_hook(kPluginId, "Delete", on_command, nullptr, 100);

    host->register_command(kPluginId, "demo.cpp.stats", show_stats, nullptr);
    host->register_key_binding(kPluginId, "demo.cpp.stats", "Ctrl+Alt+F10");
    host->set_command_caption(kPluginId, "demo.cpp.stats", "Stats");
    return 0;
}

MTN_EXPORT void mtn_plugin_shutdown(void) { g_host = nullptr; }

}  // extern "C"
