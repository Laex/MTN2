## Einstellungen

Das Menü **Optionen** (F9):
- **Farbschema...** – das Aussehen wählen; wirkt sofort. **Anpassen...** öffnet den Editor des gewählten Farbschemas: Bereiche (Farben von Fenstern, Dialogen, Schaltflächen, Cursor, Panels und mehr, Markdown, Textstile, Zeichen, Rahmen) mit ihren Werten; **Enter** auf einer Zeile bearbeitet den Wert (eine Farbe wird als `#RRGGBB` eingegeben oder mit **F9** / der Schaltfläche **[...]** gewählt), **Erben** gibt den Wert des Basis-Farbschemas zurück; Zeilen mit einem Sternchen werden vom Farbschema selbst gesetzt. Eine Farbe ist ein Wert `#RRGGBB`, ein Verweis auf eine andere Rolle des Farbschemas (`@cursor.bg`) oder ein Name aus der Palette. Der Bereich **Basen** führt die Farbschemata auf, auf denen dieses aufbaut (mehrere durch `;` getrennt, spätere überschreiben frühere). Änderungen wirken sofort. **Speichern** schreibt das Farbschema in eine Datei. Eingebaute Farbschemata sind schreibgeschützt: eine Kopie eines eingebauten Farbschemas wird unter neuem Namen gespeichert (eine Datei im Ordner `themes` des Einstellungsordners), ein eigenes Farbschema wird mit **Speichern** an Ort und Stelle aktualisiert, und **Speichern unter...** schreibt es unter anderem Namen. **Neu...** erstellt ein Farbschema von Grund auf („leer“) oder aus einem beliebigen anderen. **Löschen** entfernt ein eigenes Farbschema. Wird das Farbschema der gespeicherten Sitzung nicht gefunden, meldet das Programm das und verwendet das klassische Far-Farbschema.
- **Schrift / Anzeige...** – Schrift, Größe, Zoom, Cursorblinken, Dateisymbole im Panel, **Zeilenabstand** (siehe unten), Popup-Hinweise, **Dateien mit der Maus ziehen** (abschaltbar), die **Titelleiste, Menüleiste, F-Tastenleiste und Statuszeile** (eine ausgeblendete Zeile geht an die Panels; bei ausgeblendeter Menüleiste zeigt F9 sie über der obersten Zeile, solange das Menü offen ist; bei ausgeblendeter Titelleiste wandern die Schaltflächen **[_] [□] [x]** ans rechte Ende der Menüleiste, oder der Tableiste, wenn auch sie ausgeblendet ist, der Fenstertitel steht im freien Bereich der Tableiste, und das Fenster wird an den freien Stellen von Menü- und Tableiste gezogen und an seinen Rändern in der Größe geändert; ein Rechtsklick auf eine freie Stelle der Tableiste öffnet das Hauptmenü, wie F9), **Schatten** von Fenstern und Schaltflächen (Klassisch, Weich oder Keine; die Abdunkelung hinter einem Dialog wird dabei aufgehellt oder entfällt), das Aussehen **markierter Dateien** („Textfarbe“ – nur die Buchstaben ändern die Farbe, wie in Far; „Zeilenhintergrund“ – zusätzlich ein Hintergrundband über die ganze Zeile) und die **Oberflächensprache** (English / Русский / Deutsch); alles wirkt ohne Neustart. Das Kontrollfeld **„Alles auswählen auch Ordner“** im selben Dialog sorgt dafür, dass Shift+Grau + / Shift+Grau − und das Auswählen nach Endung auch Ordner erfassen (standardmäßig nur Dateien, wie in Far).
- **Spalten...** – die Spalten des Modus „Eigene“.
- **Konsole...** – die Scrollback-Größe von Konsole und Terminals, Bestätigung beim mehrzeiligen Einfügen, Entfernen von Leerzeichen am Zeilenende beim Kopieren und Einfügen, Rückkehr zu den Panels, wenn ein Befehl aus der Befehlszeile endet (mehr in der Hilfe zur Befehlszeile).
- **Einstellungen exportieren... / Einstellungen importieren...** – die Einstellungen als eine Zip-Datei: Sitzung und Anzeigeoptionen, Tasten, Benutzermenü, Zuordnungen, Hotlist, Liste der SSH-Verbindungen, Arbeitsbereiche, eigene Farbschemata; Verläufe sind nicht enthalten. Das Dateinamenfeld ist ein Eingabefeld mit einer ↓-Auswahlliste der zuvor verwendeten Dateien; standardmäßig ist es `mtn2-settings.zip` im Ordner des aktiven Panels. Vor einem Import werden die ersetzten Dateien als `settings-backup.zip` im Einstellungsordner gesichert. Die neuen Einstellungen wirken nach einem Neustart von MTN2.
- **Farbgruppen...** – Zeilenfarben nach Namensmasken; sie werden im Farbschema gespeichert, eine Änderung bei einem eingebauten Farbschema wird also als neues Farbschema gespeichert (das Programm fragt nach seinem Namen). **F9** auf einem Farbfeld oder ein Klick auf die Schaltfläche **[...]** an seinem rechten Ende (sie zeigt die Farbe des Feldes) öffnet die Farbauswahl (siehe unten).
- **Tastenbelegung...** – Tasten ansehen und ändern.
- **Plugins...** – installierte Plugins. Beim ersten Start sind alle Plugins ausgeschaltet. **Leertaste** auf einer Zeile schaltet das Plugin aus oder ein (`[x]` ist ein, `[ ]` ist aus); die Wahl gilt mit **OK** und bleibt zwischen den Starts erhalten, **Abbrechen** verwirft sie. **Berechtigungen...** öffnet einen Dialog: dem Plugin erlauben, eingebaute Handler zu ersetzen (`[replaces .zip: on]`) und was sein Manifest anfordert, zum Beispiel Dateien über das Programm zu lesen (`[needs vfs.read: on]`). **Ctrl+Up** und **Ctrl+Down** ändern die Ladereihenfolge der Plugins (sie spielt zwischen Plugins gleicher Priorität eine Rolle und gilt ab dem nächsten Start). **Info** zeigt, wofür das Plugin da ist und was es hinzugefügt hat (Befehle, Tasten, Dateitypen, Schemata), und öffnet seine Hilfeseite, wenn es eine hat.
- **Externer Viewer/Editor...** – die Befehle Alt+F3 / Alt+F4; `%1` ist der Dateipfad (ohne `%1` wird der Pfad am Ende angehängt), z. B. `"C:\Program Files\Notepad++\notepad++.exe" %1`.
- **Markdown-Farben...** – Farben der Markdown-Ansicht (F3 auf einer `.md`-Datei): Vordergrund und Hintergrund (`#RRGGBB`) und ein **Textstil** (die Liste: Farbschema, Normal, Fett, Kursiv, Fett kursiv, Unterstrichen, Durchgestrichen und Kombinationen) für jedes Element – Überschriften, Fett, Kursiv, Durchgestrichen, Code, Zitat, Listenmarkierungen, Linien, Links, Tabellen. Ein leeres Feld oder **Farbschema** in der Stilliste behält das Eigene des Farbschemas; **Normal** schaltet den Stil aus, den das Element hat (zum Beispiel die Unterstreichung von Links); **F9** auf einem Feld oder ein Klick auf seine Schaltfläche **[...]** öffnet die Farbauswahl. Die Zeile **Text / Dokument** legt die Textfarbe und den Hintergrund der ganzen Markdown-Ansicht fest (nur für Markdown, andere Dateien behalten die Farben des Farbschemas); Elemente ohne eigenen Hintergrund folgen ihr. **Aus Obsidian importieren...** liest die Farben aus einem Obsidian-Design (`theme.css`, zum Beispiel `<Tresor>\.obsidian\themes\<Design>\theme.css`); die Palette **Dunkel** oder **Hell** wird im Importdialog gewählt, und die importierten Farben und Textstile (Gewicht, Kursivschrift und Unterstreichung, die das Design für Überschriften, Fett, Links, Zitate und Tabellenköpfe festlegt) ersetzen die Felder und Listen (nichts wird gespeichert, bevor OK gedrückt wird). **Zurücksetzen** leert alle Felder und setzt jeden Stil auf **Farbschema**, sodass die eigenen Farben und Stile des Farbschemas gelten. Das Beispiel neben einer Zeile wird mit ihren Farben und ihrem Stil gezeichnet. Gespeichert wird im aktiven Farbschema: bei einem eingebauten Farbschema fragt das Programm nach dem Namen eines neuen, ein eigenes wird an Ort und Stelle aktualisiert; die Felder enthalten nur, was das Farbschema selbst festlegt (der Rest wird geerbt).
- **Zoom**: Ctrl+Mausrad, **Ctrl+0** – zurücksetzen.

