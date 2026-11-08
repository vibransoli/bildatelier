import AppKit

enum BrowserActionChecks {
    static func run(_ parent: URL) throws -> Int {
        var failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
        }
        let fm = FileManager.default
        let root = parent.appendingPathComponent("BrowserActionChecks")
        let nested = root.appendingPathComponent("Tief/NochTiefer")
        let target = root.appendingPathComponent("Ziel")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let image = nested.appendingPathComponent("Bären.jpg")
        try SelfTests.createImage(image, width: 60, height: 40, orientation: 1, palette: 0)
        let second = root.appendingPathComponent("Zweitbild.jpg")
        try fm.copyItem(at: image, to: second)
        let xmp = nested.appendingPathComponent("Bären_jpg.xmp")
        try """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:subject><rdf:Bag><rdf:li>Nordseeurlaub</rdf:li>Möwe</rdf:li></rdf:Bag></dc:subject></rdf:Description></rdf:RDF></x:xmpmeta>
        """.write(to: xmp, atomically: true, encoding: .utf8)
        var hits: [MediaItem] = [], total = 0, done = false
        BrowserSearch.scan(root: root, query: "BAREN nordseeurlaub", operation: Operation()) { batch, scanned, _, complete in
            hits += batch; total = scanned; done = complete
        }
        check(done && total == 2 && hits.count == 1 && hits.first?.url == image, "Rekursive Suche kombiniert Dateiname und XMP, unabhängig von Großschreibung/Umlauten")
        if let hit = hits.first {
            check(!BrowserSearch.matches(hit, terms: BrowserSearch.terms("Nordseeurlaub fehlt")), "Suchwörter sind UND-verknüpft")
        }
        let cancelled = Operation(); cancelled.cancel(); var called = false
        BrowserSearch.scan(root: root, query: "jpg", operation: cancelled) { _, _, _, _ in called = true }
        check(!called, "Abgebrochene Suche liefert keine Ergebnisse")
        let scan = try DirectoryScan.read(root, operation: Operation())
        let model = AppModel(restore: false)
        model.items = scan.items
        let selectable = model.displayItems
        if selectable.count >= 3 {
            model.select(selectable[0]); model.select(selectable[2], modifiers: .command)
            check(model.selectedIDs == Set([selectable[0].id, selectable[2].id]), "CMD-Auswahl ergänzt Dateien")
            model.select(selectable[0], modifiers: .command)
            check(model.selectedIDs == Set([selectable[2].id]), "CMD-Auswahl entfernt einzelne Datei")
            model.select(selectable[0]); model.select(selectable[2], modifiers: .shift)
            check(model.selectedIDs == Set(selectable[0...2].map(\.id)), "Umschalt-Auswahl markiert Bereich")
            model.prepareContext(selectable[1])
            check(model.selectedIDs.count == 3, "Kontextmenü erhält Mehrfachauswahl")
            model.items = [selectable[0]]
            check(model.selectedIDs == Set([selectable[0].id]), "Entfernte Dateien verschwinden aus der Auswahl")
        }
        let unit = try FileActions.units([image])[0]
        check(unit.sidecar == xmp, "Dateiaktionen finden Nitro-XMP")
        let copied = try FileActions.destination(for: unit, in: target)
        try FileActions.transfer(unit, to: copied, move: false, moveSidecar: false)
        check(fm.fileExists(atPath: image.path) && fm.fileExists(atPath: FileActions.companion(for: unit, target: copied)!.path), "Kopieren behält Original und überträgt XMP")
        let duplicate = try FileActions.destination(for: unit, in: target)
        check(duplicate != copied && duplicate.lastPathComponent.contains("Kopie"), "Namenskonflikte überschreiben keine Datei")
        let copiedUnit = try FileActions.units([copied])[0]
        let renamed = try FileActions.destination(for: copiedUnit, in: target, name: "Umbenannt.jpg")
        try FileActions.transfer(copiedUnit, to: renamed, move: true, moveSidecar: true)
        check(!fm.fileExists(atPath: copied.path) && fm.fileExists(atPath: FileActions.companion(for: copiedUnit, target: renamed)!.path), "Umbenennen verschiebt Bild und XMP")
        do {
            _ = try FileActions.destination(for: unit, in: target, name: "Umbenannt.jpg")
            check(false, "Umbenennen auf vorhandenen Namen verhindert")
        } catch { check(true, "Umbenennen auf vorhandenen Namen verhindert") }
        let directory = FileUnit(url: nested, sidecar: nil, sharedSidecar: false, directory: true)
        do {
            _ = try FileActions.destination(for: directory, in: nested.appendingPathComponent("Innen"))
            check(false, "Ordner darf nicht in sich selbst verschoben werden")
        } catch { check(true, "Ordner darf nicht in sich selbst verschoben werden") }
        let failingUnit = FileUnit(url: image, sidecar: root.appendingPathComponent("missing.xmp"), sharedSidecar: false, directory: false)
        let rollback = target.appendingPathComponent("Rollback.jpg")
        do { try FileActions.transfer(failingUnit, to: rollback, move: true, moveSidecar: true); check(false, "XMP-Fehler nimmt Bildverschiebung zurück") }
        catch { check(fm.fileExists(atPath: image.path) && !fm.fileExists(atPath: rollback.path), "XMP-Fehler nimmt Bildverschiebung zurück") }
        // Two RAW formats sharing one basename: an unselected owner retains XMP.
        let raw1 = root.appendingPathComponent("Shared.orf"), raw2 = root.appendingPathComponent("Shared.nef")
        try Data([0]).write(to: raw1); try Data([0]).write(to: raw2)
        try Data(contentsOf: xmp).write(to: root.appendingPathComponent("Shared.xmp"))
        let shared = try FileActions.units([raw1])[0].sharedSidecar
        check(shared, "Gemeinsames XMP bleibt bei nicht ausgewähltem Bild")
        let browser = AppModel(restore: false)
        let record = FolderRecord(id: UUID().uuidString, path: root.path, opened: Date())
        browser.folders = [record]; browser.activeFolder = record.id; browser.currentURL = root
        browser.searchQuery = "Nordseeurlaub"; browser.refresh()
        browser.searchQuery = "Zweitbild"; browser.refresh()
        let deadline = Date().addingTimeInterval(10)
        while browser.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        if browser.busy || browser.items.count != 1 { print("SEARCH DIAGNOSTIC busy=\(browser.busy) scanned=\(browser.searchScanned) skipped=\(browser.searchSkipped) hits=\(browser.items.map { $0.url.lastPathComponent })") }
        check(!browser.busy && browser.items.count == 1 && browser.items.first?.url == second, "Überholte Suche überschreibt neue Suchergebnisse nicht")
        if let hit = browser.items.first {
            browser.revealContainingFolder(hit)
            let deadline = Date().addingTimeInterval(10)
            while browser.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            check(!browser.searchActive && browser.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path && browser.selectedID == second.path, "Zum Ordner wechseln beendet Suche und markiert Treffer, auch im Such-Stammordner")
        }
        return failures
    }
}
