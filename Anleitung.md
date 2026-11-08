# Bild-Atelier 1.9.0 – portables Buildpaket

Nativer Bild- und Videobetrachter für macOS 13 oder neuer. Dieses Paket enthält den aktualisierten Quellcode und ein Buildskript für Apple Silicon und Intel. Die App wird direkt auf dem Ziel-Mac erstellt; eine vorkompilierte App ist nicht enthalten.

## Erstellen und starten

Siehe **BITTE-ZUERST-LESEN.txt** im Paket. **App-erstellen-und-starten.command** baut für den aktuellen Mac; **Universal-App-erstellen.command** baut für Intel und Apple Silicon. Beide führen anschließend die Selbsttests mit temporären Dateien aus. Das Ergebnis liegt unter **Build/Bild-Atelier.app**, das Protokoll unter **Build/Build-Protokoll.txt**.

Benötigt werden macOS 13 oder neuer sowie passende Apple Command Line Tools (Swift 5.7+) oder Xcode. Fehlende Werkzeuge lassen sich mit `xcode-select --install` installieren. Kein Python und kein Homebrew erforderlich. Der Build verwendet keine festen Benutzerpfade und keine fest vorgegebene SDK-Version. Eine bestehende App im Build-Ziel wird mit Zeitstempel aufbewahrt.

**Prüfstand:** Universal-Build erfolgreich; 99 Funktions- und neun Leistungsprüfungen bestanden.

## Neu in Version 1.9.0: RAM-Suchindex

Nach einer vollständig abgeschlossenen Suche bleiben die Dateiliste, Metadaten und normalisierten Suchtexte des Ordnerbaums im Arbeitsspeicher. Auch Dateien, die nicht zur ersten Suchanfrage passen, werden indexiert. Weitere Suchbegriffe im selben Ordnerbaum werden ohne erneutes Einlesen des Ordners oder der Bild-/XMP-Dateien ausgewertet. Die Statuszeile zeigt dann **RAM-Cache**. Das gilt auch nach dem Leeren des Suchfeldes oder einem zwischenzeitlichen Ordnerwechsel, solange der Index noch vorhanden ist.

Es bleiben bis zu vier zuletzt verwendete Ordnerbäume erhalten. Das Kostenbudget des Suchindex beträgt rund 96 MiB, zusätzlich zum bestehenden Metadaten- und Thumbnailcache. Dies ist keine Obergrenze für den gesamten App-Arbeitsspeicher. Überschreitet ein einzelner Baum das Indexbudget, bleibt die normale Hintergrundsuche verfügbar. Unvollständige, abgebrochene oder teilweise unlesbare Durchläufe werden nicht als vollständiger Index gespeichert.

**⌘R bzw. Aktualisieren** verwirft den betroffenen Index und liest die Dateien neu. Dateiaktionen innerhalb der App invalidieren betroffene über- und untergeordnete Indizes automatisch. Externe Änderungen, insbesondere in Unterordnern oder XMP-Dateien, werden bei einer reinen RAM-Suche nicht geprüft: dafür bitte ⌘R verwenden. Beim Beenden der App wird der RAM-Index verworfen; er wird nicht auf Festplatte gespeichert.

## Portabilität seit Version 1.8.1

- Erkennt Intel und Apple Silicon automatisch, auch bei einem Terminal unter Rosetta.
- Optionaler Universal-Build für beide Architekturen.
- Dynamische Compiler-/SDK-Erkennung mit einer SwiftUI-Kompatibilitätsprobe.
- Öffentliche SwiftUI-State-Property-Wrapper werden ohne Abhängigkeit vom neuen gleichnamigen Macro-Plug-in verwendet.
- Temporärer Build hält iCloud-/Finder-Metadaten aus der Signierung heraus. Pfade mit Leerzeichen und Umlauten sind unterstützt.
- Fehlende Entwicklerwerkzeuge und zu alte macOS-Versionen erhalten eine verständliche Meldung.
- Korrigiert eine Pfadvergleichsstelle bei schnell wechselnden Suchanfragen.

## Neu: Suche und Dateiverwaltung

