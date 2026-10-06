# Panel tools (Rust)

Two small tools for the file panels, and a notice about saved files.

## Use

- **Ctrl+Shift+P** – copies the full paths of the selected files (or of the file under the cursor when nothing is selected) to the clipboard, one per line. A notice tells how many were copied.
- **Ctrl+Shift+M** – shows the folder of the active panel in the other panel too.
- **Ctrl+Shift+X** – selects every file of the folder with the extension of the file under the cursor.
- **Ctrl+Shift+K** – counts the files, folders and bytes under the active folder in a background thread; a progress notice stays on screen and the totals follow when it is done.
- **Ctrl+Shift+L** – reads the file under the cursor through the host (it can be inside an archive or on an sftp server) and shows its size, the number of lines and the first line. The plugin asks for the permission `vfs.read`: allow it in **Parameters - Plugins - Permissions...** first.
- Whenever you save a file in the editor (F2), a notice **Saved: name** appears. The plugin gets this from the host event `doc.saved`.

## For authors

Source: `samples/plugins/mtn.demo.panelkit/src/lib.rs`. It reads both panels with `panel_info` (JSON: the active side, the folder, the cursor row and the selected rows of each panel, parsed with serde_json), lists a panel with `panel_list`, selects files with `panel_select`, runs the count in a thread that reports through `post_to_main`, `progress_set` and `progress_end`, moves a panel with `panel_goto`, writes the clipboard with `clipboard_set`, shows notices with `show_message` and listens to host events with `subscribe`. See `docs/PLUGIN_DEVELOPMENT.md`, section "Documents, panels and the clipboard".
