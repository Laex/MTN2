# Makros

Das Plugin führt in Lua geschriebene Makros aus. Ein Makro ist eine Textdatei im Ordner `macros` des Einstellungsverzeichnisses. Es startet über eine eigene Taste oder über das Menü **Makros** in Panels, Viewer, Editor und Konsole (nicht von der Kommandozeile). Esc stoppt ein laufendes Makro.

## Aufzeichnen

* **Strg+.** beginnt die Aufzeichnung der gedrückten Tasten; **Strg+.** noch einmal (oder ein Klick auf die Marke **REC**) beendet sie. **Strg+Umschalt+.** pausiert und setzt fort.
* Nach der Aufzeichnung fragt ein Dialog nach Name, Taste und danach, ob das Makro im Menü „Makros“ erscheint. Das Tastenfeld nimmt die gedrückte Kombination auf; Rücktaste entfernt sie. Belegt das Programm oder ein anderes Plugin die Taste bereits, warnt der Dialog: erneutes OK weist sie trotzdem zu; nach einer Aufzeichnung wird eine belegte Taste nicht zugewiesen.
* Das Makro wird als Lua-Datei gespeichert und lässt sich wie normaler Text bearbeiten.

## Makros verwalten

**Makros > Makros verwalten...** zeigt die Makros als Tabelle.

| Taste | Aktion |
|---|---|
| Enter | starten |
| Leertaste | ein- / ausschalten |
| F2 | Taste zuweisen |
| F4 | im Editor öffnen (nach dem Speichern werden die Makros neu gelesen) |
| F5 | Ordner ohne Neustart neu lesen |
| Entf | löschen |

Die Schaltfläche **Import...** nimmt eine Makrodatei oder einen Ordner mit Makros an; **Export...** kopiert alle Makros in einen Ordner.

## Ein Makro schreiben

```lua
macro {
  name = "Make folder",
  area = "panels",
  requires = "has_selection",
  key = "Ctrl+Alt+2",
  menu = true,
  run = function()
    mtn.key("F7")
    mtn.text("New folder")
    mtn.key("Enter")
  end,
}
```

| Feld | Bedeutung |
|---|---|
| `name` | Name in Menü und Liste |
| `area` | wo das Makro läuft: `panels`, `editor`, `viewer`, `terminal`, mehrere durch Komma getrennt, oder `any` |
| `requires` | Bedingungen vor dem Start, durch Komma getrennt: `has_selection`, `no_selection`, `cursor_file`, `cursor_dir`, `editable`, `modified` |
| `key` | Tastenkombination, zum Beispiel `Ctrl+Alt+2` |
| `menu` | `true` zeigt das Makro im Menü „Makros“ |
| `run` | die Funktion, die die Arbeit erledigt |

Funktionen in `run`:

| Funktion | Wirkung |
|---|---|
| `mtn.key("F7")` | Taste oder Kombination drücken |
| `mtn.text("abc")` | Text eingeben |
| `mtn.action(name)` | einen Programmbefehl ausführen |
| `mtn.state()` | Zustandstabelle: `area`, `has_selection`, `selected_count`, `cursor_kind`, `cursor_name`, `panel_kind`, `active_side`, `editor_modified`, `editor_has_selection`, `viewer_mode`, `busy`, `jobs` |
| `mtn.selected()` | Liste der markierten Einträge |
| `mtn.message(text)` | eine Meldung anzeigen |
| `mtn.wait_idle()` | dem Programm Zeit geben, das vom Makro Begonnene zu zeichnen und zu verarbeiten |
| `mtn.wait_jobs()` | warten, bis alle Hintergrundaufgaben (Kopieren, Verschieben, Löschen, Packen, Plugin-Aufgaben) beendet sind; eine Aufgabe mit offener Frage wartet auf die Antwort |

Jeder Aufruf, der das Programm berührt, wartet, bis das Programm ihn verarbeitet hat, und erst dann läuft das Makro weiter. Die Lua-Umgebung enthält die Basisbibliothek sowie `string`, `table`, `math`, `utf8` und `coroutine`; `io`, `os`, `package` und `debug` stehen nicht zur Verfügung. Ein Makro, das lange ohne Warten läuft, wird gestoppt.

