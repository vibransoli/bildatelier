import AppKit
import ImageIO

struct XMPReference {
    let url: URL
    let version: String
    init(url: URL, values: URLResourceValues) {
        self.url = url.standardizedFileURL
        version = self.url.path + "|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)"
    }
    static let rawExtensions: Set<String> = ["orf", "nef", "nrw", "arw", "cr2", "cr3", "raf", "rw2", "pef", "srw", "raw"]
    static func matching(_ image: URL, in references: [String: XMPReference], rawBasenames: Set<String> = []) -> XMPReference? {
        let stem = image.deletingPathExtension().lastPathComponent, ext = image.pathExtension.lowercased()
        if let specific = references[image.lastPathComponent] ?? references[stem + "_" + ext] { return specific }
        // Nitro's basename sidecar belongs to the RAW half of a RAW+JPEG pair.
        if rawBasenames.contains(stem) && !rawExtensions.contains(ext) { return nil }
        return references[stem]
    }
}

final class XMPDocument: NSObject {
    var fields: [MetaField: String] = [:]
    var crop: CGRect?
    var originalSize: CGSize?
    var orientation: Int?
    var notices: [String] = []
    var isNitro = false
    private static let cache: NSCache<NSString, XMPDocument> = {
        let c = NSCache<NSString, XMPDocument>(); c.countLimit = 2000; c.totalCostLimit = 16 * 1024 * 1024; return c
    }()
    static func read(_ reference: XMPReference) -> XMPDocument {
        if let cached = cache.object(forKey: reference.version as NSString) { return cached }
        let result: XMPDocument
        do {
            let handle = try FileHandle(forReadingFrom: reference.url); defer { try? handle.close() }
            result = parse(try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data())
        } catch { result = XMPDocument(); result.notices = ["XMP konnte nicht gelesen werden."] }
        cache.setObject(result, forKey: reference.version as NSString, cost: 512 + result.fields.values.reduce(0) { $0 + $1.utf8.count * 2 })
        return result
    }
    static func parse(_ data: Data) -> XMPDocument {
        let result = XMPDocument()
        let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        guard data.count <= 8 * 1024 * 1024, !xml.isEmpty,
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"), !xml.localizedCaseInsensitiveContains("<!ENTITY"),
              let metadata = CGImageMetadataCreateFromXMPData(data as CFData),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] else {
            result.notices = ["XMP ungültig, nicht unterstützt oder größer als 8 MiB."]; return result
        }
        let namespaces = ["http://purl.org/dc/elements/1.1/": "dc", "http://ns.adobe.com/xap/1.0/": "xmp", "http://ns.adobe.com/photoshop/1.0/": "ps", "http://ns.adobe.com/exif/1.0/aux/": "aux", "http://com.gentlemencoders/xmp/nitro/1.0/": "nitro"]
        var values: [String: Any] = [:]
        for tag in tags {
            guard let ns = CGImageMetadataTagCopyNamespace(tag) as String?, let name = CGImageMetadataTagCopyName(tag) as String?, let value = CGImageMetadataTagCopyValue(tag) else { continue }
            if let prefix = namespaces[ns] { values[prefix + ":" + name] = value }
            else if ns.contains("camera-raw-settings") || ns.contains("darktable") || ns.contains("rawtherapee") { result.notices.append("Entwicklungseinstellungen anderer Programme werden nicht angewendet.") }
        }
        func strings(_ value: Any) -> [String] {
            if CFGetTypeID(value as CFTypeRef) == CGImageMetadataTagGetTypeID() {
                return CGImageMetadataTagCopyValue(value as! CGImageMetadataTag).map(strings) ?? []
            }
            if let array = value as? [Any] {
                for member in array where CFGetTypeID(member as CFTypeRef) == CGImageMetadataTagGetTypeID() {
                    let tag = member as! CGImageMetadataTag
                    let qualifiers = CGImageMetadataTagCopyQualifiers(tag) as? [CGImageMetadataTag] ?? []
                    if qualifiers.contains(where: { (CGImageMetadataTagCopyName($0) as String?) == "lang" && (CGImageMetadataTagCopyValue($0) as? String) == "x-default" }) { return strings(tag) }
                }
                return array.flatMap(strings)
            }
            if let dict = value as? [String: Any] {
                if let preferred = dict["x-default"] { return strings(preferred) }
                return dict.keys.sorted().first.flatMap { dict[$0] }.map(strings) ?? []
            }
            return [String(describing: value)]
        }
        func assign(_ field: MetaField, _ key: String, separator: String = ", ") {
            if let value = values[key] { result.fields[field] = strings(value).joined(separator: separator) }
        }
        for (field, key) in [(MetaField.title,"dc:title"),(.caption,"dc:description"),(.creator,"dc:creator"),(.copyright,"dc:rights"),(.city,"ps:City"),(.region,"ps:State"),(.country,"ps:Country"),(.credit,"ps:Credit"),(.source,"ps:Source"),(.rating,"xmp:Rating"),(.colorLabel,"xmp:Label"),(.lens,"aux:Lens"),(.taken,"ps:DateCreated")] { assign(field, key) }
        assign(.keywords, "dc:subject", separator: "\n")
        if let flag = values["nitro:Flag"] { result.fields[.nitroFlag] = strings(flag).joined(separator: ", ") }
        if let model = values["nitro:EditModel"].map(strings)?.first { result.isNitro = true; result.parseNitro(model) }
        return result
    }
    private func parseNitro(_ text: String) {
        // A plist is data, never an NSKeyedUnarchiver/object graph. Nitro embeds JSON in it.
        guard let data = text.data(using: .utf8),
              let p = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              p["format"] as? String == "com.gentlemencoders.nitro", (p["version"] as? Int) == 1, (p["compression"] as? Int) == 0,
              let json = p["editModel"] as? String, let bytes = json.data(using: .utf8),
              let model = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], (model["formatVersion"] as? Int) == 1,
              let versions = model["versions"] as? [[String: Any]], let index = model["currentVersionIndex"] as? Int, versions.indices.contains(index) else {
            notices.append("Nitro-EditModel: Format oder Kompression noch nicht unterstützt."); return
        }
        if let size = p["originalImagePixelSize"] as? String {
            let n = size.components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted).compactMap(Double.init)
            if n.count == 2, n.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100000 }) { originalSize = CGSize(width: n[0], height: n[1]) }
        }
        orientation = model["defaultOrientation"] as? Int
        let version = versions[index]
        if let masks = version["masks"] as? [Any], !masks.isEmpty { notices.append("Nitro-Masken werden nicht angewendet.") }
        guard let adjustments = version["adjDataArr"] as? [[String: Any]] else { notices.append("Nitro-Bearbeitungsliste fehlt."); return }
        for adjustment in adjustments {
            let name = adjustment["id"] as? String ?? "Unbekannt"
            guard let json = adjustment["json"] as? String, let bytes = json.data(using: .utf8), let settings = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { notices.append("Nitro-\(name): nicht lesbar."); continue }
            if settings["enabled"] as? Bool == false { continue }
            guard name == "Crop" else { notices.append("Nitro-\(name) wird noch nicht angewendet."); continue }
            let numeric = settings["numeric"] as? [String: Any] ?? [:]
            let neutral: [String: Double] = ["yOffset": 0, "zoomFactor": 1, "xOffset": 0, "horizontalDegrees": 0, "scale": 0, "straighten": 0, "horizStretch": 0, "verticalDegrees": 0]
            let simple = numeric.allSatisfy { key, value in
                guard let expected = neutral[key], let n = value as? NSNumber else { return false }
                return n.doubleValue.isFinite && abs(n.doubleValue - expected) < 0.000001
            }
            guard simple, settings["orientationIsRelative"] as? Bool != true, settings["usePoints"] as? Bool != true,
                  (settings["points"] as? [Any] ?? []).isEmpty, (settings["sliderMathVersion"] as? Int ?? 1) == 1,
                  let rect = settings["cropRect"] as? [[Double]], rect.count == 2, rect.allSatisfy({ $0.count == 2 }),
                  rect.flatMap({ $0 }).allSatisfy({ $0.isFinite }), let size = originalSize,
                  rect[0][0] >= 0, rect[0][1] >= 0, rect[1][0] > 0, rect[1][1] > 0,
                  rect[0][0] + rect[1][0] <= size.width, rect[0][1] + rect[1][1] <= size.height else {
                notices.append("Nitro-Beschnitt mit Drehung/Perspektive oder unbekannten Werten noch nicht unterstützt."); continue
            }
            crop = CGRect(x: rect[0][0], y: rect[0][1], width: rect[1][0], height: rect[1][1])
        }
    }
    var status: String {
        let first = crop == nil ? "XMP-Metadaten übernommen" : "Nitro-Beschnitt (experimentell); O im Vollbild zeigt das Original"
        return ([first] + Array(Set(notices)).sorted()).joined(separator: ". ")
    }
}

