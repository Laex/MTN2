## Hintergrundaufträge

<!--job-list-->Kopieren, Verschieben und Löschen laufen im Hintergrund. Das Fortschrittsfenster lässt sich in den Hintergrund schicken; **Ctrl+Shift+J** – die Auftragsliste (Fortschritt, Abbrechen).

<!--stop-->Ein Auftrag lässt sich im Fortschrittsfenster mit der Schaltfläche **Abbrechen**, mit **Esc** oder mit einem Klick außerhalb des Fensters stoppen; die Schaltflächen „Abbrechen“ und „Alle abbrechen“ in der Auftragsliste tun dasselbe.

Zuerst kommt eine Frage: „Den aktuellen Vorgang abbrechen?“:
- **Stopp** hält den Auftrag an;
- **Fortsetzen** (die Standardschaltfläche, auch Esc) kehrt zum vorherigen Fenster zurück.

Nach **Stopp** schließt das Fortschrittsfenster sofort, und der Auftrag beendet das Anhalten selbst: bis er die Anforderung bemerkt, bleibt er in der Auftragsliste, ohne Plakette.

Dialogschaltflächen werden mit **Enter** und der **Leertaste** gedrückt: die Schaltfläche sieht gedrückt aus, solange die Taste gehalten wird, und wirkt beim Loslassen. Esc vor dem Loslassen hebt die Schaltfläche an, ohne dass sie wirkt.

<!--queue-->**Warteschlange, Pause und Tempo.** Kopier- und Verschiebeaufträge auf demselben Laufwerk laufen nacheinander; die übrigen warten in der Warteschlange (`..`). In der Auftragsliste (**Ctrl+Shift+J**) gilt für den gewählten Auftrag:
- **Pause** hält ein laufendes Kopieren beim nächsten Block an (Chip `||`, Status „pausiert“) oder verhindert den Start eines wartenden Auftrags; ein angehaltener Auftrag belegt sein Laufwerk, bis er fortgesetzt oder abgebrochen wird;
- **Hoch** und **Runter** ändern die Startreihenfolge wartender Aufträge;
- **Tempo** schaltet die Geschwindigkeitsbegrenzung durch: keine, 1, 5, 20 und 100 MB/s (in der Statusspalte). Die Begrenzung gilt beim Kopieren zwischen lokalen Ordnern.

<!--errors-->Hält ein Kopier-, Verschiebe- oder Löschvorgang mit einem Fehler an, bietet das Fehlerfenster **Wiederholen**, **Überspringen**, **Alle überspringen**, **Abbrechen** und, bei „Zugriff verweigert“ auf einem lokalen Pfad, **Admin** an: es wiederholt das Element und den Rest des Auftrags über den Administrator-Helfer (siehe [Dateioperationen](fileops.md)).

Hintergrundaufträge erscheinen rechts in der Tableiste: eine Plakette pro Auftrag und am Ende eine Listenschaltfläche.

**Plaketten**
- Eine Plakette hat ein Symbol für den Vorgang und seinen Fortschritt: `»` Kopieren, `►` Verschieben, `▼` Papierkorb, `‼` Löschen, `■` Packen, `□` Entpacken.
- Statt einer Prozentzahl kann sie `..` (in der Warteschlange), `?` (wartet auf eine Antwort) oder `!` (fehlgeschlagen) zeigen.
- Ein Klick auf eine Plakette holt diesen Auftrag zurück: sein Fortschrittsfenster, die Frage oder die Fehlermeldung.
- Die Schaltfläche `[≡N]` öffnet die Auftragsliste.
- Ohne Hintergrundaufträge wird dort nichts angezeigt, ob die Statuszeile sichtbar ist oder nicht.

**Abschluss.** Wenn ein Auftrag, der eine Weile im Hintergrund lief, endet, meldet das ein Hinweis; bricht er mit einem Fehler ab, wird der Hinweis auch bei ausgeschalteten Benachrichtigungen gezeigt, und ein Klick auf die Plakette des Auftrags öffnet den Fehler.

---

[Inhalt](index.md)
