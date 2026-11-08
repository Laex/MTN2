## Selecting files

| Key | Action |
| --- | --- |
| Ins | select / deselect and move down |
| Shift+arrows, Shift+Home/End/PgUp/PgDn | select as the cursor moves |
| Shift+Gray + | select all files |
| Ctrl+M | bring back the selection held before it was last cleared (after a copy, say); a second press swaps back |
| Gray + / Gray − | select / deselect by mask (`*.txt`, `a*.*`) |
| Gray * | invert the selection |
| Ctrl+Gray + / Ctrl+Gray − | select / deselect files with the same extension as the one under the cursor |
| Shift+Gray − | deselect all files |
| Alt+Gray + / Alt+Gray − | select / deselect files with the same name |

In the select-by-mask dialog the “Select folders” check box applies the mask to folders as well. Operations (copy, delete, …) work on the selected items, or on the item under the cursor if nothing is selected.

### Mask groups

<!--mask-groups-->In any mask (selection, panel filter, search, colour groups) `@Name` expands to a named set of masks, for example `@Images` or `*.log;@Documents`. The groups Images, Audio, Video, Documents, Archives and Sources are built in. Your own groups, or replacements of built-in ones, go into `maskgroups.json` in the settings folder: `{ "groups": { "Logs": "*.log;*.out" } }`. An unknown name stays ordinary mask text. The Options menu item "Mask groups..." opens a list where groups are added, changed and deleted; the select-by-mask dialog can also save its mask as a group. In a mask field of a dialog (select, filter, search), Ctrl+G saves the typed masks as a group named after the first mask and puts `@Name` in the field.

### Column sets

The column modes menu lists named column sets under Custom (Minimal, Dates and Technical are built in). A set applies its columns to the Custom mode. To save the current choice, type a name in the "Save as column set" field of the Custom columns dialog; sets are kept in `columnsets.json` in the settings folder.

---

[Contents](index.md)
