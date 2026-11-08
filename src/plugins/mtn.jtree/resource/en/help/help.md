# JSON and YAML tree

Enter on a `.json`, `.yaml` or `.yml` file opens it like a folder (`jtree:///path/file.json!/`). Objects and arrays are folders, values are files. The **Value** column shows a value (`{3}` / `[3]` for a folder with 3 children), **Type** shows `object`, `array`, `string`, `number`, `boolean` or `null`.

| Key | Action |
|---|---|
| Enter | go into an object or array |
| F3 | view a value (a string as it is, a number or `true` / `false` / `null` as text) |
| F5 | copy a value, or a whole object or array as formatted JSON, to a local folder |

Array items are named by their index (`00`, `01`, ...), so they sort in order. A `/` in a key is written `%2F`. The tree is read-only. The file is read into memory whole, so one over 200 MB is not opened: an error is shown.

YAML: block mappings and sequences, quoted and plain scalars, flow collections on one line, `|` and `>` block scalars, comments. Anchors, aliases, tags and multi-line flow collections are not supported; the file is then shown as an error with the line number. Only the first document of a stream is read.
