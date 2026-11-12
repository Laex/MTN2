# Folder map

With the cursor on a local folder, Quick View (Ctrl+Q) draws a treemap: every file and subfolder is a tile whose area is proportional to the space it takes. Big subfolders show their own contents inside.

The folder is scanned in a background thread shortly after the cursor stops on it, and the map fills in while the scan runs: the large folders appear first, then the folders and files inside them, and every tile grows as its contents are found. A finished scan is kept for half a minute, so going back to a folder is instant. A scan stops after 30 seconds or 3 million entries; the status line then says the map is incomplete.

Tab gives the keyboard to the map:

- Arrows – move between tiles.
- Enter – zoom into the selected folder; Backspace – zoom out.
- G – show the selected tile in the file panel and close the map.
- Mouse – click selects, double click zooms in, right click zooms out.
- Tab or Esc – back to the file panel.

Only local folders are scanned; other folders keep the plain Quick View. Folder links are not followed. Sizes are file sizes, not space taken on disk.

The Settings button switches the map off.
