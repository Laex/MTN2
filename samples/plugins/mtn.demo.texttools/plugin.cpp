// Demo plugin in C++: text tools for the editor and viewer.
//
//   Ctrl+Shift+U  upper-case the selection        Ctrl+Shift+L  lower-case the selection
//   Ctrl+Shift+S  sort the lines (selection, or the whole document when nothing is selected)
//   Ctrl+Shift+R  remove repeated lines (selection or the whole document)
//   Ctrl+Shift+T  switch "tidy on save" on or off
//
// "Tidy on save" hooks the editor's own Save command: before the built-in save runs, the
// plugin strips trailing blanks and makes the text end with a line break.
//
// Shows: the document API (doc_get_text, doc_replace, doc_info, doc_set_cursor), a hook that
// changes what a built-in editor command works on, show_message and plugin settings.

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <cwchar>
#include <cwctype>
#include <locale.h>
#include <wctype.h>
#endif

#include <algorithm>
#include <cstdlib>
#include <string>
#include <unordered_set>
#include <vector>

#include "mtn_plugin.h"

namespace {

constexpr const char *kPluginId = "mtn.demo.texttools";

const MtnHostApi *g_host = nullptr;
bool g_tidy_on_save = false;

#ifdef _WIN32

std::wstring widen(const std::string &text) {
    if (text.empty()) {
        return L"";
    }
    const int len = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring out(len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), &out[0], len);
    return out;
}

std::string narrow(const std::wstring &text) {
    if (text.empty()) {
        return "";
    }
    const int len = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0,
                                        nullptr, nullptr);
    std::string out(len, '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), &out[0], len, nullptr, nullptr);
    return out;
}

void change_case(std::wstring &wide, bool upper) {
    LCMapStringEx(LOCALE_NAME_USER_DEFAULT, upper ? LCMAP_UPPERCASE : LCMAP_LOWERCASE, wide.data(),
                  static_cast<int>(wide.size()), &wide[0], static_cast<int>(wide.size()), nullptr, nullptr, 0);
}

// Case-insensitive, by the rules of the user's language (Cyrillic sorts as expected).
bool line_less(const std::wstring &a, const std::wstring &b) {
    return CompareStringEx(LOCALE_NAME_USER_DEFAULT, LINGUISTIC_IGNORECASE, a.c_str(), -1, b.c_str(), -1,
                           nullptr, nullptr, 0) == CSTR_LESS_THAN;
}

#else

// wchar_t is a UTF-32 code point here. The user's locale is a private locale_t, so the
// plugin never changes the locale of the host process.
locale_t user_locale() {
    static locale_t loc = [] {
        locale_t l = newlocale(LC_ALL_MASK, "", nullptr);
        return l ? l : newlocale(LC_ALL_MASK, "C.UTF-8", nullptr);
    }();
    return loc;
}

std::wstring widen(const std::string &text) {
    std::wstring out;
    for (size_t i = 0; i < text.size();) {
        const unsigned char c = static_cast<unsigned char>(text[i]);
        size_t extra = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : c >= 0xC0 ? 1 : 0;
        // A cut-off sequence is taken as the single byte it starts with.
        if (i + extra >= text.size()) {
            extra = 0;
        }
        unsigned long cp = extra == 0 ? c : (c & (0x3Fu >> extra));
        for (size_t k = 1; k <= extra; ++k) {
            cp = (cp << 6) | (static_cast<unsigned char>(text[i + k]) & 0x3F);
        }
        out.push_back(static_cast<wchar_t>(cp));
        i += 1 + extra;
    }
    return out;
}

std::string narrow(const std::wstring &text) {
    std::string out;
    for (wchar_t w : text) {
        const unsigned long cp = static_cast<unsigned long>(w);
        if (cp < 0x80) {
            out += static_cast<char>(cp);
        } else if (cp < 0x800) {
            out += static_cast<char>(0xC0 | (cp >> 6));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out += static_cast<char>(0xE0 | (cp >> 12));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            out += static_cast<char>(0xF0 | (cp >> 18));
            out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        }
    }
    return out;
}

