# 7-Zip archives

Enter on an archive or disk image (7z, RAR, TAR, GZ, ISO, CAB, WIM, VHD, MSI, DEB, RPM and others) opens it like a folder.

Inside an archive:

- F3 views a file, F5 unpacks the files under the cursor or the selected ones;
- F5 from a panel into an archive adds files to it, if 7-Zip can update the format (7z, zip, tar and others);
- F8 deletes entries from such an archive.

"Test archive (checksums)" in the Plugins menu (and File > Test archive for archives that are not ZIP) checks every file of the archive under the cursor against its stored checksums without unpacking it, in the background.

A multi-volume archive is made in two steps: pack into a .7z, then File > Split / combine... cuts it into `name.7z.001`, `name.7z.002`, ...; the first volume opens like a folder.

"Make self-extracting archive (.exe)" in the Plugins menu (Windows only) turns the .7z archive under the cursor into a program next to it that unpacks the archive without 7-Zip. An existing file is never replaced. It needs the `7z.sfx` module in the plugin folder, the 7-Zip folder or Far ArcLite.

On Windows `7z.dll` is taken from the plugin folder; on Linux the `7zz` or `7z` program must be in PATH.
