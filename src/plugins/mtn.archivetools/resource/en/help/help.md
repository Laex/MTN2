# Archive tools

**Test archive** (File > Test archive): checks every file of the archive under the cursor against its stored checksums without unpacking it (Esc in the job list cancels). ZIP is checked by this plugin, 7z, RAR, TAR and the other formats of the 7-Zip plugin by that plugin. A healthy archive shows a one-line notice; damaged entries are listed by name.

**Pack each item** (File > Pack each item): packs every selected file or folder into its own ZIP (`name.zip`) in the other panel's folder; an existing archive is never replaced (the new one becomes `name (2).zip`). Runs in the background, Esc in the job list cancels.

Neither command has a default key; both can be bound in the keymap dialog.