Das Eingabefeld befindet sich direkt rechts neben dem Raster-/Listenumschalter. Es durchsucht den aktuellen Ordner und seine Unterordner nach Dateinamen und den von der App gelesenen Datei-/EXIF-/IPTC-/XMP-Metadaten. Groß-/Kleinschreibung und Akzente sind unerheblich. Mehrere durch Leerzeichen getrennte Suchwörter müssen alle vorkommen, dürfen aber in unterschiedlichen Feldern stehen. Treffer erscheinen während der Suche; bestehende Metadatenfilter gelten zusätzlich. Die Sortierung wird nach Abschluss der Suche angewendet.

Die Suche läuft nach kurzer Tipp-Pause im Hintergrund, ist bei Änderungen abbrechbar und nutzt einen begrenzten Metadatencache. Die Statuszeile zeigt die Anzahl geprüfter Dateien. Unlesbare Ordner werden gemeldet. Versteckte Ordner, App-Pakete und symbolische Verknüpfungen werden nicht durchsucht. Auch Videos werden berücksichtigt. Bei Änderungen in Unterordnern die Suche mit ⌘R aktualisieren; es findet keine dauerhafte Überwachung des gesamten Baums statt.

Rechtsklick auf einen Treffer → **Zum Ordner wechseln** beendet die Suche, öffnet dessen direkten Ordner und markiert die Datei. Das × im Suchfeld beendet die Suche im bisherigen Stammordner.

In beiden Ansichten:

| Bedienung | Aktion |
| --- | --- |
| ⌘-Klick | Einzelne Objekte zur Auswahl hinzufügen oder entfernen |
| Umschalt-Klick | Zusammenhängenden Bereich auswählen |
| ⌘A | Alle aktuell angezeigten Objekte auswählen |
| ⌘C / ⌘X | Kopieren / zum Verschieben vormerken |
| ⌘V | In den aktuellen Browserordner einfügen; nach Ausschneiden verschieben |
| ⌥⌘V | Kopierte Dateien hierher bewegen, auch aus dem Finder |
| ⌘D | Duplizieren |
| ⌘Rückschritt | Nach Rückfrage in den Papierkorb verschieben |
| Kontextmenü | Zusätzlich Umbenennen, Verschieben nach … und Im Finder anzeigen |

Im Suchfeld gelten die üblichen Textbefehle; ⌘C kopiert dort Text. Einfügen während einer Suche verwendet den angezeigten Such-Stammordner als Ziel. Zum Einfügen in einen Trefferordner zuerst „Zum Ordner wechseln“ verwenden. Auswahl und aktives Bild werden beim Ansichtswechsel beibehalten.

Es wird nichts dauerhaft gelöscht. Wiederherstellen aus dem Papierkorb erfolgt im Finder. Es gibt in dieser Version noch keine eigene Rückgängig-Historie für Dateiaktionen. Vorhandene Dateien werden nicht überschrieben; Kopien erhalten bei Konflikten einen Zusatz „Kopie“. Umbenennen auf einen bereits vorhandenen Namen wird abgelehnt.

**XMP:** Die von der App zugeordnete Begleitdatei wird mitkopiert, mitverschoben, passend umbenannt bzw. mit in den Papierkorb verschoben. Ihre bisherige Namenskonvention (beispielsweise `_jpg.xmp`) bleibt erhalten. Ein gemeinsam genutztes XMP bleibt am ursprünglichen Ort, solange ein nicht ausgewähltes Bild darauf angewiesen ist. Andere Begleitformate außer XMP werden nicht automatisch mitgenommen. Bild- und Metadateninhalte werden nicht bearbeitet.

## Ordnerleiste

- **Angepinnt** und **Zuletzt geöffnet** sind durch Klick auf ihre Überschrift auf- und zuklappbar.
- Rechtsklick auf einen Ordner: anpinnen, loslösen, einer Gruppe zuordnen, im Finder anzeigen oder aus der Leiste entfernen.
- Gruppen über das Kontextmenü oder **Ablage → Neue Ordnergruppe** anlegen.
- Der Trenner zwischen Ordnerleiste und Browser lässt sich ziehen. Das Seitenleistensymbol blendet die Leiste aus und ein.
- Ordnerauswahl, angepinnte Ordner, Gruppen, Ansichtsoptionen und Spalten werden lokal gespeichert. Entfernen aus der Leiste löscht keine Dateien.

