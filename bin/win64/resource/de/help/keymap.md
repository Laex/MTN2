## Tastenbelegung

Der eingebaute Tastensatz lässt sich teilweise durch die Datei `keymap.json` im Einstellungsordner (oder über **Optionen → Tastenbelegung...**) ändern: aufgeführt werden nur die geänderten Aktionen, der Rest bleibt eingebaut. **Ctrl+Alt+K** – die Datei ohne Neustart neu laden.

Neben den Panels lassen sich auch die Befehle von Viewer und Editor neu belegen. Ihre Namen in `keymap.json` beginnen mit `Doc` (Ansehen und Bearbeiten: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…), `Viewer` (nur Ansehen: `ViewerWrap`), `Markdown` (dargestelltes Markdown: `MarkdownSource`) und `Editor` (nur Bearbeiten: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…). Dieselbe Tastenkombination kann auf den Panels und in einem Dokument Unterschiedliches bedeuten – Ctrl+H zeigt auf einem Panel versteckte Dateien und schaltet in einem Dokument Hex um. Eine engere Bedeutung hat Vorrang vor einer allgemeinen: F4 über dargestelltem Markdown schaltet den Quelltext um, nicht Hex.

Globale Befehle wirken in jedem Fenster – auf den Panels, in einem Dokument, in einem Terminal: `Help` (F1), `TopMenu` (F9), `NextTab` / `PrevTab` (Ctrl+Alt+PgDn / Ctrl+Alt+PgUp), `AppConsoleToggle` (Ctrl+O), `NewTerminal` (Ctrl+Shift+N), `SelectConsoleProfile` (Ctrl+Alt+O), `AppQuit` (Alt+X), `ZoomReset` (Ctrl+0) und `ReloadKeymap` (Ctrl+Alt+K). Eine Kombination, die das Fenster selbst belegt, bleibt die des Fensters: F10 schließt ein Dokument und beendet das Programm nur auf den Panels (`Quit`); Esc auf den Panels zeigt die Konsole (`ConsoleToggle`), wenn das Panel den Fokus hat; in der Befehlszeile löscht es zuerst die Zeile und gibt dann den Fokus an das Panel zurück. Läuft in einer Konsole oder einem Terminal ein Vollbildprogramm (der Tastenmodus des Profils ist *auto* oder *Terminal*, siehe Terminals), bekommt die Konsole diese Tasten ebenfalls, außer denen, die sie verlassen: F11, Ctrl+O, Tabwechsel, Ctrl+Shift+N und Ctrl+Alt+O. Solange ein Dialog offen ist, lösen die globalen Befehle nicht aus; `ZoomReset` und `ReloadKeymap` immer.

In der Konsole (Ctrl+O) und in einem Terminal lassen sich die mit `Shell…` benannten Befehle neu belegen: `ShellHistory` (Alt+F8), `ShellSelectAll` (Ctrl+A), `ShellCopyOrInterrupt` (Ctrl+C – die Auswahl kopieren, ohne Auswahl den Befehl unterbrechen), `ShellCopy` (Ctrl+Ins) und `ShellPaste` (Ctrl+V, Shift+Ins); in der Konsole auch `ConsoleSyncDir` (Ctrl+Shift+O – das Panel wechselt in den Ordner der Konsole). Jede andere Taste geht an die Shell.

**Einstellungen → Tastenbelegung** gruppiert die Aktionen nach Fenster – global, Dateipanels, Viewer und Editor, Konsole und Terminal – unter lesbaren Namen; der Name aus `keymap.json` steht im Bearbeitungsfenster. Die F-Tasten-Beschriftungen unten, Hinweise wie `A:All` und die Tastenkürzel im Hauptmenü stammen aus der Tastenbelegung: nach einer Neubelegung zeigen sie die neue Taste.

Eine Aktion kann mehrere Kürzel haben: im Bearbeitungsfenster durch `;` getrennt aufführen oder als einzelne Einträge in `keymap.json`. Neben Buchstaben, Ziffern und Sondertasten lassen sich die Zeichen `/`, `,`, `.`, `'`, `=` belegen; Semikolon und das Minus des Hauptblocks schreibt man als `Semicolon` und `Minus` (`-`, `+` und `*` bezeichnen die Tasten des Ziffernblocks).

Modifikatoren müssen genau passen: Ctrl+Shift+A ist nicht Ctrl+A. Pfeile, Home/End, das Tippen und `/` im Viewer sind nicht konfigurierbar.

### Tab-Tasten

Alle Tab-Tasten sind gewöhnliche Aktionen der Tastenbelegung und lassen sich in `keymap.json` neu belegen. Panel-Tabs und Arbeitsbereiche (die Tabs der oberen Zeile) sind verschiedene Dinge, jeweils mit eigenen Aktionen:

| Was | Aktion in `keymap.json` | Standard |
| --- | --- | --- |
| Neuer Panel-Tab | `NewTab` | Ctrl+T |
| Nächster / vorheriger Panel-Tab | `NextPanelTab` / `PrevPanelTab` | Ctrl+Tab / Ctrl+Shift+Tab |
| Panel-Tab schließen | `CloseTab` | Ctrl+W |
| Neuer Arbeitsbereich | `NewWorkspace` | Ctrl+Shift+W |
| Nächster / vorheriger Arbeitsbereich | `NextTab` / `PrevTab` | Ctrl+Alt+PgDn / Ctrl+Alt+PgUp |

Die Schaltflächen `[+]` und `[x]` in den Tabzeilen und die Einträge des Hauptmenüs tun dasselbe.

### Die eigene `keymap.json` und Updates

Die `keymap.json` im Einstellungsordner wird über die eingebaute Tastenbelegung gelegt: die dort aufgeführten Aktionen haben Vorrang vor den eingebauten. Der Dialog **Einstellungen → Tastenbelegung** schreibt nur die geänderten Aktionen in die Datei, die anderen Tasten folgen also nach einem Update der eingebauten Tastenbelegung. Eine von früheren Versionen gespeicherte Datei führt alle Aktionen auf und friert die alten Tasten ein: um die neuen zu erhalten, löschen Sie daraus die Zeilen der benötigten Aktionen oder die ganze Datei (vorher eine Kopie anlegen, wenn sie eigene Änderungen enthält). Eine Aktion ohne Tasten wird als leere Liste geschrieben.

### Reservierte Tasten

Noch nicht belegt und für geplante Funktionen reserviert: **Shift+F3** (Archivbefehle), **F11** (das Plugin-Menü), **Ctrl+Alt+Ins** (Netzwerk-UNC-Pfade), **Ctrl+.** (Makroaufzeichnung). Eine automatische Prüfung verhindert, dass die eingebaute Tastenbelegung sie belegt.

---

[Inhalt](index.md)
