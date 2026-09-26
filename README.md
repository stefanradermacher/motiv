# Motiv

Schlichter Bild- und Galeriebetrachter für macOS 15+, gebaut mit SwiftUI, ImageIO und Quick Look. Er zeigt Bildsammlungen in Ordnerstrukturen an und verändert keine Datei.

Motiv ist quelloffen (Apache-Lizenz 2.0, siehe `LICENSE`), werbefrei und übermittelt keine Daten: kein Tracking, keine Analyse, keine eigenen Netzwerkverbindungen. Es nutzt ausschließlich Apple-Frameworks. Wer die Entwicklung unterstützen möchte, kann unter **Motiv → Über Motiv** ein freiwilliges Trinkgeld über den App Store geben; es schaltet nichts frei.

Nicht Teil des lizenzierten Werks sind die Kennzeichen des Projekts: der Name „Motiv“, das App-Symbol, die Monogramme und `scripts/make_icon.swift`, das das App-Symbol zeichnet. Was damit erlaubt ist, steht in `TRADEMARKS.md`. `NOTICE` hält den Umfang fest und ist nach Abschnitt 4(d) der Lizenz bei jeder Weitergabe mitzuführen.

Die Oberfläche gibt es auf Deutsch und Englisch. Die Texte liegen im String-Katalog `Resources/Localizable.xcstrings`; die Schlüssel sind die deutschen Sätze.

## Grundidee

- **Ordner statt Bibliothek.** Motiv arbeitet direkt auf Ordnern im Dateisystem. Man gibt einen Ordner einmal frei (⌘O, per Drag & Drop aufs Dock-Symbol oder beim ersten Öffnen eines Bildes daraus), Motiv merkt sich die Freigabe als Security-Scoped Bookmark und zeigt ihn mit allen Unterordnern in der Seitenleiste.
- **Nur betrachten.** Drehen und Spiegeln wirken nur in der Ansicht und werden nie gespeichert. Zum Bearbeiten öffnet man das Bild in Vorschau (⌘E) oder über „Öffnen mit“ in einem anderen Programm.
- **Standard-App.** Unter **Motiv → Einstellungen** lässt sich Motiv als Standard-App für Bilder festlegen, für alle Formate auf einmal oder einzeln (JPEG, PNG, HEIC, TIFF, GIF, WebP, AVIF, BMP, ICNS, ICO; Kamera-RAW bewusst nicht). Nach drei Tagen Nutzung bietet Motiv das wie Leser höchstens zweimal in einem schmalen Balken an. Das geht nur mit einer Kopie im Ordner „Programme“.
- **Ordnerleiste.** Über der Übersicht zeigt eine Zeile die Unterordner des aktuellen Ordners mit Namen und Bildzahl, vorne als grauer Ordner mit Pfeil den übergeordneten Ordner; sie erscheint deshalb auch in Ordnern ohne Unterordner. Ein Klick öffnet den Ordner. Die Trennlinie darunter lässt sich ziehen, die Symbole wachsen mit und bleiben in einer Zeile, die sich mit dem Mausrad seitwärts scrollen lässt. Die Höhe gilt für alle Ordner; ein Doppelklick auf die Trennlinie oder das Kontextmenü der Leiste stellt die Standardhöhe wieder her. Ein- und ausschalten über den Button vor „Mit Unterordnern“ oder das Menü Darstellung.
- **Bilderliste.** Die Seitenleiste kann auch die Bilder des Ordners als Liste zeigen, bei einbezogenen Unterordnern nach Unterordnern gegliedert. Man blättert darin mit Pfeiltasten oder Maus, rechts steht das Bild; die Miniaturleiste unten entfällt dann.
- **Informationen.** Die Seitenleiste zeigt wahlweise die Ordner, die Informationen zum Bild (Datei, Bild, Aufnahme/EXIF, Ort, Beschreibung, Video, alle Metadaten) oder beides übereinander. Jede Ansicht merkt sich ihre Wahl: In der Übersicht stehen meist die Ordner, in der Einzelansicht die Informationen. Orte öffnet Motiv in Karten, eine eingebettete Karte gibt es nicht, weil sie Kacheln aus dem Netz laden würde.
- **Sensible Inhalte.** Ist in den Systemeinstellungen unter „Datenschutz & Sicherheit“ der Hinweis für sensible Inhalte eingeschaltet, prüft Motiv Bilder mit Apples SensitiveContentAnalysis auf dem Mac und zeigt mögliche Nacktbilder weichgezeichnet, bis man „Anzeigen“ wählt. ⇧⌘U setzt das bis zum Beenden aus. Eine eigene Einstellung dafür gibt es bewusst nicht.
- **Videos werden erkannt, aber nicht abgespielt.** Sie erscheinen mit Standbild in der Übersicht; ein Doppelklick öffnet sie im Standardprogramm.