### Farbauswahl

Die Auswahl hat ein Raster aus Farbfeldern (Farbtöne nach rechts, hell nach dunkel nach unten; die unterste Zeile ist grau), Schieberegler **H, S, L** (Farbton, Sättigung, Helligkeit) und **R, G, B** sowie ein **Hex**-Feld neben zwei Farbfeldern: die Farbe **vorher**, als die Auswahl geöffnet wurde, und die Farbe **jetzt**. **Up / Down** wechseln zwischen Raster, Schiebereglern und Hex-Feld; **Left / Right** bewegen sich im Raster oder ändern einen Regler um 1 (**Shift** – um 10, **PgUp / PgDn** – um 10, **Home / End** – an die Enden). Das Raster verwendet die aktuelle Sättigung, der Regler **S** macht es also blasser oder kräftiger. Ein Mausklick wählt ein Farbfeld oder stellt einen Regler ein; ein Klick auf das Feld **vorher** kehrt zur ursprünglichen Farbe zurück. **Übernehmen** übernimmt die Farbe, **Farbschema-Farbe** leert das Feld, sodass wieder die Farbe des Farbschemas gilt.

### Schrift und Zeilenabstand

Das Kontrollfeld **Zeilenabstand (wie im Terminal)** unter **Optionen → Schrift / Anzeige...** macht die Zeilen um 15 % der Schriftgröße höher; der Text bleibt in der Zeile zentriert, Rahmen und Hervorhebungen dehnen sich über die ganze Höhe. Standardmäßig ist es aus: die Zeilen sind so hoch wie die Zeile der Schrift, und es passen mehr davon auf den Bildschirm. Für Cascadia Mono 11 pt sind das 17 Pixel ohne Abstand und 19 mit ihm – genauso wie im Windows Terminal.

