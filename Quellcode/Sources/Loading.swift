import AppKit

// File enumeration and natural sorting never run on the UI thread.
struct DirectoryScan {
    let items: [MediaItem]
    let directories: [URL]
    static let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
    static func read(_ url: URL, operation: Operation, directoriesOnly: Bool = false) throws -> DirectoryScan {
        var failure: Error?
        let requested = directoriesOnly ? Set<URLResourceKey>([.isDirectoryKey, .isPackageKey]) : keys
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(requested), options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants], errorHandler: { _, error in failure = error; return false }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var items: [MediaItem] = [], directories: [URL] = []
        var types: [String: Bool?] = [:]
        var sidecars: [String: XMPReference] = [:]
        for case let file as URL in enumerator {
            if operation.isCancelled { return DirectoryScan(items: [], directories: []) }
            autoreleasepool {
                guard let values = try? file.resourceValues(forKeys: requested) else { return }
                if values.isDirectory == true && values.isPackage != true {
                    directories.append(file.standardizedFileURL)
                    if !directoriesOnly {
                        let item = MediaItem(url: file, values: values, video: false, isDirectory: true)
                        item.metadata[.kind] = "Ordner"; item.metadata[.size] = ""; item.metadataLoaded = true; items.append(item)
                    }
                } else if !directoriesOnly && values.isRegularFile == true {
                    let ext = file.pathExtension.lowercased()
                    if ext == "xmp" {
                        let key = file.deletingPathExtension().lastPathComponent
                        if sidecars[key] == nil || file.pathExtension == "xmp" { sidecars[key] = XMPReference(url: file, values: values) }
                        return
                    }
                    let video: Bool?
                    if let cached = types[ext] { video = cached } else { video = MediaItem.classify(file); types[ext] = .some(video) }
                    if let video { items.append(MediaItem(url: file, values: values, video: video)) }
                }
            }
        }
        if let failure { throw failure }
        if !directoriesOnly && !sidecars.isEmpty {
            let rawNames = Set(items.filter { XMPReference.rawExtensions.contains($0.url.pathExtension.lowercased()) }.map { $0.url.deletingPathExtension().lastPathComponent })
            for item in items where !item.isDirectory { item.sidecar = XMPReference.matching(item.url, in: sidecars, rawBasenames: rawNames) }
        }
        directories.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return DirectoryScan(items: items, directories: directories)
    }
}

struct ItemSortKey {
    let item: MediaItem
    let text: String
    init(_ item: MediaItem, field: MetaField) { self.item = item; text = item.value(field) }
    static func sorted(_ keys: [ItemSortKey], field: MetaField, ascending: Bool) -> [MediaItem] {
        keys.sorted { left, right in
            let a = left.item, b = right.item
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let comparison: ComparisonResult
            if field == .size { comparison = a.bytes == b.bytes ? .orderedSame : (a.bytes < b.bytes ? .orderedAscending : .orderedDescending) }
            else if field == .modified { comparison = a.modified.compare(b.modified) }
            else { comparison = left.text.localizedStandardCompare(right.text) }
            let result = comparison == .orderedSame ? a.id.localizedStandardCompare(b.id) : comparison
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }.map(\.item)
    }
}

final class MetadataValue: NSObject {
    let fields: [MetaField: String]
    init(_ fields: [MetaField: String]) { self.fields = fields }
}

final class MetadataUpdates: ObservableObject {
    @Published var revision = 0
    private var scheduled = false
    func changed() {
        guard !scheduled else { return }; scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }; self.scheduled = false; self.revision += 1
        }
    }
}

extension MetaField {
    var needsMetadata: Bool { ![.name, .kind, .size, .modified, .created].contains(self) }
}
