import AppKit

enum PerformanceChecks {
    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Atelier-Performance-\(UUID().uuidString)")
        var failures = 0
        func check(_ condition: Bool, _ name: String) { print("\(condition ? "PASS" : "FAIL") \(name)"); if !condition { failures += 1 } }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { if !CommandLine.arguments.contains("--keep-performance-fixtures") { try? fm.removeItem(at: root) } else { print("FIXTURES \(root.path)") } }
            let fixture = root.appendingPathComponent("source.jpg")
            try SelfTests.createImage(fixture, width: 1200, height: 800, orientation: 1, palette: 0)
            let large = root.appendingPathComponent("Gross"), small = root.appendingPathComponent("Klein")
            try fm.createDirectory(at: large, withIntermediateDirectories: true)
            try fm.createDirectory(at: small, withIntermediateDirectories: true)
            for i in 0..<2000 { try fm.copyItem(at: fixture, to: large.appendingPathComponent(String(format:"Foto_%04d.jpg", i))) }
            for i in 0..<1000 { try fm.createDirectory(at: large.appendingPathComponent(String(format:"Ordner_%04d", i)), withIntermediateDirectories: true) }
            try fm.copyItem(at: fixture, to: small.appendingPathComponent("Einzelbild.jpg"))
            let model = AppModel(restore: false)
            let record = FolderRecord(id:"performance",path:root.path,opened:Date())
            model.folders = [record]; model.activeFolder = record.id; model.currentURL = root
            var last = ProcessInfo.processInfo.systemUptime, maxGap = 0.0
            let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
                let now = ProcessInfo.processInfo.systemUptime; maxGap = max(maxGap, now-last); last = now
            }
            defer { timer.invalidate() }
            func measure(_ name: String, _ action: () -> Void) {
                maxGap = 0; last = ProcessInfo.processInfo.systemUptime; let start = last
                action()
                let deadline = Date().addingTimeInterval(30)
                while model.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
                let elapsed = ProcessInfo.processInfo.systemUptime-start
                RunLoop.current.run(until:Date().addingTimeInterval(0.05))
                print(String(format:"MEASURE %@: %.1f ms; main-loop max gap %.1f ms",name,elapsed*1000,maxGap*1000))
            }
            measure("Ordner 2000 JPEG + 1000 Unterordner", { model.navigate(to:large) })
            check(model.items.count == 3000, "Alle 3000 Einträge vorhanden")
            check(model.mediaItems.count == 2000, "2000 Medien ohne Unterordner im Vollbild")
            check(model.mediaItems.allSatisfy { !$0.metadataLoaded }, "Kein EXIF/IPTC-Lesen für unsichtbare Dateien")
            let first = model.mediaItems[0], revision = model.itemsRevision
            for _ in 0..<20 { model.requestMetadata(first) }
            let metadataDeadline = Date().addingTimeInterval(10)
            while !first.metadataLoaded && Date() < metadataDeadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            check(first.value(.camera) == "Atelier Camera" && model.mediaItems.filter(\.metadataLoaded).count == 1, "Nur angefordertes Foto erhält Metadaten")
            check(model.itemsRevision == revision, "Metadaten ändern nicht die gesamte Dateiliste")
            measure("Unveränderten Ordner aktualisieren", { model.refresh() })
            check(model.mediaItems.first === first && first.metadataLoaded, "Aktualisierung übernimmt unveränderte Objekte und Metadaten")
            let sortingStart = ProcessInfo.processInfo.systemUptime
            model.setSort(.camera, ascending: false)
            let sortDeadline = Date().addingTimeInterval(20)
            while (model.mediaItems.contains { !$0.metadataLoaded } || model.sorting) && Date() < sortDeadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            RunLoop.current.run(until:Date().addingTimeInterval(0.6))
            check(model.mediaItems.allSatisfy(\.metadataLoaded) && model.mediaItems.first?.url.lastPathComponent == "Foto_1999.jpg", "EXIF-Sortierung berücksichtigt auch nicht sichtbare Bilder")
            print(String(format:"MEASURE EXIF-Sortierung 2000 JPEG: %.1f ms", (ProcessInfo.processInfo.systemUptime-sortingStart)*1000))
            model.setSort(.name, ascending: true)
            measure("20 schnelle Wechsel, Ziel kleiner Ordner", {
                for _ in 0..<10 { model.navigate(to:large); model.navigate(to:small) }
            })
            check(model.items.count == 1 && model.items.first?.url.lastPathComponent == "Einzelbild.jpg", "Veraltete Scans überschreiben Ziel nicht")
            RunLoop.current.run(until:Date().addingTimeInterval(0.3))
            check(model.items.count == 1, "Auswahl bleibt nach verspäteten Rückmeldungen stabil")
        } catch { print("FAIL \(error)"); failures += 1 }
        exit(failures == 0 ? 0 : 1)
    }
}
