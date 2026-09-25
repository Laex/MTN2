# Working with text and the mouse

The same in the viewer and editor, on the command line, in dialog fields and in consoles.

A **word** is made of letters of any alphabet, digits and `_`. Everything else — spaces, punctuation, `\`, `/`, `.`, `:` — is a **separator**.

| Action | Result |
| --- | --- |
| Ctrl+← / Ctrl+→ | to the start of a word / to the end of a word (up to the next separator) |
| Ctrl+Shift+← / Ctrl+Shift+→ | the same with selection; stepping back deselects the part passed over |
| Shift+arrows, Shift+Home/End | selection |
| Click | place the cursor |
| Double click | select a word (on a separator — a run of identical characters) |
| Next quick click | select the whole line |
| Shift+click | extend or shrink the selection to the click point |
| Mouse drag | selection (viewer, editor, console) |
| Ctrl+C / Ctrl+Ins, Ctrl+X / Shift+Del, Ctrl+V / Shift+Ins | clipboard |
| Ctrl+A | select all |

In the panels, when the command line is not empty, Ctrl+Shift+←/→ work on the command line.

**Input history.** Fields with **↓** at the right end (selection masks, file search mask and text, copy/move destination and exclusions, link target, new folder and file, editor find and replace, user menu prompts) remember their last 20 values. **Ctrl+↓** / **Alt+↓** or a click on the arrow drops the list down: **Enter** — use the entry, **Del** — remove it from the history, **Esc** — close the list. A value is added when the dialog is accepted.

---

[Contents](index.md)
