## Archives

- **Enter** on an archive opens it as a folder; **Ctrl+\\** or `..` in the archive root – leave it.
- **Ctrl+PgDn** opens a file as an archive whatever its extension: `.docx`, `.xlsx` or `.odt` (ZIP inside), or an archive with an unusual extension. The format is found from the file's content; on a file that is not an archive nothing happens.
- **F5** from an archive extracts the selection, **F5** into an open archive adds to it.
- **Shift+F1** – pack the selection, **Shift+F2** – unpack.
<!--pack-->- The pack dialog suggests the name of the current folder as the archive name and lets you pick the type: `zip` or `7z`. A `7z` archive can get a compression level, a password and encrypted file names (these fields are greyed out for `zip`); files can be added to and deleted from an encrypted `7z` archive.
<!--password-->- 7z and other formats – through the 7-Zip plugin (`7z.dll` comes with the program; you can replace it with your own copy in `plugins\mtn.7z\`).
<!--test-->- **Test archive** (File > Test archive): checks every file of the archive under the cursor against its stored checksums without unpacking it (Esc cancels). ZIP is checked by the program itself, 7z, RAR, TAR and the other formats of the 7-Zip plugin by the plugin. A healthy archive shows a one-line toast; damaged entries are listed by name. The command has no default key and can be bound in the keymap dialog.
<!--pack-each-->- **Pack each item** (File > Pack each item): packs every selected file or folder into its own ZIP (`name.zip`) in the other panel's folder; an existing archive is never replaced (the new one becomes `name (2).zip`). Runs in the background, Esc cancels. The command has no default key and can be bound in the keymap dialog.
- For encrypted archives the program asks for the password: on entering one whose file names are encrypted, otherwise on the first view or copy of an encrypted file. A wrong password is asked again; the right one is kept until the program closes.

---

[Contents](index.md)