struct RenderedPicture {
    let image: NSImage
    let pixelSize: CGSize
    let warning: String?
}

enum ImageRenderer {
    static func render(_ item: MediaItem, maxPixel: Int, original: Bool = false) -> RenderedPicture? {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let document = original ? nil : item.sidecar.map(XMPDocument.read)
        var decodeLimit = maxPixel
        if let crop = document?.crop, let full = document?.originalSize {
            let ratio = max(full.width, full.height) / max(crop.width, crop.height)
            decodeLimit = Int(min(max(full.width, full.height), ceil(Double(maxPixel) * ratio)))
        }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: decodeLimit, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let orientation = (p[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        let w = (p[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? Double(cg.width)
        let h = (p[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? Double(cg.height)
        let size = (5...8).contains(orientation) ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        let base = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        guard let document, let crop = document.crop else { return RenderedPicture(image: base, pixelSize: size, warning: nil) }
        guard let expected = document.originalSize, abs(size.width - expected.width) < 1, abs(size.height - expected.height) < 1,
              document.orientation == nil || document.orientation == orientation else {
            return RenderedPicture(image: base, pixelSize: size, warning: "Nitro-Beschnitt nicht angewendet: Ausgangsgröße oder Ausrichtung weicht ab.")
        }
        // Experimental interpretation of Nitro CGRect: oriented Core Image space (bottom-left).
        // CGImage cropping uses top-left coordinates, so flip the y coordinate once.
        let rect = CGRect(x: crop.minX / size.width * Double(cg.width), y: (size.height - crop.maxY) / size.height * Double(cg.height), width: crop.width / size.width * Double(cg.width), height: crop.height / size.height * Double(cg.height))
        guard let cut = cg.cropping(to: rect.integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))) else {
            return RenderedPicture(image: base, pixelSize: size, warning: "Nitro-Beschnitt konnte nicht dargestellt werden.")
        }
        // Keep the intended aspect ratio despite integer thumbnail pixel rounding.
        return RenderedPicture(image: NSImage(cgImage: cut, size: CGSize(width: Double(cut.width), height: Double(cut.width) * crop.height / crop.width)), pixelSize: crop.size, warning: nil)
    }
}
