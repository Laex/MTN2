# PDF viewer

F3 on a `.pdf` file opens its pages as pictures drawn by PDFium, with the original fonts, images and layout.

| Key | Action |
|---|---|
| PgDn, Space | Scroll down by a screen; at the bottom of a page, turn to the next one |
| PgUp, Backspace | Scroll up; at the top of a page, turn to the previous one |
| Up, Down, Left, Right | Scroll by a small step |
| Home, End | First page, last page |
| `+`, `-` | Zoom in, zoom out |
| `0` | Fit the whole page |
| `w` | Fit the page width (the default) |
| `1` | 100% |
| Wheel | Scroll; with Ctrl, zoom |
| Drag | Move the page |

Quick View (Ctrl+Q) shows the text of the first 300 pages of a file up to 16 MB. Tab in Quick View opens the same viewer in the preview panel: all the keys above work there, and the mouse wheel and drag too. Tab or Esc returns to the file panel. The **Settings** button of the plugin in Options > Plugins has two Quick View options for what the preview shows before Tab:

- *Always show pages as pictures*: the first page is drawn even when the document has text.
- *Show pages as pictures if the text cannot be extracted* (on by default): a scanned document, which has no text, is drawn instead of an empty panel.

A file that is damaged or protected by a password opens in the other viewers instead. The plugin needs `pdfium.dll` (`libpdfium.so` on Linux) in its folder; without it the text viewer of the document plugin is used.
