import AppKit

enum XMPChecks {
    static func packet(id: String = "Crop", enabled: Bool = true, compression: Int = 0, angle: Double = 0) throws -> Data {
        let adjustment: [String: Any] = ["enabled": enabled, "orientationIsRelative": false, "useHomography": true, "sliderMathVersion": 1, "points": [], "usePoints": false, "cropRect": [[78,428],[3313,4417]], "numeric": ["yOffset": 0, "zoomFactor": 1, "xOffset": 0, "horizontalDegrees": 0, "scale": 0, "straighten": angle, "horizStretch": 0, "verticalDegrees": 0]]
        let json = String(data: try JSONSerialization.data(withJSONObject: adjustment), encoding: .utf8)!
        let model: [String: Any] = ["formatVersion": 1, "currentVersionIndex": 0, "defaultOrientation": 8, "versions": [["masks": [], "adjDataArr": [["id": id, "json": json]]]]]
        let modelText = String(data: try JSONSerialization.data(withJSONObject: model), encoding: .utf8)!
        let plist: [String: Any] = ["format": "com.gentlemencoders.nitro", "version": 1, "compression": compression, "editModel": modelText, "originalImagePixelSize": "{3888, 5184}", "editedImagePixelSize": "{3313, 4417}"]
        let plistText = String(data: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), encoding: .utf8)!
        let escaped = plistText.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return ("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\" xmlns:n=\"http://com.gentlemencoders/xmp/nitro/1.0/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmp:Rating=\"4\"><n:EditModel>" + escaped + "</n:EditModel><dc:subject><rdf:Bag><rdf:li>Test A</rdf:li><rdf:li>Test, B</rdf:li></rdf:Bag></dc:subject><dc:description><rdf:Alt><rdf:li xml:lang=\"x-default\">XMP-Testbeschreibung</rdf:li></rdf:Alt></dc:description></rdf:Description></rdf:RDF></x:xmpmeta>").data(using: .utf8)!
    }
    static func run(_ folder: URL) throws -> Int {
        var failures = 0
        func check(_ condition: Bool, _ name: String) { print("\(condition ? "PASS" : "FAIL") \(name)"); if !condition { failures += 1 } }
        let data = try packet(), doc = XMPDocument.parse(data)
        check(doc.crop == CGRect(x: 78, y: 428, width: 3313, height: 4417) && doc.orientation == 8, "Nitro-XML/Plist/JSON und aktiver Beschnitt gelesen")
        check(doc.fields[.keywords] == "Test A\nTest, B" && doc.fields[.caption] == "XMP-Testbeschreibung", "XMP-Arrays und Sprachalternativen gelesen")
        check(doc.fields[.rating] == "4", "XMP-Bewertung als Attribut gelesen")
        check(XMPDocument.parse(try packet(compression: 1)).crop == nil, "Unbekannte Nitro-Kompression sicher übersprungen")
        check(XMPDocument.parse(try packet(angle: 1)).crop == nil, "Nicht unterstützte Geometrie wird nicht falsch zugeschnitten")
        check(XMPDocument.parse(try packet(enabled: false)).crop == nil, "Deaktivierte Nitro-Bearbeitung übersprungen")
        check(XMPDocument.parse(try packet(id: "Tone")).status.contains("noch nicht"), "Nicht unterstützte Bearbeitung ausgewiesen")
        check(!XMPDocument.parse(Data("<broken>".utf8)).notices.isEmpty, "Fehlerhaftes XMP ohne Absturz")
        let imageURL = folder.appendingPathComponent("NitroTest.jpg"), xmpURL = folder.appendingPathComponent("NitroTest_jpg.xmp")
        try SelfTests.createImage(imageURL, width: 5184, height: 3888, orientation: 8, palette: 0)
        try data.write(to: xmpURL)
        let scan = try DirectoryScan.read(folder, operation: BlockOperation())
        guard let item = scan.items.first(where: { $0.url == imageURL.standardizedFileURL }) else { check(false, "XMP-Testbild eingelesen"); return failures }
        check(item.sidecar?.url == xmpURL.standardizedFileURL, "Nitro-Dateiname _jpg.xmp zugeordnet")
        check(!scan.items.contains { $0.url.pathExtension == "xmp" }, "XMP nicht als Bild aufgeführt")
        check(MetadataReader.read(item)[.caption] == "XMP-Testbeschreibung", "Sidecar-Metadaten überschreiben eingebettete Angaben")
        let cropped = ImageRenderer.render(item, maxPixel: 512), original = ImageRenderer.render(item, maxPixel: 512, original: true)
        check(cropped?.pixelSize == CGSize(width: 3313, height: 4417) && cropped?.warning == nil, "Nitro-Beschnitt mit korrekter logischer Pixelgröße")
        check(original?.pixelSize == CGSize(width: 3888, height: 5184), "Originalvergleich ohne XMP-Beschnitt")
        check(abs((cropped?.image.size.width ?? 0) / (cropped?.image.size.height ?? 1) - 3313.0 / 4417.0) < 0.00001, "Beschnitt-Seitenverhältnis trotz Thumbnail-Rundung")
        let oldKey = item.cacheKey
        try (data + Data(" ".utf8)).write(to: xmpURL)
        let refreshed = try DirectoryScan.read(folder, operation: BlockOperation()).items.first { $0.id == item.id }!
        check(oldKey != refreshed.cacheKey, "XMP-Änderung invalidiert Vorschau- und Metadatencache")
        if let ref = item.sidecar { check(XMPReference.matching(URL(fileURLWithPath: "/Test/Foto.jpg"), in: ["Foto": ref], rawBasenames: ["Foto"]) == nil, "RAW-Sidecar wird nicht auf benachbartes JPEG angewandt") }
        return failures
    }
}
