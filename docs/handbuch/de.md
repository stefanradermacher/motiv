<!--
Texte des Handbuchs. Daraus erzeugt `swift scripts/make_manual.swift` das PDF
(mit „en“ die englische Fassung).

Oben stehen die Angaben für Titelseite und Dokumentinformationen, danach der Inhalt:
  # Kapitel             beginnt eine neue Seite und einen Eintrag in der Gliederung
  ## Überschrift        Zwischenüberschrift
  Text                  Absatz; Zeilenumbrüche sind egal, eine Leerzeile trennt Absätze
                        (das gilt auch für die Angaben oben)
  - Punkt               Aufzählungspunkt
  > Hinweis             Text im farbigen Kasten
  ![Text](Pfad)         Bildschirmfoto über die ganze Breite, darunter der Text;
                        fehlt die Datei, wird es ausgelassen
  | Befehl | Kürzel |   Zeile der Tastaturkürzel-Tabelle
-->

Dokumenttitel: Motiv – Handbuch
Thema: Bild- und Galeriebetrachter für macOS
Untertitel: Handbuch zum Bild- und Galeriebetrachter für macOS
Leitsatz: Deine Ordner, deine Bilder.
Einleitung: Bilder dort ansehen, wo sie liegen: mit Übersicht, Einzelansicht, Informationen und Vergleich.
Kostenlos, werbefrei und ohne Datensammlung.

# Über dieses Handbuch

Motiv ist ein Bild- und Galeriebetrachter für macOS, gemacht für Bildsammlungen in Ordnern. Es zeigt Bilder dort, wo sie liegen: ohne Mediathek, ohne Import und ohne Anmeldung. Dieses Handbuch beschreibt in wenigen Kapiteln, was Motiv kann und wie es sich bedienen lässt.

## Was Motiv ausmacht

- Arbeitet direkt mit deinen Ordnern, nichts wird importiert oder kopiert
- Modifiziert keine Dateien; Drehen und Spiegeln wirken nur auf die Ansicht
- Kostenlos und quelloffen unter der Apache-Lizenz 2.0
- Keine Werbung, kein Tracking, keine Datensammlung
- Nur Apple-Frameworks, keine Fremdkomponenten
- Deutsch und Englisch

# Ordner und Favoriten

Motiv zeigt keine Mediathek, sondern deine Ordner. Einen Ordner fügst du über „Ablage → Ordner hinzufügen …“ hinzu oder ziehst ihn auf das Motiv-Symbol im Dock. Er steht dann mit allen Unterordnern in der Seitenleiste.

## Warum Ordner freigeben?

Wie jede App aus dem App Store darf Motiv nur lesen, was du ausgewählt hast. Öffnest du ein einzelnes Bild aus dem Finder, zeigt Motiv es sofort; die Bilder daneben sieht es erst, wenn du den Ordner mit „Ordner freigeben …“ in der Titelzeile freigibst. Motiv merkt sich die Freigabe, und zwar nur zum Lesen.

## Favoriten

Tief verschachtelte Ordner holst du als Favoriten nach oben in die Seitenleiste, über das Kontextmenü oder mit ⌃⌘T. Ein Klick auf das x neben dem Namen entfernt einen Ordner oder Favoriten wieder aus der Seitenleiste; auf der Platte bleibt alles, wie es ist.

## Die Ordnerleiste

Über den Miniaturen zeigt eine Leiste die Unterordner des aktuellen Ordners mit Namen und Bildzahl, vorne den übergeordneten Ordner. Ein Klick öffnet den Ordner. Die Leiste lässt sich in der Höhe ziehen und mit dem Mausrad seitwärts scrollen. Mit „Unterordner einbeziehen“ zeigt die Übersicht auch alle Bilder der Unterordner.

# Die Übersicht

Die Übersicht zeigt die Bilder und Videos eines Ordners als Miniaturen. Die Größe stellst du mit dem Regler in der Symbolleiste ein, mit ⌘+ und ⌘- oder mit zwei Fingern auf dem Trackpad; ⌘0 stellt die Standardgröße wieder her.

![Die Übersicht mit Ordnern, Ordnerleiste und Miniaturen](docs/screenshots/1-uebersicht.jpg)

## Sortieren und finden

Sortieren lässt sich nach Name, Aufnahmedatum, Änderungsdatum, Größe oder Art. Um ein Bild zu finden, tippst du einfach den Anfang seines Namens. Mit den Pfeiltasten wanderst du durch die Miniaturen, mit Bild auf und Bild ab seitenweise, mit ⇧ erweiterst du die Auswahl.

