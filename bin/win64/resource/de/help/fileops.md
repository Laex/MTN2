## Dateioperationen

| Taste | Aktion |
| --- | --- |
| F3 | Datei ansehen; bei Ordnern – Größe der ausgewählten Ordner berechnen (Esc – abbrechen) |
| F4 | bearbeiten |
| Shift+F4 | Datei erstellen |
| F5 | kopieren |
| Shift+F5 | unter anderem Namen im selben Ordner kopieren |
| F6 | verschieben / umbenennen |
| Shift+F6 | das Element unter dem Cursor umbenennen |
| F7 | Ordner erstellen |
| Alt+F6 | Link erstellen (symbolischer Link, Hardlink, Junction) |
| F8, Del | in den Papierkorb löschen |
| Shift+F8, Shift+Del | endgültig löschen |
| Ctrl+A | Attribute, Besitzer und Datumsangaben (erstellt / geändert / Zugriff) |
| Alt+Enter | das Windows-Fenster „Eigenschaften“ (für die Auswahl oder das Element unter dem Cursor; nur Dateien und Ordner auf der Festplatte) |
| Shift+F10, Menütaste | das Windows-Kontextmenü (für die Auswahl oder das Element unter dem Cursor) |
| Ctrl+Alt+C | die Dateien unter den Cursorn beider Panels oder die zwei markierten Dateien des aktiven Panels vergleichen; das Fenster zeigt Größe, Änderungszeit und das Ergebnis des Inhaltsvergleichs |
| Ctrl+Alt+H | Prüfsummen (MD5, SHA-1, SHA-256, SHA-512) der ausgewählten Dateien und Ordner; bei einer `.md5`- / `.sha1`- / `.sha256`- / `.sha512`-Datei – sie prüfen |
| Ctrl+Alt+N | ausgewählte Elemente gemeinsam umbenennen: Masken für Name und Erweiterung, Zähler, Suchen und Ersetzen, Groß-/Kleinschreibung |
| Ctrl+C / Ctrl+X / Ctrl+V | Dateien über die Zwischenablage kopieren / ausschneiden / einfügen |
| Alt+Shift+Ins | den vollständigen Pfad in die Zwischenablage kopieren |
| Ctrl+Shift+Ins | nur den Namen (ohne Pfad) in die Zwischenablage kopieren |

**Alt+Shift+Ins** und **Ctrl+Shift+Ins** übernehmen die ausgewählten Elemente (eines pro Zeile) oder, ohne Auswahl, das Element unter dem Cursor; bei `..` – den aktuellen Ordner. Das Ergebnis lässt sich überall mit **Shift+Ins** / **Ctrl+V** einfügen. Ein kurzer Hinweis unten rechts bestätigt das Kopieren (oder meldet, dass nichts zu kopieren ist); er lässt sich unter **Optionen → Oberfläche...** ausschalten.

<!--attributes-->Im Dialog **Ctrl+A** werden Datumsangaben im Systemformat eingegeben, die Zeit als `hh:mm:ss` (Sekunden und Zeitteil sind optional).
- Ein leeres Feld behält das Datum: so werden Datumsangaben angezeigt, die sich zwischen den ausgewählten Dateien unterscheiden.
- **Aktuell** trägt die aktuelle Zeit in alle drei Felder ein, **Original** stellt die aus den Dateien gelesenen Werte wieder her.
- „Unterordner einbeziehen“ gilt auch für die Datumsangaben.

Derselbe Dialog enthält die übrigen Dateiattribute: **Komprimiert**, **Verschlüsselt**, **Nicht indiziert**, **Sparse**, **Temporär** und **Offline** (jeweils: beibehalten / setzen / entfernen; Komprimierung, Verschlüsselung und das Sparse-Attribut übernimmt das Dateisystem, ein Volume ohne diese Funktionen meldet einen Fehler).

**Laufwerksstamm.** Bei einem Laufwerksstamm (**F4** in der Laufwerksliste **Alt+F1** / **Alt+F2**) stehen oben das Volume (GUID-Pfad) und das Gerät; die Schaltfläche **System-Eigenschaften** öffnet das Windows-Eigenschaftenfenster.

