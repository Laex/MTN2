## Archive

- **Enter** auf einem Archiv öffnet es wie einen Ordner; **Ctrl+\\** oder `..` im Wurzelverzeichnis des Archivs – verlassen.
- **Ctrl+PgDn** öffnet eine Datei unabhängig von ihrer Endung als Archiv: `.docx`, `.xlsx` oder `.odt` (ZIP im Inneren) oder ein Archiv mit ungewöhnlicher Endung. Das Format wird am Dateiinhalt erkannt; bei einer Datei, die kein Archiv ist, passiert nichts.
- **F5** aus einem Archiv entpackt die Auswahl, **F5** in ein geöffnetes Archiv fügt hinzu.
- **Shift+F1** – Auswahl packen, **Shift+F2** – entpacken.
<!--pack-->- Der Packen-Dialog schlägt den Namen des aktuellen Ordners als Archivnamen vor und lässt den Typ wählen: `zip` oder `7z`. Ein `7z`-Archiv kann eine Kompressionsstufe, ein Passwort und verschlüsselte Dateinamen erhalten (für `zip` sind diese Felder gesperrt); zu einem verschlüsselten `7z`-Archiv lassen sich Dateien hinzufügen und daraus löschen.
<!--password-->- 7z und andere Formate – über das 7-Zip-Plugin (`7z.dll` gehört zum Programm; sie lässt sich durch eine eigene Kopie in `plugins\mtn.7z\` ersetzen).
<!--test-->- **Archiv prüfen** (Datei > Archiv prüfen): vergleicht jede Datei des Archivs unter dem Cursor mit den gespeicherten Prüfsummen, ohne zu entpacken (Esc bricht ab). ZIP prüft das Programm selbst, 7z, RAR, TAR und die übrigen Formate des 7-Zip-Plugins das Plugin. Ein intaktes Archiv zeigt eine Kurzmeldung, beschädigte Einträge werden namentlich aufgelistet. Der Befehl hat keine Standardtaste und lässt sich im Tastaturdialog zuweisen.
<!--pack-each-->- **Jedes Element packen** (Datei > Jedes Element packen): packt jede ausgewählte Datei oder jeden Ordner in ein eigenes ZIP (`name.zip`) im Ordner der anderen Leiste; ein vorhandenes Archiv wird nie ersetzt (das neue heißt `name (2).zip`). Läuft im Hintergrund, Esc bricht ab. Der Befehl hat keine Standardtaste und lässt sich im Tastaturdialog zuweisen.
- Bei verschlüsselten Archiven fragt das Programm nach dem Passwort: beim Öffnen eines Archivs mit verschlüsselten Dateinamen, sonst beim ersten Ansehen oder Kopieren einer verschlüsselten Datei. Ein falsches Passwort wird erneut abgefragt; das richtige bleibt bis zum Beenden des Programms gespeichert.

---

[Inhalt](index.md)