## Aus der Übersicht heraus

Ein Doppelklick oder die Eingabetaste zeigt ein Bild groß. Das Kontextmenü öffnet Bilder in Vorschau oder einer anderen App, zeigt sie im Finder, teilt sie oder vergleicht die ausgewählten Bilder.

# Die Einzelansicht

In der Einzelansicht blätterst du mit den Pfeiltasten, der Leertaste oder mit zwei Fingern auf dem Trackpad. Esc führt zurück zur Übersicht, unten zeigt eine Leiste die Nachbarbilder. Mit ⌥⌘F füllt das Bild den ganzen Bildschirm, ohne Leisten und ohne Mauszeiger.

![Die Einzelansicht mit Informationen in der Seitenleiste](docs/screenshots/2-einzelansicht.jpg)

## Zoomen

Ein Bild passt sich zunächst ins Fenster ein. Ein Doppelklick zeigt es in Originalgröße an der angeklickten Stelle, ein zweiter passt es wieder ein. Über die Prozentzahl in der Symbolleiste passt du an Breite oder Höhe an oder wählst eine Zoomstufe. Sehr große Bilder lädt Motiv erst beim Hineinzoomen in voller Auflösung, so bleibt es flüssig.

## Drehen und Spiegeln

Drehen (⌘L, ⌘R oder mit zwei Fingern) und Spiegeln wirken nur auf die Ansicht. Die Datei bleibt unverändert; beim nächsten Bild ist alles wieder wie gespeichert.

# Informationen

Die Seitenleiste zeigt wahlweise die Ordner, die Bilder als Liste, die Informationen zum Bild oder Ordner und Informationen übereinander. Umschalten lässt sich oben in der Seitenleiste oder mit ⌃⌘1 bis ⌃⌘4.

## Was Motiv anzeigt

- Datei: Name, Art, Größe und Datum
- Bild: Maße, Farbprofil und Farbtiefe
- Aufnahme: Kamera, Objektiv, Belichtung und Aufnahmedatum
- Ort, Beschreibung und Schlagwörter, bei Videos Dauer und Codec
- Auf Wunsch alle Metadaten der Datei

## Schnellinfo und Karten

Mit ⌥⌘I zeigt eine Zeile im Bild die wichtigsten Angaben. Enthält ein Bild einen Ort, öffnet ein Klick ihn in Karten; eine Karte lädt Motiv selbst nicht.

# Vergleichen

Wähle zwei bis vier Bilder aus und drücke ⌃⌘C. Motiv zeigt sie nebeneinander, vier als 2 × 2. Unter jedem Bild stehen Buchstabe, Name, Maße und Größe.

![Vier Bilder im Vergleich](docs/screenshots/3-vergleich.jpg)

## Gekoppelter Zoom

Zoom und Ausschnitt sind gekoppelt: Alle Bilder zeigen denselben Bildbereich, auch bei unterschiedlicher Auflösung. „Gleiche Pixel“ zeigt stattdessen alle im selben Maßstab, das Kettensymbol hebt die Kopplung auf.

## Übereinander

- Umschalten: die Bilder an derselben Stelle, Leertaste oder A bis D wechseln
- Überblenden: ein Bild stufenlos ins andere, mit Regler oder ← und →
- Trennlinie: links das eine, rechts das andere Bild, die Linie lässt sich ziehen

Esc beendet den Vergleich.

# Videos und andere Programme

Motiv erkennt Videos und zeigt sie mit einem Standbild, spielt sie aber nicht ab. Ein Doppelklick öffnet sie in deinem Standardprogramm, etwa QuickTime Player.

## Bearbeiten

Motiv modifiziert keine Bilder. Mit ⌘E öffnest du ein Bild in Vorschau, über „Öffnen mit“ in jedem anderen Programm. Teilen und Kopieren übergeben die Dateien nur, wenn du es ausdrücklich möchtest.

## Drucken

Mit ⌘P druckst du das gezeigte Bild oder alle ausgewählten, jedes auf einer eigenen Seite. Für breite Bilder wählt Motiv das Querformat vor. Im Abschnitt „Motiv“ des Druckdialogs wählst du, ob Bilder automatisch zum Papier gedreht werden und wie groß sie erscheinen: in Originalgröße nach ihrer Auflösung, nur verkleinert, wenn sie nicht passen, oder auf das Papierformat skaliert. Motiv merkt sich die Wahl. In der Einzelansicht druckt es das Bild so gedreht und gespiegelt, wie du es siehst. Ein PDF bekommst du über „PDF → In Vorschau öffnen“ im Druckdialog und sicherst es dann in Vorschau, denn Motiv selbst schreibt keine Dateien.