void change_case(std::wstring &wide, bool upper) {
    for (wchar_t &c : wide) {
        c = static_cast<wchar_t>(upper ? towupper_l(c, user_locale()) : towlower_l(c, user_locale()));
    }
}

std::wstring folded(const std::wstring &text) {
    std::wstring out = text;
    change_case(out, false);
    return out;
}

// Case-insensitive, by the collation of the user's locale.
bool line_less(const std::wstring &a, const std::wstring &b) {
    return wcscoll_l(folded(a).c_str(), folded(b).c_str(), user_locale()) < 0;
}

#endif

// Reads text through one of the "text out" functions of the host API, growing the buffer as asked.
template <class Fn>
bool read_text(Fn call, std::string &out) {
    std::vector<char> buf(4096);
    for (int attempt = 0; attempt < 3; ++attempt) {
        const int64_t n = call(buf.data(), static_cast<int64_t>(buf.size()));
        if (n < 0) {
            return false;
        }
        if (n < static_cast<int64_t>(buf.size())) {
            out.assign(buf.data(), static_cast<size_t>(n));
            return true;
        }
        buf.resize(static_cast<size_t>(n) + 1);
    }
    return false;
}

bool doc_text(int64_t what, std::string &out) {
    return read_text([what](char *b, int64_t n) { return g_host->doc_get_text(what, b, n); }, out);
}

// "row":N or "col":N of the doc_info JSON (plain numbers, no escaping involved).
int json_int(const std::string &json, const char *key) {
    const std::string needle = std::string("\"") + key + "\":";
    const size_t at = json.find(needle);
    return at == std::string::npos ? 0 : std::atoi(json.c_str() + at + needle.size());
}

void say(const std::string &text, int kind = 0) { g_host->show_message(text.c_str(), kind); }

// Selection when there is one, otherwise the whole document; what tells which it was.
bool selection_or_all(std::string &text, int64_t &what) {
    what = 0;
    if (!doc_text(0, text)) {
        say("Open a text file in the viewer or editor first.", 1);
        return false;
    }
    if (text.empty()) {
        what = 1;
        if (!doc_text(1, text)) {
            return false;
        }
    }
    return true;
}

bool replace_or_explain(int64_t what, const std::string &text) {
    if (g_host->doc_replace(what, text.c_str()) != 0) {
        say("The document is read-only here: press F4 to edit it.", 1);
        return false;
    }
    return true;
}

void map_case(bool upper) {
    std::string text;
    if (!doc_text(0, text)) {
        say("Open a text file in the viewer or editor first.", 1);
        return;
    }
    if (text.empty()) {
        say("Select some text first.", 1);
        return;
    }
    std::wstring wide = widen(text);
    change_case(wide, upper);
    replace_or_explain(0, narrow(wide));
}

std::vector<std::string> split_lines(const std::string &text) {
    std::vector<std::string> lines;
    size_t start = 0;
    for (;;) {
        const size_t at = text.find('\n', start);
        if (at == std::string::npos) {
            lines.push_back(text.substr(start));
            return lines;
        }
        lines.push_back(text.substr(start, at - start));
        start = at + 1;
    }
}

std::string join_lines(const std::vector<std::string> &lines) {
    std::string out;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (i > 0) {
            out += '\n';
        }
        out += lines[i];
    }
    return out;
}

void sort_lines() {
    std::string text;
    int64_t what;
    if (!selection_or_all(text, what)) {
        return;
    }
    std::vector<std::pair<std::wstring, std::string>> keyed;
    for (const std::string &line : split_lines(text)) {
        keyed.emplace_back(widen(line), line);
    }
    std::stable_sort(keyed.begin(), keyed.end(),
                     [](const auto &a, const auto &b) { return line_less(a.first, b.first); });
    std::vector<std::string> lines;
    for (auto &entry : keyed) {
        lines.push_back(std::move(entry.second));
    }
    if (replace_or_explain(what, join_lines(lines))) {
        say("Sorted " + std::to_string(lines.size()) + " lines");
    }
}

