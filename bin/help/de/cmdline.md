## Befehlszeile und Konsole

Die Befehlszeile befindet sich immer unter den Panels: einfach losschreiben. Ein Befehl läuft in der eingebauten Konsole; seine Ausgabe zeigt **Ctrl+O**.

| Taste | Aktion |
| --- | --- |
| Enter | Befehl ausführen; ein eingegebener Ordnerpfad wechselt in den Ordner, eine Datei (auch ein mit Ctrl+Enter eingefügter Name) wird gestartet: ein Konsolenprogramm in der eingebauten Konsole, alles andere mit seinem Windows-Programm. Danach geht der Fokus zurück ins Panel und die Pfeiltasten bewegen wieder den Cursor |
| Ctrl+↓ / Ctrl+↑ | Befehlszeile fokussieren / zurück zum Panel |
| ↑ / ↓ (beim Eingeben eines Befehls) | Befehlsverlauf |
| Tab | Vervollständigung: ein Name aus dem Panel oder ein Pfad von der Festplatte, wenn das Wort `\`, `/` oder `X:` enthält (wiederholtes Drücken wechselt durch die Treffer) |
| Ctrl+↓ / Alt+↓ (Zeile fokussiert) | Befehlsverlauf als Liste: Enter – in die Zeile übernehmen, Del – aus dem Verlauf entfernen, Esc – schließen |
| Ctrl+Enter | Namen des Elements unter dem Cursor einfügen |
| Ctrl+F, Ctrl+Shift+Enter | vollständigen Pfad des Elements einfügen |
| Alt+Shift+Enter | Befehlszeile im Hintergrund ausführen: die Konsole zeigt kurz den Start, dann kommen die Panels zurück (**Optionen → Konsole...** weiter unten) |
| Ctrl+Alt+Enter | Befehlszeile in einem neuen Terminal-Tab ausführen: ein neuer Arbeitsbereich-Tab mit der Shell der Hintergrundkonsole (cmd, PowerShell, WSL, ...), der Befehl startet dort und der Tab bleibt offen |
| Esc | Schritt für Schritt: Zeile löschen → Fokus ans Panel zurückgeben → Konsole zeigen. Bei leerer Zeile entfällt der erste Schritt; bei Fokus auf dem Panel zeigt Esc sofort die Konsole |
| Ctrl+O | Panels ↔ Konsole |
| Ctrl+Shift+O | Ordner zwischen aktivem Panel und Konsole abgleichen |
| Ctrl+Alt+O | Shell der Hintergrundkonsole wählen (cmd, PowerShell, WSL, …) |

**Befehle → Hintergrundkonsole...** ist derselbe Dialog. **Shell beim Programmstart starten** ist standardmäßig aus: die Shell startet beim ersten **Ctrl+O** oder beim ersten Befehl aus der Befehlszeile. Mit eingeschalteter Option startet die Shell wie früher zusammen mit dem Programm.

**In der Konsole:** **Ctrl+C** unterbricht den Befehl; **Esc** blendet die Konsole nur aus und beendet den Prozess nicht. Das Mausrad blättert durch die Ausgabe. Text wird mit der Maus ausgewählt (siehe [Arbeiten mit Text und Maus](text.md)).

**Einfügen in die Konsole** (**Ctrl+V**, **Shift+Ins**): jeder Zeilenumbruch geht als Enter an die Shell, die eingefügten Zeilen laufen also nacheinander, auch die letzte. Bei eingeschaltetem **Mehrzeiliges Einfügen bestätigen** fragt das Programm vorher nach.

**Optionen → Konsole...** legt die Größe des Scrollbacks von Konsole und Terminals fest (1000 – 50.000 Zeilen, standardmäßig 10.000), die Bestätigung beim mehrzeiligen Einfügen (aus; ein Vollbildprogramm wie vim fragt nie), das Entfernen von Leerzeichen am Zeilenende beim Kopieren und beim Einfügen sowie **Nach Befehlsende immer zu den Panels zurückkehren** (aus). Bei eingeschalteter Option führt ein aus der Befehlszeile unter den Panels gestarteter Befehl zurück zu den Panels, sobald die Shell wieder ihren Prompt zeigt; ein in der Hintergrundkonsole (Ctrl+O) eingegebener Befehl bleibt immer in der Konsole. **Alt+Shift+Enter** führt die Befehlszeile in der Konsole im Hintergrund aus: die Konsole wird für die unter **Hintergrundausführung** eingestellte Zeit gezeigt (0,5 – 10 s, standardmäßig 2 s) und die Panels kommen von selbst zurück; eine vorher in der Konsole gedrückte Taste hält sie im Vordergrund, und der Befehl läuft in beiden Fällen weiter. Änderungen gelten sofort, auch für geöffnete Konsolen.

**Befehle → Konsolenausgabe speichern...** schreibt den Scrollback der Hintergrundkonsole (Ctrl+O) in eine UTF-8-Textdatei; **Konsolenpuffer leeren** löscht ihn, die Shell läuft weiter.

---

[Inhalt](index.md)
