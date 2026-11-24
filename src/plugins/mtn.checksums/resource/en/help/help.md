# Checksums

Ctrl+Alt+H (Files > Checksums...) calculates the checksums of the selected files and folders on disk, or of the file under the cursor when nothing is selected.

- Choose the algorithm: MD5, SHA-1, SHA-256 or SHA-512. The calculation runs in the background; Esc in the job list cancels it.
- The result list shows one line per file. **Copy** puts the lines on the clipboard; **Save** writes them to `<file>.sha256` (one file) or `checksums.sha256` in the panel folder; the extension follows the algorithm.
- On a `.md5`, `.sha1`, `.sha256` or `.sha512` file the command checks every file listed in it and shows OK, FAILED or MISSING for each.