### Warum Ordner freigeben?

In der Sandbox darf eine App nur lesen, was der Benutzer ausgewählt hat. Öffnet man ein einzelnes Bild per Doppelklick, bekommt Motiv nur diese eine Datei, nicht die Bilder daneben. Liegt das Bild in keinem freigegebenen Ordner, zeigt Motiv es zunächst allein; in der Titelzeile steht dann „Ordner nicht freigegeben“ mit dem Button „Ordner freigeben …“.

## Bauen

Motiv ist ein Xcode-Projekt (`Motiv.xcodeproj`, Xcode 27 oder neuer, macOS 15+). In Xcode öffnen und mit ⌘R starten; für einen signierten Build unter „Signing & Capabilities“ das eigene Team eintragen.

Ohne Xcode-Oberfläche:

```
./build.sh
```

Das baut `build/Motiv.app` mit `xcodebuild` (mit derselben Sandbox wie im App Store) und installiert die App nach `/Applications`. Läuft Motiv gerade, wird es vorher beendet und danach wieder geöffnet. Nur bauen, ohne zu installieren: `./build.sh --no-install`.

Nennt `Config/Local.xcconfig` eine Team-ID, signiert `build.sh` mit diesem Team; Xcode legt App-ID und Entwicklungsprofil bei Bedarf im Entwicklerkonto an. Ohne Team-ID, oder mit `--adhoc`, signiert es ad hoc – dann ohne Entwicklerkonto, aber auch ohne die Berechtigung zur Prüfung sensibler Inhalte (`Config/Motiv-AdHoc.entitlements`), denn die verlangt ein Provisioning-Profil. Die App läuft trotzdem vollständig, sie prüft nur keine Bilder.

Die Versionsnummer steht im Projekt unter „Version“ (`MARKETING_VERSION`) und wird von Hand erhöht. Die Build-Nummer steht als `CURRENT_PROJECT_VERSION` in `Config/Motiv.xcconfig`. **Vor jedem Upload in den App Store einmal `./scripts/bump-build.sh` ausführen und mitcommitten.**

Das App-Icon und das Dokumentsymbol zeichnet `scripts/make_icon.swift`: das App-Icon in den Asset-Katalog, das Dokumentsymbol nach `Resources/ImageDocument.icns`. Das Dokumentsymbol zeigt macOS nur, wenn Motiv die Standard-App für ein Bildformat ist, und auch dann meist nur dort, wo es keine Vorschau des Bildes gibt. Nach Änderungen an der Zeichnung im Projektordner `swift scripts/make_icon.swift` ausführen.

### Projektstruktur

- `Sources/Motiv/`: Quellcode; neue Dateien gehören automatisch zum Projekt
  - `Library.swift`: freigegebene Ordner, Favoriten, Ordnerbaum
  - `Gallery.swift`: Inhalt eines Fensters — Ordner, Auswahl, Sortierung, Übersicht und Einzelansicht
  - `GridView.swift`, `ViewerView.swift`, `SidebarView.swift`: die drei Bereiche des Fensters
  - `ImageViewerModel.swift`, `ImageCanvas.swift`: Laden, Drehen und Zoomen in der Einzelansicht
  - `Thumbnails.swift`: Miniaturen über Quick Look, mit Zwischenspeicher
  - `FileActions.swift`: Übergabe an Vorschau, „Öffnen mit“, Finder
