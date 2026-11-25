## Dateien auswählen

| Taste | Aktion |
| --- | --- |
| Ins | auswählen / Auswahl aufheben und nach unten gehen |
| Shift+Pfeile, Shift+Home/End/PgUp/PgDn | beim Bewegen des Cursors auswählen |
| Shift+Grau + | alle Dateien auswählen |
| Ctrl+M | die Auswahl zurückholen, die vor dem letzten Aufheben bestand (zum Beispiel nach einem Kopieren); ein zweites Drücken tauscht zurück |
| Grau + / Grau − | nach Maske auswählen / abwählen (`*.txt`, `a*.*`) |
| Grau * | die Auswahl umkehren |
| Ctrl+Grau + / Ctrl+Grau − | Dateien mit derselben Endung wie die unter dem Cursor auswählen / abwählen |
| Shift+Grau − | alle Dateien abwählen |
| Alt+Grau + / Alt+Grau − | Dateien mit demselben Namen auswählen / abwählen |

Im Dialog „Nach Maske auswählen“ wendet das Kontrollfeld „Ordner auswählen“ die Maske auch auf Ordner an. Operationen (Kopieren, Löschen, …) wirken auf die ausgewählten Elemente oder, wenn nichts ausgewählt ist, auf das Element unter dem Cursor.

### Maskengruppen

<!--mask-groups-->Mehrere Masken in einem Feld werden durch `;` getrennt (ein Komma geht ebenfalls; die zusätzlichen Muster im Dialog zur Ordnersynchronisierung kennen nur `;`). In jeder Maske (Auswahl, Panelfilter, Suche, Farbgruppen) steht `@Name` für eine benannte Gruppe von Masken, zum Beispiel `@Images` oder `*.log;@Documents`. Eingebaut sind Images, Audio, Video, Documents, Archives und Sources. Eigene Gruppen verwaltet der Menüpunkt "Maskengruppen..." im Menü Optionen (Datei `maskgroups.json` im Einstellungsordner); der Dialog zur Auswahl nach Maske kann seine Maske ebenfalls als Gruppe speichern. In einem Maskenfeld eines Dialogs speichert Strg+G die eingegebenen Masken als Gruppe (benannt nach der ersten Maske) und setzt `@Name` ins Feld.

### Spaltensätze

Das Menü der Spaltenmodi führt nach den voreingestellten Modi die benannten Spaltensätze auf. Die Wahl eines Satzes gibt dem Panel, in dem er gewählt wurde, diese Spalten; das andere Panel behält seine eigenen, jedes Panel merkt sich seine Spalten. Die Sätze liegen in `columnsets.json` im Einstellungsordner; fehlt die Datei, wird sie mit den Sätzen Minimal, Dates und Technical angelegt, danach sind es gewöhnliche Sätze, die geändert, umbenannt oder gelöscht werden können. Um die aktuelle Auswahl zu speichern, einen Namen in das Feld „Als Spaltensatz speichern“ des Dialogs Eigene Spalten tippen (Optionen, Spalten), der die Spalten des aktiven Panels bearbeitet. Derselbe Dialog listet die Sätze: Bearbeiten lädt den gewählten Satz in die Kontrollkästchen und das Namensfeld (OK speichert die Änderungen unter diesem Namen), Umbenennen gibt dem gewählten Satz den im Feld getippten Namen, Löschen entfernt ihn.

---

[Inhalt](index.md)
