import AppKit
import SwiftUI

struct FacetValue: Identifiable {
    let id: String
    let count: Int
    static let missing = "Ohne Angabe"
    static func values(_ item: MediaItem, field: MetaField) -> Set<String> {
        let raw = (item.metadata[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [missing] }
        if field == .keywords { return Set(raw.components(separatedBy: "\n").filter { !$0.isEmpty }) }
        if field == .taken {
            let day = String(raw.prefix(10)).replacingOccurrences(of: ":", with: "-")
            return [day]
        }
        return [raw]
    }
    static func options(_ items: [MediaItem], field: MetaField, selections: [MetaField: Set<String>]) -> [FacetValue] {
        let otherFilters = selections.filter { $0.key != field }
        var counts: [String: Int] = [:]
        for item in items where !item.isDirectory && (!field.needsMetadata || item.metadataLoaded) && matches(item, selections: otherFilters) {
            for value in values(item, field: field) { counts[value, default: 0] += 1 }
        }
        return counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { FacetValue(id: $0, count: counts[$0]!) }
    }
    static func matches(_ item: MediaItem, selections: [MetaField: Set<String>]) -> Bool {
        selections.allSatisfy { field, selected in
            selected.isEmpty || ((!field.needsMetadata || item.metadataLoaded) && selected.isSubset(of: values(item, field: field)))
        }
    }
}

struct FacetBar: View {
    @ObservedObject var model: AppModel
    @AtelierState(wrappedValue: Preferences.defaults.dictionary(forKey: "facetWidths") as? [String: Double] ?? [:]) private var widths: [String: Double]
    @AtelierState(wrappedValue: Preferences.defaults.object(forKey: "facetHeight") as? Double ?? 180) private var height: Double
    @AtelierState(wrappedValue: nil) private var dragWidth: Double?
    @AtelierState(wrappedValue: nil) private var dragHeight: Double?
    private func width(_ field: MetaField, available: CGFloat) -> CGFloat {
        if let saved = widths[field.rawValue] { return saved }
        let fixed = model.facetFields.compactMap { widths[$0.rawValue] }.reduce(0, +)
        let automatic = model.facetFields.filter { widths[$0.rawValue] == nil }.count
        return max(100, (available - CGFloat(model.facetFields.count * 6) - fixed) / CGFloat(max(1, automatic)))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.facetsOpen.toggle() } label: {
                    Label("Sortieren & Filtern", systemImage: model.facetsOpen ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain)
                if !model.facetSelections.isEmpty {
                    Text("\(model.displayMediaItems.count) von \(model.mediaItems.count) Dateien").foregroundStyle(.secondary)
                    Button("Zurücksetzen") { model.facetSelections = [:] }
                }
                Spacer()
                if model.facetsOpen {
                    if model.facetPending > 0 { ProgressView().controlSize(.mini); Text("\(model.facetPending) Metadaten …").foregroundStyle(.secondary) }
                    Menu {
                        Button("Spalten gleichmäßig verteilen") { widths = [:]; Preferences.defaults.removeObject(forKey: "facetWidths") }
                        Divider()
                        ForEach(MetaField.allCases) { field in
                            Button {
                                if model.facetFields.contains(field) { model.facetFields.removeAll { $0 == field } }
                                else { model.facetFields.append(field) }
                            } label: {
                                if model.facetFields.contains(field) { Label(field.label, systemImage: "checkmark") } else { Text(field.label) }
                            }
                        }
                    } label: { Label("Spalten", systemImage: "tablecells") }.fixedSize()
                }
            }.font(.system(size: 12)).padding(.horizontal, 18).frame(height: 36)
            if model.facetsOpen {
                GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(model.facetFields) { field in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(field == .taken ? "Datum" : field.label).fontWeight(.semibold)
                                    Spacer()
                                    Button { model.setSort(field) } label: { Image(systemName: model.sortField == field ? (model.ascending ? "arrow.up" : "arrow.down") : "arrow.up.arrow.down") }.buttonStyle(.plain).help("Nach \(field.label) sortieren")
                                }
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        Button("Alle") { model.facetSelections[field] = nil }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.vertical, 3)
                                        ForEach(model.facetValues[field] ?? []) { value in
                                            Button { model.toggleFacet(field, value.id) } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: model.facetSelections[field]?.contains(value.id) == true ? "checkmark.square.fill" : "square")
                                                    Text(value.id).lineLimit(1).truncationMode(.middle)
                                                    Spacer(minLength: 2); Text("\(value.count)").foregroundStyle(.secondary)
                                                }.padding(.vertical, 3).contentShape(Rectangle())
                                            }.buttonStyle(.plain).help(value.id)
                                        }
                                    }
                                }.frame(maxHeight: .infinity)
                            }.font(.system(size: 12)).padding(.horizontal, 12).frame(width: width(field, available: geometry.size.width))
                            Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 6)
                                .contentShape(Rectangle()).help("Ziehen, um die Spaltenbreite anzupassen")
                                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                                .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                                    if dragWidth == nil { dragWidth = width(field, available: geometry.size.width) }
                                    widths[field.rawValue] = max(100, min(1600, dragWidth! + value.translation.width))
                                }.onEnded { _ in
                                    dragWidth = nil; Preferences.defaults.set(widths, forKey: "facetWidths")
                                })
                        }
                    }.padding(.vertical, 8)
                }
                }.frame(height: height)
                Text("Alle ausgewählten Kriterien gelten gemeinsam (UND) · Ordner bleiben zur Navigation sichtbar")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 7)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 7)
                    .overlay(Capsule().fill(Color.secondary).frame(width: 34, height: 2))
                    .contentShape(Rectangle()).help("Ziehen, um die Höhe der Filterleiste anzupassen")
                    .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        if dragHeight == nil { dragHeight = height }
                        height = max(100, min(500, dragHeight! + value.translation.height))
                    }.onEnded { _ in dragHeight = nil; Preferences.defaults.set(height, forKey: "facetHeight") })
            }
        }.background(.bar)
    }
}

