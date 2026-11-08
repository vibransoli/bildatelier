import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import AVFoundation

enum MetaField: String, CaseIterable, Codable, Identifiable {
    case name, kind, size, dimensions, modified, created, duration
    case taken, camera, lens, aperture, shutter, iso, focalLength, exposureBias, flash, colorSpace, dpi, gps
    case title, caption, keywords, creator, copyright, city, region, country, credit, source
    case rating, colorLabel, nitroFlag, xmpStatus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rating: return "Bewertung"
        case .colorLabel: return "Farbmarkierung"
        case .nitroFlag: return "Nitro-Markierung"
        case .xmpStatus: return "XMP-Status"
        case .name: return "Dateiname"
        case .kind: return "Dateityp"
        case .size: return "Dateigröße"
        case .dimensions: return "Abmessungen"
        case .modified: return "Geändert"
        case .created: return "Erstellt"
        case .duration: return "Dauer"
        case .taken: return "Aufgenommen"
        case .camera: return "Kamera"
        case .lens: return "Objektiv"
        case .aperture: return "Blende"
        case .shutter: return "Belichtungszeit"
        case .iso: return "ISO"
        case .focalLength: return "Brennweite"
        case .exposureBias: return "Belichtungskorrektur"
        case .flash: return "Blitz"
        case .colorSpace: return "Farbprofil"
        case .dpi: return "Auflösung (dpi)"
        case .gps: return "GPS"
        case .title: return "Titel"
        case .caption: return "Beschreibung"
        case .keywords: return "Stichwörter"
        case .creator: return "Urheber"
        case .copyright: return "Copyright"
        case .city: return "Stadt"
        case .region: return "Region"
        case .country: return "Land"
        case .credit: return "Credit"
        case .source: return "Quelle"
        }
    }
    var group: String {
        switch self {
        case .rating, .colorLabel, .nitroFlag, .xmpStatus: return "XMP"
        case .name, .kind, .size, .dimensions, .modified, .created, .duration: return "Datei"
        case .taken, .camera, .lens, .aperture, .shutter, .iso, .focalLength, .exposureBias, .flash, .colorSpace, .dpi, .gps: return "EXIF"
        default: return "IPTC"
        }
    }
}

struct FolderRecord: Identifiable, Codable {
    var id: String
    var path: String
    var bookmark: Data?
    var pinned = false
    var group: String? = nil
    var opened: Date
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent.isEmpty ? path : url.lastPathComponent }
}

final class MediaItem: ObservableObject, Identifiable {
    let id: String
    let url: URL
    let video: Bool
    let isDirectory: Bool
    let bytes: Int64
    let modified: Date
    @Published var metadata: [MetaField: String]
    var sidecar: XMPReference?
    @Published var renderWarning: String?
    @Published var metadataLoaded = false
    init(url: URL, values: URLResourceValues, video: Bool, isDirectory: Bool = false) {
        self.isDirectory = isDirectory
        self.url = url.standardizedFileURL; self.id = self.url.path; self.video = video
        bytes = Int64(values.fileSize ?? 0); modified = values.contentModificationDate ?? .distantPast
        metadata = [.name: url.lastPathComponent, .kind: url.pathExtension.uppercased(),
                    .size: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file),
                    .modified: Self.formatDate(modified), .created: values.creationDate.map(Self.formatDate) ?? ""]
    }
    init(cachedURL: URL, bytes: Int64, modified: Date, video: Bool, metadata: [MetaField: String], sidecar: XMPReference?) {
        url = cachedURL; id = cachedURL.path; self.bytes = bytes; self.modified = modified
        self.video = video; isDirectory = false; self.metadata = metadata
        self.sidecar = sidecar; metadataLoaded = true
    }
    static func formatDate(_ date: Date) -> String {
        let key = "BildAtelier.DateFormatter"
        let f: DateFormatter
        if let existing = Thread.current.threadDictionary[key] as? DateFormatter { f = existing }
        else { f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateStyle = .medium; f.timeStyle = .short; Thread.current.threadDictionary[key] = f }
        return f.string(from: date)
    }
    func value(_ field: MetaField) -> String { metadata[field].flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: "\n", with: ", ") } ?? "—" }
    var cacheKey: String { id + "-\(modified.timeIntervalSince1970)-\(bytes)|" + (sidecar?.version ?? "") }
    static func classify(_ url: URL) -> Bool? {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .movie) || type.conforms(to: .video) { return true }
            if type.conforms(to: .image) { return false }
        }
        // Common extensions remain usable when LaunchServices has no registered type.
        let ext = url.pathExtension.lowercased()
        if ["jpg","jpeg","jpe","png","tif","tiff","heic","heif","gif","bmp","webp","avif","dng","cr2","cr3","nef","nrw","arw","orf","rw2","raf","pef","srw","psd","jp2","jxl","exr","ico"].contains(ext) { return false }
        if ["mov","mp4","m4v","avi","mpg","mpeg","m2v","mts","m2ts","3gp","3g2","mkv","webm"].contains(ext) { return true }
        return nil
    }
}

