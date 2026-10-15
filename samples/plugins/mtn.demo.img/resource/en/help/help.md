# Picture viewer (Rust)

The plugin shows pictures in a viewer tab of MTN2, scaled to fit the tab.

## Use

- Put the cursor on a picture (`.jpg`, `.jpeg`, `.png`, `.bmp`, `.gif`, `.tif`, `.tiff`, `.webp`) and press **F3**.
- **Right**, **Down** or **Space** shows the next picture of the folder, **Left**, **Up** or **Backspace** the previous one; the order is by name.
- The mouse wheel zooms around the pointer, dragging with the left button moves the picture, a double click switches between fit and 100 %. **+**, **-**, **0** and **1** zoom in, out, fit and 100 %; **r** rotates clockwise, **f** switches full screen.
- **Ctrl+Shift+V** shows the picture under the panel cursor in the other panel and follows the cursor; press it again to close; **Ctrl+Shift+Y** rotates that picture.
- **Esc** leaves full screen first, then closes the tab (**F10** closes at once). The status line shows the picture size and its place in the folder.
- An animated GIF is shown as its first frame. A picture over 4096 pixels on a side is shrunk first. The EXIF orientation of photos is applied.

## For authors

Source: `samples/plugins/mtn.demo.img/src/lib.rs`. The plugin uses the picture surface of the host API (`surface_open_ex` with the tab, full screen and panel modes, mouse events with the size of the area, `surface_set_frame`, `surface_set_info`) and the panel events (`panel.cursor`): a document provider opens a surface, decodes the file with the `image` crate and hands the BGRA pixels to the host, which draws them into the tab. See `docs/PLUGIN_DEVELOPMENT.md`.