## Standard-App

Soll Motiv Bilder immer öffnen, legst du es in den Einstellungen als Standard fest, für alle Formate oder einzeln. macOS fragt für jedes Format selbst nach. „Zurücksetzen“ gibt ein Format später der App zurück, die es vorher hatte. Kamera-RAW bietet Motiv dabei bewusst nicht an.

# Einstellungen

Die Einstellungen enthalten nur, was selten geändert wird. Sortierung, Größe der Miniaturen und Seitenleiste merkt sich Motiv von selbst.

## Miniaturen

Motiv erzeugt die Miniaturen selbst und legt keine Kopien deiner Bilder auf der Platte ab. Wer es schneller mag, aktiviert „Miniaturen im Systemcache ablegen“; dann erzeugt die Übersicht von macOS die Miniaturen und legt sie wie für den Finder im Systemcache ab.

## Sensible Inhalte

Ist in den Systemeinstellungen unter „Datenschutz & Sicherheit“ der Hinweis für sensible Inhalte eingeschaltet, zeigt Motiv Bilder mit möglicherweise sensiblen Inhalten weichgezeichnet, bis du „Anzeigen“ wählst. ⇧⌘U setzt das bis zum Beenden aus. Geprüft wird nur auf deinem Mac.

> Ist über die Bildschirmzeit die Kommunikationssicherheit für ein Kind eingerichtet, zeigt Motiv solche Bilder gar nicht und lässt sich das auch nicht aussetzen.

# Fragen und Antworten

## Kann ich mit Motiv Bilder bearbeiten oder umbenennen?

Nein. Motiv ist ein reiner Betrachter. Zum Bearbeiten öffnest du das Bild in Vorschau oder einem anderen Programm.

## Ein Ordner in der Seitenleiste ist ausgegraut.

Motiv kann ihn gerade nicht lesen, etwa weil die Festplatte nicht angeschlossen ist oder der Ordner verschoben wurde. Über das Kontextmenü „Erneut freigeben …“ wählst du ihn neu aus.

## Die Übersicht fragt, ob sie wirklich alle Bilder zeigen soll.

Mit Unterordnern kann ein Ordner sehr viele Bilder enthalten. Ab 10.000 fragt Motiv nach, bevor es alle einliest.

## Was passiert mit meinen Bildern?

Nichts, außer dass sie angezeigt werden. Motiv modifiziert deine Bilder nicht und lädt nirgendwo etwas hoch.

# Tastaturkürzel

Die wichtigsten Befehle lassen sich ohne Maus erreichen:

| Ordner hinzufügen | ⌘O |
| Bild öffnen, zurück zur Übersicht | ↩, Esc |
| Vorheriges und nächstes Bild | ← und → |
| Erstes und letztes Bild | Pos1, Ende |
| Seitenweise blättern | Bild auf, Bild ab |
| Zurück, Vorwärts | ⌘[, ⌘] |
| Übergeordneter Ordner | ⌘↑ |
| Vergrößern, Verkleinern, Originalgröße | ⌘+, ⌘-, ⌘0 |
| An Fenster anpassen | ⌘9 |
| Nach links, nach rechts drehen | ⌘L, ⌘R |
| Seitenleiste umschalten | ⌃⌘1 bis ⌃⌘4 |
| Informationen, Schnellinfo | ⌘I, ⌥⌘I |
| Nur das Bild im Vollbild | ⌥⌘F |
| Bilder vergleichen | ⌃⌘C |
| In Vorschau öffnen | ⌘E |
| Drucken | ⌘P |
| Im Finder zeigen | ⇧⌘R |

# Datenschutz

Motiv übermittelt keine Daten. Es gibt kein Tracking, keine Analyse und keine Werbung, und die App baut selbst keine Verbindung ins Internet auf; nur ein freiwilliges Trinkgeld läuft über den App Store. Deine Bilder werden ausschließlich auf deinem Mac gelesen und angezeigt.

## Was lokal gespeichert wird

- Deine Einstellungen
- Die freigegebenen Ordner und Favoriten
- Der zuletzt gezeigte Ordner sowie Größe und Position der Fenster

Diese Angaben verlassen deinen Mac nicht. Miniaturen und Bildinformationen hält Motiv nur im Arbeitsspeicher.

> Wer möchte, kann die Weiterentwicklung mit einem freiwilligen Trinkgeld unterstützen. Es schaltet nichts frei: Motiv bleibt vollständig kostenlos.