- `Resources/`: Asset-Katalog mit App-Icon, Lokalisierung, `PrivacyInfo.xcprivacy`
- `Config/Info.plist`, `Config/Motiv.entitlements`: App-Einstellungen und Sandbox-Berechtigungen (selbst gewählte Dateien, dauerhafte Bookmarks)
- `Config/Motiv.storekit`: Trinkgelder zum Testen in Xcode (Kaffee, Frühstück, Abendessen), wie bei Leser
- `Config/Motiv.xcconfig`: Build-Einstellungen; bindet optional `Config/Local.xcconfig` ein

Zum Signieren mit eigenem Entwicklerkonto `Config/Local.xcconfig.example` nach `Config/Local.xcconfig` kopieren und die eigene Team-ID eintragen.

## Bedienung

| Funktion | Tastatur |
|---|---|
| Ordner hinzufügen | ⌘O |
| Bild öffnen / zurück zur Übersicht | ↩ oder ⌘↓ / Esc oder ⌘↑ |
| Übergeordneter Ordner (in der Übersicht) | ⌘↑ |
| Zurück / Vorwärts (Einzelansicht → Übersicht, zuvor gezeigter Ordner) | ⌘[ / ⌘] oder die Seitentasten der Maus |
| Auswahl bewegen / erweitern | Pfeiltasten / ⇧ + Pfeiltasten |
| Vorheriges / nächstes Bild | ← / → oder ⌘← / ⌘→ (in der Einzelansicht auch ↑ / ↓ und Leertaste) |
| Erstes / letztes Bild | Pos1 / Ende oder ⌘Pos1 / ⌘Ende |
| Vergrößern / Verkleinern (Übersicht: Miniaturen) | ⌘+ / ⌘- oder Pinch auf dem Trackpad |
| Standardgröße der Miniaturen (Übersicht) | ⌘0 oder Doppelklick auf den Größenregler |
| Originalgröße / An Fenster anpassen | ⌘0 / ⌘9 |
| Eingepasst ↔ näher heran (100 %, bei kleinen Bildern Fenstergröße) | Doppelklick ins Bild oder mit zwei Fingern doppeltippen |
| An Breite / Höhe anpassen, feste Zoomstufen | Klick auf die Prozentzahl in der Toolbar |
| Zoomstufe eingeben | ⌥⌘0 |
| Nach links / rechts drehen (nur Ansicht) | ⌘L / ⌘R oder mit zwei Fingern drehen |
| Nächstes / voriges Bild auf dem Trackpad | mit zwei Fingern waagerecht streichen (wenn „Mit Streichen Seiten blättern“ auf zwei Finger steht) |
| Horizontal / vertikal spiegeln (nur Ansicht) | Menü „Bild“ oder Toolbar |
| Mit Unterordnern (ab 10.000 Bildern mit Rückfrage) | ⌥⌘U |
| In Vorschau öffnen | ⌘E |
| Im Finder zeigen | ⇧⌘R |
| Ordner zu Favoriten hinzufügen | ⌃⌘T |
| Aktualisieren | ⌥⌘R |
| Kopieren / Alles auswählen | ⌘C / ⌘A |
| Seitenleiste: Ordner / Bilder / Informationen / Ordner und Informationen | ⌃⌘1 / ⌃⌘2 / ⌃⌘3 / ⌃⌘4 |
| Informationen ein-/ausblenden | ⌘I |
| Schnellinfo im Bild | ⌥⌘I |
| Nur Bild im Vollbild / beenden | ⌥⌘F / Esc |
| Sensible Inhalte weichzeichnen, bis zum Beenden ein/aus | ⇧⌘U |
| Bild per Namen finden (Übersicht) | Anfang des Namens eintippen |

## Geplant

- Diashow
- Vergleichsansicht für 2–4 Bilder
- „Exportieren als …“ über ImageIO (JPEG, PNG, HEIC, TIFF), immer in eine neue Datei
- Zwischenspeicher für Miniaturen auf der Platte, Ordner beobachten statt „Aktualisieren“
