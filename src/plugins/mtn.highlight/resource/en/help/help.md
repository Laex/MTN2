# Syntax highlighting

Colors source code in the viewer (F3) and the editor (F4). The plugin ships with about 70 languages, among them C, C++, C#, Java, Go, Rust, Python, Ruby, PHP, Perl, Lua, JavaScript, HTML, CSS, XML, JSON, YAML, SQL, Markdown, Pascal (`.pas`, `.dpr`), shell scripts, batch files and makefiles.

## Use

Nothing to press: open a file of one of these languages. The language is chosen by the file extension or, for files such as `Makefile`, by the whole file name. Keywords, types, functions, strings, numbers, constants, operators, preprocessor lines and comments get their own colors; the colors belong to the program and follow the theme.

Block comments and multi-line strings are followed from line to line, also while you edit: a line you change recolors the lines below it. In a very long file the colors of the lines far below the screen are worked out in the background, so right after a jump to the end of the file the first screens may show plain text for a moment.

Left plain: lines longer than 3500 bytes and text files (`.txt`). Files that the viewer reads in pieces because of their size (more than 10 MB) are colored line by line, without the state of the lines above, so a block comment that began earlier is not recognized.

## Switching off

Open Options - Plugins... and switch the plugin off; files are plain text again.

## For authors

Source: `src/plugins/mtn.highlight/src/lib.rs` (Rust, the `syntect` crate, Sublime syntaxes). It registers every language with `register_highlighter_state` and answers `hl_line` with the colored spans and the parser state at the end of the line. See `docs/PLUGIN_DEVELOPMENT.md`.

## Licenses

The plugin contains the `syntect` library and the Sublime Text syntax definitions; their licenses are in `licenses.md` next to the plugin.