Die Schriftgröße wird in typografischen Punkten angegeben, wie im Windows Terminal und in der Windows-Konsole: 6 bis 24 pt, in Halbpunktschritten von 8 bis 12 pt. Bei 100 % Windows-Skalierung ist 1 pt = 4/3 Pixel: 10,5 pt sind 14 Pixel (der frühere Standard), 11 pt sind 14,7 Pixel.

Zwei weitere Optionen im selben Dialog machen den Text schärfer:
- **Schriftgröße an Geräte-Pixel anpassen** rundet die Buchstabengröße auf ganze physische Bildschirmpixel. Bei 125 % oder 150 % Windows-Skalierung und gebrochenen Größen (11 pt) haben die Striche dann gleiches Gewicht. Die Zellengröße kann sich leicht ändern. Standardmäßig aus.
- **Textkontrast** (Aus, Niedrig, Mittel, Hoch) füllt den schwachen Antialiasing-Saum aus: dünner heller Text auf dunklem Hintergrund liest sich fester. Standardmäßig aus.
- **Zellenbreite** und **Zellenhöhe** fügen jeder Zelle 0 bis 4 physische Pixel hinzu. Sie helfen bei einer Schrift, deren Buchstaben sich berühren oder deren Zeilen zu eng sitzen. Die Buchstaben bleiben in der Zelle zentriert, Rahmen füllen sie vollständig aus. Standardmäßig 0.

#### Warum der Text anders aussieht als in Far

