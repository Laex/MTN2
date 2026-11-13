# MTN2 – Benutzerhandbuch

[English](HELP.md) | [Русский](HELP.ru.md) | **Deutsch** | [中文](HELP.zh.md)

Modern Terminal Navigator 2 ist ein Dateimanager mit zwei Panels im Stil von NDN / FAR Manager mit eingebauter Konsole, Terminals, Viewer und Editor.

Die Tasten gelten für das eingebaute Profil; sie lassen sich ändern (siehe [Tastenbelegung](#tastenbelegung)).

## Inhalt

- [Programmoberfläche](#programmoberfläche)
- [Panels und Navigation](#panels-und-navigation)
- [Dateien auswählen](#dateien-auswählen)
- [Dateioperationen](#dateioperationen)
- [Laufwerke und besondere Orte](#laufwerke-und-besondere-orte)
- [Tabs und Arbeitsbereiche](#tabs-und-arbeitsbereiche)
- [Panelansicht und Sortierung](#panelansicht-und-sortierung)
- [Suche und Filter](#suche-und-filter)
- [Verlauf und Ordner-Hotlist](#verlauf-und-ordner-hotlist)
- [Befehlszeile und Konsole](#befehlszeile-und-konsole)
- [Terminals](#terminals)
- [Umgebungsprofile](#umgebungsprofile)
- [Dateien ansehen und bearbeiten](#dateien-ansehen-und-bearbeiten)
- [Arbeiten mit Text und Maus](#arbeiten-mit-text-und-maus)
- [Hauptmenü (F9)](#hauptmenü-f9)
- [Benutzermenü (F2)](#benutzermenü-f2)
- [Archive](#archive)
- [Netzwerk: SSH und SFTP](#netzwerk-ssh-und-sftp)
- [Synchronisieren und Vergleichen](#synchronisieren-und-vergleichen)
- [Hintergrundaufträge](#hintergrundaufträge)
- [Dateizuordnungen](#dateizuordnungen)
- [Einstellungen](#einstellungen)
- [Updates](#updates)
- [Tastenbelegung](#tastenbelegung)
- [Einstellungsdateien](#einstellungsdateien)

### Die Hilfe bedienen

| Taste | Aktion |
| --- | --- |
| Tab / Shift+Tab | nächster / vorheriger Link |
| Enter, Klick auf einen Link | dem Link folgen |
| Backspace, Alt+← | zurück |
| F1 | diese Seite (Inhalt) |
| F7, Shift+F7 / Alt+F7 | Text suchen, nächster / vorheriger Treffer |
| ↑ ↓ PgUp PgDn Home End | blättern |
| Esc, F10 | Hilfe schließen |

## Tastenbelegung

Der eingebaute Tastensatz lässt sich teilweise durch die Datei `keymap.json` im Einstellungsordner (oder über **Optionen → Tastenbelegung...**) ändern: aufgeführt werden nur die geänderten Aktionen, der Rest bleibt eingebaut. **Ctrl+Alt+K** – die Datei ohne Neustart neu laden.

Neben den Panels lassen sich auch die Befehle von Viewer und Editor neu belegen. Ihre Namen in `keymap.json` beginnen mit:
- `Doc` – Ansehen und Bearbeiten: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…;
- `Viewer` – nur Ansehen: `ViewerWrap`;
- `Markdown` – dargestelltes Markdown: `MarkdownSource`;
- `Editor` – nur Bearbeiten: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…

Dieselbe Tastenkombination kann auf den Panels und in einem Dokument Unterschiedliches bedeuten – Ctrl+H zeigt auf einem Panel versteckte Dateien und schaltet in einem Dokument Hex um. Eine engere Bedeutung hat Vorrang vor einer allgemeinen: F4 über dargestelltem Markdown schaltet den Quelltext um, nicht Hex.

Globale Befehle wirken in jedem Fenster – auf den Panels, in einem Dokument, in einem Terminal:
- `Help` (F1), `TopMenu` (F9), `CommandPalette` (Shift+F9);
- `NextTab` / `PrevTab` (Ctrl+Alt+PgDn / Ctrl+Alt+PgUp);
- `AppConsoleToggle` (Ctrl+O), `NewTerminal` (Ctrl+Shift+N), `SelectConsoleProfile` (Ctrl+Alt+O);
- `AppQuit` (Alt+X), `ZoomReset` (Ctrl+0), `ReloadKeymap` (Ctrl+Alt+K);
- `ToggleMouse` (Ctrl+Shift+M, nur Textterminal-Version).

**Eine vom Fenster selbst belegte Kombination.** Sie bleibt die des Fensters:
- F10 schließt ein Dokument und beendet das Programm nur auf den Panels (`Quit`);
- Esc auf den Panels zeigt die Konsole (`ConsoleToggle`), wenn das Panel den Fokus hat; in der Befehlszeile löscht es zuerst die Zeile und gibt dann den Fokus an das Panel zurück.

**Vollbildprogramm.** Läuft eines in einer Konsole oder einem Terminal (der Tastenmodus des Profils ist *auto* oder *Terminal*, siehe Terminals), bekommt die Konsole diese Tasten ebenfalls, außer denen, die sie verlassen: F11, Ctrl+O, Tabwechsel, Ctrl+Shift+N und Ctrl+Alt+O.

**Dialoge.** Solange ein Dialog offen ist, lösen die globalen Befehle nicht aus; `ZoomReset` und `ReloadKeymap` immer.

In der Konsole (Ctrl+O) und in einem Terminal lassen sich die mit `Shell…` benannten Befehle neu belegen:
- `ShellHistory` (Alt+F8), `ShellSelectAll` (Ctrl+A);
- `ShellCopyOrInterrupt` (Ctrl+C – die Auswahl kopieren, ohne Auswahl den Befehl unterbrechen), `ShellCopy` (Ctrl+Ins), `ShellPaste` (Ctrl+V, Shift+Ins);
- `ShellFind` (Ctrl+Shift+F – in der Ausgabe suchen), `ShellFindNext` / `ShellFindPrev` (F3 / Shift+F3);
- in der Konsole auch `ConsoleSyncDir` (Ctrl+Shift+O – das Panel wechselt in den Ordner der Konsole).

Jede andere Taste geht an die Shell.

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

Die `keymap.json` im Einstellungsordner wird über die eingebaute Tastenbelegung gelegt: die dort aufgeführten Aktionen haben Vorrang vor den eingebauten.
- Der Dialog **Einstellungen → Tastenbelegung** schreibt nur die geänderten Aktionen in die Datei, die anderen Tasten folgen also nach einem Update der eingebauten Tastenbelegung.
- Eine von früheren Versionen gespeicherte Datei führt alle Aktionen auf und friert die alten Tasten ein: um die neuen zu erhalten, löschen Sie daraus die Zeilen der benötigten Aktionen oder die ganze Datei (vorher eine Kopie anlegen, wenn sie eigene Änderungen enthält).
- Eine Aktion ohne Tasten wird als leere Liste geschrieben.

### Beispiele für Far- und MC-Gewohnheiten

Im Repository liegen zwei Beispiel-`keymap.json`, [`keymap.far.json` und `keymap.mc.json`](https://github.com/Laex/MTN2/tree/main/docs/keymap-presets). Kopiere die gewünschte als `keymap.json` in den Einstellungsordner (oder übernimm ihre Aktionen in deine Datei) und drücke **Strg+Alt+K**.
- **Far:** Esc in den Panels leert die Befehlszeile und öffnet die Konsole nicht (sie bleibt auf Strg+O).
- **MC:** Alt+. zeigt versteckte Dateien, Strg+\ öffnet die Ordnerliste, Alt+Enter fügt den Dateinamen in die Befehlszeile ein, Alt+A und Alt+Umschalt+A fügen den Ordnerpfad des aktiven und des anderen Panels ein, die Eigenschaften wandern auf Strg+Umschalt+P.

### Reservierte Tasten

Noch nicht belegt und für geplante Funktionen reserviert: **Shift+F3** (Archivbefehle), **F11** (das Plugin-Menü), **Ctrl+Alt+Ins** (Netzwerk-UNC-Pfade), **Ctrl+.** (Makroaufzeichnung). Eine automatische Prüfung verhindert, dass die eingebaute Tastenbelegung sie belegt.

---

[Inhalt](#inhalt)

## Programmoberfläche

Von oben nach unten:
- **Hauptmenü** – die Kategorien Links / Dateien / Bearbeiten / Befehle / Optionen / Rechts und eine Uhr. Geöffnet mit **F9**, **Alt** oder einem Klick.
- **Arbeitsbereich-Tabs** – Sätze von Panels und Terminals (siehe [Tabs und Arbeitsbereiche](#tabs-und-arbeitsbereiche)).
- **Zwei Dateipanels** – das aktive ist durch seinen Rahmen hervorgehoben; **Tab** wechselt die Seite. Laufwerksbuchstaben stehen am unteren Rand eines Panels.
- **Befehlszeile** – ein Prompt mit dem aktuellen Ordner.
- **F-Tastenleiste** – Hinweise zu den Aktionen des aktuellen Modus; sie lassen sich anklicken. Solange Shift / Ctrl / Alt gedrückt ist, zeigt die Leiste die passenden Aktionen. In einem Fenster ab 100 Spalten nennt die Leiste auf den Panels links auch die Taste der Befehlspalette.
- **Statuszeile** – Angaben zum Panel; ein Klick auf einen Abschnitt öffnet den zugehörigen Dialog: Seite und freier Platz öffnen die Laufwerkliste, der Pfad den Ordnerverlauf, der Spaltenmodus das Modusmenü, Element oder Auswahl die Eigenschaften. In Anzeige und Editor: die Position öffnet „Zu Zeile gehen“, die Kodierung die Kodierungsliste, das Suchergebnis „Suchen“.

Die **Konsole** liegt unter den Panels: **Ctrl+O** (oder **Esc** bei Fokus auf dem Panel) blendet die Panels aus und zeigt die Befehlsausgabe.

Der Fenstertitel zeigt **[Administrator]**, wenn MTN2 selbst als Administrator gestartet wurde, und **[Admin-Helfer]**, solange der Administrator-Helfer läuft (siehe [Dateioperationen](#dateioperationen)).

**Dialogschaltflächen** werden wie echte gedrückt: eine gedrückte Schaltfläche rutscht nach rechts und verdeckt ihren Schatten.
- **Maus.** Der Befehl läuft, wenn die Maustaste über derselben Schaltfläche losgelassen wird; zieht man den Zeiger weg und lässt dort los, passiert nichts.
- **Enter und Leertaste.** Sie halten die Schaltfläche gedrückt, bis die Taste losgelassen wird, und der Befehl läuft beim Loslassen; ein dazwischen gedrücktes **Esc** hebt die Schaltfläche an, ohne den Befehl auszuführen, und lässt den Dialog offen.
- **Der hervorgehobene Buchstabe sowie Y / N.** Sie drücken die Schaltfläche kurz nieder und lösen sie dann aus.
- Sonst schließt **Esc** den Dialog sofort.

**Tastenbuchstaben in Dialogen.** Bei Schaltflächen, Kontrollfeldern und Optionsfeldern ist ein Buchstabe der Beschriftung farbig hervorgehoben (in manchen Farbschemata unterstrichen).
- Das Drücken dieses Buchstabens drückt die Schaltfläche, schaltet das Kontrollfeld um oder wählt das Optionsfeld; solange der Fokus in einem Eingabefeld steht, drückt man ihn mit Alt.
- Der Buchstabe funktioniert auch bei einer anderen Tastaturbelegung: „Überspringen“ mit hervorgehobenem S reagiert sowohl auf S als auch auf den kyrillischen Buchstaben auf derselben Taste.
- Die Standardschaltfläche (in spitzen Klammern) und die Abbrechen-Schaltfläche brauchen keinen Buchstaben – Enter und Esc erledigen das.

**F1** – Hilfe zu dem, was auf dem Bildschirm steht (Panels, Viewer, der offene Dialog oder das Menü); **F1** in der Hilfe – der Inhalt. **F10** – beenden.

---

[Inhalt](#inhalt)

## Panels und Navigation

| Taste | Aktion |
| --- | --- |
| ↑ ↓ PgUp PgDn Home End | den Cursor bewegen |
| ← / → | im Modus „Kurz“ – eine Spalte nach links / rechts; in den anderen Modi – zum ersten / letzten Element (wie Home / End) |
| Enter | Ordner / Archiv betreten, Datei öffnen (laut [Zuordnung](#dateizuordnungen)); Konsolenprogramm in der eingebauten Konsole ausführen (siehe unten) |
| Backspace | eine Ebene nach oben, wie Enter auf `..` (bei leerer Befehlszeile; sonst löscht es dort ein Zeichen) |
| Ctrl+PgUp / Ctrl+PgDn | eine Ebene nach oben / den Ordner unter dem Cursor betreten, wie in FAR; bei einer Datei öffnet Ctrl+PgDn sie als Archiv (siehe [Archive](#archive)) |
| Shift+Enter | eine Datei oder einen Befehl in einem separaten Betriebssystemfenster ausführen |
| Alt+Shift+Enter | die Befehlszeile im Hintergrund ausführen: die Konsole zeigt sie kurz, dann kommen die Panels zurück; bei leerer Zeile startet es das Konsolenprogramm unter dem Cursor auf dieselbe Weise |
| Ctrl+Alt+Enter | die Befehlszeile in einem neuen Terminal-Tab ausführen (die Shell der Hintergrundkonsole); bei leerer Zeile startet es das Konsolenprogramm unter dem Cursor im Terminal-Tab des Panel-Tabs |
| Alt+Shift+F3 | das Element unter dem Cursor im anderen Panel zeigen |
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

**Ordnerbaum (Alt+F10)** öffnet sich über dem aktiven Panel. Er ist immer nur über einem Panel geöffnet.

**Öffnen.** Gezeigt wird die Laufwerkswurzel mit geöffnetem Pfad zum aktuellen Ordner und dem Cursor darauf.

**Tastatur**
- ↑ ↓ PgUp PgDn Home End – bewegen.
- → oder `+` – einen Zweig öffnen (`[+]─`) oder in ihn eintreten.
- ← oder `-` – einen Zweig schließen (`[-]─`) oder zum übergeordneten Ordner gehen.
- Ein Buchstabe – zum nächsten Ordner springen, der damit beginnt.
- Enter – den Ordner im aktiven Panel öffnen und den Baum schließen.
- Esc oder Alt+F10 – den Baum schließen; dasselbe Panel erscheint wieder.

**Das andere Panel.** Es wechselt in den Ordner unter dem Cursor, sobald der Cursor zur Ruhe kommt.

**Fokus**
- Tab oder ein Klick auf das andere Panel verschiebt den Fokus dorthin; der Baum bleibt, wie ein FAR-Baumpanel.
- Tab oder ein Klick auf den Rahmen des Baums bringt den Fokus zurück.

**Maus.** Der Baum funktioniert wie ein Index:
- ein Klick auf einen Ordner zeigt ihn sofort im anderen Panel und verschiebt den Fokus dorthin;
- ein Klick auf `[+]` / `[-]` öffnet oder schließt den Zweig, ohne den Fokus zu verschieben;
- das Mausrad blättert den Baum, ohne den Cursor zu bewegen.

**Folgen und Lesen im Hintergrund**
- Wechselt das andere Panel in einen anderen Ordner, öffnet der Baum den Pfad dorthin und setzt den Cursor darauf; für ein anderes Laufwerk baut er sich neu auf.
- Ordner werden im Hintergrund gelesen; wechselt das Panel unter dem Baum währenddessen in einen anderen Ordner, schließt sich der Baum.

**Schnellansicht (Ctrl+Q)** zeigt die Datei unter dem Cursor im anderen Panel: ein Bild, Text (die Kodierung wird erkannt), dargestelltes Markdown oder einen Hex-Dump einer Binärdatei.
- Große Dateien werden gestreamt.
- Das Mausrad über der Vorschau blättert sie.
- Dateien auf SFTP und große Dateien in Archiven werden nicht bei jeder Cursorbewegung gelesen – das Panel schlägt vor, sie mit F3 zu öffnen.
- Tab oder erneut Ctrl+Q schließt die Schnellansicht.

**Konsolenprogramme** (eine `.exe` des Konsolen-Subsystems, `.bat`, `.cmd`, `.ps1`) laufen mit Enter so, dass ihre Ausgabe auf dem Bildschirm bleibt und nicht in einem separaten Windows-Fenster erscheint:
- in der Hintergrundkonsole (Ctrl+O), wenn ihre Shell cmd, PowerShell oder pwsh ist und nichts darin läuft: wie ein in die Befehlszeile eingegebener Befehl;
- sonst (eine WSL-, Git-Bash- oder SSH-Konsole oder eine, die mit einem anderen Befehl beschäftigt ist) – in einem neuen Terminal-Tab mit cmd, bei einer `.ps1` mit PowerShell; der Tab bleibt nach dem Ende des Programms offen.

Mit **Programme der Panels in einem Terminal-Tab ausführen** (**Befehle → Hintergrundkonsole...**) läuft jedes Konsolenprogramm in einem Terminal-Tab, sodass die anderen Tabs währenddessen benutzbar bleiben.
- Das erste aus einem Panel-Tab gestartete Programm öffnet daneben einen Terminal-Tab.
- Die folgenden werden in der Shell dieses Tabs eingegeben (im Ordner der Datei), solange sie frei ist und in der Eingabezeile nichts steht, sonst öffnet sich ein neuer Tab.
- Die Shell des Tabs hat ein eigenes Umgebungsprofil (**F6** in der Shell-Liste) und einen eigenen Shell-Verlauf.

Fensterprogramme und Dokumente öffnen sich wie bisher mit ihrem Windows-Programm. **Shift+Enter** führt weiterhin jede Datei in einem separaten Fenster aus.

Ein Mausklick setzt den Cursor, ein Doppelklick wirkt wie Enter. Dateien lassen sich mit der Maus zwischen den Panels und zu anderen Programmen (und zurück) ziehen.

---

[Inhalt](#inhalt)

## Dateien auswählen

| Taste | Aktion |
| --- | --- |
| Ins | auswählen / Auswahl aufheben und nach unten gehen |
| Shift+Pfeile, Shift+Home/End/PgUp/PgDn | beim Bewegen des Cursors auswählen |
| Shift+Grau + | alle Dateien auswählen |
| Ctrl+M | die Auswahl zurückholen, die vor dem letzten Aufheben bestand (zum Beispiel nach einem Kopieren); ein zweites Drücken tauscht zurück |
| Grau + / Grau − | nach Maske auswählen / abwählen (`*.txt`, `a*.*`) |
| Grau * | die Auswahl umkehren |
| Ctrl+Grau + / Ctrl+Grau − | Dateien mit derselben Endung wie die unter dem Cursor auswählen / abwählen |
| Shift+Grau − | alle Dateien abwählen |
| Alt+Grau + / Alt+Grau − | Dateien mit demselben Namen auswählen / abwählen |

Im Dialog „Nach Maske auswählen“ wendet das Kontrollfeld „Ordner auswählen“ die Maske auch auf Ordner an. Operationen (Kopieren, Löschen, …) wirken auf die ausgewählten Elemente oder, wenn nichts ausgewählt ist, auf das Element unter dem Cursor.

### Maskengruppen

<!--mask-groups-->In jeder Maske (Auswahl, Panelfilter, Suche, Farbgruppen) steht `@Name` für eine benannte Gruppe von Masken, zum Beispiel `@Images` oder `*.log;@Documents`. Eingebaut sind Images, Audio, Video, Documents, Archives und Sources. Eigene Gruppen verwaltet der Menüpunkt "Maskengruppen..." im Menü Optionen (Datei `maskgroups.json` im Einstellungsordner); der Dialog zur Auswahl nach Maske kann seine Maske ebenfalls als Gruppe speichern. In einem Maskenfeld eines Dialogs speichert Strg+G die eingegebenen Masken als Gruppe (benannt nach der ersten Maske) und setzt `@Name` ins Feld.

---

[Inhalt](#inhalt)

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
| Ctrl+Alt+M | ausgewählte Elemente gemeinsam umbenennen: Masken für Name und Erweiterung, Zähler, Suchen und Ersetzen, Groß-/Kleinschreibung |
| Ctrl+C / Ctrl+X / Ctrl+V | Dateien über die Zwischenablage kopieren / ausschneiden / einfügen |
| Alt+Shift+Ins | den vollständigen Pfad in die Zwischenablage kopieren |
| Ctrl+Shift+Ins | nur den Namen (ohne Pfad) in die Zwischenablage kopieren |
| Ctrl+Z | die Datei beschreiben: eine Eingabezeile, der Text wird in `Descript.ion` neben der Datei gespeichert |

**Alt+Shift+Ins** und **Ctrl+Shift+Ins** übernehmen die ausgewählten Elemente (eines pro Zeile) oder, ohne Auswahl, das Element unter dem Cursor; bei `..` – den aktuellen Ordner. Das Ergebnis lässt sich überall mit **Shift+Ins** / **Ctrl+V** einfügen. Ein kurzer Hinweis unten rechts bestätigt das Kopieren (oder meldet, dass nichts zu kopieren ist); er lässt sich unter **Optionen → Oberfläche...** ausschalten.

<!--export-list-->**Dateien → Liste speichern...** schreibt die ausgewählten Elemente (ohne Auswahl das Element unter dem Cursor) in eine Datei.

**Der Dialog fragt nach**
- dem Dateinamen;
- dem Format – nach Endung (`.md` – Markdown-Tabelle, `.csv` – CSV, sonst ausgerichteter Text), einfacher Text, Markdown oder CSV;
- den Feldern: Name, vollständiger Pfad, Endung, Größe, Änderungs- / Erstellungs- / Zugriffsdatum, Typ und Attribute.

Die Überschriftenzeile lässt sich abschalten (eine Markdown-Tabelle hat immer eine). Bei Ordnern steht statt der Größe `<DIR>`. Die Auswahl bleibt über Neustarts erhalten; der Eintrag hat keine Standardtaste – sie lässt sich im Dialog für die Tastenbelegung zuweisen (Aktion `ExportList`).

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

<!--copy-->Im Dialog Kopieren/Verschieben lassen sich alle Zeitstempel beibehalten, nur neuere Dateien kopieren, der Inhalt symbolischer Links kopieren und eine Ausschlussmaske festlegen. Bei einem Namenskonflikt fragt das Programm, was zu tun ist (überschreiben, überspringen, umbenennen, für alle…).

<!--checksums-->**Prüfsummen.** Sie werden im Hintergrund berechnet (Esc – abbrechen). In der Ergebnisliste: **Kopieren** – in die Zwischenablage, **Speichern** – nach `<Datei>.sha256` (eine Datei) oder `checksums.sha256` im Panelordner. Die Prüfung markiert jede Zeile mit `OK`, `FAILED` oder `MISSING`. Zeilen der Form `Hash *Name`, `Hash  Name` und `SHA256 (Name) = Hash` werden verstanden.

<!--multi-rename-->**Mehrfach umbenennen.** Die Masken für Name und Erweiterung kennen:
- `[N]` – alter Name ohne Erweiterung;
- `[E]` – alte Erweiterung;
- `[C]` – Zähler mit Start, Schritt und Stellenzahl;
- `[Date]` und `[Time]` – Datum (`2026-11-05`) und Uhrzeit (`14-30-07`) der Änderung; `[Year]`, `[Month]` und `[Day]` – Teile des Datums;
- `[Parent]` – Name des Ordners; `[Size]` – Größe in Bytes;
- `[Dim]`, `[Camera]`, `[Artist]` und `[Title]` – Werte der Spalten des Metadaten-Plugins (Bildgröße und Kamera, Interpret und Titel) wie im Panel angezeigt; sie sind leer, bis das Plugin die Datei gelesen hat;
- anderer Text bleibt wie eingegeben.

Suchen und Ersetzen wirken auf den neuen Namen und die Erweiterung, die Groß-/Kleinschreibung wird aus der Liste gewählt. Mit **Regulärer Ausdruck** ist Suchen ein Muster und Ersetzen darf `$1`, `$2` verwenden; ein ungültiges Muster lässt die Namen unverändert. Platzhalter dürfen in beliebiger Schreibweise stehen; ein unbekannter Wert ist leer, und Zeichen, die ein Name nicht enthalten darf, werden zu `_`. Die Liste unter den Feldern zeigt die Paare „alt -> neu“ sofort.

**Fehler.** Ein leerer, ungültiger, doppelter oder im Ordner bereits vergebener Name (auch von einem anderen Element der Auswahl) ist mit `!` markiert; solange einer übrig ist, tut **Umbenennen** nichts.

Es lassen sich nur Elemente eines Ordners wählen. Das Umbenennen läuft wie ein Verschieben als Hintergrundauftrag.

---

[Inhalt](#inhalt)

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

## Laufwerke und besondere Orte

**Alt+F1 / Alt+F2** – Laufwerk für das linke / rechte Panel wählen. Unter der Laufwerksliste stehen besondere Orte (Auswahl per Ziffer, Enter oder Klick):
1. **Systemordner** – Desktop, Dokumente, Downloads und andere.
2. **Papierkorb** – durchsuchen; **Ctrl+Alt+R** stellt ein Element wieder her, **F8** löscht es endgültig. Schneller Sprung – **Ctrl+Alt+F8**.
3. **Temporär** – ein temporäres Panel, wenn das Plugin „Temporär“ installiert ist.
4. **Arbeitsbereich** – ein Panel mit Verknüpfungen zu Dateien und Ordnern (keine Kopien): **F5** fügt eine Verknüpfung hinzu, **F8** entfernt sie, **F7** erstellt eine Gruppe.

Nach den Laufwerken zeigt die Liste Netzwerkfreigaben wie `\\Server\Freigabe`, in denen gerade ein Panel geöffnet ist oder die kürzlich geöffnet waren (bis zu acht). Enter öffnet die Freigabe, die Freigabe des aktiven Panels ist mit einem Sternchen markiert.

**Auf einem Laufwerk**
- **F4** zeigt die Attribute seines Stammordners.
- **Entf** auf einem Wechsel- oder optischen Laufwerk oder einem verbundenen Netzlaufwerk trennt es (wirft den Datenträger aus) nach einer Bestätigung; ein Laufwerk mit geöffneten Dateien bleibt verbunden, das Programm nennt den Grund.

**Ctrl+← / Ctrl+→** – das benachbarte Laufwerk am unteren Rand des Panels vorab anzeigen; der Wechsel erfolgt beim Loslassen von Ctrl (Esc – abbrechen). Ein Klick auf einen Laufwerksbuchstaben wechselt sofort. Der zuletzt geöffnete Ordner wird für jedes Laufwerk gemerkt.

Der Eintrag **..** in den Systemordnern und im Papierkorb führt dorthin zurück, woher Sie kamen.

---

[Inhalt](#inhalt)

## Tabs und Arbeitsbereiche

<!--panel-tabs-->**Panel-Tabs** – jede Seite hat ihre eigenen. Die Schaltfläche **[+]** nach dem letzten Tab oder ein Doppelklick auf eine leere Stelle der Tabzeile erstellt einen neuen:

| Taste | Aktion |
| --- | --- |
| Ctrl+T | neuer Tab |
| Ctrl+W | den Tab schließen |
| Ctrl+Alt+T | Tab sperren oder entsperren (gesperrt: Hintergrund in der Akzentfarbe, ein anderer Ordner öffnet einen neuen Tab, schließen nicht möglich) |
| Ctrl+Tab / Ctrl+Shift+Tab | nächster / vorheriger Panel-Tab (bei einem Dokument oder Terminal – Arbeitsbereich) |

<!--workspaces-->**Arbeitsbereiche** – die Tabs der oberen Zeile (**Ctrl+Shift+W** erstellt einen, **Ctrl+Alt+PgDn** / **Ctrl+Alt+PgUp** wechseln). Jeder enthält sein eigenes Panelpaar oder ein Terminal. Ein Doppelklick auf einen Tab benennt ihn um; die Schaltfläche **[+]** direkt nach dem letzten Tab erstellt einen neuen.

<!--saved-->**Gespeicherte Arbeitsbereiche** – **Ctrl+Shift+D** (Liste, Sprung, Löschen), **Ctrl+Alt+Shift+D** – den aktuellen speichern.

<!--findtows-->**Suchergebnisse in einen Arbeitsbereich** – **Ctrl+Alt+F7** (Menü **Befehle**) legt im Linkpanel `ws:///` Verknüpfungen zu den markierten Einträgen des aktiven Panels an, ohne Markierung zu allen (zum Beispiel den Ergebnissen von **Alt+F7**), und öffnet es im anderen Panel. Gleiche Namen werden nummeriert, bereits verknüpfte Einträge nicht wiederholt, Einträge in Archiven und Plugin-Schemata übersprungen. Enthält der Arbeitsbereich schon Verknüpfungen oder gibt es gespeicherte Mengen, erscheint eine Auswahl: zur aktuellen Menge hinzufügen, sie ersetzen, eine neue Menge anlegen oder zu einer gespeicherten hinzufügen; eine geänderte Menge wird vor dem Ersetzen gespeichert. Mit **Ctrl+Alt+Shift+D** lässt sich die Menge speichern.

---

[Inhalt](#inhalt)

## Panelansicht und Sortierung

| Taste | Aktion |
| --- | --- |
| Ctrl+\` | Menü der Spaltenmodi |
| Ctrl+Shift+F1 … F6 | Modus: kurz, Größe, Datum, voll, erstellt, Typen |
| Ctrl+F12 | Sortiermenü |
| Ctrl+F3 / F4 / F5 / F6 | nach Name / Erweiterung / Änderungsdatum / Größe sortieren |
| Ctrl+F7 / F8 / F9 | unsortiert / nach Erstellungsdatum / nach Zugriffsdatum |

Die erneute Wahl derselben Sortierung kehrt die Richtung um. Der Buchstabe in der linken oberen Ecke des Panels zeigt die Sortierung (Großbuchstabe – absteigend). Die Spalten des Modus „Eigene“ werden unter **Optionen → Spalten...** festgelegt. Zeilenfarben nach Maske – **Optionen → Farbgruppen...**.

---

[Inhalt](#inhalt)

## Suche und Filter

| Taste | Aktion |
| --- | --- |
| Alt+F7 | Dateien suchen (Maske, Inhalt, Unterordner, Groß-/Kleinschreibung, ganze Wörter, reguläre Ausdrücke) |
| Ctrl+I | Panel-Filter: ein Dialog mit einer Liste fertiger Filter und einer Zeile für die eigene Maske; Enter oder ein Doppelklick auf die Liste wendet den Filter an, Löschen entfernt ihn |
| Ctrl+B | flache Ansicht: alle Dateien des Teilbaums in einer Liste |
| Alt+Buchstabe | Schnellsuche nach Name |

Suchergebnisse öffnen sich als Panel – die üblichen Operationen funktionieren damit.

Esc während einer laufenden Suche fragt „Suche beenden?“: **Stopp** beendet die Suche, **Fortsetzen** (Esc) lässt sie weiterlaufen.

---

[Inhalt](#inhalt)

## Verlauf und Ordner-Hotlist

| Taste | Aktion |
| --- | --- |
| Alt+F12 | Verlauf der besuchten Ordner |
| Ctrl+Shift+F12 | häufige Ordner (nach Anzahl und Aktualität der Besuche) |
| Alt+F11 | Verlauf der angesehenen und bearbeiteten Dateien |
| Alt+F8 | Befehlsverlauf |
| Ctrl+D | Ordner-Hotlist |
| Ctrl+Alt+D | den aktuellen Ordner zur Hotlist hinzufügen |

In den Listen: **Ins** – hinzufügen, **F2** – bearbeiten, **Del** – löschen (wo möglich). Die Wahl eines Eintrags aus dem Befehlsverlauf setzt den Befehl in die Befehlszeile, führt ihn aber nicht aus.

Im Ordner-, Datei- und Befehlsverlauf (Alt+F12, Alt+F11, Alt+F8) entfernt **Del** den gewählten Eintrag aus dem Verlauf und **Ctrl+Del** leert den ganzen Verlauf; eine Eingabe filtert die Liste.

<!--frecent-->**Häufige Ordner (Ctrl+Shift+F12)** – die Ordner, die Sie am häufigsten betreten; jüngere Besuche zählen stärker. Tippen schränkt die Liste ein, **Enter** öffnet den Ordner, **Entf** vergisst seinen Zähler, **Ctrl+Entf** löscht die Rangliste. Anders als Alt+F12 (nach Zeit sortiert) bleiben täglich genutzte Ordner oben.

<!--file-history-->**Dateiverlauf (Alt+F11)** – die letzten 100 mit F3/F4 geöffneten Dateien, die neueste zuerst; die Markierung links ist der Modus, in dem die Datei zuletzt geöffnet wurde (**A** – Ansehen, **B** – Bearbeiten).
- **Enter** öffnet die Datei im selben Modus.
- **F3** / **F4** – im Viewer / Editor.
- **Ctrl+Enter** – springt im Panel zur Datei.
- **Del** – entfernt sie aus dem Verlauf.
- Eine Eingabe filtert die Liste nach Pfad. Die Position in der Datei wird wiederhergestellt.

---

[Inhalt](#inhalt)

## Befehlszeile und Konsole

Die Befehlszeile befindet sich immer unter den Panels: einfach losschreiben. Ein Befehl läuft in der eingebauten Konsole; seine Ausgabe zeigt **Ctrl+O**.

| Taste | Aktion |
| --- | --- |
| Enter | Befehl ausführen; ein eingegebener Ordnerpfad wechselt in den Ordner, eine Datei (auch ein mit Ctrl+Enter eingefügter Name) wird gestartet: ein Konsolenprogramm in der eingebauten Konsole, alles andere mit seinem Windows-Programm. Danach geht der Fokus zurück ins Panel und die Pfeiltasten bewegen wieder den Cursor |
| Ctrl+↓ / Ctrl+↑ | Befehlszeile fokussieren / zurück zum Panel |
| ↑ / ↓ (beim Eingeben eines Befehls) | Befehlsverlauf |
| Tab | Vervollständigung: ein Name aus dem Panel oder ein Pfad von der Festplatte, wenn das Wort `\`, `/` oder `X:` enthält (wiederholtes Drücken wechselt durch die Treffer) |
| Ctrl+↓ / Alt+↓ (Zeile fokussiert) | Befehlsverlauf als Liste: Enter – in die Zeile übernehmen, Del – aus dem Verlauf entfernen, Esc – schließen |
| Eingabe in der Zeile | die älteren Befehle, die mit dem getippten Text beginnen, erscheinen als Liste über der Zeile; sie nimmt keine Tasten weg: ↑ / ↓ wählen einen Eintrag, Enter übernimmt ihn in die Zeile (Enter ohne Auswahl führt die Zeile aus), Del entfernt den Eintrag aus dem Verlauf, Esc schließt die Liste. Ist **Beim Tippen den Fokus nicht auf die Befehlszeile setzen** (Optionen → Oberfläche) eingeschaltet, gelangt das im Panel Getippte in die Zeile, ohne den Fokus dorthin zu setzen (Leertaste und Rücktaste nur bei nicht leerer Zeile); den Fokus setzen Ctrl+↓ oder ein Mausklick |
| Ctrl+Enter | Namen des Elements unter dem Cursor einfügen |
| Ctrl+F, Ctrl+Shift+Enter | vollständigen Pfad des Elements einfügen |
| Alt+Shift+Enter | Befehlszeile im Hintergrund ausführen: die Konsole zeigt kurz den Start, dann kommen die Panels zurück (**Optionen → Konsole...** weiter unten); bei leerer Zeile startet es das Konsolenprogramm unter dem Cursor auf dieselbe Weise |
| Ctrl+Alt+Enter | Befehlszeile in einem neuen Terminal-Tab ausführen: ein neuer Arbeitsbereich-Tab mit der Shell der Hintergrundkonsole (cmd, PowerShell, WSL, ...), der Befehl startet dort und der Tab bleibt offen; bei leerer Zeile startet es das Konsolenprogramm unter dem Cursor im Terminal-Tab des Panel-Tabs |
| Esc | Schritt für Schritt: Zeile löschen → Fokus ans Panel zurückgeben → Konsole zeigen. Bei leerer Zeile entfällt der erste Schritt; bei Fokus auf dem Panel wird zuerst der in der Zeile verbliebene Text gelöscht, bei leerer Zeile zeigt Esc sofort die Konsole |
| Ctrl+O | Panels ↔ Konsole |
| Ctrl+Shift+O | Ordner zwischen aktivem Panel und Konsole abgleichen |
| Ctrl+Alt+O | Shell der Hintergrundkonsole wählen (cmd, PowerShell, WSL, …) |

<!--console-profile-->**Befehle → Hintergrundkonsole...** ist derselbe Dialog.
- **Shell beim Programmstart starten** ist standardmäßig aus: die Shell startet beim ersten **Ctrl+O** oder beim ersten Befehl aus der Befehlszeile. Mit eingeschalteter Option startet die Shell wie früher zusammen mit dem Programm.
- **Programme der Panels in einem Terminal-Tab ausführen** schickt Konsolenprogramme, die in einem Panel mit Enter gestartet werden, in Terminal-Tabs statt in diese Konsole.

**In der Konsole:** **Ctrl+C** unterbricht den Befehl; **Esc** blendet die Konsole nur aus und beendet den Prozess nicht. Das Mausrad blättert durch die Ausgabe. Text wird mit der Maus ausgewählt (siehe [Arbeiten mit Text und Maus](#arbeiten-mit-text-und-maus)).

**Suche in der Ausgabe** (Konsole und Terminal):
- **Ctrl+Shift+F** fragt nach dem Text; Treffer sind im ganzen Verlauf hervorgehoben, der aktuelle ist wie bei einer Mausauswahl markiert. Eine leere Zeile im Dialog hebt die Suche auf.
- **F3** / **Shift+F3** springen zum nächsten / vorherigen Treffer (zyklisch), solange eine Suche gesetzt ist und im Fenster kein Vollbildprogramm läuft.
- In einer Konsole mit der Shell cmd blättern **↑** / **↓** im gemeinsamen Befehlsverlauf (wie Alt+F8), und **↓** nach dem neuesten Befehl bringt die getippte Zeile zurück.

**Einfügen in die Konsole** (**Ctrl+V**, **Shift+Ins**): jeder Zeilenumbruch geht als Enter an die Shell, die eingefügten Zeilen laufen also nacheinander, auch die letzte. Bei eingeschaltetem **Mehrzeiliges Einfügen bestätigen** fragt das Programm vorher nach.

**Optionen → Konsole...** legt fest:
- die Größe des Scrollbacks von Konsole und Terminals (1000 – 50.000 Zeilen, standardmäßig 10.000);
- die Bestätigung beim mehrzeiligen Einfügen (aus; ein Vollbildprogramm wie vim fragt nie);
- das Entfernen von Leerzeichen am Zeilenende beim Kopieren und beim Einfügen;
- **Nach Befehlsende immer zu den Panels zurückkehren** (aus). Bei eingeschalteter Option führt ein aus der Befehlszeile unter den Panels gestarteter Befehl zurück zu den Panels, sobald die Shell wieder ihren Prompt zeigt; ein in der Hintergrundkonsole (Ctrl+O) eingegebener Befehl bleibt immer in der Konsole.

**Hintergrundausführung.** **Alt+Shift+Enter** führt die Befehlszeile in der Konsole im Hintergrund aus: die Konsole wird für die unter **Hintergrundausführung** eingestellte Zeit gezeigt (0,5 – 10 s, standardmäßig 2 s) und die Panels kommen von selbst zurück. Eine vorher in der Konsole gedrückte Taste hält sie im Vordergrund; der Befehl läuft in beiden Fällen weiter.

Änderungen gelten sofort, auch für geöffnete Konsolen.

<!--save-output-->**Befehle → Konsolenausgabe speichern...** schreibt den Scrollback der Hintergrundkonsole (Ctrl+O) in eine UTF-8-Textdatei; **Konsolenpuffer leeren** löscht ihn, die Shell läuft weiter.

---

[Inhalt](#inhalt)

## Terminals

**Ctrl+Shift+N** – ein neues Terminal in einem eigenen Arbeitsbereich-Tab: ein Shell-Profil wählen (cmd, PowerShell, WSL, gespeicherte SSH-Verbindungen). Vollbildprogramme (vim, mc, htop, …) funktionieren im Terminal genauso wie in einer normalen Konsole.

<!--profiles-->In der Profilliste:

- **1-9, 0, A-Z** – das Profil mit dieser Nummer starten (am Zeilenanfang hervorgehoben).
- **Ins** – das gewählte Profil kopieren: dieselbe Shell, eigene Einstellungen. **Del** löscht eine Kopie (ein Profil selbst lässt sich nicht löschen).
- **Ctrl+Up / Ctrl+Down** – das Profil verschieben; die Reihenfolge wird gemerkt (`shellprofiles.json` im Einstellungsordner).
- **F4** – der Tastenmodus des Profils. Der Modus gilt auch für die Hintergrundkonsole (Ctrl+O), wenn ihr Profil gewählt ist.

Die Modi:
- *auto* – das Programm bekommt die Tasten, solange eine Vollbildanwendung wie mc oder vim in der Konsole läuft;
- *Terminal* – das Programm bekommt jede Taste, auch F1, F9 und Alt+Buchstabe;
- *Host* – die Tasten des MTN2-Fensters haben Vorrang.

Bei *auto* und *Terminal* behält das Fenster nur die Tasten, die die Konsole verlassen: F11, Ctrl+O, Tabwechsel, Ctrl+Shift+N und Ctrl+Alt+O.
- **F6** – das Umgebungsprofil der gewählten Shell oder ihrer Kopie (siehe [Umgebungsprofile](#umgebungsprofile)).

---

[Inhalt](#inhalt)

## Umgebungsprofile

**Optionen → Umgebungsprofile...** öffnet die Datei `environment.json` im Editor (beim ersten Aufruf wird sie mit einem Beispiel angelegt).

Ein Profil ist eine benannte Liste von Einträgen `NAME=Wert`, die über die Umgebung jeder neuen Shell gelegt werden: Terminal-Tabs und die Konsole unter den Panels. Bereits laufende Shells behalten ihre Umgebung; eine Shell, die nach dem Speichern der Datei startet, sieht die Änderung.

```json
{
  "profiles": [
    { "name": "default", "vars": ["EDITOR=vim", "WORK=%TEMP%\\work", "OLD_VARIABLE="] },
    { "name": "proxy", "auto": false, "shells": ["pwsh"], "vars": ["HTTPS_PROXY=http://proxy:3128"] }
  ]
}
```

**Einträge.**
- Die Profile werden in der Reihenfolge der Datei angewendet, die Einträge in der Reihenfolge der Liste; ein späterer Eintrag sieht also das Ergebnis eines früheren.
- Ein Eintrag mit leerem Wert (`OLD_VARIABLE=`) entfernt die Variable.
- `%NAME%` wird auf allen Systemen durch den aktuellen Wert der Variablen ersetzt; unter Linux und macOS funktionieren auch `$NAME` und `${NAME}`. Ein nicht gesetzter Name bleibt wie geschrieben.
- Unter Windows wird die Groß-/Kleinschreibung der Namen nicht beachtet.

**Welche Profile für eine Shell gelten**
- `default` – gilt für jede Shell, zuerst.
- `auto` (standardmäßig an) – das Profil gilt von selbst. Mit `"auto": false` nur für eine Shell, die es benennt (siehe unten).
- `shells` – die Shell-Profile, für die das Profil gedacht ist: `pwsh`, `wsl`, `wsl:Ubuntu`, die ID einer Kopie wie `pwsh#2`. Ein einfaches `wsl` umfasst auch `wsl:Ubuntu`, eine Basis-ID ihre Kopien. Leer oder fehlend – jede Shell.
- `off` – `true` schaltet das Profil ganz aus, auch dort, wo es benannt ist.

<!--choice-->**Profil für eine Shell.** In der Shell-Liste (**Ctrl+Shift+N**) öffnet **F6** die Auswahl eines Umgebungsprofils für die gewählte Shell oder ihre Kopie. Eine solche Shell startet mit `default` und dem gewählten Profil; `(keins)` kehrt zu den automatischen Profilen zurück. Aufgelistet werden nur Profile, die nicht ausgeschaltet sind und nicht `default` heißen.

Die Datei gehört zu **Einstellungen exportieren / importieren**.

---

[Inhalt](#inhalt)

## Dateien ansehen und bearbeiten

**F3** – ansehen, **F4** – bearbeiten, **F6** – zwischen Viewer ↔ Editor wechseln, ohne die Datei zu schließen.

**Alt+F3** / **Alt+F4** – die Datei unter dem Cursor im externen Viewer / Editor öffnen. Die Befehle werden unter **Optionen → Externer Viewer/Editor...** festgelegt; ohne sie öffnet Alt+F3 die Datei mit ihrem Windows-Programm und Alt+F4 mit dem Windows-Befehl „Bearbeiten“ oder, falls es keinen gibt, mit Notepad. Nur Dateien auf der Festplatte.

| Taste | Aktion |
| --- | --- |
| F7, Ctrl+F (im Viewer auch `/`) | der Suchdialog (siehe unten) |
| Shift+F7 / Alt+F7, F3 / Shift+F3 | nächster / vorheriger Treffer (bei eingeschalteter **Rückwärtssuche** tauschen die beiden) |
| Ctrl+F7 | Suchen und Ersetzen (Editor): dieselben Optionen und Schaltflächen, dazu **Ersetzen** und **Alle** |
| Alt+F8 | Gehe zu Zeile |
| F8 | nächste Kodierung; Shift+F8 – eine Kodierung wählen |
| F4 (im Viewer), Ctrl+H | HEX-Modus (im HEX-Modus des Editors lassen sich Bytes bearbeiten) |
| Ctrl+M | Markdown: dargestellte Ansicht ↔ Quelltext |
| Tab / Shift+Tab | Markdown: nächster / vorheriger Link |
| Enter, Klick auf einen Link | Markdown: einen lokalen Link (`other.md`, `other.md#abschnitt`, `#abschnitt`) im selben Fenster öffnen; ein externer Link (`https://…`, `mailto:…`) wird nach einer Bestätigung in der Standardanwendung geöffnet |
| Rücktaste / Alt+← | Markdown: von einem gefolgten lokalen Link zurückkehren |
| F2 | speichern (Editor) / Zeilenumbruch (Viewer; wird pro Datei zusammen mit der Position gemerkt) |
| Ctrl+Shift+F | Viewer: dem Ende einer wachsenden Datei (Log) folgen; Ende mit derselben Taste, Hochscrollen, Up, PgUp, Home oder einem anderen Modus |
| Ctrl+S | speichern |
| Ctrl+Z / Ctrl+Shift+Z | rückgängig / wiederholen |
| Ctrl+Y, Ctrl+D | die Zeile löschen |
| Ctrl+K | bis zum Zeilenende löschen |
| Ctrl+N | eine leere Zeile darunter einfügen |
| Ctrl+Alt+S / Ctrl+Alt+Shift+S | ausgewählte Zeilen (ohne Auswahl die ganze Datei) auf- / absteigend sortieren |
| Ctrl+Alt+U | doppelte Zeilen entfernen |
| Ctrl+Alt+F | Text auf eine vorgegebene Breite umbrechen (Absätze trennen Leerzeilen) |
| Alt+→ / Alt+← | ausgewählte Zeilen (ohne Auswahl die aktuelle) nach rechts / links einrücken |
| Alt+Shift+Pfeiltasten (auch Home / End / PgUp / PgDn), Alt+Maus | rechteckigen Block auswählen – dieselben Spalten mehrerer Zeilen; Del, Backspace, Eingabe und Ctrl+X / Ctrl+C / Ctrl+V wirken auf jede Zeile des Blocks, ein kopierter Block wird als Block eingefügt |
| Enter (Editor) | die neue Zeile beginnt mit dem Einzug der Zeile, die sie fortsetzt (die Leerzeichen links vom Cursor); der Modus wird mit **Ctrl+Alt+I**, im Menü „Bearbeiten“ und in den Einstellungen (Oberfläche) ein- und ausgeschaltet |
| Ctrl+F2 | Lesezeichen der Cursorzeile setzen / entfernen (die Zeile ist im Rahmen links mit ■ markiert) |
| Ctrl+Shift+F2 / Ctrl+Alt+F2 | zum nächsten / vorherigen Lesezeichen springen (zyklisch) |
| Ctrl+Alt+B | Liste der Lesezeichen (Zeilennummer und Text): Enter springt zum gewählten |
| Ctrl+Home / Ctrl+End | zum Anfang / Ende der Datei |
| Ctrl+C / Ctrl+X / Ctrl+V | kopieren (ohne Auswahl – die Zeile) / ausschneiden / einfügen |
| Esc, F10 (im Viewer auch 5 auf dem Ziffernblock) | schließen |

Große Dateien werden gestreamt und nicht als Ganzes geladen. Ändert sich die Datei auf der Festplatte, wird das geöffnete Fenster aktualisiert. Bei einer schreibgeschützten Datei bietet das Programm an, sie zum Schreiben zu öffnen, indem das Attribut aufgehoben wird.

<!--bookmarks-->**Lesezeichen.** **Ctrl+F2** setzt und entfernt das Lesezeichen der Cursorzeile, **Ctrl+Shift+F2** / **Ctrl+Alt+F2** springen zum nächsten / vorherigen, **Ctrl+Alt+B** öffnet die Liste: Enter springt zur gewählten Zeile, Esc schließt.

<!--find-->**Suchdialog.** Das Feld merkt sich frühere Suchen (**Ctrl+↓** / **Alt+↓**); die Optionen sind **Groß-/Kleinschreibung**, **Ganze Wörter**, **Reguläre Ausdrücke** und **Rückwärts suchen**.

**Feld und Treffer**
- **Wort** setzt das Wort unter dem Cursor in das Feld, **Auswahl** setzt die Auswahl ein (die aktuelle Zeile, wenn nichts ausgewählt ist; die erste Zeile einer mehrzeiligen Auswahl). Bei eingeschalteten **Regulären Ausdrücken** wird der Text dieser beiden Schaltflächen maskiert.
- Ein gefundener Treffer wird ausgewählt, und **F3** / **Shift+F3** machen von dort aus weiter. Ein Treffer erstreckt sich nie über einen Zeilenumbruch.
- Bei **Regulären Ausdrücken** ist das Muster ein PCRE-Ausdruck, und in der Ersetzung ist `$0` der ganze Treffer, `$1` ... `$9` sind die Gruppen und `$$` ist ein Dollarzeichen; ohne die Option wird die Ersetzung unverändert übernommen. Ein Muster, das sich nicht kompilieren lässt, wird gemeldet, und es wird nichts gesucht.

<!--replace-->**Ersetzen**
- **Ersetzen** im Dialog „Ersetzen“ geht die Treffer einzeln durch: jeder wird ausgewählt angezeigt, mit dem Text, seiner Ersetzung und der Zeile, die ihn enthält, und mit **Ersetzen** (ersetzen und zum nächsten weitergehen), **Alle** (den Rest ohne Nachfrage ersetzen), **Überspringen** oder **Abbrechen** beantwortet.
- Wird das Textende erreicht und die Suche hat in der Mitte begonnen, bietet es an, am Anfang fortzusetzen (beim Rückwärtssuchen am Ende).
- **Alle** im Dialog „Ersetzen“ ersetzt alle Treffer des ganzen Textes auf einmal.
- Beide Wege zeigen am Ende von **Alle** an, wie viele Ersetzungen vorgenommen wurden, werden mit einem einzigen **Ctrl+Z** rückgängig gemacht und setzen den Cursor dorthin zurück, wo er vor dem Ersetzen stand.

**Was gemerkt wird.** Groß-/Kleinschreibung, ganze Wörter und reguläre Ausdrücke werden zwischen den Starts gemerkt; **Rückwärts suchen** nur, bis MTN2 geschlossen wird.

---

[Inhalt](#inhalt)

## Arbeiten mit Text und Maus

Dasselbe im Viewer und Editor, in der Befehlszeile, in Dialogfeldern und in Konsolen.

Ein **Wort** besteht aus Buchstaben eines beliebigen Alphabets, Ziffern und `_`. Alles andere – Leerzeichen, Satzzeichen, `\`, `/`, `.`, `:` – ist ein **Trennzeichen**.

| Aktion | Ergebnis |
| --- | --- |
| Ctrl+← / Ctrl+→ | zum Anfang eines Wortes / zum Ende eines Wortes (bis zum nächsten Trennzeichen) |
| Ctrl+Shift+← / Ctrl+Shift+→ | dasselbe mit Auswahl; ein Schritt zurück hebt den überschrittenen Teil wieder auf |
| Shift+Pfeile, Shift+Home/End | Auswahl |
| Klick | den Cursor setzen |
| Doppelklick | ein Wort auswählen (auf einem Trennzeichen – eine Folge gleicher Zeichen) |
| Nächster schneller Klick | die ganze Zeile auswählen |
| Shift+Klick | die Auswahl bis zum Klickpunkt erweitern oder verkleinern |
| Maus ziehen | Auswahl (Viewer, Editor, Konsole) |
| Alt+Maus ziehen | rechteckiger Block (Viewer, Editor) |
| Ctrl+C / Ctrl+Ins, Ctrl+X / Shift+Del, Ctrl+V / Shift+Ins | Zwischenablage |
| Ctrl+A | alles auswählen |

In den Panels wirken Ctrl+Shift+←/→ auf die Befehlszeile, wenn sie nicht leer ist.

<!--mouse-->**Textterminal-Version (mtn2-tui).** Das Programm fordert die Maus vom Terminal an: Ein Ziehen markiert innerhalb von MTN2, und der Text gelangt über das Terminal in die Zwischenablage (eine Steuersequenz, die manche Terminals, etwa PuTTY standardmäßig, ignorieren; in tmux und auf einem Desktop füllt MTN2 zusätzlich den tmux-Puffer und die Systemzwischenablage).

Um mit dem Terminal selbst zu markieren:
- halten Sie beim Ziehen **Shift** gedrückt;
- oder schalten Sie die Maus mit **Ctrl+Shift+M** aus (**Optionen → Terminal-Maus an/aus**); dieselbe Taste schaltet sie wieder ein.

Die Option `--no-mouse` startet das Programm mit ausgeschalteter Maus.

**Eingabeverlauf.** Felder mit **↓** am rechten Ende merken sich ihre letzten 20 Werte. Das sind Auswahlmasken, die Dateisuche (Maske und Text), Ziel und Ausschlüsse beim Kopieren/Verschieben, Linkziel, neuer Ordner und neue Datei, Suchen und Ersetzen im Editor, Abfragen des Benutzermenüs.

**Mit der Liste arbeiten.** **Ctrl+↓** / **Alt+↓** oder ein Klick auf den Pfeil klappt die Liste auf:
- **Enter** – den Eintrag verwenden;
- **Del** – ihn aus dem Verlauf entfernen;
- **Esc** – die Liste schließen.

Ein Wert wird hinzugefügt, wenn der Dialog bestätigt wird.

---

[Inhalt](#inhalt)

## Hauptmenü (F9)

**F9** oder **Alt** öffnet das Menü.
- Pfeile bewegen, **Enter** führt aus, **Esc** schließt.
- Der hervorgehobene (Akzent-)Buchstabe eines Eintrags führt ihn sofort aus – in jeder Tastaturbelegung: bei offenem Untermenü wird der Buchstabe unter dessen Einträgen gesucht, sonst unter den Kategorien.
- Die Tasten der Einträge stehen rechts neben den Einträgen. Im aktuellen Modus nicht verfügbare Einträge sind grau.
- Passt ein Menü nicht ins Fenster, wird es gescrollt: am rechten Rand zeigt eine Leiste mit ▲ ▼, dass mehr Einträge folgen, der gewählte Eintrag bleibt sichtbar, das Mausrad bewegt die Auswahl.

**Umschalt+F9** (oder „Befehl suchen...“ im Menü ≡) öffnet die Befehlspalette, eine Suche in den Menüeinträgen.

**Suche**
- Beim Tippen wird die Liste enger: gesucht wird in den Wörtern der Bezeichnung, der Kategorie und gängigen Synonymen („shell“ findet „Hintergrundkonsole...“; mehrere Wörter müssen alle passen).
- Die Suche steht im Feld über der Liste; ein Wort darf `?` (ein Zeichen) und `*` (beliebig viele Zeichen) enthalten.
- Die Suche erfasst auch die Spalte der Tastenkombinationen: „F9“ findet die Befehle, deren Kombination F9 enthält, „shift“ alle Kombinationen mit Shift, „ctrl+f“ die Kombinationen mit Ctrl+F.
- Eigene Suchwörter stehen in `aliases.json` im Einstellungsordner: `{ "tmaCmdConsoleProfile": "bash, zsh" }` – Name des Eintrags und die Wörter, durch Komma getrennt oder als Liste. Die Datei wird bei jedem Öffnen der Palette neu gelesen.

**Tasten**
- Pfeile wählen, **Enter** führt aus, **Rücktaste** löscht, **Esc** schließt.
- **Strg+K** öffnet die Tastenliste beim gewählten Befehl, um seine Taste zu ändern; nach dem Schließen der Liste öffnet sich die Palette wieder mit derselben Suche und demselben Befehl, die neue Taste ist sichtbar (ein Befehl ohne eigene Taste meldet das). Bei einem Plugin-Befehl öffnet sich stattdessen ein Feld für eine einzelne Taste (ein leeres Feld lässt den Befehl ohne Taste; die Taste des Plugins kommt durch ihre Eingabe oder mit **Zurücksetzen** zurück); die Wahl steht in `plugin-keys.json` im Einstellungsordner.
- Die Taste der Palette selbst lässt sich in der Tastenbelegung ändern (Befehl `CommandPalette`).

**Was aufgeführt wird.** Nur jetzt verfügbare Einträge; zuletzt ausgeführte stehen oben. Befehle ohne Menüpunkt (Ctrl+Enter, Alt+Shift+Enter und die übrigen Panel-Tasten) stehen mit ihren Tastenkombinationen in der Kategorie „Tasten“.

**Tastenhinweise.** Wechselt das Programm in einen neuen Zustand, zeigt es einmalig eine kurze Meldung mit den nützlichen Tasten.

**Wann sie erscheinen**
- Nach einer Suche, in einem Archiv, in einem temporären Panel, in einem Arbeitsbereich, in einem SFTP- oder Plugin-Ordner, im Papierkorb.
- Bei markierten Dateien, in der Schnellansicht und im Infofenster, bei einem zweiten Fenster-Tab oder Arbeitsbereich, bei Hintergrundjobs.
- In der Konsole und im Terminal, im Viewer, in der Hex-Ansicht, in Markdown und im Editor, bei geöffnetem Menü, beim Eingeben eines Befehls und nach dem Start eines Konsolenprogramms mit Enter.
- Weitere Hinweise nennen selten genutzte Tasten: bei mehreren markierten Dateien, bei einem Archiv unter dem Cursor, in einem langen Ordner, nach vielen Ordnerwechseln, bei gleichnamigen Ordnern in beiden Panels und bei markierten Zeilen im Editor.

**So funktionieren sie.** Die Tasten stammen aus der aktuellen Tastenbelegung. Bereits gezeigte Hinweise werden zwischen den Starts gespeichert. Unter **Optionen → Oberfläche** schaltet das Kontrollkästchen „Tastenhinweise anzeigen“ sie ab, die Schaltfläche „Hinweise zurücksetzen“ macht sie wieder neu; bei ausgeschalteten Popup-Hinweisen erscheinen auch sie nicht.

---

[Inhalt](#inhalt)

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

<!--item-->**Menüeintrag:** Taste (ein Zeichen), Typ (Befehl / Untermenü / Trennlinie), Beschriftung und Befehl. Ist die Beschriftung leer, wird der Befehl selbst angezeigt.

<!--substitutions-->**Ersetzungen in einem Befehl:**

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

[Inhalt](#inhalt)

## Archive

- **Enter** auf einem Archiv öffnet es wie einen Ordner; **Ctrl+\\** oder `..` im Wurzelverzeichnis des Archivs – verlassen.
- **Ctrl+PgDn** öffnet eine Datei unabhängig von ihrer Endung als Archiv: `.docx`, `.xlsx` oder `.odt` (ZIP im Inneren) oder ein Archiv mit ungewöhnlicher Endung. Das Format wird am Dateiinhalt erkannt; bei einer Datei, die kein Archiv ist, passiert nichts.
- **F5** aus einem Archiv entpackt die Auswahl, **F5** in ein geöffnetes Archiv fügt hinzu.
- **Shift+F1** – Auswahl packen, **Shift+F2** – entpacken.
<!--pack-->- Der Packen-Dialog schlägt den Namen des aktuellen Ordners als Archivnamen vor und lässt den Typ wählen: `zip` oder `7z`. Ein `7z`-Archiv kann eine Kompressionsstufe, ein Passwort und verschlüsselte Dateinamen erhalten (für `zip` sind diese Felder gesperrt); zu einem verschlüsselten `7z`-Archiv lassen sich Dateien hinzufügen und daraus löschen.
<!--password-->- 7z und andere Formate – über das 7-Zip-Plugin (`7z.dll` gehört zum Programm; sie lässt sich durch eine eigene Kopie in `plugins\mtn.7z\` ersetzen).
- Bei verschlüsselten Archiven fragt das Programm nach dem Passwort: beim Öffnen eines Archivs mit verschlüsselten Dateinamen, sonst beim ersten Ansehen oder Kopieren einer verschlüsselten Datei. Ein falsches Passwort wird erneut abgefragt; das richtige bleibt bis zum Beenden des Programms gespeichert.

---

[Inhalt](#inhalt)

## Netzwerk: SSH und SFTP

**Ctrl+Alt+Shift+N** – die Liste der SSH/SFTP-Verbindungen: hinzufügen, bearbeiten, löschen, als Panel (SFTP) oder als Terminal (SSH) öffnen. Ein SFTP-Panel braucht Schlüsselauthentifizierung (oder ssh-agent / `~/.ssh/config`); ein Passwort für das Panel wird weder gespeichert noch abgefragt. In einem SSH-Terminal wird das Passwort wie üblich eingegeben.

---

[Inhalt](#inhalt)

## Synchronisieren und Vergleichen

<!--dir-sync-->- **Ctrl+Alt+S** – die Ordner des aktiven und des passiven Panels synchronisieren: einseitig oder zweiseitig; das Kontrollfeld „Probelauf“ zeigt, was getan würde, ohne etwas zu ändern.
- Im Synchronisationsdialog ist jeder Unterschied eine Listenzeile mit ihrer Aktion: `->` kopiert nach rechts, `<-` nach links, `--` überspringt; Konflikte sind zunächst übersprungen. Die Schaltflächen **Nach rechts**, **Nach links** und **Überspringen** setzen die Aktion der gewählten Zeile (eine manuelle Wahl ist mit `*` markiert), **Zurücksetzen** stellt die automatische wieder her, **Nur übersprungene** zeigt die Zeilen, über die noch nicht entschieden ist. Übersprungene Unterschiede bleiben bis zur nächsten Synchronisation offen.
<!--compare-files-->- **Ctrl+Alt+C** – die Dateien unter den Cursorn beider Panels oder die zwei markierten Dateien des aktiven Panels vergleichen; das Fenster zeigt Größe, Änderungszeit und das Ergebnis des Inhaltsvergleichs. Bei zwei oder mehr markierten Dateien werden gleichnamige Dateien verglichen (Markierungen in beiden Panels: nur die markierten; in einem Panel: das andere wird nach Namen durchsucht); eine Liste zeigt jedes Paar als identisch oder unterschiedlich, Enter öffnet die Unterschiede. Ordner werden übersprungen.
  For text files a compare-and-merge window opens: two columns with line numbers and the differences marked in the middle (`~` changed, `<` only on the left, `>` only on the right). **Ctrl+Down** and **Ctrl+Up** move between differences, **Right** copies a difference from left to right, **Left** from right to left, **Ctrl+Z** undoes a copy, **Ctrl+S** writes the changed files with their original encoding and line breaks. Closing with unsaved changes asks for confirmation (a second close discards them). Binary, very large (over 16 MB or 60000 lines) and identical files are shown in the earlier summary window.
<!--compare-folders-->- **Ctrl+Shift+C** – Ordner vergleichen: beide Panels wählen die auf der anderen Seite fehlenden Dateien und die neueren der gleichnamigen aus; bei gleicher Zeit, aber anderer Größe werden beide ausgewählt.

Einzelheiten des Vergleichs:
- Ordner werden nur ausgewählt, wenn sie auf der anderen Seite fehlen.
- Verglichen werden die aktuellen Panellisten ohne Unterordner, es funktioniert also auch in Archiven und auf SFTP.
- Der Dialog fragt, was als Unterschied gilt: Zeit, Größe, Inhalt.
- Der Inhalt wird nur bei gleich großen Dateien auf der Festplatte Byte für Byte verglichen und läuft im Hintergrund (Esc bricht ab).

---

[Inhalt](#inhalt)

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

<!--errors-->Hält ein Kopier-, Verschiebe- oder Löschvorgang mit einem Fehler an, bietet das Fehlerfenster **Wiederholen**, **Überspringen**, **Alle überspringen**, **Abbrechen** und, bei „Zugriff verweigert“ auf einem lokalen Pfad, **Admin** an: es wiederholt das Element und den Rest des Auftrags über den Administrator-Helfer (siehe [Dateioperationen](#dateioperationen)).

Hintergrundaufträge erscheinen rechts in der Tableiste: eine Plakette pro Auftrag und am Ende eine Listenschaltfläche.

**Plaketten**
- Eine Plakette hat ein Symbol für den Vorgang und seinen Fortschritt: `»` Kopieren, `►` Verschieben, `▼` Papierkorb, `‼` Löschen, `■` Packen, `□` Entpacken.
- Statt einer Prozentzahl kann sie `..` (in der Warteschlange), `?` (wartet auf eine Antwort) oder `!` (fehlgeschlagen) zeigen.
- Ein Klick auf eine Plakette holt diesen Auftrag zurück: sein Fortschrittsfenster, die Frage oder die Fehlermeldung.
- Die Schaltfläche `[≡N]` öffnet die Auftragsliste.
- Ohne Hintergrundaufträge wird dort nichts angezeigt, ob die Statuszeile sichtbar ist oder nicht.

**Abschluss.** Wenn ein Auftrag, der eine Weile im Hintergrund lief, endet, meldet das ein Hinweis; bricht er mit einem Fehler ab, wird der Hinweis auch bei ausgeschalteten Benachrichtigungen gezeigt, und ein Klick auf die Plakette des Auftrags öffnet den Fehler.

---

[Inhalt](#inhalt)

## Dateizuordnungen

**Ctrl+Alt+Shift+A** – was **Enter** bei Dateien mit einer bestimmten Endung tut: ansehen, bearbeiten, mit dem Windows-Programm öffnen oder einen eigenen Befehl ausführen (`%1` – Pfad zur Datei). In der Liste: **Ins** – hinzufügen, **F2** – bearbeiten, **Del** – löschen.

---

[Inhalt](#inhalt)

## Einstellungen

Das Menü **Optionen** (F9):
<!--theme-->- **Farbschema...** – das Aussehen wählen; wirkt sofort.

**Anpassen...** öffnet den Editor des gewählten Farbschemas: Bereiche (Farben von Fenstern, Dialogen, Schaltflächen, Cursor, Panels und mehr, Markdown, Textstile, Zeichen, Rahmen) mit ihren Werten.
- **Enter** auf einer Zeile bearbeitet den Wert: eine Farbe wird als `#RRGGBB` eingegeben oder mit **F9** / der Schaltfläche **[...]** gewählt.
- **Erben** gibt den Wert des Basis-Farbschemas zurück; Zeilen mit einem Sternchen werden vom Farbschema selbst gesetzt.
- Eine Farbe ist ein Wert `#RRGGBB`, ein Verweis auf eine andere Rolle des Farbschemas (`@cursor.bg`) oder ein Name aus der Palette.
- Der Bereich **Basen** führt die Farbschemata auf, auf denen dieses aufbaut (mehrere durch `;` getrennt, spätere überschreiben frühere).
- Änderungen wirken sofort.

**Speichern**
- **Speichern** schreibt das Farbschema in eine Datei. Eingebaute Farbschemata sind schreibgeschützt: eine Kopie eines eingebauten Farbschemas wird unter neuem Namen gespeichert (eine Datei im Ordner `themes` des Einstellungsordners), ein eigenes Farbschema wird mit **Speichern** an Ort und Stelle aktualisiert.
- **Speichern unter...** schreibt das Farbschema unter anderem Namen.
- **Neu...** erstellt ein Farbschema von Grund auf („leer“) oder aus einem beliebigen anderen.
- **Löschen** entfernt ein eigenes Farbschema.

Wird das Farbschema der gespeicherten Sitzung nicht gefunden, meldet das Programm das und verwendet das klassische Far-Farbschema.
<!--display-->- **Schrift / Anzeige...** – Schrift, Größe, Zoom, Cursorform und -blinken, Dateisymbole im Panel, **Zeilenabstand** (siehe unten), **Schatten** und das Aussehen **markierter Dateien**; alles wirkt ohne Neustart.

**Schatten und markierte Dateien**
- **Schatten** von Fenstern und Schaltflächen: Klassisch, Weich oder Keine; die Abdunkelung hinter einem Dialog wird dabei aufgehellt oder entfällt.
- **Markierte Dateien:** „Textfarbe“ – nur die Buchstaben ändern die Farbe, wie in Far; „Zeilenhintergrund“ – zusätzlich ein Hintergrundband über die ganze Zeile.
<!--interface-->- **Oberfläche...** – die Oberflächensprache, Hinweise, die Sichtbarkeit der Fensterzeilen, Ziehen, das Menü bei Alt, den automatischen Einzug und einige weitere Kontrollfelder; alles wirkt ohne Neustart.

**Was festgelegt wird**
- Die **Oberflächensprache** (English / Русский / Deutsch / 简体中文) und Popup-Hinweise.
- Die **Titelleiste, Menüleiste, F-Tastenleiste und Statuszeile.** Eine ausgeblendete Zeile geht an die Panels.
- **Dateien mit der Maus ziehen** (abschaltbar), das **Menü bei einzelnem Alt** (abschaltbar), den Cursor im inaktiven Panel und den **automatischen Einzug im Editor bei Enter** (abschaltbar).

**Ausgeblendete Fensterzeilen**
- Bei ausgeblendeter Menüleiste zeigt F9 sie über der obersten Zeile, solange das Menü offen ist.
- Bei ausgeblendeter Titelleiste wandern die Schaltflächen **[_] [□] [x]** ans rechte Ende der Menüleiste, oder der Tableiste, wenn auch sie ausgeblendet ist.
- Der Fenstertitel steht im freien Bereich der Tableiste; das Fenster wird an den freien Stellen von Menü- und Tableiste gezogen und an seinen Rändern in der Größe geändert.
- Ein Rechtsklick auf eine freie Stelle der Tableiste öffnet das Hauptmenü, wie F9.

**Kontrollfelder für Auswahl und Größen**
- **„Alles auswählen auch Ordner“** sorgt dafür, dass Shift+Grau + / Shift+Grau − und das Auswählen nach Endung auch Ordner erfassen (standardmäßig nur Dateien, wie in Far).
- **„Genaue Größe in Bytes anzeigen“** zeigt die Größen in der Panelfußzeile (Summe des Ordners oder der Auswahl, Größe des Elements unter dem Cursor) und in der Statuszeile als genaue Byteanzahl mit der Zifferngruppierung des Systems (`1.234.567`) statt `1.2 M`; passt die Zahl nicht, bleibt die Kurzform. Die Spalte „Größe“ der Dateiliste ändert sich nicht.

**Vim-Tasten im Panel.** Das Kontrollkästchen **„Vim-Tasten im Panel“** (standardmäßig aus) macht bei leerer Befehlszeile im Panel nutzbar:
- **j / k** – Cursor abwärts / aufwärts;
- **h** – übergeordneter Ordner; **l** – öffnen;
- **g / G** – erste / letzte Zeile;
- **/** – Schnellsuche; **:** – zur Befehlszeile.
<!--columns-->- **Spalten...** – die Spalten des Modus „Eigene“.
<!--console-->- **Konsole...** – die Scrollback-Größe von Konsole und Terminals, Bestätigung beim mehrzeiligen Einfügen, Entfernen von Leerzeichen am Zeilenende beim Kopieren und Einfügen, Rückkehr zu den Panels, wenn ein Befehl aus der Befehlszeile endet (mehr in der Hilfe zur Befehlszeile).
<!--save-settings-->- **Einstellungen speichern** – schreibt die Einstellungen, die Panels und die Tabs sofort in die Einstellungsdatei und nicht erst beim Beenden des Programms; ein Hinweis bestätigt es oder nennt das Problem. In Dialogen geänderte Optionen gelten sofort; dieser Punkt stellt sicher, dass sie auf dem Datenträger liegen, zum Beispiel bevor der Einstellungsordner kopiert wird.
<!--settings-file-->- **Einstellungen exportieren... / Einstellungen importieren...** – die Einstellungen als eine Zip-Datei.

**Was enthalten ist.** Sitzung und Anzeigeoptionen, Tasten, Benutzermenü, Zuordnungen, Hotlist, Liste der SSH-Verbindungen, Arbeitsbereiche, eigene Farbschemata; Verläufe sind nicht enthalten.

**So funktioniert es**
- Das Dateinamenfeld ist ein Eingabefeld mit einer ↓-Auswahlliste der zuvor verwendeten Dateien; standardmäßig ist es `mtn2-settings.zip` im Ordner des aktiven Panels.
- Vor einem Import werden die ersetzten Dateien als `settings-backup.zip` im Einstellungsordner gesichert.
- Die neuen Einstellungen wirken nach einem Neustart von MTN2.
<!--location-->- **Speicherort der Einstellungen...** – legt fest, wo die Einstellungen liegen: im Benutzerordner (Standardmodus) oder neben dem Programm (portabler Modus, Datei `portable.dat`).

**Was der Dialog zeigt.** Beide Orte, wie viele Dateien verschoben werden und was im Weg steht: kein Schreibzugriff auf den Programmordner, ein Programmordner für alle Benutzer, Dateien am Ziel, die ersetzt werden (sie bleiben als `*.before-switch` erhalten).

**Verschieben**
- Sitzung, Verläufe, Tasten, Plugin-Einstellungen und eigene Farbschemata werden gemeinsam verschoben, die alten Kopien gelöscht.
- Die Änderung gilt sofort ohne Neustart. Bei einem Fehler bleibt der alte Ort in Kraft.
- Sprachen und mitgelieferte Themes in `resource\` bleiben immer beim Programm.
<!--color-coding-->- **Farbgruppen...** – Zeilenfarben nach Namensmasken und optional nach Größe, Alter und Attributen (Feld **Bedingung**: Terme wie `size>10M`, `age<7d`, `+H`, `-R`; Buchstaben H versteckt, R schreibgeschützt, S System, A Archiv, C komprimiert, E verschlüsselt, L Link; `age<7d` = vor weniger als 7 Tagen geändert); sie werden im Farbschema gespeichert, eine Änderung bei einem eingebauten Farbschema wird also als neues Farbschema gespeichert (das Programm fragt nach seinem Namen). **F9** auf einem Farbfeld oder ein Klick auf die Schaltfläche **[...]** an seinem rechten Ende (sie zeigt die Farbe des Feldes) öffnet die Farbauswahl (siehe unten).
  Beispiele für Bedingungen (eine Gruppe gilt nur, wenn Maske und Bedingung zutreffen):
  - `size>100M` – Dateien über 100 MB, etwa mit der Maske `*.log` für große Protokolle.
  - `size>0 size<4K` – kleine, nicht leere Dateien.
  - `age<1d` – am letzten Tag geändert; `age<90m` – in den letzten 90 Minuten.
  - `age>30d` – seit einem Monat unberührt (veraltete Dateien abdunkeln); `age>2w` – älter als zwei Wochen.
  - `+H` – nur versteckte Dateien; `+HS` – versteckt und System; `-R` – alles außer schreibgeschützten Dateien.
  - `size>1G age>90d -R` – groß, alt und beschreibbar: alle drei Bedingungen müssen zutreffen (Kandidaten zum Aufräumen).
  - Ein Ordner hat keine Größe, daher trifft eine Gruppe mit Größenterm nie auf Ordner zu; Bedingungen nur mit Attributen oder Alter gelten auch für Ordner. Die Gruppen werden von oben nach unten geprüft, die erste passende gewinnt: die engere Gruppe (`*.log` + `size>100M`) gehört über die allgemeine (`*.log`).
- **Tastenbelegung...** – Tasten ansehen und ändern.
<!--plugins-->- **Plugins...** – installierte Plugins. Standardmäßig sind alle Plugins eingeschaltet.

**Bedienung**
- **Leertaste** auf einer Zeile schaltet das Plugin aus oder ein (`[x]` ist ein, `[ ]` ist aus); die Wahl gilt mit **OK** und bleibt zwischen den Starts erhalten, **Abbrechen** verwirft sie.
- **Berechtigungen...** öffnet einen Dialog: dem Plugin erlauben, eingebaute Handler zu ersetzen (`[replaces .zip: on]`) und was sein Manifest anfordert, zum Beispiel Dateien über das Programm zu lesen (`[needs vfs.read: on]`).
- **Ctrl+Up** und **Ctrl+Down** ändern die Ladereihenfolge der Plugins (sie spielt zwischen Plugins gleicher Priorität eine Rolle und gilt ab dem nächsten Start).
- **Info** zeigt, wofür das Plugin da ist und was es hinzugefügt hat (Befehle, Tasten, Dateitypen, Schemata), und öffnet seine Hilfeseite, wenn es eine hat.
<!--external-tools-->- **Externer Viewer/Editor...** – die Befehle Alt+F3 / Alt+F4; `%1` ist der Dateipfad (ohne `%1` wird der Pfad am Ende angehängt), z. B. `"C:\Program Files\Notepad++\notepad++.exe" %1`.
- **Umgebungsprofile...** – Variablen, die über die Umgebung neuer Shells gelegt werden; siehe [Umgebungsprofile](#umgebungsprofile).
<!--markdown-colors-->- **Markdown-Farben...** – Farben der Markdown-Ansicht (F3 auf einer `.md`-Datei): Vordergrund und Hintergrund (`#RRGGBB`) und ein **Textstil** für jedes Element.

**Elemente und Stile**
- Elemente: Überschriften, Fett, Kursiv, Durchgestrichen, Code, Zitat, Listenmarkierungen, Linien, Links, Tabellen.
- Der Stil kommt aus einer Liste: Farbschema, Normal, Fett, Kursiv, Fett kursiv, Unterstrichen, Durchgestrichen und Kombinationen.
- Ein leeres Feld oder **Farbschema** in der Stilliste behält das Eigene des Farbschemas; **Normal** schaltet den Stil aus, den das Element hat (zum Beispiel die Unterstreichung von Links).
- **F9** auf einem Feld oder ein Klick auf seine Schaltfläche **[...]** öffnet die Farbauswahl.
- Die Zeile **Text / Dokument** legt die Textfarbe und den Hintergrund der ganzen Markdown-Ansicht fest (nur für Markdown, andere Dateien behalten die Farben des Farbschemas); Elemente ohne eigenen Hintergrund folgen ihr.
- Das Beispiel neben einer Zeile wird mit ihren Farben und ihrem Stil gezeichnet.

**Aus Obsidian importieren...** liest die Farben aus einem Obsidian-Design (`theme.css`, zum Beispiel `<Tresor>\.obsidian\themes\<Design>\theme.css`).
- Die Palette **Dunkel** oder **Hell** wird im Importdialog gewählt.
- Die importierten Farben und Textstile (Gewicht, Kursivschrift und Unterstreichung, die das Design für Überschriften, Fett, Links, Zitate und Tabellenköpfe festlegt) ersetzen die Felder und Listen (nichts wird gespeichert, bevor OK gedrückt wird).

**Zurücksetzen** leert alle Felder und setzt jeden Stil auf **Farbschema**, sodass die eigenen Farben und Stile des Farbschemas gelten.

**Wo gespeichert wird.** Im aktiven Farbschema: bei einem eingebauten Farbschema fragt das Programm nach dem Namen eines neuen, ein eigenes wird an Ort und Stelle aktualisiert; die Felder enthalten nur, was das Farbschema selbst festlegt (der Rest wird geerbt).
- **Zoom**: Ctrl+Mausrad, **Ctrl+0** – zurücksetzen.

<!--color-picker-->### Farbauswahl

Die Auswahl hat:
- ein Raster aus Farbfeldern (Farbtöne nach rechts, hell nach dunkel nach unten; die unterste Zeile ist grau);
- Schieberegler **H, S, L** (Farbton, Sättigung, Helligkeit) und **R, G, B**;
- ein **Hex**-Feld neben zwei Farbfeldern: die Farbe **vorher**, als die Auswahl geöffnet wurde, und die Farbe **jetzt**.

**Tasten**
- **Up / Down** wechseln zwischen Raster, Schiebereglern und Hex-Feld.
- **Left / Right** bewegen sich im Raster oder ändern einen Regler um 1 (**Shift** – um 10, **PgUp / PgDn** – um 10, **Home / End** – an die Enden).

**Maus.** Ein Mausklick wählt ein Farbfeld oder stellt einen Regler ein; ein Klick auf das Feld **vorher** kehrt zur ursprünglichen Farbe zurück.

Das Raster verwendet die aktuelle Sättigung, der Regler **S** macht es also blasser oder kräftiger. **Übernehmen** übernimmt die Farbe, **Farbschema-Farbe** leert das Feld, sodass wieder die Farbe des Farbschemas gilt.

### Schrift und Zeilenabstand

Das Kontrollfeld **Zeilenabstand (wie im Terminal)** unter **Optionen → Schrift / Anzeige...** macht die Zeilen um 15 % der Schriftgröße höher; der Text bleibt in der Zeile zentriert, Rahmen und Hervorhebungen dehnen sich über die ganze Höhe. Standardmäßig ist es aus: die Zeilen sind so hoch wie die Zeile der Schrift, und es passen mehr davon auf den Bildschirm. Für Cascadia Mono 11 pt sind das 17 Pixel ohne Abstand und 19 mit ihm – genauso wie im Windows Terminal.

Die Schriftgröße wird in typografischen Punkten angegeben, wie im Windows Terminal und in der Windows-Konsole: 6 bis 24 pt, in Halbpunktschritten von 8 bis 12 pt. Bei 100 % Windows-Skalierung ist 1 pt = 4/3 Pixel: 10,5 pt sind 14 Pixel (der frühere Standard), 11 pt sind 14,7 Pixel.

Zwei weitere Optionen im selben Dialog machen den Text schärfer:
- **Schriftgröße an Geräte-Pixel anpassen** rundet die Buchstabengröße auf ganze physische Bildschirmpixel. Bei 125 % oder 150 % Windows-Skalierung und gebrochenen Größen (11 pt) haben die Striche dann gleiches Gewicht. Die Zellengröße kann sich leicht ändern. Standardmäßig aus.
- **Textkontrast** (Aus, Niedrig, Mittel, Hoch) füllt den schwachen Antialiasing-Saum aus: dünner heller Text auf dunklem Hintergrund liest sich fester. Standardmäßig aus.
- **Zellenbreite** und **Zellenhöhe** fügen jeder Zelle 0 bis 4 physische Pixel hinzu. Sie helfen bei einer Schrift, deren Buchstaben sich berühren oder deren Zeilen zu eng sitzen. Die Buchstaben bleiben in der Zelle zentriert, Rahmen füllen sie vollständig aus. Standardmäßig 0.
- **Ersatzschrift** nennt eine zweite Schriftfamilie für Zeichen, die der Hauptschrift fehlen, etwa CJK-Zeichen und Symbole. Gib den Familiennamen ein; ein leeres Feld oder eine nicht installierte Familie überlässt die Wahl Windows. Die Zellengröße ändert die Ersatzschrift nicht: sie kommt von der Hauptschrift.

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

Hinweise werden unter **Optionen → Oberfläche...** ausgeschaltet („Popup-Hinweise anzeigen“). Eine Ausnahme ist der Hinweis zur Update-Suche: er hat ein eigenes Kontrollfeld (siehe [Updates](#updates)).

### Updates

Die Suche nach neuen Versionen und ihre Installation, ihre Einstellungen und was über das Netzwerk geht, stehen auf der Seite [Updates](#updates).

---

[Inhalt](#inhalt)

## Updates

MTN2 kann sich selbst aktualisieren: es findet eine neue Version auf GitHub, lädt sie herunter und installiert sie, aber nur, wenn der Benutzer zustimmt.

### So läuft ein Update ab

Einige Sekunden nach dem Start, einmal am Tag, sucht MTN2 auf GitHub nach einer neuen Version. Gibt es eine, fragt es: **Aktualisieren**, **Später** oder **Diese Version überspringen** (eine übersprungene Version wird nicht erneut angeboten). Ohne Antwort wird nichts heruntergeladen oder installiert.

Nach dem Download (das Paket wird gegen seine SHA-256 geprüft) bietet MTN2 an, jetzt **Neu zu starten** oder **Beim Beenden** zu installieren. Solange Kopieraufträge laufen, wartet die Installation bis zum Beenden. Ersetzt werden nur Programmdateien (auch `7z.dll`, die zum Paket gehört) – Einstellungen und andere Benutzerdateien bleiben, wie sie sind.

### Einstellungen der Suche

**≡ → Nach Updates suchen...** (F9, dann der linkeste Eintrag des Hauptmenüs) zeigt die installierte Version, sucht sofort (**Jetzt suchen**) und hat zwei Kontrollfelder:

- **Beim Start nach Updates suchen** – einmal am Tag beim Start. Ist es aus, geht MTN2 nicht von selbst online.
- **Hinweis bei der Suche anzeigen** – jede Suche, die online geht (beim Start oder mit **Jetzt suchen**), zeigt unten rechts einige Sekunden lang den Hinweis „Suche auf github.com nach MTN2-Updates...“.

Einzelheiten:
- Bei der Suche beim Start hat der Hinweis eine zweite Zeile dazu, wie sich die Suche ausschalten lässt.
- Er wird auch angezeigt, wenn andere Popup-Hinweise aus sind, und verschwindet, sobald GitHub geantwortet hat.
- Solange ein Dialog offen ist, bleibt er darunter verborgen.

### Was über das Netzwerk geht

Die Suche ist eine einzelne HTTPS-Anfrage an `api.github.com` nach dem neuesten Release des Repositorys `Laex/MTN2`. Sie enthält nichts außer der MTN2-Version im Header `User-Agent` – keine Dateinamen, Pfade oder Einstellungen. Das Update selbst ist das Release-Paket, das nach **Aktualisieren** von GitHub heruntergeladen wird.

---

[Inhalt](#inhalt)

## Tastenbelegung

Der eingebaute Tastensatz lässt sich teilweise durch die Datei `keymap.json` im Einstellungsordner (oder über **Optionen → Tastenbelegung...**) ändern: aufgeführt werden nur die geänderten Aktionen, der Rest bleibt eingebaut. **Ctrl+Alt+K** – die Datei ohne Neustart neu laden.

Neben den Panels lassen sich auch die Befehle von Viewer und Editor neu belegen. Ihre Namen in `keymap.json` beginnen mit:
- `Doc` – Ansehen und Bearbeiten: `DocHex`, `DocFind`, `DocEncoding`, `DocClose`…;
- `Viewer` – nur Ansehen: `ViewerWrap`;
- `Markdown` – dargestelltes Markdown: `MarkdownSource`;
- `Editor` – nur Bearbeiten: `EditorSave`, `EditorUndo`, `EditorDeleteLine`…

Dieselbe Tastenkombination kann auf den Panels und in einem Dokument Unterschiedliches bedeuten – Ctrl+H zeigt auf einem Panel versteckte Dateien und schaltet in einem Dokument Hex um. Eine engere Bedeutung hat Vorrang vor einer allgemeinen: F4 über dargestelltem Markdown schaltet den Quelltext um, nicht Hex.

Globale Befehle wirken in jedem Fenster – auf den Panels, in einem Dokument, in einem Terminal:
- `Help` (F1), `TopMenu` (F9), `CommandPalette` (Shift+F9);
- `NextTab` / `PrevTab` (Ctrl+Alt+PgDn / Ctrl+Alt+PgUp);
- `AppConsoleToggle` (Ctrl+O), `NewTerminal` (Ctrl+Shift+N), `SelectConsoleProfile` (Ctrl+Alt+O);
- `AppQuit` (Alt+X), `ZoomReset` (Ctrl+0), `ReloadKeymap` (Ctrl+Alt+K);
- `ToggleMouse` (Ctrl+Shift+M, nur Textterminal-Version).

**Eine vom Fenster selbst belegte Kombination.** Sie bleibt die des Fensters:
- F10 schließt ein Dokument und beendet das Programm nur auf den Panels (`Quit`);
- Esc auf den Panels zeigt die Konsole (`ConsoleToggle`), wenn das Panel den Fokus hat; in der Befehlszeile löscht es zuerst die Zeile und gibt dann den Fokus an das Panel zurück.

**Vollbildprogramm.** Läuft eines in einer Konsole oder einem Terminal (der Tastenmodus des Profils ist *auto* oder *Terminal*, siehe Terminals), bekommt die Konsole diese Tasten ebenfalls, außer denen, die sie verlassen: F11, Ctrl+O, Tabwechsel, Ctrl+Shift+N und Ctrl+Alt+O.

**Dialoge.** Solange ein Dialog offen ist, lösen die globalen Befehle nicht aus; `ZoomReset` und `ReloadKeymap` immer.

In der Konsole (Ctrl+O) und in einem Terminal lassen sich die mit `Shell…` benannten Befehle neu belegen:
- `ShellHistory` (Alt+F8), `ShellSelectAll` (Ctrl+A);
- `ShellCopyOrInterrupt` (Ctrl+C – die Auswahl kopieren, ohne Auswahl den Befehl unterbrechen), `ShellCopy` (Ctrl+Ins), `ShellPaste` (Ctrl+V, Shift+Ins);
- `ShellFind` (Ctrl+Shift+F – in der Ausgabe suchen), `ShellFindNext` / `ShellFindPrev` (F3 / Shift+F3);
- in der Konsole auch `ConsoleSyncDir` (Ctrl+Shift+O – das Panel wechselt in den Ordner der Konsole).

Jede andere Taste geht an die Shell.

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

Die `keymap.json` im Einstellungsordner wird über die eingebaute Tastenbelegung gelegt: die dort aufgeführten Aktionen haben Vorrang vor den eingebauten.
- Der Dialog **Einstellungen → Tastenbelegung** schreibt nur die geänderten Aktionen in die Datei, die anderen Tasten folgen also nach einem Update der eingebauten Tastenbelegung.
- Eine von früheren Versionen gespeicherte Datei führt alle Aktionen auf und friert die alten Tasten ein: um die neuen zu erhalten, löschen Sie daraus die Zeilen der benötigten Aktionen oder die ganze Datei (vorher eine Kopie anlegen, wenn sie eigene Änderungen enthält).
- Eine Aktion ohne Tasten wird als leere Liste geschrieben.

### Beispiele für Far- und MC-Gewohnheiten

Im Repository liegen zwei Beispiel-`keymap.json`, [`keymap.far.json` und `keymap.mc.json`](https://github.com/Laex/MTN2/tree/main/docs/keymap-presets). Kopiere die gewünschte als `keymap.json` in den Einstellungsordner (oder übernimm ihre Aktionen in deine Datei) und drücke **Strg+Alt+K**.
- **Far:** Esc in den Panels leert die Befehlszeile und öffnet die Konsole nicht (sie bleibt auf Strg+O).
- **MC:** Alt+. zeigt versteckte Dateien, Strg+\ öffnet die Ordnerliste, Alt+Enter fügt den Dateinamen in die Befehlszeile ein, Alt+A und Alt+Umschalt+A fügen den Ordnerpfad des aktiven und des anderen Panels ein, die Eigenschaften wandern auf Strg+Umschalt+P.

### Reservierte Tasten

Noch nicht belegt und für geplante Funktionen reserviert: **Shift+F3** (Archivbefehle), **F11** (das Plugin-Menü), **Ctrl+Alt+Ins** (Netzwerk-UNC-Pfade), **Ctrl+.** (Makroaufzeichnung). Eine automatische Prüfung verhindert, dass die eingebaute Tastenbelegung sie belegt.

---

[Inhalt](#inhalt)

## Einstellungsdateien

Der Einstellungsordner ist `%APPDATA%\MTN2\`. Liegt eine Datei `portable.dat` neben `MTN2.exe`, werden die Einstellungen neben dem Programm gespeichert (portabler Modus).

| Datei | Inhalt |
| --- | --- |
| `session.json` | Zustand von Fenster, Panels und Tabs, Farbschema, Schrift, Sprache |
| `keymap.json` | geänderte Tasten |
| `environment.json` | Umgebungsprofile für Shells |
| `aliases.json` | eigene Suchwörter für die Befehlspalette |
| `history.json` | Befehlsverlauf |
| `folderhistory.json` | Ordnerverlauf |
| `filehistory.json` | Dateiverlauf (Alt+F11) |
| `externaltools.json` | externer Viewer und Editor (Alt+F3 / Alt+F4) |
| `themes\*.theme.json` | eigene Farbschemata (Optionen → Farbschema...) |
| `dialoghistory.json` | Verlauf der Eingabefelder in Dialogen |
| `workspaces.json` | gespeicherte Arbeitsbereiche |
| `sshconnections.json` | SSH/SFTP-Verbindungen |
| `associations.json` | Dateizuordnungen |
| `usermenu.json` | Haupt-Benutzermenü (F2) |
| `.mtn2menu.json` (in einem beliebigen Ordner) | Menü dieses Ordners und der darunterliegenden Ordner |

---

[Inhalt](#inhalt)
