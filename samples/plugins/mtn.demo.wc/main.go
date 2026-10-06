// Demo plugin in Go, built as a WASM module for WASI ("wasi": true in
// plugin.json): "word count". Ctrl+Shift+E counts the lines, words and
// characters of the selection (or of the whole document when nothing is
// selected) in the editor or viewer and shows them in a notice.
//
// Shows: the document API from a WASM guest (doc_get_text with a buffer that the
// guest grows on request, show_message), a plugin command with a key chord.
//
// Build: GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o plugin.wasm
package main

import (
	"fmt"
	"strings"
	"unicode/utf8"
	"unsafe"
)

const pluginID = "mtn.demo.wc"

//go:wasmimport mtn_host register_command
func registerCommand(idPtr, idLen, exportPtr, exportLen uint32) int32

//go:wasmimport mtn_host register_key_binding
func registerKeyBinding(actionPtr, actionLen, comboPtr, comboLen uint32) int32

//go:wasmimport mtn_host doc_get_text
func docGetText(what int32, outPtr, outCap uint32) int32

//go:wasmimport mtn_host show_message
func showMessage(textPtr, textLen uint32, kind int32) int32

// scratch is the 32 KiB area the host writes strings into when it calls an
// export that takes (ptr, len) arguments.
var scratch [32768]byte

func ptr(s string) uint32 {
	return uint32(uintptr(unsafe.Pointer(unsafe.StringData(s))))
}

func say(text string, kind int32) {
	showMessage(ptr(text), uint32(len(text)), kind)
}

// docText reads one kind of document text (0 selection, 1 whole document). The
// host returns the length and writes the text only when it fits, so a longer
// result means: ask again with a bigger buffer.
func docText(what int32) (string, bool) {
	size := 4096
	for attempt := 0; attempt < 3; attempt++ {
		buf := make([]byte, size)
		n := docGetText(what, uint32(uintptr(unsafe.Pointer(&buf[0]))), uint32(size))
		if n < 0 {
			return "", false
		}
		if int(n) <= size {
			return string(buf[:n]), true
		}
		size = int(n)
	}
	return "", false
}

//go:wasmexport mtn_plugin_get_abi_version
func abiVersion() int64 { return 2 }

//go:wasmexport mtn_plugin_init
func pluginInit() int32 {
	id, run := "wc.count", "count_words"
	if registerCommand(ptr(id), uint32(len(id)), ptr(run), uint32(len(run))) != 0 {
		return -1
	}
	combo := "Ctrl+Shift+E"
	registerKeyBinding(ptr(id), uint32(len(id)), ptr(combo), uint32(len(combo)))
	return 0
}

//go:wasmexport mtn_plugin_shutdown
func shutdown() {}

//go:wasmexport mtn_scratch_ptr
func scratchPtr() int32 { return int32(uintptr(unsafe.Pointer(&scratch[0]))) }

//go:wasmexport count_words
func countWords() {
	what, label := int32(0), "selection"
	text, ok := docText(0)
	if !ok {
		say("Open a text file in the viewer or editor first.", 1)
		return
	}
	if text == "" {
		what, label = 1, "document"
		if text, ok = docText(what); !ok {
			return
		}
	}
	lines := strings.Count(text, "\n") + 1
	words := len(strings.Fields(text))
	say(fmt.Sprintf("%s: %d lines, %d words, %d characters", label, lines, words, utf8.RuneCountInString(text)), 0)
}

func main() {}
