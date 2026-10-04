## Background jobs

Copying, moving and deleting run in the background. The progress window can be sent to the background; **Ctrl+Shift+J** – the job list (progress, cancel).

When a copy, move or delete stops with an error, the error window offers **Retry**, **Skip**, **Skip all**, **Cancel** and, for “Access denied” on a local path, **Admin**: it repeats the item and the rest of the job through the administrator helper (see [File operations](fileops.md)).

Background jobs show at the right of the tab bar: one chip per job and a list button at the end. A chip has an icon for the operation and its progress: `»` copy, `►` move, `▼` recycle, `‼` delete, `■` pack, `□` unpack. Instead of a percentage it can show `..` (queued), `?` (waiting for an answer) or `!` (failed). Clicking a chip brings that job back: its progress window, question or error message. The `[≡N]` button opens the job list. With no background jobs nothing is shown there, whether or not the status line is visible.

---

[Contents](index.md)
