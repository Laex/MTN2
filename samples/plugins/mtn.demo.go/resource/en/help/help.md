# JSON viewer (Go)

**F3** on a `.json` file shows it pretty-printed. A file that is not valid JSON opens as usual.

## Use

- Put the cursor on a `.json` file and press **F3**.
- **Ctrl+Alt+F9** (*GoInfo*) shows the Go runtime version and memory use.
- **Options > Plugins... > Settings** sets the indent width (1 to 8 spaces, 2 by default).

## For authors

Source: `samples/plugins/mtn.demo.go`. A native DLL built with cgo; `keepLoaded` is set because the Go runtime cannot be unloaded.
