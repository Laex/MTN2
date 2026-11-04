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
| `mtn.state()` | Zustandstabelle: `area`, `has_selection`, `selected_count`, `cursor_kind`, `cursor_name`, `panel_kind`, `active_side`, `editor_modified`, `editor_has_selection`, `viewer_mode` |
| `mtn.selected()` | Liste der markierten Einträge |
| `mtn.message(text)` | eine Meldung anzeigen |
| `mtn.wait_idle()` | dem Programm Zeit geben, das vom Makro Begonnene zu zeichnen und zu verarbeiten |

Jeder Aufruf, der das Programm berührt, wartet, bis das Programm ihn verarbeitet hat, und erst dann läuft das Makro weiter. Die Lua-Umgebung enthält die Basisbibliothek sowie `string`, `table`, `math`, `utf8` und `coroutine`; `io`, `os`, `package` und `debug` stehen nicht zur Verfügung. Ein Makro, das lange ohne Warten läuft, wird gestoppt.

Drei Beispiele liegen im Ordner `samples/macros` der Distribution: Zeilen sortieren ohne Duplikate, Ordner anlegen, Bericht über markierte Dateien.
