# Export list

Files > Export list... saves the selected items (or, with nothing selected, the item under the cursor) to a file.

**The dialog asks for**
- the file name;
- the layout – by extension (`.md` – Markdown table, `.csv` – CSV, anything else – aligned text), plain text, Markdown or CSV;
- the fields: name, full path, extension, size, modified / created / accessed date, type and attributes.

The header line can be switched off (a Markdown table always has one). Folders show `<DIR>` in place of the size. The choice is remembered between launches. Items of local folders only; the item has no default key, one can be assigned in the key bindings dialog (command `exportlist.run`).
