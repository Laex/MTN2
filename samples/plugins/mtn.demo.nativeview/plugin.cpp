// Demo plugin in C++: a window of the plugin inside the program.
//
// Ctrl+Shift+G opens a viewer tab whose area is a native window (HWND) that the plugin draws in
// itself with GDI: a gradient, a bouncing ball and the last click. The program keeps the window
// over the cells of the tab, hides it under dialogs and menus and resizes the windows inside it
// to fill it. A player such as libmpv would be given the same handle as its output window.
//
// Shows: surface_open_ex with the native flag, surface_native_handle, a window class of the
// plugin, mouse messages arriving in the plugin window, keys through the surface callback.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <cstdio>
#include <cstring>
#include <cwchar>

#include "mtn_plugin.h"

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

namespace {

constexpr const char *kPluginId = "mtn.demo.nativeview";
constexpr const wchar_t *kClass = L"MtnNativeDemoView";
constexpr UINT_PTR kTimer = 1;

const MtnHostApi *g_host = nullptr;
HINSTANCE g_module = nullptr;
bool g_class_registered = false;
int64_t g_surface = 0;
HWND g_view = nullptr;

struct State {
    double x = 80, y = 60, dx = 3, dy = 2;
    bool paused = false;
    POINT click = {-1, -1};
    int clicks = 0;
    int frames = 0;
} g_state;

void paint(HWND hwnd) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    RECT rc;
    GetClientRect(hwnd, &rc);
    const int w = rc.right, h = rc.bottom;
    HDC mem = CreateCompatibleDC(dc);
    HBITMAP bmp = CreateCompatibleBitmap(dc, w, h);
    HGDIOBJ old = SelectObject(mem, bmp);
    // Vertical gradient from dark blue to teal, drawn as bands.
    for (int y = 0; y < h; y += 4) {
        const int t = h > 0 ? y * 255 / h : 0;
        HBRUSH brush = CreateSolidBrush(RGB(10 + t / 8, 30 + t / 3, 90 + t / 2));
        RECT band = {0, y, w, y + 4};
        FillRect(mem, &band, brush);
        DeleteObject(brush);
    }
    HBRUSH ball = CreateSolidBrush(RGB(255, 200, 60));
    HGDIOBJ prev = SelectObject(mem, ball);
    Ellipse(mem, static_cast<int>(g_state.x) - 24, static_cast<int>(g_state.y) - 24,
            static_cast<int>(g_state.x) + 24, static_cast<int>(g_state.y) + 24);
    SelectObject(mem, prev);
    DeleteObject(ball);
    if (g_state.click.x >= 0) {
        HPEN pen = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
        HGDIOBJ old_pen = SelectObject(mem, pen);
        SelectObject(mem, GetStockObject(NULL_BRUSH));
        Ellipse(mem, g_state.click.x - 12, g_state.click.y - 12, g_state.click.x + 12, g_state.click.y + 12);
        SelectObject(mem, old_pen);
        DeleteObject(pen);
    }
    SetBkMode(mem, TRANSPARENT);
    SetTextColor(mem, RGB(255, 255, 255));
    wchar_t text[160];
    swprintf(text, 160, L"A native window of the plugin   %dx%d   frame %d   clicks %d%ls", w, h, g_state.frames,
             g_state.clicks, g_state.paused ? L"   (paused)" : L"");
    TextOutW(mem, 12, 10, text, static_cast<int>(wcslen(text)));
    const wchar_t *hint = L"Click in the window. Space pauses. Esc closes the tab.";
    TextOutW(mem, 12, 32, hint, static_cast<int>(wcslen(hint)));
    BitBlt(dc, 0, 0, w, h, mem, 0, 0, SRCCOPY);
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
    EndPaint(hwnd, &ps);
}

LRESULT CALLBACK view_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    switch (msg) {
    case WM_CREATE:
        SetTimer(hwnd, kTimer, 16, nullptr);
        return 0;
    case WM_TIMER: {
        if (g_state.paused) {
            return 0;
        }
        RECT rc;
        GetClientRect(hwnd, &rc);
        g_state.x += g_state.dx;
        g_state.y += g_state.dy;
        if (g_state.x < 24 || g_state.x > rc.right - 24) {
            g_state.dx = -g_state.dx;
        }
        if (g_state.y < 24 || g_state.y > rc.bottom - 24) {
            g_state.dy = -g_state.dy;
        }
        ++g_state.frames;
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    }
    case WM_LBUTTONDOWN:
        g_state.click = {static_cast<int>(static_cast<short>(LOWORD(lparam))),
                         static_cast<int>(static_cast<short>(HIWORD(lparam)))};
        ++g_state.clicks;
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT:
        paint(hwnd);
        return 0;
    case WM_DESTROY:
        KillTimer(hwnd, kTimer);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int64_t on_key(void *, const char *key) {
    if (std::strcmp(key, "Space") == 0) {
        g_state.paused = !g_state.paused;
        return 1;
    }
    return 0;
}

// The program destroys the surface window and the window inside it when the tab closes.
void on_closed(void *) {
    g_surface = 0;
    g_view = nullptr;
}

void open_view(void *) {
    if (g_surface != 0) {
        return;
    }
    // 256 = native window, 0 = a tab of its own.
    g_surface = g_host->surface_open_ex(kPluginId, "Native window", 256, on_key, nullptr, on_closed, nullptr, nullptr);
    if (g_surface <= 0) {
        g_surface = 0;
        g_host->show_message("Switch to the file panels first.", 1);
        return;
    }
    HWND container = reinterpret_cast<HWND>(g_host->surface_native_handle(g_surface));
    if (!g_class_registered) {
        WNDCLASSW wc = {};
        wc.lpfnWndProc = view_proc;
        wc.hInstance = g_module;
        wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32515));
        wc.lpszClassName = kClass;
        g_class_registered = RegisterClassW(&wc) != 0;
    }
    // The program resizes this window to the area of the tab whenever the area changes.
    g_view = CreateWindowExW(0, kClass, L"", WS_CHILD | WS_VISIBLE, 0, 0, 100, 100, container, nullptr, g_module,
                             nullptr);
}

}  // namespace

extern "C" {

MTN_EXPORT int64_t mtn_plugin_get_abi_version(void) { return MTN_ABI_VERSION; }

MTN_EXPORT int64_t mtn_plugin_init(const MtnHostApi *host) {
    if (host == nullptr || host->abi_version < 2 || host->surface_open_ex == nullptr ||
        host->surface_native_handle == nullptr || host->register_command == nullptr) {
        return -1;
    }
    g_host = host;
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&mtn_plugin_init), &module);
    g_module = module;
    host->register_command(kPluginId, "nativeview.open", open_view, nullptr);
    host->register_key_binding(kPluginId, "nativeview.open", "Ctrl+Shift+G");
    return 0;
}

MTN_EXPORT void mtn_plugin_shutdown(void) {
    // The host has closed the tab (and with it the window) by now.
    if (g_class_registered) {
        UnregisterClassW(kClass, g_module);
        g_class_registered = false;
    }
    g_host = nullptr;
}

}  // extern "C"