## Browser

Das Raster-/Listensymbol schaltet zwischen Thumbnails und Tabelle um. Der Regler verändert die Thumbnailgröße. Das Textsymbol blendet sämtliche Thumbnail-Textzeilen aus bzw. wieder ein.

Unter **Einstellungen → Thumbnails** lassen sich vier Zeilen einzeln belegen oder abschalten, beispielsweise Dateiname, Aufnahmezeit, Kamera und IPTC-Titel. Insgesamt stehen 29 Dateieigenschaften und EXIF-/IPTC-Felder zur Auswahl. Nicht vorhandene Werte erscheinen als „—“.

In der Tabelle öffnet ein **Rechtsklick auf die Spaltenüberschriften** die Spaltenauswahl. Alternativ findet sie sich in den Einstellungen. Spalten sind verschiebbar, in der Breite veränderbar und durch Klick auf die Überschrift sortierbar. Dateigröße wird numerisch sortiert. Die Symbolleiste bietet ebenfalls eine Sortierauswahl. **⌘R** liest den Ordner erneut. Änderungen am Ordner werden auch automatisch erkannt.

Unterordner stehen vor den Bild- und Videodateien. Ein Doppelklick öffnet einen Unterordner. Die Pfeile links in der Symbolleiste führen zurück bzw. eine Ebene nach oben. Die linke Leiste zeigt einen aufklappbaren Ordnerbaum; beim Hineinnavigieren wird der passende Pfad automatisch aufgeklappt. Ordnernamen bleiben auch bei ausgeblendeten Metadaten sichtbar. Versteckte Dateien und App-Pakete erscheinen nicht.

## Einzelbild im Vollbild

Ein Doppelklick öffnet die Datei. Die Ansicht füllt den Bildschirm des Browserfensters. Menüleiste, Dock, Fenstertitel und Werkzeugleisten sind ausgeblendet. Bilder werden proportional vor dunkelgrauem Hintergrund eingepasst. Der obere Bereich in Höhe der Menüleiste beziehungsweise der Notch bleibt schwarz. Bilder, Videos und Overlays liegen vollständig darunter.

| Taste / Geste | Funktion |
| --- | --- |
| ← / → | Vorherige / nächste Datei in der aktuellen Sortierung |
| ↑ | Vorschauleiste öffnen; Tastaturfokus liegt unmittelbar in der Leiste |
| ← / → bei offener Leiste | Vorschau auswählen, ohne das große Bild zu wechseln |
| ↓ oder Enter | Vorschau übernehmen und Leiste schließen |
| i | Halbtransparentes EXIF-/IPTC-Overlay im rechten Bildschirmdrittel |
| + / − oder Trackpad-Pinch | Vergrößern / verkleinern |
| 0 | Bild einpassen |
| 1 | Originalgröße: ein Bildpixel entspricht einem Bildschirm-Pixel |
| Rechte Maustaste halten und ziehen / Trackpad mit zwei Fingern bewegen | Vergrößertes Bild verschieben |
| Doppelklick auf das Bild | Zwischen Einpassen und Originalgröße wechseln |
| Leertaste | Video abspielen / pausieren; am Ende erneut starten |
| Esc | Zum Browser zurückkehren; zuletzt angezeigte Datei bleibt markiert |

Ein Klick auf ein Thumbnail in der Vorschauleiste übernimmt es sofort. Die Navigation stoppt am ersten bzw. letzten Eintrag. Esc kehrt auch bei offener Vorschauleiste direkt zum Browser zurück; eine nur vormarkierte Vorschau wird dabei nicht übernommen.

## Zweiter Monitor und Finder

**CMD beim Doppelklick gedrückt halten:** Das Bild öffnet sich auf einem anderen angeschlossenen Monitor. Bei mehreren zusätzlichen Monitoren wird der erste von macOS gemeldete andere Monitor verwendet. Ohne zweiten Monitor öffnet sich das normale Vollbild.

Der Browser bleibt im Zweitmonitor-Modus aktiv. Ein Klick auf ein anderes Bild oder die Auswahl per Pfeiltasten aktualisiert die Bildanzeige sofort, auch beim Wechsel des Ordners. Ordner selbst werden nicht als Bild dargestellt. ESC im Bildfenster beendet die Anzeige. Andere Apps auf den übrigen Monitoren bleiben bedienbar; die Anzeige holt den Fokus nicht zurück.

