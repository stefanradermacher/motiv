# Datenschutz für Motiv

Stand: 26. September 2026

Motiv ist ein Bild- und Galeriebetrachter für macOS. Diese Erklärung beschreibt, welche Daten die App verarbeitet. Die kurze Antwort: keine, die deinen Mac verlassen.

## Nichts verlässt deinen Mac

Motiv übermittelt keine personenbezogenen Daten an den Entwickler oder an Dritte. Es gibt kein Tracking, keine Analyse, keine Werbung und keine Konten. Die App baut selbst keine Verbindung ins Internet auf; nur ein freiwilliges Trinkgeld läuft über den App Store.

## Deine Bilder

Motiv liest nur Ordner und Dateien, die du selbst freigegeben oder geöffnet hast. Bilder, Videos und ihre Metadaten wie Aufnahmedaten oder Ortsangaben werden ausschließlich lokal auf deinem Mac gelesen und angezeigt. Sie werden nicht hochgeladen, nicht ausgewertet und nicht verändert. Motiv kann Bilder weder bearbeiten noch speichern; Drehen und Spiegeln wirken nur auf die Ansicht.

## Was lokal gespeichert wird

Auf deinem Mac merkt sich Motiv, damit es beim nächsten Start dort weitermacht, wo du aufgehört hast:

- deine Einstellungen (Sortierung, Größe der Miniaturen, Seitenleiste und weitere Optionen)
- die freigegebenen Ordner und deine Favoriten, als Lesezeichen von macOS mit ihrem Pfad
- den zuletzt gezeigten Ordner sowie Größe und Position der Fenster
- wenige Zählwerte für die gelegentliche Frage, ob Motiv die Standard-App für Bilder werden soll, und welche App ein Bildformat vor Motiv geöffnet hat, damit du es ihr zurückgeben kannst

Diese Angaben liegen im Bereich der App auf deinem Mac und verlassen ihn nicht. Die Pfade enthalten die Namen deiner Ordner, so wie sie auf deinem Mac heißen.

### Miniaturen

Miniaturen und Bildinformationen hält Motiv nur im Arbeitsspeicher, solange es läuft. Die Miniaturen erzeugt Motiv selbst und legt keine Kopien deiner Bilder auf der Platte ab. Nur bei wenigen seltenen Formaten, die Motiv nicht selbst lesen kann, übernimmt das die Übersicht (Quick Look) von macOS; sie speichert ihre Miniaturen im geschützten Systemcache, wie für den Finder. Wer es schneller mag, kann in den Einstellungen „Miniaturen im Systemcache ablegen“ aktivieren; dann erzeugt Quick Look alle Miniaturen und legt sie dort ab.

### So löschst du sie

Einzelne Ordner und Favoriten entfernst du in der Seitenleiste mit dem x neben dem Namen oder über das Kontextmenü. Alles zusammen entfernst du, indem du Motiv beendest und den Ordner `~/Library/Containers/com.stefanradermacher.motiv` löschst. Den Systemcache der Miniaturen leert `qlmanage -r cache` im Terminal.

## Sensible Inhalte

Ist in den Systemeinstellungen unter „Datenschutz & Sicherheit“ der Hinweis für sensible Inhalte eingeschaltet, prüft Motiv Bilder mit Apples Framework „SensitiveContentAnalysis“ auf sensible Inhalte, um sie bis zu deiner Freigabe weichgezeichnet zu zeigen. Die Prüfung läuft vollständig auf deinem Mac; weder Motiv noch Apple erhalten die Bilder oder die Ergebnisse. Motiv speichert die Ergebnisse nicht, sie gelten nur, solange die App läuft. Ist der Hinweis aus, prüft Motiv nichts.

## Orte in Karten

Enthält ein Bild Ortsangaben, zeigt Motiv die Koordinaten als Text. Erst wenn du „In Karten öffnen“ anklickst, übergibt Motiv die Koordinaten an die App Karten von Apple; für sie gilt Apples Datenschutzerklärung. Eine Karte lädt Motiv selbst nicht.

## Teilen und andere Apps

Wenn du ein Bild teilst, mit „Öffnen mit“ oder „In Vorschau öffnen“ an eine andere App gibst, ein Video im Standardprogramm öffnest oder Dateien kopierst, übergibt Motiv die ausgewählten Dateien an die App oder den Dienst, den du wählst, bzw. an die Zwischenablage. Das geschieht nur auf deine ausdrückliche Aktion. Für die weitere Verarbeitung gelten die Datenschutzbestimmungen der jeweiligen App oder des Dienstes.

## Freiwillige Trinkgelder

In Motiv kannst du freiwillig ein Trinkgeld geben. Damit die Preise im Fenster stehen, fragt Motiv sie beim Öffnen beim App Store ab. Diese Käufe wickelt ausschließlich Apple über den App Store ab. Motiv erfährt dabei nur, ob ein Kauf erfolgreich war; Zahlungsdaten bekommt die App nie zu sehen. Für die Zahlung gilt Apples Datenschutzerklärung.

## Links nach außen

Im Fenster „Über Motiv“ und im Hilfe-Menü gibt es Links zu GitHub und zu meiner Webseite. Sie öffnen sich erst, wenn du sie anklickst, und dann in deinem Browser. Für die aufgerufenen Seiten gelten deren eigene Datenschutzbestimmungen.

## Verantwortlich

Stefan Radermacher
Siegburger Straße 171
50679 Köln
Deutschland

E-Mail: motiv@stefanradermacher.com

## Änderungen

Ändert sich an der Datenverarbeitung etwas, wird diese Seite angepasst. Das Datum oben zeigt den Stand.
