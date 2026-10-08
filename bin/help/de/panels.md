## Panels und Navigation

| Taste | Aktion |
| --- | --- |
| ↑ ↓ PgUp PgDn Home End | den Cursor bewegen |
| ← / → | im Modus „Kurz“ – eine Spalte nach links / rechts; in den anderen Modi – zum ersten / letzten Element (wie Home / End) |
| Enter | Ordner / Archiv betreten, Datei öffnen (laut [Zuordnung](associations.md)); Konsolenprogramm in der eingebauten Konsole ausführen (siehe unten) |
| Backspace | eine Ebene nach oben, wie Enter auf `..` (bei leerer Befehlszeile; sonst löscht es dort ein Zeichen) |
| Ctrl+PgUp / Ctrl+PgDn | eine Ebene nach oben / den Ordner unter dem Cursor betreten, wie in FAR; bei einer Datei öffnet Ctrl+PgDn sie als Archiv (siehe [Archive](archives.md)) |
| Shift+Enter | eine Datei oder einen Befehl in einem separaten Betriebssystemfenster ausführen |
| Alt+Shift+Enter | die Befehlszeile im Hintergrund ausführen: die Konsole zeigt sie kurz, dann kommen die Panels zurück |
| Ctrl+Alt+Enter | die Befehlszeile in einem neuen Terminal-Tab ausführen (die Shell der Hintergrundkonsole) |
| Tab | das aktive Panel wechseln |
| Ctrl+\\ | zur Laufwerkswurzel (in einem Archiv – das Archiv verlassen) |
| Alt+← / Alt+→ | zurück / vor im Ordnerverlauf |
| Ctrl+U | die Panels tauschen |
| Ctrl+] | passives Panel := Ordner des aktiven |
| Ctrl+[ | aktives Panel := Ordner des passiven |
| Ctrl+F1 / Ctrl+F2 | das linke / rechte Panel aus- / einblenden |
| Ctrl+P | das inaktive Panel aus- / einblenden |
| Ctrl+L | Infopanel (Laufwerk, Speicher) auf der anderen Seite |
| Ctrl+H | versteckte und Systemdateien zeigen / verbergen |
| Ctrl+R | das Panel aktualisieren |
| Ctrl+Q | Schnellansicht der Datei im anderen Panel: Bild, Text, Markdown oder Hex |
| Alt+F10 | Ordnerbaum des Laufwerks über dem aktiven Panel (siehe unten) |
| Alt+Buchstabe | Schnellsuche nach Name im Panel |

**Ordnerbaum (Alt+F10)** öffnet sich über dem aktiven Panel: die Laufwerkswurzel mit geöffnetem Pfad zum aktuellen Ordner und dem Cursor darauf. ↑ ↓ PgUp PgDn Home End bewegen, → oder `+` öffnet einen Zweig (`[+]─`) oder tritt in ihn ein, ← oder `-` schließt einen Zweig (`[-]─`) oder geht zum übergeordneten Ordner, ein Buchstabe springt zum nächsten Ordner, der damit beginnt. Das andere Panel wechselt in den Ordner unter dem Cursor, sobald der Cursor zur Ruhe kommt. Enter öffnet den Ordner im aktiven Panel und schließt den Baum; Esc oder Alt+F10 schließt den Baum, und dasselbe Panel erscheint wieder. Tab oder ein Klick auf das andere Panel verschiebt den Fokus dorthin, und der Baum bleibt, wie ein FAR-Baumpanel; Tab oder ein Klick auf den Rahmen des Baums bringt den Fokus zurück. Mit der Maus funktioniert der Baum wie ein Index: ein Klick auf einen Ordner zeigt ihn sofort im anderen Panel und verschiebt den Fokus dorthin, ein Klick auf `[+]` / `[-]` öffnet oder schließt den Zweig, ohne den Fokus zu verschieben; das Mausrad blättert den Baum, ohne den Cursor zu bewegen. Der Baum folgt auch dem anderen Panel: wechselt es in einen anderen Ordner, öffnet der Baum den Pfad dorthin und setzt den Cursor darauf und baut sich für ein anderes Laufwerk neu auf. Ordner werden im Hintergrund gelesen; wechselt das Panel unter dem Baum währenddessen in einen anderen Ordner, schließt sich der Baum. Der Baum ist immer nur über einem Panel geöffnet.

**Schnellansicht (Ctrl+Q)** zeigt die Datei unter dem Cursor im anderen Panel: ein Bild, Text (die Kodierung wird erkannt), dargestelltes Markdown oder einen Hex-Dump einer Binärdatei; große Dateien werden gestreamt. Das Mausrad darüber blättert die Vorschau. Dateien auf SFTP und große Dateien in Archiven werden nicht bei jeder Cursorbewegung gelesen – das Panel schlägt vor, sie mit F3 zu öffnen. Tab oder erneut Ctrl+Q schließt die Schnellansicht.

**Konsolenprogramme** (eine `.exe` des Konsolen-Subsystems, `.bat`, `.cmd`, `.ps1`) laufen mit Enter so, dass ihre Ausgabe auf dem Bildschirm bleibt und nicht in einem separaten Windows-Fenster erscheint:
- in der Hintergrundkonsole (Ctrl+O), wenn ihre Shell cmd, PowerShell oder pwsh ist und nichts darin läuft: wie ein in die Befehlszeile eingegebener Befehl;
- sonst (eine WSL-, Git-Bash- oder SSH-Konsole oder eine, die mit einem anderen Befehl beschäftigt ist) – in einem neuen Terminal-Tab mit cmd, bei einer `.ps1` mit PowerShell; der Tab bleibt nach dem Ende des Programms offen.

Fensterprogramme und Dokumente öffnen sich wie bisher mit ihrem Windows-Programm. **Shift+Enter** führt weiterhin jede Datei in einem separaten Fenster aus.

Ein Mausklick setzt den Cursor, ein Doppelklick wirkt wie Enter. Dateien lassen sich mit der Maus zwischen den Panels und zu anderen Programmen (und zurück) ziehen.

---

[Inhalt](index.md)