**Finder → Öffnen mit → Bild-Atelier:** Das gewählte Bild öffnet sich direkt im Vollbild. ESC zeigt seinen Ordner im Browser und markiert die Datei. Die App registriert sich als zusätzlicher Betrachter für Bilder und Videos, ohne die Standard-App zu ändern.

Zwei-Finger-Bewegungen und das Mausrad verschieben den Ausschnitt; sie zoomen nicht. Auf dem Trackpad zoomt ausschließlich die Pinch-Geste. Zusätzlich bleiben die Tastaturbefehle für Zoom verfügbar.

## Formate und Metadaten

Die Bilddarstellung nutzt Apples **ImageIO**, **Core Graphics** und **AppKit**, Videos verwenden **AVFoundation mit AVPlayerLayer**. EXIF-Orientierung und eingebettete Farbprofile werden beim Decodieren berücksichtigt. Das sind öffentliche macOS-Bildschnittstellen; die interne Rendering-Implementierung von Apples „Vorschau“ wird nicht eingebunden oder als identisch vorausgesetzt.

Typische Formate sind JPEG, PNG, TIFF, HEIC, GIF und von der installierten macOS-Version unterstützte RAW-Formate. Mehrseitige bzw. animierte Bilddateien werden als erstes Bild angezeigt. Videoformate und Codecs hängen von der macOS-Unterstützung ab; nicht unterstützte Dateien erhalten eine verständliche Fehlermeldung. Für RAW besteht keine zusätzliche herstellerspezifische Decoder-Bibliothek.

EXIF und eingebettetes IPTC werden gelesen. Häufige eingebettete XMP-Felder ergänzen fehlende IPTC-Werte. Ab Version 1.7 werden externe XMP-Begleitdateien berücksichtigt; Details und Grenzen stehen im Abschnitt „XMP und Nitro“. Videos zeigen vorhandene QuickTime-/AVFoundation-Metadaten; fehlende Fotofelder bleiben leer. Beim Betrachten bleiben Bild- und Metadateninhalte unverändert. Dateiaktionen können Dateien umbenennen, kopieren, verschieben oder in den Papierkorb legen.

Thumbnails und Metadaten werden bedarfsgesteuert im Hintergrund geladen. Sichtbare Fotos und das aktuelle Vollbild haben Vorrang. Bei EXIF/IPTC-Sortierung, Metadatenfiltern oder einer Suche werden auch die Metadaten noch nicht sichtbarer Dateien geladen. Unveränderte Dateieinträge bleiben bei einer Aktualisierung erhalten. Der Thumbnail-Cache ist auf etwa 96 MiB Kosten begrenzt; Metadaten haben einen separaten begrenzten Cache. Vorschauen werden abhängig von ihrer Anzeigegröße mit maximal 256, 512 oder 840 Pixeln dekodiert. Gleichzeitige identische Anfragen teilen denselben Ladeauftrag. Außerhalb der sichtbaren Rasterfläche geben die Ansichten ihre Bildreferenzen frei. Die Cache-Grenzen begrenzen nicht den gesamten App-Speicher, insbesondere große Vollbilder benötigen zusätzlichen Speicher. Im Vollbild wird zunächst eine Vorschau bis 4096 Pixel geladen; beim Hineinzoomen folgt die Originalauflösung. Sehr große Originaldateien benötigen entsprechend Arbeitsspeicher.

## Quellcode und Prüflauf

Im Ordner **Quellcode** liegen sämtliche Swift-Dateien, das App-Manifest und das Buildskript. Es sind keine externen Swift-Pakete erforderlich.

Mit installierten Apple Command Line Tools:

```sh
cd Quellcode
bash build.sh
Build/Bild-Atelier.app/Contents/MacOS/BildAtelier --self-test --skip-video --demo
```

Der Selbsttest erstellt temporäre Bild- und Videodateien und prüft Medienfilter, EXIF/IPTC, Orientierung, Seitenverhältnis, Zoom und die getrennte Vorschau-/Vollbildauswahl. Testdateien werden anschließend entfernt. `--self-test --fixtures /absoluter/Testordner` behält sie für eine manuelle Prüfung.

