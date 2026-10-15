# Safe delete (Go, WASM)

Blocks **Shift+Del** (permanent delete) and the **Wipe** command, and says so in a dialog. The normal **F8 / Del** (to the recycle bin) is not touched. The status line shows **Safe delete: on**.

To allow permanent delete again, switch the plugin off in **Options > Plugins...**.

## For authors

Source: `samples/plugins/mtn.demo.go.wasm/main.go`. A WebAssembly module built with `GOOS=wasip1`; it needs `"wasi": true` in `plugin.json`.
