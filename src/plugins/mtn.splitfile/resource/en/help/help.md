# Split / combine

File > Split / combine... works on the file under the cursor (a file on disk).

- On an ordinary file it asks for the folder (the other panel's folder by default) and the part size (`700M`, `1.44M`, `4G` or bytes) and writes `name.001`, `name.002`, ...
- On any part (`name.001`...) it joins all the parts back into one file; the result name defaults to the part name without the number.
- The work runs in the background. Existing files are never overwritten; Esc in the job list cancels the work and removes the unfinished result.
- The parts are plain slices, so they can also be joined with `copy /b`. The command has no default key; it can be bound in the keymap dialog.