Apple-Dokumentation:
- https://developer.apple.com/documentation/imageio/cgimagesource
- https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct/hidemenubar
- https://developer.apple.com/documentation/avfoundation/avplayerlayer

## Prüfstand 22.10.2026

40 automatisierte Funktionsprüfungen für Medienerkennung, Metadaten, EXIF-Ausrichtung, Navigation und Zoom sind bestanden. Zusätzlich wurden Raster, Tabelle, Spaltenauswahl per Rechtsklick, Einstellungen, Doppelklick, Vollbild-Overlay, Vorschauleiste, Escape-Rückkehr und MP4-Wiedergabe mit einem eigens erzeugten H.264-Testvideo direkt auf einem Apple-Silicon-Mac geprüft. Die Intel-Ausgabe ist kompiliert, wurde jedoch nicht auf einem Intel-Mac ausgeführt. RAW-Varianten und sämtliche herstellerspezifischen Metadaten wurden nicht einzeln getestet.

Version 1.2: Finder → Öffnen mit und Escape-Rückkehr direkt geprüft. Mehrmonitor-Fokuswechsel, Live-Bild auf dem Zielmonitor sowie physische Rechtsdrag-/Trackpad-Gesten sind nicht vollständig Ende-zu-Ende verifiziert. Verschieben, Auswahlereignisse und Finder-Ladeablauf sind automatisiert geprüft.

## Version 1.3 – Geschwindigkeit und große Ordner

- Ordnerinhalt und Unterordnerliste entstehen aus einem gemeinsamen, abbrechbaren Scan. Wiederholtes Aufklappen nutzt einen kurzzeitig gültigen Ordnercache.
- Veraltete Scans, Sortierungen und Metadatenaufträge werden beim Ordnerwechsel abgebrochen bzw. ihre Ergebnisse verworfen. Ein bereits laufender blockierender Systemzugriff kann erst nach seiner Rückkehr beendet werden.
- Die Seitenleiste baut nur die benötigten Zeilen des flachen Ordnerbaums auf; auch tausend Unterordner erzeugen nicht gleichzeitig tausend vollständige Ansichten.
- Natürliche Sortierung läuft im Hintergrund. Die Tabellenansicht lädt bei neuen Metadaten nur sichtbare Zeilen neu; Dateiauswahl und Zähler verwenden vorbereitete Indizes.
- Datumsformatierer werden pro Arbeitsthread wiederverwendet.
- Das Vollbild kann ein vorhandenes Thumbnail sofort anzeigen, während die größere Bildfassung im Hintergrund lädt.

### Vergleichstest auf Apple Silicon, 22.10.2026

Ein lokaler Testordner enthält 2.000 synthetische JPEGs (je 1200 × 800 Pixel, etwa 40 KB) und 1.000 Unterordner. Die Dateien wurden unmittelbar vor der Messung erzeugt; Betriebssystem-Caches können somit warm sein. Gemessen ist der Ladeablauf bis zur verfügbaren Dateiliste, einschließlich Grundsortierung, aber ohne Zeichnen des Fensters und ohne sämtliche Thumbnails.

| Vorgang | Version 1.2 | Version 1.3 |
| --- | ---: | ---: |
| Großen Ordner einlesen | 1.085,5 ms | 373,6 ms |
| Unveränderten Ordner aktualisieren | 781,4 ms | 306,3 ms |
| 20 schnelle Ordnerwechsel bis zum letzten Ziel | 9.894,6 ms | 16,4 ms |

Die größte gemessene Pause eines alle 10 ms geplanten Main-Runloop-Timers lag beim ersten Scan bei 34,2 ms in Version 1.2 und 12,0 ms in Version 1.3. Dies ist keine Messung der Bildwiederholrate. Messwerte schwanken mit Datenträger, Dateiarten, Cache-Zustand und Rechnerlast. Netzlaufwerke, Cloud-Platzhalter und große RAW-Dateien können wesentlich länger benötigen.

