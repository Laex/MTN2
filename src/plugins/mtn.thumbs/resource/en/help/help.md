# Thumbnails

"Thumbnails of the folder" in the Plugins menu opens a sheet with the pictures (PNG, JPEG, GIF, BMP, TIFF, ICO, WebP) of the folder of the active panel, sorted by name. The picture under the panel cursor is selected at the start.

- Arrows, Home, End and Page Up / Down move the selection; the mouse wheel turns the pages;
- Enter, F3 or a double click opens the selected picture in the viewer, F4 in the editor, Esc closes the sheet;
- S or F9 cycles the order: by name, date (newest first), size (largest first), extension; the status line shows it;
- a red square marks a file that cannot be decoded.

Only folders on disk are shown. Pictures are decoded in the background, one page at a time. On Linux decoding needs SDL2 (BMP) or SDL2_image (the other formats).
