import AppKit

// Each operation owns its MediaItems until delivery; no background mutations of
// objects already observed by SwiftUI. Cancellation is checked between files.
// Value snapshots keep the index independent of mutable, published UI objects.
private struct SearchRecord {
    let url: URL
    let video: Bool
    let bytes: Int64
    let modified: Date
    let metadata: [MetaField: String]
    let sidecar: XMPReference?
    let text: String
    let cost: Int
    init(_ item: MediaItem) {
        url = item.url; video = item.video; sidecar = item.sidecar; metadata = item.metadata
        bytes = item.bytes; modified = item.modified
        text = BrowserSearch.searchText(item)
        cost = 512 + url.path.utf8.count * 2 + text.utf8.count * 2 + metadata.values.reduce(0) { $0 + $1.utf8.count * 2 }
    }
    func makeItem() -> MediaItem {
        return MediaItem(cachedURL: url, bytes: bytes, modified: modified, video: video, metadata: metadata, sidecar: sidecar)
    }
}

private final class SearchIndexStore {
    static let shared = SearchIndexStore()
    static let limit = 96 * 1024 * 1024
    private let lock = NSLock()
    private var roots: [String: [SearchRecord]] = [:]
    private var costs: [String: Int] = [:]
    private var recent: [String] = []
    private var epoch = 0
    func lookup(_ path: String) -> ([SearchRecord]?, Int) {
        lock.lock(); defer { lock.unlock() }
        if roots[path] != nil { recent.removeAll { $0 == path }; recent.append(path) }
        return (roots[path], epoch)
    }
    func save(_ records: [SearchRecord], at path: String, cost: Int, generation: Int) {
        lock.lock(); defer { lock.unlock() }
        guard generation == epoch, cost <= Self.limit else { return }
        roots[path] = records; costs[path] = cost
        recent.removeAll { $0 == path }; recent.append(path)
        while recent.count > 4 || costs.values.reduce(0, +) > Self.limit {
            let oldest = recent.removeFirst(); roots[oldest] = nil; costs[oldest] = nil
        }
    }
    func invalidate(_ path: String?) {
        lock.lock(); defer { lock.unlock() }; epoch += 1
        let affected = recent.filter { root in
            guard let path else { return true }
            return root == path || root == "/" || path == "/" || root.hasPrefix(path + "/") || path.hasPrefix(root + "/")
        }
        for root in affected { roots[root] = nil; costs[root] = nil }
        recent.removeAll { affected.contains($0) }
    }
}