40 Funktionsprüfungen und neun zusätzliche Prüfungen für große Ordner bestanden. Die Zusatzprüfungen decken vollständige Einträge, bedarfsgesteuerte Metadaten, Wiederverwendung unveränderter Objekte, EXIF-Sortierung aller 2.000 Fotos und schnelle Ordnerwechsel ab. Direkt in der App geprüft: 3.000 Einträge, Scrollen zu den letzten Fotos, Vollbild mit EXIF/IPTC, Escape mit Auswahl, Tabellenansicht mit Metadaten und Scrollen ans Ende der 1.000 Unterordner. Intel kompiliert, nicht auf Intel-Hardware ausgeführt.

Lasttest wiederholen:

```sh
Build/Bild-Atelier.app/Contents/MacOS/BildAtelier --performance-test
```

Der Test erzeugt etwa 80 MB temporäre Testdateien und räumt diese anschließend wieder auf. `--keep-performance-fixtures` behält sie für eine Prüfung in der Oberfläche. Die detaillierten Ergebnisse liegen im Quellcode unter `Tests`.


## Neu in Version 1.4

Rechts neben „Angepinnt“ durchsucht das Suchfeld die Namen aller angepinnten Ordner und ihrer Unterordner. Über das Filtersymbol lassen sich eine Gruppe und die Suche im vollständigen Pfad wählen. Ergebnisse zeigen ihren Pfad; Anklicken öffnet den Ordner und klappt seine Vorfahren auf. Versteckte Ordner, Paket-Inhalte und symbolische Links werden nicht rekursiv durchsucht.

„Sortieren & Filtern“ oberhalb des Bildbrowsers öffnet die Metadatenleiste. Voreingestellt sind Aufnahmetag, Kamera, Objektiv und Stichwörter. „Spalten“ ergänzt oder entfernt Dateidaten und Metadaten; die Auswahl wird gespeichert. Ein Pfeil in der Spaltenüberschrift sortiert danach. Alle gewählten Werte gelten gemeinsam (UND), auch innerhalb derselben Spalte. „Alle“ löscht die Auswahl einer Spalte; „Zurücksetzen“ alle Filter.

Werte und Trefferzahlen berücksichtigen die Filter der jeweils anderen Spalten. Während Metadaten laden, können weitere Werte und Treffer hinzukommen. Die Leiste wirkt auch auf die Tabellenansicht und die Navigation im Vollbild. Unterordner bleiben zur Navigation sichtbar. Beim Ordnerwechsel werden die aktiven Dateifilter zurückgesetzt. Zugeklappt bleiben gewählte Filter aktiv; ohne aktive Filter werden Metadaten weiterhin nur bedarfsgerecht geladen.

## Neu in Version 1.5

Filterspalten verteilen sich zunächst gleichmäßig über die gesamte Browserbreite. Ziehe die Trennlinie rechts einer Spalte, um deren Breite festzulegen. Manuelle Breiten werden gespeichert; unveränderte Spalten teilen sich den verbleibenden Platz. Bei Platzmangel lässt sich horizontal scrollen. Über „Spalten → Spalten gleichmäßig verteilen“ werden manuelle Breiten zurückgesetzt. Die Griffleiste am unteren Rand verändert die Höhe; auch diese wird gespeichert.

Alle gewählten Filterwerte sind UND-verknüpft. Zwei Stichwörter finden nur Dateien, die beide enthalten. Zwei unterschiedliche Kamerawerte ergeben daher keine Treffer bei Dateien mit nur einer Kamera.

Die Ordnersuche sitzt kompakt rechts neben „Angepinnt“, mit größerem Abstand zur Überschrift. Beim Bearbeiten oder bei vorhandenem Suchtext wird sie breiter. Ein erneuter Klick auf den aktuell geöffneten Ordner klappt dessen Unterordner ein beziehungsweise wieder aus.

## Neu in Version 1.6

Die Filterspalten schränken sich gegenseitig ein. Eine Kameraauswahl zeigt beispielsweise nur noch Aufnahmetage, Objektive und Stichwörter der passenden Dateien. Jede Spalte berücksichtigt alle Filter der anderen Spalten; ihre eigene Auswahl schränkt ihre Optionen nicht ein. Trefferzahlen beziehen sich ebenfalls auf diesen eingeschränkten Bestand. Nicht mehr passende Optionen verschwinden. „Alle“ löscht weiterhin die Auswahl einer Spalte, „Zurücksetzen“ sämtliche Filter. Die UND-Verknüpfung bleibt erhalten.

