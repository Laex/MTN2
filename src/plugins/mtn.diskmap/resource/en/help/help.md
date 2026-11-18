# Folder map

With the cursor on a local folder, Quick View (Ctrl+Q) draws a treemap: every file and subfolder is a tile whose area is proportional to the space it takes. Big subfolders show their own contents inside.

The folder is scanned in a background thread shortly after the cursor stops on it, and the map fills in while the scan runs: the large folders appear first, then the folders and files inside them, and every tile grows as its contents are found. A finished scan is kept for half a minute, so going back to a folder is instant. A scan stops after 30 seconds or 3 million entries; the status line then says the map is incomplete.

Tab gives the keyboard to the map:

- Arrows – move between tiles; Home and End – to the first and the last.
- Enter – zoom into the selected folder; when it is a file, an empty folder or one still being scanned, the status line says so. Backspace – zoom out. At the top of the scanned folder Backspace maps the folder above it and selects the folder you came from, so the map can reach the root of the disk.
- G (also the same key on a Russian layout), Ctrl+Enter or Shift+Enter – show the selected tile in the file panel and close the map.
- F5 or Ctrl+R – scan the folder again, ignoring the remembered result.
- Mouse – click selects and gives the keyboard to the map, double click zooms in, right click zooms out (like Backspace), Ctrl+click or Shift+click shows the tile in the file panel like G. The wheel forward enters the folder under the pointer, backward leaves it without leaving the scanned folder.
- Tab or Esc – give the keyboard back to the file panel; the map stays and follows the panel cursor again.

The status line shows the name, size, share and full path of the selected tile, and a key reminder when there is room. The header of a nested folder shows its size.

Only local folders are scanned; other folders keep the plain Quick View. Folder links are not followed. Sizes are file sizes, not space taken on disk.

The Settings button switches the map off.