final class Preferences: ObservableObject {
    static let defaults: UserDefaults = CommandLine.arguments.contains("--demo") ? UserDefaults(suiteName: "eu.mitgmbh.bildatelier.demo")! : .standard
    @Published var thumbnailSize: Double { didSet { Self.defaults.set(thumbnailSize, forKey: "thumbSize") } }
    @Published var showText: Bool { didSet { Self.defaults.set(showText, forKey: "showText") } }
    @Published var listMode: Bool { didSet { Self.defaults.set(listMode, forKey: "listMode") } }
    @Published var lines: [String] { didSet { Self.defaults.set(Array(lines.prefix(4)), forKey: "thumbLines") } }
    @Published var columns: [MetaField] { didSet { Self.defaults.set(columns.map(\.rawValue), forKey: "columns") } }
    init() {
        let d = Self.defaults
        thumbnailSize = d.object(forKey: "thumbSize") == nil ? 210 : min(420, max(120, d.double(forKey: "thumbSize")))
        showText = d.object(forKey: "showText") == nil ? true : d.bool(forKey: "showText")
        listMode = d.bool(forKey: "listMode")
        var savedLines = Array((d.stringArray(forKey: "thumbLines") ?? ["name", "taken", "camera", "title"]).prefix(4))
        while savedLines.count < 4 { savedLines.append("") }
        lines = savedLines
        columns = (d.stringArray(forKey: "columns") ?? ["name", "dimensions", "taken", "camera", "size"]).compactMap(MetaField.init)
        if columns.isEmpty { columns = [.name] }
    }
    func toggle(_ field: MetaField) {
        if columns.contains(field) { if columns.count > 1 { columns.removeAll { $0 == field } } }
        else { columns.append(field) }
    }
}

