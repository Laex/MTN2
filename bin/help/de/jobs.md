## Hintergrundaufträge

Kopieren, Verschieben und Löschen laufen im Hintergrund. Das Fortschrittsfenster lässt sich in den Hintergrund schicken; **Ctrl+Shift+J** – die Auftragsliste (Fortschritt, Abbrechen).

Ein Auftrag lässt sich im Fortschrittsfenster mit der Schaltfläche **Abbrechen**, mit **Esc** oder mit einem Klick außerhalb des Fensters stoppen; die Schaltflächen „Abbrechen“ und „Alle abbrechen“ in der Auftragsliste tun dasselbe. Zuerst kommt eine Frage: „Den aktuellen Vorgang abbrechen?“. **Stopp** hält den Auftrag an, **Fortsetzen** (die Standardschaltfläche, auch Esc) kehrt zum vorherigen Fenster zurück. Nach **Stopp** schließt das Fortschrittsfenster sofort, und der Auftrag beendet das Anhalten selbst: bis er die Anforderung bemerkt, bleibt er in der Auftragsliste, ohne Plakette.

Dialogschaltflächen werden mit **Enter** und der **Leertaste** gedrückt: die Schaltfläche sieht gedrückt aus, solange die Taste gehalten wird, und wirkt beim Loslassen. Esc vor dem Loslassen hebt die Schaltfläche an, ohne dass sie wirkt.

Hält ein Kopier-, Verschiebe- oder Löschvorgang mit einem Fehler an, bietet das Fehlerfenster **Wiederholen**, **Überspringen**, **Alle überspringen**, **Abbrechen** und, bei „Zugriff verweigert“ auf einem lokalen Pfad, **Admin** an: es wiederholt das Element und den Rest des Auftrags über den Administrator-Helfer (siehe [Dateioperationen](fileops.md)).

Hintergrundaufträge erscheinen rechts in der Tableiste: eine Plakette pro Auftrag und am Ende eine Listenschaltfläche. Eine Plakette hat ein Symbol für den Vorgang und seinen Fortschritt: `»` Kopieren, `►` Verschieben, `▼` Papierkorb, `‼` Löschen, `■` Packen, `□` Entpacken. Statt einer Prozentzahl kann sie `..` (in der Warteschlange), `?` (wartet auf eine Antwort) oder `!` (fehlgeschlagen) zeigen. Ein Klick auf eine Plakette holt diesen Auftrag zurück: sein Fortschrittsfenster, die Frage oder die Fehlermeldung. Die Schaltfläche `[≡N]` öffnet die Auftragsliste. Ohne Hintergrundaufträge wird dort nichts angezeigt, ob die Statuszeile sichtbar ist oder nicht.

---

[Inhalt](index.md)
