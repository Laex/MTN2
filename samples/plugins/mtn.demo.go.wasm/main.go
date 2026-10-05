// Demo plugin in Go, built as a WASM module for WASI ("wasi": true in
// plugin.json): "safe delete". Shift+Del (DeletePermanent) and the Wipe
// command are blocked and a dialog says so; the plugin cancels the command by
// answering 1 from its hook. The status line shows "Safe delete: on".
//
// Shows: Go //go:wasmimport / //go:wasmexport against the host's mtn_host
// module, the reactor start (_initialize, run by the host), and the scratch
// buffer a Go guest keeps for the host (mtn_scratch_ptr), because Go's heap
// uses all of linear memory.
//
// Build: GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o plugin.wasm
package main

import "unsafe"

const pluginID = "mtn.demo.go.wasm"

//go:wasmimport mtn_host register_command_hook
func registerCommandHook(cmdPtr, cmdLen, exportPtr, exportLen, priority uint32) int32

//go:wasmimport mtn_host show_dialog
func showDialog(jsonPtr, jsonLen, exportPtr, exportLen uint32) int32

//go:wasmimport mtn_host set_status_segment
func setStatusSegment(idPtr, idLen, textPtr, textLen uint32) int32

// scratch is the 32 KiB area the host writes strings into when it calls an
// export that takes (ptr, len) arguments.
var scratch [32768]byte

func ptr(s string) uint32 {
	return uint32(uintptr(unsafe.Pointer(unsafe.StringData(s))))
}

func hook(command, export string) int32 {
	return registerCommandHook(ptr(command), uint32(len(command)), ptr(export), uint32(len(export)), 100)
}

const blockedDialog = `{"type":"dialog","version":"2.0","title":"Safe delete","width":50,"height":9,` +
	`"children":[` +
	`{"type":"label","text":"Permanent delete is switched off by the","col":2,"row":1,"width":44,"height":1},` +
	`{"type":"label","text":"Safe delete plugin. Use Delete (the recycle bin).","col":2,"row":2,"width":46,"height":1},` +
	`{"type":"button","id":"ok","text":"  OK  ","default":true,"cancel":true,"col":19,"row":5,"width":10,"height":1}]}`

const (
	statusID   = "state"
	statusText = "Safe delete: on"
	answerName = "on_dialog_answer"
	blockName  = "on_block"
)

//go:wasmexport mtn_plugin_get_abi_version
func abiVersion() int64 { return 2 }

//go:wasmexport mtn_plugin_init
func pluginInit() int32 {
	if hook("DeletePermanent", blockName) != 0 || hook("Wipe", blockName) != 0 {
		return -1
	}
	setStatusSegment(ptr(statusID), uint32(len(statusID)), ptr(statusText), uint32(len(statusText)))
	return 0
}

//go:wasmexport mtn_plugin_shutdown
func shutdown() {}

//go:wasmexport mtn_scratch_ptr
func scratchPtr() int32 { return int32(uintptr(unsafe.Pointer(&scratch[0]))) }

// on_block is the hook of both commands: it explains and answers 1, which
// cancels the built-in command.
//
//go:wasmexport on_block
func onBlock() int32 {
	showDialog(ptr(blockedDialog), uint32(len(blockedDialog)), ptr(answerName), uint32(len(answerName)))
	return 1
}

// on_dialog_answer receives the control id and the values JSON; the dialog
// only informs, so there is nothing to do.
//
//go:wasmexport on_dialog_answer
func onDialogAnswer(idPtr, idLen, valuesPtr, valuesLen uint32) {}

func main() {}
