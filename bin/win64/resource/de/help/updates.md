## Updates

MTN2 kann sich selbst aktualisieren: es findet eine neue Version auf GitHub, lädt sie herunter und installiert sie, aber nur, wenn der Benutzer zustimmt.

### So läuft ein Update ab

Einige Sekunden nach dem Start, einmal am Tag, sucht MTN2 auf GitHub nach einer neuen Version. Gibt es eine, fragt es: **Aktualisieren**, **Später** oder **Diese Version überspringen** (eine übersprungene Version wird nicht erneut angeboten). Ohne Antwort wird nichts heruntergeladen oder installiert.

Nach dem Download (das Paket wird gegen seine SHA-256 geprüft) bietet MTN2 an, jetzt **Neu zu starten** oder **Beim Beenden** zu installieren. Solange Kopieraufträge laufen, wartet die Installation bis zum Beenden. Ersetzt werden nur Programmdateien (auch `7z.dll`, die zum Paket gehört) – Einstellungen und andere Benutzerdateien bleiben, wie sie sind.

### Einstellungen der Suche

**≡ → Nach Updates suchen...** (F9, dann der linkeste Eintrag des Hauptmenüs) zeigt die installierte Version, sucht sofort (**Jetzt suchen**) und hat zwei Kontrollfelder:

- **Beim Start nach Updates suchen** – einmal am Tag beim Start. Ist es aus, geht MTN2 nicht von selbst online.
- **Hinweis bei der Suche anzeigen** – jede Suche, die online geht (beim Start oder mit **Jetzt suchen**), zeigt unten rechts einige Sekunden lang den Hinweis „Suche auf github.com nach MTN2-Updates...“. Bei der Suche beim Start hat er eine zweite Zeile dazu, wie sich die Suche ausschalten lässt. Er wird auch angezeigt, wenn andere Popup-Hinweise aus sind, und verschwindet, sobald GitHub geantwortet hat; solange ein Dialog offen ist, bleibt er darunter verborgen.

### Was über das Netzwerk geht

Die Suche ist eine einzelne HTTPS-Anfrage an `api.github.com` nach dem neuesten Release des Repositorys `Laex/MTN2`. Sie enthält nichts außer der MTN2-Version im Header `User-Agent` – keine Dateinamen, Pfade oder Einstellungen. Das Update selbst ist das Release-Paket, das nach **Aktualisieren** von GitHub heruntergeladen wird.

---

[Inhalt](index.md)
