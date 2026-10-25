## Benutzermenü (F2)

Ihre eigene Befehlsliste: Einträge mit Tasten, verschachtelte Untermenüs und Trennlinien. Ein Befehl läuft in der Panelkonsole, im Ordner des aktiven Panels; seine Ausgabe zeigt **Ctrl+O**.

**Zwei Menüs:**

- **Haupt** – gilt für alle Ordner.
- **Ordnermenü** – die Datei `.mtn2menu.json` in einem Ordner. Sie gilt für diesen Ordner und alle darunterliegenden; gibt es solche Dateien auf mehreren Ebenen, wird die nächste verwendet. Praktisch für Projekte: ein Menü in der Wurzel eines Repositorys steht in jedem seiner Unterordner zur Verfügung.

**F2** öffnet das Ordnermenü, wenn es eines gibt, sonst das Hauptmenü. **Shift+F2** in einem geöffneten Menü wechselt Ordnermenü ↔ Hauptmenü. Ein Menü für einen Ordner erstellen: F2, dann Shift+F2 (ein leeres Menü dieses Ordners öffnet sich) und **Ins**.

**Tasten im Menü:**

| Taste | Aktion |
| --- | --- |
| Enter, Taste des Eintrags, Klick | den Befehl ausführen oder das Untermenü betreten |
| → | das Untermenü betreten |
| ← / Esc | eine Ebene nach oben; Esc auf der obersten Ebene schließt das Menü |
| Ins | einen Eintrag vor dem Cursor hinzufügen |
| F4 | den Eintrag bearbeiten |
| Del | den Eintrag löschen (ein Untermenü – zusammen mit seinem Inhalt) |
| Ctrl+↑ / Ctrl+↓ | den Eintrag verschieben |
| Shift+F2 | Ordnermenü ↔ Hauptmenü |

**Menüeintrag:** Taste (ein Zeichen), Typ (Befehl / Untermenü / Trennlinie), Beschriftung und Befehl. Ist die Beschriftung leer, wird der Befehl selbst angezeigt.

**Ersetzungen in einem Befehl:**

| Muster | Wird ersetzt durch |
| --- | --- |
| `!.!` | Name der Datei unter dem Cursor mit Endung |
| `!` | Dateiname ohne Endung |
| `!\` | Panelordner mit abschließendem `\` |
| `!:` | Laufwerk des Ordners (`C:`) |
| `!&` | ausgewählte Namen, durch Leerzeichen getrennt (oder der Name unter dem Cursor); Namen mit Leerzeichen werden in Anführungszeichen gesetzt |
| `!@!` | Pfad zu einer temporären Datei mit den vollständigen Pfaden der ausgewählten Elemente (einer pro Zeile, UTF-8) |
| `!?Frage?Antwort!` | Antwort des Benutzers: vor der Ausführung erscheint ein Fenster mit der Frage und einer vorgeschlagenen Antwort; Abbrechen bricht den Befehl ab |
| `!#` | weitere Ersetzungen werden dem **passiven** Panel entnommen |
| `!^` | weitere Ersetzungen – wieder aus dem **aktiven** Panel |
| `!!` | das Zeichen `!` selbst |

Namen mit Leerzeichen werden unverändert eingesetzt – setzen Sie sie selbst in Anführungszeichen: `"!\!.!"`.

**Beispiele:**

```
notepad.exe "!\!.!"                    die Datei im Editor öffnen
explorer.exe /select,"!\!.!"           die Datei im Explorer anzeigen
certutil -hashfile "!.!" SHA256        Prüfsumme
fc "!.!" "!#!\!.!"                     mit der gleichnamigen Datei im anderen Panel vergleichen
7z a "!?Archivname?backup!.7z" @!@!    die Auswahl packen und nach dem Archivnamen fragen
git commit -am "!?Commit-Nachricht?!"  committen und nach der Nachricht fragen
```

Der Befehl läuft in der für die Konsole gewählten Shell (cmd, PowerShell, WSL) – schreiben Sie Befehle in deren Syntax. Mehrere Befehle in einer Zeile lassen sich mit `&&` verbinden (cmd, PowerShell 7).

Solange das Hauptmenü noch nie gespeichert wurde, zeigt es Beispiele. Menüdateien lassen sich auch von Hand bearbeiten – Änderungen werden beim nächsten Öffnen des Menüs übernommen.

**Nach dem Start** im Eintragsdialog legt fest, wohin das Programm geht, wenn ein Befehl beendet ist: **Wie in den Konsolenoptionen** (das Kontrollfeld **Nach Befehlsende immer zu den Panels zurückkehren** unter **Optionen → Konsole...**), **Zu den Panels zurückkehren** oder **In der Konsole bleiben**.

---

[Inhalt](index.md)
