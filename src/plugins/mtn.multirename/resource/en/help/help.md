# Multi-rename

Files > Multi-rename... (Ctrl+Alt+N).

The name and extension masks understand:
- `[N]` – the old name without extension;
- `[E]` – the old extension;
- `[C]` – a counter with the given start, step and number of digits;
- `[Date]` and `[Time]` – the modification date (`2026-11-05`) and time (`14-30-07`); `[Year]`, `[Month]` and `[Day]` – parts of the date;
- `[Parent]` – the name of the folder; `[Size]` – the size in bytes;
- `[Dim]`, `[Camera]`, `[Artist]` and `[Title]` – the values of the metadata plugin columns (image size and camera, audio artist and title) as the panel shows them; they are empty until the plugin has read the file;
- other text stays as typed.

Search and Replace work on the new name and extension, and the letter case comes from the list. With **Regular expression** Search is a pattern and Replace may use `$1`, `$2`; a pattern that is not valid leaves the names unchanged. Tokens may be typed in any letter case; a value that is unknown is empty, and characters a name cannot hold become `_`. The list under the fields shows the "old -> new" pairs as you type.

**Errors.** A name that is empty, invalid, used twice or already taken in the folder (also by another item of the batch) is marked with `!`, and **Rename** does nothing while any is left.

Only items of one folder can be chosen. The renaming runs as a background job, like a move.
