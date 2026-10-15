# Word count (Go, WASM)

Counts the text on screen in the editor (F4) or viewer (F3).

## Use

Open a text file and press **Ctrl+Shift+E**. A notice shows the number of lines, words and characters of the selection, or of the whole document when nothing is selected.

## For authors

Source: `samples/plugins/mtn.demo.wc/main.go`. A WASM module for WASI: it imports `doc_get_text`, `show_message`, `register_command` and `register_key_binding` from the `mtn_host` module. `doc_get_text` returns the length of the text and writes it only when it fits, so the plugin asks again with a bigger buffer when the result is longer. See `docs/PLUGIN_DEVELOPMENT.md`, section "Documents, panels and the clipboard".
