## Umgebungsprofile

**Optionen → Umgebungsprofile...** öffnet die Datei `environment.json` im Editor (beim ersten Aufruf wird sie mit einem Beispiel angelegt). Ein Profil ist eine benannte Liste von Einträgen `NAME=Wert`, die über die Umgebung jeder neuen Shell gelegt werden: Terminal-Tabs und die Konsole unter den Panels. Bereits laufende Shells behalten ihre Umgebung; eine Shell, die nach dem Speichern der Datei startet, sieht die Änderung.

```json
{
  "profiles": [
    { "name": "default", "vars": ["EDITOR=vim", "WORK=%TEMP%\\work", "OLD_VARIABLE="] },
    { "name": "proxy", "auto": false, "shells": ["pwsh"], "vars": ["HTTPS_PROXY=http://proxy:3128"] }
  ]
}
```

**Einträge.** Die Profile werden in der Reihenfolge der Datei angewendet, die Einträge in der Reihenfolge der Liste; ein späterer Eintrag sieht also das Ergebnis eines früheren. Ein Eintrag mit leerem Wert (`OLD_VARIABLE=`) entfernt die Variable. `%NAME%` wird auf allen Systemen durch den aktuellen Wert der Variablen ersetzt; unter Linux und macOS funktionieren auch `$NAME` und `${NAME}`. Ein nicht gesetzter Name bleibt wie geschrieben. Unter Windows wird die Groß-/Kleinschreibung der Namen nicht beachtet.

**Welche Profile für eine Shell gelten**
- `default` – gilt für jede Shell, zuerst.
- `auto` (standardmäßig an) – das Profil gilt von selbst. Mit `"auto": false` nur für eine Shell, die es benennt (siehe unten).
- `shells` – die Shell-Profile, für die das Profil gedacht ist: `pwsh`, `wsl`, `wsl:Ubuntu`, die ID einer Kopie wie `pwsh#2`. Ein einfaches `wsl` umfasst auch `wsl:Ubuntu`, eine Basis-ID ihre Kopien. Leer oder fehlend – jede Shell.
- `off` – `true` schaltet das Profil ganz aus, auch dort, wo es benannt ist.

<!--choice-->**Profil für eine Shell.** In der Shell-Liste (**Ctrl+Shift+N**) öffnet **F6** die Auswahl eines Umgebungsprofils für die gewählte Shell oder ihre Kopie. Eine solche Shell startet mit `default` und dem gewählten Profil; `(keins)` kehrt zu den automatischen Profilen zurück. Aufgelistet werden nur Profile, die nicht ausgeschaltet sind und nicht `default` heißen.

Die Datei gehört zu **Einstellungen exportieren / importieren**.

---

[Inhalt](index.md)