enum BrowserSearch {
    private static let cache: NSCache<NSString, MetadataValue> = {
        let value = NSCache<NSString, MetadataValue>()
        value.countLimit = 10000; value.totalCostLimit = 24 * 1024 * 1024
        return value
    }()
    static func terms(_ query: String) -> [String] {
        query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    static func searchText(_ item: MediaItem) -> String {
        return ([item.url.lastPathComponent] + Array(item.metadata.values)).joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
    static func matches(_ item: MediaItem, terms: [String]) -> Bool {
        let text = searchText(item)
        return terms.allSatisfy { text.contains($0) }
    }
    static func invalidate(root: URL? = nil) {
        SearchIndexStore.shared.invalidate(root?.standardizedFileURL.path)
        cache.removeAllObjects()
    }
    static func scan(root: URL, query: String, operation: Operation,
                     onCacheHit: () -> Void = {},
                     deliver: @escaping ([MediaItem], Int, Int, Bool) -> Void) {
        let words = terms(query)
        let path = root.standardizedFileURL.path
        let (cached, epoch) = SearchIndexStore.shared.lookup(path)
        if let cached {
            guard !operation.isCancelled else { return }
            onCacheHit()
            var batch: [MediaItem] = [], scanned = 0
            var lastDelivery = Date()
            for record in cached {
                if operation.isCancelled { return }
                scanned += 1
                if words.allSatisfy({ record.text.contains($0) }) { batch.append(record.makeItem()) }
                if Date().timeIntervalSince(lastDelivery) >= 0.25 {
                    deliver(batch, scanned, 0, false); batch.removeAll(keepingCapacity: true); lastDelivery = Date()
                }
            }
            if !operation.isCancelled { deliver(batch, scanned, 0, true) }
            return
        }
        var records: [SearchRecord] = [], indexCost = 0, retainIndex = true
        var stack = [root], visited = Set<String>(), batch: [MediaItem] = []
        var scanned = 0, skipped = 0, lastDelivery = Date()
        while let directory = stack.popLast() {
            if operation.isCancelled { return }
            // Do not follow symlinks out of the selected tree or into cycles.
            guard visited.insert(directory.standardizedFileURL.path).inserted else { continue }
            do {
                let result = try DirectoryScan.read(directory, operation: operation)
                for child in result.directories {
                    if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true { stack.append(child) }
                }
                for item in result.items where !item.isDirectory {
                    if operation.isCancelled { return }
                    autoreleasepool {
                        if (try? item.url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return }
                        let key = item.cacheKey as NSString
                        let fields: [MetaField: String]
                        if let existing = cache.object(forKey: key) { fields = existing.fields }
                        else {
                            fields = MetadataReader.read(item)
                            cache.setObject(MetadataValue(fields), forKey: key, cost: fields.values.reduce(128) { $0 + $1.utf8.count * 2 })
                        }
                        item.metadata.merge(fields) { _, new in new }; item.metadataLoaded = true
                        scanned += 1
                        let record = SearchRecord(item)
                        if retainIndex {
                            indexCost += record.cost
                            if indexCost <= SearchIndexStore.limit { records.append(record) }
                            else { records.removeAll(); retainIndex = false }
                        }
                        if words.allSatisfy({ record.text.contains($0) }) { batch.append(item) }
                    }
                    if Date().timeIntervalSince(lastDelivery) >= 0.25 {
                        deliver(batch, scanned, skipped, false); batch.removeAll(keepingCapacity: true); lastDelivery = Date()
                    }
                }
            } catch { skipped += 1 }
        }
        if !operation.isCancelled {
            // Never reuse an incomplete traversal or a tree with inaccessible folders.
            if retainIndex && skipped == 0 { SearchIndexStore.shared.save(records, at: path, cost: indexCost, generation: epoch) }
            deliver(batch, scanned, skipped, true)
        }
    }
}

extension AppModel {
    func scheduleBrowserSearch() {
        cancelLoadingForSearch()
        searchWork?.cancel(); searchQueue.cancelAllOperations(); searchGeneration = UUID()
        let work = DispatchWorkItem { [weak self] in self?.refresh(useSearchCache: true) }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func startBrowserSearch(_ root: URL) {
        let token = UUID(); searchGeneration = token
        let query = searchQuery
        items = []; selectedID = nil; searchScanned = 0; searchSkipped = 0; searchFromMemory = false
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            BrowserSearch.scan(root: root, query: query, operation: operation, onCacheHit: {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.searchGeneration == token, !operation.isCancelled else { return }
                    self.searchFromMemory = true
                }
            }) { batch, scanned, skipped, complete in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.searchGeneration == token, !operation.isCancelled,
                          self.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path, self.searchQuery == query else { return }
                    self.searchScanned = scanned; self.searchSkipped = skipped
                    if !batch.isEmpty { self.items.append(contentsOf: batch) }
                    if complete {
                        self.busy = false; self.sort()
                        if self.selectedID == nil { self.selectedID = self.displayItems.first?.id }
                    }
                }
            }
        }
        searchQueue.addOperation(operation)
    }
    func revealContainingFolder(_ item: MediaItem) {
        pendingRevealURL = item.url
        navigate(to: item.url.deletingLastPathComponent())
    }
    var selectedItems: [MediaItem] { displayItems.filter { selectedIDs.contains($0.id) } }
    func setSelection(_ ids: Set<String>, primary: String?, updateAnchor: Bool = true) {
        let valid = ids.intersection(Set(displayIndex.keys))
        updatingSelection = true
        if selectedIDs != valid { selectedIDs = valid }
        let lead = primary.flatMap { valid.contains($0) ? $0 : nil } ?? displayItems.first(where: { valid.contains($0.id) })?.id
        if selectedID != lead { selectedID = lead }
        updatingSelection = false
        if updateAnchor { selectionAnchor = lead }
    }
    func select(_ item: MediaItem, modifiers: NSEvent.ModifierFlags = []) {
        if modifiers.contains(.shift), let anchor = selectionAnchor, let a = displayIndex[anchor], let b = displayIndex[item.id] {
            let range = Set(displayItems[min(a,b)...max(a,b)].map(\.id))
            setSelection(modifiers.contains(.command) ? selectedIDs.union(range) : range, primary: item.id, updateAnchor: false)
        } else if modifiers.contains(.command) {
            var ids = selectedIDs
            if ids.contains(item.id) { ids.remove(item.id) } else { ids.insert(item.id) }
            setSelection(ids, primary: item.id)
        } else { setSelection([item.id], primary: item.id) }
    }
    func selectAllFiles() { setSelection(Set(displayItems.map(\.id)), primary: selectedID) }
    func prepareContext(_ item: MediaItem) {
        if !selectedIDs.contains(item.id) { setSelection([item.id], primary: item.id) }
    }
}