struct FolderHit: Identifiable {
    var id: String { url.path }
    let root: FolderRecord
    let url: URL
}
final class PinnedSearch: ObservableObject {
    @Published var query = ""
    @Published var group = ""
    @Published var searchPath = false
    @Published var hits: [FolderHit] = []
    @Published var busy = false
    @Published var inaccessible = false
    var active: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !group.isEmpty }
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .utility; return q }()
    private var token = UUID()
    private var delay: DispatchWorkItem?
    func search(_ roots: [FolderRecord]) {
        delay?.cancel(); queue.cancelAllOperations(); token = UUID()
        hits = []; inaccessible = false; busy = active
        guard active else { return }
        let token = token, query = query.trimmingCharacters(in: .whitespacesAndNewlines), group = group, searchPath = searchPath
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == token else { return }
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self, weak operation] in
                guard let operation, !operation.isCancelled else { return }
                var hits: [FolderHit] = [], visited: Set<String> = [], failed = false
                let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
                func add(_ url: URL, root: FolderRecord) {
                    let haystack = searchPath ? url.path : url.lastPathComponent
                    if (query.isEmpty || haystack.localizedStandardContains(query)) && visited.insert(url.path).inserted { hits.append(FolderHit(root: root, url: url)) }
                }
                for root in roots where root.pinned && (group.isEmpty || root.group == group) {
                    if operation.isCancelled { return }
                    add(root.url, root: root)
                    guard let enumerator = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failed = true; return true }) else { failed = true; continue }
                    for case let url as URL in enumerator {
                        if operation.isCancelled { return }
                        autoreleasepool {
                            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { failed = true; return }
                            if values.isSymbolicLink == true || values.isPackage == true { enumerator.skipDescendants(); return }
                            if values.isDirectory == true { add(url, root: root) }
                        }
                    }
                }
                hits.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
                let result = hits, partial = failed
                DispatchQueue.main.async { guard let self, self.token == token, !operation.isCancelled else { return }; self.hits = result; self.busy = false; self.inaccessible = partial }
            }
            self.queue.addOperation(operation)
        }
        delay = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
