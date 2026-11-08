# Automatische DMG und Dropbox

Jeder Push auf main startet den Workflow „DMG bauen und in Dropbox speichern“.
Lokale Änderungen müssen erst nach GitHub übertragen werden.
Manueller Start: Actions → Workflow → Run workflow.

Der Build erzeugt eine Universal-App für Intel und Apple Silicon ab macOS 13,
führt die Funktionstests aus und erstellt eine DMG mit Verknüpfung zu Programme.
Die DMG bleibt 30 Tage als GitHub-Artefakt verfügbar.
Dropbox-Ziel: /2 KI-Export/Bild-Atelier/
Dateinamen enthalten Version und Buildnummer; ältere Builds bleiben erhalten.

## Einmalig Dropbox verbinden

Die ChatGPT-Verbindung kann nicht an GitHub Actions weitergegeben werden.
In der Dropbox App Console https://www.dropbox.com/developers/apps eine
Scoped-Access-App mit Full Dropbox erstellen (für den bestehenden Zielordner).
Nur die benötigte Berechtigung files.content.write aktivieren.
App Key und App Secret aus den Einstellungen verwenden.

Über den OAuth-Autorisierungsablauf mit token_access_type=offline einen
Refresh Token erhalten:
https://dropbox.tech/developers/using-oauth-2-0-with-offline-access

Diese drei Werte ausschließlich als Repository-Secrets eintragen:
https://github.com/vibransoli/bildatelier/settings/secrets/actions

- DROPBOX_APP_KEY
- DROPBOX_APP_SECRET
- DROPBOX_REFRESH_TOKEN

Keine Zugangsdaten in Quellcode, Issues oder Chat veröffentlichen.
Anschließend den Workflow manuell starten. Ohne Secrets schlägt nur der
Dropbox-Schritt fehl; die fertige DMG bleibt unter dem Lauf herunterladbar.

## Signierung

Die App wird wie bisher ad hoc signiert. Sie ist nicht mit einer Apple
Developer ID signiert oder notarisiert; macOS kann beim ersten Öffnen
eine Freigabe in den Sicherheitseinstellungen verlangen.