final class AppModel: ObservableObject {
    @Published var folders: [FolderRecord] = []
    @Published var groups: [String] = []
    @Published var currentURL: URL? { didSet { if currentURL != oldValue { searchQuery = ""; facetSelections = [:] } } }
    @Published var expandedPaths: Set<String> = []
    @Published var childFolders: [String: [URL]] = [:]
    @Published var history: [URL] = []
    @Published var activeFolder: String?
    @Published var items: [MediaItem] = [] { didSet {
        itemIndex = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        mediaItems = items.filter { !$0.isDirectory }
        directoryCount = items.count - mediaItems.count; videoCount = mediaItems.filter(\.video).count
        itemsRevision += 1
        rebuildDisplay(); scheduleFacets()
    } }
    private(set) var itemIndex: [String: Int] = [:]
    private(set) var mediaItems: [MediaItem] = []
    private(set) var directoryCount = 0
    private(set) var videoCount = 0
    private(set) var itemsRevision = 0
    @Published var displayItems: [MediaItem] = []
    var displayIndex: [String: Int] = [:]
    var displayRevision = 0
    var displayMediaItems: [MediaItem] { displayItems.filter { !$0.isDirectory } }
    @Published var facetsOpen = false { didSet { scheduleFacets() } }
    @Published var facetFields: [MetaField] = (Preferences.defaults.stringArray(forKey: "facetFields") ?? ["taken", "camera", "lens", "keywords"]).compactMap(MetaField.init) { didSet {
        Preferences.defaults.set(facetFields.map(\.rawValue), forKey: "facetFields")
        facetSelections = facetSelections.filter { facetFields.contains($0.key) }; scheduleFacets()
    } }
    @Published var facetSelections: [MetaField: Set<String>] = [:] { didSet { rebuildDisplay(); scheduleFacets() } }
    @Published var facetValues: [MetaField: [FacetValue]] = [:]
    @Published var facetPending = 0
    private var facetWork: DispatchWorkItem?
    func rebuildDisplay() {
        let filtered = items.filter { $0.isDirectory || FacetValue.matches($0, selections: facetSelections) }
        displayIndex = Dictionary(uniqueKeysWithValues: filtered.enumerated().map { ($0.element.id, $0.offset) })
        displayRevision += 1; displayItems = filtered
        setSelection(selectedIDs.intersection(Set(filtered.map(\.id))), primary: selectedID, updateAnchor: false)
    }
    func scheduleFacets() {
        guard facetsOpen || !facetSelections.isEmpty else { return }
        guard facetWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.facetWork = nil
            guard self.facetsOpen || !self.facetSelections.isEmpty else { return }
            if self.facetFields.contains(where: \.needsMetadata) {
                for item in self.mediaItems { self.requestMetadata(item, priority: .low) }
            }
            self.facetPending = self.mediaItems.filter { !$0.metadataLoaded }.count
            var result: [MetaField: [FacetValue]] = [:]
            for field in self.facetFields {
                result[field] = FacetValue.options(self.mediaItems, field: field, selections: self.facetSelections)
            }
            self.facetValues = result
            if !self.facetSelections.isEmpty { self.rebuildDisplay() }
        }
        facetWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func toggleFacet(_ field: MetaField, _ value: String) {
        var values = facetSelections[field] ?? []
        if values.contains(value) { values.remove(value) } else { values.insert(value) }
        facetSelections[field] = values.isEmpty ? nil : values
    }
    @Published var sorting = false
    @Published var selectedID: String? { didSet {
        if !updatingSelection {
            if let selectedID { selectedIDs = Set([selectedID]) } else { selectedIDs = [] }
            selectionAnchor = selectedID
        }
        if selectedID != oldValue { selectionChanged?() }
    } }
    @Published var selectedIDs: Set<String> = []
    var updatingSelection = false
    var selectionAnchor: String?
    @Published var searchQuery = "" { didSet { if searchQuery != oldValue { scheduleBrowserSearch() } } }
    @Published var searchFromMemory = false
    @Published var searchScanned = 0
    @Published var searchSkipped = 0
    var searchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var searchWork: DispatchWorkItem?
    let searchQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .utility; return q }()
    var searchGeneration = UUID()
    var pendingRevealURL: URL?
    @Published var fileOperationBusy = false
    let fileQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q }()
    var cutPaths: Set<String> = []
    var cutPasteboardChange = -1
    var selectionChanged: (() -> Void)?
    var pendingOpenURL: URL?
    @Published var busy = false
    @Published var error: String?
    @Published var sortField: MetaField = .name
    @Published var ascending = true
    @Published var sidebarVisible = true
    let metadataUpdates = MetadataUpdates()
    let preferences = Preferences()
    var openViewer: ((MediaItem) -> Void)?
    var showSettings: (() -> Void)?
    private let scanQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .userInitiated; return q }()
    private let treeQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q }()
    private let sortQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q }()
    private var sortGeneration = UUID()
    private var childRequests: [String: Operation] = [:]
    private var childDates: [String: Date] = [:]
    private var metadataRequests: [String: Operation] = [:]
    private let metadataCache: NSCache<NSString, MetadataValue> = { let c = NSCache<NSString, MetadataValue>(); c.countLimit = 10000; c.totalCostLimit = 16 * 1024 * 1024; return c }()
    private var metadataBatches: [(MediaItem, [MetaField: String])] = []
    private var metadataFlush: DispatchWorkItem?
    private let metaQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 3; q.qualityOfService = .utility; return q }()
    private var generation = UUID()
    private var watcher: DispatchSourceFileSystemObject?
    private var watchRefresh: DispatchWorkItem?
    private var scopedURL: URL?
    private var sortWork: DispatchWorkItem?

    init(restore: Bool = true) {
        if restore, let data = Preferences.defaults.data(forKey: "folders"), let decoded = try? JSONDecoder().decode([FolderRecord].self, from: data) { folders = decoded }
        if restore { groups = Preferences.defaults.stringArray(forKey: "folderGroups") ?? [] }
    }
    var rootFolder: FolderRecord? { folders.first { $0.id == activeFolder } }
    var folder: FolderRecord? {
        guard var record = rootFolder else { return nil }
        if let currentURL { record.path = currentURL.path }
        return record
    }
    var canGoUp: Bool { currentURL != nil && currentURL?.path != "/" }
    func activate(_ item: MediaItem) { if item.isDirectory { navigate(to: item.url) } else { openViewer?(item) } }
    func toggleExpanded(_ url: URL) {
        if expandedPaths.contains(url.path) { expandedPaths.remove(url.path); childRequests[url.path]?.cancel(); childRequests[url.path] = nil }
        else { expandedPaths.insert(url.path); loadChildren(url) }
    }
    func loadChildren(_ url: URL) {
        let path = url.path
        guard childRequests[path] == nil else { return }
        if let date = childDates[path], Date().timeIntervalSince(date) < 5 { return }
        let operation = BlockOperation(); childRequests[path] = operation
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let result = try? DirectoryScan.read(url, operation: operation, directoriesOnly: true)
            DispatchQueue.main.async {
                guard let self, self.childRequests[path] === operation else { return }
                self.childRequests[path] = nil
                guard !operation.isCancelled, let result else { return }
                self.updateChildren(result.directories, at: path)
            }
        }
        treeQueue.addOperation(operation)
    }
    private func updateChildren(_ urls: [URL], at path: String) {
        childDates[path] = Date()
        if childFolders[path] != urls { childFolders[path] = urls }
        if childFolders.count > 256 {
            for key in childDates.keys.sorted(by: { childDates[$0]! < childDates[$1]! }) where !expandedPaths.contains(key) && key != path {
                childFolders[key] = nil; childDates[key] = nil
                if childFolders.count <= 192 { break }
            }
        }
    }
    func navigate(to url: URL, recordHistory: Bool = true) {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        if recordHistory, let currentURL, currentURL != target { history.append(currentURL) }
        searchQuery = ""; currentURL = target; selectedID = nil; items = []
        var ancestor = target.deletingLastPathComponent()
        while let root = rootFolder, ancestor.path == root.path || ancestor.path.hasPrefix(root.path + "/") {
            expandedPaths.insert(ancestor.path); loadChildren(ancestor)
            if ancestor.path == root.path { break }; ancestor.deleteLastPathComponent()
        }
        expandedPaths.insert(target.path)
        watcher?.cancel(); watcher = nil; watchRefresh?.cancel()
        refresh(useSearchCache: true); watch(target)
    }
    func goBack() { if let previous = history.popLast() { navigate(to: previous, recordHistory: false) } }
    func goUp() {
        guard let currentURL, canGoUp else { return }
        let child = currentURL.path, parent = currentURL.deletingLastPathComponent()
        if parent.path == rootFolder?.path || parent.path.hasPrefix((rootFolder?.path ?? "") + "/") { navigate(to: parent) }
        else { add([parent]) }
        selectedID = child
    }
    var selected: MediaItem? { selectedID.flatMap { itemIndex[$0] }.map { items[$0] } }
    var recent: [FolderRecord] { folders.filter { !$0.pinned }.sorted { $0.opened > $1.opened } }
    func persist() {
        if let data = try? JSONEncoder().encode(folders) { Preferences.defaults.set(data, forKey: "folders") }
        Preferences.defaults.set(groups, forKey: "folderGroups")
        Preferences.defaults.set(activeFolder, forKey: "lastFolder")
    }
    func addFolders() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true; panel.prompt = "Hinzufügen"; panel.message = "Ordner zur Seitenleiste hinzufügen"
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func add(_ urls: [URL]) {
        var first: String?
        for url in urls {
            let u = url.resolvingSymlinksInPath().standardizedFileURL
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &directory), directory.boolValue else { continue }
            if let existing = folders.first(where: { $0.path == u.path }) { if first == nil { first = existing.id }; continue }
            let record = FolderRecord(id: UUID().uuidString, path: u.path, bookmark: try? u.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), opened: Date())
            folders.append(record); if first == nil { first = record.id }
        }
        persist(); if let first { selectFolder(first) }
    }
    func selectFolder(_ id: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        watcher?.cancel(); watcher = nil; watchRefresh?.cancel()
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil
        var url = folders[index].url
        if let bookmark = folders[index].bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale) {
                url = resolved; folders[index].path = resolved.path
                if stale { folders[index].bookmark = try? resolved.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
            }
        }
        url = url.resolvingSymlinksInPath().standardizedFileURL; folders[index].path = url.path
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let changed = activeFolder != id || currentURL != url
        activeFolder = id; folders[index].opened = Date(); if changed { selectedID = nil; items = [] }
        history = []; currentURL = url
        expandedPaths.insert(url.path)
        persist(); refresh(useSearchCache: true); watch(url)
    }
    func refreshFileLocations(_ urls: [URL]) {
        for url in urls { BrowserSearch.invalidate(root: url.deletingLastPathComponent()) }
        for parent in Set(urls.map { $0.deletingLastPathComponent().path }) {
            childDates[parent] = nil; childRequests[parent]?.cancel(); childRequests[parent] = nil
            if expandedPaths.contains(parent) { loadChildren(URL(fileURLWithPath: parent)) }
        }
    }
    func cancelLoadingForSearch() {
        generation = UUID(); scanQueue.cancelAllOperations(); metaQueue.cancelAllOperations()
        sortQueue.cancelAllOperations(); sortGeneration = UUID(); sortWork?.cancel(); sortWork = nil
        metadataFlush?.cancel(); metadataFlush = nil; metadataRequests.removeAll(); metadataBatches.removeAll()
        sorting = false
    }
    func refresh(useSearchCache: Bool = false) {
        searchWork?.cancel(); searchWork = nil
        searchGeneration = UUID(); searchQueue.cancelAllOperations()
        guard let folder else { return }
        if !useSearchCache { BrowserSearch.invalidate(root: folder.url) }
        let token = UUID(); generation = token
        scanQueue.cancelAllOperations(); metaQueue.cancelAllOperations(); sortQueue.cancelAllOperations()
        sortGeneration = UUID(); sortWork?.cancel(); sortWork = nil; sorting = false
        metadataRequests.removeAll(); metadataBatches.removeAll(); metadataFlush?.cancel(); metadataFlush = nil
        busy = true; error = nil
        if searchActive { startBrowserSearch(folder.url); return }
        searchScanned = 0; searchSkipped = 0
        let url = folder.url, field = sortField, up = ascending
        childRequests[url.path]?.cancel(); childRequests[url.path] = nil
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            do {
                let result = try DirectoryScan.read(url, operation: operation)
                guard !operation.isCancelled else { return }
                let ordered = ItemSortKey.sorted(result.items.map { ItemSortKey($0, field: field) }, field: field, ascending: up)
                guard !operation.isCancelled else { return }
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    let existing = Dictionary(uniqueKeysWithValues: self.items.map { ($0.id, $0) })
                    self.items = ordered.map { item in
                        if let old = existing[item.id], old.cacheKey == item.cacheKey { return old }; return item
                    }
                    self.updateChildren(result.directories, at: url.path); self.busy = false
                    if let reveal = self.pendingRevealURL {
                        self.pendingRevealURL = nil
                        if self.itemIndex[reveal.path] != nil { self.selectedID = reveal.path }
                    }
                    if self.selectedID.flatMap({ self.itemIndex[$0] }) == nil { self.selectedID = self.items.first?.id }
                    if let pending = self.pendingOpenURL, let index = self.itemIndex[pending.standardizedFileURL.path] {
                        self.pendingOpenURL = nil; self.selectedID = self.items[index].id; self.openViewer?(self.items[index])
                    }
                    if self.sortField.needsMetadata { self.requestSortMetadata() }
                    if field != self.sortField || up != self.ascending || self.sortField.needsMetadata { self.sort() }
                }
            } catch {
                DispatchQueue.main.async { guard let self, self.generation == token else { return }; self.items = []; self.busy = false; self.error = "Der Ordner ist nicht erreichbar oder darf nicht gelesen werden.\n\(error.localizedDescription)" }
            }
        }
        scanQueue.addOperation(operation)
    }
    func requestMetadata(_ item: MediaItem, priority: Operation.QueuePriority = .veryHigh) {
        guard !item.isDirectory, !item.metadataLoaded else { return }
        let key = item.cacheKey
        if let pending = metadataRequests[key] { if priority.rawValue > pending.queuePriority.rawValue { pending.queuePriority = priority }; return }
        if let cached = metadataCache.object(forKey: key as NSString) {
            item.metadata.merge(cached.fields) { _, new in new }; item.metadataLoaded = true; metadataUpdates.changed(); scheduleFacets(); return
        }
        let operation = BlockOperation(); operation.queuePriority = priority; metadataRequests[key] = operation
        let token = generation
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else { return }
            let data = autoreleasepool { MetadataReader.read(item) }
            self.metadataCache.setObject(MetadataValue(data), forKey: key as NSString, cost: data.values.reduce(128) { $0 + $1.utf8.count * 2 })
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async {
                guard self.generation == token, !operation.isCancelled else { return }
                self.metadataRequests[key] = nil
                self.metadataBatches.append((item, data)); self.scheduleMetadataFlush()
            }
        }
        metaQueue.addOperation(operation)
    }
    private func scheduleMetadataFlush() {
        guard metadataFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.metadataFlush = nil
            let batch = self.metadataBatches; self.metadataBatches.removeAll(keepingCapacity: true)
            for (item, data) in batch { item.metadata.merge(data) { _, new in new }; item.metadataLoaded = true }
            self.metadataUpdates.changed(); self.scheduleFacets()
            if self.sortField.needsMetadata { self.deferredSort() }
        }
        metadataFlush = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }
    private func requestSortMetadata() { for item in mediaItems { requestMetadata(item, priority: .low) } }
    private func deferredSort() {
        guard sortWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.sortWork = nil; self?.sort() }; sortWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func sort() {
        let token = UUID(); sortGeneration = token; sortQueue.cancelAllOperations()
        let field = sortField, up = ascending, keys = items.map { ItemSortKey($0, field: sortField) }
        let itemVersion = itemsRevision
        if field.needsMetadata { requestSortMetadata() }
        sorting = true
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let sorted = ItemSortKey.sorted(keys, field: field, ascending: up)
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async {
                guard let self, self.sortGeneration == token else { return }; self.sorting = false
                guard self.itemsRevision == itemVersion else { return }
                if !zip(self.items, sorted).allSatisfy({ $0.id == $1.id }) { self.items = sorted }
            }
        }
        sortQueue.addOperation(operation)
    }
    func setSort(_ field: MetaField, ascending up: Bool? = nil) {
        ascending = up ?? (sortField == field ? !ascending : true); sortField = field; sort()
    }
    func pin(_ folder: FolderRecord, group: String? = nil) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i].pinned = group != nil || !folders[i].pinned; folders[i].group = group; persist()
    }
    func remove(_ folder: FolderRecord) {
        folders.removeAll { $0.id == folder.id }
        if activeFolder == folder.id {
            searchWork?.cancel(); searchWork = nil; searchGeneration = UUID(); searchQueue.cancelAllOperations()
            generation = UUID(); scanQueue.cancelAllOperations(); metaQueue.cancelAllOperations(); sortQueue.cancelAllOperations(); sortGeneration = UUID(); sortWork?.cancel(); sortWork = nil; metadataFlush?.cancel(); metadataFlush = nil; metadataBatches = []; metadataRequests = [:]; watcher?.cancel(); watcher = nil
            scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil
            activeFolder = nil; currentURL = nil; history = []; items = []; selectedID = nil; error = nil; busy = false
        }; persist()
    }
    func createGroup() {
        let alert = NSAlert(); alert.messageText = "Neue Gruppe"; alert.informativeText = "Angepinnte Ordner in einer Gruppe sammeln."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); field.placeholderString = "Gruppenname"
        alert.accessoryView = field; alert.addButton(withTitle: "Anlegen"); alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !groups.contains(name) { groups.append(name); persist() }
        }
    }
    private func watch(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, !self.fileOperationBusy, !self.searchActive else { return }; self.watchRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }; self.watchRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        source.setCancelHandler { close(descriptor) }; source.resume(); watcher = source
    }
}