Far zeichnet seinen Text nicht selbst: das tut das Konsolenfenster, in dem es läuft – das Windows Terminal oder die klassische Windows-Konsole – mit eigener Schrift und eigenen Regeln. Bei gleicher Schrift, Größe und gleichen Farben zeichnen MTN2 und Far dieselben Buchstaben: Strichstärke und Antialiasing stimmen überein. Die Unterschiede kommen von Einstellungen:
- **Schrift und Größe.** Das Windows Terminal verwendet standardmäßig Cascadia Mono 11 pt. MTN2 nimmt Schrift und Größe aus Schrift / Anzeige (Cascadia Mono, falls installiert, sonst Consolas; 10,5 pt). Schmale, leichte Schriften wie Ubuntu Mono wirken dünner und blasser, besonders auf Blau.
- **Zeilenhöhe.** Das Windows Terminal fügt etwa 15 % der Schriftgröße zur Zeile der Schrift hinzu. In MTN2 ist das das Kontrollfeld Zeilenabstand; ohne es sind die Zeilen enger. Die klassische Windows-Konsole nimmt die Zeilenhöhe aus den Windows-Metriken der Schrift, die weitere 1–3 Pixel höher sein können (Cascadia Mono 11 pt – 20 Pixel).
- **Farben.** Die Farben von MTN2 stammen aus seinem Farbschema; die von Far aus seiner eigenen Hervorhebung und dem Farbschema des Terminals. Im Standard-Farbschema sind einfache Dateien hellgrau; in Far sind sie meist cyan, mit doppeltem Kontrast auf Blau, der Text wirkt also kräftiger.
- **Antialiasing.** MTN2 verwendet Graustufen-Antialiasing. Das Windows Terminal ebenfalls, wenn der `antialiasingMode` des Profils `grayscale` ist (der Standard); bei `cleartype` bekommen Buchstaben farbige Säume. Die klassische Windows-Konsole verwendet ClearType, wenn es in Windows eingeschaltet ist.
- **Windows-Skalierung.** Beide zeichnen Text in physischen Bildschirmpixeln, er ist bei 125 % und 150 % also gleich scharf.

#### Wann sie übereinstimmen

MTN2 stimmt mit Far im Windows Terminal in Zellengröße, Strichstärke und Zeilenhöhe überein, wenn:
- die Schrift dieselbe ist (der Standard des Windows Terminals ist Cascadia Mono);
- die Größe dieselbe ist (der Standard des Windows Terminals ist 11 pt);
- Zeilenabstand (wie im Terminal) eingeschaltet ist;
- das Profil des Windows Terminals `grayscale`-Antialiasing verwendet;
- das Farbschema von MTN2 und Far ähnliche Farben verwenden.

Mit der klassischen Windows-Konsole (Far ohne Windows Terminal) stimmen sie nicht genau überein: ihre Zeilenhöhe und ihr ClearType sind ihre eigenen.

### Hinweise

Befehle, die auf dem Bildschirm nichts ändern, bestätigen sich selbst mit einem kurzen Hinweis unten rechts; er verschwindet nach ein paar Sekunden und nimmt keine Tasten entgegen. Hinweise erscheinen bei:
- **Alt+Shift+Ins** / **Ctrl+Shift+Ins** – der kopierte Pfad / Name (oder „Nichts zu kopieren“);
- **Ctrl+C** / **Ctrl+X** (**Ctrl+Ins** / **Ctrl+Del**) im Panel – die in die Zwischenablage gelegten Dateien;
- dem Kopieren von Text im Viewer / Editor (ohne Auswahl – die aktuelle Zeile), in der Befehlszeile und in einem Terminal;
- **Ctrl+R** – das aktualisierte Panel;
- **Ctrl+Shift+O** – der Ordner, in den die Konsole gewechselt ist;
- **Ctrl+Alt+R** – das aus dem Papierkorb wiederhergestellte Element;
- **Ctrl+Alt+D** – der zur Hotlist hinzugefügte Ordner;
- einer Auswahl nach Maske (**Grau +/−**, **Ctrl+Grau +/−**, **Alt+Grau +/−**), die nichts geändert hat – in Rot angezeigt.

Hinweise werden unter **Optionen → Schrift / Anzeige...** ausgeschaltet („Popup-Hinweise anzeigen“). Eine Ausnahme ist der Hinweis zur Update-Suche: er hat ein eigenes Kontrollfeld (siehe [Updates](updates.md)).

### Updates

Die Suche nach neuen Versionen und ihre Installation, ihre Einstellungen und was über das Netzwerk geht, stehen auf der Seite [Updates](updates.md).

---

[Inhalt](index.md)
