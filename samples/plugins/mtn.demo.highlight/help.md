# Syntax colors (Rust)

Colors configuration-style text in the viewer (F3) and the editor (F4).

## Use

Nothing to press: open a `.json`, `.ini`, `.cfg`, `.conf`, `.toml`, `.yaml` or `.yml` file. Strings, numbers, constants (`true`, `false`, `null`, `yes`, `no`, `on`, `off`), keys, `[sections]` and comments (`;`, `#`, `//`) get their own colors. The colors belong to the program and follow the theme: a dark and a light background each get a fitting set.

## For authors

Source: `samples/plugins/mtn.demo.highlight/src/lib.rs`. The plugin registers a handler with `register_highlighter`. For every line the viewer or editor draws, the host calls it with the text of the line (UTF-8) and room for spans of three integers: the start (byte offset), the length (bytes) and a class (comment, string, number, keyword, type, function, operator, preprocessor, constant, key, error). The host caches the answer by the text of the line. See `docs/PLUGIN_DEVELOPMENT.md`.
