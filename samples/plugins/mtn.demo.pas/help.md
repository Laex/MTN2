# Quick notes (Delphi)

**Ctrl+Alt+F8** (*Note* in the function bar) asks for a line of text and adds it, with the date and time, to the notes file. The status line shows **Notes: N**, the number of notes in the file.

## Use

- Press **Ctrl+Alt+F8**, type the note, press OK.
- **Options > Plugins... > Settings** chooses another notes file. Empty means `mtn2-notes.txt` in your user folder.

## For authors

Source: `samples/plugins/mtn.demo.pas/NotesPlugin.dpr`. Shows a command with a key, a dialog with an input field, a status segment and a settings dialog.
