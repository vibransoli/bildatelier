# Bild-Atelier

Nativer Bild- und Videobetrachter für **macOS 13 oder neuer**, für Intel und Apple Silicon. Aktueller Stand: **1.9.0**.

## Funktionen

- Ordnerbrowser mit angepinnten Ordnern und aufklappbarem Ordnerbaum.
- Thumbnail- und Tabellenansicht mit konfigurierbaren Metadaten.
- Vollbild, Zoom, Vorschauband und Anzeige auf einem zweiten Monitor.
- Rekursive Suche nach Dateinamen und EXIF-/IPTC-/XMP-Metadaten.
- RAM-Suchindex für schnelle Folgesuchen; Aktualisieren mit ⌘R.
- Mehrfachauswahl und Dateiaktionen einschließlich zugehöriger XMP-Dateien.
- Experimentelle Unterstützung einfacher Nitro-Beschnitte.

## Erstellen und starten

Repository klonen oder über **Code → Download ZIP** herunterladen und entpacken.

- `App-erstellen-und-starten.command`: App für den aktuellen Mac erstellen, Selbsttests ausführen und starten.
- `Universal-App-erstellen.command`: App für Intel und Apple Silicon erstellen.

Erforderlich sind Apples Command Line Tools mit Swift 5.7 oder neuer und einem passenden macOS-SDK, alternativ Xcode. Fehlende Werkzeuge installieren:

```sh
xcode-select --install
```

Das Ergebnis liegt unter `Build/Bild-Atelier.app`. Die Skripte verwenden relative Pfade und erkennen Compiler, SDK und Architektur automatisch. Es sind keine externen Swift-Pakete, Python oder Homebrew erforderlich. Die App ist lokal signiert, nicht von Apple notarisiert.

## Entwicklung auf mehreren Macs

Dieses Repository ist der gemeinsame Projektstand. Vor Änderungen den aktuellen Stand abrufen; Änderungen anschließend committen und pushen. Lokale Build-Ausgaben, Caches und Einstellungen werden nicht versioniert.

## Quellcode und Tests

Der Swift-Quellcode und die Testprogramme liegen in `Quellcode/Sources`, das Manifest in `Quellcode/Info.plist`. Ein Build ohne automatischen App-Start ist möglich mit:

```sh
bash Quellcode/build.sh --universal --output "$PWD/Build"
```

Die Startskripte führen Selbsttests mit temporären Testbildern aus. Für einen separaten Prüflauf das Programm aus dem Bundle kopieren, damit keine grafische LaunchServices-Sitzung benötigt wird:

```sh
TASK_CHECK_DIR="$(mktemp -d)"
cp Build/Bild-Atelier.app/Contents/MacOS/BildAtelier "$TASK_CHECK_DIR/BildAtelier-Check"
"$TASK_CHECK_DIR/BildAtelier-Check" --self-test --skip-video --demo
"$TASK_CHECK_DIR/BildAtelier-Check" --performance-test --demo
rm -rf "$TASK_CHECK_DIR"
```

Stand 1.9.0: Universal-Build sowie 99 Funktionsprüfungen und neun Leistungsprüfungen auf Apple Silicon erfolgreich. Intel-Code wurde kompiliert, nicht auf Intel-Hardware ausgeführt.

Ausführliche Bedienung und Grenzen: [Anleitung](Anleitung.md), [Build-Hinweise](BITTE-ZUERST-LESEN.txt).
