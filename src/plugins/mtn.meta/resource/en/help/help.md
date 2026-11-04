# File metadata

The plugin shows the metadata of the file under the panel cursor in the status line. It adds no keys and no commands.

| File | Shown |
|---|---|
| JPEG, PNG, GIF, BMP, WebP | format, size in pixels; for JPEG with an EXIF block also the camera and the shooting time |
| MP3 | artist, title, album and year (ID3v2 and ID3v1) |
| EXE, DLL (Windows) | version, company and description |

The segment appears a moment after the cursor stops and disappears on files of other kinds. Only local files are read, and only their first bytes.

Columns: in the Custom column mode (**Columns...**) the panel can also show, for the files of the folder, the pixel size and camera of images and the artist and title of MP3 files. These cells are shown but not sorted.
