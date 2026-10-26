## Arbeiten mit Text und Maus

Dasselbe im Viewer und Editor, in der Befehlszeile, in Dialogfeldern und in Konsolen.

Ein **Wort** besteht aus Buchstaben eines beliebigen Alphabets, Ziffern und `_`. Alles andere – Leerzeichen, Satzzeichen, `\`, `/`, `.`, `:` – ist ein **Trennzeichen**.

| Aktion | Ergebnis |
| --- | --- |
| Ctrl+← / Ctrl+→ | zum Anfang eines Wortes / zum Ende eines Wortes (bis zum nächsten Trennzeichen) |
| Ctrl+Shift+← / Ctrl+Shift+→ | dasselbe mit Auswahl; ein Schritt zurück hebt den überschrittenen Teil wieder auf |
| Shift+Pfeile, Shift+Home/End | Auswahl |
| Klick | den Cursor setzen |
| Doppelklick | ein Wort auswählen (auf einem Trennzeichen – eine Folge gleicher Zeichen) |
| Nächster schneller Klick | die ganze Zeile auswählen |
| Shift+Klick | die Auswahl bis zum Klickpunkt erweitern oder verkleinern |
| Maus ziehen | Auswahl (Viewer, Editor, Konsole) |
| Alt+Maus ziehen | rechteckiger Block (Viewer, Editor) |
| Ctrl+C / Ctrl+Ins, Ctrl+X / Shift+Del, Ctrl+V / Shift+Ins | Zwischenablage |
| Ctrl+A | alles auswählen |

In den Panels wirken Ctrl+Shift+←/→ auf die Befehlszeile, wenn sie nicht leer ist.

<!--mouse-->**Textterminal-Version (mtn2-tui).** Das Programm fordert die Maus vom Terminal an: Ein Ziehen markiert innerhalb von MTN2, und der Text gelangt über das Terminal in die Zwischenablage (eine Steuersequenz, die manche Terminals, etwa PuTTY standardmäßig, ignorieren; in tmux und auf einem Desktop füllt MTN2 zusätzlich den tmux-Puffer und die Systemzwischenablage). Um mit dem Terminal selbst zu markieren, halten Sie beim Ziehen **Shift** gedrückt oder schalten Sie die Maus mit **Ctrl+Shift+M** aus (**Optionen → Terminal-Maus an/aus**); dieselbe Taste schaltet sie wieder ein. Die Option `--no-mouse` startet das Programm mit ausgeschalteter Maus.

**Eingabeverlauf.** Felder mit **↓** am rechten Ende (Auswahlmasken, Maske und Text der Dateisuche, Ziel und Ausschlüsse beim Kopieren/Verschieben, Linkziel, neuer Ordner und neue Datei, Suchen und Ersetzen im Editor, Abfragen des Benutzermenüs) merken sich ihre letzten 20 Werte. **Ctrl+↓** / **Alt+↓** oder ein Klick auf den Pfeil klappt die Liste auf: **Enter** – den Eintrag verwenden, **Del** – ihn aus dem Verlauf entfernen, **Esc** – die Liste schließen. Ein Wert wird hinzugefügt, wenn der Dialog bestätigt wird.

---

[Inhalt](index.md)
