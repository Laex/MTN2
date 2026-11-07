## Synchronisieren und Vergleichen

<!--dir-sync-->- **Ctrl+Alt+S** – die Ordner des aktiven und des passiven Panels synchronisieren: einseitig oder zweiseitig; das Kontrollfeld „Probelauf“ zeigt, was getan würde, ohne etwas zu ändern.
- Im Synchronisationsdialog ist jeder Unterschied eine Listenzeile mit ihrer Aktion: `->` kopiert nach rechts, `<-` nach links, `--` überspringt; Konflikte sind zunächst übersprungen. Die Schaltflächen **Nach rechts**, **Nach links** und **Überspringen** setzen die Aktion der gewählten Zeile (eine manuelle Wahl ist mit `*` markiert), **Zurücksetzen** stellt die automatische wieder her, **Nur übersprungene** zeigt die Zeilen, über die noch nicht entschieden ist. Übersprungene Unterschiede bleiben bis zur nächsten Synchronisation offen.
<!--compare-files-->- **Ctrl+Alt+C** – die Dateien unter den Cursorn beider Panels oder die zwei markierten Dateien des aktiven Panels vergleichen; das Fenster zeigt Größe, Änderungszeit und das Ergebnis des Inhaltsvergleichs. Bei zwei oder mehr markierten Dateien werden gleichnamige Dateien verglichen (Markierungen in beiden Panels: nur die markierten; in einem Panel: das andere wird nach Namen durchsucht); eine Liste zeigt jedes Paar als identisch oder unterschiedlich, Enter öffnet die Unterschiede. Ordner werden übersprungen.
  For text files a compare-and-merge window opens: two columns with line numbers and the differences marked in the middle (`~` changed, `<` only on the left, `>` only on the right). **Ctrl+Down** and **Ctrl+Up** move between differences, **Right** copies a difference from left to right, **Left** from right to left, **Ctrl+Z** undoes a copy, **Ctrl+S** writes the changed files with their original encoding and line breaks. Closing with unsaved changes asks for confirmation (a second close discards them). Binary, very large (over 16 MB or 60000 lines) and identical files are shown in the earlier summary window.
<!--compare-folders-->- **Ctrl+Shift+C** – Ordner vergleichen: beide Panels wählen die auf der anderen Seite fehlenden Dateien und die neueren der gleichnamigen aus; bei gleicher Zeit, aber anderer Größe werden beide ausgewählt.

Einzelheiten des Vergleichs:
- Ordner werden nur ausgewählt, wenn sie auf der anderen Seite fehlen.
- Verglichen werden die aktuellen Panellisten ohne Unterordner, es funktioniert also auch in Archiven und auf SFTP.
- Der Dialog fragt, was als Unterschied gilt: Zeit, Größe, Inhalt.
- Der Inhalt wird nur bei gleich großen Dateien auf der Festplatte Byte für Byte verglichen und läuft im Hintergrund (Esc bricht ab).

---

[Inhalt](index.md)
