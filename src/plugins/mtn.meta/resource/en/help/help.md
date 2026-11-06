# File metadata

The plugin shows the metadata of the file under the panel cursor in the status line. It adds no keys and no commands.

| File | Shown |
|---|---|
| JPEG, PNG, GIF, BMP, WebP | format, size in pixels; for JPEG with an EXIF block also the camera and the shooting time |
| MP3 | artist, title, album and year (ID3v2 and ID3v1) |
| EXE, DLL (Windows) | version, company and description |

The segment appears a moment after the cursor stops and disappears on files of other kinds. Only local files are read, and only their first bytes.

Columns: in the Custom column mode (**Columns...**) the panel can also show, for the files of the folder:
- images: pixel size and camera;
- MP3 files: artist, title, album and year;
- EXE, DLL, SYS, OCX and SCR files (Windows): version, company and description.

The pixel size, artist, title and camera columns are on by default; album, year, version, company and description are added in **Columns...** when needed. A click on a column heading sorts by it: the pixel size column by image area, the version column as versions are ordered (`1.10.0.0` after `1.9.0.0`).

Examples:
- Find out which build of a library is installed: open the folder, add the **Version** column and sort by it.
- Spot files of one vendor in `C:\Windows\System32`: add **Company** and sort by it.
- Tidy a music folder: show **Artist**, **Album** and **Year** and sort by **Year**.
- Find the largest photos: sort by the pixel size column.
