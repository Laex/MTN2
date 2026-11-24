# 7-Zip archives

Enter on an archive or disk image (7z, RAR, TAR, GZ, ISO, CAB, WIM, VHD, MSI, DEB, RPM and others) opens it like a folder.

Inside an archive:

- F3 views a file, F5 unpacks the files under the cursor or the selected ones;
- F5 from a panel into an archive adds files to it, if 7-Zip can update the format (7z, zip, tar and others);
- F8 deletes entries from such an archive.

"Test archive (checksums)" in the Plugins menu (and File > Test archive for archives that are not ZIP) checks every file of the archive under the cursor against its stored checksums without unpacking it, in the background.

On Windows `7z.dll` is taken from the plugin folder; on Linux the `7zz` or `7z` program must be in PATH.