Drei Beispiele liegen im Ordner `samples/macros` der Distribution: Zeilen sortieren ohne Duplikate, Ordner anlegen, Bericht über markierte Dateien.

## Editor, panels, dialogs and programs

These functions also wait until the program has handled the call. Lines and columns count from 1; a panel side is `"left"`, `"right"` or `nil` (the active one).

| Function | Action |
|---|---|
| `mtn.editor.info()` | table: `uri`, `lines`, `row`, `col`, `dirty`, `can_edit`, `has_selection`; `nil` without a document |
| `mtn.editor.text()`, `.selection()`, `.current_line()` | the whole text, the selection, the current line |
| `mtn.editor.line(n)` | line `n` or `nil` |
| `mtn.editor.replace(text)` | replace the selection (or insert at the cursor) |
| `mtn.editor.replace_all(text)`, `.replace_line(text)` | replace the whole text or the current line |
| `mtn.editor.set_cursor(row, col)`, `.set_selection(r1, c1, r2, c2)` | place the cursor or the selection |
| `mtn.panel.list(side)` | table: `path`, `files` (rows with `name`, `uri`), `cursor`, `truncated` |
| `mtn.panel.path(side)`, `.cursor(side)` | the path of a panel, the row under the cursor |
| `mtn.panel.open(uri, side)`, `.set_cursor(uri, side)` | go to a folder, put the cursor on an item |
| `mtn.panel.select(mask, side)`, `.unselect(mask, side)`, `.clear_selection(side)` | mark, unmark by mask, unmark all |
| `mtn.panel.select_item(uri, side)`, `.unselect_item(uri, side)` | mark or unmark one item |
| `mtn.panel.refresh()` | reread the panels |
| `mtn.clipboard.get()`, `.set(text)` | the clipboard |
| `mtn.input(prompt, default, title)` | an input box; `nil` when closed |
| `mtn.confirm(text, title)` | a Yes/No question: `true` or `false` |
| `mtn.choose(title, items)` | pick from a list of strings: the item number or `nil` |
| `mtn.exec(program, args, opts)` | run a program: its output and exit code, or `nil` and the reason |

A program starts only when its name (without path and extension) is listed in the macro's `exec` field, comma separated, for example `exec = "git, hg"`. `opts` takes `stdin` (text for the input) and `timeout` (seconds, 10 by default, at most 60). The output is cut at 1 MB. Dialogs are unavailable while another dialog is open.

### Events

`mtn.on(topic, function, {exec = "..."})` called while a file loads registers a handler. When the program publishes an event (`doc.opened`, `doc.saved`, `doc.changed`, `doc.closed`, `panel.dir`, `panel.cursor`), the function runs as a macro and gets the event table with a `topic` field. An event that arrives while another macro or handler runs is skipped, so a handler cannot start itself.

```lua
mtn.on("doc.saved", function(e)
  mtn.message("Saved: " .. (e.uri or ""))
end)
```

### Panel columns

`mtn.column{...}` called while a file loads adds a column to the file panels (Settings – Columns...).

```lua
mtn.column {
  id = "kb", title = "KB", width = 7, align = "right", default = true,
  value = function(f)
    if f.dir then return nil end
    return f.size // 1024 .. " KB"
  end,
}
```

| Field | Meaning |
|---|---|
| `id` | the name of the column (required) |
| `title` | the heading, `id` by default |
| `width` | the width (10 by default) |
| `align` | `"left"` or `"right"` |
| `default` | `true` shows the column until the user picks a set of their own |
| `value` | a function: gets the file table (`name`, `uri`, `dir`, `size`) and returns a text or a number; `nil` leaves the cell empty |

The values are computed for both panels when the macros load and whenever a folder changes, for the first 3000 files and in local folders only. The function runs like a macro but cannot wait: calls that reach into the program (`mtn.key`, `mtn.editor.*`, dialogs, `mtn.exec`) are unavailable in it. A column whose function raised an error is switched off until the macros are reloaded, and the error is shown once. A column cannot be sorted.