void remove_repeats() {
    std::string text;
    int64_t what;
    if (!selection_or_all(text, what)) {
        return;
    }
    std::unordered_set<std::string> seen;
    std::vector<std::string> kept;
    size_t total = 0;
    for (const std::string &line : split_lines(text)) {
        ++total;
        if (seen.insert(line).second) {
            kept.push_back(line);
        }
    }
    if (kept.size() == total) {
        say("No repeated lines");
        return;
    }
    if (replace_or_explain(what, join_lines(kept))) {
        say("Removed " + std::to_string(total - kept.size()) + " repeated lines");
    }
}

void toggle_tidy() {
    g_tidy_on_save = !g_tidy_on_save;
    g_host->set_setting(kPluginId, "tidyOnSave", g_tidy_on_save ? "1" : "0");
    g_host->set_status_segment(kPluginId, "tidy", g_tidy_on_save ? "Tidy on save" : "");
    say(g_tidy_on_save ? "Tidy on save: on" : "Tidy on save: off");
}

// Strips trailing blanks of every line and makes the text end with a line break (an empty last line).
std::string tidy(const std::string &text) {
    std::vector<std::string> lines = split_lines(text);
    for (std::string &line : lines) {
        const size_t end = line.find_last_not_of(" \t\r");
        line.erase(end == std::string::npos ? 0 : end + 1);
    }
    if (!lines.empty() && !lines.back().empty()) {
        lines.push_back("");
    }
    return join_lines(lines);
}

// Runs before the built-in Save of the editor; answering 0 lets the save go on with the tidied text.
int64_t on_editor_save(void *, const char *, const char *) {
    if (!g_tidy_on_save) {
        return 0;
    }
    std::string info, text;
    if (!read_text([](char *b, int64_t n) { return g_host->doc_info(b, n); }, info) || !doc_text(1, text)) {
        return 0;
    }
    const std::string tidy_text = tidy(text);
    if (tidy_text == text) {
        return 0;
    }
    const int row = json_int(info, "row");
    const int col = json_int(info, "col");
    if (g_host->doc_replace(1, tidy_text.c_str()) == 0) {
        g_host->doc_set_cursor(row, col);
    }
    return 0;
}

void cmd_upper(void *) { map_case(true); }
void cmd_lower(void *) { map_case(false); }
void cmd_sort(void *) { sort_lines(); }
void cmd_repeats(void *) { remove_repeats(); }
void cmd_tidy(void *) { toggle_tidy(); }

void add_command(const char *id, mtn_command_cb run, const char *chord) {
    g_host->register_command(kPluginId, id, run, nullptr);
    g_host->register_key_binding(kPluginId, id, chord);
}

}  // namespace

extern "C" {

MTN_EXPORT int64_t mtn_plugin_get_abi_version(void) { return MTN_ABI_VERSION; }

MTN_EXPORT int64_t mtn_plugin_init(const MtnHostApi *host) {
    if (host == nullptr || host->abi_version < 2 || host->doc_get_text == nullptr ||
        host->doc_replace == nullptr || host->doc_info == nullptr || host->show_message == nullptr ||
        host->register_command == nullptr || host->register_command_hook == nullptr) {
        return -1;
    }
    g_host = host;
    char value[8] = {};
    g_tidy_on_save = host->get_setting(kPluginId, "tidyOnSave", value, sizeof(value)) > 0 && value[0] == '1';
    if (g_tidy_on_save) {
        host->set_status_segment(kPluginId, "tidy", "Tidy on save");
    }
    add_command("texttools.upper", cmd_upper, "Ctrl+Shift+U");
    add_command("texttools.lower", cmd_lower, "Ctrl+Shift+L");
    add_command("texttools.sort", cmd_sort, "Ctrl+Shift+S");
    add_command("texttools.repeats", cmd_repeats, "Ctrl+Shift+R");
    add_command("texttools.tidy", cmd_tidy, "Ctrl+Shift+T");
    host->register_command_hook(kPluginId, "EditorSave", on_editor_save, nullptr, 100);
    return 0;
}

MTN_EXPORT void mtn_plugin_shutdown(void) { g_host = nullptr; }

}  // extern "C"