## Neu in Version 1.6.1

Unterordner angepinnter Ordner erscheinen in der linken Leiste auf jeder aufgeklappten Ebene nach Namen absteigend (Z–A, Zahlen in natürlicher Reihenfolge).

## Neu in Version 1.6.2

Das Filtermenü neben der Ordnersuche und das Sortiermenü in der Browser-Symbolleiste zeigen keinen zusätzlichen Abwärtspfeil mehr. Die Menüs öffnen weiterhin per Klick auf ihr Symbol.

## Neu in Version 1.6.3

Ordner ohne Unterordner zeigen links kein Aufklappsymbol. Der Platz bleibt frei, sodass alle Ordner unverändert eingerückt sind. Sichtbare Ordner werden dafür im Hintergrund geprüft.

## Neu in Version 1.7: XMP und Nitro

XMP-Begleitdateien werden aus dem gleichen Ordner gelesen. Unterstützt werden `Foto.xmp`, `Foto.ORF.xmp` sowie Nitros Benennung `Foto_jpg.xmp`, `Foto_jpeg.xmp`, `Foto_dng.xmp` usw. Dateinamen vor der Endung werden exakt zugeordnet. Spezifische Begleitdateien haben Vorrang. Bei einem RAW+JPEG-Paar gehört `Foto.xmp` zum RAW, damit ein exportiertes JPEG nicht nochmals beschnitten wird.

Vorhandene XMP-Metadaten überschreiben die entsprechenden eingebetteten Angaben: Titel, Beschreibung, Stichwörter, Urheber, Copyright, Ortsangaben, Bewertung und Farbmarkierung. Nitro-Markierungen werden als gespeicherter Zahlenwert angezeigt. Die neuen Felder sind für Tabelle, Thumbnail-Text und Filter auswählbar; das Info-Overlay enthält einen XMP-Abschnitt. Leere XMP-Werte können eingebettete Angaben löschen. Bildbearbeitungen und Metadaten werden nicht zurückgeschrieben; die Dateiaktionen aus Version 1.8 können Dateien und Begleitdateien kopieren, umbenennen, verschieben oder in den Papierkorb legen.

**Experimentelle Nitro-Bildvorschau:** Unterstützt wird der einfache rechteckige Beschnitt aus Nitros unkomprimiertem EditModel Version 1 (XML → Property List → JSON), jeweils aus der aktiven Version. Die Umsetzung basiert auf der bereitgestellten XMP-Struktur. Die Koordinaten werden als CGRect mit Ursprung unten links interpretiert; ein direkter Vergleich mit dem bereitgestellten ORF/JPEG war wegen des fehlgeschlagenen lokalen Dateitransfers nicht möglich. Automatische Tests verwenden ein synthetisches Bild mit den Beispielmaßen 3888 × 5184 und dem Beschnitt 3313 × 4417.

Thumbnails und Vollbild verwenden denselben Beschnitt. **O** wechselt im Vollbild zur Originaldarstellung und zurück; **I** zeigt Details und Einschränkungen. Unterordner und XMP-Dateien selbst werden nicht als Fotos behandelt. Die unbeschnittene EXIF-Abmessung bleibt unter „Abmessungen“ erhalten.

Noch nicht unterstützt: Nitro-Farb-/Tonwertbearbeitungen, Masken, Perspektive, Begradigung und von der Originaldatei abweichende Ausrichtungen sowie komprimierte oder unbekannte EditModel-Versionen. Solche Einstellungen werden im XMP-Status genannt und nicht stillschweigend nachgebildet. Bei abweichender Ausgangsgröße/Ausrichtung wird der Beschnitt übersprungen. Die RAW-Farbwiedergabe stammt weiterhin von macOS und muss nicht exakt dem Nitro-Export entsprechen.

Neue oder geänderte XMP-Dateien werden beim Aktualisieren des Ordners berücksichtigt; ⌘R erzwingt dies. Eine bereits geöffnete Vollbildansicht danach schließen und erneut öffnen. Ordnerüberwachung kann Änderungen automatisch erkennen, je nach Dateisystem aber nicht jede Änderung innerhalb einer bestehenden Datei.
