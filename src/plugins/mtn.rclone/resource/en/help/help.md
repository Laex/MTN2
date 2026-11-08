# Rclone

The plugin adds **Rclone** (`rclone:///`) to the Change Drive list (Alt+F1 / Alt+F2). It runs the `rclone` program, so it must be in PATH and a remote must be configured (`rclone config`).

The root lists the configured remotes; a remote opens as a folder of the panel. Every operation is one `rclone` call: `lsjson` lists, `cat` reads, `rcat` writes, `copyto` and `moveto` transfer, `mkdir` makes a folder, `deletefile` and `purge` delete, `about` reports the free space.

| Key | Action |
|---|---|
| F3 | view a file (binary files are fetched to a temporary local copy first) |
| F4 | edit and save a text file (`rclone rcat`) |
| F5 / F6 | copy or move between a remote and a local folder, or between two remotes |
| F7 | make a folder |
| F8 | delete a file, or a folder with everything in it (`purge`) |

A `/` in a name is written `%2F`. Listing a large remote can take a while: rclone reads the whole folder before the panel fills.
