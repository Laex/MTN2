# Document viewer

F3 on one of these files shows its text in the built-in viewer.

| Files | What is shown |
|---|---|
| `.docx` | Paragraphs, tabs and line breaks of the document body |
| `.xlsx` | Every sheet as rows with tab-separated cells (the first 100000 rows of a sheet) |
| `.pptx` | The text of each slide, slide by slide |
| `.pdf` | The text drawn by the page streams |
| `.svg` | Size, element counts, title and text, then the source (indented when it is on a few long lines) |
| `.sqlite`, `.sqlite3`, `.db`, `.db3` | The schema, then the first 200 rows of every table |

The viewer reads the file; it never changes it. F4 opens the original in the editor as usual.

Quick View (Ctrl+Q) shows the same text for files up to 16 MB.

Limits:

- PDF text is read from the text operators as stored. Pages that are scans, encrypted files and fonts with their own encodings give no text or unreadable text; the file then opens in the usual way.
- Formulas of a sheet show their last calculated value.
- A `.db` file that is not a SQLite database opens as usual.
