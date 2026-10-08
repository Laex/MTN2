## Dateien ansehen und bearbeiten

**F3** – ansehen, **F4** – bearbeiten, **F6** – zwischen Viewer ↔ Editor wechseln, ohne die Datei zu schließen.

**Alt+F3** / **Alt+F4** – die Datei unter dem Cursor im externen Viewer / Editor öffnen. Die Befehle werden unter **Optionen → Externer Viewer/Editor...** festgelegt; ohne sie öffnet Alt+F3 die Datei mit ihrem Windows-Programm und Alt+F4 mit dem Windows-Befehl „Bearbeiten“ oder, falls es keinen gibt, mit Notepad. Nur Dateien auf der Festplatte.

| Taste | Aktion |
| --- | --- |
| F7, Ctrl+F (im Viewer auch `/`) | der Suchdialog (siehe unten) |
| Shift+F7 / Alt+F7, F3 / Shift+F3 | nächster / vorheriger Treffer (bei eingeschalteter **Rückwärtssuche** tauschen die beiden) |
| Ctrl+F7 | Suchen und Ersetzen (Editor): dieselben Optionen und Schaltflächen, dazu **Ersetzen** und **Alle** |
| Alt+F8 | Gehe zu Zeile |
| F8 | nächste Kodierung; Shift+F8 – eine Kodierung wählen |
| F4 (im Viewer), Ctrl+H | HEX-Modus (im HEX-Modus des Editors lassen sich Bytes bearbeiten) |
| Ctrl+M | Markdown: dargestellte Ansicht ↔ Quelltext |
| Tab / Shift+Tab | Markdown: nächster / vorheriger Link |
| Enter, Klick auf einen Link | Markdown: einen externen Link (`https://…`, `mailto:…`) nach einer Bestätigung in der Standardanwendung öffnen |
| F2 | speichern (Editor) / Zeilenumbruch (Viewer; wird pro Datei zusammen mit der Position gemerkt) |
| Ctrl+S | speichern |
| Ctrl+Z / Ctrl+Shift+Z | rückgängig / wiederholen |
| Ctrl+Y, Ctrl+D | die Zeile löschen |
| Ctrl+K | bis zum Zeilenende löschen |
| Ctrl+N | eine leere Zeile darunter einfügen |
| Ctrl+Home / Ctrl+End | zum Anfang / Ende der Datei |
| Ctrl+C / Ctrl+X / Ctrl+V | kopieren (ohne Auswahl – die Zeile) / ausschneiden / einfügen |
| Esc, F10 (im Viewer auch 5 auf dem Ziffernblock) | schließen |

Große Dateien werden gestreamt und nicht als Ganzes geladen. Ändert sich die Datei auf der Festplatte, wird das geöffnete Fenster aktualisiert. Bei einer schreibgeschützten Datei bietet das Programm an, sie zum Schreiben zu öffnen, indem das Attribut aufgehoben wird.

**Suchdialog.** Das Feld merkt sich frühere Suchen (**Ctrl+↓** / **Alt+↓**); die Optionen sind **Groß-/Kleinschreibung**, **Ganze Wörter**, **Reguläre Ausdrücke** und **Rückwärts suchen**. **Wort** setzt das Wort unter dem Cursor in das Feld, **Auswahl** setzt die Auswahl ein (die aktuelle Zeile, wenn nichts ausgewählt ist; die erste Zeile einer mehrzeiligen Auswahl). Bei eingeschalteten **Regulären Ausdrücken** wird der Text dieser beiden Schaltflächen maskiert. Ein gefundener Treffer wird ausgewählt, und **F3** / **Shift+F3** machen von dort aus weiter. Ein Treffer erstreckt sich nie über einen Zeilenumbruch. Bei **Regulären Ausdrücken** ist das Muster ein PCRE-Ausdruck, und in der Ersetzung ist `$0` der ganze Treffer, `$1` ... `$9` sind die Gruppen und `$$` ist ein Dollarzeichen; ohne die Option wird die Ersetzung unverändert übernommen. Ein Muster, das sich nicht kompilieren lässt, wird gemeldet, und es wird nichts gesucht. **Ersetzen** im Dialog „Ersetzen“ geht die Treffer einzeln durch: jeder wird ausgewählt angezeigt, mit dem Text, seiner Ersetzung und der Zeile, die ihn enthält, und mit **Ersetzen** (ersetzen und zum nächsten weitergehen), **Alle** (den Rest ohne Nachfrage ersetzen), **Überspringen** oder **Abbrechen** beantwortet. Wird das Textende erreicht und die Suche hat in der Mitte begonnen, bietet es an, am Anfang fortzusetzen (beim Rückwärtssuchen am Ende). **Alle** im Dialog „Ersetzen“ ersetzt alle Treffer des ganzen Textes auf einmal. Beide Wege zeigen am Ende von **Alle** an, wie viele Ersetzungen vorgenommen wurden, werden mit einem einzigen **Ctrl+Z** rückgängig gemacht und setzen den Cursor dorthin zurück, wo er vor dem Ersetzen stand. Groß-/Kleinschreibung, ganze Wörter und reguläre Ausdrücke werden zwischen den Starts gemerkt; **Rückwärts suchen** nur, bis MTN2 geschlossen wird.

---

[Inhalt](index.md)
