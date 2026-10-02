# Hilfe zu Motiv

Motiv ist ein schlichter Bild- und Galeriebetrachter für macOS, gemacht für Bildsammlungen in Ordnern.

## Erste Schritte

Füge mit „Ablage → Ordner hinzufügen …“ (⌘O) einen Ordner mit Bildern hinzu oder zieh ihn auf das Motiv-Symbol im Dock. Er steht dann mit allen Unterordnern in der Seitenleiste. Ein Doppelklick auf ein Bild zeigt es groß, Esc führt zurück zur Übersicht. Soll Motiv Bilder immer öffnen, lege es in den Einstellungen als Standard fest, für alle Formate oder einzeln. „Zurücksetzen“ gibt die Formate später der App zurück, die sie vorher hatte.

Ausführlich steht alles im Handbuch: https://github.com/stefanradermacher/motiv/raw/main/docs/Motiv-Handbuch.pdf. In Motiv findest du es unter „Hilfe → Motiv-Handbuch“.

## Tastaturkürzel

| Funktion | Kürzel |
|---|---|
| Ordner hinzufügen | ⌘O |
| Bild öffnen, zurück zur Übersicht | ↩, Esc |
| Vorheriges, nächstes Bild | ← →, in der Einzelansicht auch ↑ ↓ und Leertaste |
| Erstes, letztes Bild | Pos1, Ende |
| Seitenweise blättern (Übersicht) | Bild auf, Bild ab |
| Zurück, Vorwärts | ⌘[, ⌘] oder die Seitentasten der Maus |
| Übergeordneter Ordner | ⌘↑ |
| Vergrößern, Verkleinern, Originalgröße | ⌘+, ⌘-, ⌘0 |
| An Fenster anpassen, Zoomstufe eingeben | ⌘9, ⌥⌘0 |
| Nach links, nach rechts drehen | ⌘L, ⌘R |
| Seitenleiste: Ordner, Bilder, Informationen, beides | ⌃⌘1 bis ⌃⌘4 |
| Informationen, Schnellinfo im Bild | ⌘I, ⌥⌘I |
| Nur das Bild im Vollbild | ⌥⌘F |
| Ausgewählte Bilder vergleichen | ⌃⌘C |
| Im Vergleich umschalten | Leertaste, A–D |
| Überblenden, Trennlinie verschieben | ← → |
| Sensible Inhalte bis zum Beenden nicht weichzeichnen | ⇧⌘U |
| Mit Unterordnern | ⌥⌘U |
| In Vorschau öffnen, im Finder zeigen | ⌘E, ⇧⌘R |
| Drucken | ⌘P |

In der Übersicht springst du zu einem Bild, indem du den Anfang seines Namens tippst. Auf dem Trackpad blätterst du in der Einzelansicht mit zwei Fingern, drehst mit zwei Fingern und tippst doppelt mit zwei Fingern für 100 %.

## Häufige Fragen

**Kann ich mit Motiv Bilder bearbeiten, drehen oder umbenennen?**
Nein, und das bleibt so. Motiv ist bewusst nur ein Betrachter. Drehen und Spiegeln wirken nur auf die Ansicht. Zum Bearbeiten öffnest du das Bild mit ⌘E in Vorschau oder über „Öffnen mit“ in einem anderen Programm.

**Kann ich Bilder drucken oder als PDF sichern?**
Drucken ja: ⌘P druckt das gezeigte Bild oder alle ausgewählten, jedes auf einer eigenen Seite. Drehen und Größe stellst du im Abschnitt „Motiv“ des Druckdialogs ein. Für ein PDF wählst du im Druckdialog „PDF → In Vorschau öffnen“ und sicherst es in Vorschau; „Als PDF sichern“ geht in Motiv nicht, weil die App nur lesen darf.

**Warum muss ich Ordner freigeben?**
Wie jede App aus dem App Store darf Motiv nur lesen, was du ausgewählt hast. Öffnest du ein einzelnes Bild aus dem Finder, zeigt Motiv es sofort; die Bilder daneben sieht es erst, wenn du mit „Ordner freigeben …“ in der Titelzeile den Ordner freigibst. Motiv merkt sich die Freigabe. Willst du den Ordner nur kurz ansehen, wähle über den Pfeil daneben „Nur bis zum Beenden freigeben …“; dann verschwindet er nach dem Beenden wieder aus der Seitenleiste.

**Ein Ordner in der Seitenleiste ist ausgegraut.**
Motiv kann ihn gerade nicht lesen, etwa weil die Festplatte nicht angeschlossen ist oder der Ordner verschoben wurde. Über das Kontextmenü „Erneut freigeben …“ wählst du ihn neu aus.

**Kann Motiv Videos abspielen?**
Nein. Videos erscheinen mit einem Standbild in der Übersicht; ein Doppelklick öffnet sie in deinem Standardprogramm, etwa QuickTime Player.

**Die Übersicht fragt, ob sie wirklich alle Bilder zeigen soll.**
Mit Unterordnern kann ein Ordner sehr viele Bilder enthalten. Ab 10.000 fragt Motiv nach, bevor es alle einliest.

**Die Miniaturen erscheinen langsamer als im Finder.**
Motiv erzeugt die Miniaturen selbst und legt keine Kopien auf der Platte ab. Der Finder nutzt dagegen den Systemcache von macOS. Wer es schneller mag, schaltet in den Einstellungen „Miniaturen im Systemcache ablegen“ ein.

**Warum sind manche Bilder unscharf?**
Du hast in den Systemeinstellungen unter „Datenschutz & Sicherheit“ den Hinweis für sensible Inhalte eingeschaltet, und Motiv hat im Bild möglicherweise sensible Inhalte erkannt. Mit „Anzeigen“ siehst du es trotzdem; ⇧⌘U setzt das Weichzeichnen bis zum Beenden von Motiv aus. Ist über die Bildschirmzeit die Kommunikationssicherheit für ein Kind eingerichtet, zeigt Motiv stattdessen eine graue Fläche, und beides ist gesperrt. Geprüft wird nur auf deinem Mac.

**Was bringen mir die Trinkgelder?**
Nichts außer meinem Dank. Sie schalten keine Funktionen frei; Motiv ist und bleibt vollständig kostenlos.

## Fehler melden und Ideen vorschlagen

Am besten über GitHub: https://github.com/stefanradermacher/motiv/issues

Oder per E-Mail an motiv@stefanradermacher.com. Hilfreich sind die Version aus „Über Motiv“, deine macOS-Version und, wenn möglich, ein Beispielbild.

## Quellcode

Motiv ist quelloffen unter der Apache-Lizenz 2.0: https://github.com/stefanradermacher/motiv