**Windows-Kontextmenü** – dasselbe Menü wie ein Rechtsklick im Explorer: „Öffnen mit“, „Senden an“, Einträge von Archivierer, Virenscanner und Versionsverwaltung und so weiter.

**So öffnet man es:** **Shift+F10** oder die **Menütaste** an der Cursorzeile, **Dateien → Windows-Kontextmenü** oder die rechte Maustaste etwa eine Sekunde auf einer Datei gedrückt halten.

**Worauf es wirkt**
- Von der Tastatur und aus dem Menü – auf die Auswahl, ohne Auswahl auf das Element unter dem Cursor (bei `..` – auf den aktuellen Ordner).
- Beim Halten der Maustaste öffnet sich das Menü der Datei unter der Maus.

Nur für Dateien und Ordner auf der Festplatte: Archive, SFTP, Papierkorb und Suchergebnisse haben kein Windows-Menü.

<!--multi-rename-->**Mehrfach-Umbenennen (Ctrl+Alt+N).** Dateien > Mehrfach-Umbenennen... benennt die ausgewählten Elemente eines Ordners in einem Zug um. Die Masken für Name und Erweiterung verstehen `[N]` (alter Name), `[E]` (alte Erweiterung), `[C]` (Zähler mit Start, Schritt und Stellenzahl), `[Date]`, `[Time]`, `[Year]`, `[Month]`, `[Day]`, `[Parent]`, `[Size]` sowie die Metadatenwerte `[Dim]`, `[Camera]`, `[Artist]`, `[Title]`; anderer Text bleibt wie getippt. Suchen und Ersetzen (wahlweise als regulärer Ausdruck mit `$1`, `$2`) und die Groß-/Kleinschreibung gelten für den neuen Namen. Die Liste unter den Feldern zeigt beim Tippen die Paare „alt -> neu“; ein leerer, ungültiger, doppelter oder bereits belegter Name wird mit `!` markiert, und **Umbenennen** tut nichts, solange einer übrig ist. Das Umbenennen läuft als Hintergrundauftrag.

<!--copy-->Im Dialog Kopieren/Verschieben lassen sich alle Zeitstempel beibehalten, nur neuere Dateien kopieren, der Inhalt symbolischer Links kopieren und eine Ausschlussmaske festlegen. Bei einem Namenskonflikt fragt das Programm, was zu tun ist (überschreiben, überspringen, umbenennen, für alle…).

---

[Inhalt](index.md)

<!--admin-->**Geschützte Ordner.** Schlägt Kopieren, Verschieben, Löschen, Ordner erstellen oder Umbenennen bei einem lokalen Pfad (zum Beispiel in `C:\Program Files`) mit „Zugriff verweigert“ fehl, bietet das Fehlerfenster **Admin** an, und bei „Ordner erstellen“ und „Umbenennen“ erscheint die Frage „Als Administrator wiederholen?“.

**So funktioniert es**
- Nach einem Ja zeigt Windows die übliche UAC-Abfrage, und MTN2 startet einen kleinen Hilfsprozess mit Administratorrechten.
- Das fehlgeschlagene Element und der Rest des Auftrags laufen dort, mit denselben Fortschritts- und Fehlerfenstern.
- Vor Ihrer Bestätigung läuft nichts mit diesen Rechten.
- Solange der Helfer läuft, zeigt der Fenstertitel **[Admin-Helfer]** und ein Hinweis weist darauf hin; er endet von selbst nach zwei Minuten ohne Arbeit oder wenn MTN2 geschlossen wird.

**Grenzen**
- Der Helfer kopiert, verschiebt, löscht, erstellt Ordner und speichert Text nur auf lokalen Pfaden: er kann keine Programme starten, und nur das MTN2, das ihn gestartet hat, kann mit ihm sprechen.
- Archive und virtuelle Ordner kennen diesen Schritt nicht.

**MTN2 als Administrator.** Wird MTN2 selbst als Administrator gestartet (Rechtsklick, Als Administrator ausführen), zeigt der Titel **[Administrator]** und es wird kein Helfer benötigt; Windows blockiert dann Drag & Drop von nicht erhöhten Programmen wie dem Explorer.
