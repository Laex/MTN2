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
| Ctrl+Alt+C | die Dateien unter den Cursorn beider Panels vergleichen |
| Ctrl+Alt+H | Prüfsummen (MD5, SHA-1, SHA-256, SHA-512) der ausgewählten Dateien und Ordner; bei einer `.md5`- / `.sha1`- / `.sha256`- / `.sha512`-Datei – sie prüfen |
| Ctrl+Alt+M | ausgewählte Elemente gemeinsam umbenennen: Masken für Name und Erweiterung, Zähler, Suchen und Ersetzen, Groß-/Kleinschreibung |
| Ctrl+C / Ctrl+X / Ctrl+V | Dateien über die Zwischenablage kopieren / ausschneiden / einfügen |
| Alt+Shift+Ins | den vollständigen Pfad in die Zwischenablage kopieren |
| Ctrl+Shift+Ins | nur den Namen (ohne Pfad) in die Zwischenablage kopieren |
| Ctrl+Z | die Datei beschreiben: eine Eingabezeile, der Text wird in `Descript.ion` neben der Datei gespeichert |

**Alt+Shift+Ins** und **Ctrl+Shift+Ins** übernehmen die ausgewählten Elemente (eines pro Zeile) oder, ohne Auswahl, das Element unter dem Cursor; bei `..` – den aktuellen Ordner. Das Ergebnis lässt sich überall mit **Shift+Ins** / **Ctrl+V** einfügen. Ein kurzer Hinweis unten rechts bestätigt das Kopieren (oder meldet, dass nichts zu kopieren ist); er lässt sich unter **Optionen → Schrift / Anzeige...** ausschalten.

Im Dialog **Ctrl+A** werden Datumsangaben im Systemformat eingegeben, die Zeit als `hh:mm:ss` (Sekunden und Zeitteil sind optional). Ein leeres Feld behält das Datum: so werden Datumsangaben angezeigt, die sich zwischen den ausgewählten Dateien unterscheiden. **Aktuell** trägt die aktuelle Zeit in alle drei Felder ein, **Original** stellt die aus den Dateien gelesenen Werte wieder her. „Unterordner einbeziehen“ gilt auch für die Datumsangaben.

Derselbe Dialog enthält die übrigen Dateiattribute: **Komprimiert**, **Verschlüsselt**, **Nicht indiziert**, **Sparse**, **Temporär** und **Offline** (jeweils: beibehalten / setzen / entfernen; Komprimierung, Verschlüsselung und das Sparse-Attribut übernimmt das Dateisystem, ein Volume ohne diese Funktionen meldet einen Fehler). Bei einem Laufwerksstamm (**F4** in der Laufwerksliste **Alt+F1** / **Alt+F2**) stehen oben das Volume (GUID-Pfad) und das Gerät; die Schaltfläche **System-Eigenschaften** öffnet das Windows-Eigenschaftenfenster.

**Windows-Kontextmenü** – dasselbe Menü wie ein Rechtsklick im Explorer: „Öffnen mit“, „Senden an“, Einträge von Archivierer, Virenscanner und Versionsverwaltung und so weiter. Es öffnet sich mit **Shift+F10** oder der **Menütaste** an der Cursorzeile, über **Dateien → Windows-Kontextmenü** oder indem man die rechte Maustaste etwa eine Sekunde auf einer Datei gedrückt hält. Von der Tastatur und aus dem Menü wirkt es auf die Auswahl, ohne Auswahl auf das Element unter dem Cursor (bei `..` – auf den aktuellen Ordner); beim Halten der Maustaste öffnet sich das Menü der Datei unter der Maus. Nur für Dateien und Ordner auf der Festplatte: Archive, SFTP, Papierkorb und Suchergebnisse haben kein Windows-Menü.

Im Dialog Kopieren/Verschieben lassen sich alle Zeitstempel beibehalten, nur neuere Dateien kopieren, der Inhalt symbolischer Links kopieren und eine Ausschlussmaske festlegen. Bei einem Namenskonflikt fragt das Programm, was zu tun ist (überschreiben, überspringen, umbenennen, für alle…).

**Prüfsummen.** Sie werden im Hintergrund berechnet (Esc – abbrechen). In der Ergebnisliste: **Kopieren** – in die Zwischenablage, **Speichern** – nach `<Datei>.sha256` (eine Datei) oder `checksums.sha256` im Panelordner. Die Prüfung markiert jede Zeile mit `OK`, `FAILED` oder `MISSING`. Zeilen der Form `Hash *Name`, `Hash  Name` und `SHA256 (Name) = Hash` werden verstanden.

**Mehrfach umbenennen.** Die Masken für Name und Erweiterung kennen `[N]` (alter Name ohne Erweiterung), `[E]` (alte Erweiterung) und `[C]` (Zähler mit Start, Schritt und Stellenzahl); anderer Text bleibt wie eingegeben. Suchen und Ersetzen wirken auf den neuen Namen und die Erweiterung, die Groß-/Kleinschreibung wird aus der Liste gewählt. Die Liste unter den Feldern zeigt die Paare „alt -> neu“ sofort. Ein leerer, ungültiger, doppelter oder im Ordner bereits vergebener Name (auch von einem anderen Element der Auswahl) ist mit `!` markiert; solange einer übrig ist, tut **Umbenennen** nichts. Es lassen sich nur Elemente eines Ordners wählen. Das Umbenennen läuft wie ein Verschieben als Hintergrundauftrag.

---

[Inhalt](index.md)

**Geschützte Ordner.** Schlägt Kopieren, Verschieben, Löschen, Ordner erstellen oder Umbenennen bei einem lokalen Pfad (zum Beispiel in `C:\Program Files`) mit „Zugriff verweigert“ fehl, bietet das Fehlerfenster **Admin** an, und bei „Ordner erstellen“ und „Umbenennen“ erscheint die Frage „Als Administrator wiederholen?“. Nach einem Ja zeigt Windows die übliche UAC-Abfrage, und MTN2 startet einen kleinen Hilfsprozess mit Administratorrechten; das fehlgeschlagene Element und der Rest des Auftrags laufen dort, mit denselben Fortschritts- und Fehlerfenstern. Vor Ihrer Bestätigung läuft nichts mit diesen Rechten. Solange der Helfer läuft, zeigt der Fenstertitel **[Admin-Helfer]** und ein Hinweis weist darauf hin; er endet von selbst nach zwei Minuten ohne Arbeit oder wenn MTN2 geschlossen wird. Der Helfer kopiert, verschiebt, löscht, erstellt Ordner und speichert Text nur auf lokalen Pfaden: er kann keine Programme starten, und nur das MTN2, das ihn gestartet hat, kann mit ihm sprechen. Archive und virtuelle Ordner kennen diesen Schritt nicht. Wird MTN2 selbst als Administrator gestartet (Rechtsklick, Als Administrator ausführen), zeigt der Titel **[Administrator]** und es wird kein Helfer benötigt; Windows blockiert dann Drag & Drop von nicht erhöhten Programmen wie dem Explorer.