enum MetadataReader {
    static func read(_ item: MediaItem) -> [MetaField: String] {
        var data = read(item.url, video: item.video)
        if let sidecar = item.sidecar {
            let document = XMPDocument.read(sidecar)
            data.merge(document.fields) { _, xmp in xmp }
            data[.xmpStatus] = item.video ? "XMP-Metadaten; Videobearbeitungen werden nicht angewendet." : document.status
        }
        return data
    }
    static func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let array = value as? [Any] { return array.compactMap { text($0) }.joined(separator: ", ") }
        return String(describing: value)
    }
    static func read(_ url: URL, video: Bool) -> [MetaField: String] {
        if video { return readVideo(url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return [:] }
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        var data: [MetaField: String] = [:]
        func set(_ field: MetaField, _ value: Any?) { if field == .keywords, let values = value as? [String] { data[field] = values.joined(separator: "\n") } else if let t = text(value), !t.isEmpty { data[field] = t } }
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        if let w = properties[kCGImagePropertyPixelWidth as String] as? NSNumber, let h = properties[kCGImagePropertyPixelHeight as String] as? NSNumber {
            data[.dimensions] = (5...8).contains(orientation) ? "\(h) × \(w)" : "\(w) × \(h)"
        }
        set(.taken, exif["DateTimeOriginal"] ?? exif["DateTimeDigitized"] ?? tiff["DateTime"])
        let make = text(tiff["Make"]) ?? "", model = text(tiff["Model"]) ?? ""
        data[.camera] = model.lowercased().hasPrefix(make.lowercased()) ? model : [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        set(.lens, exif["LensModel"]); set(.iso, exif["ISOSpeedRatings"])
        if let n = exif["FNumber"] as? NSNumber { data[.aperture] = "ƒ/\(n)" }
        if let n = exif["ExposureTime"] as? NSNumber { let v = n.doubleValue; data[.shutter] = v > 0 && v < 1 ? "1/\(Int((1 / v).rounded())) s" : "\(n) s" }
        if let n = exif["FocalLength"] as? NSNumber { data[.focalLength] = "\(n) mm" }
        if let n = exif["ExposureBiasValue"] as? NSNumber { data[.exposureBias] = "\(n) EV" }
        if let n = exif["Flash"] as? NSNumber { data[.flash] = n.intValue & 1 == 1 ? "Ausgelöst" : "Nicht ausgelöst" }
        set(.colorSpace, properties[kCGImagePropertyProfileName as String]); set(.dpi, properties[kCGImagePropertyDPIWidth as String])
        if let lat = gps["Latitude"] as? NSNumber, let lon = gps["Longitude"] as? NSNumber { data[.gps] = String(format: "%.6f° %@, %.6f° %@", lat.doubleValue, text(gps["LatitudeRef"]) ?? "", lon.doubleValue, text(gps["LongitudeRef"]) ?? "") }
        let mappings: [(MetaField, String)] = [(.title,"ObjectName"),(.caption,"Caption/Abstract"),(.keywords,"Keywords"),(.creator,"Byline"),(.copyright,"CopyrightNotice"),(.city,"City"),(.region,"Province/State"),(.country,"Country/PrimaryLocationName"),(.credit,"Credit"),(.source,"Source")]
        for (field, key) in mappings { set(field, iptc[key]) }
        if data[.creator] == nil { set(.creator, tiff["Artist"]) }
        if data[.copyright] == nil { set(.copyright, tiff["Copyright"]) }
        if data[.caption] == nil { set(.caption, tiff["ImageDescription"]) }
        // ImageIO also exposes embedded XMP; use it where legacy IPTC is absent.
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            let xmp: [(MetaField, String)] = [(.title,"dc:title"),(.caption,"dc:description"),(.creator,"dc:creator"),(.copyright,"dc:rights"),(.keywords,"dc:subject"),(.city,"photoshop:City"),(.region,"photoshop:State"),(.country,"photoshop:Country"),(.credit,"photoshop:Credit"),(.source,"photoshop:Source")]
            for (field, path) in xmp where data[field] == nil {
                if let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString), let value = CGImageMetadataTagCopyValue(tag) {
                    if let dictionary = value as? [String: Any] { set(field, dictionary["x-default"] ?? dictionary.values.first) }
                    else { set(field, value) }
                }
            }
        }
        return data
    }
    static func readVideo(_ url: URL) -> [MetaField: String] {
        let asset = AVURLAsset(url: url); var result: [MetaField: String] = [:]
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isFinite && seconds >= 0 { result[.duration] = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
        if let track = asset.tracks(withMediaType: .video).first {
            let s = track.naturalSize.applying(track.preferredTransform); result[.dimensions] = "\(Int(abs(s.width))) × \(Int(abs(s.height)))"
        }
        for meta in asset.commonMetadata {
            guard let key = meta.commonKey, let value = meta.stringValue else { continue }
            switch key {
            case .commonKeyTitle: result[.title] = value
            case .commonKeyDescription: result[.caption] = value
            case .commonKeyCreator, .commonKeyArtist: result[.creator] = value
            case .commonKeyCopyrights: result[.copyright] = value
            case .commonKeyCreationDate: result[.taken] = value
            case .commonKeyModel: result[.camera] = value
            default: break
            }
        }; return result
    }
}

