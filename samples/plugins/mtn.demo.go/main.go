// Demo plugin in Go, built as a native DLL (cgo, c-shared): F3 on a .json file
// shows it pretty-printed; Ctrl+Alt+F9 ("GoInfo" in the function bar) opens a
// dialog with the Go runtime's version and memory use.
//
// Shows: a document provider that answers with a redirect (the plugin writes
// the formatted text to a temp file and the host opens it in the built-in
// viewer), a plugin command with a dialog, and a settings dialog (Settings in
// the Plugins dialog) whose value, the indent width, the host stores. The host table, the exports and
// the callbacks live in bridge.c; Go gets the two callbacks below.
package main

/*
#cgo CFLAGS: -I${SRCDIR}/../../include
#include <stdlib.h>
#include "bridge.h"
*/
import "C"

import (
	"bytes"
	"strconv"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"unsafe"
)

const maxBytes = 4 << 20

// indentWidth is the number of spaces per level: the stored setting, 2 by default.
func indentWidth() int {
	buf := make([]byte, 16)
	key := C.CString("indent")
	defer C.free(unsafe.Pointer(key))
	n := int(C.bridgeGetSetting(key, (*C.char)(unsafe.Pointer(&buf[0])), C.int64_t(len(buf))))
	if n <= 0 {
		return 2
	}
	if w, err := strconv.Atoi(string(buf[:n])); err == nil && w >= 1 && w <= 8 {
		return w
	}
	return 2
}

// uriToPath turns file:///C:/dir/a%20b.json into C:\dir\a b.json.
func uriToPath(uri string) (string, bool) {
	rest, ok := strings.CutPrefix(uri, "file:///")
	if !ok {
		return "", false
	}
	p, err := url.PathUnescape(rest)
	if err != nil {
		return "", false
	}
	return filepath.FromSlash(p), true
}

// render returns the URI of a text file holding the pretty-printed JSON.
func render(uri string) (string, bool) {
	path, ok := uriToPath(uri)
	if !ok {
		return "", false
	}
	info, err := os.Stat(path)
	if err != nil || info.Size() > maxBytes {
		return "", false
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	var out bytes.Buffer
	if err := json.Indent(&out, bytes.TrimPrefix(raw, []byte("\xef\xbb\xbf")), "", strings.Repeat(" ", indentWidth())); err != nil {
		return "", false // not valid JSON: leave it to the built-in viewer
	}
	out.WriteByte('\n')
	h := fnv.New64a()
	h.Write([]byte(uri))
	target := filepath.Join(os.TempDir(), fmt.Sprintf("mtn2-json-%016x.txt", h.Sum64()))
	if err := os.WriteFile(target, out.Bytes(), 0o600); err != nil {
		return "", false
	}
	return "file:///" + filepath.ToSlash(target), true
}

//export goOnDocument
func goOnDocument(uri, mode, redirect *C.char, redirectCap C.int64_t) C.int64_t {
	target, ok := render(C.GoString(uri))
	if !ok || int64(len(target))+1 > int64(redirectCap) {
		return 0 // not mine
	}
	buf := unsafe.Slice((*byte)(unsafe.Pointer(redirect)), int(redirectCap))
	copy(buf, target)
	buf[len(target)] = 0
	return 2 // open the redirect URI in the built-in viewer
}

//export goShowInfo
func goShowInfo() {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	decl := map[string]any{
		"type": "dialog", "version": "2.0", "title": "Go plugin", "width": 46, "height": 10,
		"children": []map[string]any{
			{"type": "label", "text": runtime.Version() + " " + runtime.GOOS + "/" + runtime.GOARCH,
				"col": 2, "row": 1, "width": 40, "height": 1},
			{"type": "label", "text": fmt.Sprintf("CPUs: %d   goroutines: %d", runtime.NumCPU(), runtime.NumGoroutine()),
				"col": 2, "row": 2, "width": 40, "height": 1},
			{"type": "label", "text": fmt.Sprintf("Heap: %d KiB", m.HeapAlloc/1024),
				"col": 2, "row": 3, "width": 40, "height": 1},
			{"type": "button", "id": "ok", "text": "  OK  ", "default": true, "cancel": true,
				"col": 17, "row": 6, "width": 10, "height": 1},
		},
	}
	data, err := json.Marshal(decl)
	if err != nil {
		return
	}
	text := C.CString(string(data))
	defer C.free(unsafe.Pointer(text))
	C.bridgeShowDialog(text)
	status := C.CString("Go: " + runtime.Version())
	defer C.free(unsafe.Pointer(status))
	C.bridgeSetStatus(status)
}

// goConfigure shows the settings dialog: the indent width, 1 to 8.
//
//export goConfigure
func goConfigure() {
	decl := map[string]any{
		"type": "dialog", "version": "2.0", "title": "JSON viewer settings", "width": 44, "height": 9,
		"children": []map[string]any{
			{"type": "label", "text": "Indent width (1-8 spaces):", "col": 2, "row": 1, "width": 30, "height": 1},
			{"type": "input", "id": "indent", "value": strconv.Itoa(indentWidth()), "col": 2, "row": 2, "width": 10, "height": 1},
			{"type": "button", "id": "ok", "text": "  OK  ", "default": true, "col": 10, "row": 5, "width": 10, "height": 1},
			{"type": "button", "id": "cancel", "text": "Cancel", "cancel": true, "col": 23, "row": 5, "width": 10, "height": 1},
		},
	}
	data, err := json.Marshal(decl)
	if err != nil {
		return
	}
	text := C.CString(string(data))
	defer C.free(unsafe.Pointer(text))
	C.bridgeShowSettingsDialog(text)
}

// goSettingsAnswer stores the indent width when OK was pressed and the value
// is a number from 1 to 8.
//
//export goSettingsAnswer
func goSettingsAnswer(controlID, valuesJSON *C.char) {
	if C.GoString(controlID) != "ok" {
		return
	}
	var values struct {
		Indent string `json:"indent"`
	}
	if json.Unmarshal([]byte(C.GoString(valuesJSON)), &values) != nil {
		return
	}
	if w, err := strconv.Atoi(strings.TrimSpace(values.Indent)); err == nil && w >= 1 && w <= 8 {
		key := C.CString("indent")
		value := C.CString(strconv.Itoa(w))
		defer C.free(unsafe.Pointer(key))
		defer C.free(unsafe.Pointer(value))
		C.bridgeSetSetting(key, value)
	}
}

func main() {}
