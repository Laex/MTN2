## Suche und Filter

| Taste | Aktion |
| --- | --- |
| Alt+F7 | Dateien suchen (Maske, Inhalt, Unterordner, Groß-/Kleinschreibung, ganze Wörter, reguläre Ausdrücke) |
| Ctrl+I | Panel-Filter: ein Dialog mit einer Liste fertiger Filter und einer Zeile für die eigene Maske; Enter oder ein Doppelklick auf die Liste wendet den Filter an, Löschen entfernt ihn |
| Ctrl+B | flache Ansicht: alle Dateien des Teilbaums in einer Liste |
| Alt+Buchstabe | Schnellsuche nach Name |

### Suche über Plugins

Das Everything-Plugin beantwortet Namenssuchen in lokalen Ordnern aus seinem Index, das ripgrep-Plugin (`rg` im PATH oder neben dem Plugin) durchsucht den Dateitext, und das Plugin Dokumentenansicht lässt eine Textsuche auch in `.docx`, `.xlsx`, `.pptx`, `.pdf`, `.svg` und SQLite-Dateien schauen. Suchen in Archiven, nach Hex-Bytes oder nach Attributen nutzen die eingebaute Suche. Eine Textsuche mit selektiver Maske läuft als Pipeline: die erste Stufe listet die Dateien nach Namen auf (Everything oder der eingebaute Durchlauf), die zweite sucht darin den Text (ripgrep oder die eingebaute Prüfung). Die Schaltfläche **Pipeline** im Suchdialog öffnet einen Dialog mit einer Liste je Stufe: **Auto** wählt das beste Plugin, **Eingebaut** nutzt den eingebauten Code, oder ein Plugin wird nach Namen gewählt; kann dieses Plugin die Stufe nicht bedienen, läuft der eingebaute Code.

### Schnellsuche

Alt+Buchstabe öffnet ein Suchfeld im aktiven Panel; weitere Buchstaben werden angehängt, und der Cursor springt zur ersten Datei, deren Name mit dem getippten Text beginnt. Rücktaste löscht das letzte Zeichen, Esc schließt das Feld, Enter öffnet die Datei unter dem Cursor. Pfeil auf und ab wechseln zu den Nachbardateien; jede andere Taste oder ein Ctrl-Kürzel schließt die Suche und wirkt wie gewohnt.

Optionen (Einstellungen – Oberfläche):

- **Schnellsuche nach dem Loslassen von Alt offen halten** – das Feld bleibt bis Esc oder Enter offen;
- **Leere Schnellsuche offen halten** – ein leeres Feld wird durch die Rücktaste nicht geschlossen;
- **Schnellsuche filtert auch das Panel** – neben dem Cursor bleiben nur die passenden Dateien im Panel; das Feld bleibt nach dem Loslassen von Alt offen, Esc oder Enter bringt alle Dateien zurück, und der Cursor bleibt auf derselben Datei;
- **Schnellsuchfilter in anderen Ordnern beibehalten** – Enter auf einem Ordner oder ein Klick trägt den Filter in den neuen Ordner, danach entfernt ihn nur Esc;
- **Unscharfer Schnellsuchfilter** – auch Namen, die die getippten Buchstaben in dieser Reihenfolge, aber nicht unbedingt nebeneinander enthalten, passen (`mnr` findet `main_readme.txt`); der Cursor geht zu einer Datei mit passendem Anfang, sonst zur ersten der Liste.

Suchergebnisse öffnen sich als Panel – die üblichen Operationen funktionieren damit.

Esc während einer laufenden Suche fragt „Suche beenden?“: **Stopp** beendet die Suche, **Fortsetzen** (Esc) lässt sie weiterlaufen.

---

[Inhalt](index.md)