final class ThumbnailRequest {
    private var cancelAction: (() -> Void)?
    init(_ cancel: @escaping () -> Void) { cancelAction = cancel }
    func cancel() { cancelAction?(); cancelAction = nil }
}

final class ThumbnailStore {
    static let shared = ThumbnailStore()
    private let cache = NSCache<NSString, NSImage>()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 3; q.qualityOfService = .userInitiated; return q }()
    private final class Job {
        let operation = BlockOperation()
        var listeners: [UUID: (NSImage?) -> Void] = [:]
    }
    // Jobs and subscriptions are confined to the main thread; NSCache is thread-safe.
    private var jobs: [String: Job] = [:]
    init() { cache.totalCostLimit = 96 * 1024 * 1024 }
    static func bucket(_ pixels: Int) -> Int { pixels <= 256 ? 256 : pixels <= 512 ? 512 : 840 }
    static func decode(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    func cached(_ item: MediaItem) -> NSImage? {
        for pixels in [840, 512, 256] { if let image = cache.object(forKey: (item.cacheKey + "-\(pixels)") as NSString) { return image } }; return nil
    }
    func load(_ item: MediaItem, maxPixel: Int = 512, completion: @escaping (NSImage?) -> Void) -> ThumbnailRequest? {
        let pixels = Self.bucket(maxPixel), key = item.cacheKey + "-\(Self.bucket(maxPixel))"
        for size in [256, 512, 840] where size >= pixels {
            if let image = cache.object(forKey: (item.cacheKey + "-\(size)") as NSString) { completion(image); return nil }
        }
        let id = UUID()
        let ticket = ThumbnailRequest { [weak self] in
            guard let self, let job = self.jobs[key] else { return }; job.listeners[id] = nil
            if job.listeners.isEmpty { job.operation.cancel(); self.jobs[key] = nil }
        }
        if let job = jobs[key] { job.listeners[id] = completion; return ticket }
        let job = Job(); job.listeners[id] = completion; jobs[key] = job
        job.operation.addExecutionBlock { [weak self, weak job] in
            guard let self, let job, !job.operation.isCancelled else { return }
            let image: NSImage? = autoreleasepool {
                if item.video {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.url)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: pixels, height: pixels)
                    if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) { return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }; return nil
                }; let rendered = ImageRenderer.render(item, maxPixel: pixels)
                if let warning = rendered?.warning { DispatchQueue.main.async { item.renderWarning = warning } }
                return rendered?.image
            }
            if let image { self.cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4)) }
            DispatchQueue.main.async {
                guard self.jobs[key] === job else { return }; self.jobs[key] = nil
                if !job.operation.isCancelled { for callback in job.listeners.values { callback(image) } }
            }
        }
        queue.addOperation(job.operation); return ticket
    }
}
