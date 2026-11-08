import AppKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

enum SelfTests {
    static func run() {
        var failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
        }
        let args = CommandLine.arguments
        let keepIndex = args.firstIndex(of: "--fixtures")
        let folder = (keepIndex.flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil } ?? FileManager.default.temporaryDirectory.appendingPathComponent("BildAtelier-Tests-\(UUID().uuidString)")).resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { if keepIndex == nil { try? FileManager.default.removeItem(at: folder) } }
            let jpg = folder.appendingPathComponent("01_Kueste.jpg")
            try createImage(jpg, width: 1200, height: 800, orientation: 1, palette: 0)
            let rotated = folder.appendingPathComponent("02_Hochformat.jpg")
            try createImage(rotated, width: 1000, height: 600, orientation: 6, palette: 1)
            for index in 3...8 { try createImage(folder.appendingPathComponent(String(format: "%02d_Studie.jpg", index)), width: index % 2 == 0 ? 900 : 1400, height: 900, orientation: 1, palette: index) }
            try "not an image".write(to: folder.appendingPathComponent("Nicht_anzeigen.txt"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Unterordner"), withIntermediateDirectories: true)
            check(MediaItem.classify(jpg) == false, "JPEG als Bild erkannt")
            check(MediaItem.classify(folder.appendingPathComponent("Clip.MOV")) == true, "MOV als Video erkannt")
            check(MediaItem.classify(folder.appendingPathComponent("test.HEIC")) == false, "HEIC als Bild erkannt")
            check(MediaItem.classify(folder.appendingPathComponent("test.pdf")) == nil, "PDF ausgeschlossen")
            check(MediaItem.classify(folder.appendingPathComponent("test.txt")) == nil, "Text ausgeschlossen")
            let metadata = MetadataReader.read(jpg, video: false)
            check(metadata[.dimensions] == "1200 × 800", "Bildabmessungen")
            check(metadata[.camera] == "Atelier Camera", "Kamera aus TIFF/EXIF")
            check(metadata[.iso] == "200", "ISO aus EXIF")
            check(metadata[.shutter] == "1/250 s", "Belichtungszeit formatiert")
            check(metadata[.title] == "Licht und Landschaft", "IPTC-Titel")
            check(metadata[.creator] == "Bild-Atelier", "IPTC-Urheber")
            check(metadata[.keywords]?.contains("Testmotiv") == true, "IPTC-Stichwörter")
            check(metadata[.caption] == "Synthetisches Testbild für die App-Prüfung.", "IPTC-Beschreibung")
            let rotatedMeta = MetadataReader.read(rotated, video: false)
            check(rotatedMeta[.dimensions] == "600 × 1000", "EXIF-Orientierung in Abmessungen")
            let thumb = ThumbnailStore.decode(rotated, maxPixel: 400)
            check(thumb?.size == CGSize(width: 240, height: 400), "Gedrehtes Thumbnail proportional")
            let values = try jpg.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let one = MediaItem(url: jpg, values: values, video: false)
            let two = MediaItem(url: rotated, values: values, video: false)
            let state = ViewerState(items: [one, two], index: 0)
            state.showStrip(); state.move(1)
            check(state.index == 0 && state.candidate == 1 && state.filmstrip, "Vorschaunavigation ändert Vollbild nicht")
            state.confirm(); check(state.index == 1 && !state.filmstrip, "Pfeil unten übernimmt Auswahl")
            state.move(1); check(state.index == 1, "Navigation stoppt am Ende")
            state.move(-1); check(state.index == 0, "Pfeil links wechselt Datei")
            state.move(-1); check(state.index == 0, "Navigation stoppt am Anfang")
            let canvas = ImageCanvas(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
            canvas.pixelSize = CGSize(width: 1200, height: 800)
            check(abs(canvas.fitScale - 1000.0 / 1200.0) < 0.001, "Vollbild-Seitenverhältnis")
            canvas.setZoom(2); check(canvas.zoom == 2, "Zoom vergrößert")
            canvas.reset(); check(canvas.zoom == 1 && canvas.offset == .zero, "Einpassen setzt Zoom und Verschiebung zurück")
            canvas.setZoom(3); canvas.pan(x: 80, y: -60)
            check(canvas.zoom == 3 && canvas.offset == CGPoint(x: 80, y: -60), "Verschieben verändert Ausschnitt ohne Zoom")
            canvas.pan(x: 100000, y: -100000)
            check(abs(canvas.offset.x) <= 1000.001 && abs(canvas.offset.y) <= 600.001, "Verschieben bleibt an den Bildgrenzen")
            canvas.reset()
            let root = PresentationRoot(canvas: canvas)
            root.frame = NSRect(x: 0, y: 0, width: 1000, height: 800); root.reservedTop = 38
            check(canvas.frame == NSRect(x: 0, y: 0, width: 1000, height: 762), "Notch-Bereich bleibt außerhalb der Bildfläche")
            root.setFrameSize(NSSize(width: 1200, height: 900))
            check(canvas.frame.height == 862, "Schwarzer oberer Rand bleibt beim Größenwechsel erhalten")
            let nested = folder.appendingPathComponent("Unterordner/Weitere")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nested.deletingLastPathComponent().appendingPathComponent("AAA"), withIntermediateDirectories: true)
            try createImage(nested.appendingPathComponent("Innen.jpg"), width: 600, height: 400, orientation: 1, palette: 2)
            let model = AppModel(restore: false)
            let record = FolderRecord(id: "test", path: folder.path, opened: Date())
            model.folders = [record]; model.activeFolder = record.id; model.currentURL = folder
            func awaitScan() { let deadline = Date().addingTimeInterval(10); while model.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) } }
            model.refresh(); awaitScan()
            check(model.items.filter { $0.isDirectory }.count == 1, "Browser zeigt Unterordner")
            check(model.mediaItems.count == 8 && !model.mediaItems.contains { $0.isDirectory }, "Vollbild enthält ausschließlich Medien")
            check(model.items.first?.isDirectory == true, "Ordner stehen vor Bildern")
            model.navigate(to: nested); awaitScan()
            check(model.items.first?.url.lastPathComponent == "Innen.jpg", "Navigation in verschachtelten Ordner")
            check(model.expandedPaths.contains(folder.path) && model.expandedPaths.contains(nested.deletingLastPathComponent().path), "Seitenleiste klappt Vorfahren auf")
            model.goBack(); awaitScan()
            check(model.currentURL?.path == folder.path, "Zurück zum vorherigen Ordner")
            model.navigate(to: nested); awaitScan(); model.goUp(); awaitScan()
            check(model.currentURL?.lastPathComponent == "Unterordner" && model.selected?.url.lastPathComponent == "Weitere", "Übergeordneter Ordner markiert verlassenen Unterordner")
            var openedID: String?
            model.openViewer = { openedID = $0.id }
            model.pendingOpenURL = jpg.standardizedFileURL
            model.navigate(to: folder); awaitScan()
            check(openedID == jpg.standardizedFileURL.path && model.selectedID == openedID, "Finder-Datei wird nach Ordnerladen geöffnet und markiert")
            check(model.pendingOpenURL == nil, "Finder-Öffnung wird nur einmal ausgeführt")
            var selectionEvents = 0
            model.selectionChanged = { selectionEvents += 1 }
            model.selectedID = two.id; model.selectedID = two.id
            check(selectionEvents == 1, "Live-Auswahl meldet nur tatsächliche Änderungen")
            let thumbs = ThumbnailStore()
            var cancelledCalls = 0, callbacks = 0
            var thumbnailA: NSImage?, thumbnailB: NSImage?
            let cancelled = thumbs.load(one, maxPixel: 120) { _ in cancelledCalls += 1 }
            let ticketA = thumbs.load(one, maxPixel: 120) { image in thumbnailA = image; callbacks += 1 }
            let ticketB = thumbs.load(one, maxPixel: 120) { image in thumbnailB = image; callbacks += 1 }
            cancelled?.cancel()
            let thumbnailDeadline = Date().addingTimeInterval(5)
            while callbacks < 2 && Date() < thumbnailDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            check(callbacks == 2 && cancelledCalls == 0, "Thumbnail-Abbruch beeinträchtigt andere Abnehmer nicht")
            check(thumbnailA != nil && thumbnailA === thumbnailB, "Gleichzeitige Thumbnail-Anfragen teilen ein Ergebnis")
            check(max(thumbnailA?.size.width ?? 999, thumbnailA?.size.height ?? 999) <= 256, "Kleine Vorschauen werden in passender Größe dekodiert")
            ticketA?.cancel(); ticketB?.cancel()
            if !args.contains("--skip-video") {
                let movie = folder.appendingPathComponent("09_Video.mp4")
                try createMovie(movie)
                let vm = MetadataReader.read(movie, video: true)
                check(vm[.dimensions] == "640 × 360", "Videoabmessungen")
                check(vm[.duration] == "0:02", "Videodauer")
            } else { print("SKIP Video-Encoder: separater UI-Prüflauf erforderlich") }
            one.metadata = [.taken: "2026:10:22 12:00:00", .camera: "A", .lens: "35 mm", .keywords: "Natur\nOrt, Name"]
            one.metadataLoaded = true
            two.metadata = [.taken: "2026-10-22T18:00:00Z", .camera: "B", .keywords: "Natur"]
            two.metadataLoaded = true
            check(FacetValue.values(one, field: .taken) == FacetValue.values(two, field: .taken), "Aufnahmetag gruppiert EXIF und ISO ohne Uhrzeit")
            check(FacetValue.values(one, field: .keywords) == ["Natur", "Ort, Name"], "Einzelne Stichwörter erhalten eingebettete Kommas")
            check(!FacetValue.matches(one, selections: [.camera: ["A", "B"]]), "Alle Werte einer Spalte müssen erfüllt sein")
            check(FacetValue.matches(one, selections: [.keywords: ["Natur", "Ort, Name"]]), "Bild mit beiden Stichwörtern erfüllt UND")
            check(!FacetValue.matches(two, selections: [.keywords: ["Natur", "Ort, Name"]]), "Bild mit nur einem Stichwort erfüllt UND nicht")
            check(!FacetValue.matches(two, selections: [.camera: ["A", "B"], .lens: ["35 mm"]]), "Filterspalten werden gemeinsam angewandt")
            check(FacetValue.matches(two, selections: [.lens: [FacetValue.missing]]), "Fehlende Metadaten separat filterbar")
            let scopedKeywords = FacetValue.options([one, two], field: .keywords, selections: [.camera: ["B"]])
            check(scopedKeywords.map(\.id) == ["Natur"] && scopedKeywords.first?.count == 1, "Kamerafilter beschränkt Stichwortoptionen und Trefferzahlen")
            check(FacetValue.options([one, two], field: .camera, selections: [.keywords: ["Natur", "Ort, Name"]]).map(\.id) == ["A"], "Stichwort-UND beschränkt Kameraoptionen")
            check(FacetValue.options([one, two], field: .camera, selections: [.camera: ["A"]]).count == 2, "Eigene Spaltenauswahl lässt Alternativen verfügbar")
            check(FacetValue.options([one, two], field: .lens, selections: [.camera: ["Unbekannt"]]).isEmpty, "Kein Treffer ergibt keine Optionen in anderen Spalten")
            check(FacetValue.options([one, two], field: .keywords, selections: [:]).count == 2, "Zurücksetzen stellt alle Optionen wieder her")
            let filteredModel = AppModel(restore: false)
            filteredModel.items = [one, two]
            filteredModel.selectedID = two.id
            filteredModel.facetSelections = [.camera: ["A"]]
            check(filteredModel.displayItems.map(\.id) == [one.id] && filteredModel.items.count == 2, "Filter erhält ursprünglichen Ordnerinhalt")
            check(filteredModel.selectedID == nil, "Ausgefilterte Auswahl wird aufgehoben")
            filteredModel.facetSelections = [.camera: ["Unbekannt"]]
            check(filteredModel.displayItems.isEmpty, "Filter ohne Treffer")
            filteredModel.currentURL = folder
            check(filteredModel.facetSelections.isEmpty && filteredModel.displayItems.count == 2, "Ordnerwechsel setzt Filter zurück")
            let deep = folder.appendingPathComponent("Unterordner/Tiefer/Suchziel")
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            let searchRoot = FolderRecord(id: "search-test", path: folder.path, bookmark: nil, pinned: true, opened: Date())
            let search = PinnedSearch(); search.query = "Suchziel"; search.search([searchRoot])
            let deadline = Date().addingTimeInterval(5)
            while search.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            check(search.hits.map { $0.url.standardizedFileURL.path } == [deep.standardizedFileURL.path], "Angepinnt-Suche findet nicht aufgeklappte Unterordner")
            search.query = "Suchziel"; search.search([searchRoot]); search.query = "KeinTreffer"; search.search([searchRoot])
            let deadline2 = Date().addingTimeInterval(5)
            while search.busy && Date() < deadline2 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            check(search.hits.isEmpty, "Überholte Ordnersuche wird verworfen")
            failures += try XMPChecks.run(folder)
            failures += try BrowserActionChecks.run(folder)
            failures += try SearchCacheChecks.run(folder)
            print("\(failures == 0 ? "SUCCESS" : "FAILURE"): \(failures) Fehler")
        } catch { failures += 1; print("FAIL \(error)") }
        exit(failures == 0 ? 0 : 1)
    }
    static func createImage(_ url: URL, width: Int, height: Int, orientation: Int, palette: Int) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors: [[CGFloat]] = [[0.16,0.45,0.53,1],[0.66,0.37,0.23,1],[0.30,0.42,0.30,1],[0.42,0.38,0.58,1],[0.78,0.61,0.34,1],[0.22,0.33,0.52,1],[0.57,0.33,0.40,1],[0.35,0.48,0.46,1],[0.72,0.52,0.37,1]]
        let base = colors[palette % colors.count]
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(colorSpace: space, components: base)!, CGColor(colorSpace: space, components: [0.92,0.88,0.78,1])!] as CFArray, locations: [0,1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        context.setFillColor(CGColor(red: 0.98, green: 0.89, blue: 0.65, alpha: 0.85)); context.fillEllipse(in: CGRect(x: CGFloat(width) * 0.62, y: CGFloat(height) * 0.57, width: CGFloat(height) * 0.24, height: CGFloat(height) * 0.24))
        for i in 0..<4 {
            let y = CGFloat(height) * (0.11 + Double(i) * 0.09)
            context.setFillColor(CGColor(red: base[0] * 0.6, green: base[1] * 0.6, blue: base[2] * 0.6, alpha: 0.25))
            context.beginPath(); context.move(to: CGPoint(x:0,y:0)); context.addLine(to:CGPoint(x:0,y:y)); context.addCurve(to: CGPoint(x:CGFloat(width),y:y * 1.3), control1: CGPoint(x:CGFloat(width)*0.3,y:y*2), control2: CGPoint(x:CGFloat(width)*0.7,y:y*0.4)); context.addLine(to:CGPoint(x:width,y:0)); context.closePath(); context.fillPath()
        }
        guard let image = context.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw NSError(domain:"Fixture",code:1) }
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake:"Atelier",kCGImagePropertyTIFFModel:"Atelier Camera"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal:"2026:10:22 09:41:00",kCGImagePropertyExifFNumber:2.8,kCGImagePropertyExifExposureTime:0.004,kCGImagePropertyExifISOSpeedRatings:[200],kCGImagePropertyExifFocalLength:50,kCGImagePropertyExifLensModel:"50 mm ƒ/1.8"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCObjectName:"Licht und Landschaft",kCGImagePropertyIPTCByline:["Bild-Atelier"],kCGImagePropertyIPTCKeywords:["Testmotiv","Landschaft"],kCGImagePropertyIPTCCaptionAbstract:"Synthetisches Testbild für die App-Prüfung.",kCGImagePropertyIPTCCopyrightNotice:"Bild-Atelier Testdaten",kCGImagePropertyIPTCCity:"Bochum"]]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        if !CGImageDestinationFinalize(dest) { throw NSError(domain:"Fixture",code:2) }
    }
    static func createMovie(_ url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,AVVideoWidthKey:640,AVVideoHeightKey:360])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:640,kCVPixelBufferHeightKey as String:360,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<48 {
            var pixel: CVPixelBuffer?; CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_32ARGB, nil, &pixel)
            guard let pixel else { continue }; CVPixelBufferLockBaseAddress(pixel, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.setFillColor(CGColor(red:0.10,green:0.19,blue:0.25,alpha:1)); context.fill(CGRect(x:0,y:0,width:640,height:360))
            context.setFillColor(CGColor(red:0.9,green:0.7,blue:0.4,alpha:1)); context.fillEllipse(in:CGRect(x:50+i*9,y:135,width:90,height:90)); CVPixelBufferUnlockBaseAddress(pixel, [])
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(i), timescale: 24)) else { throw writer.error ?? NSError(domain:"FixtureVideo",code:1) }
        }
        writer.endSession(atSourceTime: CMTime(value: 2,timescale:1)); input.markAsFinished()
        let done = DispatchSemaphore(value:0); writer.finishWriting { done.signal() }; _ = done.wait(timeout: .now()+10)
        if writer.status != .completed { throw writer.error ?? NSError(domain:"FixtureVideo",code:2) }
    }
}
