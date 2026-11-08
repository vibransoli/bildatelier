import AppKit

enum SearchCacheChecks {
    static func run(_ parent: URL) throws -> Int {
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            if value { print("PASS \(message)") } else { failures += 1; print("FAIL \(message)") }
        }
        let fm = FileManager.default
        let root = parent.appendingPathComponent("SearchCache")
        let hidden = parent.appendingPathComponent("SearchCache-temporarily-moved")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: hidden); BrowserSearch.invalidate(root: root) }
        let first = root.appendingPathComponent("Bild000.jpg")
        try SelfTests.createImage(first, width: 64, height: 48, orientation: 1, palette: 0)
        for n in 1..<500 { try fm.copyItem(at: first, to: root.appendingPathComponent(String(format: "Bild%03d.jpg", n))) }
        func search(_ query: String) -> (items: [MediaItem], cached: Bool, complete: Bool) {
            var hits: [MediaItem] = [], cached = false, complete = false
            BrowserSearch.scan(root: root, query: query, operation: Operation(), onCacheHit: { cached = true }) { batch, _, _, done in
                hits += batch; complete = done
            }
            return (hits, cached, complete)
        }
        BrowserSearch.invalidate(root: root)
        var start = Date()
        let initial = search("NichtVorhanden")
        let cold = Date().timeIntervalSince(start)
        check(!initial.cached && initial.complete && initial.items.isEmpty, "Erste Suche baut vollständigen Index auch ohne Treffer auf")
        start = Date()
        let warm = search("Testmotiv")
        let hot = Date().timeIntervalSince(start)
        check(warm.cached && warm.complete && warm.items.count == 500, "Zweite Metadatensuche verwendet vollständigen RAM-Index")
        print(String(format: "MEASURE Suchindex 500 JPEG: erster Durchlauf %.1f ms; RAM-Suche %.1f ms", cold * 1000, hot * 1000))
        if let item = warm.items.first { item.metadata[.keywords] = "UI-Änderung" }
        check(search("Testmotiv").items.count == 500, "RAM-Snapshots sind unabhängig von Änderungen an UI-Objekten")
        try fm.moveItem(at: root, to: hidden)
        let offline = search("Bild000")
        check(offline.cached && offline.items.count == 1, "Warme Suche funktioniert ohne Zugriff auf den ursprünglichen Ordner")
        try fm.moveItem(at: hidden, to: root)
        try fm.removeItem(at: first)
        BrowserSearch.invalidate(root: root)
        let refreshed = search("Bild000")
        check(!refreshed.cached && refreshed.items.isEmpty, "Aktualisieren verwirft Index und erkennt gelöschte Dateien")
        BrowserSearch.invalidate(root: parent)
        check(!search("Bild001").cached, "Änderung am übergeordneten Ordner invalidiert Unterordner-Index")
        BrowserSearch.invalidate(root: root)
        let cancelled = Operation(); cancelled.cancel()
        BrowserSearch.scan(root: root, query: "jpg", operation: cancelled) { _, _, _, _ in }
        check(!search("Bild001").cached, "Abgebrochener Durchlauf wird nicht als vollständiger Index gespeichert")
        return failures
    }
}
