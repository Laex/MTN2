## Terminals

**Ctrl+Shift+N** – ein neues Terminal in einem eigenen Arbeitsbereich-Tab: ein Shell-Profil wählen (cmd, PowerShell, WSL, gespeicherte SSH-Verbindungen). Vollbildprogramme (vim, mc, htop, …) funktionieren im Terminal genauso wie in einer normalen Konsole.

<!--profiles-->In der Profilliste:

- **1-9, 0, A-Z** – das Profil mit dieser Nummer starten (am Zeilenanfang hervorgehoben).
- **Ins** – das gewählte Profil kopieren: dieselbe Shell, eigene Einstellungen. **Del** löscht eine Kopie (ein Profil selbst lässt sich nicht löschen).
- **Ctrl+Up / Ctrl+Down** – das Profil verschieben; die Reihenfolge wird gemerkt (`shellprofiles.json` im Einstellungsordner).
- **F4** – der Tastenmodus des Profils. Der Modus gilt auch für die Hintergrundkonsole (Ctrl+O), wenn ihr Profil gewählt ist.

Die Modi:
- *auto* – das Programm bekommt die Tasten, solange eine Vollbildanwendung wie mc oder vim in der Konsole läuft;
- *während Programm läuft* – wie *auto*, außerdem solange ein aus der Shell gestartetes Konsolenprogramm läuft, auch eines ohne alternativen Bildschirm wie Far Manager. Am leeren Prompt gelten die Tasten des Fensters; ein aus der Shell gestartetes GUI-Programm zählt nicht;
- *Terminal* – das Programm bekommt jede Taste, auch F1, F9 und Alt+Buchstabe; dem Fenster bleiben nur die reinen Navigationstasten (Pfeile, Home, End, PgUp, PgDn, Insert, Delete, mit und ohne Shift) am leeren Prompt: damit blättert man durch die Ausgabe, wählt aus und ruft den Verlauf auf. Das ist der Modus für Shells, die selbst das Programm sind (bash in WSL, ssh, Git Bash) und eigene Tasten wie Ctrl+R und Ctrl+A brauchen;
- *Host* – die Tasten des MTN2-Fensters haben Vorrang.

Wer die Tasten bekommt:

| Modus | Am leeren Prompt | Gewöhnlicher Befehl (`ping`, `git`, ein Build) | Vollbildprogramm (`vim`, `htop`) | Konsolenprogramm ohne alternativen Bildschirm (Far Manager) |
|---|---|---|---|---|
| auto | Fenster | Fenster | Programm | Fenster |
| während Programm läuft | Fenster | Programm | Programm | Programm |
| Terminal | Programm | Programm | Programm | Programm |
| Host | Fenster | Fenster | Fenster | Fenster |

„Fenster“ meint hier die eigenen Tasten des MTN2-Fensters: Hilfe, Blättern und Auswählen der Ausgabe, Aufruf des Befehlsverlaufs. Bei *auto* behält das Fenster Blättern und Auswählen, solange ein gewöhnlicher Befehl läuft; ein Programm wie Far braucht *während Programm läuft* oder *Terminal*. *Während Programm läuft* erkennt ein Programm am Konsolenprozess, den die Shell gestartet hat, und passt daher nicht zu einer Shell, die selbst das Programm ist (WSL, ssh): dafür *Terminal*.

Bei *auto*, *während Programm läuft* und *Terminal* behält das Fenster nur die Tasten, die die Konsole verlassen: F11, Ctrl+O, Tabwechsel, Ctrl+Shift+N und Ctrl+Alt+O.
- **F6** – das Umgebungsprofil der gewählten Shell oder ihrer Kopie (siehe [Umgebungsprofile](environment.md)).

---

[Inhalt](index.md)
